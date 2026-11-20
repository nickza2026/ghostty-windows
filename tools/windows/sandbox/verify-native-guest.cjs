'use strict';
// One owned disposable guest only. Never imports or inspects a live package.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto'), net = require('node:net'), assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { inventory, sha, real, repo } = require('./build-native-package.cjs');
const cli = require('./runtime-cli.cjs'), storage = require('./storage-policy.cjs');
const { sha512crypt } = require('./guest-password-hash.cjs');
const { ssh, stop, fixturePassword } = require('./verify-node-native.cjs');
const { inputScript } = require('./native-window-input.cjs');
const delay = ms => new Promise(r => setTimeout(r, ms));
const json = f => JSON.parse(fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, ''));
async function freePort() { return new Promise((resolve, reject) => { const s = net.createServer(); s.once('error', reject); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => p === 18787 ? freePort().then(resolve, reject) : resolve(p)); }); }); }
function validateResume(previous, factory, profile) {
  assert(previous.schema === 1 && previous.syntheticOnly === true && previous.passed === false && previous.preconfiguredSyntheticSetupOnly === true);
  assert(previous.root === factory.testRoot && previous.factory === factory.root && typeof previous.finished === 'string' && Number.isFinite(Date.parse(previous.finished)));
  assert(Number.isSafeInteger(previous.hostPort) && previous.hostPort >= 1024 && previous.hostPort <= 65535 && previous.hostPort !== 18787);
  assert.deepEqual(profile, { schema: 1, profile: 'node', ports: [{ hostPort: previous.hostPort, guestPort: 8787 }] });
}
async function publicInventory(root) {
  const files = [];
  async function walk(dir) {
    real(dir);
    for (const name of fs.readdirSync(dir)) {
      if (dir === root && name === 'Data') continue;
      const file = path.join(dir, name), stat = fs.lstatSync(file);
      assert(!stat.isSymbolicLink());
      if (stat.isDirectory()) await walk(file);
      else { assert(stat.isFile()); files.push({ name: path.relative(root, file).replaceAll('\\', '/'), bytes: stat.size, sha256: await sha(file) }); }
    }
  }
  await walk(root); return files.sort((a, b) => a.name.localeCompare(b.name));
}
async function verify(receiptFile, resumeFile) {
  receiptFile = path.resolve(receiptFile || '');
  if (!receiptFile.startsWith(path.join(repo, 'zig-out') + path.sep)) throw Error('Owned native factory receipt required');
  real(receiptFile); const factory = json(receiptFile), root = factory.testRoot, out = path.dirname(receiptFile);
  assert(factory.passed && factory.archiveReextractVerified && factory.dataIncluded === false);
  assert.equal(root, path.join(out, 'archive-check/Sandbox-Native-Preview'));
  let previous;
  if (resumeFile) {
    resumeFile = path.resolve(resumeFile);
    assert(path.dirname(resumeFile) === out && /^native-guest-[a-f0-9-]+\.json$/.test(path.basename(resumeFile)));
    real(resumeFile); previous = json(resumeFile);
    validateResume(previous, factory, json(path.join(root, 'guest-profile.json')));
    assert.equal(await cli.existing(root), null, 'resume requires no active manager');
    const omitProfile = list => list.filter(file => file.name !== 'guest-profile.json');
    assert.deepEqual(omitProfile(await publicInventory(root)), omitProfile(factory.files), 'resume must not change public payload');
    const boots = fs.readdirSync(path.join(root, 'Data')).filter(name => /^boot-[a-f0-9]{32}\.json$/.test(name)).map(name => path.join(root, 'Data', name)).sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
    assert(boots.length && fs.statSync(boots[0]).size < 8192); real(boots[0]);
    const lastBoot = json(boots[0]);
    assert(lastBoot.stage === 'runtime' && lastBoot.ok === false && lastBoot.qemuExited === true && /node-download TimeoutError/.test(lastBoot.error), 'resume only this observed official Node download timeout');
    assert(fs.statSync(boots[0]).mtimeMs <= Date.parse(previous.finished) + 2000, 'resume receipt must describe latest boot');
  } else {
    assert(!fs.existsSync(path.join(root, 'Data')), 'distinct reextract must be unconfigured');
    assert.deepEqual(await inventory(root), factory.files, 'test reextract must match verified factory before setup');
  }
  assert.equal(await sha(factory.archive), factory.archiveSha256);
  const requestId = crypto.randomUUID();
  const report = { schema: 1, requestId, root, factory: factory.root, syntheticOnly: true, passed: false, stages: [], firstUseWizardTested: false, ...(previous ? { resumedAfterNodeDownloadTimeout: path.basename(resumeFile), dataReset: false } : {}) };
  const resultFile = path.join(out, 'native-guest-' + requestId + '.json');
  if (fs.existsSync(resultFile)) throw Error('Do not reuse a previous guest test request');
  const save = () => fs.writeFileSync(resultFile, JSON.stringify(report, null, 2)); save(); console.log('NATIVE_GUEST_RECEIPT=' + resultFile);
  const temp = path.join(out, 'test-temp-' + requestId); fs.mkdirSync(temp);
  const psEnv = { SystemRoot: process.env.SystemRoot, ProgramData: process.env.ProgramData, TEMP: temp, TMP: temp, PATH: path.join(process.env.SystemRoot, 'System32') };
  async function ps(script, timeout = 30000) {
    // HWND SendMessage waits for the native UI thread. Keep this event loop
    // free to drain that UI's debug pipes while the diagnostic runs.
    const child = spawn(path.join(psEnv.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'), ['-NoLogo', '-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand', Buffer.from("$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';\n" + script, 'utf16le').toString('base64')], { env: psEnv, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '', stderr = '', failure = '';
    for (const [stream, target] of [[child.stdout, 'stdout'], [child.stderr, 'stderr']]) {
      stream.setEncoding('utf8');
      stream.on('data', text => {
        if (target === 'stdout') stdout += text; else stderr += text;
        if (stdout.length + stderr.length > 1024 * 1024) { failure = 'DIAGNOSTIC_OUTPUT_LIMIT'; child.kill(); }
      });
    }
    const timer = setTimeout(() => { failure = 'ETIMEDOUT'; child.kill(); }, timeout);
    let code;
    try {
      code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); });
    } finally { clearTimeout(timer); }
    if (failure || code !== 0) {
      const detail = [failure, stderr, stdout].filter(Boolean).join('\n').slice(0, 6000);
      fs.writeFileSync(path.join(temp, 'powershell-failure-' + crypto.randomUUID() + '.log'), detail);
      throw Error('Owned diagnostic PowerShell operation failed: ' + detail.slice(0, 1600));
    }
    return stdout.trim().replace(/^\uFEFF/, '');
  }
  async function memory() { const m = JSON.parse(await ps('$m=Get-CimInstance Win32_OperatingSystem; @{freeCommitKiB=$m.FreeVirtualMemory;freePhysicalKiB=$m.FreePhysicalMemory}|ConvertTo-Json -Compress')); report.lastMemory = m; save(); if (m.freeCommitKiB < 6 * 1024 * 1024 || m.freePhysicalKiB < 4 * 1024 * 1024) throw Error('Insufficient memory headroom for one 3072 MiB disposable guest'); return m; }
  async function input(pid, command) {
    return JSON.parse(await ps(inputScript(pid, command)));
  }
  const owner = json(path.join(root, 'sandbox-owned.json')); assert.equal(owner.nonce, factory.nonce);
  async function ownedStatus(expectedNonce) {
    const until = Date.now() + 12000;
    while (true) {
      try {
        const found = await cli.existing(root);
        if (found && expectedNonce && found.state.managerNonce !== expectedNonce) throw Error('Owned manager changed; no cleanup');
        return found;
      } catch (error) {
        if (!error.message.startsWith('Stale/unreachable manager;') || Date.now() >= until) throw error;
        await delay(500);
      }
    }
  }
  let active, native;
  try {
    report.initialMemory = await memory(); save();
    const port = previous ? previous.hostPort : await freePort(); assert(port >= 1024 && port <= 65535 && port !== 18787);
    if (!previous) {
      fs.writeFileSync(path.join(root, 'guest-profile.json'), JSON.stringify({ schema: 1, profile: 'node', ports: [{ hostPort: port, guestPort: 8787 }] }));
      storage.prepare(root);
      fs.writeFileSync(path.join(root, 'Data/guest-setup.json'), JSON.stringify({ schema: 1, rootId: owner.nonce, passwordHash: sha512crypt(Buffer.from(fixturePassword), 'NativePreview26', 5000) }), { mode: 0o600 });
    } else {
      assert(require('./guest-config.cjs').passwordHash(root), 'Missing owned synthetic setup');
      const encoded = Buffer.from(root, 'utf8').toString('base64');
      await ps(`$root=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encoded}'));$prefix=$root+'\\';$active=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)});if($active.Count){throw 'Owned package process still active'};$f=[IO.File]::Open((Join-Path $root 'Data/guest.qcow2'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);$f.Dispose()`);
    }
    report.preconfiguredSyntheticSetupOnly = true; report.hostPort = port; save();
    const persist = crypto.randomBytes(16).toString('hex');
    for (const phase of ['cold-start', 'restart']) {
      await memory(); assert.equal(await cli.existing(root), null, 'native must cause cold manager start');
      const item = { phase, requestNonce: crypto.randomUUID(), passed: false }; report.stages.push(item); save();
      const logFile = path.join(out, 'native-' + requestId + '-' + phase + '.log');
      const log = fs.createWriteStream(logFile); const drained = new Promise((resolve, reject) => { log.once('finish', resolve); log.once('error', reject); });
      native = spawn(path.join(root, 'Sandbox.exe'), [], { cwd: out, env: { SystemRoot: psEnv.SystemRoot, ProgramData: psEnv.ProgramData, LOCALTERM_SANDBOX_OFFSCREEN: '1' }, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
      item.nativePid = native.pid; let ended = false, exitCode, spawnError;
      native.stdout.pipe(log, { end: false }); native.stderr.pipe(log, { end: false });
      const exited = new Promise(resolve => { native.once('error', e => { spawnError = e.code; }); native.once('close', code => { ended = true; exitCode = code; log.end(); resolve(); }); });
      const until = Date.now() + 20 * 60 * 1000;
      while (Date.now() < until) {
        if (ended) throw Error('Native ended before owned manager readiness');
        const found = await cli.existing(root);
        if (found) { active = found.state.managerNonce; if (found.answer.phase === 'ready') break; if (found.answer.phase !== 'booting') throw Error('Owned manager failed readiness'); }
        await delay(500);
      }
      const ready = await cli.existing(root); if (!ready || ready.answer.phase !== 'ready') throw Error('Owned native cold-start readiness deadline');
      active = ready.state.managerNonce; item.coldStartCausedByNative = true; save();
      ssh(root, ['-T', 'portable-sandbox', 'true']);
      const proofCode = `const fs=require('fs'),a=require('assert/strict');const p={uid:process.getuid(),home:process.env.HOME,cwd:process.cwd(),node:process.version,inputTTY:process.stdin.isTTY,outputTTY:process.stdout.isTTY,columns:process.stdout.columns,rows:process.stdout.rows,nonce:${JSON.stringify(owner.nonce)}};a.equal(p.uid,1000);a.equal(p.home,'/home/sandbox');a.equal(p.cwd,'/home/sandbox/workspaces');a.equal(p.node,'v24.22.1');a(p.inputTTY&&p.outputTTY&&p.columns>0&&p.rows>0);const f=p.home+'/native-preview-persist';${phase === 'cold-start' ? `fs.writeFileSync(f,${JSON.stringify(persist)});` : `a.equal(fs.readFileSync(f,'utf8'),${JSON.stringify(persist)});`}fs.writeFileSync(p.home+'/native-preview-proof.json',JSON.stringify(p));`;
      const command = `node -e "eval(Buffer.from('${Buffer.from(proofCode).toString('base64')}','base64').toString())" && printf '\\033[31mLOCALTERM_SANDBOX_%s_%s \\340\\271\\204\\340\\270\\227\\340\\270\\242\\033[0m\\n' NATIVE ${owner.nonce}`;
      assert(!command.includes('LOCALTERM_SANDBOX_NATIVE_' + owner.nonce), 'full marker must not be command echo');
      item.input = await input(native.pid, command); save();
      const paintedUntil = Date.now() + 45000;
      while (Date.now() < paintedUntil && !fs.readFileSync(logFile, 'utf8').includes('sandbox native painted marker=LOCALTERM_SANDBOX_NATIVE_' + owner.nonce + ' thai=true')) { if (ended) throw Error('Native ended before fresh painted marker'); await delay(100); }
      if (!fs.readFileSync(logFile, 'utf8').includes('sandbox native painted marker=LOCALTERM_SANDBOX_NATIVE_' + owner.nonce + ' thai=true')) throw Error('Fresh Linux PTY parsed/painted marker deadline');
      item.guest = JSON.parse(ssh(root, ['-T', 'portable-sandbox', 'cat /home/sandbox/native-preview-proof.json']).trim());
      assert.equal(item.guest.nonce, owner.nonce); item.persistence = phase === 'restart'; save();
      await input(native.pid, 'exit');
      const endUntil = Date.now() + 30000; while (!ended && Date.now() < endUntil) await delay(100);
      if (!ended) throw Error('Native did not naturally disconnect'); await exited; await drained;
      const text = fs.readFileSync(logFile, 'utf8');
      assert.equal(spawnError, undefined); assert.equal(exitCode, 0);
      assert(/sandbox native diagnostic frames=[1-9]\d* paints=[1-9]\d* marker_painted=true natural_exit=true renderer_failed=false/.test(text));
      const still = await ownedStatus(active); assert(still && still.state.managerNonce === active && still.answer.phase === 'ready'); item.nativeCloseDisconnectOnly = true;
      await stop(root, active); active = null; item.normalStop = true; native = null; item.passed = true; save();
    }
    assert(!fs.existsSync(path.join(factory.root, 'Data')), 'factory was touched');
    assert.deepEqual(await inventory(factory.root), factory.files, 'unbooted factory changed');
    assert.equal(await sha(factory.archive), factory.archiveSha256);
    report.factoryStillUnbooted = true; report.passed = true;
  } catch (error) { report.error = error.message; throw error; }
  finally {
    if (native && native.exitCode === null) native.kill(); // Owned native only, never a process tree/VM PID.
    try { const found = await ownedStatus(active); if (found) { await stop(root, found.state.managerNonce); report.failureNormalStop = true; } }
    catch (e) { report.cleanupError = e.message; report.passed = false; }
    report.finished = new Date().toISOString(); save(); console.log(JSON.stringify({ passed: report.passed, resultFile, error: report.error, cleanupError: report.cleanupError }));
  }
  return report;
}
if (require.main === module) verify(process.argv[2], process.argv[3]).catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { verify, validateResume };

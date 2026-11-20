'use strict';
// Synthetic native/ConPTY fixture only. Never imports the real sandbox backend.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const assert = require('node:assert/strict');

// Avoid Node 22's recursive cpSync path conversion on relocated Unicode roots.
// Only public regular build resources are accepted; never follow links.
function copyPublicTree(source, destination) {
  const stat = fs.lstatSync(source);
  assert(!stat.isSymbolicLink(), `public resource link refused: ${source}`);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination);
    for (const name of fs.readdirSync(source)) copyPublicTree(path.join(source, name), path.join(destination, name));
  } else {
    assert(stat.isFile(), `nonregular public resource refused: ${source}`);
    fs.copyFileSync(source, destination);
  }
}

async function main() {
  assert.equal(process.platform, 'win32');
  const repo = path.resolve(__dirname, '../../..');
  const build = path.resolve(process.argv[2] || path.join(repo, 'zig-out/native-sandbox-build-9ed7622e15044791a25ea60debb45ed5/package'));
  const publicNode = path.join(repo, 'zig-out/sandbox-node-candidate-20261115-ebdfc56b/Sandbox-Node-Portable/Runtime/node/node.exe');
  for (const file of [publicNode, path.join(build, 'bin/localterm-dev.exe'), path.join(build, 'share')]) assert(fs.existsSync(file), `missing public build input: ${file}`);
  const owned = path.join(repo, 'zig-out', `native-conpty-fixture-${crypto.randomUUID()}`);
  fs.mkdirSync(owned);
  const receipt = { owned, build, started: new Date().toISOString(), syntheticOnly: true, cases: [], offscreenContract: 'Reviewed window.zig: virtual desktop right+64 anchor before CreateWindowExW; WS_EX_NOACTIVATE; positioned before SW_SHOWNOACTIVATE; WINDOWPOSCHANGING guard; no focus/capture calls for no_activate hooks; existing guard asserts owned HWND is not foreground immediately after ShowWindow. Diagnostic may_close=null prevents modal confirmation. No continuous external foreground trace.' };
  const save = () => fs.writeFileSync(path.join(owned, 'receipt.json'), JSON.stringify(receipt, null, 2));
  console.log(owned);
  save();
  try {
    const root = path.join(owned, "relocated ไทย space's");
    fs.mkdirSync(path.join(root, 'Runtime/node'), { recursive: true });
    fs.mkdirSync(path.join(root, 'App'));
    fs.mkdirSync(path.join(owned, 'unrelated-cwd'));
    fs.copyFileSync(path.join(build, 'bin/localterm-dev.exe'), path.join(root, 'Sandbox.exe'));
    receipt.executableSha256 = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'Sandbox.exe'))).digest('hex');
    fs.copyFileSync(publicNode, path.join(root, 'Runtime/node/node.exe'));
    copyPublicTree(path.join(build, 'share'), path.join(root, 'share'));
    assert(fs.existsSync(path.join(root, 'share/ghostty')));
    assert(fs.existsSync(path.join(root, 'share/terminfo/ghostty.terminfo')));
    const nonce = crypto.randomBytes(16).toString('hex');
    fs.writeFileSync(path.join(root, 'sandbox-owned.json'), JSON.stringify({ name: 'ghostty-sandbox-owned', schema: 1, nonce }));
    const marker = `LOCALTERM_SANDBOX_NATIVE_${nonce}`;
    fs.writeFileSync(path.join(root, 'App/entry.cjs'), `
'use strict';
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const root = ${JSON.stringify(root)};
const result = { nonce: ${JSON.stringify(nonce)}, pid: process.pid, ppid: process.ppid, argv: process.argv, cwd: process.cwd(), syntheticOnly: true };
const out = path.join(root, 'synthetic-child.json');
try {
 assert.deepEqual(process.argv.slice(2), ['terminal', root]);
 assert.equal(process.execPath.toLowerCase(), path.join(root, 'Runtime/node/node.exe').toLowerCase());
 assert.equal(process.cwd(), root);
 assert.equal(process.stdin.isTTY, true); assert.equal(process.stdout.isTTY, true);
 assert(process.stdout.columns > 0 && process.stdout.rows > 0);
 result.columns = process.stdout.columns; result.rows = process.stdout.rows;
 for (const key of ['HOME','USERPROFILE','TEMP','TMP']) assert.equal(process.env[key], path.join(root, 'Data'));
 assert.equal(process.env.APPDATA, path.join(root, 'Data/profile'));
 assert.equal(process.env.LOCALAPPDATA, path.join(root, 'Data/local'));
 for (const key of ['NODE_OPTIONS','NODE_COMPILE_CACHE','NODE_PATH','OPENAI_API_KEY','LETTA_API_KEY','LETTA_BASE_URL','SSH_AUTH_SOCK','LOCALTERM_SANDBOX_OFFSCREEN','LOCALTERM_TERMINAL_SMOKE']) assert.equal(process.env[key], undefined, key);
 assert.equal(process.env.PATH.toLowerCase(), path.join(process.env.SystemRoot, 'System32').toLowerCase());
 result.validated = true; fs.writeFileSync(out, JSON.stringify(result));
 process.stdout.write('\\x1b[31m${marker} ไทย\\x1b[0m\\r\\n');
 setTimeout(() => { result.naturalExit = true; fs.writeFileSync(out, JSON.stringify(result)); process.exit(0); }, 5000);
} catch (error) { result.error = String(error.stack); fs.writeFileSync(out, JSON.stringify(result)); process.exit(3); }
`);
    const env = {
      SystemRoot: process.env.SystemRoot,
      ProgramData: process.env.ProgramData,
      LOCALTERM_SANDBOX_OFFSCREEN: '1',
      NODE_OPTIONS: '--no-warnings', NODE_COMPILE_CACHE: path.join(owned, 'forbidden-cache'),
      OPENAI_API_KEY: 'synthetic-not-a-real-key', LETTA_BASE_URL: 'http://synthetic.invalid',
      HOME: path.join(owned, 'forbidden-home'), LOCALTERM_TERMINAL_SMOKE: '1',
    };
    assert(env.SystemRoot && env.ProgramData, 'approved OS metadata missing');
    async function launch(label, requestNonce = crypto.randomBytes(16).toString('hex')) {
      const child = cp.spawn(path.join(root, 'Sandbox.exe'), [], { cwd: path.join(owned, 'unrelated-cwd'), env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
      const item = { label, requestNonce, pid: child.pid, acquired: false }; receipt.cases.push(item); save();
      const stdout = fs.createWriteStream(path.join(owned, `${label}.stdout.log`));
      const stderr = fs.createWriteStream(path.join(owned, `${label}.stderr.log`));
      const drained = Promise.all([stdout, stderr].map(stream => new Promise((resolve, reject) => { stream.once('finish', resolve); stream.once('error', reject); })));
      child.stdout.pipe(stdout); child.stderr.pipe(stderr);
      const timer = setTimeout(() => { item.timedOut = true; child.kill(); }, 30000);
      try {
        const result = await new Promise(resolve => { child.once('error', error => { item.spawnError = error.code; }); child.once('close', (code, signal) => resolve({ code, signal })); });
        Object.assign(item, result);
        await drained;
      } finally { clearTimeout(timer); save(); }
      assert(!item.timedOut, 'owned native process timed out');
      const log = fs.readFileSync(path.join(owned, `${label}.stderr.log`), 'utf8');
      let candidate;
      try { candidate = JSON.parse(fs.readFileSync(path.join(root, 'synthetic-child.json'), 'utf8')); } catch {}
      item.acquired = !item.spawnError && item.code === 0 && candidate?.nonce === requestNonce && candidate?.naturalExit === true && log.includes(`sandbox native painted marker=LOCALTERM_SANDBOX_NATIVE_${requestNonce} thai=true`);
      save();
      return { item, log };
    }
    const positive = await launch('relocated', nonce);
    assert.equal(positive.item.code, 0, positive.log);
    assert.equal(positive.item.acquired, true, 'fresh per-request result and native marker required');
    const result = JSON.parse(fs.readFileSync(path.join(root, 'synthetic-child.json'), 'utf8'));
    assert.equal(result.validated, true, JSON.stringify(result));
    assert.equal(result.naturalExit, true);
    assert.throws(() => process.kill(result.pid, 0), error => error.code === 'ESRCH', 'owned private Node must have exited');
    receipt.ownedNodeExited = true;
    assert(positive.log.includes(`sandbox native painted marker=${marker} thai=true`), 'native parsed/painted nonce evidence absent');
    assert(/sandbox native diagnostic frames=[1-9]\d* paints=[1-9]\d* marker_painted=true natural_exit=true renderer_failed=false/.test(positive.log), 'native presentation/normal-exit evidence absent');
    assert(/smoke window offscreen x=-?\d+ y=-?\d+; no-activate/.test(positive.log), 'guarded offscreen placement evidence absent');
    const bmp = path.join(root, 'Data/native/logs/sandbox-native-frame.bmp');
    const bytes = fs.readFileSync(bmp);
    assert.equal(bytes.subarray(0, 2).toString(), 'BM'); assert(bytes.length > 54);
    receipt.render = { marker, bmp, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), evidence: 'native terminal parsed nonce and Thai; red rendered pixels after successful GDI paint; not OCR or human GUI acceptance' };
    fs.writeFileSync(path.join(owned, 'prior-valid-receipt.json'), JSON.stringify({ passed: true, nonce, render: receipt.render, child: result }, null, 2));
    const staleChild = fs.readFileSync(path.join(root, 'synthetic-child.json'), 'utf8');
    // Negative case cannot reach window creation: dependency validation is global.
    fs.renameSync(path.join(root, 'Runtime/node/node.exe'), path.join(root, 'Runtime/node/node.absent'));
    const negative = await launch('missing-node');
    assert.notEqual(negative.item.code, 0, 'missing private runtime must fail closed');
    assert.equal(negative.item.acquired, false, 'prior valid result must not satisfy a failed startup request');
    assert(!negative.log.includes('smoke window offscreen'), 'missing runtime unexpectedly created native window');
    fs.renameSync(path.join(root, 'Sandbox.exe'), path.join(root, 'Sandbox.absent'));
    const acquisition = await launch('missing-native');
    assert.equal(acquisition.item.spawnError, 'ENOENT');
    assert.equal(acquisition.item.acquired, false, 'prior valid receipt must not satisfy failed acquisition');
    assert.equal(fs.readFileSync(path.join(root, 'synthetic-child.json'), 'utf8'), staleChild, 'negative requests preserve the prior result as stale evidence');
    receipt.staleArtifactRejected = true;
    receipt.passed = true;
  } catch (error) { receipt.passed = false; receipt.error = String(error.stack); throw error; }
  finally { receipt.finished = new Date().toISOString(); save(); }
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });

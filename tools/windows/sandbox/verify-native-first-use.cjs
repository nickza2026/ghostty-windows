'use strict';
// Native/no-VM password workflow. Only fresh synthetic roots and current child handles.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const { sha, real, inventory, repo } = require('./build-native-package.cjs');
const { inputScript } = require('./native-window-input.cjs');
const { syntheticPassword } = require('./verify-password-console.cjs');
const { sha512crypt } = require('./guest-password-hash.cjs');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const json = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));

// Do not persist an unexpected write before the controller can check it.
// This is pinned fixture output, not a general terminal capture facility.
function validateProgramWrite(text) {
  const permitted = [
    'Create a NEW Linux sudo password (not your Windows password). Prefer 12+ characters. It is not sent to chat.\n',
    'Linux sudo password: ', 'Confirm Linux password: ', '*', '\b \b', '\n', '',
    'Linux sudo password configured locally. SSH remains key-only; Windows privileges are unchanged.\n',
  ];
  if (!permitted.includes(text)) throw Error('Unexpected password setup output; not captured');
}

function validateProof(proof, nonce) {
  assert.equal(proof.nonce, nonce, 'fresh request proof required');
  for (const field of ['privateNode', 'stdinTTY', 'stdoutTTY', 'validHash', 'rawRestored', 'firstPrompt', 'confirmPrompt']) assert.equal(proof[field], true, field);
  assert.equal(typeof proof.programOutput, 'string');
  assert(proof.programOutput.length < 65536);
  assert(!proof.programOutput.includes(syntheticPassword), 'plaintext program echo');
  assert(!/\$6\$(?:rounds=\d+\$)?[^\s]+/.test(proof.programOutput), 'hash in output');
  assert(proof.programOutput.includes('Linux sudo password: ') && proof.programOutput.includes('Confirm Linux password: '));
  assert(proof.programOutput.includes('*'), 'actual masking output required');
}

async function verify(receiptFile = path.join(repo, 'zig-out/native-preview-5a909091-d660-4282-9d93-aeb03647292f/native-package.json')) {
  assert.equal(process.platform, 'win32');
  receiptFile = path.resolve(receiptFile); assert(receiptFile.startsWith(path.join(repo, 'zig-out') + path.sep)); real(receiptFile);
  const factory = json(receiptFile);
  assert(factory.passed && factory.dataIncluded === false && factory.archiveReextractVerified);
  assert(!fs.existsSync(path.join(factory.root, 'Data')));
  assert.deepEqual(await inventory(factory.root), factory.files, 'factory public payload mismatch');
  const requestId = crypto.randomUUID(), nonce = crypto.randomBytes(16).toString('hex');
  const out = path.join(repo, 'zig-out', 'native-first-use-' + requestId), root = path.join(out, 'Native-First-Use');
  assert(!fs.existsSync(out)); fs.mkdirSync(out); fs.mkdirSync(root);
  const reportFile = path.join(out, 'first-use.json');
  const report = { schema: 1, requestId, nonce, root, syntheticOnly: true, noVM: true, passed: false, humanAcceptance: false, stages: [] };
  const save = () => fs.writeFileSync(reportFile, JSON.stringify(report, null, 2)); save();
  console.log('NATIVE_FIRST_USE_RECEIPT=' + reportFile);
  function linkTree(from, to) {
    real(from); const stat = fs.lstatSync(from); assert(!stat.isSymbolicLink());
    if (stat.isDirectory()) { fs.mkdirSync(to); for (const name of fs.readdirSync(from)) linkTree(path.join(from, name), path.join(to, name)); }
    else { assert(stat.isFile()); fs.linkSync(from, to); }
  }
  let native, nativeExit, log = '', logFailure = false;
  const temp = path.join(out, 'controller-temp'); fs.mkdirSync(temp);
  const env = { SystemRoot: process.env.SystemRoot, ProgramData: process.env.ProgramData, HOME: temp, USERPROFILE: temp, TEMP: temp, TMP: temp, PATH: path.join(process.env.SystemRoot, 'System32') };
  async function ps(script, timeout = 20000) {
    const child = spawn(path.join(env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'), ['-NoLogo', '-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand', Buffer.from("$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';\n" + script, 'utf16le').toString('base64')], { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '', stderr = '', failure;
    child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
    child.stdout.on('data', text => { stdout += text; if (stdout.length > 1024 * 1024) { failure = 'output limit'; child.kill(); } });
    child.stderr.on('data', text => { stderr += text; if (stderr.length > 65536) { failure = 'error output limit'; child.kill(); } });
    const timer = setTimeout(() => { failure = 'deadline'; child.kill(); }, timeout);
    try {
      const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); });
      if (failure || code !== 0) throw Error(('Owned diagnostic PowerShell failed: ' + (failure || stderr)).replaceAll(syntheticPassword, '[synthetic-password-redacted]').slice(0, 1800));
      return stdout.trim().replace(/^\uFEFF/, '');
    } finally { clearTimeout(timer); }
  }
  async function waitFor(check, label, timeout = 20000) {
    const until = Date.now() + timeout;
    while (Date.now() < until) {
      const value = check(); if (value) return value;
      if (nativeExit || logFailure) throw Error('Native ended before ' + label);
      await delay(50);
    }
    throw Error('Owned ' + label + ' deadline');
  }
  try {
    fs.mkdirSync(path.join(root, 'Runtime/node'), { recursive: true }); fs.mkdirSync(path.join(root, 'App'));
    fs.linkSync(path.join(factory.root, 'Sandbox.exe'), path.join(root, 'Sandbox.exe'));
    fs.linkSync(path.join(factory.root, 'Runtime/node/node.exe'), path.join(root, 'Runtime/node/node.exe'));
    linkTree(path.join(factory.root, 'share'), path.join(root, 'share'));
    // Never truncate a hardlinked entry: original and probe are separate files.
    for (const name of fs.readdirSync(path.join(factory.root, 'App'))) {
      if (name !== 'entry.cjs') linkTree(path.join(factory.root, 'App', name), path.join(root, 'App', name));
    }
    fs.copyFileSync(path.join(factory.root, 'App/entry.cjs'), path.join(root, 'App/entry-real.cjs'));
    fs.writeFileSync(path.join(root, 'sandbox-owned.json'), JSON.stringify({ schema: 1, name: 'ghostty-sandbox-owned', nonce }));
    fs.writeFileSync(path.join(root, 'guest-profile.json'), JSON.stringify({ schema: 1, profile: 'node', ports: [] }));
    const first = path.join(out, 'prompt-first.json'), confirm = path.join(out, 'prompt-confirm.json'), proofFile = path.join(out, 'proof.json'), ack = path.join(out, 'exit-approved');
    const marker = 'LOCALTERM_SANDBOX_NATIVE_' + nonce;
    const probe = `
'use strict';
const fs=require('node:fs'),path=require('node:path');
const root=${JSON.stringify(root)},nonce=${JSON.stringify(nonce)};
const first=${JSON.stringify(first)},confirm=${JSON.stringify(confirm)},proofFile=${JSON.stringify(proofFile)},ack=${JSON.stringify(ack)};
let output='',firstPrompt=false,confirmPrompt=false;
const original=process.stdout.write;
const validateProgramWrite=${validateProgramWrite.toString()};
process.stdout.write=function(chunk,...args){const text=Buffer.isBuffer(chunk)?chunk.toString('utf8'):String(chunk);validateProgramWrite(text);output+=text;if(output.length>65536)throw Error('Synthetic output bound');if(text.includes('Linux sudo password: ')){firstPrompt=true;fs.writeFileSync(first,JSON.stringify({nonce,stage:'first'}),{flag:'wx'});}if(text.includes('Confirm Linux password: ')){confirmPrompt=true;fs.writeFileSync(confirm,JSON.stringify({nonce,stage:'confirm'}),{flag:'wx'});}return original.call(this,chunk,...args)};
(async()=>{
 await require('./entry-real.cjs').main(['setup-guest',root]);
 const proof={nonce,privateNode:process.execPath.toLowerCase()===path.join(root,'Runtime/node/node.exe').toLowerCase(),stdinTTY:process.stdin.isTTY===true,stdoutTTY:process.stdout.isTTY===true,validHash:!!require('./guest-config.cjs').passwordHash(root),rawRestored:process.stdin.isRaw===false,firstPrompt,confirmPrompt,programOutput:output};
 fs.writeFileSync(proofFile,JSON.stringify(proof),{flag:'wx'});
 original.call(process.stdout,${JSON.stringify('\x1b[31m' + marker + ' ไทย\x1b[0m\r\n')});
 const until=Date.now()+15000;const timer=setInterval(()=>{if(fs.existsSync(ack)){clearInterval(timer);process.exit(0);}else if(Date.now()>until){clearInterval(timer);process.exit(4);}},50);
})().catch(()=>{fs.writeFileSync(${JSON.stringify(path.join(out, 'probe-failed.json'))},JSON.stringify({nonce,failed:true}),{flag:'wx'});process.exit(3)});
`;
    fs.writeFileSync(path.join(root, 'App/entry.cjs'), probe);
    assert(!fs.existsSync(path.join(root, 'Runtime/qemu')) && !fs.existsSync(path.join(root, 'Data/guest-setup.json')));
    const nativeEnv = { SystemRoot: env.SystemRoot, ProgramData: env.ProgramData, LOCALTERM_SANDBOX_OFFSCREEN: '1' };
    native = spawn(path.join(root, 'Sandbox.exe'), [], { cwd: out, env: nativeEnv, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    report.nativePid = native.pid; save();
    for (const stream of [native.stdout, native.stderr]) { stream.setEncoding('utf8'); stream.on('data', text => { log += text; if (log.length > 4 * 1024 * 1024 || log.includes(syntheticPassword)) { logFailure = true; native.kill(); } }); }
    const closed = new Promise((resolve, reject) => { native.once('error', reject); native.once('close', (code, signal) => { nativeExit = { code, signal }; resolve(nativeExit); }); });
    for (const [stage, file] of [['first', first], ['confirm', confirm]]) {
      await waitFor(() => fs.existsSync(file) && json(file).nonce === nonce && json(file).stage === stage, stage + ' real prompt');
      const input = JSON.parse(await ps(inputScript(native.pid, syntheticPassword, factory.productName === 'Sandbox' ? 'Sandbox' : undefined)));
      assert(input.offscreen && input.noActivate && input.globalInput === false && input.ownedPid === native.pid);
      if (factory.productName === 'Sandbox') assert.equal(input.verifiedSandboxTitle, 'Sandbox');
      report.stages.push({ stage, input }); save();
    }
    const proof = await waitFor(() => fs.existsSync(proofFile) && json(proofFile), 'completed real setup'); validateProof(proof, nonce);
    const setupFile = path.join(root, 'Data/guest-setup.json'), rawSetup = fs.readFileSync(setupFile, 'utf8'), setup = JSON.parse(rawSetup);
    assert(!rawSetup.includes(syntheticPassword)); assert.equal(setup.rootId, nonce);
    const parts = setup.passwordHash.split('$'); assert.equal(parts[1], '6');
    const rounds = Number(parts[2].replace('rounds=', ''));
    assert.equal(sha512crypt(Buffer.from(syntheticPassword), parts[3], rounds), setup.passwordHash, 'UTF-8 native input hash must match typed fixture');
    assert(!fs.existsSync(path.join(root, 'Data/vm.json')) && !fs.existsSync(path.join(root, 'Data/guest.qcow2')));
    await waitFor(() => log.includes('sandbox native painted marker=' + marker + ' thai=true'), 'fresh native parsed/red/Thai paint');
    const bmp = path.join(root, 'Data/native/logs/sandbox-native-frame.bmp');
    assert(fs.existsSync(bmp) && fs.readFileSync(bmp).subarray(0, 2).toString() === 'BM');
    fs.writeFileSync(ack, nonce, { flag: 'wx' });
    const exit = await Promise.race([closed, delay(15000).then(() => { throw Error('Native natural-exit deadline'); })]);
    assert.equal(exit.code, 0); assert.equal(exit.signal, null);
    assert(/sandbox native diagnostic frames=[1-9]\d* paints=[1-9]\d* marker_painted=true natural_exit=true renderer_failed=false/.test(log));
    assert(!log.includes(syntheticPassword)); assert(!/\$6\$rounds=\d+\$/.test(log));
    fs.writeFileSync(path.join(out, 'native.log'), log);
    // Preserve only masked, verified program output. Never capture stdin or hash.
    fs.writeFileSync(path.join(out, 'masked-output.txt'), proof.programOutput);
    const png = path.join(out, 'native-first-use.png');
    const encodedBmp = Buffer.from(bmp).toString('base64'), encodedPng = Buffer.from(png).toString('base64');
    await ps(`Add-Type -AssemblyName System.Drawing;$bmp=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encodedBmp}'));$png=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encodedPng}'));$image=[Drawing.Image]::FromFile($bmp);try{$image.Save($png,[Drawing.Imaging.ImageFormat]::Png)}finally{$image.Dispose()}`);
    assert(!fs.existsSync(path.join(factory.root, 'Data'))); assert.deepEqual(await inventory(factory.root), factory.files);
    Object.assign(report, { passed: true, nativeExit: exit, utf8NativePassword: true, hashMatchesTypedFixture: true, rawRestored: true, programStdoutPlaintextEcho: false, setupPlaintextStored: false, noVMData: true, factoryUntouched: true, factoryDataIncluded: false, render: { bmp, bmpSha256: await sha(bmp), png, pngSha256: await sha(png), parsedNonceThaiRedPaint: true, visualReviewPending: true } });
  } catch (error) {
    report.error = String(error.message).replaceAll(syntheticPassword, '[synthetic-password-redacted]').replace(/\$6\$(?:rounds=\d+\$)?\S+/g, '[hash-redacted]').slice(0, 2000); throw Error(report.error);
  } finally {
    if (native && native.exitCode === null) native.kill();
    report.finished = new Date().toISOString(); save();
    console.log(JSON.stringify({ passed: report.passed, resultFile: reportFile, error: report.error }));
  }
  return report;
}
if (require.main === module) verify(process.argv[2]).catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { verify, validateProof, validateProgramWrite };

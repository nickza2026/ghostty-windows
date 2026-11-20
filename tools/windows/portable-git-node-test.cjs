'use strict';

// Node -> real EXE spawn boundary used by Letta. No agent/provider is started.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');

const root = path.resolve(process.argv[2] || '');
assert.equal(fs.readFileSync(path.join(root, '.portable-git-test-owned'), 'utf8'), 'portable-git-node-fixture-v1');
const data = path.join(root, 'bin', 'portable-data');
const scratch = fs.mkdtempSync(path.join(data, 'tmp', 'node-git-'));
const home = path.join(scratch, 'home');
fs.mkdirSync(home);
const emptyConfig = path.join(home, 'test-empty.gitconfig');
fs.writeFileSync(emptyConfig, '');
const windows = process.env.SystemRoot;
const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^git_/i.test(name) && !/^(path|home|userprofile|node_options)$/i.test(name)));
Object.assign(env, {
  PATH: [path.join(data, 'shims'), path.join(windows, 'System32'), windows].join(';'),
  HOME: home, USERPROFILE: home, GIT_CONFIG_GLOBAL: emptyConfig,
  GIT_CONFIG_NOSYSTEM: '1', GIT_TERMINAL_PROMPT: '0',
});
const direct = path.join(data, 'runtimes', 'git', 'cmd', 'git.exe');
const proxy = path.join(data, 'shims', 'git.exe');
const cases = [];
const run = (args, options = {}) => cp.spawnSync('git', args, { env, cwd: scratch, encoding: 'utf8', timeout: 15000, windowsHide: true, ...options });
const check = (name, fn) => { fn(); cases.push(name); console.log('PASS ' + name); };
function successful(result) {
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}
function ownedProcesses() {
  const prefix = Buffer.from(root + path.sep, 'utf16le').toString('base64');
  const script = `$ProgressPreference='SilentlyContinue';$p=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('${prefix}'));@(Get-CimInstance Win32_Process -Filter "Name='git.exe'"|Where-Object{$_.ExecutablePath -and $_.ExecutablePath.StartsWith($p,[StringComparison]::OrdinalIgnoreCase)}|Select-Object -ExpandProperty ProcessId)|ConvertTo-Json -Compress`;
  const result = cp.spawnSync(path.join(windows, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'), ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], { env, encoding: 'utf8', timeout: 10000, windowsHide: true });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  const parsed = result.stdout.trim() ? JSON.parse(result.stdout.trim()) : [];
  return Array.isArray(parsed) ? parsed : [parsed];
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(predicate, milliseconds) {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) { if (await predicate()) return; await delay(100); }
  throw new Error('Owned fixture condition timed out');
}

async function main() {
  check('native-git-exe-found-without-shell-or-host-PATH', () => {
    assert.ok(fs.existsSync(proxy));
    assert.match(successful(run(['--version'])), /^git version 2\.56\.0/);
    assert.equal(successful(run(['--version'])), successful(cp.spawnSync(direct, ['--version'], { env, encoding: 'utf8', timeout: 15000, windowsHide: true })));
  });
  const repo = path.join(scratch, 'repo spaces ไทย');
  check('isolated-git-init-and-cwd-inheritance', () => {
    successful(run(['-c', 'init.defaultBranch=main', 'init', repo]));
    assert.equal(path.resolve(successful(run(['rev-parse', '--show-toplevel'], { cwd: repo })).trim()), path.resolve(repo));
    assert.equal(successful(run(['status', '--porcelain'], { cwd: repo })), '');
  });
  check('stdin-binary-forwarding-and-object-hash', () => {
    const input = Buffer.concat([Buffer.from('synthetic ไทย\0'), Buffer.from([0, 255, 13, 10]), Buffer.alloc(200000, 97)]);
    const expected = crypto.createHash('sha1').update(Buffer.from(`blob ${input.length}\0`)).update(input).digest('hex');
    assert.equal(successful(run(['hash-object', '--stdin'], { cwd: repo, input })).trim(), expected);
  });
  check('argv-unicode-quotes-and-trailing-backslashes', () => {
    const value = 'with space ไทย "quoted" slash\\ trailing\\';
    assert.equal(successful(run(['-c', 'fixture.value=' + value, 'config', '--get', 'fixture.value'])).trimEnd(), value);
  });
  check('nonzero-exit-and-stderr-forwarding', () => {
    const throughProxy = run(['--fixture-invalid-option']);
    const native = cp.spawnSync(direct, ['--fixture-invalid-option'], { env, encoding: 'utf8', timeout: 15000, windowsHide: true });
    assert.ifError(throughProxy.error);
    assert.equal(throughProxy.status, native.status);
    assert.notEqual(throughProxy.status, 0);
    assert.equal(throughProxy.stderr, native.stderr);
  });
  const targetHidden = direct + '.owned-test-hidden';
  check('missing-private-target-does-not-fall-back-to-host-Git', () => {
    fs.renameSync(direct, targetHidden);
    try {
      const result = run(['--version']);
      assert.ifError(result.error);
      assert.equal(result.status, 127);
      assert.equal(result.stdout, '');
    } finally { fs.renameSync(targetHidden, direct); }
  });
  const waiting = cp.spawn('git', ['hash-object', '--stdin'], { cwd: repo, env, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
  let exited = false;
  let spawnError;
  waiting.once('error', error => { spawnError = error; exited = true; });
  waiting.once('exit', () => { exited = true; });
  try {
    await waitFor(() => ownedProcesses().some(pid => pid !== waiting.pid), 10000);
    assert.ifError(spawnError);
    assert.equal(exited, false, 'Git stdin fixture did not remain waiting');
    assert.equal(waiting.kill('SIGTERM'), true);
    await waitFor(() => exited, 10000);
    await waitFor(() => ownedProcesses().length === 0, 10000);
    cases.push('Node-cancel-kills-private-Git-descendants');
    console.log('PASS Node-cancel-kills-private-Git-descendants');
  } finally {
    if (!exited) waiting.kill('SIGTERM');
    waiting.stdin.destroy(); waiting.stdout.destroy(); waiting.stderr.destroy();
    // Only exact exe-path-qualified children of this uniquely marked fixture.
    for (const pid of ownedProcesses()) {
      cp.spawnSync(path.join(windows, 'System32', 'taskkill.exe'), ['/PID', String(pid), '/T', '/F'], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
    }
  }
  const result = { passed: true, cases, fixture: root, realAccountsUsed: false, providerCalls: false, projectCommitsCreated: false };
  fs.writeFileSync(path.join(scratch, 'results.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });

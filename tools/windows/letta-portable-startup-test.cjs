'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(process.argv[2]);
const workspace = path.resolve(__dirname, '..', '..');
const data = path.join(root, 'bin', 'portable-data');
const resumeAt = process.argv.indexOf('--resume-fixture');
const resumeFixture = resumeAt >= 0 ? path.resolve(process.argv[resumeAt + 1]) : null;
const ownershipTest = process.argv.includes('--portable-ownership') || !!resumeFixture;
const fixture = resumeFixture || fs.mkdtempSync(ownershipTest ? path.join(data, 'tmp', 'lt-') : path.join(workspace, 'zig-out', 'letta-startup-'));
if (resumeFixture) {
  assert(fixture.startsWith(path.join(data, 'tmp') + path.sep));
  assert.equal(fs.readFileSync(path.join(fixture, '.owned-startup'), 'utf8'), 'letta-startup-test-v1');
} else fs.writeFileSync(path.join(fixture, '.owned-startup'), 'letta-startup-test-v1');
const pkg = path.join(data, 'npm', 'node_modules', '@letta-ai', 'letta-code');
const node = path.join(data, 'runtimes', 'node', 'node.exe');
const windows = process.env.SystemRoot;
const home = path.join(fixture, 'home');
const tmp = path.join(fixture, 'tmp');
if (!resumeFixture) { fs.mkdirSync(home); fs.mkdirSync(tmp); }
const emptyConfig = path.join(fixture, 'empty.gitconfig');
if (!resumeFixture) fs.writeFileSync(emptyConfig, '');
if (ownershipTest && !resumeFixture) {
  const scope = '%(prefix)/../../../tmp/' + path.basename(fixture) + '/home/.letta/local/memfs/*';
  fs.writeFileSync(emptyConfig, '[safe]\n\tdirectory = ' + scope + '\n');
}
const env = {
  SystemRoot: windows, WINDIR: windows, ComSpec: path.join(windows, 'System32', 'cmd.exe'),
  PATH: [path.join(data, 'shims'), path.join(data, 'runtimes', 'node'), path.join(windows, 'System32'), windows].join(';'),
  PATHEXT: '.COM;.EXE;.BAT;.CMD', NoDefaultCurrentDirectoryInExePath: '1',
  HOME: home, USERPROFILE: home, APPDATA: path.join(home, 'AppData', 'Roaming'),
  LOCALAPPDATA: path.join(home, 'AppData', 'Local'), TEMP: tmp, TMP: tmp,
  XDG_CONFIG_HOME: path.join(home, '.config'), XDG_DATA_HOME: path.join(home, '.local', 'share'),
  XDG_STATE_HOME: path.join(home, '.local', 'state'), XDG_CACHE_HOME: path.join(home, '.cache'),
  LETTA_HOME: path.join(home, '.letta'), LETTA_LOCAL_BACKEND_DIR: path.join(home, '.letta', 'local'),
  DISABLE_AUTOUPDATER: '1', DO_NOT_TRACK: '1',
  GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: emptyConfig, GIT_TERMINAL_PROMPT: '0',
  TERM: 'xterm-256color', COLORTERM: 'truecolor', FORCE_COLOR: '1',
};
// A fixture-local repository boundary prevents borrowing this project's settings.
const init = ownershipTest ? { status: 0 } : cp.spawnSync(path.join(data, 'shims', 'git.exe'), ['-c', 'init.defaultBranch=main', 'init', fixture], {
  cwd: fixture, env, encoding: 'utf8', windowsHide: true, timeout: 15000,
});
assert.ifError(init.error); assert.equal(init.status, 0, init.stderr);
// Run only the already reviewed published patcher, not dependency lifecycle scripts.
const patch = ownershipTest ? { status: 0, stdout: 'Already prepared public CLI: no patcher rerun in ownership test.', stderr: '' } : cp.spawnSync(node, [path.join(pkg, 'scripts', 'postinstall-patches.js')], {
  cwd: fixture, env, encoding: 'utf8', windowsHide: true, timeout: 30000,
});
assert.ifError(patch.error);
assert.equal(patch.status, 0, patch.stderr);
fs.writeFileSync(path.join(fixture, 'published-postinstall.txt'), patch.stdout + patch.stderr);
const version = cp.spawnSync(node, [path.join(pkg, 'letta.js'), '--version'], {
  cwd: fixture, env, encoding: 'utf8', windowsHide: true, timeout: 30000,
});
assert.ifError(version.error); assert.equal(version.status, 0, version.stderr);
assert.match(version.stdout, /0\.34\.23/);
fs.writeFileSync(path.join(fixture, 'version.txt'), version.stdout + version.stderr);
const pty = require(path.join(pkg, 'node_modules', 'node-pty'));
const guardLog = path.join(fixture, 'transport-guard.jsonl');
env.NODE_OPTIONS = '--require="' + path.join(__dirname, 'letta-startup-network-guard.cjs').replaceAll('\\', '/') + '"';
env.PORTABLE_STARTUP_GUARD_LOG = guardLog;
env.PORTABLE_STARTUP_PACKAGE = root;
const resumeAgent = resumeFixture ? JSON.parse(fs.readFileSync(path.join(fixture, 'results.json'), 'utf8')).committedMemoryRepos.map(p => path.basename(path.dirname(p)))[0] : null;
const terminal = pty.spawn(node, [path.join(pkg, 'letta.js'), '--backend', 'local', ...(resumeAgent ? ['--agent', resumeAgent, '--new'] : ['--new-agent'])], {
  name: 'xterm-256color', cols: 110, rows: 35, cwd: fixture, env, useConpty: true,
});
let output = ''; let ended = false; let exitCode = null; let stoppedByTest = false;
terminal.onData(text => { output += text; });
terminal.onExit(result => { ended = true; exitCode = result.exitCode; });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function main() {
  const deadline = Date.now() + 35000;
  try {
    while (Date.now() < deadline && !ended) {
      await delay(250);
      const plain = output.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '');
      if (/Error during initialization:|spawn git ENOENT|Raw mode is not supported/i.test(plain)) break;
      if (/Select.*provider|choose.*provider|Connect.*provider|no.*providers|Welcome to Letta|API key|Select.*model/i.test(plain) && output.length > 200) {
        await delay(1000); break;
      }
    }
  } finally {
    if (!ended) {
      stoppedByTest = true;
      // Graceful termination avoids node-pty's AttachConsole helper racing an
      // already closing ConPTY. No prompt, login or model input is sent.
      try { terminal.write('\x03'); await delay(350); } catch {}
      if (!ended) { try { terminal.write('\x03'); await delay(500); } catch {} }
      if (!ended) { try { terminal.kill(); } catch {} }
    }
    await delay(700);
  }
  fs.writeFileSync(path.join(fixture, 'pty-output.txt'), output);
  const plain = output.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '');
  const events = fs.existsSync(guardLog) ? fs.readFileSync(guardLog, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line)) : [];
  const memfs = path.join(env.LETTA_LOCAL_BACKEND_DIR, 'memfs');
  const committedMemoryRepos = [];
  if (fs.existsSync(memfs)) {
    for (const agent of fs.readdirSync(memfs)) {
      const memory = path.join(memfs, agent, 'memory');
      const ref = path.join(memory, '.git', 'refs', 'heads', 'main');
      if (fs.existsSync(ref) && /^[a-f0-9]{40}\s*$/.test(fs.readFileSync(ref, 'utf8'))) committedMemoryRepos.push(memory);
    }
  }
  const result = {
    fixture, privateCLI: '0.34.23', privateGitENOENT: /spawn git ENOENT/i.test(plain),
    initializationError: /Error during initialization:/i.test(plain),
    outputCharacters: output.length, exitCode, stoppedByTest, guardEvents: events,
    expectedFirstRunUI: /Select.*provider|choose.*provider|Connect.*provider|no.*providers|Welcome to Letta|API key|Select.*model/i.test(plain),
    syntheticInitialMemoryCommit: committedMemoryRepos.length > 0, committedMemoryRepos,
    ownershipTest, resumeTest: !!resumeFixture, dubiousOwnership: /dubious ownership|does not record ownership/i.test(plain),
    genuineConPTY: true, visibleWindow: false, realCredentials: false,
    sentUserInput: false, terminationControlOnly: stoppedByTest, providerChatVerified: false,
  };
  fs.writeFileSync(path.join(fixture, 'results.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
  // No broad success claim: inspect the rendered state and fixture Git evidence.
  console.log('OUTPUT_TAIL=' + plain.slice(-1800));
  if (result.privateGitENOENT || result.initializationError || (!result.expectedFirstRunUI && !result.syntheticInitialMemoryCommit) || (!stoppedByTest && exitCode !== 0)) process.exitCode = 1;
  if (ownershipTest && (result.dubiousOwnership || !result.syntheticInitialMemoryCommit)) process.exitCode = 1;
  // node-pty may retain a native pipe watcher after ConPTY process exit.
  // The owned child was explicitly closed above; do not hang the test runner.
  setTimeout(() => process.exit(process.exitCode || 0), 100).unref();
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });

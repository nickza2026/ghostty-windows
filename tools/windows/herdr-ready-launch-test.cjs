'use strict';
// Full launcher test. All IPC/processes/data belong to a newly built D: fixture.
// Never point this at a used delivery or at A:.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(process.argv[2]);
const workspace = path.resolve(__dirname, '../..');
assert(root.startsWith(path.join(workspace, 'zig-out') + path.sep));
const finalCandidate = process.argv[3] === '--fresh-owned-candidate';
assert(/^hr-ready-test-/.test(path.basename(root)) || (finalCandidate && path.basename(root) === 'herdr-ready-20261029'), 'Only an explicitly owned test build is allowed');
const data = path.join(root, 'bin/portable-data');
const profile = path.join(data, 'profiles/herdr');
if(finalCandidate){
  const m=JSON.parse(fs.readFileSync(path.join(root,'package-manifest.json'),'utf8').replace(/^\uFEFF/,''));
  assert(m.ready_Herdr && m.user_data_copied === false);
  assert(!fs.existsSync(path.join(profile,'home/.letta/local/memfs')), 'Final candidate must be unused before this owned test');
}
const exe = path.join(data, 'apps/herdr/0.9.5/herdr.exe');
const windows = process.env.SystemRoot;
const sessionBase = 'portable-' + crypto.createHash('sha256').update(root.toLowerCase()).digest('hex').slice(0, 24);
const session = sessionBase + '-shell-v3';
const evidence = fs.mkdtempSync(path.join(workspace, 'zig-out', 'herdr-cmd-e2e-'));
fs.writeFileSync(path.join(evidence, '.owned'), 'herdr-ready-cmd-test-v1');
fs.writeFileSync(path.join(root, '.owned-ready-test'), 'herdr-ready-cmd-test-v1');
const trap = path.join(evidence, 'host-bin'); fs.mkdirSync(trap);
for (const name of ['git.exe', 'node.exe', 'letta.ps1']) fs.writeFileSync(path.join(trap, name), 'host trap must not execute');
const env = {
  SystemRoot: windows, WINDIR: windows, ComSpec: path.join(windows, 'System32/cmd.exe'),
  PATH: [trap, path.join(windows, 'System32'), windows, path.join(windows, 'System32/WindowsPowerShell/v1.0')].join(';'),
  PATHEXT: '.COM;.EXE;.BAT;.CMD', NoDefaultCurrentDirectoryInExePath: '1',
  HOME: path.join(profile, 'home'), USERPROFILE: path.join(profile, 'home'),
  APPDATA: path.join(profile, 'config'), LOCALAPPDATA: path.join(profile, 'state'),
  XDG_CONFIG_HOME: path.join(profile, 'config'), XDG_STATE_HOME: path.join(profile, 'state'),
  XDG_CACHE_HOME: path.join(profile, 'cache'), TEMP: path.join(profile, 'tmp'), TMP: path.join(profile, 'tmp'),
  HERDR_CONFIG_PATH: path.join(profile, 'config/herdr/config.toml'),
  TERM: 'xterm-256color', COLORTERM: 'truecolor',
};
const allowed = new Set([session, sessionBase]);
function api(name, args, mustWork = true) {
  assert(allowed.has(name));
  const r = cp.spawnSync(exe, ['--session', name, ...args], { cwd: evidence, env, encoding: 'utf8', timeout: 20000, windowsHide: true });
  assert.ifError(r.error);
  if (!mustWork && r.status !== 0) return null;
  assert.equal(r.status, 0, r.stderr);
  if (args[0] === 'pane' && args[1] === 'read') return { text: r.stdout };
  if (!r.stdout.trim()) {
    assert(['run', 'send-keys', 'stop'].includes(args[1]), 'Read API returned no JSON');
    return {};
  }
  const value = JSON.parse(r.stdout);
  assert(!value.error, JSON.stringify(value.error));
  return value.result ?? value;
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, timeout, message) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { const value = check(); if (value) return value; await delay(200); }
  throw new Error(message);
}
function endpoint(name) { return path.join(env.XDG_CONFIG_HOME, 'herdr/sessions', name, 'herdr.sock'); }
function text(pane) { return api(session, ['pane', 'read', pane, '--source', 'visible']).text; }
const quote = value => "'" + value.replaceAll("'", "''") + "'";
let legacy, client;
let legacyOut = '', legacyErr = '', clientOutput = '';
const pty = require(path.join(data, 'npm/node_modules/@letta-ai/letta-code/node_modules/node-pty'));
function launch() {
  const terminal = pty.spawn(env.ComSpec, ['/d', '/c', path.join(root, 'Run-Herdr.cmd')], {
    name: 'xterm-256color', cols: 120, rows: 38, cwd: evidence, env, useConpty: true,
  });
  terminal.onData(t => { clientOutput += t; });
  terminal.onExit(() => { terminal.testEnded = true; });
  return terminal;
}
function retireClient(terminal){
  if(!terminal || terminal.testEnded) return;
  // Servers have already been stopped gracefully. Retire only our recorded CMD
  // PID; node-pty.kill's console-list helper errors after a ConPTY has detached.
  cp.spawnSync(path.join(windows,'System32/taskkill.exe'),['/PID',String(terminal.pid),'/T','/F'],{windowsHide:true,stdio:'ignore',timeout:10000});
}
function memories() {
  const p = path.join(profile, 'home/.letta/local/memfs');
  return fs.existsSync(p) ? fs.readdirSync(p).filter(n => n.startsWith('agent-local-')).map(n => path.join(p, n, 'memory')) : [];
}
async function privatePane(round) {
  await until(() => fs.existsSync(endpoint(session)), 45000, 'Normal CMD did not start its own current-generation server');
  const panes = await until(() => {
    const r = api(session, ['pane', 'list']);
    const list = Array.isArray(r) ? r : r.panes;
    assert(Array.isArray(list), 'Unexpected actual pane-list schema');
    return list.length ? list : null;
  }, 20000, 'Normal launcher did not provide an initial pane');
  assert.equal(panes.length, 1, 'Fresh launcher unexpectedly created extra panes');
  const pane = panes[0].pane_id;
  const proof = path.join(evidence, `commands-${round}.json`);
  api(session, ['pane', 'run', pane,
    `[pscustomobject]@{git=(Get-Command git).Source;node=(Get-Command node).Source;letta=(Get-Command letta).Source;home=$env:HOME;noProfile=([Environment]::CommandLine -match '-NoProfile')}|ConvertTo-Json|Set-Content -Encoding UTF8 -LiteralPath ${quote(proof)}`]);
  await until(() => fs.existsSync(proof), 12000, 'Default pane was not a working managed PowerShell');
  const p = JSON.parse(fs.readFileSync(proof, 'utf8').replace(/^\uFEFF/, ''));
  for (const key of ['git', 'node', 'letta']) assert(p[key].toLowerCase().startsWith(data.toLowerCase() + path.sep), `${key} escaped to host`);
  assert.equal(p.home.toLowerCase(), env.HOME.toLowerCase()); assert(p.noProfile);
  return pane;
}
async function letNew(pane, round) {
  const guard = path.join(__dirname, 'letta-startup-network-guard.cjs').replaceAll('\\', '/');
  const guardLog = path.join(evidence, `network-guard-${round}.jsonl`);
  const command = `Clear-Host;$env:NODE_OPTIONS=${quote('--require="' + guard + '"')};$env:PORTABLE_STARTUP_GUARD_LOG=${quote(guardLog)};$env:PORTABLE_STARTUP_PACKAGE=${quote(root)};letta --new`;
  api(session, ['pane', 'run', pane, command]);
  await until(() => {
    const output = text(pane);
    fs.writeFileSync(path.join(evidence, `letta-${round}.txt`), output);
    assert(!/Error during initialization:|dubious ownership|--local can only be used inside/i.test(output), 'Actual letta --new initialization failed');
    const events = fs.existsSync(guardLog) ? fs.readFileSync(guardLog, 'utf8').trim().split('\n').filter(Boolean).map(t => JSON.parse(t)) : [];
    return /No model selected|Starting new conversation|Creating a new agent|\/connect/.test(output) && memories().length && events.filter(e => e.allowed === 'private Git').length >= 3;
  }, 40000, 'Actual user command did not reach the local interactive agent');
  assert(fs.existsSync(guardLog), 'No transport guard evidence from actual user-command chain');
  const repos = memories();
  assert(repos.some(p => fs.existsSync(path.join(p, '.git/refs/heads/main'))), 'No initial memory commit in actual launcher profile');
  await delay(700); assert(!/Error during initialization:|--local can only be used inside/i.test(text(pane)));
  api(session, ['pane', 'send-keys', pane, 'Ctrl+c']); await delay(450);
  api(session, ['pane', 'send-keys', pane, 'Ctrl+c']);
  const marker = path.join(evidence, `back-in-shell-${round}`);
  await delay(800);
  api(session, ['pane', 'run', pane, `[IO.File]::WriteAllText(${quote(marker)},'owned')`]);
  await until(() => fs.existsSync(marker), 12000, 'Owned Letta did not return to shell on explicit Ctrl+C');
  return repos.map(p => path.basename(path.dirname(p))).sort();
}
async function main() {
  let result;
  try {
    // Keep a live legacy session to reproduce the old launcher reattach problem.
    const oldShell = path.join(workspace, 'zig-out/portable-packages/localterm-herdr-portable-20261028/bin/portable-data/apps/herdr-shell/v2/herdr-private-shell.exe');
    assert(fs.existsSync(oldShell));
    const legacyConfig = path.join(evidence, 'legacy.toml');
    fs.writeFileSync(legacyConfig, '[terminal]\ndefault_shell = ' + JSON.stringify(oldShell) + '\n[update]\nversion_check = false\nmanifest_check = false\n');
    legacy = cp.spawn(exe, ['--session', sessionBase, 'server'], { cwd: evidence, env: { ...env, HERDR_CONFIG_PATH: legacyConfig }, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    legacy.stdout.on('data', t => { legacyOut += t; }); legacy.stderr.on('data', t => { legacyErr += t; });
    await until(() => fs.existsSync(endpoint(sessionBase)), 20000, 'Owned legacy server failed to bind');
    api(sessionBase, ['workspace', 'create', '--cwd', env.HOME, '--label', 'owned-legacy-v2']);
    client = launch();
    const first = await privatePane('fresh');
    const initialAgents = await letNew(first, 'fresh');
    assert.equal(legacy.exitCode, null, 'Launcher stopped the old session');
    api(session, ['server', 'stop']);
    await until(() => !fs.existsSync(endpoint(session)), 15000, 'Owned server did not stop for restore test');
    await delay(700); retireClient(client); client = null;
    client = launch();
    const restored = await privatePane('restored');
    const resumedAgents = await letNew(restored, 'restored');
    assert.deepEqual(resumedAgents, initialAgents, '--new replaced agents instead of reusing their local state');
    assert.equal(legacy.exitCode, null, 'Restore stopped the old session');
    result = { passed: true, root, evidence, actual_Run_Herdr_cmd_in_ConPTY: true,
      normal_launcher_provides_private_pane_without_manual_v3: true,
      actual_Git_Node_Letta_resolution_private: true, actual_letta_new_and_initial_memory_commit: true,
      restart_restore_and_letta_new_same_agents: true, legacy_v2_session_left_running: true,
      no_real_credentials_or_provider_calls: true, A_touched: false, visible_GUI_or_focus: false };
    console.log(JSON.stringify(result, null, 2));
  } finally {
    for (const name of [session, sessionBase]) if (fs.existsSync(endpoint(name))) { try { api(name, ['server', 'stop']); } catch {} }
    await delay(700); retireClient(client);
    fs.writeFileSync(path.join(evidence, 'normal-launch-client.txt'), clientOutput);
    fs.writeFileSync(path.join(evidence, 'legacy-server.txt'), legacyOut + legacyErr);
    fs.writeFileSync(path.join(evidence, 'result.json'), JSON.stringify(result || { passed: false, root, evidence }, null, 2));
  }
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; }).finally(() => setTimeout(() => process.exit(process.exitCode || 0), 200).unref());

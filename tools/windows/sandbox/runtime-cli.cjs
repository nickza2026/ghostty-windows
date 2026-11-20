'use strict';
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const ide = require('./ide-workspace.cjs');
const { TerminalFilter } = require('./terminal-filter.cjs');
const { TerminalInput } = require('./terminal-protocol.cjs');
const commands = ['manager', 'terminal', 'ide', 'status', 'stop', 'force-stop'];
const tokenPattern = /^[a-f0-9]{64}$/;
const failureMessages = Object.freeze({
  SSH_KEY_STORAGE_UNSUPPORTED: 'Windows OpenSSH cannot load the portable key on this storage. No key-check bypass or host-profile fallback.',
  SSH_KEY_MISMATCH: 'Portable SSH public/private key mismatch; no automatic key replacement.',
  SSH_AGENT_UNAVAILABLE: 'Package private SSH agent unavailable; no global-agent or host-profile fallback.'
});
const knownFailure = value => Object.hasOwn(failureMessages, value || '');
function parse(args) {
  const [command, root, project] = args;
  if (!commands.includes(command) || !root || args.length > 3 || (project && command !== 'ide')) throw Error('Usage: runtime-cli.cjs manager|terminal|ide|status|stop|force-stop <packageRoot> [guestProjectPath]');
  if (project !== undefined) ide.guestUri(project);
  return { command, root: path.resolve(root), project };
}
function environment(root, source = process.env) {
  const data = path.join(root, 'Data');
  const system = source.SystemRoot || 'C:\\Windows';
  return { SystemRoot: system, ...(source.ProgramData ? { ProgramData: source.ProgramData } : {}),
    PATH: path.join(system, 'System32'), TEMP: data, TMP: data,
    HOME: data, USERPROFILE: data, APPDATA: path.join(data, 'profile'), LOCALAPPDATA: path.join(data, 'local'), TERM: 'xterm-256color' };
}
function required(file, io = fs) {
  if (!io.existsSync(file)) throw Error(`Required portable component unavailable: ${file}`);
  return file;
}
function identity(root, io = fs) {
  const owner = JSON.parse(io.readFileSync(path.join(root, 'sandbox-owned.json'), 'utf8'));
  if (owner.name !== 'ghostty-sandbox-owned' || owner.schema !== 1 || typeof owner.nonce !== 'string' || owner.nonce.length < 16) throw Error('Invalid package ownership');
  return owner.nonce;
}
function validState(state, root, rootId) {
  return state && state.root === root && state.rootId === rootId && tokenPattern.test(state.token) &&
    tokenPattern.test(state.managerNonce) && Number.isInteger(state.port) && state.port > 0 && state.port <= 65535 &&
    (state.activePorts === undefined || (Array.isArray(state.activePorts) && state.activePorts.length <= 10 && state.activePorts.every(p => Number.isInteger(p) && p > 0 && p <= 65535))) &&
    ['booting', 'ready', 'failed', 'stopping', 'stopped'].includes(state.phase);
}
function authorized(req, state) {
  const h = req.headers;
  if (h.host !== `127.0.0.1:${state.port}` || h.origin !== undefined || h['transfer-encoding'] !== undefined) return false;
  if (h['content-length'] !== undefined && (!/^\d+$/.test(h['content-length']) || Number(h['content-length']) > 1024)) return false;
  const value = h.authorization;
  if (typeof value !== 'string' || !/^Bearer [a-f0-9]{64}$/.test(value) || !tokenPattern.test(state.token)) return false;
  return crypto.timingSafeEqual(Buffer.from(value.slice(7)), Buffer.from(state.token));
}
function publicState(state) {
  const { root, rootId, phase, managerNonce, port } = state;
  return { root, rootId, phase, managerNonce, port, ...(knownFailure(state.failureCode) ? { failureCode: state.failureCode } : {}) };
}
function terminalCommand(root, source = process.env, io = fs) {
  const relay=fs.readFileSync(path.join(__dirname,'guest-terminal.py')).toString('base64');
  return { executable: required(path.join(source.SystemRoot || 'C:\\Windows', 'System32', 'OpenSSH', 'ssh.exe'), io),
    args: ['-F', path.join(root, 'Data', 'ssh', 'config'), '-T', '-e', 'none', 'portable-sandbox',
      `/usr/bin/python3 -I -c 'import base64;exec(compile(base64.b64decode("${relay}"),"<portable-terminal>","exec"))'`] };
}
function codeCommand(source = process.env, io = fs) {
  const choices = [source.LOCALAPPDATA && path.join(source.LOCALAPPDATA, 'Programs', 'Microsoft VS Code', 'Code.exe'),
    source.ProgramFiles && path.join(source.ProgramFiles, 'Microsoft VS Code', 'Code.exe')].filter(Boolean);
  const executable = choices.find(p => io.existsSync(p));
  if (!executable) throw Error('Public VS Code installation unavailable');
  if (io.existsSync(path.join(path.dirname(executable), 'data'))) throw Error('IDE has its own portable data; refusing another profile principal');
  const base = path.dirname(executable);
  let script = path.join(base, 'resources', 'app', 'out', 'cli.js');
  if (!io.existsSync(script) && typeof io.readFileSync === 'function') {
    const launcher = path.join(base, 'bin', 'code.cmd');
    if (io.existsSync(launcher)) {
      const source = io.readFileSync(launcher, 'utf8');
      const tag = source.length <= 16384 && /"%~dp0\.\.\\([a-f0-9]{6,40})\\resources\\app\\out\\cli\.js"/i.exec(source)?.[1];
      if (tag) {
        if (io.existsSync(path.join(base, tag, 'data'))) throw Error('Versioned IDE has portable data; refusing another profile principal');
        script = path.join(base, tag, 'resources', 'app', 'out', 'cli.js');
      }
    }
  }
  return { executable, cli: required(script, io) };
}
function request(state, method, route) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port: state.port, path: route, method,
      headers: { Host: `127.0.0.1:${state.port}`, Authorization: `Bearer ${state.token}`, 'Content-Length': '0' }, timeout: 3000 }, res => {
      let text = '';
      res.on('data', chunk => { text += chunk; if (text.length > 4096) res.destroy(Error('Oversized manager response')); });
      res.on('error', reject);
      res.on('end', () => { try { if (res.statusCode !== 200) throw Error('Manager rejected request'); resolve(JSON.parse(text)); } catch (e) { reject(e); } });
    });
    req.on('timeout', () => req.destroy(Error('Manager deadline'))); req.on('error', reject); req.end();
  });
}
async function existing(root, deps = {}) {
  const io = deps.fs || fs, file = path.join(root, 'Data', 'manager.json');
  if (!io.existsSync(file)) return null;
  const raw = Buffer.from(io.readFileSync(file));
  if (raw.length > 8192) throw Error('Invalid/stale manager state; manual inspection required');
  let state;
  try { state = JSON.parse(raw.toString('utf8')); } catch { throw Error('Invalid/stale manager state; manual inspection required'); }
  if (!validState(state, root, identity(root, io))) throw Error('Invalid/stale manager state; manual inspection required');
  let answer;
  try { answer = await (deps.request || request)(state, 'GET', '/status'); }
  catch {
    const error = Error('Stale/unreachable manager; guarded recovery required; no PID cleanup');
    error.code = 'MANAGER_UNREACHABLE'; error.snapshot = { raw, state }; throw error;
  }
  if (answer.root !== root || answer.rootId !== state.rootId || answer.managerNonce !== state.managerNonce) throw Error('Manager ownership mismatch');
  return { state, answer };
}
function gate(root, io = fs) {
  identity(root, io);
  required(path.join(root, 'Runtime', 'node', 'node.exe'), io);
}
async function spawnManager(root, deps = {}) {
  const io = deps.fs || fs;
  await (deps.prepareStorage || require('./prototype.cjs').prepareStorage)(root);
  const log = io.openSync(path.join(root, 'Data', 'manager.log'), 'a');
  try {
    const child = (deps.spawn || spawn)(path.join(root, 'Runtime', 'node', 'node.exe'),
      [path.join(root, 'App', 'runtime-cli.cjs'), 'manager', root],
      { cwd: root, env: environment(root), detached: true, windowsHide: true, shell: false, stdio: ['ignore', log, log] });
    await new Promise((resolve, reject) => { child.once('error', reject); child.once('spawn', resolve); });
    child.unref();
  } finally { io.closeSync(log); }
  const until = Date.now() + 15000;
  while (Date.now() < until) {
    if (io.existsSync(path.join(root, 'Data', 'manager.json'))) return existing(root, deps);
    await new Promise(r => setTimeout(r, 100));
  }
  throw Error('Manager startup deadline');
}
function recoveryFor(deps, io) {
  // Explicit dependency injection never invokes native host guards by accident.
  return deps.recovery || (io === fs ? require('./manager-recovery.cjs') : null);
}
async function ensure(root, deps = {}) {
  const io = deps.fs || fs;
  gate(root, io);
  let stale;
  try { const found = await existing(root, deps); if (found) return found; }
  catch (error) { if (error.code !== 'MANAGER_UNREACHABLE') throw error; stale = error; }
  const recovery = recoveryFor(deps, io);
  if (!recovery) { if (stale) throw stale; return spawnManager(root, deps); }
  const rootId = identity(root, io), startup = await recovery.acquireLease(root, 'startup', { rootId });
  let lifetime;
  try {
    stale = undefined;
    try { const winner = await existing(root, deps); if (winner) return winner; }
    catch (error) { if (error.code !== 'MANAGER_UNREACHABLE') throw error; stale = error; }
    lifetime = await recovery.acquireLease(root, 'manager', { rootId, timeoutMs: 5000 });
    // Proof and preservation happen while BOTH leases are held. An absent
    // marker also requires proof: an orphan QEMU must never be booted over.
    await recovery.recover(root, stale?.snapshot || { raw: null, state: null });
    await lifetime.close(); lifetime = null;
    // The startup lease remains held until the authenticated new state exists.
    return await spawnManager(root, deps);
  } finally { if (lifetime) await lifetime.close(); await startup.close(); }
}
async function ready(root, deps = {}) {
  let found = await ensure(root, deps);
  // Only a NEW explicit open that first observes shutdown requests a restart.
  // A stop received after this client's boot began remains a cancellation.
  let afterShutdown = ['stopping', 'stopped'].includes(found.answer.phase);
  const until = Date.now() + 20 * 60 * 1000;
  while ((found.answer.phase === 'booting' || (afterShutdown && ['stopping', 'stopped'].includes(found.answer.phase))) && Date.now() < until) {
    const nonce = found.state.managerNonce;
    await new Promise(r => setTimeout(r, 500)); found = await existing(root, deps);
    if (!found) {
      const io = deps.fs || fs, lastFile = path.join(root, 'Data', 'manager-last.json');
      let last; try { if (io.existsSync(lastFile)) last = JSON.parse(io.readFileSync(lastFile, 'utf8')); } catch {}
      if (afterShutdown && last?.root === root && last.rootId === identity(root, io) && last.managerNonce === nonce && last.phase === 'stopped') {
        found = await ensure(root, deps); afterShutdown = false; continue;
      }
      if (last?.root === root && last.rootId === identity(root, io) && last.managerNonce === nonce && last.phase === 'failed' && knownFailure(last.failureCode)) throw Error(failureMessages[last.failureCode]);
      throw Error('Manager ended before guest readiness; inspect private boot logs. No automatic restart.');
    }
  }
  if (knownFailure(found.answer.failureCode)) throw Error(failureMessages[found.answer.failureCode]);
  if (found.answer.phase !== 'ready') throw Error('Guest is not ready');
  return found;
}
function atomicStateWrite(file, value, io = fs, expected) {
  if (io.lstatSync) {
    const node = io.lstatSync(file, { throwIfNoEntry: false });
    if (node && (!node.isFile() || node.isSymbolicLink() || Number(node.nlink) !== 1)) throw Error('Manager state is not an ordinary single-link file');
  }
  if (expected) {
    const current = JSON.parse(io.readFileSync(file, 'utf8'));
    if (current.root !== expected.root || current.rootId !== expected.rootId || current.managerNonce !== expected.managerNonce)
      throw Error('Manager ownership changed; state left unchanged');
  } else if (io.existsSync(file)) throw Error('Manager state exists; another owner won');
  if (!io.renameSync) { io.writeFileSync(file, JSON.stringify(value), { mode: 0o600, ...(expected ? {} : { flag: 'wx' }) }); return; }
  const temp = path.join(path.dirname(file), '.manager-state-' + crypto.randomUUID() + '.json');
  io.writeFileSync(temp, JSON.stringify(value), { mode: 0o600, flag: 'wx' });
  try { io.renameSync(temp, file); } catch (error) { try { io.unlinkSync(temp); } catch {} throw error; }
}
async function manager(root, deps = {}) {
  const io = deps.fs || fs;
  gate(root, io);
  const recovery = recoveryFor(deps, io);
  if (!recovery) return managerOwned(root, deps);
  const lease = await recovery.acquireLease(root, 'manager', { rootId: identity(root, io), timeoutMs: 15000 });
  try { return await managerOwned(root, deps); } finally { await lease.close(); }
}
async function managerOwned(root, deps = {}) {
  const io = deps.fs || fs;
  gate(root, io);
  if (await existing(root, deps)) throw Error('Manager already owns this package');
  const prototype = deps.prototype || require('./prototype.cjs');
  const storage = await (deps.prepareStorage || prototype.prepareStorage)(root);
  const file = path.join(root, 'Data', 'manager.json');
  const state = { root, rootId: identity(root, io), token: crypto.randomBytes(32).toString('hex'),
    managerNonce: crypto.randomBytes(32).toString('hex'), port: 0, phase: 'booting' };
  let release, context, agentSession, claimed = false, generationOpen = true;
  const held = new Promise(r => { release = r; });
  const save = () => { if (!generationOpen) return; atomicStateWrite(file, state, io, claimed ? state : undefined); };
  const server = (deps.createServer || http.createServer)(async (req, res) => {
    const reply = (code, body) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(body)); };
    if (!authorized(req, state)) { reply(403, { error: 'Rejected' }); req.resume(); return; }
    const route = `${req.method} ${req.url}`;
    if (!['GET /status', 'POST /stop', 'POST /force-stop'].includes(route)) { reply(404, { error: 'Unknown route' }); req.resume(); return; }
    let size = 0;
    req.on('data', chunk => { size += chunk.length; if (size > 1024) req.destroy(); });
    req.on('end', async () => {
      if (size) return reply(400, { error: 'Body not supported' });
      try {
        if (route !== 'GET /status') {
          if (!context) return reply(409, { error: 'Guest control not ready' });
          state.phase = 'stopping'; save();
          if (route === 'POST /force-stop') await context.forceStop();
          else if (context.powerDown) await context.powerDown();
          release();
        }
        reply(200, publicState(state));
      } catch { reply(500, { error: 'Guest control failed' }); }
    });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  state.port = server.address().port;
  try { save(); claimed = true; }
  catch (error) { server.close(); throw error; } // Concurrent starters fail closed, before boot.
  try {
    const reduced = storage.protection === 'reduced';
    const prepared = await prototype.prepare(root, reduced ? { privateAgent: true } : {});
    if (prepared?.cfg?.sshPort) { state.activePorts = [prepared.cfg.sshPort, ...(prepared.portForwards || []).map(p => p.hostPort)]; save(); }
    if (reduced) {
      const agent = deps.privateAgent || require('./private-agent.cjs');
      agentSession = await agent.start(root, prepared.agentIdentity);
      agentSession.child.once('exit', () => {
        if (!['stopped','stopping','failed'].includes(state.phase)) { state.phase = 'failed'; state.failureCode = 'SSH_AGENT_UNAVAILABLE'; save(); }
      });
      await agent.verifyClient(root, agentSession.pipe, prepared.agentIdentity);
    }
    const bootOptions = { allowForce: false, onControl(ctx) { context = ctx; } };
    if (agentSession) { bootOptions.agentPipe = agentSession.pipe; bootOptions.agentPublicKey = prepared.pub; }
    if (storage.protection === 'reduced' || !prototype.bootstrapCurrent(root)) await prototype.boot(root, 'bootstrap', undefined, bootOptions);
    if (state.phase === 'stopping') { state.phase = 'stopped'; save(); return; }
    if (agentSession && !agentSession.isAlive()) throw Object.assign(Error('Private agent ended before runtime'), { code:'SSH_AGENT_UNAVAILABLE' });
    await prototype.boot(root, 'runtime', async ctx => {
      context = ctx;
      if (state.phase === 'stopping') return;
      if (agentSession && !agentSession.isAlive()) throw Object.assign(Error('Private agent ended before guest readiness'), { code:'SSH_AGENT_UNAVAILABLE' });
      ctx.child.once('exit', () => { state.phase = 'stopped'; save(); release(); });
      state.phase = 'ready'; save(); await held;
    }, bootOptions);
    state.phase = 'stopped'; save();
  } catch (error) {
    if (state.phase === 'stopping') { state.phase = 'stopped'; save(); }
    else { state.phase = 'failed'; if (knownFailure(error.code)) state.failureCode = error.code; save(); throw error; }
  }
  finally {
    if (agentSession) await agentSession.close();
    generationOpen = false;
    server.close();
    // A normal completed manager must not require manual JSON cleanup before
    // the next launch. Never remove a different manager's state or kill a PID.
    try {
      const current = JSON.parse(io.readFileSync(file, 'utf8'));
      if (current.managerNonce === state.managerNonce && current.rootId === state.rootId &&
          ['stopped', 'failed'].includes(state.phase)) {
        io.writeFileSync(path.join(root, 'Data', 'manager-last.json'), JSON.stringify(publicState(state)));
        io.unlinkSync(file);
      }
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}
function launch(executable, args, root, deps = {}, extra = {}) {
  return new Promise((resolve, reject) => {
    const child = (deps.spawn || spawn)(executable, args, { cwd: root, shell: false, windowsHide: true,
      env: environment(root), stdio: 'inherit', ...extra });
    child.once('error', reject); child.once('exit', code => resolve(code === null ? 1 : code));
  });
}
function interactiveTerminal(executable, args, root, deps = {}) {
  return new Promise((resolve, reject) => {
    const input = deps.stdin || process.stdin; const output = deps.stdout || process.stdout;
    const raw = input.isRaw;
    const child = (deps.spawn || spawn)(executable, args, { cwd: root, shell: false, windowsHide: true,
      env: environment(root), stdio: ['pipe', 'pipe', 'pipe'] });
    const filter = new TerminalFilter();
    const encoder = new TerminalInput(output);let cleaned=false;
    filter.pipe(output, { end: false });
    child.stdout.pipe(filter, { end: false }); child.stderr.pipe(filter, { end: false });
    if (input.isTTY) input.setRawMode(true);
    const resize=()=>encoder.resize(output);output.on('resize',resize);
    input.pipe(encoder).pipe(child.stdin);
    encoder.on('error',()=>child.stdin.end());
    child.stdin.on('error', () => {});
    function cleanup() { if(cleaned)return;cleaned=true;output.removeListener('resize',resize);input.unpipe(encoder);encoder.unpipe(child.stdin);encoder.destroy();if (input.isTTY) input.setRawMode(Boolean(raw)); input.pause(); }
    child.once('error', error => { cleanup(); filter.end(); reject(error); });
    child.once('close', code => { cleanup(); filter.end(); resolve(code === null ? 1 : code); });
  });
}
async function main(args = process.argv.slice(2), deps = {}) {
  const { command, root, project } = parse(args);
  if (command === 'manager') return manager(root, deps);
  if (['status', 'stop', 'force-stop'].includes(command)) {
    const found = await existing(root, deps);
    if (!found) throw Error('No manager');
    const answer = command === 'status' ? found.answer : await (deps.request || request)(found.state, 'POST', `/${command}`);
    (deps.print || console.log)(JSON.stringify(publicState(answer))); return 0;
  }
  // Preflight host clients before starting any VM.
  const client = command === 'terminal' ? terminalCommand(root, deps.env, deps.fs) : codeCommand(deps.env, deps.fs);
  await (deps.ready || ready)(root, deps);
  if (command === 'terminal') return (deps.interactiveTerminal || interactiveTerminal)(client.executable, client.args, root, deps);
  const staged = (deps.stageWorkspace || ide.stageWorkspace)(root, project);
  const install = await launch(client.executable, [client.cli, ...staged.extensionArgs], root, deps,
    { env: { ...environment(root), ELECTRON_RUN_AS_NODE: '1' } });
  if (install !== 0) throw Error('Private Remote SSH extension install failed');
  return launch(client.executable, staged.openArgs, root, deps);
}
if (require.main === module) main().then(code => { process.exitCode = code || 0; }).catch(error => {
  console.error('Portable runtime operation failed: ' + error.message + '. No host-shell fallback.'); process.exitCode = 1;
});
module.exports = { parse, environment, identity, validState, authorized, publicState, terminalCommand, codeCommand,
  existing, gate, ensure, ready, manager, atomicStateWrite, launch, interactiveTerminal, main };

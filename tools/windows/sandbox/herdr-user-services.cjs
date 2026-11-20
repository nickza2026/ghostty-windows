'use strict';
// Linux user-service adapter. It owns only its child and receipts, never a
// discovered PID. This is a cooperative same-UID boundary, not a sandbox.
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const invocationPattern = /^[a-f0-9]{32}$/;

function hasEntry(file, io = fs) {
  return Boolean(io.lstatSync(file, { throwIfNoEntry: false }));
}

function regular(file, privateFile = false) {
  const s = fs.lstatSync(file);
  if (!s.isFile() || s.isSymbolicLink() || fs.realpathSync(file) !== file)
    throw Error('Expected a canonical regular file');
  if (privateFile && process.platform !== 'win32' && (s.uid !== process.geteuid() || (s.mode & 0o077)))
    throw Error('Expected an owner-private file');
  return s;
}
function directory(dir, privateDirectory = false) {
  const s = fs.lstatSync(dir);
  if (!s.isDirectory() || s.isSymbolicLink() || fs.realpathSync(dir) !== dir)
    throw Error('Expected a canonical directory');
  if (privateDirectory && process.platform !== 'win32' && (s.uid !== process.geteuid() || (s.mode & 0o077)))
    throw Error('Expected an owner-private directory');
  return s;
}
function validateConfig(c) {
  if (!c || typeof c !== 'object' || Array.isArray(c)) throw Error('Invalid service configuration');
  for (const k of ['home', 'repo', 'node', 'bun', 'native', 'stateRoot', 'nativeConfig', 'managedNativeConfig'])
    if (typeof c[k] !== 'string' || !path.isAbsolute(c[k]) || path.resolve(c[k]) !== c[k] || /[\0\r\n]/.test(c[k]))
      throw Error('Service paths must be explicit, absolute and canonical');
  if (!Number.isSafeInteger(c.hostPort) || c.hostPort < 1024 || c.hostPort > 65535) throw Error('Invalid host port');
  if (c.nativeConfig === c.managedNativeConfig || path.dirname(c.nativeConfig) !== path.dirname(c.managedNativeConfig))
    throw Error('Managed native configuration must be a separate file in the original directory');
  directory(c.home); directory(c.repo); directory(c.stateRoot, true); directory(path.dirname(c.nativeConfig));
  for (const k of ['node', 'bun', 'native']) regular(c[k]);
  regular(c.nativeConfig);
  if (!fs.existsSync(path.join(c.repo, 'scripts/run-local.ts'))) throw Error('Source-native launcher missing');
  return c;
}
function childEnvironment(c, source = process.env) {
  const p = path.posix;
  const env = {
    HOME: c.home, USER: p.basename(c.home), LOGNAME: p.basename(c.home),
    XDG_CONFIG_HOME: p.join(c.home, '.config'), XDG_DATA_HOME: p.join(c.home, '.local/share'),
    XDG_CACHE_HOME: p.join(c.home, '.cache'), LANG: 'C.UTF-8', LC_ALL: 'C.UTF-8', TERM: 'dumb',
    PATH: [...new Set([p.dirname(c.node), p.dirname(c.bun), p.dirname(c.native), p.join(c.home, '.local/bin'), '/usr/local/bin', '/usr/bin', '/bin'])].join(':'),
  };
  for (const k of ['NOTIFY_SOCKET', 'INVOCATION_ID', 'XDG_RUNTIME_DIR']) if (typeof source[k] === 'string') env[k] = source[k];
  return env;
}
function noResumeText(original) {
  if (typeof original !== 'string' || original.length > 1024 * 1024 || original.includes('\0')) throw Error('Invalid native configuration');
  const rows = original.split('\n'); let section = '', session = -1, key = -1;
  for (let i = 0; i < rows.length; i++) {
    if (/^\s*\[/.test(rows[i])) {
      section = rows[i].replace(/\s+#.*$/, '').trim();
      if (section === '[session]') { if (session >= 0) throw Error('Duplicate session section'); session = i; }
    }
    if (section === '[session]' && /^\s*resume_agents_on_restore\s*=/.test(rows[i])) {
      if (key >= 0) throw Error('Duplicate restore key'); key = i;
    }
  }
  if (key >= 0) rows[key] = 'resume_agents_on_restore = false';
  else if (session >= 0) rows.splice(session + 1, 0, 'resume_agents_on_restore = false');
  else rows.push('', '[session]', 'resume_agents_on_restore = false');
  return rows.join('\n');
}
const tomlVerifier = `const x=JSON.parse(await Bun.stdin.text());const a=Bun.TOML.parse(x.before),b=Bun.TOML.parse(x.after);const expected={...a,session:{...(a.session??{}),resume_agents_on_restore:false}};if(!Bun.deepEquals(b,expected))throw Error('Unexpected native configuration change');if(Bun.version!=='1.4.2')throw Error('Pinned Bun required');`;
function verifyNoResume(c, before, after, env) {
  const r = cp.spawnSync(c.bun, ['-e', tomlVerifier], { input: JSON.stringify({ before, after }), env, encoding: 'utf8', timeout: 10000, maxBuffer: 65536 });
  // Parser errors can include private configuration fragments. Never forward stderr.
  if (r.error || r.status !== 0) throw Error('Native configuration semantic verification failed; originals unchanged');
}
function atomicPrivate(file, bytes) {
  directory(path.dirname(file));
  if (hasEntry(file)) regular(file, true);
  const temp = path.join(path.dirname(file), '.' + path.basename(file) + '-' + crypto.randomUUID());
  fs.writeFileSync(temp, bytes, { flag: 'wx', mode: 0o600 });
  try { fs.renameSync(temp, file); } catch (e) { fs.unlinkSync(temp); throw e; }
}
function managedNativeConfig(c, env) {
  const original = fs.readFileSync(c.nativeConfig, 'utf8'), next = noResumeText(original);
  verifyNoResume(c, original, next, env);
  const marker = c.managedNativeConfig + '.sandbox-owner.json';
  const targetExists = hasEntry(c.managedNativeConfig), markerExists = hasEntry(marker);
  if (targetExists !== markerExists) throw Error('Incomplete managed native configuration; preserve for inspection');
  if (targetExists) {
    regular(c.managedNativeConfig, true); regular(marker, true);
    const old = JSON.parse(fs.readFileSync(marker, 'utf8'));
    if (old.schema !== 1 || old.path !== c.managedNativeConfig || old.sha256 !== hash(fs.readFileSync(c.managedNativeConfig)))
      throw Error('Foreign or modified managed native configuration');
  }
  // A crash between these two renames fails closed on the next start, rather
  // than overwriting an unproven file. The original user configuration is untouched.
  atomicPrivate(c.managedNativeConfig, next);
  atomicPrivate(marker, JSON.stringify({ schema: 1, path: c.managedNativeConfig, sha256: hash(next) }));
  if (fs.readFileSync(c.nativeConfig, 'utf8') !== original) throw Error('Original native configuration changed concurrently');
  return c.managedNativeConfig;
}
function socketIdentity(file) {
  directory(path.dirname(file), true);
  const s = fs.lstatSync(file, { bigint: true });
  if (!s.isSocket() || s.isSymbolicLink() || s.uid !== BigInt(process.geteuid()) || (s.mode & 0o777n) !== 0o600n)
    throw Error('Expected an owner-private socket');
  return { path: file, dev: String(s.dev), ino: String(s.ino), ctimeNs: String(s.ctimeNs), uid: String(s.uid), mode: String(s.mode) };
}
function sameIdentity(a, b) {
  return ['path', 'dev', 'ino', 'ctimeNs', 'uid', 'mode'].every(k => a?.[k] === b?.[k]);
}
function connectStatus(file, timeout = 1000) {
  return new Promise((resolve, reject) => {
    let done = false; const socket = net.connect(file);
    const finish = (error, value) => { if (done) return; done = true; clearTimeout(timer); socket.destroy(); error ? reject(error) : resolve(value); };
    const timer = setTimeout(() => finish(Error('Socket probe deadline')), timeout);
    socket.once('connect', () => finish(null, 'live'));
    socket.once('error', e => e.code === 'ECONNREFUSED' ? finish(null, 'refused') : finish(Error('Socket probe failed: ' + e.code)));
  });
}
function receiptPath(stateRoot) { return path.join(stateRoot, 'web-owned.json'); }
function readReceipt(stateRoot) {
  const file = receiptPath(stateRoot); regular(file, true);
  const b = fs.readFileSync(file); if (b.length > 8192) throw Error('Invalid socket receipt');
  const r = JSON.parse(b);
  if (r.schema !== 1 || !invocationPattern.test(r.invocation)) throw Error('Invalid socket receipt');
  return r;
}
async function recoverOwnedSocket(file, stateRoot, invocation, probe = connectStatus) {
  if (!invocationPattern.test(invocation || '')) throw Error('Systemd invocation identity required');
  directory(stateRoot, true);
  const entry = fs.lstatSync(file, { throwIfNoEntry: false });
  if (!entry) return 'absent';
  if (entry.isSymbolicLink()) throw Error('Socket link refused');
  const before = socketIdentity(file), receipt = readReceipt(stateRoot);
  if (receipt.invocation === invocation || !sameIdentity(receipt.identity, before)) throw Error('Socket ownership receipt does not match prior invocation');
  if (await probe(file) !== 'refused') throw Error('Existing socket is live; left unchanged');
  if (!sameIdentity(before, socketIdentity(file))) throw Error('Socket changed during recovery');
  const recovery = path.join(stateRoot, 'recovery');
  if (!hasEntry(recovery)) fs.mkdirSync(recovery, { mode: 0o700 });
  directory(recovery, true);
  const target = path.join(recovery, 'web-control-' + crypto.randomUUID() + '.sock');
  if (hasEntry(target)) throw Error('Recovery target occupied');
  fs.renameSync(file, target); // Preserve the dead node; never unlink an unknown node.
  return 'preserved';
}
function recordOwnedSocket(file, stateRoot, invocation) {
  directory(stateRoot, true);
  if (!invocationPattern.test(invocation || '')) throw Error('Systemd invocation identity required');
  const identity = socketIdentity(file), output = receiptPath(stateRoot);
  if (hasEntry(output) && readReceipt(stateRoot).identity?.path !== file)
    throw Error('Foreign socket receipt left unchanged');
  atomicPrivate(output, JSON.stringify({ schema: 1, invocation, identity }));
  return identity;
}
function pingNative(file, timeout = 1000) {
  return new Promise((resolve, reject) => {
    let done = false, bytes = Buffer.alloc(0); const socket = net.connect(file);
    const finish = (error, value) => { if (done) return; done = true; clearTimeout(timer); socket.destroy(); error ? reject(error) : resolve(value); };
    const timer = setTimeout(() => finish(Error('Native ping deadline')), timeout);
    socket.once('connect', () => socket.write(JSON.stringify({ id: 'service-ready', method: 'ping', params: {} }) + '\n'));
    socket.on('data', b => {
      if (done) return;
      if (bytes.length + b.length > 65536) return finish(Error('Native ping response exceeds limit'));
      bytes = Buffer.concat([bytes, b]); const end = bytes.indexOf(10); if (end < 0) return;
      let frame; try { frame = JSON.parse(bytes.subarray(0, end).toString('utf8')); } catch { return finish(Error('Malformed native ping response')); }
      if (frame?.id !== 'service-ready' || frame?.error || frame?.result?.version !== '0.9.5' || frame?.result?.protocol !== 22) {
        const e = Error('Unexpected native ping identity'); e.code = 'NATIVE_IDENTITY'; return finish(e);
      }
      finish(null, { version: frame.result.version, protocol: frame.result.protocol });
    });
    socket.once('error', e => finish(Error('Native socket unavailable: ' + e.code)));
    socket.once('end', () => finish(Error('Native ping closed before response')));
  });
}
async function waitNative(file, isAlive = () => true, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline && isAlive()) {
    try { return await pingNative(file, Math.min(1000, deadline - Date.now())); }
    catch (e) { if (e.code === 'NATIVE_IDENTITY') throw e; }
    await sleep(200);
  }
  throw Error('Native readiness deadline or child exit');
}
function readinessBanner(line, port) {
  return line.startsWith('Herdr source-native app ready at http://127.0.0.1:' + port + ' ')
    && line.includes('explicit VM host-loopback forward');
}
function notifier(env) {
  if (!env.NOTIFY_SOCKET) throw Error('Systemd notify socket required');
  const r = cp.spawnSync('/usr/bin/systemd-notify', ['--ready'], { env, stdio: 'ignore', timeout: 5000 });
  if (r.error || r.status !== 0) throw Error('Systemd readiness notification failed');
}
async function run(mode, c, source = process.env) {
  if (process.platform !== 'linux' || !['native', 'web'].includes(mode)) throw Error('Linux native|web user service required');
  validateConfig(c);
  const env = childEnvironment(c, source), invocation = env.INVOCATION_ID;
  if (!invocationPattern.test(invocation || '') || !env.NOTIFY_SOCKET) throw Error('Run through the installed systemd user unit');
  const nativeSocket = path.join(c.home, '.config/herdr/herdr.sock');
  const webSocket = path.join(c.repo, '.agent-state/runtime/upstream-v10700/web-control.sock');
  if (mode === 'native') {
    if (fs.lstatSync(nativeSocket, { throwIfNoEntry: false })) {
      socketIdentity(nativeSocket);
      if (await connectStatus(nativeSocket) !== 'refused') throw Error('Existing native server left unchanged');
    }
    env.HERDR_CONFIG_PATH = managedNativeConfig(c, env);
  }
  else { await waitNative(nativeSocket); await recoverOwnedSocket(webSocket, c.stateRoot, invocation); }
  const command = mode === 'native' ? c.native : c.bun;
  const args = mode === 'native' ? ['server'] : ['start', '--runtime=herdr', '--vm-forward=' + c.hostPort];
  const child = cp.spawn(command, args, { cwd: c.repo, env, detached: false, stdio: ['ignore', 'pipe', 'inherit'] });
  let alive = true, stopping = false, buffer = '', ready = false, owned = false, startupError;
  let resolveReady, rejectReady;
  const readyPromise = new Promise((resolve, reject) => { resolveReady = resolve; rejectReady = reject; });
  // Native mode uses RPC, so prevent an unused promise rejection in that mode.
  readyPromise.catch(() => {});
  const stopped = new Promise((resolve, reject) => {
    child.once('error', e => { alive = false; rejectReady(e); reject(e); });
    child.once('close', (code, signal) => {
      alive = false; rejectReady(Error('Child exited before readiness'));
      resolve(stopping ? 0 : code === 0 ? 0 : 1);
    });
  });
  stopped.catch(() => {});
  const stop = signal => { if (stopping) return; stopping = true; if (alive) child.kill(signal); };
  const onTerm = () => stop('SIGTERM'), onInt = () => stop('SIGINT');
  process.on('SIGTERM', onTerm); process.on('SIGINT', onInt);
  function capture() {
    if (mode !== 'web' || owned || !alive) return;
    const node = fs.lstatSync(webSocket, { throwIfNoEntry: false });
    if (!node) return;
    // The launcher creates then chmods its socket. Wait for that transition,
    // never accept a regular file or a linked replacement.
    if (!node.isSocket() || node.isSymbolicLink()) throw Error('Unexpected Web control node');
    if ((node.mode & 0o777) !== 0o600) return;
    recordOwnedSocket(webSocket, c.stateRoot, invocation); owned = true;
    if (captureTimer) clearInterval(captureTimer);
  }
  child.stdout.on('data', b => {
    process.stdout.write(b);
    if (mode !== 'web' || ready) return;
    buffer += b.toString('utf8');
    if (buffer.length > 65536) buffer = buffer.slice(-8192);
    let end;
    while ((end = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, end).replace(/\r$/, ''); buffer = buffer.slice(end + 1);
      if (readinessBanner(line, c.hostPort)) {
        try { capture(); if (!owned) throw Error('Fresh Web control receipt required'); ready = true; resolveReady(); }
        catch (e) { startupError = e; rejectReady(e); stop('SIGTERM'); }
      }
    }
  });
  const captureTimer = mode === 'web' ? setInterval(() => {
    try { capture(); } catch (e) { startupError = e; rejectReady(e); stop('SIGTERM'); }
  }, 50) : null;
  let deadline;
  try {
    if (mode === 'native') await waitNative(nativeSocket, () => alive);
    else await Promise.race([readyPromise, new Promise((_, reject) => { deadline = setTimeout(() => reject(Error('Web startup deadline')), 180000); })]);
    if (startupError) throw startupError;
    notifier(env);
    return await stopped;
  } catch (e) {
    stop('SIGTERM'); throw e;
  } finally {
    if (captureTimer) clearInterval(captureTimer); if (deadline) clearTimeout(deadline);
    process.off('SIGTERM', onTerm); process.off('SIGINT', onInt);
  }
}
async function main(args = process.argv.slice(2)) {
  if (args.length !== 2 || !['native', 'web'].includes(args[0]) || !path.isAbsolute(args[1])) throw Error('Usage: node herdr-user-services.cjs native|web /absolute/config.json');
  regular(args[1], true); const bytes = fs.readFileSync(args[1]); if (bytes.length > 16384) throw Error('Service configuration exceeds limit');
  return run(args[0], JSON.parse(bytes));
}
if (require.main === module) main().then(code => { process.exitCode = code; }).catch(e => { console.error('Herdr user service refused: ' + e.message); process.exitCode = 1; });
module.exports = { hasEntry, validateConfig, childEnvironment, noResumeText, verifyNoResume, managedNativeConfig,
  socketIdentity, sameIdentity, connectStatus, recoverOwnedSocket, recordOwnedSocket,
  pingNative, waitNative, readinessBanner, run, main };

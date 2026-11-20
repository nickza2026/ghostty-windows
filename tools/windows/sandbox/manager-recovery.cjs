'use strict';
// Exclusion is not authentication. The caller retains both documented leases
// while recovery runs; neither a PID nor the existence of a file grants a lease.
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const storage = require('./storage-policy.cjs');
const MAX_STATE = 8192;
const token = /^[a-f0-9]{64}$/;
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');

function rootIdentity(root, io = fs) {
  const owner = JSON.parse(io.readFileSync(path.join(root, 'sandbox-owned.json'), 'utf8'));
  if (owner?.name !== 'ghostty-sandbox-owned' || owner.schema !== 1 || typeof owner.nonce !== 'string' ||
      owner.nonce.length < 16 || owner.nonce.length > 256 || /[\0\r\n]/.test(owner.nonce)) throw Error('Recovery package ownership is invalid');
  return owner.nonce;
}

function leaseName(root, scope, rootId, platform = process.platform) {
  if (!['startup', 'manager'].includes(scope)) throw Error('Unknown manager lease scope');
  if (platform !== 'win32') throw Error('Manager recovery leases require Windows');
  if (typeof rootId !== 'string' || rootId.length < 16 || rootId.length > 256 || /[\0\r\n]/.test(rootId)) throw Error('Invalid manager lease identity');
  const normalized = path.win32.resolve(root).toLowerCase();
  return '\\\\.\\pipe\\ghostty-sandbox-lease-' + scope + '-' + sha256(JSON.stringify([normalized, rootId]));
}

async function acquireLease(root, scope, options = {}) {
  const platform = options.platform || process.platform;
  const rootId = options.rootId || rootIdentity(root);
  const address = leaseName(root, scope, rootId, platform);
  const timeoutMs = options.timeoutMs ?? 45000;
  if (!Number.isInteger(timeoutMs) || timeoutMs < 0 || timeoutMs > 120000) throw Error('Invalid manager lease deadline');
  const createServer = options.createServer || net.createServer;
  const now = options.now || Date.now;
  const sleep = options.sleep || (ms => new Promise(resolve => setTimeout(resolve, ms)));
  const deadline = now() + timeoutMs;
  while (true) {
    const server = createServer(socket => { socket.once('error', () => {}); socket.destroy(); });
    server.maxConnections = 4;
    const listening = await new Promise((resolve, reject) => {
      const onError = error => { server.removeListener('listening', onListening); resolve(error); };
      const onListening = () => { server.removeListener('error', onError); resolve(null); };
      server.once('error', onError); server.once('listening', onListening);
      try { server.listen({ path: address, exclusive: true }); } catch (error) { server.removeListener('error', onError); server.removeListener('listening', onListening); reject(error); }
    });
    if (!listening) {
      let closed;
      return { address, close() {
        if (!closed) closed = new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
        return closed;
      } };
    }
    // A failed listen owns no endpoint. Never unlink a pipe or reclaim a PID.
    if (!['EADDRINUSE', 'EBUSY'].includes(listening.code)) {
      const error = Error('Manager lease could not be verified'); error.code = listening.code; throw error;
    }
    if (now() >= deadline) {
      const error = Error('Another startup or manager still owns this package; wait and reopen Sandbox.exe'); error.code = 'MANAGER_LEASE_BUSY'; throw error;
    }
    await sleep(Math.min(100, Math.max(1, deadline - now())));
  }
}

function regular(file, io = fs) {
  const stat = io.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || Number(stat.nlink) !== 1) throw Error('Recovery requires an ordinary single-link file');
  for (let part = path.dirname(file); ; part = path.dirname(part)) {
    const parent = io.lstatSync(part);
    if (!parent.isDirectory() || parent.isSymbolicLink()) throw Error('Recovery path has an unsafe ancestor');
    if (path.dirname(part) === part) break;
  }
  const fold = value => process.platform === 'win32' ? value.toLowerCase() : value;
  if (fold(io.realpathSync(file)) !== fold(path.resolve(file))) throw Error('Recovery path is not canonical');
  return stat;
}

function validateSnapshot(root, snapshot, io = fs) {
  if (!snapshot || (!Buffer.isBuffer(snapshot.raw) && typeof snapshot.raw !== 'string')) throw Error('Recovery needs exact original state bytes');
  const raw = Buffer.from(snapshot.raw);
  if (!raw.length || raw.length > MAX_STATE) throw Error('Recovery manager state exceeds its supported size');
  let state; try { state = JSON.parse(raw.toString('utf8')); } catch { throw Error('Invalid manager state cannot be automatically recovered'); }
  const rootId = rootIdentity(root, io);
  if (!state || state.root !== root || state.rootId !== rootId || !token.test(state.token) || !token.test(state.managerNonce) ||
      !Number.isInteger(state.port) || state.port < 1 || state.port > 65535 || !['booting', 'ready', 'failed', 'stopping', 'stopped'].includes(state.phase))
    throw Error('Recovery manager ownership or state is invalid');
  if (!snapshot.state || snapshot.state.root !== state.root || snapshot.state.rootId !== state.rootId ||
      snapshot.state.managerNonce !== state.managerNonce || snapshot.state.token !== state.token || snapshot.state.port !== state.port || snapshot.state.phase !== state.phase)
    throw Error('Recovery snapshot does not match its original bytes');
  return { raw, state, rootId };
}

function proveAndArchive(root, snapshot, deps = {}) {
  const env = storage.environment(root, deps.source || process.env);
  const args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-File', path.join(__dirname, 'manager-recovery-proof.ps1'),
    '-Root', root, '-ClientPid', String(process.pid), '-ExpectedStateSha256', snapshot.raw === null ? '0'.repeat(64) : sha256(snapshot.raw), '-ExpectedRootId', snapshot.rootId];
  if (snapshot.raw === null) args.push('-NoState');
  const result = (deps.run || spawnSync)(path.join(env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'), args,
    { cwd: root, env, shell: false, windowsHide: true, encoding: 'utf8', timeout: 60000, maxBuffer: 65536 });
  // Do not forward arbitrary stderr: it can contain the old bearer-token JSON.
  if (result.error || result.status !== 0) {
    const known = /^RECOVERY_REFUSED: ([A-Z_]+)\s*$/m.exec(result.stderr || '');
    const error = Error('Automatic manager recovery was refused' + (known ? ': ' + known[1] : '; inspect the package recovery diagnostic'));
    error.code = 'MANAGER_RECOVERY_REFUSED'; throw error;
  }
  let answer; try { answer = JSON.parse(result.stdout.trim()); } catch { throw Error('No verified manager recovery result'); }
  return answer;
}

async function recover(root, original, deps = {}) {
  const io = deps.fs || fs;
  if (!path.isAbsolute(root) || path.resolve(root) !== root) throw Error('Recovery requires an absolute package root');
  if (original?.raw === null && original?.state === null) {
    const rootId = rootIdentity(root, io), file = path.join(root, 'Data/manager.json');
    regular(path.join(root, 'sandbox-owned.json'), io);
    if (io.lstatSync(file, { throwIfNoEntry: false })) throw Error('Manager state appeared before vacant-start proof');
    await (deps.prepareStorage || storage.prepare)(root);
    if (rootIdentity(root, io) !== rootId || io.lstatSync(file, { throwIfNoEntry: false })) throw Error('Package changed before vacant-start proof');
    const answer = await (deps.proveAndArchive || proveAndArchive)(root, { raw: null, state: null, rootId }, deps);
    if (answer?.vacant !== true || rootIdentity(root, io) !== rootId || io.lstatSync(file, { throwIfNoEntry: false })) throw Error('No verified vacant-start result');
    return { vacant: true };
  }
  const snapshot = validateSnapshot(root, original, io);
  const file = path.join(root, 'Data/manager.json');
  regular(path.join(root, 'sandbox-owned.json'), io);
  const stat = regular(file, io);
  if (stat.size > MAX_STATE || !Buffer.from(io.readFileSync(file)).equals(snapshot.raw)) throw Error('Manager state changed before recovery');
  await (deps.prepareStorage || storage.prepare)(root);
  if (rootIdentity(root, io) !== snapshot.rootId || !Buffer.from(io.readFileSync(file)).equals(snapshot.raw)) throw Error('Package changed during storage verification');
  const answer = await (deps.proveAndArchive || proveAndArchive)(root, snapshot, deps);
  if (answer?.recovered !== true || typeof answer.archive !== 'string' || !/^Data\/recovery\/[a-f0-9-]{36}\/manager\.json$/.test(answer.archive)) throw Error('Invalid manager recovery receipt');
  const archive = path.join(root, ...answer.archive.split('/'));
  regular(archive, io);
  if (!Buffer.from(io.readFileSync(archive)).equals(snapshot.raw)) throw Error('Preserved manager state does not match original bytes');
  if (io.lstatSync(file, { throwIfNoEntry: false })) throw Error('Manager state reappeared during recovery; no replacement attempted');
  return { recovered: true, archive: answer.archive };
}

module.exports = { acquireLease, leaseName, recover, proveAndArchive, validateSnapshot, MAX_STATE };

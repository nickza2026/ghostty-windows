'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { EventEmitter } = require('node:events');
const recovery = require('./manager-recovery.cjs');

function fixture(t) {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'sandbox-recovery-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'Data'));
  const state = { root, rootId: 'fixture-owned-package-12345678', token: 'a'.repeat(64), managerNonce: 'b'.repeat(64), port: 23456, phase: 'ready' };
  fs.writeFileSync(path.join(root, 'sandbox-owned.json'), JSON.stringify({ name: 'ghostty-sandbox-owned', schema: 1, nonce: state.rootId }));
  const raw = Buffer.from(JSON.stringify(state));
  fs.writeFileSync(path.join(root, 'Data/manager.json'), raw);
  return { root, state, raw, file: path.join(root, 'Data/manager.json') };
}
function archiveMock(f, calls) {
  return async (root, snapshot) => {
    calls.push('proof-and-archive'); assert.equal(root, f.root); assert(snapshot.raw.equals(f.raw));
    const relative = 'Data/recovery/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/manager.json';
    const file = path.join(root, ...relative.split('/')); fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.renameSync(f.file, file); return { recovered: true, archive: relative };
  };
}

test('lease names separate roles, normalize Windows casing and bind package identity', () => {
  const a = recovery.leaseName('D:\\fixture\\Package', 'startup', 'owned-package-nonce', 'win32');
  assert(a.startsWith('\\\\.\\pipe\\ghostty-sandbox-lease-startup-'));
  assert.equal(a, recovery.leaseName('d:\\FIXTURE\\package', 'startup', 'owned-package-nonce', 'win32'));
  assert.notEqual(a, recovery.leaseName('D:\\fixture\\Package', 'manager', 'owned-package-nonce', 'win32'));
  assert.notEqual(a, recovery.leaseName('D:\\fixture\\Package', 'startup', 'another-package-nonce', 'win32'));
  assert.throws(() => recovery.leaseName('x', 'unknown', 'owned-package-nonce', 'win32'), /scope/);
  assert.throws(() => recovery.leaseName('x', 'startup', 'owned-package-nonce', 'linux'), /Windows/);
});
test('missing marker still requires a positive vacant-start proof and no archive', async t => {
  const f = fixture(t), calls = []; fs.unlinkSync(f.file);
  const result = await recovery.recover(f.root, { raw: null, state: null }, {
    prepareStorage: async () => calls.push('storage'),
    proveAndArchive: async (root, snapshot) => { assert.equal(root, f.root); assert.equal(snapshot.raw, null); assert.equal(snapshot.rootId, f.state.rootId); calls.push('proof'); return { vacant: true }; }
  });
  assert.deepEqual(result, { vacant: true }); assert.deepEqual(calls, ['storage', 'proof']); assert(!fs.existsSync(f.file));
});
test('an orphan-owner refusal or newly appeared marker never becomes a fresh boot', async t => {
  const f = fixture(t); fs.unlinkSync(f.file);
  await assert.rejects(recovery.recover(f.root, { raw: null, state: null }, { prepareStorage: async () => {}, proveAndArchive: async () => { throw Error('Live QEMU'); } }), /Live QEMU/);
  await assert.rejects(recovery.recover(f.root, { raw: null, state: null }, { prepareStorage: async () => { fs.writeFileSync(f.file, f.raw); }, proveAndArchive: async () => { throw Error('must not run'); } }), /changed/);
  assert(fs.readFileSync(f.file).equals(f.raw));
});
test('lease waits for contention, never reclaims files or PIDs, and closes once', async () => {
  let attempts = 0, time = 0, closes = 0;
  const lease = await recovery.acquireLease('D:\\fixture', 'startup', { rootId: 'fixture-owned-nonce', platform: 'win32', timeoutMs: 1000,
    now: () => time, sleep: async ms => { time += ms; }, createServer() {
      const server = new EventEmitter(); server.listen = options => {
        assert(options.exclusive); assert(options.path.startsWith('\\\\.\\pipe\\'));
        queueMicrotask(() => ++attempts < 3 ? server.emit('error', Object.assign(Error('busy'), { code: 'EADDRINUSE' })) : server.emit('listening'));
      }; server.close = callback => { closes++; callback(); }; return server;
    } });
  assert.equal(attempts, 3); assert.equal(time, 200);
  await Promise.all([lease.close(), lease.close()]); assert.equal(closes, 1);
});
test('lease bounds unknown-owner waiting and never converts access denial to absence', async () => {
  for (const [code, expected] of [['EBUSY', 'MANAGER_LEASE_BUSY'], ['EACCES', 'EACCES']]) {
    let attempts = 0;
    await assert.rejects(recovery.acquireLease('D:\\fixture', 'manager', { rootId: 'fixture-owned-nonce', platform: 'win32', timeoutMs: 0,
      createServer() { const s = new EventEmitter(); s.listen = () => queueMicrotask(() => { attempts++; s.emit('error', Object.assign(Error('denied'), { code })); }); return s; } }), e => e.code === expected);
    assert.equal(attempts, 1);
  }
});
test('recovery preserves byte-exact state only through the proof-and-archive operation', async t => {
  const f = fixture(t), calls = [];
  const answer = await recovery.recover(f.root, f, { prepareStorage: async () => calls.push('storage'), proveAndArchive: archiveMock(f, calls) });
  assert.deepEqual(calls, ['storage', 'proof-and-archive']); assert(answer.recovered);
  assert(!fs.existsSync(f.file)); assert(fs.readFileSync(path.join(f.root, answer.archive)).equals(f.raw));
});
test('storage rejection leaves state in place without invoking proof', async t => {
  const f = fixture(t); let proofs = 0;
  await assert.rejects(recovery.recover(f.root, f, { prepareStorage: async () => { throw Error('unsupported storage'); }, proveAndArchive: async () => { proofs++; } }), /unsupported/);
  assert.equal(proofs, 0); assert(fs.readFileSync(f.file).equals(f.raw));
});
test('changed marker or package identity refuses before proof without mutations', async t => {
  for (const change of ['state', 'owner']) {
    const f = fixture(t); let proofs = 0;
    await assert.rejects(recovery.recover(f.root, f, { prepareStorage: async () => {
      if (change === 'state') fs.writeFileSync(f.file, JSON.stringify({ ...f.state, phase: 'failed' }));
      else fs.writeFileSync(path.join(f.root, 'sandbox-owned.json'), JSON.stringify({ name: 'ghostty-sandbox-owned', schema: 1, nonce: 'different-owned-nonce' }));
    }, proveAndArchive: async () => { proofs++; } }), /changed/);
    assert.equal(proofs, 0); assert(fs.existsSync(f.file));
  }
});
test('snapshot rejects malformed, oversized, wrong-root, wrong-owner and unknown phase', t => {
  const f = fixture(t);
  for (const raw of ['not JSON', 'x'.repeat(8193)]) assert.throws(() => recovery.validateSnapshot(f.root, { raw, state: f.state }), /Invalid|size/);
  for (const patch of [{ root: f.root + '-other' }, { rootId: 'other' }, { token: 'bad' }, { port: 0 }, { phase: 'unknown' }]) {
    const state = { ...f.state, ...patch }; assert.throws(() => recovery.validateSnapshot(f.root, { raw: JSON.stringify(state), state }), /invalid/);
  }
  assert.throws(() => recovery.validateSnapshot(f.root, { raw: f.raw, state: { ...f.state, managerNonce: 'c'.repeat(64) } }), /snapshot/);
});
test('multiple-link manager entries refuse before storage preparation', async t => {
  const f = fixture(t); let prepared = false;
  const io = { ...fs, lstatSync(file, options) { if (file === f.file) return { isFile: () => true, isSymbolicLink: () => false, nlink: 2 }; return fs.lstatSync(file, options); } };
  await assert.rejects(recovery.recover(f.root, f, { fs: io, prepareStorage: async () => { prepared = true; } }), /single-link/);
  assert.equal(prepared, false); assert(fs.readFileSync(f.file).equals(f.raw));
});
test('proof denial and malformed or escaping receipts never permit replacement', async t => {
  for (const answer of [null, {}, { recovered: true, archive: '../manager.json' }, { recovered: true, archive: 'Data/recovery/../../manager.json' }]) {
    const f = fixture(t);
    await assert.rejects(recovery.recover(f.root, f, { prepareStorage: async () => {}, proveAndArchive: async () => answer }), /receipt/);
    assert(fs.readFileSync(f.file).equals(f.raw));
  }
  const f = fixture(t);
  await assert.rejects(recovery.recover(f.root, f, { prepareStorage: async () => {}, proveAndArchive: async () => { throw Error('disk busy'); } }), /disk busy/);
  assert(fs.readFileSync(f.file).equals(f.raw));
});
test('archive mismatch or a new current marker is not silently accepted', async t => {
  for (const mismatch of [true, false]) {
    const f = fixture(t), calls = [], archive = archiveMock(f, calls);
    await assert.rejects(recovery.recover(f.root, f, { prepareStorage: async () => {}, proveAndArchive: async (...args) => {
      const answer = await archive(...args);
      fs.writeFileSync(mismatch ? path.join(f.root, answer.archive) : f.file, 'replacement'); return answer;
    } }), mismatch ? /Preserved/ : /reappeared/);
  }
});
test('proof subprocess uses pinned local script, explicit RemoteSigned and private environment', () => {
  const root = path.resolve('fixture'), snapshot = { raw: Buffer.from('original'), rootId: 'owned-package-nonce' };
  const result = recovery.proveAndArchive(root, snapshot, { source: { SystemRoot: 'C:\\Windows', SECRET_PROVIDER_KEY: 'not-inherited' }, run(exe, args, options) {
    assert(args.includes('RemoteSigned')); assert(!args.includes('Bypass')); assert.equal(args.at(-1), snapshot.rootId);
    assert(args.includes(path.join(__dirname, 'manager-recovery-proof.ps1'))); assert.equal(options.shell, false);
    assert.equal(options.env.SECRET_PROVIDER_KEY, undefined); assert.equal(options.env.TEMP, path.join(root, 'Data'));
    assert.equal(options.timeout, 60000); return { status: 0, stdout: '{"recovered":true,"archive":"Data/recovery/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/manager.json"}' };
  } });
  assert(result.recovered);
  assert.throws(() => recovery.proveAndArchive(root, snapshot, { run: () => ({ status: 1, stderr: 'private original state token=DO_NOT_EXPORT\nRECOVERY_REFUSED: LIVE_PACKAGE_QEMU\n' }) }), e => e.message.includes('LIVE_PACKAGE_QEMU') && !e.message.includes('DO_NOT_EXPORT'));
});
test('Windows proof source retains all guards and archives under held handles', () => {
  const s = fs.readFileSync(path.join(__dirname, 'manager-recovery-proof.ps1'), 'utf8');
  for (const required of ['GetFileInformationByHandle', 'Links -ne 1', 'Get-CimInstance Win32_Process', 'LIVE_PACKAGE_QEMU', 'LIVE_PACKAGE_NODE', 'ConnectionRefused', 'FileShare]::None', 'CORRUPT_OR_UNEXPECTED_DISK', 'STATE_IDENTITY_CHANGED', '[IO.File]::Move($statePath,$archive)', 'ARCHIVE_VERIFICATION_FAILED', '$held[$i].Dispose()']) assert(s.includes(required), required);
  assert(!/Stop-Process|taskkill|Remove-Item|ExecutionPolicy\s+Bypass/.test(s));
  assert(s.indexOf('foreach($p in $ports)') < s.indexOf('[IO.File]::Move($statePath,$archive)'));
  assert(s.indexOf('[IO.File]::Move($statePath,$archive)') < s.lastIndexOf('$held[$i].Dispose()'));
});

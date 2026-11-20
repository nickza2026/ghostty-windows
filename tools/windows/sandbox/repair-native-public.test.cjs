'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const { createPlan, applyPlan, validateSource, safePath } = require('./repair-native-public.cjs');
const repo = path.resolve(__dirname, '../../..'), out = path.join(repo, 'zig-out');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
function write(root, name, body) { const p = path.join(root, ...name.split('/')); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, body); }
function fixture() {
  const root = fs.mkdtempSync(path.join(out, 'repair-public-test-')), source = path.join(root, 'source'), target = path.join(root, 'target');
  fs.mkdirSync(source); fs.mkdirSync(target);
  const owner = n => JSON.stringify({ schema: 1, name: 'ghostty-sandbox-owned', nonce: n.repeat(32) });
  const publicFiles = {
    'sandbox-owned.json': owner('a'),
    'guest-profile.json': JSON.stringify({ schema: 1, profile: 'node', ports: [] }),
    'Sandbox.exe': 'synthetic new executable, never executed',
    'App/entry.cjs': "const policy=require('./policy.cjs'); module.exports={main:()=>policy};\n",
    'App/policy.cjs': "module.exports=require('./nested/helper.cjs');\n",
    'App/nested/helper.cjs': 'module.exports={synthetic:true};\n',
    'Runtime/node/node.exe': 'synthetic node, never executed',
    'Runtime/base/base.qcow2': 'synthetic immutable public backing image',
    'share/font.txt': 'synthetic font',
  };
  for (const [n, b] of Object.entries(publicFiles)) write(source, n, b);
  write(target, 'sandbox-owned.json', owner('b'));
  const receipt = { schema: 1, passed: true, dataIncluded: false, root: source,
    executableSha256: sha(publicFiles['Sandbox.exe']),
    files: Object.entries(publicFiles).map(([name, body]) => ({ name, bytes: Buffer.byteLength(body), sha256: sha(body) })) };
  const request = { receipt, targetRoot: target, filesystem: 'NTFS' };
  const backup = () => path.join(out, 'repair-public-backup-' + crypto.randomUUID());
  return { root, source, target, receipt, request, backup, publicFiles };
}
test('known rebuilt pkgconfig metadata needs exact old hashes and verified backups', async () => {
  const f = fixture(), allowedReplacements = {}, old = 'prefix=old-owned-build\n', newer = 'prefix=new-owned-build\n';
  const names = ['share/pkgconfig/libghostty-vt.pc', 'share/pkgconfig/libghostty-vt-static.pc'];
  for (const name of names) {
    write(f.source, name, newer); write(f.target, name, old);
    f.receipt.files.push({ name, bytes: Buffer.byteLength(newer), sha256: sha(newer) });
    allowedReplacements[name] = sha(old);
  }
  assert.equal((await createPlan(f.request)).blocks.length, 2);
  const request = { ...f.request, allowedReplacements }, plan = await createPlan(request);
  assert.deepEqual(plan.blocks, []);
  const backupRoot = f.backup(); await applyPlan(plan, { backupRoot });
  for (const name of names) {
    assert.equal(fs.readFileSync(path.join(f.target, name), 'utf8'), newer);
    assert.equal(fs.readFileSync(path.join(backupRoot, name), 'utf8'), old);
  }
  await assert.rejects(createPlan({ ...f.request, allowedReplacements: { 'share/user-work.pc': sha(old) } }), /Replacement authorization/);
});
test('minimal fixture fails module closure before repair; complete source installs all dependencies', async () => {
  const f = fixture();
  const missing = structuredClone(f.receipt);
  missing.files = missing.files.filter(x => !x.name.includes('policy.cjs'));
  fs.unlinkSync(path.join(f.source, 'App/policy.cjs'));
  await assert.rejects(validateSource(missing), /Missing backend module/);
  write(f.source, 'App/policy.cjs', f.publicFiles['App/policy.cjs']);
  write(f.target, 'App/entry.cjs', f.publicFiles['App/entry.cjs']);
  const plan = await createPlan(f.request);
  assert(plan.actions.some(a => a.name === 'App/policy.cjs'));
  assert.deepEqual(plan.blocks, []);
  const report = await applyPlan(plan, { backupRoot: f.backup() });
  assert(report.passed); assert(report.moduleClosure.includes('App/nested/helper.cjs'));
  assert.equal((await createPlan(f.request)).actions.length, 0);
});
test('identity, config, Data sentinel and unmanifested unique work are preserved', async () => {
  const f = fixture();
  write(f.target, 'guest-profile.json', JSON.stringify({ schema: 1, profile: 'node', ports: [{ hostPort: 25000, guestPort: 8787 }] }));
  write(f.target, 'portable-storage.json', JSON.stringify({ schema: 1, storageMode: 'strict' }));
  write(f.target, 'Data/guest.qcow2', 'synthetic user disk bytes');
  write(f.target, 'Data/user-work.txt', 'synthetic unique user work');
  write(f.target, 'App/extra-user-file.txt', 'synthetic unique extra');
  const names = ['sandbox-owned.json', 'guest-profile.json', 'portable-storage.json', 'Data/guest.qcow2', 'Data/user-work.txt', 'App/extra-user-file.txt'];
  const before = names.map(n => fs.readFileSync(path.join(f.target, n)));
  const plan = await createPlan(f.request); assert.deepEqual(plan.blocks, []);
  await applyPlan(plan, { backupRoot: f.backup() });
  names.forEach((n, i) => assert(fs.readFileSync(path.join(f.target, n)).equals(before[i])));
});
test('missing profile with any existing guest state blocks adoption without reading it', async () => {
  for (const n of ['vm.json', 'guest.qcow2', 'guest-setup.json']) {
    const f = fixture(); write(f.target, 'Data/' + n, 'not JSON; must not be read');
    const plan = await createPlan(f.request);
    assert(plan.blocks.some(b => /adoption/.test(b)));
    await assert.rejects(applyPlan(plan, { backupRoot: f.backup() }), /Blocked repair/);
    assert(!fs.existsSync(path.join(f.target, 'App')));
  }
});
test('manager presence blocks repair, no status/stop/PID action is taken', async () => {
  const f = fixture(); write(f.target, 'Data/manager.json', 'synthetic not-json');
  const plan = await createPlan(f.request); assert(plan.blocks.some(b => /manager state/.test(b)));
  await assert.rejects(applyPlan(plan, { backupRoot: f.backup() }), /Blocked/);
});
test('modified public code and existing backing images block instead of overwrite', async () => {
  const f = fixture(); write(f.target, 'App/policy.cjs', 'unique modified code'); write(f.target, 'Runtime/base/base.qcow2', 'unique existing backing');
  const plan = await createPlan(f.request);
  assert(plan.blocks.some(b => /Modified public file/.test(b))); assert(plan.blocks.some(b => /backing image/.test(b)));
  await assert.rejects(applyPlan(plan, { backupRoot: f.backup() }), /Blocked/);
  await assert.rejects(createPlan({ ...f.request, allowedReplacements: { 'Runtime/base/base.qcow2': sha('unique existing backing') } }), /limited/);
});
test('known old EXE/entry replacement has verified independent backups and does not mutate hardlinks', async () => {
  const f = fixture(); const old = { 'Sandbox.exe': 'synthetic old exe', 'App/entry.cjs': 'synthetic broken entry' };
  for (const [n, b] of Object.entries(old)) write(f.target, n, b);
  const linked = path.join(f.root, 'linked-old-exe'); fs.linkSync(path.join(f.target, 'Sandbox.exe'), linked);
  const plan = await createPlan({ ...f.request, allowedReplacements: Object.fromEntries(Object.entries(old).map(([n, b]) => [n, sha(b)])) });
  const backup = f.backup(), report = await applyPlan(plan, { backupRoot: backup }); assert(report.passed);
  for (const [n, b] of Object.entries(old)) assert.equal(fs.readFileSync(path.join(backup, n), 'utf8'), b);
  assert.equal(fs.readFileSync(linked, 'utf8'), old['Sandbox.exe']);
});
test('source tamper/unmanifested files/private paths and traversal are rejected', async () => {
  const f = fixture(); write(f.source, 'App/policy.cjs', 'tampered'); await assert.rejects(createPlan(f.request), /source hash mismatch/);
  write(f.source, 'App/policy.cjs', f.publicFiles['App/policy.cjs']); write(f.source, 'unexpected.txt', 'extra');
  await assert.rejects(createPlan(f.request), /Unmanifested/); fs.unlinkSync(path.join(f.source, 'unexpected.txt'));
  for (const n of ['../escape', 'Data/guest.qcow2', 'data/token', 'App/id_ed25519', 'App/.env', 'App/foo:stream', 'App/NUL.cjs', 'App/../other']) assert.throws(() => safePath(f.source, n));
  write(f.source, 'Data/unexpected', 'synthetic'); await assert.rejects(createPlan(f.request), /unbooted/);
});
test('source executable receipt and actual Node extensionless resolution are checked', async () => {
  const f = fixture();
  await assert.rejects(createPlan({ ...f.request, receipt: { ...f.receipt, executableSha256: '0'.repeat(64) } }), /executable receipt mismatch/);
  const body = "module.exports=require('./policy');\n";
  write(f.source, 'App/entry.cjs', body);
  const changed = structuredClone(f.receipt), entry = changed.files.find(f => f.name === 'App/entry.cjs');
  entry.sha256 = sha(body); entry.bytes = Buffer.byteLength(body);
  await assert.rejects(createPlan({ ...f.request, receipt: changed }), /Missing backend module/);
});
test('source and destination reparse ancestors are rejected without following them', async () => {
  const f = fixture(), sourceLink = path.join(f.root, 'source-link'), targetLink = path.join(f.root, 'target-link');
  fs.symlinkSync(f.source, sourceLink, process.platform === 'win32' ? 'junction' : 'dir');
  fs.symlinkSync(f.target, targetLink, process.platform === 'win32' ? 'junction' : 'dir');
  await assert.rejects(createPlan({ ...f.request, receipt: { ...f.receipt, root: sourceLink } }), /Reparse/);
  await assert.rejects(createPlan({ ...f.request, targetRoot: targetLink }), /Reparse/);
  fs.unlinkSync(sourceLink); fs.unlinkSync(targetLink);
});
test('stale target, protected config or source after planning fails before installation', async () => {
  for (const change of ['target', 'owner', 'source']) {
    const f = fixture(), plan = await createPlan(f.request);
    if (change === 'target') write(f.target, 'App/policy.cjs', 'new external edit');
    if (change === 'owner') write(f.target, 'sandbox-owned.json', JSON.stringify({ schema: 1, name: 'ghostty-sandbox-owned', nonce: 'c'.repeat(32) }));
    if (change === 'source') write(f.source, 'share/font.txt', 'tampered after plan');
    await assert.rejects(applyPlan(plan, { backupRoot: f.backup() }), /Stale|source hash mismatch/);
    assert(!fs.existsSync(path.join(f.target, 'Sandbox.exe')));
  }
});
test('simulated busy executable/install failure rolls back installed files and retains backups', async () => {
  const f = fixture(); write(f.target, 'Sandbox.exe', 'old exe');
  const request = { ...f.request, allowedReplacements: { 'Sandbox.exe': sha('old exe') } }, backup = f.backup();
  const plan = await createPlan(request); let thrown;
  try { await applyPlan(plan, { backupRoot: backup, beforeInstall(_name, count) { if (count === 3) { const e = Error('synthetic busy executable'); e.code = 'EPERM'; throw e; } } }); } catch (e) { thrown = e; }
  assert(thrown); assert.deepEqual(thrown.report.rollbackFailures, []);
  assert.equal(fs.readFileSync(path.join(f.target, 'Sandbox.exe'), 'utf8'), 'old exe');
  assert(!fs.existsSync(path.join(f.target, 'guest-profile.json')));
  assert(!fs.existsSync(path.join(f.target, 'App/entry.cjs')));
  assert.equal(fs.readFileSync(path.join(backup, 'Sandbox.exe'), 'utf8'), 'old exe');
});
test('external edit during install is preserved, rollback failure is explicit', async () => {
  const f = fixture(), plan = await createPlan(f.request); let first;
  await assert.rejects(applyPlan(plan, { backupRoot: f.backup(), beforeInstall(name, count) {
    if (count === 0) first = name;
    if (count === 1) { write(f.target, first, 'external change during install'); throw Error('synthetic failure'); }
  } }), e => e.report.rollbackFailures.includes(first));
  assert.equal(fs.readFileSync(path.join(f.target, first), 'utf8'), 'external change during install');
});
test('filesystem verification and explicit exFAT consent are mandatory, never created by repair', async () => {
  const f = fixture();
  for (const filesystem of [undefined, 'FAT32', 'exFAT']) assert((await createPlan({ ...f.request, filesystem })).blocks.some(b => /Filesystem/.test(b)));
  write(f.target, 'portable-storage.json', JSON.stringify({ schema: 1, storageMode: 'exfat-reduced-protection' }));
  const plan = await createPlan({ ...f.request, filesystem: 'exFAT' }); assert.deepEqual(plan.blocks, []);
  assert(!plan.actions.some(a => a.name === 'portable-storage.json'));
});
test('backup roots outside owned zig-out or existing roots are refused before writes', async () => {
  const f = fixture(), plan = await createPlan(f.request);
  for (const backupRoot of [f.root, path.join(repo, 'unapproved-backup'), f.target]) await assert.rejects(applyPlan(plan, { backupRoot }), /Fresh owned/);
});

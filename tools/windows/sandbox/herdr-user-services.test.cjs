'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), net = require('node:net');
const service = require('./herdr-user-services.cjs');
const posix = process.platform !== 'win32';
const a = 'a'.repeat(32), b = 'b'.repeat(32);
test('collision guard detects a dangling directory entry without following it', () => {
  const linked = { isSymbolicLink: () => true };
  const io = { existsSync: () => false, lstatSync: (p, options) => { assert.equal(options.throwIfNoEntry, false); return p === 'missing' ? undefined : linked; } };
  assert.equal(service.hasEntry('dangling', io), true);
  assert.equal(service.hasEntry('missing', io), false);
});
function fixture(t) {
  const dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'herdr-service-unit-')));
  fs.chmodSync(dir, 0o700); t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
async function socket(t, file, handler = () => {}) {
  const server = net.createServer(handler);
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(file, resolve); });
  fs.chmodSync(file, 0o600);
  t.after(() => { server.close(); });
  return server;
}
async function deadSocket(t, file) {
  const server = await socket(t, file), parked = file + '-parked';
  fs.renameSync(file, parked); await new Promise(resolve => server.close(resolve)); fs.renameSync(parked, file);
}
test('no-resume transformation preserves root and other-table keys', () => {
  const before = 'resume_agents_on_restore = "root value"\n[other]\nresume_agents_on_restore = "table value"\n[session]\nresume_agents_on_restore = true # old\nstartup_per_agent_delay_ms = 100\n';
  const after = service.noResumeText(before);
  assert(after.includes('resume_agents_on_restore = "root value"'));
  assert(after.includes('resume_agents_on_restore = "table value"'));
  assert(after.includes('[session]\nresume_agents_on_restore = false\nstartup_per_agent_delay_ms = 100'));
  assert.equal(service.noResumeText(after), after);
});
test('no-resume transformation creates only the missing session key or section', () => {
  assert.equal(service.noResumeText('[session]\nfoo = 1'), '[session]\nresume_agents_on_restore = false\nfoo = 1');
  assert.equal(service.noResumeText('foo = "preserved"'), 'foo = "preserved"\n\n[session]\nresume_agents_on_restore = false');
  assert.throws(() => service.noResumeText('[session]\n[session]\n'), /Duplicate/);
  assert.throws(() => service.noResumeText('[session]\nresume_agents_on_restore=true\nresume_agents_on_restore=false'), /Duplicate/);
  assert.throws(() => service.noResumeText('x\0'), /Invalid/);
});
test('child environment is explicit and does not import provider, test or Herdr overrides', () => {
  const c = { home: '/home/example', node: '/opt/node/bin/node', bun: '/home/example/.local/bin/bun', native: '/home/example/.local/bin/herdr' };
  const env = service.childEnvironment(c, { NOTIFY_SOCKET: '/run/user/123/notify', INVOCATION_ID: a, XDG_RUNTIME_DIR: '/run/user/123', OPENAI_API_KEY: 'fixture', NODE_OPTIONS: '--bad', HERDR_SOCKET: '/wrong', HOME: '/wrong', HERDR_TEST_MODE: 'native' });
  assert.equal(env.HOME, c.home); assert.equal(env.XDG_CONFIG_HOME, '/home/example/.config');
  assert(env.PATH.startsWith('/opt/node/bin:')); assert.equal(env.INVOCATION_ID, a);
  for (const k of ['OPENAI_API_KEY', 'NODE_OPTIONS', 'HERDR_SOCKET', 'HERDR_TEST_MODE']) assert.equal(env[k], undefined);
});
test('Web readiness requires the fresh exact host port and VM-forward banner', () => {
  const good = 'Herdr source-native app ready at http://127.0.0.1:18787 (native 0.9.5, protocol 22; explicit VM host-loopback forward)';
  assert(service.readinessBanner(good, 18787));
  assert(!service.readinessBanner(good, 18788));
  assert(!service.readinessBanner(good.replace('explicit VM host-loopback forward', 'private ingress'), 18787));
  assert(!service.readinessBanner('cached ' + good, 18787));
});
test('configuration rejects relative paths and unsupported ports before filesystem effects', () => {
  assert.throws(() => service.validateConfig({ home: 'relative' }), /explicit/);
  const c = Object.fromEntries(['home','repo','node','bun','native','stateRoot','nativeConfig','managedNativeConfig'].map(k => [k, path.resolve('fake-' + k)]));
  for (const port of [0, 1023, 65536, '18787', NaN]) assert.throws(() => service.validateConfig({ ...c, hostPort: port }), /port/);
  assert.throws(() => service.validateConfig({ ...c, hostPort: 18787, managedNativeConfig: c.nativeConfig }), /separate/);
});
test('actual pinned Bun verifies semantic equality and keeps original config unchanged', { skip: !process.env.HERDR_SERVICE_TEST_BUN }, t => {
  const dir = fixture(t), original = path.join(dir, 'config.toml'), target = path.join(dir, 'service.toml');
  fs.writeFileSync(original, 'title = "fixture"\n[session]\nresume_agents_on_restore=true\n[other]\nresume_agents_on_restore="untouched"\n', { mode: 0o600 });
  const c = { bun: fs.realpathSync(process.env.HERDR_SERVICE_TEST_BUN), nativeConfig: original, managedNativeConfig: target };
  const before = fs.readFileSync(original);
  service.managedNativeConfig(c, process.env); service.managedNativeConfig(c, process.env);
  assert(fs.readFileSync(original).equals(before)); assert(fs.readFileSync(target, 'utf8').includes('resume_agents_on_restore = false'));
  fs.appendFileSync(target, '\n# user edit'); assert.throws(() => service.managedNativeConfig(c, process.env), /modified/);
  const unsupported = 'text = """\n[session]\nresume_agents_on_restore=true\n"""\n';
  assert.throws(() => service.verifyNoResume(c, unsupported, service.noResumeText(unsupported), process.env), /semantic/);
});
for (const collision of ['config', 'marker']) test('managed native configuration preserves dangling ' + collision, { skip: !posix || !process.env.HERDR_SERVICE_TEST_BUN }, t => {
  const dir = fixture(t), original = path.join(dir, 'config.toml'), target = path.join(dir, 'managed.toml'), marker = target + '.sandbox-owner.json';
  fs.writeFileSync(original, 'title="fixture"\n', { mode: 0o600 });
  const blocked = collision === 'config' ? target : marker;
  fs.symlinkSync(path.join(dir, 'absent'), blocked);
  const c = { bun: fs.realpathSync(process.env.HERDR_SERVICE_TEST_BUN), nativeConfig: original, managedNativeConfig: target };
  assert.throws(() => service.managedNativeConfig(c, process.env), /Incomplete|canonical/);
  assert(fs.lstatSync(blocked).isSymbolicLink());
  assert.equal(fs.readFileSync(original, 'utf8'), 'title="fixture"\n');
  assert(!fs.existsSync(collision === 'config' ? marker : target));
});
test('owned-socket receipt preserves a dangling collision', { skip: !posix }, async t => {
  const dir = fixture(t), file = path.join(dir, 'web.sock'), state = path.join(dir, 'state'); fs.mkdirSync(state, { mode: 0o700 });
  await socket(t, file); const receipt = path.join(state, 'web-owned.json');
  fs.symlinkSync(path.join(dir, 'absent'), receipt);
  assert.throws(() => service.recordOwnedSocket(file, state, a), /canonical/);
  assert(fs.lstatSync(receipt).isSymbolicLink());
  assert(fs.lstatSync(file).isSocket());
});
test('unknown regular, linked, live and replaced Web nodes are never removed', { skip: !posix }, async t => {
  const dir = fixture(t), file = path.join(dir, 'web.sock'), state = path.join(dir, 'state'); fs.mkdirSync(state, { mode: 0o700 });
  fs.writeFileSync(file, 'owned user file', { mode: 0o600 });
  await assert.rejects(service.recoverOwnedSocket(file, state, b), /socket/); assert.equal(fs.readFileSync(file, 'utf8'), 'owned user file');
  fs.unlinkSync(file); fs.symlinkSync(path.join(dir, 'missing'), file);
  await assert.rejects(service.recoverOwnedSocket(file, state, b), /link/); assert(fs.lstatSync(file).isSymbolicLink()); fs.unlinkSync(file);
  await socket(t, file); service.recordOwnedSocket(file, state, a);
  await assert.rejects(service.recoverOwnedSocket(file, state, b), /live/); assert(fs.lstatSync(file).isSocket());
  await assert.rejects(service.recoverOwnedSocket(file, state, a), /prior invocation/);
  fs.renameSync(file, file + '-original'); fs.writeFileSync(file, 'replacement', { mode: 0o600 });
  await assert.rejects(service.recoverOwnedSocket(file, state, b), /socket/); assert.equal(fs.readFileSync(file, 'utf8'), 'replacement');
});
test('only an exact dead socket owned by a prior invocation is preserved by rename', { skip: !posix }, async t => {
  const dir = fixture(t), file = path.join(dir, 'web.sock'), state = path.join(dir, 'state'); fs.mkdirSync(state, { mode: 0o700 });
  await deadSocket(t, file);
  await assert.rejects(service.recoverOwnedSocket(file, state, b)); assert(fs.existsSync(file));
  service.recordOwnedSocket(file, state, a);
  assert.equal(await service.recoverOwnedSocket(file, state, b), 'preserved'); assert(!fs.existsSync(file));
  const saved = fs.readdirSync(path.join(state, 'recovery')); assert.equal(saved.length, 1); assert(fs.lstatSync(path.join(state, 'recovery', saved[0])).isSocket());
  assert.equal(await service.recoverOwnedSocket(file, state, b), 'absent');
});
test('changed socket receipt and a replacement during probe fail closed', { skip: !posix }, async t => {
  const dir = fixture(t), file = path.join(dir, 'web.sock'), state = path.join(dir, 'state'); fs.mkdirSync(state, { mode: 0o700 });
  await deadSocket(t, file); service.recordOwnedSocket(file, state, a);
  const receipt = path.join(state, 'web-owned.json'), value = JSON.parse(fs.readFileSync(receipt)); value.identity.ino = 'incorrect'; fs.writeFileSync(receipt, JSON.stringify(value));
  await assert.rejects(service.recoverOwnedSocket(file, state, b), /does not match/); assert(fs.existsSync(file));
  service.recordOwnedSocket(file, state, a);
  await assert.rejects(service.recoverOwnedSocket(file, state, b, async () => { fs.renameSync(file, file + '-old'); fs.writeFileSync(file, 'changed', { mode: 0o600 }); return 'refused'; }));
  assert.equal(fs.readFileSync(file, 'utf8'), 'changed');
});
test('native RPC readiness accepts only matching bounded protocol responses', { skip: !posix }, async t => {
  const dir = fixture(t), file = path.join(dir, 'native.sock');
  await socket(t, file, s => s.once('data', b => { const q = JSON.parse(b); assert.equal(q.method, 'ping'); s.end(JSON.stringify({ id: q.id, result: { version: '0.9.5', protocol: 22 } }) + '\n'); }));
  assert.deepEqual(await service.pingNative(file, 200), { version: '0.9.5', protocol: 22 });
});
for (const [name, output, expected] of [
  ['malformed', 'not JSON\n', /Malformed/],
  ['wrong identity', '{"id":"other","result":{"version":"0.9.5","protocol":22}}\n', /identity/],
  ['oversized', 'x'.repeat(65537), /limit/],
  ['partial', '{"id":', /deadline/],
]) test('native RPC rejects ' + name + ' without readiness', { skip: !posix }, async t => {
  const dir = fixture(t), file = path.join(dir, 'native.sock');
  await socket(t, file, s => { s.on('error', () => {}); s.once('data', () => s.write(output)); });
  await assert.rejects(service.pingNative(file, 100), expected);
});

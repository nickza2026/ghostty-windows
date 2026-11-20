'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { makeGuestFiles } = require('./guest-blueprint.cjs');
const key = Buffer.concat([Buffer.from([0, 0, 0, 11]), Buffer.from('ssh-ed25519'), Buffer.from([0, 0, 0, 32]), Buffer.alloc(32, 7)]).toString('base64');
const rules = '*filter\n:INPUT DROP [0:0]\n:FORWARD DROP [0:0]\n:OUTPUT DROP [0:0]\nCOMMIT\n';
const input = { instanceId: 'persistent-1', bootId: 'fresh-2', sshPublicKey: `ssh-ed25519 ${key}`, networkRulesV4: rules, networkRulesV6: rules };
const tools = { node: { url: 'https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz', version: '24.22.1', sha256: '6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6' }, herdr: { url: 'https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-linux-x86_64', version: '0.9.5', sha256: '14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d' }, lettaVersion: '0.34.23' };

test('guest has node-gyp native build prerequisites before unprivileged npm install', () => {
  const script = config(makeGuestFiles({ ...input, tools })).write_files.find(f => f.path === '/usr/local/sbin/portable-sandbox-boot').content;
  assert(script.includes("'build-essential'"));
  assert(script.includes("shutil.which('make')"));
  assert(script.includes("shutil.which('g++')"));
  assert(script.indexOf("setphase('build-prerequisites')") < script.indexOf("setphase('npm-install')"));
  assert(script.includes('safe[:8]+safe[-4:]'));
});
function config(files) { return JSON.parse(files['user-data'].slice('#cloud-config\n'.length)); }
test('pure API emits stage seed file and stable instance identity', () => {
  const files = makeGuestFiles(input);
  assert.deepEqual(Object.keys(files).sort(), ['PROFILE.TXT', 'BOOTID.TXT', 'STAGE.TXT', 'NET4.TXT', 'NET6.TXT', 'meta-data', 'user-data'].sort());
  assert.equal(files['STAGE.TXT'], 'bootstrap\n');
  assert.equal(makeGuestFiles({ ...input, stage: 'runtime' })['STAGE.TXT'], 'runtime\n');
  assert.throws(() => makeGuestFiles({ ...input, stage: 'other' }));
  assert.equal(files['BOOTID.TXT'], 'fresh-2\n');
  assert.equal(files['NET4.TXT'], rules);
  assert.equal(JSON.parse(files['meta-data'])['instance-id'], input.instanceId);
  assert.equal(config(files).portable_tools, null);
  assert.ok(Buffer.byteLength(files['user-data']) < 30 * 1024);
  assert.deepEqual(makeGuestFiles(input), files);
});
test('clean profile is explicit, strict and emits no SDK executable or environment', () => {
  assert.equal(makeGuestFiles(input)['PROFILE.TXT'], 'sdk\n');
  for (const guestProfile of [null, '', 'SDK', 'clean\n', {}, 1]) assert.throws(() => makeGuestFiles({ ...input, guestProfile }));
  const files = makeGuestFiles({ ...input, guestProfile: 'clean', stage: 'runtime' });
  assert.equal(files['PROFILE.TXT'], 'clean\n');
  const c = config(files);
  assert.equal(c.users[0].uid, 1000);
  assert.equal(c.users[0].sudo, false);
  assert.equal(c.portable_tools, null);
  assert.ok(!c.write_files.some(f => f.path === '/usr/local/bin/letta'));
  const script = c.write_files.find(f => f.path.endsWith('/portable-sandbox-boot')).content;
  assert.doesNotMatch(script, /apt-get|build-essential|npm|LETTA_HOME|urllib|def install\(|\/opt\/portable|unapproved tools|tool version mismatch/);
  assert.doesNotMatch(c.write_files.find(f => f.path.startsWith('/etc/profile.d/')).content, /npm|LETTA/);
  assert.ok(script.includes("marker('TOOLS_READY')"));
  assert.ok(script.includes("'-s','/bin/bash'"));
  assert.throws(() => makeGuestFiles({ ...input, guestProfile: 'clean', tools: { ...tools, lettaVersion: '*' } }));
});
test('all boot variants validate seed and recorded profile before bootstrap or unlock', () => {
  for (const guestProfile of ['sdk', 'clean', 'node']) {
    const c = config(makeGuestFiles({ ...input, guestProfile }));
    const script = c.write_files.find(f => f.path.endsWith('/portable-sandbox-boot')).content;
    for (const text of ["seed/'PROFILE.TXT'", "profile not in ('sdk','clean','node')", `if profile!='${guestProfile}':`, "recorded.read_text()!=profile", "legacy.exists() and profile!='sdk'", 'profile mismatch', 'legacy profile mismatch']) assert.ok(script.includes(text), text);
    assert.ok(script.indexOf("'-s','/usr/sbin/nologin'") < script.indexOf("seed/'PROFILE.TXT'"));
    assert.ok(script.indexOf('legacy profile mismatch') < script.indexOf("stage=='bootstrap'"));
    assert.ok(script.indexOf('profile mismatch') < script.indexOf("'-s','/bin/bash'"));
    assert.doesNotMatch(script, /rmtree|purge/);
  }
});
test('node baseline pins only Node and installs no SDK or apt packages', () => {
  const files = makeGuestFiles({ ...input, guestProfile: 'node' });
  assert.equal(files['PROFILE.TXT'], 'node\n');
  const c = config(files);
  assert.deepEqual(c.portable_tools, { node: tools.node });
  assert.deepEqual(config(makeGuestFiles({ ...input, guestProfile: 'node', tools: { node: tools.node } })).portable_tools, c.portable_tools);
  for (const invalid of [tools, {}, null, { node: { ...tools.node, version: '1.0.0' } }, { node: { ...tools.node, sha256: 'a'.repeat(64) } }, { node: { ...tools.node, url: 'http://example.invalid' } }]) assert.throws(() => makeGuestFiles({ ...input, guestProfile: 'node', tools: invalid }));
  const script = c.write_files.find(f => f.path.endsWith('/portable-sandbox-boot')).content;
  assert.doesNotMatch(script, /herdr|letta|LETTA|apt-get|build-essential|'git'|npm_config|npm-install|backend-local/);
  for (const text of ["if tools != APPROVED", "hashlib.sha256", "filter='data'", "if initial:\n        setphase('node-download')", "for name in ['node','npm','npx']", "for name in ['node','npm']", "node version mismatch", "manifest.chmod(0o600)"]) assert.ok(script.includes(text), text);
  assert.ok(!c.write_files.some(f => f.path === '/usr/local/bin/letta'));
  const login = c.write_files.find(f => f.path === '/etc/profile.d/portable-sandbox.sh').content;
  assert.match(login,/npm_config_prefix=\$HOME\/\.local/);
  assert.match(login,/npm_config_cache=\$HOME\/\.cache\/npm/);
  assert.doesNotMatch(login,/LETTA_HOME/);
  assert.equal(c.users[0].sudo, false);
  assert.equal(c.users[0].lock_passwd, true);
  assert.doesNotMatch(script, /passwd|chpasswd|rmtree|purge/);
});
test('fresh node and clean accounts accept only SHA512crypt and require password for sudo', () => {
  const digest = 'A'.repeat(86);
  const hashes = [`$6$salt$${digest}`, `$6$rounds=5000$./salt$${digest}`, `$6$rounds=1000000$salt$${digest}`];
  for (const guestProfile of ['node', 'clean']) {
    for (const guestPasswordHash of hashes) {
      const c = config(makeGuestFiles({ ...input, guestProfile, guestPasswordHash }));
      assert.equal(c.users[0].passwd, guestPasswordHash);
      assert.equal(c.users[0].lock_passwd, false);
      assert.equal(c.users[0].sudo, 'ALL=(ALL) ALL');
      assert.equal(c.ssh_pwauth, false);
      assert.equal(c.disable_root, true);
      const written = JSON.stringify(c.write_files);
      assert.ok(!written.includes(guestPasswordHash));
      assert.doesNotMatch(written, /NOPASSWD/);
      assert.match(c.write_files.find(f => f.path.includes('sshd_config.d')).content, /PermitRootLogin no\nPasswordAuthentication no/);
    }
    for (const guestPasswordHash of [null, 6, '', 'plaintext', hashes[0] + '\n', `$5$salt$${digest}`, `$6$rounds=4999$salt$${digest}`, `$6$rounds=1000001$salt$${digest}`, `$6$rounds=05000$salt$${digest}`, `$6$$${digest}`, `$6$${'s'.repeat(17)}$${digest}`, `$6$salt$${digest.slice(1)}`, `$6$salt$${'!'.repeat(86)}`]) assert.throws(() => makeGuestFiles({ ...input, guestProfile, guestPasswordHash }));
  }
  assert.throws(() => makeGuestFiles({ ...input, guestProfile: 'sdk', guestPasswordHash: hashes[0] }));
});
test('strict identifiers and public key wire format reject injection/private/options', () => {
  for (const instanceId of [undefined, null, '', 'a\nb', '../a', 'x;id']) assert.throws(() => makeGuestFiles({ ...input, instanceId }));
  for (const bootId of [undefined, null, '', 'a\nb', 'x y']) assert.throws(() => makeGuestFiles({ ...input, bootId }));
  for (const sshPublicKey of ['', 'PRIVATE KEY', input.sshPublicKey + '\n', 'command="id" ' + input.sshPublicKey, 'ssh-rsa ' + key, 'ssh-ed25519 ' + Buffer.alloc(51).toString('base64')]) assert.throws(() => makeGuestFiles({ ...input, sshPublicKey }));
});
test('pins require exact versions, HTTPS without credentials, and SHA256', () => {
  const c = config(makeGuestFiles({ ...input, tools }));
  assert.deepEqual(c.portable_tools, tools);
  for (const change of [{ url: 'http://example.invalid/a' }, { url: 'https://user:pass@example.invalid/a' }, { url: 'https://example.invalid/a\nb' }, { version: 'latest' }, { version: '1.2.3;id' }, { sha256: 'not-a-digest' }]) assert.throws(() => makeGuestFiles({ ...input, tools: { ...tools, node: { ...tools.node, ...change } } }));
  assert.throws(() => makeGuestFiles({ ...input, tools: { ...tools, lettaVersion: '*' } }));
  for (const networkRulesV4 of ['', '*filter\nCOMMIT', '*filter\n\0COMMIT\n']) assert.throws(() => makeGuestFiles({ ...input, networkRulesV4 }));
});
test('root ownership, failclosed network dependencies and bounded readonly seed mount', () => {
  const c = config(makeGuestFiles(input));
  const file = path => c.write_files.find(f => f.path === path);
  for (const f of c.write_files) { assert.equal(f.owner, 'root:root'); assert.ok(['0644', '0700', '0755'].includes(f.permissions)); }
  const fw = file('/usr/local/sbin/portable-sandbox-firewall').content;
  for (const text of ['seq 1 15', '/dev/disk/by-label/CIDATA', 'ro,nosuid,nodev,noexec', 'iptables-restore --test', 'ip6tables-restore --test']) assert.ok(fw.includes(text), text);
  assert.ok(fw.indexOf('ip6tables-restore --test') < fw.indexOf('iptables-restore <'));
  for (const name of ['ssh', 'networking', 'NetworkManager', 'systemd-networkd']) {
    const unit = file(`/etc/systemd/system/${name}.service.d/portable-sandbox.conf`).content;
    assert.match(unit, /Requires=portable-sandbox-firewall.service/);
    assert.match(unit, /After=portable-sandbox-firewall.service/);
  }
  assert.equal(c.users.length, 1);
  assert.equal(c.users[0].sudo, false);
  assert.deepEqual(c.users[0].groups, []);
  assert.equal(c.users[0].shell, '/usr/sbin/nologin');
  assert.equal(c.users[0].lock_passwd, true);
  assert.match(file('/etc/ssh/sshd_config.d/00-portable-sandbox.conf').content, /PermitRootLogin no\nPasswordAuthentication no/);
});
test('raw ELF role, bounded downloads, initial-only bootstrap and nonlogin CLI route', () => {
  const c = config(makeGuestFiles({ ...input, tools }));
  const script = c.write_files.find(f => f.path.endsWith('/portable-sandbox-boot')).content;
  for (const text of ["if pin != APPROVED[role]", "if role=='herdr':", 'bytes([127,69,76,70])', 'binary.chmod(0o755)', 'total>128*1024*1024', 'time.monotonic()>deadline', 'timeout=30', "filter='data'", 'initial=not manifest.exists()', 'manifest mismatch', "manifest.chmod(0o600)"]) assert.ok(script.includes(text), text);
  assert.match(script, /if initial:\n        setphase\('npm-install'\)\n        user\(\['npm','install'/);
  assert.match(script, /setphase\('apt-update'\)\n        run\(\['apt-get','update'/);
  assert.ok(script.indexOf('hashlib.sha256') < script.indexOf("if role=='herdr':"));
  assert.ok(script.indexOf("if role=='herdr':") < script.indexOf('with tarfile.open'));
  const wrapper = c.write_files.find(f => f.path === '/usr/local/bin/letta');
  assert.equal(wrapper.permissions, '0755');
  assert.equal(wrapper.content, '#!/bin/sh\nexec /home/sandbox/.local/bin/letta "$@"\n');
  for (const change of [{ url: 'https://example.invalid/node' }, { sha256: 'a'.repeat(64) }]) assert.throws(() => makeGuestFiles({ ...input, tools: { ...tools, node: { ...tools.node, ...change } } }));
});
test('each boot reads fresh stage/pins; bootstrap powers off before tools; runtime unlocks last', () => {
  const c = config(makeGuestFiles({ ...input, tools }));
  const script = c.write_files.find(f => f.path.endsWith('/portable-sandbox-boot')).content;
  for (const text of ["seed/'STAGE.TXT'", "stage=='bootstrap'", "stage!='runtime'", "seed/'BOOTID.TXT'", "seed/'user-data'", "hashlib.sha256", "filter='data'", "'runuser','-u','sandbox'", "'env','-i'", "'backend','local'", "marker('FAILED', phase+"]) assert.ok(script.includes(text), text);
  assert.ok(script.indexOf("['systemctl','poweroff']") < script.indexOf("['apt-get','update']"));
  assert.ok(script.indexOf("'backend','local'") < script.indexOf("'-s','/bin/bash'"));
  assert.ok(script.indexOf("'-s','/bin/bash'") < script.indexOf("marker('TOOLS_READY')"));
  assert.equal((script.match(/poweroff/g) || []).length, 1);
  assert.doesNotMatch(script, /shell=True|eval\(|herdr --session|sudo /);
});
test('fresh setup diagnostics are framed, phase-specific, private and bounded', () => {
  const c = config(makeGuestFiles({ ...input, tools }));
  const script = c.write_files.find(f => f.path.endsWith('/portable-sandbox-boot')).content;
  assert.equal(c.ssh_deletekeys, false);
  assert.ok(script.includes("out.write('\\nPORTABLE_SANDBOX '"));
  assert.ok(script.includes('out.flush()'));
  for (const phase of ['apt-update', 'apt-install', 'node-download', 'herdr-download', 'npm-install', 'backend-local', 'health']) assert.ok(script.includes(`setphase('${phase}')`));
  for (const text of ['LOG_LIMIT=1024*1024', '[-LOG_LIMIT:]', 'log.truncate()', 'os.O_NOFOLLOW', 'os.fchmod(fd, 0o600)', 'directory.chmod(0o700)', 'stderr=subprocess.STDOUT', 'len(safe)<=12 else safe[:8]+safe[-4:]', "'[REDACTED]'", "'[URL]'", '[:240]', 'raise SystemExit(1)', "type(error).__name__", "getattr(error, 'returncode', 1)"]) assert.ok(script.includes(text), text);
  assert.doesNotMatch(script, /journalctl|print\(os.environ|traceback/);
  assert.equal((script.match(/capture_setup=True/g) || []).length, 3);
  assert.ok(script.indexOf("directory=pathlib.Path('/var/log/portable-sandbox')") > script.indexOf('if initial:'));
});

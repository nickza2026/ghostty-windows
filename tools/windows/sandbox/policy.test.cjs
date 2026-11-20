'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { inside, firewall, qemuArgs, sshConfig, parseReady } = require('./policy.cjs');

test('paths fail closed on traversal, absolute paths, ADS and sibling prefixes', () => {
  const root = path.resolve('owned-sandbox');
  assert.equal(inside(root, 'Data/guest.qcow2'), path.join(root, 'Data/guest.qcow2'));
  for (const value of ['../other/key', '../owned-sandbox-evil/key', '/etc/passwd', 'Data/a:secret', ''])
    assert.throws(() => inside(root, value));
  assert.throws(() => inside('D:\\Owned', '..\\Other\\key', path.win32));
  assert.equal(inside('D:\\Owned', 'Data\\file', path.win32), 'D:\\Owned\\Data\\file');
});

test('network blocks guest initiated host/LAN access before public HTTP(S)', () => {
  const { v4, v6 } = firewall(['203.0.113.15']);
  assert.match(v4, /:OUTPUT DROP/);
  assert.match(v4, /--ctstate ESTABLISHED --ctdir REPLY/);
  assert(v4.indexOf('-d 10.0.0.0/8 -j REJECT') < v4.indexOf('--dports 80,443'));
  assert(v4.indexOf('-d 203.0.113.15/32 -j REJECT') < v4.indexOf('--dports 80,443'));
  assert.match(v6, /:OUTPUT DROP/);
  assert.throws(() => firewall(['127.0.0.1\nCOMMIT']));
  assert.throws(() => firewall(['::1']));
});

test('QEMU supports only WHPX and package disks, loopback SSH, no host shares', () => {
  const args = qemuArgs({ root: path.resolve('owned-sandbox'), sshPort: 42222, bootstrap: true });
  assert.equal(args[args.indexOf('-accel') + 1], 'whpx');
  const network = args[args.indexOf('-netdev') + 1];
  assert.match(network, /restrict=on/);
  assert.match(network, /hostfwd=tcp:127\.0\.0\.1:42222-10\.0\.2\.15:22/);
  assert(!args.some(x => /virtfs|fsdev|smb=|tftp=|spice|qemu-ga|tcg/.test(x)));
  assert.throws(() => qemuArgs({ root: path.resolve('owned'), sshPort: 22 }));
  assert.throws(() => qemuArgs({ root: path.resolve('owned'), sshPort: 42222, memoryMiB: 9000 }));
});

test('WHPX guest explicitly exposes the SSE4 features required by Bun without a KVM host model', () => {
  for (const bootstrap of [false, true]) {
    const args = qemuArgs({ root: path.resolve('owned-sandbox'), sshPort: 42222, bootstrap });
    const cpuIndex = args.indexOf('-cpu');
    assert.notEqual(cpuIndex, -1, 'QEMU default CPU hides host SSE4.2 from the guest');
    assert.equal(args[cpuIndex + 1], 'qemu64,+ssse3,+sse4.1,+sse4.2,enforce=on');
    assert.equal(args[args.indexOf('-accel') + 1], 'whpx');
  }
});

test('SSH never accepts unknown keys or host credentials/agent', () => {
  const cfg = sshConfig({ root: path.resolve('owned-sandbox'), sshPort: 42222 });
  for (const value of ['StrictHostKeyChecking yes', 'IdentityAgent none', 'ForwardAgent no',
    'ForwardX11 no', 'BatchMode yes', 'GlobalKnownHostsFile none']) assert(cfg.includes(value));
  assert(!cfg.includes('accept-new'));
});
test('private agent is explicit, public-only, unforwarded and never inherits the host agent',()=>{
  const pipe='\\\\.\\pipe\\ghostty-sbx-'+'a'.repeat(64),cfg=sshConfig({root:path.resolve('owned-sandbox'),sshPort:42222,agentPipe:pipe});
  assert(cfg.includes(`IdentityAgent "${pipe.replaceAll('\\','\\\\')}"`));assert(cfg.includes('client_key.pub"'));
  for(const required of ['IdentitiesOnly yes','AddKeysToAgent no','ForwardAgent no','StrictHostKeyChecking yes','PasswordAuthentication no'])assert(cfg.includes(required));
  for(const bad of ['none','\\\\.\\pipe\\openssh-ssh-agent','C:\\host-key','\\\\server\\pipe\\anything',pipe+'\nHost *'])assert.throws(()=>sshConfig({root:path.resolve('owned-sandbox'),sshPort:42222,agentPipe:bad}));
});

test('QEMU uses fixed ASCII package-relative filenames for Unicode root relocation', () => {
  const root = path.resolve("owned VM ภาษาไทย ย้าย'path");
  const args = qemuArgs({ root, sshPort: 42222 });
  const drives = args.filter((value, i) => args[i - 1] === '-drive');
  assert.equal(drives[0], 'file=Data/guest.qcow2,if=virtio,format=qcow2');
  assert.equal(drives[1], 'file=Data/seed.img,if=virtio,format=raw,readonly=on');
  assert.equal(args[args.indexOf('-serial') + 1], 'file:Data/current-console.log');
});

test('ready marker requires fresh boot identity, stage and unique public key', () => {
  const id = 'a'.repeat(32); const old = 'b'.repeat(32); const key = 'A'.repeat(68);
  const line = `PORTABLE_READY ${id} runtime ssh-ed25519 ${key}`;
  assert.equal(parseReady(line, id).stage, 'runtime');
  assert.equal(parseReady(line, old), null);
  assert.equal(parseReady(line + '\n' + line, id), null);
  assert.equal(parseReady(`PORTABLE_READY ${id} ready ssh-ed25519 ${key}`, id), null);
});

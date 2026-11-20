'use strict';

const path = require('node:path');
const net = require('node:net');

const PRIVATE_V4 = ['0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
  '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '224.0.0.0/4', '240.0.0.0/4'];

function fail(message) { throw new Error(message); }
function integer(value, min, max, label) {
  if (!Number.isSafeInteger(value) || value < min || value > max) fail(`Invalid ${label}`);
  return value;
}
function inside(root, relative, api = path) {
  if (typeof root !== 'string' || !api.isAbsolute(root) || typeof relative !== 'string' ||
      !relative || api.isAbsolute(relative) || /[\x00-\x1f:]/.test(relative)) fail('Unsafe package-relative path');
  const base = api.resolve(root);
  const result = api.resolve(base, relative);
  const fold = value => api === path.win32 || process.platform === 'win32' ? value.toLowerCase() : value;
  if (!fold(result).startsWith(fold(base + api.sep))) fail('Path escaped package');
  return result;
}

function ports(value = []) {
  if (!Array.isArray(value) || value.length > 8) fail('Invalid loopback port list');
  const host = new Set(), guest = new Set();
  return value.map(p => {
    if (!p || Object.keys(p).sort().join(',') !== 'guestPort,hostPort') fail('Invalid loopback mapping');
    integer(p.hostPort,1024,65535,'host port');integer(p.guestPort,1024,65535,'guest port');
    if(host.has(p.hostPort)||guest.has(p.guestPort))fail('Duplicate loopback mapping');host.add(p.hostPort);guest.add(p.guestPort);
    return {hostPort:p.hostPort,guestPort:p.guestPort};
  });
}
function firewall(hostAddresses = [], forwarded = []) {
  const mappings=ports(forwarded);
  if (!Array.isArray(hostAddresses) || hostAddresses.some(ip => net.isIP(ip) !== 4)) fail('Invalid host IPv4 list');
  const reject = [...new Set([...PRIVATE_V4, ...hostAddresses.map(ip => `${ip}/32`)])];
  const v4 = ['*filter', ':INPUT DROP [0:0]', ':FORWARD DROP [0:0]', ':OUTPUT DROP [0:0]',
    '-A INPUT -i lo -j ACCEPT', '-A OUTPUT -o lo -j ACCEPT',
    '-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT',
    '-A INPUT -p udp -s 10.0.2.2 --sport 67 --dport 68 -j ACCEPT',
    '-A INPUT -p tcp -d 10.0.2.15 --dport 22 -m conntrack --ctstate NEW -j ACCEPT',
    '-A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED --ctdir REPLY -j ACCEPT',
    ...mappings.flatMap(p=>[
      `-A INPUT -p tcp -s 10.0.2.2 -d 10.0.2.15 --dport ${p.guestPort} -m conntrack --ctstate NEW -j ACCEPT`,
      `-A OUTPUT -p tcp --sport ${p.guestPort} -m conntrack --ctstate ESTABLISHED --ctdir REPLY -j ACCEPT`
    ]),
    '-A OUTPUT -p udp --sport 68 --dport 67 -d 255.255.255.255 -j ACCEPT',
    '-A OUTPUT -p udp --sport 68 --dport 67 -d 10.0.2.2 -j ACCEPT',
    '-A OUTPUT -p udp -d 10.0.2.3 --dport 53 -j ACCEPT',
    '-A OUTPUT -p tcp -d 10.0.2.3 --dport 53 -j ACCEPT',
    ...reject.map(destination => `-A OUTPUT -d ${destination} -j REJECT`),
    '-A OUTPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT',
    'COMMIT', ''].join('\n');
  const v6 = ['*filter', ':INPUT DROP [0:0]', ':FORWARD DROP [0:0]', ':OUTPUT DROP [0:0]',
    '-A INPUT -i lo -j ACCEPT', '-A OUTPUT -o lo -j ACCEPT', 'COMMIT', ''].join('\n');
  return { v4, v6 };
}

function qemuArgs({ root, sshPort, bootstrap = false, memoryMiB = 3072, cpus = 2, portForwards = [] }) {
  integer(sshPort, 1024, 65535, 'SSH port');
  integer(memoryMiB, 2048, 4096, 'guest memory');
  integer(cpus, 1, 4, 'guest CPU count');
  if (typeof bootstrap !== 'boolean') fail('Bootstrap must be explicit boolean');
  const forwarded=ports(portForwards);if(forwarded.some(p=>p.hostPort===sshPort))fail('Dev port conflicts with SSH control port');
  // No shell, monitor TCP, guest agent, passthrough, host folders, clipboard,
  // SMB, TFTP, alternate accelerators, or arbitrary caller-supplied QEMU args.
  // The verified QEMU Windows build cannot open absolute Unicode filenames.
  // Caller MUST spawn with cwd=root (prototype.boot does). Validate confinement
  // but pass only these fixed ASCII names; never create global path aliases.
  const files = relative => { inside(root, relative); return relative; };
  // QEMU keyval escaping is separate from CreateProcess argument quoting.
  const keyval = value => value.replaceAll(',', ',,');
  const network = ['user', 'id=n0', 'ipv6=off', 'net=10.0.2.0/24', 'host=10.0.2.2',
    'dns=10.0.2.3', 'dhcpstart=10.0.2.15', bootstrap ? 'restrict=on' : 'restrict=off',
    `hostfwd=tcp:127.0.0.1:${sshPort}-10.0.2.15:22`,
    ...(bootstrap?[]:forwarded.map(p=>`hostfwd=tcp:127.0.0.1:${p.hostPort}-10.0.2.15:${p.guestPort}`))].join(',');
  // WHPX does not expose the host's SSE4 features through QEMU's default CPU.
  // Keep the existing qemu64 baseline, explicitly enable these host-checked
  // features, and fail rather than silently masking unsupported instructions.
  return ['-accel', 'whpx', '-machine', 'q35', '-cpu', 'qemu64,+ssse3,+sse4.1,+sse4.2,enforce=on', '-smp', String(cpus), '-m', String(memoryMiB),
    '-display', 'none', '-monitor', 'none', '-qmp', 'stdio', '-no-reboot',
    '-drive', `file=${keyval(files('Data/guest.qcow2'))},if=virtio,format=qcow2`,
    '-drive', `file=${keyval(files('Data/seed.img'))},if=virtio,format=raw,readonly=on`,
    '-netdev', network, '-device', 'virtio-net-pci,netdev=n0,mac=52:54:00:12:34:56',
    '-serial', `file:${files('Data/current-console.log')}`];
}

function sshConfig({ root, sshPort, username = 'sandbox', agentPipe }) {
  integer(sshPort, 1024, 65535, 'SSH port');
  if (username !== 'sandbox') fail('Unexpected guest user');
  if (agentPipe !== undefined && !require('./private-agent.cjs').validPipe(agentPipe)) fail('Invalid private agent endpoint');
  const quote = value => `"${value.replaceAll('\\', '/')}"`;
  return ['Host portable-sandbox', '  HostName 127.0.0.1', `  Port ${sshPort}`,
    `  User ${username}`, `  IdentityFile ${quote(inside(root, agentPipe ? 'Data/ssh/client_key.pub' : 'Data/ssh/client_key'))}`,
    `  UserKnownHostsFile ${quote(inside(root, 'Data/ssh/known_hosts'))}`,
    '  GlobalKnownHostsFile none', '  IdentitiesOnly yes', agentPipe ? `  IdentityAgent "${agentPipe.replaceAll('\\', '\\\\')}"` : '  IdentityAgent none', '  AddKeysToAgent no',
    '  ForwardAgent no', '  ForwardX11 no', '  PasswordAuthentication no',
    '  KbdInteractiveAuthentication no', '  BatchMode yes', '  StrictHostKeyChecking yes',
    '  ConnectTimeout 10', '  ServerAliveInterval 15', '  ServerAliveCountMax 3', ''].join('\n');
}

function parseReady(text, bootId) {
  if (!/^[a-f0-9]{32}$/.test(bootId)) fail('Invalid boot identity');
  const lines = text.split(/\r?\n/).filter(line => line.startsWith(`PORTABLE_READY ${bootId} `));
  if (lines.length !== 1) return null;
  const match = /^PORTABLE_READY ([a-f0-9]{32}) (bootstrap|runtime) (ssh-ed25519) ([A-Za-z0-9+/]{40,100}={0,2})$/.exec(lines[0]);
  return match ? { bootId: match[1], stage: match[2], hostKey: `${match[3]} ${match[4]}` } : null;
}

module.exports = { inside, firewall, qemuArgs, sshConfig, parseReady, ports };

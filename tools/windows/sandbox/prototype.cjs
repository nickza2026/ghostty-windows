'use strict';
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const net = require('node:net');
const readline = require('node:readline');
const { spawn, spawnSync } = require('node:child_process');
const { createSeed } = require('./fat-seed.cjs');
const { makeGuestFiles } = require('./guest-blueprint.cjs');
const { inside, firewall, qemuArgs, sshConfig } = require('./policy.cjs');
const { hashFile, sources } = require('./acquire.cjs');
const storage = require('./storage-policy.cjs');

const tools = {
  node: { version: '24.22.1', url: 'https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz',
    sha256: '6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6' },
  herdr: { version: '0.9.5', url: 'https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-linux-x86_64',
    sha256: '14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d' },
  lettaVersion: '0.34.23',
};
const nonce = () => crypto.randomBytes(16).toString('hex');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function diskIdentity(file) {
  const stat = fs.statSync(file, { bigint: true });
  return { fileId: stat.ino.toString(), createdNs: stat.birthtimeNs.toString() };
}
function bootstrapBound(record, expected) {
  return Boolean(record && /^[a-f0-9]{32}$/.test(record.bootId) &&
    record.instanceId === expected.instanceId && record.hostKey === expected.hostKey &&
    record.disk?.fileId === expected.disk.fileId && record.disk?.createdNs === expected.disk.createdNs);
}
function bootstrapCurrent(root) {
  const proof = inside(root, 'Data/bootstrap-verified.json');
  safeTree(proof);
  if (!fs.existsSync(proof)) return false;
  for (const file of ['Data/guest.qcow2', 'Data/vm.json', 'Data/ssh/trusted_host_key']) {
    safeTree(inside(root, file)); if (!fs.existsSync(inside(root, file))) return false;
  }
  const cfg = JSON.parse(fs.readFileSync(inside(root, 'Data/vm.json'), 'utf8'));
  const record = JSON.parse(fs.readFileSync(proof, 'utf8'));
  return bootstrapBound(record, { instanceId: cfg.instanceId,
    hostKey: fs.readFileSync(inside(root, 'Data/ssh/trusted_host_key'), 'utf8').trim(),
    disk: diskIdentity(inside(root, 'Data/guest.qcow2')) });
}
function prepareStorage(root) { return storage.prepare(root); }
function run(executable, args, options = {}) {
  const r = spawnSync(executable, args, { windowsHide: true, shell: false, encoding: 'utf8',
    timeout: 30000, maxBuffer: 2 * 1024 ** 2, ...options });
  if (r.error || r.status !== 0) throw new Error(`${path.basename(executable)} failed: ${r.error?.message || r.stderr || r.stdout || r.status}`);
  return r.stdout;
}
function safeTree(file) {
  for (let p = path.resolve(file); p; p = path.dirname(p)) {
    if (fs.existsSync(p) && fs.lstatSync(p).isSymbolicLink()) throw Error('Reparse/symlink path refused');
    if (p === path.dirname(p)) break;
  }
}
function guestMarkers(text, bootId) {
  if (!/^[a-f0-9]{32}$/.test(bootId)) throw Error('Invalid boot identity');
  const rows = text.split(/\r?\n/).filter(line => line.startsWith(`PORTABLE_SANDBOX ${bootId} `));
  const keys = rows.map(line => /^PORTABLE_SANDBOX [a-f0-9]{32} HOSTKEY (ssh-ed25519 [A-Za-z0-9+/]{40,100}={0,2})(?: .*)?$/.exec(line)).filter(Boolean);
  const bootstrap = rows.some(line => line.trimEnd() === `PORTABLE_SANDBOX ${bootId} BOOTSTRAP_READY`);
  const runtime = rows.some(line => line.trimEnd() === `PORTABLE_SANDBOX ${bootId} TOOLS_READY`);
  // getty may leave a login prompt without a newline on the same serial TTY.
  // Be permissive only for failure: never promote embedded text to readiness.
  const failure = new RegExp(`PORTABLE_SANDBOX ${bootId} (?:ERROR|FAILED)(?: |\\r|\\n|$)`).exec(text);
  return { hostKey: keys.length === 1 ? keys[0][1] : null, bootstrap, runtime,
    failed: Boolean(failure), failure: failure ? text.slice(failure.index).split(/[\r\n]/)[0].slice(0, 240) : null };
}
async function reservePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port; // QEMU must bind successfully; SSH still requires the pinned guest host key.
}
function localV4() {
  return Object.values(os.networkInterfaces()).flat().filter(a => a && a.family === 'IPv4').map(a => a.address);
}
function findProgram(root, name) {
  const direct = inside(root, `Runtime/qemu/${name}`);
  if (fs.existsSync(direct)) return direct;
  const found = [];
  function walk(dir, depth) {
    if (depth > 3) return;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name); safeTree(p);
      if (e.isDirectory()) walk(p, depth + 1);
      else if (e.isFile() && e.name.toLowerCase() === name) found.push(p);
    }
  }
  walk(inside(root, 'Runtime/qemu'), 0);
  if (found.length !== 1) throw Error(`No unique verified ${name}`);
  return found[0];
}
function sshPaths() {
  const base = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'OpenSSH');
  for (const name of ['ssh.exe', 'ssh-keygen.exe']) if (!fs.existsSync(path.join(base, name))) throw Error('Windows OpenSSH client unavailable; no host-PATH fallback');
  return { ssh: path.join(base, 'ssh.exe'), keygen: path.join(base, 'ssh-keygen.exe') };
}
function powerShellFileArgs(file, extra = []) {
  // Process scope only. Group Policy and RemoteSigned origin checks still apply.
  return ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-File', file, ...extra];
}
function checkClientKey(root, pub) {
  let derived;
  try {
    derived = run(sshPaths().keygen, ['-y', '-P', '', '-f', inside(root, 'Data/ssh/client_key')],
      { cwd: root, env: storage.environment(root), timeout: 15000, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    const failure = Error('Windows OpenSSH cannot load the portable private key on this storage; no key-check bypass or host-profile fallback. ' + error.message);
    failure.code = 'SSH_KEY_STORAGE_UNSUPPORTED'; throw failure;
  }
  const wire = value => value.trim().split(/\s+/).slice(0, 2).join(' ');
  if (wire(derived) !== wire(pub)) { const failure = Error('Portable SSH public/private key mismatch; no automatic key replacement'); failure.code = 'SSH_KEY_MISMATCH'; throw failure; }
}
async function prepare(root, options = {}) {
  safeTree(root);
  const ownership = JSON.parse(fs.readFileSync(path.join(root, 'sandbox-owned.json'), 'utf8'));
  if (ownership.name !== 'ghostty-sandbox-owned' || ownership.schema !== 1) throw Error('Not an owned prototype');
  const completed = fs.readdirSync(inside(root, 'Build')).filter(name => /^acquisition-.+-complete\.json$/.test(name));
  if (completed.length !== 1) throw Error('No unique completed verified acquisition; no partial-artifact launch');
  const acquired = JSON.parse(fs.readFileSync(inside(root, `Build/${completed[0]}`), 'utf8'));
  if (acquired.status !== 'complete') throw Error('Runtime acquisition incomplete');
  for (const name of ['qemu-system-x86_64.exe', 'qemu-img.exe']) {
    const pinned = acquired.binaries.filter(b => path.basename(b.file).toLowerCase() === name);
    if (pinned.length !== 1 || await hashFile(findProgram(root, name)) !== pinned[0].sha256) throw Error('Verified QEMU binary changed');
  }
  if (await hashFile(inside(root, 'Runtime/base/debian.qcow2'), 'sha512') !== sources[3].digest) throw Error('Guest base image digest changed');
  const data = inside(root, 'Data'), protection = prepareStorage(root);
  const guest = require('./guest-config.cjs'), selected = guest.profile(root);
  const guestPasswordHash = selected.profile === 'sdk' ? undefined : guest.passwordHash(root);
  if (selected.profile !== 'sdk' && !guestPasswordHash) throw Error('Run Setup-Guest.cmd locally before creating this guest');
  fs.mkdirSync(inside(root, 'Data/ssh'), { recursive: true });
  const key = inside(root, 'Data/ssh/client_key');
  if (!fs.existsSync(key)) run(sshPaths().keygen, ['-q', '-t', 'ed25519', '-N', '', '-C', 'portable-sandbox', '-f', key], { cwd: root, env: storage.environment(root) });
  const pub = fs.readFileSync(`${key}.pub`, 'utf8').trim();
  let agentIdentity;
  if (protection.protection === 'reduced') {
    const agent = require('./private-agent.cjs');
    if (options.privateAgent !== true && !agent.validPipe(options.agentPipe)) throw Error('Reduced storage requires the manager-owned private agent; no native/global-agent fallback');
    agentIdentity = agent.load(root, pub);
    if (options.agentPipe && options.agentPublicKey !== pub) throw Error('Package identity changed after private-agent startup; no implicit rotation');
  } else {
    if (options.agentPipe !== undefined || options.privateAgent) throw Error('NTFS must retain native private-key checks');
    checkClientKey(root, pub);
  }
  const cfgPath = inside(root, 'Data/vm.json');
  let cfg;
  if (fs.existsSync(cfgPath)) cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  else {
    if (fs.existsSync(inside(root,'Data/guest.qcow2'))) throw Error('Unbound existing guest disk; no automatic replacement');
    let sshPort;for(let tries=0;tries<10;tries++){sshPort=await reservePort();if(!selected.ports.some(p=>p.hostPort===sshPort))break;sshPort=undefined;}
    if(!sshPort)throw Error('No non-conflicting SSH control port');
    cfg = { schema: 1, instanceId: `portable-${nonce()}`, sshPort, guestProfile:selected.profile }; fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2), { flag: 'wx' });
  }
  if (cfg.schema !== 1 || !/^portable-[a-f0-9]{32}$/.test(cfg.instanceId)) throw Error('Invalid VM identity');
  if ((cfg.guestProfile || 'sdk') !== selected.profile) throw Error('Existing guest profile differs; use a separate fresh package, not destructive conversion');
  const overlay = inside(root, 'Data/guest.qcow2');
  if (!fs.existsSync(overlay)) {
    run(findProgram(root, 'qemu-img.exe'), ['create', '-f', 'qcow2', '-F', 'qcow2', '-b', '../Runtime/base/debian.qcow2', 'guest.qcow2'], { cwd: data });
    run(findProgram(root, 'qemu-img.exe'), ['resize', 'guest.qcow2', '8G'], { cwd: data });
  }
  if (protection.protection !== 'reduced' || options.agentPipe) fs.writeFileSync(inside(root, 'Data/ssh/config'), sshConfig({ root, sshPort: cfg.sshPort, agentPipe: options.agentPipe }));
  return { cfg, pub, agentIdentity, guestProfile:selected.profile, guestPasswordHash, portForwards:selected.ports };
}

class Qmp {
  constructor(child) {
    this.child = child; this.next = 1; this.pending = new Map(); this.hello = false;
    const lines = readline.createInterface({ input: child.stdout });
    lines.on('line', line => {
      if (line.length > 65536) return;
      let msg; try { msg = JSON.parse(line); } catch { return; }
      if (msg.QMP) this.hello = true;
      if (msg.id && this.pending.has(msg.id)) {
        const entry = this.pending.get(msg.id); this.pending.delete(msg.id); clearTimeout(entry.timer);
        if (msg.error) entry.reject(Error(msg.error.desc)); else entry.resolve(msg.return);
      }
    });
  }
  command(execute) {
    return new Promise((resolve, reject) => {
      const id = this.next++;
      const timer = setTimeout(() => { this.pending.delete(id); reject(Error('QMP deadline')); }, 5000);
      this.pending.set(id, { resolve, reject, timer });
      this.child.stdin.write(JSON.stringify({ execute, id }) + '\n', error => { if (error) { clearTimeout(timer); this.pending.delete(id); reject(error); } });
    });
  }
}

async function boot(root, stage, afterReady, options = {}) {
  if (!['bootstrap', 'runtime'].includes(stage)) throw Error('Invalid stage');
  if (stage === 'runtime' && !fs.existsSync(inside(root, 'Data/bootstrap-verified.json'))) throw Error('Restricted firewall bootstrap must be verified before unrestricted networking');
  if (stage === 'runtime') for (const file of ['Data/guest.qcow2', 'Data/vm.json', 'Data/ssh/client_key', 'Data/ssh/trusted_host_key']) {
    if (!fs.existsSync(inside(root, file))) throw Error('Runtime prerequisite missing; restricted bootstrap required, not a fresh unrestricted VM');
  }
  const { cfg, pub, guestProfile, guestPasswordHash, portForwards } = await prepare(root, options);
  if (stage === 'runtime') {
    const record = JSON.parse(fs.readFileSync(inside(root, 'Data/bootstrap-verified.json'), 'utf8'));
    if (!bootstrapBound(record, { instanceId: cfg.instanceId,
      hostKey: fs.readFileSync(inside(root, 'Data/ssh/trusted_host_key'), 'utf8').trim(),
      disk: diskIdentity(inside(root, 'Data/guest.qcow2')) })) throw Error('Bootstrap proof does not match this disk/instance; restricted bootstrap required');
  }
  const bootId = nonce();
  const rules = firewall(localV4(), portForwards);
  const files = makeGuestFiles({ instanceId: cfg.instanceId, bootId, stage, sshPublicKey: pub, guestProfile, guestPasswordHash,
    networkRulesV4: rules.v4, networkRulesV6: rules.v6, ...(stage === 'runtime' && guestProfile === 'sdk' ? { tools } : {}) });
  files['STAGE.TXT'] = stage + '\n';
  fs.writeFileSync(inside(root, 'Data/seed.img'), createSeed(files));
  const consolePath = inside(root, 'Data/current-console.log');
  if (fs.existsSync(consolePath)) {
    fs.mkdirSync(inside(root, 'Data/logs'), { recursive: true });
    fs.renameSync(consolePath, inside(root, `Data/logs/console-${nonce()}.log`));
  }
  fs.writeFileSync(consolePath, '', { flag: 'wx' });
  const qemu = findProgram(root, 'qemu-system-x86_64.exe');
  const args = qemuArgs({ root, sshPort: cfg.sshPort, bootstrap: stage === 'bootstrap', portForwards });
  const firmware = path.join(path.dirname(qemu), 'share');
  if (fs.existsSync(firmware)) args.push('-L', path.relative(root, firmware).replaceAll('\\', '/'));
  const child = spawn(qemu, args, { cwd: root, shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  let ended = false, exitCode = null, stderr = '', spawnError = null;
  child.on('error', error => { spawnError = error; ended = true; });
  child.on('exit', code => { ended = true; exitCode = code; });
  child.stdin.on('error', () => {}); // Command callbacks report EPIPE; cleanup must still run.
  child.stderr.on('data', chunk => { if (stderr.length < 131072) stderr += chunk.toString(); });
  const qmp = new Qmp(child); let receipt;
  const started = Date.now(); let fresh = null;
  try {
    while (!qmp.hello && !ended && Date.now() - started < 10000) await sleep(50);
    if (!qmp.hello) throw Error(`QEMU did not initialize: ${spawnError?.message || stderr}`);
    await qmp.command('qmp_capabilities');
    options.onControl?.({ child, powerDown: () => qmp.command('system_powerdown'), forceStop: () => qmp.command('quit') });
    const limit = stage === 'bootstrap' ? 180000 : 900000;
    while (Date.now() - started < limit) {
      fresh = guestMarkers(await fsp.readFile(consolePath, 'utf8'), bootId);
      if (fresh.failed) throw Error(`Fresh guest bootstrap reported failure: ${fresh.failure}`);
      if ((stage === 'bootstrap' ? fresh.bootstrap : fresh.runtime) && fresh.hostKey) break;
      if (ended) throw Error(`Guest exited before a fresh ready marker: ${exitCode}; ${stderr.slice(-3000)}`);
      await sleep(500);
    }
    if (!fresh?.hostKey || !(stage === 'bootstrap' ? fresh.bootstrap : fresh.runtime)) throw Error('Guest ready deadline; no stale-artifact fallback');
    const pin = inside(root, 'Data/ssh/trusted_host_key');
    if (fs.existsSync(pin) && fs.readFileSync(pin, 'utf8').trim() !== fresh.hostKey) throw Error('Guest SSH host key changed; no automatic trust replacement');
    if (!fs.existsSync(pin)) fs.writeFileSync(pin, fresh.hostKey + '\n', { flag: 'wx' });
    fs.writeFileSync(inside(root, 'Data/ssh/known_hosts'), `[127.0.0.1]:${cfg.sshPort} ${fresh.hostKey}\n`);
    if (stage === 'bootstrap') {
      while (!ended && Date.now() - started < 200000) await sleep(250);
      if (!ended || exitCode !== 0) throw Error('Restricted bootstrap did not power off cleanly');
      fs.writeFileSync(inside(root, 'Data/bootstrap-verified.json'), JSON.stringify({ bootId, instanceId: cfg.instanceId,
        hostKey: fresh.hostKey, disk: diskIdentity(inside(root, 'Data/guest.qcow2')) }));
    } else if (afterReady) await afterReady({ root, cfg, ssh: sshPaths().ssh, bootId, child,
      forceStop: () => qmp.command('quit') });
    receipt = { schema: 1, stage, bootId, ok: true, elapsedMs: Date.now() - started, pid: child.pid,
      sharedHostFolders: false, hostAgentForwarded: false, realProviderTested: false, readinessEvidence: false };
    return receipt;
  } catch (error) {
    receipt = { schema: 1, stage, bootId, ok: false, error: error.message, elapsedMs: Date.now() - started,
      readinessEvidence: false };
    throw error;
  } finally {
    if (!ended) {
      try { await qmp.command('system_powerdown'); } catch {}
      const until = Date.now() + 20000;
      while (!ended && Date.now() < until) await sleep(200);
      // Prototype owns only synthetic guest data. Production force-stop policy
      // must remain explicit; never use a PID read from an old state file.
      if (!ended && options.allowForce !== false) { try { await qmp.command('quit'); } catch {} }
      if (!ended && options.allowForce !== false) { child.kill(); await sleep(500); }
      // User data is not an expendable smoke fixture. Keep the manager/control
      // API alive for an explicit force-stop instead of silently cutting power.
      if (!ended && options.allowForce === false) await new Promise(resolve => child.once('exit', resolve));
    }
    if (receipt) { receipt.qemuExited = ended; receipt.qemuExitCode = exitCode; }
    fs.writeFileSync(inside(root, `Data/boot-${bootId}.json`), JSON.stringify(receipt || { ok: false, bootId }, null, 2));
    fs.writeFileSync(inside(root, `Data/qemu-${bootId}.stderr.log`), stderr);
  }
}

async function main() {
  const [stage, rootArg] = process.argv.slice(2); const root = path.resolve(rootArg || '');
  if (!rootArg || !['bootstrap', 'smoke'].includes(stage)) throw Error('Usage: prototype.cjs bootstrap|smoke <owned-package>');
  const receipt = await boot(root, stage === 'bootstrap' ? 'bootstrap' : 'runtime', stage === 'smoke' ? async ({ cfg, ssh }) => {
    const result = run(ssh, ['-F', inside(root, 'Data/ssh/config'), 'portable-sandbox',
      'set -eu; id; printf "HOME=%s\\n" "$HOME"; command -v node herdr letta; node --version; herdr --version; letta --version; test ! -e /mnt/c; test ! -e /mnt/d'], { timeout: 60000 });
    fs.writeFileSync(inside(root, 'Data/guest-smoke.txt'), result); console.log(result);
  } : null);
  console.log(JSON.stringify(receipt));
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { guestMarkers, boot, prepare, tools, bootstrapBound, powerShellFileArgs, prepareStorage, bootstrapCurrent, checkClientKey };

'use strict';
// Owned synthetic guest workflow only. Never reads existing user work/accounts.
const fs = require('node:fs'); const path = require('node:path'); const net = require('node:net');
const crypto = require('node:crypto'); const { spawnSync } = require('node:child_process');
const { boot } = require('./prototype.cjs'); const { inside } = require('./policy.cjs');

function guestPython(ssh, root, code) {
  const encoded = Buffer.from(code, 'utf8').toString('base64');
  const command = `python3 -c "import base64;exec(base64.b64decode('${encoded}'))"`;
  const r = spawnSync(ssh, ['-F', inside(root, 'Data/ssh/config'), 'portable-sandbox', command],
    { shell: false, windowsHide: true, timeout: 120000, maxBuffer: 2 * 1024 ** 2, encoding: 'utf8' });
  if (r.error || r.status !== 0) throw Error(`Guest verification failed: ${r.error?.message || r.stderr || r.stdout}`);
  const line = r.stdout.split(/\r?\n/).find(value => value.startsWith('SYNTHETIC_PROOF '));
  if (!line) throw Error('No current semantic guest proof');
  return JSON.parse(line.slice('SYNTHETIC_PROOF '.length));
}
async function listener() {
  for (const port of [80, 443, 0]) {
    const result = { connections: 0 };
    const server = net.createServer(socket => { result.connections++; socket.end('owned synthetic listener\n'); });
    try {
      await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
      result.server = server; result.port = server.address().port; return result;
    } catch (error) { server.close(); if (error.code !== 'EADDRINUSE') throw error; }
  }
  throw Error('No owned synthetic listener');
}
async function localProbe(port) {
  await new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    socket.once('error', reject); socket.once('data', () => { socket.destroy(); resolve(); });
    socket.setTimeout(2000, () => { socket.destroy(); reject(Error('Owned listener positive control failed')); });
  });
}
async function verify(root, phase) {
  if (!['write', 'read'].includes(phase)) throw Error('Expected write/read phase');
  const stateFile = inside(root, 'Data/synthetic-proof.json');
  let fixture;
  if (phase === 'write') {
    if (fs.existsSync(stateFile)) throw Error('Synthetic fixture already exists; do not overwrite another run');
    const id = crypto.randomBytes(12).toString('hex');
    const text = `portable Linux persistence ทดสอบ ${id}\n`;
    fixture = { schema: 1, id, text, sha256: crypto.createHash('sha256').update(text).digest('hex') };
    fs.writeFileSync(stateFile, JSON.stringify(fixture), { flag: 'wx' });
  } else fixture = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  if (fixture.schema !== 1 || !/^[a-f0-9]{24}$/.test(fixture.id) || !/^[a-f0-9]{64}$/.test(fixture.sha256)) throw Error('Invalid owned synthetic fixture');
  const outcome = inside(root, 'Data/synthetic-proof-current.json');
  const requestId = crypto.randomBytes(16).toString('hex');
  fs.writeFileSync(outcome, JSON.stringify({ requestId, phase, passed: false, state: 'started' }));
  const host = await listener();
  try {
    await localProbe(host.port); const before = host.connections;
    let proof;
    const receipt = await boot(root, 'runtime', async ({ ssh }) => {
      const payload = Buffer.from(JSON.stringify({ ...fixture, phase, port: host.port, requestId })).toString('base64');
      const code = `import os,json,pathlib,hashlib,socket,subprocess,base64\n` +
        `p=json.loads(base64.b64decode('${payload}'))\n` +
        `assert os.getuid()!=0 and os.path.expanduser('~')=='/home/sandbox'\n` +
        `d=pathlib.Path('/home/sandbox/workspaces')/('.sandbox-proof-'+p['id'])\n` +
        `if p['phase']=='write':\n d.mkdir(mode=0o700); (d/'owner.json').write_text(json.dumps({'id':p['id']})); (d/'text.txt').write_text(p['text'],encoding='utf8')\n` +
        `assert json.loads((d/'owner.json').read_text())['id']==p['id']\n` +
        `assert hashlib.sha256((d/'text.txt').read_bytes()).hexdigest()==p['sha256']\n` +
        `blocked=False\ns=socket.socket();s.settimeout(2)\ntry:s.connect(('10.0.2.2',p['port']))\nexcept OSError:blocked=True\nfinally:s.close()\n` +
        `assert blocked,'guest reached owned host listener'\n` +
        `assert not any(pathlib.Path(x).exists() for x in ['/mnt/c','/mnt/d','/host','/host_mnt'])\n` +
        `groups=subprocess.check_output(['id','-Gn'],text=True).split();assert not set(groups)&{'sudo','admin','wheel','docker','dialout'}\n` +
        `units={}\nfor unit in ['portable-sandbox-firewall.service','systemd-networkd.service','ssh.service']:\n units[unit]=subprocess.check_output(['systemctl','show',unit,'--property=ActiveState,Result,Requires,After'],text=True)\n` +
        `assert 'ActiveState=active' in units['portable-sandbox-firewall.service']\n` +
        `assert 'portable-sandbox-firewall.service' in units['ssh.service']\n` +
        `print('SYNTHETIC_PROOF '+json.dumps({'requestId':p['requestId'],'fixtureId':p['id'],'sha256':p['sha256'],'home':os.path.expanduser('~'),'uid':os.getuid(),'groups':groups,'hostListenerBlocked':blocked,'listenerPort':p['port'],'unitGraph':units}))\n`;
      proof = guestPython(ssh, root, code);
      if (proof.requestId !== requestId || proof.fixtureId !== fixture.id || proof.sha256 !== fixture.sha256 || proof.hostListenerBlocked !== true) throw Error('Guest semantic proof mismatch');
      if (host.connections !== before) throw Error('Guest unexpectedly connected to owned host listener');
    });
    await localProbe(host.port);
    if (!receipt.ok || !receipt.qemuExited || receipt.qemuExitCode !== 0) throw Error('Guest did not exit cleanly after proof');
    const result = { requestId, phase, passed: true, receipt, proof, realProvidersTested: false, guiTested: false };
    fs.writeFileSync(outcome, JSON.stringify(result, null, 2));
    fs.writeFileSync(inside(root, `Data/synthetic-proof-${requestId}.json`), JSON.stringify(result, null, 2));
    return { phase, passed: true, cleanShutdown: true, hostListenerBlocked: true, fixtureId: fixture.id, guiTested: false };
  } catch (error) { fs.writeFileSync(outcome, JSON.stringify({ requestId, phase, passed: false, error: error.message }, null, 2)); throw error; }
  finally { await new Promise(resolve => host.server.close(resolve)); }
}
if (require.main === module) verify(path.resolve(process.argv[3] || ''), process.argv[2]).then(r => console.log(JSON.stringify(r))).catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { verify, guestPython };

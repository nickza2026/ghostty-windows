'use strict';

const identifier = /^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/;
const version = /^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$/;
const approved = {
  node: { url: 'https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz', version: '24.22.1', sha256: '6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6' },
  herdr: { url: 'https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-linux-x86_64', version: '0.9.5', sha256: '14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d' },
};
function pin(p, name) {
  if (!p || !version.test(p.version) || !/^[a-fA-F0-9]{64}$/.test(p.sha256)) throw Error(`Invalid ${name} pin`);
  const u = new URL(p.url);
  if (u.protocol !== 'https:' || u.username || u.password || /[\r\n\0]/.test(p.url)) throw Error(`Invalid ${name} URL`);
  const result = { url: u.href, version: p.version, sha256: p.sha256.toLowerCase() };
  if (JSON.stringify(result) !== JSON.stringify(approved[name])) throw Error(`Unapproved ${name} pin`);
  return result;
}

const firewall = `#!/bin/sh
set -eu
umask 077
mkdir -p /run/portable-seed
found=
for n in $(seq 1 15); do
  if [ -b /dev/disk/by-label/CIDATA ]; then found=yes; break; fi
  sleep 1
done
[ "$found" = yes ]
mountpoint -q /run/portable-seed || mount -o ro,nosuid,nodev,noexec /dev/disk/by-label/CIDATA /run/portable-seed
findmnt -n -o OPTIONS /run/portable-seed | tr ',' '\\n' | /bin/grep -qx ro
iptables-restore --test < /run/portable-seed/NET4.TXT
ip6tables-restore --test < /run/portable-seed/NET6.TXT
iptables-restore < /run/portable-seed/NET4.TXT
ip6tables-restore < /run/portable-seed/NET6.TXT
`;

const boot = `#!/usr/bin/python3
import os, re, json, subprocess, hashlib, urllib.request, tarfile, tempfile, pathlib, time, shutil, selectors, signal
APPROVED=json.loads('${JSON.stringify(approved)}')
os.environ.clear()
os.environ.update(PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', HOME='/root', CI='1', DEBIAN_FRONTEND='noninteractive')
seed=pathlib.Path('/run/portable-seed')
phase='startup'
log=None
LOG_LIMIT=1024*1024
def setphase(value):
    global phase
    phase=value
    marker('PHASE', value)
def capture(args, timeout, **kw):
    # Only explicitly selected setup commands enter this private bounded log.
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True, **kw) as proc:
        deadline=time.monotonic()+timeout
        with selectors.DefaultSelector() as poll:
            poll.register(proc.stdout, selectors.EVENT_READ)
            try:
                while poll.get_map():
                    if time.monotonic()>deadline: raise subprocess.TimeoutExpired(args, timeout)
                    for key, events in poll.select(min(1, max(0, deadline-time.monotonic()))):
                        chunk=os.read(key.fileobj.fileno(), 8192)
                        if not chunk:
                            poll.unregister(key.fileobj)
                            continue
                        log.seek(0)
                        data=(log.read(LOG_LIMIT)+chunk)[-LOG_LIMIT:]
                        log.seek(0); log.write(data); log.truncate(); log.flush()
                code=proc.wait(timeout=max(0.001, deadline-time.monotonic()))
                if code: raise subprocess.CalledProcessError(code, args)
                return subprocess.CompletedProcess(args, code)
            except BaseException:
                if proc.poll() is None: os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                raise
def run(args, **kw):
    if kw.pop('capture_setup', False): return capture(args, kw.pop('timeout', 1800), **kw)
    return subprocess.run(args, check=True, timeout=kw.pop('timeout', 1800), **kw)
def marker(kind, value=''):
    nonce=(seed/'BOOTID.TXT').read_text().strip()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,95}', nonce): raise ValueError('nonce')
    with open('/dev/ttyS0','w') as out:
        out.write('\\nPORTABLE_SANDBOX '+nonce+' '+kind+' '+value+'\\n')
        out.flush()
def debug_errors():
    if log is None: return
    log.seek(0)
    lines=log.read(LOG_LIMIT).decode('utf-8', errors='replace').splitlines()
    safe=[]
    private=False
    for line in lines:
        if '-----BEGIN' in line: private=True
        if private:
            if '-----END' in line: private=False
            continue
        if not re.search(r'npm (?:error|ERR!)|^E:|URLError|TimeoutError', line, re.I): continue
        line=re.sub(r'https?://[^\\s]+', '[URL]', line)
        line=re.sub(r'(?i)(?:bearer\\s+|(?:token|password|passwd|secret|authorization|api[_-]?key)\\s*[:=]\\s*)[^\\s]+', '[REDACTED]', line)
        line=re.sub(r'[A-Za-z0-9_+/=.-]{24,}', '[REDACTED]', line)
        line=re.sub(r'[^\\x20-\\x7e]', '?', line)[:240]
        safe.append(line)
    selected=safe if len(safe)<=12 else safe[:8]+safe[-4:]
    for line in selected: marker('DEBUG', line)
def hostkey():
    key=pathlib.Path('/etc/ssh/ssh_host_ed25519_key.pub').read_text().strip()
    marker('HOSTKEY', key)
def install(pin, target, role):
    from urllib.parse import urlparse
    u=urlparse(pin['url'])
    if u.scheme!='https' or u.username or u.password or not re.fullmatch(r'[a-fA-F0-9]{64}',pin['sha256']) or not re.fullmatch(r'\\d+\\.\\d+\\.\\d+(?:-[A-Za-z0-9.-]+)?',pin['version']): raise ValueError('pin')
    if pin != APPROVED[role]: raise ValueError('unapproved pin')
    with tempfile.TemporaryDirectory() as tmp:
        archive=pathlib.Path(tmp)/'archive.tar'
        # No redirect downgrade to plaintext transport.
        deadline=time.monotonic()+180
        total=0
        with urllib.request.urlopen(pin['url'],timeout=30) as response:
            if not response.url.startswith('https://'): raise ValueError('redirect')
            with archive.open('wb') as out:
                while True:
                    chunk=response.read(1024*1024)
                    if not chunk: break
                    total+=len(chunk)
                    if total>128*1024*1024 or time.monotonic()>deadline: raise ValueError('download limit')
                    out.write(chunk)
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=pin['sha256'].lower(): raise ValueError('digest')
        os.makedirs(target,exist_ok=True)
        if role=='herdr':
            with archive.open('rb') as source:
                if source.read(4)!=bytes([127,69,76,70]): raise ValueError('ELF magic')
            binary=pathlib.Path(target)/'herdr'
            shutil.copyfile(archive,binary)
            os.chown(binary,0,0)
            binary.chmod(0o755)
            return
        with tarfile.open(archive) as tar:
            # Debian 13 data filter confines links and paths to extraction root.
            members=tar.getmembers()
            if any(not (m.isfile() or m.isdir() or m.issym() or m.islnk()) for m in members): raise ValueError('archive member')
            tar.extractall(target, members=members, filter='data')
def main():
    global log
    stage=(seed/'STAGE.TXT').read_text().strip()
    run(['usermod','-s','/usr/sbin/nologin','sandbox'])
    profile=(seed/'PROFILE.TXT').read_text().strip()
    if profile not in ('sdk','clean','node'): raise ValueError('profile')
    if profile!='sdk': raise ValueError('blueprint profile mismatch')
    recorded=pathlib.Path('/var/lib/portable-sandbox/profile')
    legacy=pathlib.Path('/var/lib/portable-sandbox/tools.json')
    if recorded.exists():
        if recorded.read_text()!=profile: raise ValueError('profile mismatch')
    elif legacy.exists() and profile!='sdk': raise ValueError('legacy profile mismatch')
    if not recorded.exists():
        recorded.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
        recorded.write_text(profile)
        recorded.chmod(0o600)
    if stage=='bootstrap':
        run(['ssh-keygen','-A'])
        hostkey()
        marker('BOOTSTRAP_READY')
        run(['systemctl','poweroff'])
        return
    if stage!='runtime': raise ValueError('stage')
    tools=json.loads((seed/'user-data').read_text().removeprefix('#cloud-config\\n'))['portable_tools']
    if not tools: raise ValueError('tools missing')
    if not re.fullmatch(r'\\d+\\.\\d+\\.\\d+(?:-[A-Za-z0-9.-]+)?',tools['lettaVersion']): raise ValueError('letta version')
    if tools != dict(APPROVED, lettaVersion='0.34.23'): raise ValueError('unapproved tools')
    manifest=pathlib.Path('/var/lib/portable-sandbox/tools.json')
    initial=not manifest.exists()
    if not initial and json.loads(manifest.read_text())!=tools: raise ValueError('manifest mismatch')
    if initial:
        directory=pathlib.Path('/var/log/portable-sandbox')
        directory.mkdir(mode=0o700, exist_ok=True)
        directory.chmod(0o700)
        fd=os.open(directory/'bootstrap.log', os.O_RDWR|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW, 0o600)
        os.fchmod(fd, 0o600)
        log=os.fdopen(fd, 'w+b')
        setphase('apt-update')
        run(['apt-get','update'], capture_setup=True)
        setphase('apt-install')
        run(['apt-get','install','-y','--no-install-recommends','git','curl','ca-certificates','xz-utils','python3','python3-venv','build-essential'], capture_setup=True)
        setphase('build-prerequisites')
        if not shutil.which('make') or not shutil.which('g++'): raise ValueError('native build prerequisites missing')
        setphase('node-download')
        install(tools['node'],'/opt/portable/node','node')
        setphase('herdr-download')
        install(tools['herdr'],'/opt/portable/herdr','herdr')
    nodes=list(pathlib.Path('/opt/portable/node').glob('*/bin/node'))
    herdrs=[p for p in pathlib.Path('/opt/portable/herdr').rglob('herdr') if p.is_file()]
    if len(nodes)!=1 or len(herdrs)!=1: raise ValueError('archive layout')
    node=nodes[0]
    for name in ['node','npm','npx']:
        link=pathlib.Path('/usr/local/bin')/name
        if initial:
            link.unlink(missing_ok=True)
            link.symlink_to(node.parent/name)
    if initial:
        link=pathlib.Path('/usr/local/bin/herdr'); link.unlink(missing_ok=True); link.symlink_to(herdrs[0])
    env=['HOME=/home/sandbox','XDG_CONFIG_HOME=/home/sandbox/.config','XDG_DATA_HOME=/home/sandbox/.local/share','XDG_CACHE_HOME=/home/sandbox/.cache','npm_config_cache=/home/sandbox/.cache/npm','npm_config_prefix=/home/sandbox/.local','LETTA_HOME=/home/sandbox/.letta','PATH=/home/sandbox/.local/bin:/usr/local/bin:/usr/bin:/bin','CI=1']
    def user(args): return run(['runuser','-u','sandbox','--','env','-i']+env+args, cwd='/home/sandbox', capture_setup=True)
    if initial:
        setphase('npm-install')
        user(['npm','install','--global','@letta-ai/letta-code@'+tools['lettaVersion']])
        setphase('backend-local')
        user(['/home/sandbox/.local/bin/letta','backend','local'])
    setphase('health')
    for name,args in [('NODE',['node','--version']),('HERDR',['herdr','--version']),('LETTA',['/home/sandbox/.local/bin/letta','--version'])]:
        result=subprocess.run(['runuser','-u','sandbox','--','env','-i']+env+args,check=True,timeout=60,capture_output=True,text=True)
        expected={'NODE':tools['node']['version'],'HERDR':tools['herdr']['version'],'LETTA':tools['lettaVersion']}[name]
        if not re.search(r'(?<![0-9.])'+re.escape(expected)+r'(?![0-9.])',result.stdout): raise ValueError('tool version mismatch')
        marker(name, result.stdout.strip().replace('\\n',' ')[:200])
    if initial:
        manifest.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
        manifest.write_text(json.dumps(tools))
        manifest.chmod(0o600)
    run(['usermod','-s','/bin/bash','sandbox'])
    hostkey()
    marker('TOOLS_READY')
try: main()
except Exception as error:
    marker('FAILED', phase+' '+type(error).__name__+' '+str(getattr(error, 'returncode', 1)))
    debug_errors()
    raise SystemExit(1)
`;

// Keep the clean boot executable free of SDK installation and environment code.
const cleanBoot = boot
  .replace("if profile!='sdk':", "if profile!='clean':")
  .replace('hashlib, urllib.request, tarfile, tempfile, ', '')
  .replace(/^APPROVED=.*\n/m, '')
  .replace(/def debug_errors\(\):[\s\S]*?(?=def hostkey\(\):)/, 'def debug_errors():\n    pass\n')
  .replace(/def install\(pin, target, role\):[\s\S]*?(?=def main\(\):)/, '')
  .replace(/    tools=json.loads[\s\S]*?(?=    run\(\['usermod','-s','\/bin\/bash')/, "    setphase('health')\n");

const nodeRuntime = `    tools=json.loads((seed/'user-data').read_text().removeprefix('#cloud-config\\n'))['portable_tools']
    if tools != APPROVED: raise ValueError('unapproved tools')
    manifest=pathlib.Path('/var/lib/portable-sandbox/node.json')
    initial=not manifest.exists()
    if not initial and json.loads(manifest.read_text())!=tools: raise ValueError('manifest mismatch')
    if initial:
        setphase('node-download')
        install(tools['node'],'/opt/portable/node','node')
    nodes=list(pathlib.Path('/opt/portable/node').glob('*/bin/node'))
    if len(nodes)!=1: raise ValueError('archive layout')
    node=nodes[0]
    if initial:
        for name in ['node','npm','npx']:
            link=pathlib.Path('/usr/local/bin')/name
            link.unlink(missing_ok=True)
            link.symlink_to(node.parent/name)
    setphase('health')
    env=['HOME=/home/sandbox','PATH=/home/sandbox/.local/bin:/usr/local/bin:/usr/bin:/bin']
    for name in ['node','npm']:
        result=subprocess.run(['runuser','-u','sandbox','--','env','-i']+env+[str(node.parent/name),'--version'],check=True,timeout=60,capture_output=True,text=True)
        if name=='node' and result.stdout.strip()!='v'+tools['node']['version']: raise ValueError('node version mismatch')
        marker(name.upper(), result.stdout.strip().replace('\\n',' ')[:200])
    if initial:
        manifest.write_text(json.dumps(tools))
        manifest.chmod(0o600)
`;
const nodeBoot = boot
  .replace("if profile!='sdk':", "if profile!='node':")
  .replace(/^APPROVED=.*\n/m, `APPROVED=json.loads('${JSON.stringify({ node: approved.node })}')\n`)
  .replace(/        if role=='herdr':[\s\S]*?(?=        with tarfile.open)/, '')
  .replace(/def debug_errors\(\):[\s\S]*?(?=def hostkey\(\):)/, 'def debug_errors():\n    pass\n')
  .replace(/    tools=json.loads[\s\S]*?(?=    run\(\['usermod','-s','\/bin\/bash')/, () => nodeRuntime);

function makeGuestFiles(options) {
  const { instanceId, bootId, sshPublicKey, networkRulesV4, networkRulesV6, tools } = options;
  if (typeof instanceId !== 'string' || typeof bootId !== 'string' || !identifier.test(instanceId) || !identifier.test(bootId)) throw Error('Invalid identifier');
  if (typeof sshPublicKey !== 'string' || !/^ssh-ed25519 [A-Za-z0-9+/]{68}={0,2}(?: [A-Za-z0-9_.@-]+)?$/.test(sshPublicKey)) throw Error('Invalid SSH public key');
  const blob = Buffer.from(sshPublicKey.split(' ')[1], 'base64');
  if (blob.length !== 51 || blob.readUInt32BE(0) !== 11 || blob.subarray(4, 15).toString() !== 'ssh-ed25519' || blob.readUInt32BE(15) !== 32) throw Error('Invalid SSH key encoding');
  for (const rules of [networkRulesV4, networkRulesV6]) {
    if (typeof rules !== 'string' || rules.length > 65536 || rules.includes('\0') || !rules.startsWith('*filter\n') || !rules.endsWith('COMMIT\n')) throw Error('Invalid network rules');
  }
  const stage = options.stage ?? 'bootstrap';
  if (!['bootstrap', 'runtime'].includes(stage)) throw Error('Invalid stage');
  const guestProfile = options.guestProfile === undefined ? 'sdk' : options.guestProfile;
  if (!['sdk', 'clean', 'node'].includes(guestProfile)) throw Error('Invalid guest profile');
  let pins;
  if (guestProfile === 'node') {
    if (tools !== undefined && (!tools || Object.keys(tools).length !== 1 || !Object.hasOwn(tools, 'node'))) throw Error('Invalid node tools');
    pins = { node: pin(tools === undefined ? approved.node : tools.node, 'node') };
  } else {
    pins = tools === undefined ? null : { node: pin(tools.node, 'node'), herdr: pin(tools.herdr, 'herdr'), lettaVersion: tools.lettaVersion };
    if (pins && pins.lettaVersion !== '0.34.23') throw Error('Invalid Letta version');
  }
  const hash = options.guestPasswordHash;
  if (hash !== undefined) {
    if (guestProfile === 'sdk' || typeof hash !== 'string') throw Error('Invalid guest password hash');
    const match = /^\$6\$(?:rounds=([1-9][0-9]*)\$)?[./A-Za-z0-9]{1,16}\$[./A-Za-z0-9]{86}$/.exec(hash);
    if (!match || match[0] !== hash || (match[1] !== undefined && (+match[1] < 5000 || +match[1] > 1000000))) throw Error('Invalid guest password hash');
  }
  const files = [];
  function file(path, content, permissions = '0644') { files.push({ path, content, permissions, owner: 'root:root' }); }
  file('/usr/local/sbin/portable-sandbox-firewall', firewall, '0700');
  file('/usr/local/sbin/portable-sandbox-boot', guestProfile === 'clean' ? cleanBoot : guestProfile === 'node' ? nodeBoot : boot, '0700');
  if (guestProfile === 'sdk') file('/usr/local/bin/letta', '#!/bin/sh\nexec /home/sandbox/.local/bin/letta "$@"\n', '0755');
  file('/etc/ssh/sshd_config.d/00-portable-sandbox.conf', 'PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitUserEnvironment no\nAllowUsers sandbox\n');
  file('/etc/systemd/system/portable-sandbox-firewall.service', '[Unit]\nDefaultDependencies=no\nAfter=local-fs.target\nBefore=network-pre.target\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/portable-sandbox-firewall\nRemainAfterExit=yes\n[Install]\nWantedBy=network-pre.target\n');
  for (const name of ['systemd-networkd', 'networking', 'NetworkManager', 'ssh']) file(`/etc/systemd/system/${name}.service.d/portable-sandbox.conf`, '[Unit]\nRequires=portable-sandbox-firewall.service\nAfter=portable-sandbox-firewall.service\n');
  file('/etc/systemd/system/portable-sandbox-boot.service', '[Unit]\nRequires=portable-sandbox-firewall.service\nAfter=portable-sandbox-firewall.service network-online.target ssh.service\nWants=network-online.target ssh.service\n[Service]\nType=oneshot\nEnvironment=CI=1\nExecStart=/usr/local/sbin/portable-sandbox-boot\nTimeoutStartSec=3600\n[Install]\nWantedBy=multi-user.target\n');
  // Relock before SSH can accept a shell, including boots after a previous success.
  file('/etc/systemd/system/ssh.service.d/portable-shell-lock.conf', '[Service]\nExecStartPre=/usr/sbin/usermod -s /usr/sbin/nologin sandbox\n');
  file('/etc/profile.d/portable-sandbox.sh', 'export HOME=/home/sandbox\nexport XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache\n' + (guestProfile !== 'clean' ? 'export npm_config_cache=$HOME/.cache/npm npm_config_prefix=$HOME/.local\n' : '') + (guestProfile === 'sdk' ? 'export LETTA_HOME=$HOME/.letta\n' : '') + 'export PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin\n');
  const config = {
    users: [{ name: 'sandbox', uid: 1000, homedir: '/home/sandbox', groups: [], sudo: hash === undefined ? false : 'ALL=(ALL) ALL', lock_passwd: hash === undefined, ...(hash === undefined ? {} : { passwd: hash }), shell: '/usr/sbin/nologin', ssh_authorized_keys: [sshPublicKey] }],
    disable_root: true, ssh_pwauth: false, ssh_deletekeys: false, portable_tools: pins, write_files: files,
    runcmd: [['install', '-d', '-o', 'sandbox', '-g', 'sandbox', '-m', '0700', '/home/sandbox/workspaces'], ['systemctl', 'daemon-reload'], ['systemctl', 'enable', 'portable-sandbox-firewall.service', 'portable-sandbox-boot.service'], ['systemctl', 'start', 'portable-sandbox-firewall.service'], ['systemctl', 'start', '--no-block', 'portable-sandbox-boot.service']],
  };
  return { 'user-data': '#cloud-config\n' + JSON.stringify(config, null, 2) + '\n', 'meta-data': JSON.stringify({ 'instance-id': instanceId, 'local-hostname': 'portable-sandbox' }) + '\n', 'NET4.TXT': networkRulesV4, 'NET6.TXT': networkRulesV6, 'BOOTID.TXT': bootId + '\n', 'STAGE.TXT': stage + '\n', 'PROFILE.TXT': guestProfile + '\n' };
}
module.exports = { makeGuestFiles };

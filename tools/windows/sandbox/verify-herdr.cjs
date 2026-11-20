'use strict';
// Explicit synthetic Linux TTY verification; importing this module starts nothing.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { boot } = require('./prototype.cjs');
const { inside } = require('./policy.cjs');

function stripAnsi(text) {
  return text.replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, '').replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '').replace(/\r/g, '');
}
function guestMain(nonce) {
  const fs = require('node:fs');
  const cp = require('node:child_process');
  const crypto = require('node:crypto');
  const { createRequire } = require('node:module');
  if (process.getuid() === 0) throw Error('Root guest is forbidden');
  const cwd = '/home/sandbox/workspaces/sandbox-proof-' + nonce;
  fs.mkdirSync(cwd, { mode: 0o700 });
  // Linux sun_path is short: the previous long synthetic XDG + session path
  // exceeded the Unix-socket limit before Herdr could enter its TUI.
  const profile = '/tmp/hp-' + nonce.slice(0, 16);
  fs.mkdirSync(profile, { mode: 0o700 });
  const env = { HOME: '/home/sandbox', XDG_CONFIG_HOME: profile + '/c', XDG_DATA_HOME: profile + '/d',
    XDG_STATE_HOME: profile + '/s', XDG_CACHE_HOME: profile + '/k', LETTA_HOME: profile + '/l',
    HERDR_CONFIG_PATH: profile + '/herdr.toml',
    PATH: '/home/sandbox/.local/bin:/usr/local/bin:/usr/bin:/bin', TERM: 'xterm-256color', SHELL: '/bin/bash' };
  for (const key of ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'LETTA_HOME']) fs.mkdirSync(env[key]);
  fs.writeFileSync(env.HERDR_CONFIG_PATH, '[terminal]\ndefault_shell = "/bin/bash"\n[update]\nversion_check = false\nmanifest_check = false\n', { flag: 'wx' });
  function run(name, args) {
    const r = cp.spawnSync(name, args, { cwd, env, encoding: 'utf8', timeout: 10000, maxBuffer: 1048576 });
    if (r.error || r.status !== 0) throw Error(name + ' failed: ' + (r.error?.message || r.stderr));
    return r.stdout;
  }
  const help = run('herdr', ['--help']);
  if (!/(?:^|\s)--session(?:[=\s]|$)/m.test(help)) throw Error('Actual herdr --help lacks --session');
  let pty;
  try { pty = createRequire('/home/sandbox/.local/lib/node_modules/@letta-ai/letta-code/package.json')('node-pty'); }
  catch (e) { throw Error('Letta node-pty unavailable: ' + e.message); }
  const session = 'p-' + nonce.slice(0, 12);
  const socketPath = env.XDG_CONFIG_HOME + '/herdr/sessions/' + session + '/herdr.sock';
  if (Buffer.byteLength(socketPath) >= 100) throw Error('Synthetic Unix socket path too long');
  const probe = `const fs=require('node:fs'),cp=require('node:child_process'),c=require('node:crypto');
const call=(n,a)=>{const r=cp.spawnSync(n,a,{encoding:'utf8',timeout:8000});if(r.error||r.status!==0)throw Error(n+' failed');return r.stdout.trim()};
const names=['node','npm','git','herdr','letta'];const paths={};const versions={};
for(const n of names){paths[n]=call('/bin/sh',['-c','command -v '+n]);versions[n]=call(n,['--version']);}
const p={nonce:${JSON.stringify(nonce)},home:process.env.HOME,path:process.env.PATH,platform:process.platform,uname:call('uname',['-s']),cwd:process.cwd(),paths,versions};
const raw=JSON.stringify(p);fs.writeFileSync('pane-proof.json',raw,{flag:'wx'});
console.log('BEGIN_'+p.nonce);console.log(c.createHash('sha256').update(raw).digest('hex'));console.log('END_'+p.nonce);`;
  fs.writeFileSync(cwd + '/probe.cjs', probe, { flag: 'wx' });
  let terminal;
  try { terminal = pty.spawn('herdr', ['session', 'attach', session], { cwd, env, cols: 120, rows: 40, name: env.TERM }); }
  catch (e) { throw Error('Herdr PTY startup failed: ' + e.message); }
  let output = '', exited = false;
  terminal.onData(data => { output = (output + data).slice(-2 * 1024 * 1024); });
  terminal.onExit(() => { exited = true; });
  return new Promise((resolve, reject) => {
    let sent = false, finished = false, workspaceCreated = false, dismissed = false, dismissAt = 0, paneId;
    const start = Date.now();
    function finish(error, proof) {
      if (finished) return;
      finished = true; clearInterval(timer);
      try { terminal.kill(); } catch (_) { /* only our own PTY */ }
      // Never stop any other Herdr session.
      const stop = cp.spawnSync('herdr', ['--session', session, 'server', 'stop'], { cwd, env, encoding: 'utf8', timeout: 5000 });
      if (!error && (stop.error || stop.status !== 0)) error = Error('Owned Herdr session did not stop cleanly');
      if (error) reject(error); else resolve(proof);
    }
    const timer = setInterval(() => {
      try {
        const elapsed = Date.now() - start;
        if (!workspaceCreated && fs.existsSync(socketPath)) {
          const workspace = JSON.parse(run('herdr', ['--session', session, 'workspace', 'create', '--cwd', cwd, '--label', session]));
          if (workspace.result?.type !== 'workspace_created' || !workspace.result?.root_pane?.pane_id) throw Error('No actual Herdr shell workspace');
          paneId = workspace.result.root_pane.pane_id;
          workspaceCreated = true;
        }
        const screen = stripAnsi(output);
        if (!dismissed && screen.includes('agent integrations') && screen.includes('esc close')) {
          terminal.write('\x1b'); dismissed = true; dismissAt = elapsed; return;
        }
        if (!sent && workspaceCreated && elapsed >= 3000 && (!dismissed || elapsed - dismissAt >= 500)) {
          // Use Herdr's documented pane input API (same technique as the
          // established real-shell harness), not global first-run UI hotkeys.
          run('herdr', ['--session', session, 'pane', 'run', paneId, "cd '" + cwd + "' && node ./probe.cjs"]);
          sent = true;
        }
        if (fs.existsSync(cwd + '/pane-proof.json')) {
          const raw = fs.readFileSync(cwd + '/pane-proof.json', 'utf8');
          const hash = crypto.createHash('sha256').update(raw).digest('hex');
          const rendered = run('herdr', ['--session', session, 'pane', 'read', paneId]);
          // Pinned CLI emits rendered plain text here, unlike workspace create.
          let view; try { view = JSON.parse(rendered); } catch { view = rendered; }
          function strings(value) {
            if (typeof value === 'string') return [value];
            return value && typeof value === 'object' ? Object.values(value).flatMap(strings) : [];
          }
          const clean = strings(view).join('\n').replace(/\s/g, '');
          if (clean.includes('BEGIN_' + nonce + hash + 'END_' + nonce)) return finish(null, JSON.parse(raw));
        }
        if (exited) return finish(Error('Herdr exited before semantic pane proof (startup/wizard may block)'));
        if (elapsed > 15000) finish(Error('Herdr pane startup/proof exceeded 15 seconds: ' + JSON.stringify({
          sent, exited, proofFileExists: fs.existsSync(cwd + '/pane-proof.json'), frameBytes: output.length,
          syntheticPreview: stripAnsi(output).slice(-1800),
        })));
      } catch (e) { finish(e); }
    }, 100);
  });
}
function buildGuestScript(nonce) {
  if (!/^[a-f0-9]{32}$/.test(nonce)) throw Error('Expected 32 hex nonce');
  return `'use strict';const stripAnsi=${stripAnsi.toString()};(${guestMain.toString()})(${JSON.stringify(nonce)}).then(p=>console.log('HERDR_PROOF '+JSON.stringify(p))).catch(e=>{console.error(e.message);process.exitCode=1});`;
}
function validateProof(p, nonce) {
  if (p.nonce !== nonce || p.home !== '/home/sandbox' || p.platform !== 'linux' || p.uname !== 'Linux' || p.cwd !== '/home/sandbox/workspaces/sandbox-proof-' + nonce) throw Error('Linux pane identity mismatch');
  const linuxPath = s => typeof s === 'string' && s.startsWith('/') && !/[\\;]|[A-Za-z]:|\/mnt\/|\/host(?:\/|_)/.test(s);
  if (!p.path || !p.path.split(':').every(linuxPath)) throw Error('Non-Linux pane PATH');
  for (const n of ['node', 'npm', 'git', 'herdr', 'letta']) {
    if (!linuxPath(p.paths?.[n]) || !p.versions?.[n]) throw Error('Missing Linux command discovery: ' + n);
  }
  if (p.versions.node !== 'v24.22.1' || !/\b0\.9\.5\b/.test(p.versions.herdr) || !/\b0\.34\.23\b/.test(p.versions.letta) || !/^git version /.test(p.versions.git)) throw Error('Pane tool version mismatch');
  return p;
}
async function verify(root) {
  if (!root || !path.isAbsolute(root)) throw Error('Explicit absolute prototype root required');
  const nonce = crypto.randomBytes(16).toString('hex');
  const current = inside(root, 'Data/herdr-proof-current.json');
  const unique = inside(root, `Data/herdr-proof-${nonce}.json`);
  const initial = { nonce, passed: false, guiTested: false, realProvidersTested: false };
  fs.writeFileSync(current, JSON.stringify(initial));
  fs.writeFileSync(unique, JSON.stringify(initial), { flag: 'wx' });
  try {
    let proof;
    const receipt = await boot(root, 'runtime', async ({ ssh }) => {
      const encoded = Buffer.from(buildGuestScript(nonce)).toString('base64');
      const command = `/usr/local/bin/node -e "eval(Buffer.from('${encoded}','base64').toString())"`;
      const r = spawnSync(ssh, ['-F', inside(root, 'Data/ssh/config'), 'portable-sandbox', command], { shell: false, windowsHide: true, timeout: 90000, maxBuffer: 4 * 1024 ** 2, encoding: 'utf8' });
      if (r.error || r.status !== 0) throw Error('Herdr guest proof failed: ' + (r.error?.message || r.stderr || r.stdout));
      const lines = r.stdout.split(/\r?\n/).filter(l => l.startsWith('HERDR_PROOF '));
      if (lines.length !== 1) throw Error('Expected exactly one current semantic proof');
      proof = validateProof(JSON.parse(lines[0].slice(12)), nonce);
    });
    if (!receipt.ok || !receipt.qemuExited || receipt.qemuExitCode !== 0) throw Error('QEMU did not exit cleanly');
    const result = { ...initial, passed: true, proof, receipt,
      scope: 'Linux Herdr pane via documented PTY input/read API with TUI attached; keyboard focus, native GUI and human acceptance unverified' };
    fs.writeFileSync(unique, JSON.stringify(result, null, 2));
    fs.writeFileSync(current, JSON.stringify(result, null, 2));
    return result;
  } catch (e) {
    const failed = JSON.stringify({ ...initial, error: e.message }, null, 2);
    fs.writeFileSync(unique, failed); fs.writeFileSync(current, failed); throw e;
  }
}
if (require.main === module) verify(process.argv[2]).then(r => console.log(JSON.stringify(r))).catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { verify, buildGuestScript, validateProof, stripAnsi };

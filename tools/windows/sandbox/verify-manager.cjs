'use strict';
const fs = require('node:fs'); const path = require('node:path'); const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process'); const cli = require('./runtime-cli.cjs');
const { inside } = require('./policy.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function verify(root) {
  if (!path.isAbsolute(root) || fs.existsSync(inside(root, 'Data/manager.json'))) throw Error('Explicit idle owned fixture required');
  const requestId = crypto.randomBytes(16).toString('hex');
  const outcome = inside(root, 'Data/manager-proof-current.json');
  const started = Date.now();
  fs.writeFileSync(outcome, JSON.stringify({ requestId, passed: false, stage: 'started' }));
  const before = new Set(fs.readdirSync(inside(root, 'Data')).filter(n => /^boot-[a-f0-9]{32}\.json$/.test(n)));
  let active, previousNonce; const rounds = [];
  async function stopOwned() {
    if (!active) return;
    const found = await cli.existing(root);
    if (found && found.state.managerNonce !== active) throw Error('Manager ownership changed; no stop attempted');
    if (found) await cli.main(['stop', root], { print() {} });
    const limit = Date.now() + 35000;
    while (fs.existsSync(inside(root, 'Data/manager.json')) && Date.now() < limit) await sleep(100);
    if (fs.existsSync(inside(root, 'Data/manager.json'))) throw Error('Owned manager shutdown incomplete; no automatic force-cut');
    const last = JSON.parse(fs.readFileSync(inside(root, 'Data/manager-last.json'), 'utf8'));
    if (last.managerNonce !== active || last.phase !== 'stopped') throw Error('No current stopped-manager proof');
    active = undefined;
  }
  try {
    for (let round = 0; round < 2; round++) {
      const booting = await cli.ensure(root); active = booting.state.managerNonce;
      const found = await cli.ready(root);
      if (found.state.managerNonce !== active || active === previousNonce || found.answer.phase !== 'ready') throw Error('Manager readiness identity mismatch');
      previousNonce = active;
      const ssh = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32/OpenSSH/ssh.exe');
      const r = spawnSync(ssh, ['-F', inside(root, 'Data/ssh/config'), 'portable-sandbox',
        'uname -s; id -u; printf "HOME=%s\\n" "$HOME"; node --version'],
      { shell: false, windowsHide: true, encoding: 'utf8', timeout: 20000 });
      if (r.error || r.status !== 0 || !/^Linux\r?\n1000\r?\nHOME=\/home\/sandbox\r?\nv24\.22\.1\r?\n$/.test(r.stdout)) throw Error('Managed VM Linux SSH proof failed');
      await stopOwned(); rounds.push({ round: round + 1, linuxSsh: true, gracefulStop: true });
    }
    const receipts = fs.readdirSync(inside(root, 'Data')).filter(n => /^boot-[a-f0-9]{32}\.json$/.test(n) && !before.has(n))
      .map(n => JSON.parse(fs.readFileSync(inside(root, `Data/${n}`), 'utf8')));
    if (receipts.length !== 2 || receipts.some(r => !r.ok || !r.qemuExited || r.qemuExitCode !== 0)) throw Error('No two fresh clean VM shutdown receipts');
    const result = { requestId, passed: true, rounds, elapsedMs: Date.now() - started,
      guiTested: false, realProvidersTested: false };
    fs.writeFileSync(outcome, JSON.stringify(result, null, 2));
    fs.writeFileSync(inside(root, `Data/manager-proof-${requestId}.json`), JSON.stringify(result, null, 2));
    return result;
  } catch (error) {
    let cleanup = 'none'; try { await stopOwned(); cleanup = 'graceful'; } catch { cleanup = 'incomplete-no-force'; }
    fs.writeFileSync(outcome, JSON.stringify({ requestId, passed: false, error: error.message, cleanup }, null, 2)); throw error;
  }
}
if (require.main === module) verify(path.resolve(process.argv[2] || '')).then(r => console.log(JSON.stringify(r))).catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { verify };

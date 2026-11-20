'use strict';
// Redirected-stdin packaged CMD pipeline proof, NOT native interactive GUI proof.
const fs = require('node:fs'); const path = require('node:path'); const crypto = require('node:crypto');
const { spawn } = require('node:child_process'); const cli = require('./runtime-cli.cjs');
const { inside } = require('./policy.cjs');
function packagedCommand(root){return{executable:path.join(process.env.SystemRoot||'C:\\Windows','System32/cmd.exe'),args:['/d','/s','/c','""'+inside(root,'Open-Terminal.cmd')+'""']};}
async function verify(root) {
  if (!path.isAbsolute(root) || fs.existsSync(inside(root, 'Data/manager.json'))) throw Error('Explicit idle fixture required');
  const nonce = crypto.randomBytes(16).toString('hex');
  const file = inside(root, 'Data/entry-proof-current.json');
  fs.writeFileSync(file, JSON.stringify({ nonce, passed: false, mode: 'redirected-stdin' }));
  const code = `const p={nonce:${JSON.stringify(nonce)},platform:process.platform,uid:process.getuid?.(),home:process.env.HOME,version:process.version,cwd:process.cwd()};console.log('\\nPACKAGED_GUEST_PROOF '+JSON.stringify(p));`;
  const encoded = Buffer.from(code).toString('base64');
  let output = '', active;
  try {
    const system = process.env.SystemRoot || 'C:\\Windows';
    const command=packagedCommand(root);
    const child = spawn(command.executable, command.args,
      { cwd: root, shell: false, windowsHide: true, windowsVerbatimArguments: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let sent = false;
    const cap = data => {
      output += data.toString('utf8');
      // Model a person typing AFTER the guest prompt. Closing redirected stdin
      // during VM boot makes Windows OpenSSH send EOF before its PTY is usable.
      if (!sent && /sandbox@portable-sandbox[^\r\n]*\$/.test(output)) {
        sent = true;
        child.stdin.write(`node -e "eval(Buffer.from('${encoded}','base64').toString())"\nexit\n`);
      }
      if (output.length > 1024 * 1024) child.kill();
    };
    child.stdout.on('data', cap); child.stderr.on('data', cap); child.stdin.on('error', () => {});
    const codeExit = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { child.kill(); reject(Error('Packaged CMD pipeline deadline; no host-shell fallback')); }, 120000);
      child.once('error', e => { clearTimeout(timer); reject(e); });
      child.once('close', code => { clearTimeout(timer); resolve(code); });
    });
    const found = await cli.existing(root); if (found) active = found.state.managerNonce;
    const line = output.split(/[\r\n]/).find(l => l.startsWith('PACKAGED_GUEST_PROOF {'));
    if (codeExit !== 0 || !line) throw Error('No semantic packaged CMD guest proof: ' + output.slice(-1500));
    const proof = JSON.parse(line.slice('PACKAGED_GUEST_PROOF '.length));
    if (proof.nonce !== nonce || proof.platform !== 'linux' || proof.uid !== 1000 || proof.home !== '/home/sandbox' ||
        proof.version !== 'v24.22.1' || proof.cwd !== '/home/sandbox/workspaces') throw Error('Packaged command escaped guest identity');
    if (!found || found.answer.phase !== 'ready') throw Error('Terminal closure did not retain the owned ready VM');
    await cli.main(['stop', root], { print() {} });
    const deadline = Date.now() + 35000;
    while (fs.existsSync(inside(root, 'Data/manager.json')) && Date.now() < deadline) await new Promise(r => setTimeout(r, 100));
    if (fs.existsSync(inside(root, 'Data/manager.json'))) throw Error('Packaged VM normal shutdown incomplete');
    const last = JSON.parse(fs.readFileSync(inside(root, 'Data/manager-last.json'), 'utf8'));
    if (last.managerNonce !== active || last.phase !== 'stopped') throw Error('No current normal-stop proof');
    active = undefined;
    const result = { nonce, passed: true, mode: 'packaged CMD with redirected stdin', proof,
      nativeInteractiveGuiTested: false, realProvidersTested: false, cleanStop: true };
    fs.writeFileSync(file, JSON.stringify(result, null, 2));
    fs.writeFileSync(inside(root, `Data/entry-proof-${nonce}.json`), JSON.stringify(result, null, 2));
    return result;
  } catch (error) {
    if (active) { try { const found = await cli.existing(root); if (found?.state.managerNonce === active) await cli.main(['stop', root], { print() {} }); } catch {} }
    fs.writeFileSync(file, JSON.stringify({ nonce, passed: false, error: error.message }, null, 2)); throw error;
  }
}
if (require.main === module) verify(path.resolve(process.argv[2] || '')).then(r => console.log(JSON.stringify(r))).catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { verify,packagedCommand };

'use strict';
// CLI-only private-profile preparation. Never opens a GUI or imports accounts.
const fs = require('node:fs'); const path = require('node:path'); const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process'); const cli = require('./runtime-cli.cjs');
const ide = require('./ide-workspace.cjs'); const { inside } = require('./policy.cjs');
function verify(root) {
  if (!path.isAbsolute(root)) throw Error('Explicit owned package required');
  cli.identity(root);
  const nonce = crypto.randomBytes(16).toString('hex');
  const file = inside(root, 'Data/ide-proof-current.json');
  fs.writeFileSync(file, JSON.stringify({ nonce, passed: false, guiTested: false }));
  try {
    const code = cli.codeCommand();
    // VS Code's auto-detected portable data overrides private CLI directories.
    // Refuse rather than accidentally choosing another account/data principal.
    if (fs.existsSync(path.join(path.dirname(code.executable), 'data'))) throw Error('Public IDE has its own portable data; no principal substitution');
    const staged = ide.stageWorkspace(root);
    const settingsFile = path.join(staged.userData, 'User/settings.json');
    const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
    Object.assign(settings, { 'telemetry.telemetryLevel': 'off', 'update.mode': 'none', 'extensions.autoUpdate': false });
    fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2));
    const env = { ...cli.environment(root), ELECTRON_RUN_AS_NODE: '1' };
    function run(args, timeout) {
      const r = spawnSync(code.executable, [code.cli, ...args], { cwd: root, env, shell: false,
        windowsHide: true, encoding: 'utf8', timeout, maxBuffer: 2 * 1024 * 1024 });
      if (r.error || r.status !== 0) throw Error('Private IDE CLI failed: ' + (r.error?.message || r.stderr || r.stdout).slice(-1000));
      return r.stdout;
    }
    run(staged.extensionArgs, 180000);
    const list = run(['--user-data-dir', staged.userData, '--extensions-dir', staged.extensions, '--list-extensions', '--show-versions'], 30000);
    const installed = list.split(/\r?\n/).find(s => /^ms-vscode-remote\.remote-ssh@[^\s]+$/.test(s.trim()));
    if (!installed) throw Error('No actual private Remote SSH extension installation');
    const workspace = JSON.parse(fs.readFileSync(staged.workspaceFile, 'utf8'));
    if (workspace.folders[0].uri !== ide.guestUri() || settings['security.workspace.trust.enabled'] !== true) throw Error('Remote workspace/trust contract mismatch');
    const result = { nonce, passed: true, extension: installed.trim(), workspace: workspace.folders[0].uri,
      privateProfile: true, telemetryOff: true, guiTested: false, actualRemoteIdeConnectionTested: false,
      accountsImported: false };
    fs.writeFileSync(file, JSON.stringify(result, null, 2));
    fs.writeFileSync(inside(root, `Data/ide-proof-${nonce}.json`), JSON.stringify(result, null, 2));
    return result;
  } catch (error) { fs.writeFileSync(file, JSON.stringify({ nonce, passed: false, error: error.message, guiTested: false }, null, 2)); throw error; }
}
if (require.main === module) { try { console.log(JSON.stringify(verify(path.resolve(process.argv[2] || '')))); }
  catch (e) { console.error(e.message); process.exitCode = 1; } }
module.exports = { verify };

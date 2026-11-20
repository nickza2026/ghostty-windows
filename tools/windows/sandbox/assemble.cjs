'use strict';
const fs = require('node:fs'); const path = require('node:path'); const crypto = require('node:crypto');
const { inside } = require('./policy.cjs');
function assemble(root) {
  const marker = JSON.parse(fs.readFileSync(path.join(root, 'sandbox-owned.json'), 'utf8'));
  if (marker.name !== 'ghostty-sandbox-owned' || marker.schema !== 1) throw Error('Owned prototype required');
  if (fs.existsSync(inside(root, 'Data/manager.json'))) throw Error('Do not replace sources consumed by a manager');
  const names = ['entry.cjs', 'runtime-cli.cjs', 'prototype.cjs', 'policy.cjs', 'fat-seed.cjs',
    'guest-blueprint.cjs', 'acquire.cjs', 'range-download.cjs', 'ide-workspace.cjs', 'terminal-filter.cjs',
    'private-data.ps1', 'preflight.ps1', 'storage-policy.cjs', 'private-agent.cjs',
    'private-openssh-key.cjs', 'private-agent-bridge.ps1', 'private-agent-bridge.cs',
    'guest-config.cjs','guest-password-hash.cjs','terminal-protocol.cjs','guest-terminal.py',
    'manager-recovery.cjs', 'manager-recovery-proof.ps1'];
  const app = inside(root, 'App');
  for (let p = root; ; p = path.dirname(p)) { if (fs.lstatSync(p).isSymbolicLink()) throw Error('Reparse package refused'); if (path.dirname(p) === p) break; }
  if (fs.existsSync(app) && fs.lstatSync(app).isSymbolicLink()) throw Error('Reparse App refused');
  fs.mkdirSync(app, { recursive: true });
  const hashes = [];
  for (const name of names) {
    const source = fs.readFileSync(path.join(__dirname, name)); const output = inside(root, `App/${name}`);
    if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) throw Error('Reparse program refused');
    fs.writeFileSync(output, source); hashes.push({ name, sha256: crypto.createHash('sha256').update(source).digest('hex') });
  }
  const enable = inside(root, 'Enable-ExFAT.cmd');
  if (fs.existsSync(enable) && fs.lstatSync(enable).isSymbolicLink()) throw Error('Reparse launcher refused');
  fs.writeFileSync(enable, '@echo off\r\nsetlocal DisableDelayedExpansion\r\n' +
    'echo EXFAT REDUCED PROTECTION: drive users can read or modify VM data, SSH keys, trust records and control tokens.\r\n' +
    'echo This does not protect against other users of this drive. NTFS checks remain strict on NTFS.\r\n' +
    '"%SystemRoot%\\System32\\choice.exe" /c YN /n /m "Accept this limitation for this portable sandbox? [Y/N] "\r\n' +
    'if not "%ERRORLEVEL%"=="1" exit /b 0\r\nset "NODE_OPTIONS="\r\nset "NODE_PATH="\r\n' +
    '"%~dp0Runtime\\node\\node.exe" "%~dp0App\\entry.cjs" enable-exfat "%~dp0." --accept-unprotected-storage\r\n' +
    'set "SANDBOX_EXIT_CODE=%ERRORLEVEL%"\r\npause\r\nexit /b %SANDBOX_EXIT_CODE%\r\n');
  for (const [name, command] of [['Open-Terminal.cmd', 'terminal'], ['Open-IDE.cmd', 'ide'],
    ['Sandbox-Status.cmd', 'status'], ['Stop-Sandbox.cmd', 'stop'], ['Force-Stop-Sandbox.cmd', 'force-stop'],['Setup-Guest.cmd','setup-guest']]) {
    const output = inside(root, name);
    if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) throw Error('Reparse launcher refused');
    fs.writeFileSync(output, '@echo off\r\nsetlocal\r\nset "NODE_OPTIONS="\r\nset "NODE_PATH="\r\n' +
      '"%~dp0Runtime\\node\\node.exe" "%~dp0App\\entry.cjs" ' + command + ' "%~dp0."\r\n' +
      'set "SANDBOX_EXIT_CODE=%ERRORLEVEL%"\r\nif not "%SANDBOX_EXIT_CODE%"=="0" (\r\n' +
      '  echo.\r\n  echo Sandbox exited with code %SANDBOX_EXIT_CODE%. No host-shell fallback was opened.\r\n  pause\r\n)\r\n' +
      'exit /b %SANDBOX_EXIT_CODE%\r\n');
  }
  fs.writeFileSync(inside(root, 'App/source-snapshot.json'), JSON.stringify({ schema: 1, sources: hashes }, null, 2));
  const guide = inside(root, 'START-HERE-TH.md');
  if (fs.existsSync(guide) && fs.lstatSync(guide).isSymbolicLink()) throw Error('Reparse guide refused');
  fs.copyFileSync(path.join(__dirname, 'start-here-th.md'), guide);
  return { copied: names.length, launchers: 6, userAccountsMigrated: false };
}
if (require.main === module) { try { console.log(JSON.stringify(assemble(path.resolve(process.argv[2] || '')))); }
  catch (error) { console.error(error.message); process.exitCode = 1; } }
module.exports = { assemble };

'use strict';
const path = require('node:path'); const { spawnSync } = require('node:child_process');
const { inside } = require('./policy.cjs'); const prototype = require('./prototype.cjs');
const runtime = require('./runtime-cli.cjs');

function preflight(root, run = spawnSync, source = process.env) {
  const powershell = path.join(source.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');
  const p = run(powershell, prototype.powerShellFileArgs(path.join(__dirname, 'preflight.ps1')),
    { shell: false, windowsHide: true, timeout: 15000,
      stdio: ['ignore', 'inherit', 'inherit'], env: runtime.environment(root, source) });
  if (p.error || p.status !== 0) throw Error('Virtualization preflight failed; host shell was not opened');
}
async function main(args = process.argv.slice(2), deps = {}) {
  const [command, rootArg, acknowledgement] = args; const root = path.resolve(rootArg || '');
  if (!rootArg || !['terminal', 'ide', 'status', 'stop', 'force-stop', 'enable-exfat', 'setup-guest'].includes(command) ||
      (command === 'enable-exfat' ? args.length !== 3 || acknowledgement !== '--accept-unprotected-storage' : args.length !== 2)) throw Error('Invalid portable entry command');
  const expected = inside(root, 'Runtime/node/node.exe');
  if (path.resolve(deps.execPath || process.execPath).toLowerCase() !== expected.toLowerCase()) throw Error('Private portable Node required; no host runtime fallback');
  if (command === 'enable-exfat') {
    (deps.storage || require('./storage-policy.cjs')).enable(root, { acknowledged: true });
    (deps.print || console.log)('exFAT reduced-protection mode accepted for this portable root. NTFS still enforces ownership/ACLs.');
    return 0;
  }
  const client = deps.runtime || runtime;
  if (command === 'setup-guest') {
    client.identity(root);(deps.storage || require('./storage-policy.cjs')).prepare(root);
    await (deps.guestConfig || require('./guest-config.cjs')).setup(root,deps);return 0;
  }
  if (['terminal', 'ide'].includes(command)) {
    client.identity(root);
    // No feature enablement, driver setup, global environment or account import.
    (deps.preflight || preflight)(root);
    const guest = deps.guestConfig || require('./guest-config.cjs');
    if (guest.profile(root).profile !== 'sdk') { (deps.storage || require('./storage-policy.cjs')).prepare(root);await guest.setup(root,deps); }
  }
  return client.main([command, root]);
}
async function showFailure(error, args = process.argv.slice(2), deps = {}) {
  const input = deps.stdin || process.stdin, output = deps.stderr || process.stderr;
  const message = String(error?.message || 'Unknown portable startup failure').replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 1024);
  output.write('Sandbox could not start: ' + message + '\r\n');
  output.write('Data and accounts were not reset. No host-shell fallback was opened.\r\n');
  if (args[0] !== 'terminal' || !input.isTTY) return 1;
  output.write('Press a key to close this window, or close it with X.\r\n');
  const raw = input.isRaw;
  if (input.setRawMode) input.setRawMode(true);
  try {
    await new Promise(resolve => {
      const finish = () => { input.removeListener('data', finish); input.removeListener('end', finish); input.removeListener('error', finish); resolve(); };
      input.once('data', finish); input.once('end', finish); input.once('error', finish); input.resume();
    });
  } finally { if (input.setRawMode) input.setRawMode(Boolean(raw)); input.pause(); }
  return 1;
}
function failureSummary(error) {
  const message = String(error?.message || 'Unknown failure');
  const messages = new Set(['Manager startup deadline', 'Manager ownership mismatch', 'Manager ownership changed; state left unchanged',
    'Guest is not ready', 'Another startup or manager still owns this package; wait and reopen Sandbox.exe',
    'Invalid manager recovery receipt', 'Preserved manager state does not match original bytes', 'Manager state reappeared during recovery; no replacement attempted']);
  const reasons = new Set(['LIVE_PACKAGE_NODE', 'LIVE_PACKAGE_QEMU', 'LIVE_PORT', 'BUSY_DISK', 'PORT_PROBE_TIMEOUT', 'PORT_PROBE_AMBIGUOUS',
    'OWNER_CHANGED', 'STATE_CHANGED', 'STATE_APPEARED', 'METADATA_CHANGED', 'STATE_IDENTITY_CHANGED', 'ARCHIVE_VERIFICATION_FAILED',
    'INVALID_VM_IDENTITY', 'INVALID_GUEST_PROFILE', 'UNEXPECTED_DISK_CHAIN', 'CORRUPT_OR_UNEXPECTED_DISK', 'PROCESS_IDENTITY_UNREADABLE',
    'REPARSE_PATH', 'MULTIPLE_FILE_LINKS', 'MULTIPLE_DISK_LINKS', 'UNKNOWN_EVIDENCE']);
  const refusal = /^Automatic manager recovery was refused: ([A-Z_]+)$/.exec(message);
  const codes = new Set(['MANAGER_UNREACHABLE', 'MANAGER_LEASE_BUSY', 'MANAGER_RECOVERY_REFUSED', 'SSH_KEY_MISMATCH', 'SSH_KEY_STORAGE_UNSUPPORTED',
    'SSH_AGENT_UNAVAILABLE', 'ENOENT', 'EACCES', 'EPERM', 'EBUSY', 'EADDRINUSE', 'ETIMEDOUT', 'EIO', 'ENOSPC']);
  return { code: codes.has(error?.code) ? error.code : 'STARTUP_FAILURE',
    message: messages.has(message) || (refusal && reasons.has(refusal[1])) ? message : 'See the terminal for the startup failure.' };
}
function recordFailure(error) {
  try {
    if (process.argv[2] !== 'terminal') return;
    const fs = require('node:fs'), root = path.resolve(process.argv[3] || '');
    runtime.identity(root); const dir = path.join(root, 'Data/native/logs');
    (require('./storage-policy.cjs')).noLinks(dir); fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'startup-failure-' + process.pid + '-' + Date.now() + '.json'), JSON.stringify(failureSummary(error)), { flag: 'wx', mode: 0o600 });
  } catch {} // Optional diagnostics must never replace the actual visible error.
}
if (require.main === module) main().then(async code => {
  process.exitCode = code ? await showFailure(Error('Guest terminal ended with status ' + code)) : 0;
}).catch(async error => { recordFailure(error); process.exitCode = await showFailure(error); });
module.exports = { main, preflight, showFailure, failureSummary };

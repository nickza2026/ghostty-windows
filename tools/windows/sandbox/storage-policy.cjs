'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { inside } = require('./policy.cjs');
const reducedMode = 'exfat-reduced-protection';
function environment(root, source = process.env) {
  const data = path.join(root, 'Data'), system = source.SystemRoot || 'C:\\Windows';
  return { SystemRoot: system, ...(source.ProgramData ? { ProgramData: source.ProgramData } : {}),
    PATH: path.join(system, 'System32'), TEMP: data, TMP: data,
    HOME: data, USERPROFILE: data, APPDATA: path.join(data, 'profile'), LOCALAPPDATA: path.join(data, 'local'), TERM: 'xterm-256color' };
}
function noLinks(file, io = fs) {
  for (let p = path.resolve(file); ; p = path.dirname(p)) {
    if (io.existsSync(p) && io.lstatSync(p).isSymbolicLink()) throw Error('Reparse storage path refused');
    if (path.dirname(p) === p) break;
  }
}
function read(root, io = fs) {
  const file = inside(root, 'portable-storage.json'); noLinks(file, io);
  if (!io.existsSync(file)) return { schema: 1, storageMode: 'strict' };
  const value = JSON.parse(io.readFileSync(file, 'utf8'));
  if (!value || Object.keys(value).sort().join(',') !== 'schema,storageMode' || value.schema !== 1 ||
      !['strict', reducedMode].includes(value.storageMode)) throw Error('Invalid portable storage policy; no implicit compatibility fallback');
  return value;
}
function select(filesystem, policy) {
  if (filesystem === 'NTFS') return { schema: 1, filesystem, protection: 'acl' };
  if (filesystem === 'exFAT' && policy.storageMode === reducedMode) return { schema: 1, filesystem, protection: 'reduced' };
  if (filesystem === 'exFAT') throw Error('exFAT needs explicit reduced-protection opt-in with Enable-ExFAT.cmd');
  throw Error('Unsupported or unknown storage filesystem; no ACL-error fallback');
}
function enable(root, { acknowledged = false, fs: io = fs } = {}) {
  if (acknowledged !== true) throw Error('Explicit acceptance of readable/modifiable exFAT data is required');
  noLinks(root, io);
  const owner = JSON.parse(io.readFileSync(inside(root, 'sandbox-owned.json'), 'utf8'));
  if (owner.name !== 'ghostty-sandbox-owned' || owner.schema !== 1 || typeof owner.nonce !== 'string' || owner.nonce.length < 16) throw Error('Invalid package ownership');
  const manager = inside(root, 'Data/manager.json'); noLinks(manager, io);
  if (io.existsSync(manager)) throw Error('Stop this sandbox before changing storage policy; no automatic state cleanup');
  const current = read(root, io), file = inside(root, 'portable-storage.json');
  if (current.storageMode === reducedMode) return current;
  if (io.existsSync(file)) throw Error('Existing strict policy preserved; inspect it before explicitly replacing it');
  const value = { schema: 1, storageMode: reducedMode };
  io.writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  return value;
}
function prepare(root, { run = spawnSync, source = process.env, fs: io = fs, warn = console.warn } = {}) {
  const policy = read(root, io), data = inside(root, 'Data'); noLinks(data, io);
  const owner = JSON.parse(io.readFileSync(inside(root, 'sandbox-owned.json'), 'utf8'));
  if (owner.name !== 'ghostty-sandbox-owned' || owner.schema !== 1) throw Error('Invalid package ownership');
  io.mkdirSync(data, { recursive: true });
  const env = environment(root, source), args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-File',
    path.join(__dirname, 'private-data.ps1'), '-Directory', data];
  if (policy.storageMode === reducedMode) args.push('-AllowExfat');
  const result = run(path.join(env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'), args,
    { windowsHide: true, shell: false, encoding: 'utf8', timeout: 30000, maxBuffer: 65536, env });
  if (result.error || result.status !== 0) throw Error('Storage preparation failed: ' + (result.error?.message || result.stderr || result.stdout || result.status));
  let value; try { value = JSON.parse(result.stdout.trim()); } catch { throw Error('No verified filesystem/storage result'); }
  const expected = select(value.filesystem, policy);
  if (value.schema !== 1 || value.protection !== expected.protection) throw Error('Invalid storage protection result');
  if (value.protection === 'reduced') warn('EXFAT REDUCED PROTECTION: anyone with drive access can read/modify VM disks, keys, trust records and manager credentials. No NTFS ACL protection is claimed.');
  else if (policy.storageMode === reducedMode) warn('This root opted into exFAT compatibility; NTFS ACLs apply here, but do not revoke any prior copies of keys or data.');
  return expected;
}
module.exports = { reducedMode, environment, noLinks, read, select, enable, prepare };

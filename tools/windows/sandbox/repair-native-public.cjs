'use strict';
// Public payload repair only. This module never loads the target entry or runs a VM.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const repo = path.resolve(__dirname, '../../..');
const protectedNames = new Set(['sandbox-owned.json', 'guest-profile.json', 'portable-storage.json']);
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const absent = error => error.code === 'ENOENT';

function safePath(root, name) {
  if (typeof name !== 'string' || !name || name.includes('\\') || /[:\x00-\x1f]/.test(name)) throw Error('Unsafe public path');
  const parts = name.split('/');
  if (parts.some(p => !p || p === '.' || p === '..' || /[. ]$/.test(p) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(p))) throw Error('Unsafe public path');
  if (/^data$/i.test(parts[0]) || parts.some(p => /^(guest-setup\.json|manager\.json|known_hosts|id_rsa(?:\.pub)?|id_ed25519(?:\.pub)?|\.env(?:\..*)?)$/i.test(p) || /\.(pem|p12|pfx)$/i.test(p))) throw Error('Private path in public manifest');
  const file = path.resolve(root, ...parts);
  if (!file.startsWith(path.resolve(root) + path.sep)) throw Error('Public path escape');
  return file;
}
function noLinks(file) {
  for (let p = path.resolve(file); ; p = path.dirname(p)) {
    let s; try { s = fs.lstatSync(p); } catch (error) { if (!absent(error)) throw error; }
    if (s && s.isSymbolicLink()) throw Error('Reparse path refused');
    if (p !== path.resolve(file) && s && !s.isDirectory()) throw Error('Non-directory ancestor');
    if (path.dirname(p) === p) break;
  }
}
async function hash(file) { const h = crypto.createHash('sha256'); for await (const b of fs.createReadStream(file)) h.update(b); return h.digest('hex'); }
async function snapshot(file) {
  noLinks(file); let s; try { s = fs.lstatSync(file); } catch (error) { if (absent(error)) return null; throw error; }
  if (!s.isFile()) throw Error('Nonregular public file');
  return { bytes: s.size, sha256: await hash(file) };
}
function presence(file) { noLinks(file); try { fs.lstatSync(file); return true; } catch (error) { if (absent(error)) return false; throw error; } }
function publicJson(root, name) {
  const p = safePath(root, name); noLinks(p);
  const s = fs.lstatSync(p); if (!s.isFile() || s.size > 8192) throw Error('Unsafe public configuration');
  return json(p);
}
async function validateSource(receiptInput) {
  let receipt;
  if (typeof receiptInput === 'string') { noLinks(receiptInput); receipt = json(receiptInput); }
  else receipt = structuredClone(receiptInput);
  if (!receipt || receipt.schema !== 1 || receipt.passed !== true || receipt.dataIncluded !== false || !Array.isArray(receipt.files) || !receipt.files.length || !path.isAbsolute(receipt.root)) throw Error('Verified public factory receipt required');
  const root = path.resolve(receipt.root); noLinks(root);
  if (!fs.lstatSync(root).isDirectory() || presence(path.join(root, 'Data'))) throw Error('Factory must be unbooted without Data');
  const names = new Set(), manifest = new Map();
  for (const f of receipt.files) {
    const p = safePath(root, f.name), key = f.name.toLowerCase();
    if (names.has(key) || !Number.isSafeInteger(f.bytes) || f.bytes < 0 || !/^[a-f0-9]{64}$/.test(f.sha256)) throw Error('Invalid public manifest');
    names.add(key); manifest.set(f.name, f);
    const s = await snapshot(p); if (!s || s.bytes !== f.bytes || s.sha256 !== f.sha256) throw Error('Public source hash mismatch: ' + f.name);
  }
  const seen = [];
  function walk(dir) {
    noLinks(dir);
    for (const name of fs.readdirSync(dir)) { const p = path.join(dir, name); noLinks(p); const s = fs.lstatSync(p);
      if (s.isDirectory()) walk(p); else if (s.isFile()) seen.push(path.relative(root, p).replaceAll('\\', '/')); else throw Error('Nonregular factory file'); }
  }
  walk(root);
  if (seen.length !== manifest.size || seen.some(n => !manifest.has(n))) throw Error('Unmanifested public source file');
  if (!manifest.has('Sandbox.exe') || manifest.get('Sandbox.exe').sha256 !== receipt.executableSha256) throw Error('Factory executable receipt mismatch');
  auditModuleClosure(root, manifest);
  return { receipt, root, manifest };
}
function auditModuleClosure(root, manifest) {
  const visited = new Set(), queue = ['App/entry.cjs'];
  while (queue.length) {
    const name = queue.pop(); if (visited.has(name)) continue; visited.add(name);
    if (!manifest.has(name)) throw Error('Missing backend module: ' + name);
    if (!/\.(cjs|js)$/.test(name)) continue;
    const source = fs.readFileSync(safePath(root, name), 'utf8');
    for (const match of source.matchAll(/\brequire\s*\(\s*['"](\.[^'"\r\n]+)['"]\s*\)/g)) {
      const relative = path.posix.normalize(path.posix.join(path.posix.dirname(name), match[1]));
      if (!relative.startsWith('App/')) throw Error('Backend module escape');
      // Node does not add .cjs for extensionless require calls.
      const resolved = [relative, relative + '.js', relative + '.json', relative + '.node', relative + '/index.js', relative + '/index.json', relative + '/index.node'].find(n => manifest.has(n));
      if (!resolved) throw Error('Missing backend module: ' + relative);
      queue.push(resolved);
    }
  }
  return [...visited].sort();
}
function isBacking(name) { return name.startsWith('Runtime/') && /\.(qcow2|raw|img|vhd|vhdx)$/i.test(name); }

async function createPlan({ receipt, targetRoot, allowedReplacements = {}, filesystem } = {}) {
  const source = await validateSource(receipt), root = path.resolve(targetRoot || '');
  if (!targetRoot || !path.isAbsolute(targetRoot)) throw Error('Absolute target root required');
  noLinks(root); if (!fs.lstatSync(root).isDirectory()) throw Error('Target directory required');
  if (root === source.root || root.startsWith(source.root + path.sep) || source.root.startsWith(root + path.sep)) throw Error('Source/target overlap refused');
  const owner = publicJson(root, 'sandbox-owned.json');
  if (owner.schema !== 1 || owner.name !== 'ghostty-sandbox-owned' || typeof owner.nonce !== 'string' || !/^[a-f0-9]{32}$/i.test(owner.nonce)) throw Error('Valid existing package ownership required');
  const blocks = [], actions = [], preserved = [], protectedState = {};
  const data = path.join(root, 'Data'); noLinks(data);
  const privatePresence = {};
  // Presence only: never enumerate/read/hash Data or trust a PID from it.
  for (const n of ['guest.qcow2', 'vm.json', 'guest-setup.json', 'manager.json']) privatePresence[n] = presence(path.join(data, n));
  if (privatePresence['manager.json']) blocks.push('Existing manager state: normal stop/ownership verification required outside repair');
  const guestState = ['guest.qcow2', 'vm.json', 'guest-setup.json'].some(n => privatePresence[n]);
  for (const name of protectedNames) protectedState[name] = await snapshot(safePath(root, name));
  if (!protectedState['guest-profile.json'] && guestState) blocks.push('Missing guest profile with existing guest Data: adoption decision required');
  if (protectedState['guest-profile.json']) {
    const profile = publicJson(root, 'guest-profile.json');
    if (profile.schema !== 1 || !['sdk', 'clean', 'node'].includes(profile.profile) || (profile.ports !== undefined && !Array.isArray(profile.ports))) throw Error('Invalid existing guest profile preserved; inspect before repair');
  }
  let storageMode = 'strict';
  if (protectedState['portable-storage.json']) {
    const policy = publicJson(root, 'portable-storage.json');
    if (policy.schema !== 1 || !['strict', 'exfat-reduced-protection'].includes(policy.storageMode)) throw Error('Invalid existing storage policy');
    storageMode = policy.storageMode;
  }
  if (filesystem !== 'NTFS' && !(filesystem === 'exFAT' && storageMode === 'exfat-reduced-protection')) blocks.push('Filesystem/storage consent not verified; repair does not enable exFAT');
  for (const [name, value] of Object.entries(allowedReplacements)) {
    if (!['Sandbox.exe', 'App/entry.cjs', 'share/pkgconfig/libghostty-vt.pc', 'share/pkgconfig/libghostty-vt-static.pc'].includes(name) || !/^[a-f0-9]{64}$/.test(value)) throw Error('Replacement authorization limited to exact known program/generated metadata hashes');
  }
  for (const f of source.receipt.files) {
    const target = safePath(root, f.name), before = await snapshot(target);
    if (f.name === 'sandbox-owned.json' || f.name === 'portable-storage.json' || (f.name === 'guest-profile.json' && (before || guestState))) { preserved.push(f.name); continue; }
    if (f.name === 'guest-profile.json' && !before) {
      const p = publicJson(source.root, f.name); if (p.schema !== 1 || p.profile !== 'node') throw Error('Fresh missing-profile initialization requires verified node template');
    }
    if (before && before.bytes === f.bytes && before.sha256 === f.sha256) { preserved.push(f.name); continue; }
    if (before && (isBacking(f.name) || allowedReplacements[f.name] !== before.sha256)) {
      blocks.push((isBacking(f.name) ? 'Existing backing image differs: ' : 'Modified public file preserved: ') + f.name); continue;
    }
    actions.push({ name: f.name, kind: before ? 'replace' : 'create', before, after: { bytes: f.bytes, sha256: f.sha256 }, initializesProfile: f.name === 'guest-profile.json' });
  }
  const request = { receipt: source.receipt, targetRoot: root, allowedReplacements: structuredClone(allowedReplacements), filesystem };
  const state = { actions, protectedState, privatePresence, blocks };
  return { schema: 1, request, sourceRoot: source.root, targetRoot: root, blocks, actions, preserved, protectedState, privatePresence, stateDigest: digest(JSON.stringify(state)), moduleClosure: auditModuleClosure(source.root, source.manifest), dataRead: false, vmOperations: false };
}
async function applyPlan(plan, { backupRoot, beforeInstall } = {}) {
  if (!plan || plan.schema !== 1) throw Error('Repair plan required');
  const fresh = await createPlan(plan.request);
  if (plan.stateDigest !== fresh.stateDigest || JSON.stringify(plan.actions) !== JSON.stringify(fresh.actions)) throw Error('Stale or modified repair plan');
  if (fresh.blocks.length) throw Error('Blocked repair: ' + fresh.blocks.join('; '));
  const backup = path.resolve(backupRoot || '');
  if (!backupRoot || !backup.startsWith(path.join(repo, 'zig-out') + path.sep) || fs.existsSync(backup) || backup.startsWith(fresh.targetRoot + path.sep) || backup.startsWith(fresh.sourceRoot + path.sep)) throw Error('Fresh owned repo zig-out backup root required');
  noLinks(backup); fs.mkdirSync(backup);
  const token = crypto.randomUUID(), staged = [], installed = [], createdDirs = [], rollbackFailures = [];
  function parents(dir) {
    if (fs.existsSync(dir)) { noLinks(dir); if (!fs.lstatSync(dir).isDirectory()) throw Error('Non-directory install parent'); return; }
    parents(path.dirname(dir)); fs.mkdirSync(dir); createdDirs.push(dir);
  }
  async function current(action) { return snapshot(safePath(fresh.targetRoot, action.name)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  try {
    // Prepare and hash every new inode before changing any target file.
    for (const a of fresh.actions) {
      const target = safePath(fresh.targetRoot, a.name), from = safePath(fresh.sourceRoot, a.name);
      parents(path.dirname(target));
      if (!same(await current(a), a.before)) throw Error('Target changed before staging: ' + a.name);
      if (a.before) {
        const saved = safePath(backup, a.name); fs.mkdirSync(path.dirname(saved), { recursive: true });
        fs.copyFileSync(target, saved, fs.constants.COPYFILE_EXCL);
        if (!same(await snapshot(saved), a.before)) throw Error('Backup verification failed');
      }
      const stage = path.join(path.dirname(target), '.sandbox-repair-' + token + '-' + staged.length);
      fs.copyFileSync(from, stage, fs.constants.COPYFILE_EXCL); staged.push({ a, target, stage });
      if (!same(await snapshot(stage), a.after)) throw Error('Staged public payload mismatch');
    }
    // Recheck all target/protected state together, not just the next file.
    const recheck = await createPlan(plan.request);
    if (recheck.stateDigest !== fresh.stateDigest) throw Error('Target/source changed before installation');
    for (const item of staged) {
      if (beforeInstall) await beforeInstall(item.a.name, installed.length);
      if (!same(await current(item.a), item.a.before)) throw Error('Target changed during installation');
      noLinks(item.target); fs.renameSync(item.stage, item.target); installed.push(item);
      if (!same(await current(item.a), item.a.after)) throw Error('Installed public payload mismatch');
    }
    const after = await createPlan(plan.request);
    if (after.blocks.length || after.actions.length) throw Error('Post-repair public audit failed');
    for (const name of protectedNames) {
      const initialized = fresh.actions.find(a => a.name === name);
      if (!same(after.protectedState[name], initialized ? initialized.after : fresh.protectedState[name])) throw Error('Protected configuration changed during repair');
    }
    const report = { schema: 1, passed: true, installed: installed.map(i => i.a.name), backupRoot: backup, protectedStatePreserved: true, dataRead: false, vmOperations: false, moduleClosure: after.moduleClosure };
    fs.writeFileSync(path.join(backup, 'repair-report.json'), JSON.stringify(report, null, 2), { flag: 'wx' });
    return report;
  } catch (error) {
    for (const item of installed.reverse()) {
      try {
        if (!same(await current(item.a), item.a.after)) throw Error('External change preserved');
        if (item.a.before) {
          const stage = item.target + '.rollback-' + token;
          fs.copyFileSync(safePath(backup, item.a.name), stage, fs.constants.COPYFILE_EXCL);
          if (!same(await snapshot(stage), item.a.before)) throw Error('Rollback backup mismatch');
          fs.renameSync(stage, item.target);
        } else fs.unlinkSync(item.target);
      } catch { rollbackFailures.push(item.a.name); }
    }
    const report = { schema: 1, passed: false, error: error.message, rollbackFailures, backupRoot: backup, dataRead: false, vmOperations: false };
    fs.writeFileSync(path.join(backup, 'repair-report.json'), JSON.stringify(report, null, 2), { flag: 'wx' });
    const failure = Error('Public repair failed: ' + error.message + (rollbackFailures.length ? '; rollback incomplete: ' + rollbackFailures.join(', ') : '; installed files rolled back'));
    failure.report = report; throw failure;
  } finally {
    for (const item of staged) if (fs.existsSync(item.stage)) { try { fs.unlinkSync(item.stage); } catch { /* Retain owned staged file if busy. */ } }
    for (const dir of createdDirs.reverse()) { try { fs.rmdirSync(dir); } catch { /* Nonempty directories and user files are preserved. */ } }
  }
}
if (require.main === module) {
  const [operation, receipt, targetRoot, filesystem, backupRoot, replacementJson] = process.argv.slice(2);
  (async () => {
    if (!['plan', 'apply'].includes(operation)) throw Error('Usage: repair-native-public.cjs plan|apply RECEIPT TARGET NTFS|exFAT [FRESH_BACKUP] [REPLACEMENTS_JSON]');
    const plan = await createPlan({ receipt, targetRoot, filesystem, allowedReplacements: replacementJson ? JSON.parse(replacementJson) : {} });
    console.log(JSON.stringify(operation === 'apply' ? await applyPlan(plan, { backupRoot }) : plan, null, 2));
  })().catch(e => { console.error(e.message); process.exitCode = 1; });
}
module.exports = { createPlan, applyPlan, validateSource, auditModuleClosure, safePath };

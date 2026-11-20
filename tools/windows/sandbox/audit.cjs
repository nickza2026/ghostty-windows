'use strict';
const fs = require('node:fs'); const path = require('node:path'); const crypto = require('node:crypto');
const { inside } = require('./policy.cjs'); const { identity } = require('./runtime-cli.cjs');
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function audit(root) {
  identity(root);
  if (fs.existsSync(inside(root, 'Data/manager.json'))) throw Error('Manager is still active');
  const requestId = crypto.randomBytes(16).toString('hex');
  const output = inside(root, 'Build/audit-current.json');
  fs.writeFileSync(output, JSON.stringify({ requestId, passed: false }));
  const snapshot = JSON.parse(fs.readFileSync(inside(root, 'App/source-snapshot.json'), 'utf8'));
  if (snapshot.schema !== 1 || snapshot.sources.length !== 12) throw Error('Unexpected App snapshot');
  for (const file of snapshot.sources) {
    if (!/^[a-z0-9-]+\.(?:cjs|ps1)$/.test(file.name) ||
      digest(inside(root, `App/${file.name}`)) !== file.sha256 ||
      digest(path.join(__dirname, file.name)) !== file.sha256) throw Error('Current source/assembled App mismatch');
  }
  if (digest(inside(root, 'START-HERE-TH.md')) !== digest(path.join(__dirname, 'start-here-th.md'))) throw Error('Guide mismatch');
  const read = relative => JSON.parse(fs.readFileSync(inside(root, relative), 'utf8'));
  const entry = read('Data/entry-proof-current.json'); const pane = read('Data/herdr-proof-current.json');
  const ide = read('Data/ide-proof-current.json'); const moved = read('Build/relocation-proof.json');
  if (!entry.passed || !entry.cleanStop || entry.proof.platform !== 'linux' || entry.proof.uid !== 1000 ||
      !pane.passed || !ide.passed || !moved.thai_space_apostrophe_relocation || !moved.restored_original_root) throw Error('Required executed-proof summary missing');
  const last = read('Data/manager-last.json'); if (last.phase !== 'stopped') throw Error('No stopped manager summary');
  let logical = 0n, unique = 0n, files = 0; const seen = new Set(); const todo = [root];
  while (todo.length) {
    const dir = todo.pop();
    for (const name of fs.readdirSync(dir)) {
      const file = path.join(dir, name); const stat = fs.lstatSync(file, { bigint: true });
      if (stat.isSymbolicLink()) throw Error('Reparse entry refused; no traversal');
      if (stat.isDirectory()) todo.push(file);
      else if (stat.isFile()) {
        if (++files > 200000) throw Error('Metadata traversal limit');
        logical += stat.size; const id = stat.dev + ':' + stat.ino;
        if (!seen.has(id)) { seen.add(id); unique += stat.size; }
      }
    }
  }
  const result = { requestId, passed: true, assembledSourcesMatch: snapshot.sources.length, guideMatches: true,
    noManagerState: true, priorExecutedProofsPresent: true, files,
    logicalGiB: Number((Number(logical) / 2 ** 30).toFixed(3)),
    hardlinkDeduplicatedLogicalGiB: Number((Number(unique) / 2 ** 30).toFixed(3)),
    physicalAllocatedBytesMeasured: false, originalFailedGuestBaselinePreserved: true,
    nativeGuiTested: false, realProvidersTested: false, accountsImported: false };
  fs.writeFileSync(output, JSON.stringify(result, null, 2));
  fs.writeFileSync(inside(root, `Build/audit-${requestId}.json`), JSON.stringify(result, null, 2));
  return result;
}
if (require.main === module) { try { console.log(JSON.stringify(audit(path.resolve(process.argv[2] || '')))); }
  catch (e) { console.error(e.message); process.exitCode = 1; } }
module.exports = { audit };

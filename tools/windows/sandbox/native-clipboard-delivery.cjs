'use strict';
// Read-only public EXE delivery gate. No process, VM or clipboard access.
const fs = require('node:fs'), crypto = require('node:crypto');
function verify(file, expectedSha256) {
  if (!/^[a-f0-9]{64}$/.test(expectedSha256 || '')) throw Error('Verified native build hash required');
  const bytes = fs.readFileSync(file), sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  if (sha256 !== expectedSha256) throw Error('Installed native EXE differs from the clipboard-enabled build; App-only updates do not update native shortcuts');
  for (const binding of ['performable:ctrl+c=copy_to_clipboard', 'ctrl+v=paste_from_clipboard']) {
    if (!bytes.includes(Buffer.from(binding))) throw Error('Native EXE lacks the explicit sandbox clipboard shortcut contract');
  }
  return { passed: true, sha256, selectedCtrlCBinding: true, explicitCtrlVBinding: true };
}
if (require.main === module) {
  try { console.log(JSON.stringify(verify(process.argv[2], process.argv[3]))); }
  catch (e) { console.error(e.message); process.exitCode = 1; }
}
module.exports = { verify };

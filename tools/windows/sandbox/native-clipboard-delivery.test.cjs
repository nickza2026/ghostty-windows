'use strict';
const fs = require('node:fs'), os = require('node:os'), path = require('node:path'), crypto = require('node:crypto');
const test = require('node:test'), assert = require('node:assert/strict');
const { verify } = require('./native-clipboard-delivery.cjs');
test('native clipboard delivery rejects an App-only/old EXE and missing bindings', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clipboard-delivery-')); t.after(() => fs.rmSync(dir, { recursive: true }));
  const file = path.join(dir, 'synthetic.exe'), good = Buffer.from('synthetic public executable contract\0performable:ctrl+c=copy_to_clipboard\0ctrl+v=paste_from_clipboard');
  const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
  fs.writeFileSync(file, 'old synthetic executable');
  assert.throws(() => verify(file, sha(good)), /App-only/);
  assert.throws(() => verify(file, sha(fs.readFileSync(file))), /lacks/);
  fs.writeFileSync(file, good); assert.equal(verify(file, sha(good)).passed, true);
});

'use strict';
// Build-only filesystem operations through verified bundled Node: WinPS 5.1
// System.IO.Copy/Get-FileHash cannot reliably handle the deep npm tree paths.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const workspace = path.resolve(__dirname, '../..');
function root(value) {
  const p = path.resolve(value);
  assert(p.toLowerCase().startsWith((path.join(workspace, 'zig-out') + path.sep).toLowerCase()));
  for (let dir = p; dir.length >= workspace.length; dir = path.dirname(dir)) {
    if (fs.existsSync(dir)) assert(!fs.lstatSync(dir).isSymbolicLink(), 'Reparse ancestor refused');
    if (path.dirname(dir) === dir) break;
  }
  return p;
}
function walk(dir, visit) {
  assert(!fs.lstatSync(dir).isSymbolicLink(), 'Reparse directory refused');
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name); const stat = fs.lstatSync(p);
    assert(!stat.isSymbolicLink(), 'Reparse child refused');
    if (stat.isDirectory()) walk(p, visit); else { assert(stat.isFile()); visit(p, stat); }
  }
}
const mode = process.argv[2];
if (mode === 'copy-ready') {
  const from = root(process.argv[3]); const to = root(process.argv[4]);
  assert.notEqual(from.toLowerCase(), to.toLowerCase());
  let files = 0;
  for (const rel of ['bin/portable-data/npm/node_modules', 'bin/portable-data/runtimes/git', 'bin/portable-data/apps/herdr/0.9.5']) {
    const src = path.join(from, rel); const dest = path.join(to, rel);
    assert(!fs.existsSync(dest), 'Refuse to merge into used program software');
    fs.mkdirSync(dest, { recursive: true });
    walk(src, file => {
      const target = path.join(dest, path.relative(src, file));
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(file, target, fs.constants.COPYFILE_EXCL); files++;
    });
  }
  for (const rel of ['bin/portable-data/shims/git.exe', 'bin/portable-data/shims/git.proxy.json']) {
    const src = path.join(from, rel); assert(!fs.lstatSync(src).isSymbolicLink());
    fs.copyFileSync(src, path.join(to, rel), fs.constants.COPYFILE_EXCL); files++;
  }
  console.log(`READY_PUBLIC_PROGRAM_FILES_COPIED=${files}`);
} else if (mode === 'manifest' || mode === 'finalize') {
  const output = root(process.argv[3]); const files = [];
  const catalog = path.join(output, 'package-manifest.json');
  if(mode === 'finalize') assert(!fs.existsSync(catalog), 'Refuse to replace an existing factory catalog');
  // Skip mutable directories before descending, not after reading user files.
  function collect(dir) {
    assert(!fs.lstatSync(dir).isSymbolicLink());
    for (const name of fs.readdirSync(dir)) {
      const p = path.join(dir, name); const rel = path.relative(output, p).replaceAll('\\', '/');
      if (rel === 'package-manifest.json' || /^bin\/portable-data\/(profiles|home|cache|tmp|logs)(\/|$)/.test(rel)) continue;
      const stat = fs.lstatSync(p); assert(!stat.isSymbolicLink());
      if (stat.isDirectory()) collect(p);
      else files.push({ path: rel, bytes: stat.size, sha256: crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex').toUpperCase() });
    }
  }
  collect(output);
  if(mode === 'manifest') console.log(JSON.stringify(files));
  else{
    const metadata = path.resolve(process.argv[4]);
    assert(metadata.toLowerCase().startsWith((path.join(output,'bin/portable-data/profiles/herdr/tmp')+path.sep).toLowerCase()));
    root(path.dirname(metadata)); assert(!fs.lstatSync(metadata).isSymbolicLink());
    const record=JSON.parse(fs.readFileSync(metadata,'utf8').replace(/^\uFEFF/,''));
    assert(record.ready_Herdr && record.user_data_copied === false && !record.files);
    fs.writeFileSync(catalog,JSON.stringify({...record,files},null,2),{flag:'wx'});
    console.log(`READY_FACTORY_FILES=${files.length}`);
  }
} else throw new Error('Unknown build filesystem operation');

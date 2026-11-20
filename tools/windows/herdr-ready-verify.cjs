'use strict';
// Verify the completed immutable factory payload without piping its large
// manifest through WinPS. Never descend into mutable user storage.
const fs=require('node:fs'); const path=require('node:path'); const crypto=require('node:crypto'); const assert=require('node:assert/strict');
const workspace=path.resolve(__dirname,'../..'); const root=path.resolve(process.argv[2]);
assert(root.toLowerCase().startsWith((path.join(workspace,'zig-out')+path.sep).toLowerCase()));
const m=JSON.parse(fs.readFileSync(path.join(root,'package-manifest.json'),'utf8').replace(/^\uFEFF/,''));
assert(m.ready_Herdr && m.user_data_copied===false && m.prepared_Letta.version==='0.34.23');
const expected=new Map();
const legacy=process.argv[3]==='--legacy-ps-array';
const entries=Array.isArray(m.files)?m.files:(legacy && m.files && Array.isArray(m.files.value) && m.files.Count===m.files.value.length?m.files.value:null);
assert(entries,'Factory files must be an array (legacy wrapper accepted only for explicit pre-repair verification)');
for(const f of entries){
  assert(!path.isAbsolute(f.path) && !f.path.split(/[\\/]/).includes('..'));
  const key=f.path.replaceAll('\\','/').toLowerCase(); assert(!expected.has(key)); expected.set(key,f);
}
let count=0, bytes=0;
function walk(dir){
  assert(!fs.lstatSync(dir).isSymbolicLink());
  for(const name of fs.readdirSync(dir)){
    const file=path.join(dir,name); const rel=path.relative(root,file).replaceAll('\\','/');
    if(/^bin\/portable-data\/(profiles|home|cache|tmp|logs)(\/|$)/.test(rel) || rel==='package-manifest.json') continue;
    const stat=fs.lstatSync(file); assert(!stat.isSymbolicLink());
    if(stat.isDirectory()) walk(file);
    else{
      const f=expected.get(rel.toLowerCase()); assert(f,'Uncatalogued immutable file: '+rel);
      assert.equal(stat.size,f.bytes,rel);
      assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').toLowerCase(),f.sha256.toLowerCase(),rel);
      expected.delete(rel.toLowerCase()); count++; bytes+=stat.size;
    }
  }
}
walk(root); assert.equal(expected.size,0,'Missing immutable factory files');
assert(!fs.existsSync(path.join(root,'bin/portable-data/profiles/herdr/home/.letta/local/memfs')),'Synthetic test agents were not retired');
console.log(JSON.stringify({passed:true,root,immutableFiles:count,immutableBytes:bytes,all_factory_hashes_verified:true,fresh_profile_no_test_agents:true,A_touched:false},null,2));

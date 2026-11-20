'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');const {spawnSync}=require('node:child_process');const {build}=require('./build-launcher-fix.cjs');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
test('small patch refuses modified/active targets, preserves Data, applies idempotently and runs real preflight under Restricted parent', {skip:process.platform!=='win32'},()=>{
 const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'ghostty-fix-install-'));
 try{
  const output=path.join(scratch,'build');build(output);const root=path.join(scratch,'target');fs.cpSync(path.join(output,'bundle'),root,{recursive:true});
  const patch=path.join(root,'launcher-fix-20261113'),manifest=JSON.parse(fs.readFileSync(path.join(patch,'manifest.json'),'utf8'));
  const baseline=path.resolve(__dirname,'../../../zig-out/sandbox-prototype-20261112-1450');
  for(const f of [...manifest.files,...manifest.unchanged]){const dest=path.join(root,f.name);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(path.join(baseline,f.name),dest);}
  fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce:'synthetic-owned-fixture'}));
  fs.mkdirSync(path.join(root,'Data'));const sentinel=path.join(root,'Data/DO-NOT-CHANGE');fs.writeFileSync(sentinel,'synthetic user data');const beforeData=sha(sentinel);
  const node=path.join(root,'Runtime/node/node.exe');fs.mkdirSync(path.dirname(node),{recursive:true});fs.copyFileSync(process.execPath,node);
  const apply=()=>spawnSync(node,[path.join(patch,'install.cjs')],{windowsHide:true,cwd:root,shell:false,encoding:'utf8',timeout:15000});
  const first=path.join(root,'Open-Terminal.cmd'),original=sha(first),modified=path.join(root,'Open-IDE.cmd');fs.appendFileSync(modified,'\r\nrem unique user edit\r\n');
  let r=apply();assert.notEqual(r.status,0);assert.match(r.stderr,/modified file preserved/);assert.equal(sha(first),original);assert.equal(sha(sentinel),beforeData);fs.copyFileSync(path.join(baseline,'Open-IDE.cmd'),modified);
  const manager=path.join(root,'Data/manager.json');fs.writeFileSync(manager,'{}');r=apply();assert.notEqual(r.status,0);assert.match(r.stderr,/Stop this sandbox/);assert.equal(sha(first),original);fs.unlinkSync(manager);
  const payload=path.join(patch,'payload/App/entry.cjs');fs.appendFileSync(payload,'\n// corrupted fixture\n');r=apply();assert.notEqual(r.status,0);assert.match(r.stderr,/payload hash mismatch/);assert.equal(sha(first),original);fs.copyFileSync(path.join(output,'bundle/launcher-fix-20261113/payload/App/entry.cjs'),payload);
  r=apply();assert.equal(r.status,0,r.stderr);for(const f of manifest.files)assert.equal(sha(path.join(root,f.name)),f.after);assert.equal(sha(sentinel),beforeData);
  r=apply();assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/already applied/);assert.equal(sha(sentinel),beforeData);
  const code="const cp=require('node:child_process');require('./App/entry.cjs').preflight(process.cwd(),(e,a,o)=>cp.spawnSync(e,a,{...o,env:{...o.env,PSExecutionPolicyPreference:'Restricted'}}));";
  const live=spawnSync(node,['-e',code],{cwd:root,windowsHide:true,shell:false,encoding:'utf8',timeout:20000});assert.equal(live.status,0,live.stderr);assert.match(live.stdout,/WHPX_READY/);assert.equal(sha(sentinel),beforeData);
 }finally{fs.rmSync(scratch,{recursive:true,force:true});}
});

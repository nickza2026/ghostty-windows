'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const {build}=require('./build-exfat-patch.cjs');const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
for(const version of ['original','policy-v1'])test('exFAT code-only patch preserves Data/opt-in and rejects edits from '+version,{skip:process.platform!=='win32'},()=>{
 const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'sandbox-exfat-patch-'));
 try{
  const out=path.join(scratch,'build');build(out);const root=path.join(scratch,'target');fs.cpSync(path.join(out,'bundle'),root,{recursive:true});
  const base=path.resolve(__dirname,version==='original'?'../../../zig-out/sandbox-prototype-20261112-1450':'../../../zig-out/sandbox-launcher-fix-20261113-2255/generated');
  const patch=path.join(root,'exfat-fix-20261114'),manifestFile=path.join(patch,'manifest.json'),manifest=JSON.parse(fs.readFileSync(manifestFile,'utf8'));
  for(const f of manifest.files){const src=path.join(base,f.name);if(fs.existsSync(src)){const to=path.join(root,f.name);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(src,to);}}
  fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce:'synthetic-exfat-patch-test'}));
  fs.mkdirSync(path.join(root,'Data'));const data=path.join(root,'Data/sentinel');fs.writeFileSync(data,'synthetic persistent data');
  const flag=path.join(root,'portable-storage.json'),flagText='{"schema":1,"storageMode":"exfat-reduced-protection"}';fs.writeFileSync(flag,flagText);
  const node=path.join(root,'Runtime/node/node.exe');fs.mkdirSync(path.dirname(node),{recursive:true});fs.copyFileSync(process.execPath,node);
  const apply=()=>spawnSync(node,[path.join(patch,'install.cjs')],{cwd:root,windowsHide:true,shell:false,encoding:'utf8',timeout:15000});
  const target=path.join(root,'App/entry.cjs'),before=sha(target);fs.appendFileSync(target,'\n// unique user edit\n');let r=apply();assert.notEqual(r.status,0);assert.match(r.stderr,/modified file preserved/);fs.copyFileSync(path.join(base,'App/entry.cjs'),target);
  const manager=path.join(root,'Data/manager.json');fs.writeFileSync(manager,'{}');r=apply();assert.notEqual(r.status,0);assert.match(r.stderr,/Stop the sandbox/);assert.equal(sha(target),before);fs.unlinkSync(manager);
  const text=fs.readFileSync(manifestFile,'utf8');manifest.files[0].name='Data/sentinel';fs.writeFileSync(manifestFile,JSON.stringify(manifest));r=apply();assert.notEqual(r.status,0);assert.match(r.stderr,/fixed patch target/);assert.equal(fs.readFileSync(data,'utf8'),'synthetic persistent data');fs.writeFileSync(manifestFile,text);
  r=apply();assert.equal(r.status,0,r.stderr);for(const f of JSON.parse(text).files)assert.equal(sha(path.join(root,f.name)),f.after);
  assert.equal(fs.readFileSync(flag,'utf8'),flagText);assert.equal(fs.readFileSync(data,'utf8'),'synthetic persistent data');
  r=apply();assert.equal(r.status,0,r.stderr);assert.equal(JSON.parse(fs.readFileSync(path.join(patch,'applied.json'),'utf8')).changed,0);
 }finally{fs.rmSync(scratch,{recursive:true,force:true,maxRetries:10,retryDelay:50});}
});

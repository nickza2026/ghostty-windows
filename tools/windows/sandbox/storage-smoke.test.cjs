'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),cp=require('node:child_process');
const {assemble}=require('./assemble.cjs'),prototype=require('./prototype.cjs'),storage=require('./storage-policy.cjs');
function relocate(from,to){
  // Windows can briefly refuse directory moves immediately after an image exits.
  // Retry only sharing/access errors on this owned fixture; never skip the move.
  const until=Date.now()+3000;
  for(;;){try{fs.renameSync(from,to);return;}catch(e){if(!['EPERM','EACCES','EBUSY'].includes(e.code)||Date.now()>=until)throw e;Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,50);}}
}
function owned(fn){const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'sandbox-storage-smoke-')),root=path.join(scratch,'package');fs.mkdirSync(root);try{fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce:'synthetic-storage-smoke'}));return fn(root);}finally{fs.rmSync(scratch,{recursive:true,force:true});}}
test('real private Node enable command exits zero, is idempotent, and follows a moved root without VM operations',{skip:process.platform!=='win32'},()=>owned(root=>{
  assemble(root);let activeRoot=root,exe=path.join(root,'Runtime/node/node.exe');fs.mkdirSync(path.dirname(exe),{recursive:true});fs.copyFileSync(process.execPath,exe);
  const invoke=()=>cp.spawnSync(exe,[path.join(activeRoot,'App/entry.cjs'),'enable-exfat',activeRoot,'--accept-unprotected-storage'],{windowsHide:true,shell:false,encoding:'utf8',timeout:10000});
  let r=invoke();assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/mode accepted/);
  const flag=fs.readFileSync(path.join(root,'portable-storage.json'),'utf8');r=invoke();assert.equal(r.status,0,r.stderr);assert.equal(fs.readFileSync(path.join(root,'portable-storage.json'),'utf8'),flag);
  assert.equal(fs.existsSync(path.join(root,'Data/manager.json')),false);
  const inventory=JSON.parse(fs.readFileSync(path.join(root,'App/source-snapshot.json'),'utf8')).sources;
  assert.equal(inventory.length,21);assert.equal(new Set(inventory.map(f=>f.name)).size,21);
  for(const name of ['guest-config.cjs','guest-password-hash.cjs','terminal-protocol.cjs','guest-terminal.py'])assert.ok(inventory.some(f=>f.name===name));
  const moved=path.join(path.dirname(root),"ย้าย root ' spaces");relocate(root,moved);activeRoot=moved;exe=path.join(moved,'Runtime/node/node.exe');r=invoke();assert.equal(r.status,0,r.stderr);assert.equal(fs.readFileSync(path.join(moved,'portable-storage.json'),'utf8'),flag);
}));
test('bootstrapCurrent rejects replaced disk and malformed proof without blessing old metadata',()=>owned(root=>{
  fs.mkdirSync(path.join(root,'Data/ssh'),{recursive:true});const disk=path.join(root,'Data/guest.qcow2'),proof=path.join(root,'Data/bootstrap-verified.json');
  assert.equal(prototype.bootstrapCurrent(root),false);fs.writeFileSync(disk,'synthetic disk, not booted');const s=fs.statSync(disk,{bigint:true});
  const instanceId='portable-'+'a'.repeat(32),hostKey='ssh-ed25519 SYNTHETIC_PUBLIC_KEY';fs.writeFileSync(path.join(root,'Data/vm.json'),JSON.stringify({instanceId}));fs.writeFileSync(path.join(root,'Data/ssh/trusted_host_key'),hostKey);
  fs.writeFileSync(proof,JSON.stringify({bootId:'b'.repeat(32),instanceId,hostKey,disk:{fileId:s.ino.toString(),createdNs:s.birthtimeNs.toString()}}));assert.equal(prototype.bootstrapCurrent(root),true);
  const replacement=path.join(root,'Data/replacement');fs.writeFileSync(replacement,'replacement');fs.unlinkSync(disk);fs.renameSync(replacement,disk);assert.equal(prototype.bootstrapCurrent(root),false);
  fs.writeFileSync(proof,'{');assert.throws(()=>prototype.bootstrapCurrent(root));
}));
test('actual inbox key loader validates synthetic portable key and rejects mismatched pub without fallback',{skip:process.platform!=='win32'},()=>owned(root=>{
  storage.prepare(root);fs.mkdirSync(path.join(root,'Data/ssh'));const key=path.join(root,'Data/ssh/client_key');
  const r=cp.spawnSync(path.join(process.env.SystemRoot,'System32/OpenSSH/ssh-keygen.exe'),['-q','-t','ed25519','-N','','-C','synthetic-only','-f',key],{windowsHide:true,shell:false,encoding:'utf8',timeout:15000,env:storage.environment(root)});
  assert.equal(r.status,0,r.stderr);const pub=fs.readFileSync(key+'.pub','utf8');prototype.checkClientKey(root,pub);assert.throws(()=>prototype.checkClientKey(root,'ssh-ed25519 synthetic-wrong'),/mismatch/);
}));

'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const {importKey}=require('./private-openssh-key.cjs'),agent=require('./private-agent.cjs'),storage=require('./storage-policy.cjs');
test('native-generated Ed25519 formats preserve identity; reject seed/check/padding/header corruption without replacing files',{skip:process.platform!=='win32'},()=>{
 const root=fs.mkdtempSync(path.resolve(__dirname,'../../../zig-out/key-import-proof-'));
 try{
  fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({name:'ghostty-sandbox-owned',schema:1,nonce:crypto.randomBytes(16).toString('hex')}));storage.prepare(root);fs.mkdirSync(path.join(root,'Data/ssh'));
  const keygen=path.join(process.env.SystemRoot,'System32/OpenSSH/ssh-keygen.exe');
  for(let i=1;i<=8;i++){
   const file=path.join(root,'Data/ssh',i===1?'client_key':'key-'+i);
   const made=spawnSync(keygen,['-q','-t','ed25519','-N','','-C','x'.repeat(i),'-f',file],{env:storage.environment(root),windowsHide:true,shell:false,timeout:10000});assert.equal(made.status,0);
   const bytes=fs.readFileSync(file),pub=fs.readFileSync(file+'.pub','utf8'),key=agent.identity(importKey(bytes));
   assert.equal(agent.publicLine(key).split(' ').slice(0,2).join(' '),pub.split(' ').slice(0,2).join(' '));
   const raw=Buffer.from(bytes.toString().split(/\r?\n/).slice(1,-2).join(''),'base64');
   const armour=b=>Buffer.from('-----BEGIN OPENSSH PRIVATE KEY-----\n'+b.toString('base64')+'\n-----END OPENSSH PRIVATE KEY-----\n');
   const changed=Buffer.from(raw),first=changed.indexOf('ssh-ed25519'),second=changed.indexOf('ssh-ed25519',first+1);assert(second>first);
   changed[second+11+4+32+4]^=1;assert.throws(()=>importKey(armour(changed)),/Unsupported or corrupt/);
   const check=Buffer.from(raw);check[second-12]^=1;assert.throws(()=>importKey(armour(check)));
   const paddingStart=second+11+4+32+4+64+4+i;if(paddingStart<raw.length){const padding=Buffer.from(raw);padding[padding.length-1]=0;assert.throws(()=>importKey(armour(padding)));}
   const encrypted=Buffer.from(raw);encrypted[19]=97;assert.throws(()=>importKey(armour(encrypted)));
   const badHeader=Buffer.from(raw);badHeader[0]^=1;assert.throws(()=>importKey(armour(badHeader)));
   assert.throws(()=>importKey(Buffer.concat([bytes,Buffer.from('unexpected trailing bytes')])));
  }
  const file=path.join(root,'Data/ssh/client_key'),before=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  assert.throws(()=>agent.load(root,'ssh-ed25519 wrong'),/mismatch/);assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),before);
  assert.throws(()=>importKey(Buffer.alloc(16385)));assert.throws(()=>importKey(Buffer.from('not a key')));
 }finally{fs.rmSync(root,{recursive:true,force:true,maxRetries:10,retryDelay:100});}
});

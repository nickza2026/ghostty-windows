'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const storage = require('./storage-policy.cjs');
function fixture(fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sandbox-storage-'));
  try { fs.writeFileSync(path.join(root, 'sandbox-owned.json'), JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce:'synthetic-fixture-ownership'})); return fn(root); }
  finally { fs.rmSync(root, {recursive:true,force:true}); }
}
test('filesystem policy requires actual exFAT plus explicit opt-in; NTFS never loses ACLs', () => {
  assert.throws(() => storage.select('exFAT', {storageMode:'strict'}), /opt-in/);
  assert.equal(storage.select('exFAT', {storageMode:storage.reducedMode}).protection, 'reduced');
  for (const mode of ['strict', storage.reducedMode]) assert.equal(storage.select('NTFS', {storageMode:mode}).protection, 'acl');
  for (const fsName of ['', 'FAT32', 'unknown', null]) assert.throws(() => storage.select(fsName, {storageMode:storage.reducedMode}), /unknown storage/);
});
test('opt-in requires exact acceptance, package marker, no manager, and preserves existing configuration', () => fixture(root => {
  assert.equal(storage.read(root).storageMode, 'strict');
  assert.throws(() => storage.enable(root), /acceptance/);
  fs.mkdirSync(path.join(root,'Data'));fs.writeFileSync(path.join(root,'Data/manager.json'),'{}');
  assert.throws(() => storage.enable(root,{acknowledged:true}), /Stop this sandbox/);
  fs.unlinkSync(path.join(root,'Data/manager.json'));
  assert.equal(storage.enable(root,{acknowledged:true}).storageMode, storage.reducedMode);
  const saved=fs.readFileSync(path.join(root,'portable-storage.json'),'utf8');
  storage.enable(root,{acknowledged:true});assert.equal(fs.readFileSync(path.join(root,'portable-storage.json'),'utf8'),saved);
  for (const value of [{schema:1,storageMode:true},{schema:2,storageMode:storage.reducedMode},{schema:1,storageMode:storage.reducedMode,extra:true}]) {
    fs.writeFileSync(path.join(root,'portable-storage.json'),JSON.stringify(value));assert.throws(()=>storage.read(root),/Invalid portable storage/);
  }
}));
test('storage subprocess stays private, RemoteSigned only, no ACL failure fallback or forged reduced NTFS result', () => fixture(root => {
  let captured;
  const run=(exe,args,options)=>{captured={exe,args,options};return{status:0,stdout:'{"schema":1,"filesystem":"NTFS","protection":"acl"}'};};
  assert.equal(storage.prepare(root,{run,source:{SystemRoot:'C:\\Windows',API_KEY:'synthetic-secret'}}).protection,'acl');
  assert.equal(captured.args.includes('-AllowExfat'),false);assert.equal(captured.options.env.API_KEY,undefined);assert.equal(captured.options.env.TEMP,path.join(root,'Data'));assert.equal(captured.options.shell,false);
  assert.deepEqual(captured.args.slice(0,4),['-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned']);
  storage.enable(root,{acknowledged:true});storage.prepare(root,{run});assert.equal(captured.args.includes('-AllowExfat'),true);
  assert.throws(()=>storage.prepare(root,{run:()=>({status:1,stderr:'Private data is not owned by the current user'})}),/not owned/);
  assert.throws(()=>storage.prepare(root,{run:()=>({status:0,stdout:'{"schema":1,"filesystem":"NTFS","protection":"reduced"}'})}),/Invalid storage protection/);
  let warned='';assert.equal(storage.prepare(root,{run:()=>({status:0,stdout:'{"schema":1,"filesystem":"exFAT","protection":"reduced"}'}),warn:x=>warned=x}).protection,'reduced');assert.match(warned,/read\/modify/);
}));
test('real NTFS still establishes ACL protection with an exFAT opt-in copied onto it', {skip:process.platform!=='win32'},()=>fixture(root=>{
  storage.enable(root,{acknowledged:true});const result=storage.prepare(root);
  assert.equal(result.filesystem,'NTFS');assert.equal(result.protection,'acl');
}));

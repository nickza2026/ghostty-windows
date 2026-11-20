'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const storage=require('./storage-policy.cjs'),prototype=require('./prototype.cjs');
const json=f=>JSON.parse(fs.readFileSync(f,'utf8').replace(/^\uFEFF/,''));
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,f))).digest('hex');
function probe(job){
 job=path.resolve(job);const match=/^D:\\works\\ghostty-windows\\zig-out\\exfat-vhd-test-([a-f0-9]{32})$/i.exec(job);if(!match)throw Error('Not an owned test job');
 const nonce=match[1],state=json(path.join(job,'state.json')),volume='Z:\\';
 if(state.nonce!==nonce||state.phase!=='ready'||state.drive!==volume)throw Error('No fresh ready test volume');
 const owner=json(path.join(volume,'ghostty-test-volume.json'));
 if(owner.kind!=='owned-disposable-exfat-test'||owner.nonce!==nonce||path.resolve(owner.image)!==path.join(job,'test.vhdx'))throw Error('Test volume ownership mismatch');
 const root=path.join(volume,'sandbox-probe-'+nonce);if(fs.existsSync(root))throw Error('Fresh probe root required');
 const result={schema:1,nonce,stage:'native-storage-key-probe',guestStarted:false,realAccountsUsed:false,
  storageSource:hash('storage-policy.cjs'),prototypeSource:hash('prototype.cjs'),passed:false};
 try{
  fs.mkdirSync(root);fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({name:'ghostty-sandbox-owned',schema:1,nonce}));
  let strictRejected=false;try{storage.prepare(root,{warn(){}});}catch(e){strictRejected=/exFAT/i.test(e.message)&&/opt-in/i.test(e.message);if(!strictRejected)throw e;}
  if(!strictRejected)throw Error('Default protection unexpectedly accepted exFAT');result.strictDefaultRejected=true;
  storage.enable(root,{acknowledged:true});const selected=storage.prepare(root,{warn(){}});
  if(selected.filesystem!=='exFAT'||selected.protection!=='reduced')throw Error('Actual exFAT selection not verified');result.filesystem='exFAT';result.reducedStorageVerified=true;
  fs.mkdirSync(path.join(root,'Data/ssh'));const key=path.join(root,'Data/ssh/client_key');
  const keygen=path.join(process.env.SystemRoot,'System32/OpenSSH/ssh-keygen.exe');
  const create=spawnSync(keygen,['-q','-t','ed25519','-N','','-C','disposable-exfat-probe','-f',key],{windowsHide:true,shell:false,encoding:'utf8',timeout:15000,env:storage.environment(root)});
  if(create.status!==0)throw Object.assign(Error('Synthetic key creation failed'),{code:'KEYGEN_FAILED'});
  prototype.checkClientKey(root,fs.readFileSync(key+'.pub','utf8'));
  result.nativeKeyLoad=true;result.passed=true;
 }catch(e){result.errorCode=['SSH_KEY_STORAGE_UNSUPPORTED','SSH_KEY_MISMATCH','KEYGEN_FAILED'].includes(e.code)?e.code:'PROBE_ABORTED';result.nativeKeyLoad=false;}
 fs.writeFileSync(path.join(job,'key-probe.json'),JSON.stringify(result,null,2));
 // A failed probe never launched a guest; the elevated lease can safely retire it.
 if(!result.passed)fs.writeFileSync(path.join(job,'done.json'),JSON.stringify({nonce,guestStopped:true}));
 console.log(JSON.stringify(result));return result;
}
if(require.main===module){try{if(!probe(process.argv[2]).passed)process.exitCode=1;}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={probe};

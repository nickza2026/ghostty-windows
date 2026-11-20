'use strict';
// Owned disposable VHD only. Start from pinned public Runtime/base, not any
// existing Data/profile/account. No GUI, provider login, shared drives or A:.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const storage=require('./storage-policy.cjs'),cli=require('./runtime-cli.cjs'),{assemble}=require('./assemble.cjs');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const json=f=>JSON.parse(fs.readFileSync(f,'utf8').replace(/^\uFEFF/,''));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function copyPublic(from,to){
 const stat=fs.lstatSync(from);if(stat.isSymbolicLink())throw Error('Reparse runtime source refused');
 if(stat.isDirectory()){fs.mkdirSync(to,{recursive:true});for(const name of fs.readdirSync(from))copyPublic(path.join(from,name),path.join(to,name));}
 else if(stat.isFile())fs.copyFileSync(from,to);else throw Error('Non-file public runtime asset refused');
}
async function verify(job){
 job=path.resolve(job);const m=/^D:\\works\\ghostty-windows\\zig-out\\exfat-vhd-test-([a-f0-9]{32})$/i.exec(job);if(!m)throw Error('Owned job required');
 const nonce=m[1],state=json(path.join(job,'state.json')),owner=json('Z:\\ghostty-test-volume.json');
 if(state.nonce!==nonce||state.phase!=='ready'||owner.nonce!==nonce||owner.kind!=='owned-disposable-exfat-test'||path.resolve(owner.image)!==path.join(job,'test.vhdx'))throw Error('No fresh associated exFAT volume');
 let root=path.join('Z:\\','sandbox-flow-'+nonce),active,stopped=true;
 const report={schema:1,nonce,passed:false,stage:'preparing',guiTested:false,realProvidersTested:false,profilesImported:false,startedFrom:'pinned-public-base',rounds:[]};
 const save=()=>{report.root=root;fs.writeFileSync(path.join(job,'flow-proof.json'),JSON.stringify(report,null,2));};save();
 async function stopOwned(){
  const found=await cli.existing(root);if(found&&found.state.managerNonce!==active)throw Error('Manager changed; no stop sent');
  if(found)await cli.main(['stop',root],{print(){}});
  const until=Date.now()+35000;while(fs.existsSync(path.join(root,'Data/manager.json'))&&Date.now()<until)await sleep(100);
  if(fs.existsSync(path.join(root,'Data/manager.json')))throw Error('Owned guest shutdown incomplete; no automatic force-cut');
  const last=json(path.join(root,'Data/manager-last.json'));if(last.managerNonce!==active||last.phase!=='stopped')throw Error('Missing current normal-stop receipt');
  active=undefined;stopped=true;
 }
 function guest(script){
  const encoded=Buffer.from(script).toString('base64'),exe=path.join(process.env.SystemRoot,'System32/OpenSSH/ssh.exe');
  const result=spawnSync(exe,['-F',path.join(root,'Data/ssh/config'),'portable-sandbox',`node -e "eval(Buffer.from('${encoded}','base64').toString())"`],{cwd:root,env:storage.environment(root),windowsHide:true,shell:false,encoding:'utf8',timeout:25000,maxBuffer:65536,stdio:['ignore','pipe','pipe']});
  if(result.status!==0)throw Error('Owned guest SSH proof failed; no alternate identity or host fallback');
  const rows=result.stdout.split(/\r?\n/).filter(l=>l.startsWith('EXFAT_FLOW '));if(rows.length!==1)throw Error('No single current semantic guest proof');
  const proof=JSON.parse(rows[0].slice(11));if(proof.nonce!==nonce||proof.platform!=='linux'||proof.uid!==1000||proof.home!=='/home/sandbox'||proof.version!=='v24.22.1')throw Error('Guest identity mismatch');return proof;
 }
 try{
  if(fs.existsSync(root))throw Error('Fresh flow fixture required');fs.mkdirSync(root);
  fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({name:'ghostty-sandbox-owned',schema:1,nonce}));
  let rejected=false;try{storage.prepare(root,{warn(){}});}catch(e){if(/exFAT/i.test(e.message)&&/opt-in/i.test(e.message))rejected=true;else throw e;}
  if(!rejected)throw Error('Default mode did not reject exFAT');report.strictDefaultRejected=true;
  const source=path.resolve(__dirname,'../../../zig-out/sandbox-prototype-20261112-1450');
  copyPublic(path.join(source,'Runtime'),path.join(root,'Runtime'));fs.mkdirSync(path.join(root,'Build'));
  const manifests=fs.readdirSync(path.join(source,'Build')).filter(n=>/^acquisition-.+-complete\.json$/.test(n));if(manifests.length!==1)throw Error('No unique public acquisition');
  fs.copyFileSync(path.join(source,'Build',manifests[0]),path.join(root,'Build',manifests[0]));
  assemble(root);report.sourceSnapshot=json(path.join(root,'App/source-snapshot.json'));
  storage.enable(root,{acknowledged:true});const mode=storage.prepare(root,{warn(){}});if(mode.filesystem!=='exFAT'||mode.protection!=='reduced')throw Error('Actual reduced exFAT mode not verified');
  const content='ทดสอบข้อมูลถาวร exFAT '+nonce,expected=sha(Buffer.from(content));let previous;
  for(let round=1;round<=2;round++){
   report.stage='cold-start-'+round;save();stopped=false;
   const begun=await cli.ensure(root);active=begun.state.managerNonce;if(active===previous)throw Error('Reused stale manager');previous=active;
   const ready=await cli.ready(root);if(ready.state.managerNonce!==active||ready.answer.phase!=='ready')throw Error('No fresh guest ready');
   const common=`const fs=require('fs'),crypto=require('crypto'),f='/home/sandbox/workspaces/exfat-proof-${nonce}.txt';`;
   const script=common+(round===1?`fs.writeFileSync(f,${JSON.stringify(content)});`:'')+`console.log('EXFAT_FLOW '+JSON.stringify({nonce:${JSON.stringify(nonce)},platform:process.platform,uid:process.getuid(),home:process.env.HOME,version:process.version,sha256:crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex')}));`;
   const proof=guest(script);if(proof.sha256!==expected)throw Error('UTF-8 persistence mismatch');
   await stopOwned();report.rounds.push({round,nativeSsh:true,utf8Persistence:true,normalStop:true});save();
   if(round===1){
    const moved=path.join('Z:\\',"ทดสอบ exFAT ย้าย ' "+nonce);if(fs.existsSync(moved))throw Error('Relocation target exists');
    const until=Date.now()+3000;for(;;){try{fs.renameSync(root,moved);root=moved;break;}catch(e){if(!['EPERM','EBUSY','EACCES'].includes(e.code)||Date.now()>=until)throw e;await sleep(100);}}
    report.relocatedWithinExfat=true;save();
   }
  }
  report.stage='packaged-terminal-entry';stopped=false;save();
  const entry=await require('./verify-entry.cjs').verify(root);
  if(!entry.passed||!entry.cleanStop)throw Error('No semantic packaged-terminal normal-stop proof');
  stopped=true;report.packagedTerminal={passed:true,mode:entry.mode,nativeInteractiveGuiTested:false};
  const receipts=fs.readdirSync(path.join(root,'Data')).filter(n=>/^boot-[a-f0-9]{32}\.json$/.test(n)).map(n=>json(path.join(root,'Data',n)));
  if(receipts.length!==6||receipts.some(r=>!r.ok||!r.qemuExited||r.qemuExitCode!==0)||receipts.filter(r=>r.stage==='bootstrap').length!==3)throw Error('No six fresh clean bootstrap/runtime shutdown receipts');
  report.bootReceipts=receipts.map(({stage,bootId,ok,qemuExited,qemuExitCode})=>({stage,bootId,ok,qemuExited,qemuExitCode}));report.stage='complete';report.passed=true;
 }catch(e){report.error=e.message;if(active){try{await stopOwned();}catch{stopped=false;report.cleanup='needs-explicit-owned-guest-stop';}}throw e;}
 finally{
  save();if(stopped)fs.writeFileSync(path.join(job,'done.json'),JSON.stringify({nonce,guestStopped:true}));
  console.log(JSON.stringify({nonce,passed:report.passed,stage:report.stage,rounds:report.rounds,error:report.error,cleanup:report.cleanup,root}));
 }
 return report;
}
if(require.main===module)verify(process.argv[2]).catch(()=>{process.exitCode=1;});module.exports={verify};

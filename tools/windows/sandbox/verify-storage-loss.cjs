'use strict';
// Synthetic ConPTY roots only: no backend imports, guest disks or real USB.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const { inputScript } = require('./native-window-input.cjs');
const repo = path.resolve(__dirname, '../../..');
const sha = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function copy(from, to) {
  const s = fs.lstatSync(from); assert(!s.isSymbolicLink(), 'public source link refused');
  if (s.isDirectory()) { fs.mkdirSync(to); for (const n of fs.readdirSync(from)) copy(path.join(from,n),path.join(to,n)); }
  else { assert(s.isFile()); fs.copyFileSync(from,to); }
}
async function run(exe,args,options={}) {
  const child=cp.spawn(exe,args,{windowsHide:true,stdio:['ignore','pipe','pipe'],...options});
  let out='',err='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>err+=b);
  const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve);});
  return {code,out,err};
}
async function main() {
  assert.equal(process.platform,'win32');
  const candidate=path.resolve(process.argv[2]||'zig-out/usb-loss-20261120/shipping');
  const sender=path.resolve(process.argv[3]||'zig-out/usb-loss-20261120/storage-message-probe.exe');
  const baseline=path.join(repo,'zig-out/clipboard-validation-030e9ed2-9cba-489e-98ab-a53894809ce0/sandbox/bin/Sandbox.exe');
  assert.equal(sha(baseline),'f9272f69ef6c445231bbd46126afa071a755c4028ce469231006b3844992a9d6');
  const out=path.join(repo,'zig-out','storage-loss-fixture-'+crypto.randomUUID());fs.mkdirSync(out);
  const root=path.join(out,"ไทย space's");fs.mkdirSync(root);
  fs.mkdirSync(path.join(root,'App'));fs.mkdirSync(path.join(root,'Runtime'));fs.mkdirSync(path.join(root,'Runtime/node'));
  const publicNode=path.join(repo,'zig-out/sandbox-node-candidate-20261115-ebdfc56b/Sandbox-Node-Portable/Runtime/node/node.exe');
  fs.copyFileSync(publicNode,path.join(root,'Runtime/node/node.exe'));
  copy(path.join(candidate,'share'),path.join(root,'share'));
  fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({name:'ghostty-sandbox-owned',schema:1,nonce:crypto.randomBytes(16).toString('hex')}));
  const receipt={out,syntheticOnly:true,physicalUsbTested:false,realVmUsed:false,cases:[],passed:false};
  const save=()=>fs.writeFileSync(path.join(out,'receipt.json'),JSON.stringify(receipt,null,2));save();console.log(out);
  try {
    for (const [label,exe,expected] of [['original',baseline,2],['candidate',path.join(candidate,'bin/Sandbox.exe'),0]]) {
      fs.copyFileSync(exe,path.join(root,'Sandbox.exe'));
      const nonce=crypto.randomBytes(16).toString('hex');
      fs.writeFileSync(path.join(root,'App/entry.cjs'),`'use strict';const fs=require('fs'),path=require('path');const root=process.argv[3];const marker='LOCALTERM_SANDBOX_NATIVE_${nonce}';fs.writeFileSync(path.join(root,'child.json'),JSON.stringify({nonce:'${nonce}',pid:process.pid}));process.stdout.write('\\x1b[31m'+marker+' ไทย\\x1b[0m\\r\\n');process.stdin.setRawMode(true);let line='';process.stdin.on('data',b=>{line+=b.toString();if(line.includes('QUIT\\r'))process.exit(0)});setTimeout(()=>process.exit(7),60000);`);
      const started=Date.now(), child=cp.spawn(path.join(root,'Sandbox.exe'),[],{cwd:out,windowsHide:true,env:{SystemRoot:process.env.SystemRoot,ProgramData:process.env.ProgramData,LOCALTERM_SANDBOX_OFFSCREEN:'1'},stdio:['ignore','pipe','pipe']});
      let log='';for(const s of [child.stdout,child.stderr])s.on('data',b=>log+=b.toString());
      let ended=false;const exit=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',c=>{ended=true;resolve(c);});});
      const timeout=setTimeout(()=>{if(!ended)child.kill();},35000);
      const item={label,nonce,executableSha256:sha(exe)};receipt.cases.push(item);save();
      try {
        const deadline=Date.now()+15000;
        while(!ended&&!log.includes('sandbox native painted marker=LOCALTERM_SANDBOX_NATIVE_'+nonce)&&Date.now()<deadline)await new Promise(r=>setTimeout(r,50));
        assert(log.includes('sandbox native painted marker=LOCALTERM_SANDBOX_NATIVE_'+nonce),'fresh painted marker required before event');
        const own=JSON.parse(fs.readFileSync(path.join(root,'child.json'),'utf8'));assert.equal(own.nonce,nonce);
        const drive=root[0].toUpperCase().charCodeAt(0)-65;assert(drive>=0&&drive<26);
        const event=await run(sender,[String(child.pid),String(2**drive)]);
        item.messageResult=event.code;item.event=JSON.parse(event.out);assert.equal(event.code,expected,event.err);
        if(expected===2){
          const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
          const quit=await run(ps,['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(inputScript(child.pid,'QUIT','Sandbox'),'utf16le').toString('base64')]);
          assert.equal(quit.code,0,quit.err);
        }
        item.nativeExit=await exit;assert.equal(item.nativeExit,0,log);
        assert(log.includes('marker_painted=true')&&!log.includes('renderer_failed=true'));
        if(expected===0)assert(log.includes('storage_lost=true'),'candidate must record storage loss, not unrelated exit');
        assert.throws(()=>process.kill(own.pid,0),e=>e.code==='ESRCH','owned synthetic Node must exit');
        const frame=path.join(root,'Data/native/logs/sandbox-native-frame.bmp');assert(fs.statSync(frame).mtimeMs>=started-2000,'stale frame refused');
        fs.copyFileSync(frame,path.join(out,label+'-frame.bmp'));item.painted=true;item.ownedChildExited=true;
      } finally {clearTimeout(timeout);if(!ended){child.kill();await exit;}fs.writeFileSync(path.join(out,label+'.log'),log);save();}
    }
    receipt.originalDefectDetected=true;receipt.passed=true;save();console.log(JSON.stringify({passed:true,originalDefectDetected:true,candidateDisappeared:true,realVmUsed:false,physicalUsbTested:false,out}));
  } finally {save();}
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});

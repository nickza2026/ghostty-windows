'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{frame,resizeFrame}=require('./terminal-protocol.cjs'),{start}=require('./verify-conpty-host.cjs');
async function verify(root,hostPort){
 const nonce=crypto.randomBytes(16).toString('hex'),probe=path.join(root,'Build/real-console-terminal.cjs');
 fs.writeFileSync(probe,`const c=require(${JSON.stringify(path.join(root,'App/runtime-cli.cjs'))});(async()=>{const f=await c.existing(${JSON.stringify(root)});if(!f||f.answer.phase!=='ready')throw Error('No pre-existing ready owned manager');console.log('REAL_HOST_GEOMETRY '+JSON.stringify({tty:process.stdin.isTTY&&process.stdout.isTTY,columns:process.stdout.columns,rows:process.stdout.rows}));const p=c.terminalCommand(${JSON.stringify(root)});const code=await c.interactiveTerminal(p.executable,p.args,${JSON.stringify(root)});console.log('REAL_HOST_EXIT '+JSON.stringify({code,rawRestored:process.stdin.isRaw===false}));process.exitCode=code;})().catch(e=>{console.error(e.message);process.exitCode=1});`);
 const code=`const nonce=${JSON.stringify(nonce)};const p=()=>nonce+' '+process.stdout.columns+'x'+process.stdout.rows+' '+(process.stdin.isTTY?'T':'F')+(process.stdout.isTTY?'T':'F');const s=require('http').createServer((q,r)=>r.end(nonce));s.listen(8787,'0.0.0.0',()=>console.log('\\nREAL_GUEST_INITIAL '+p()));process.stdout.on('resize',()=>console.log('\\nREAL_GUEST_RESIZED '+p()));process.on('SIGINT',()=>{console.log('\\nREAL_GUEST_CTRL_C '+nonce);s.close(()=>process.exit(7));});setTimeout(()=>process.exit(99),20000);`;
 const command=`node -e "eval(Buffer.from('${Buffer.from(code).toString('base64')}','base64').toString())"; code=$?; exit "$code"\r`;
 const child=start(root,probe);child.stdin.on('error',()=>{});let data='',error='',sent=false,initial=false,resized=false,http=false;let timer;
 let rejectTest;const failure=new Promise((r,j)=>rejectTest=j);
 child.stdout.on('data',chunk=>{(async()=>{
  data+=chunk.toString('utf8');if(data.length>1048576)throw Error('ConPTY guest output bound');const plain=data.replace(/\x1b\[[0-9;?]*[A-Za-z]/g,'');
  if(!sent&&/sandbox@portable-sandbox[^\r\n]*\$/.test(plain)){sent=true;child.stdin.write(frame(1,Buffer.from(command)));}
  const first=/REAL_GUEST_INITIAL ([a-f0-9]{32}) (\d+)x(\d+) (TT|TF|FT|FF)/.exec(plain);if(first&&!initial){initial=true;if(first[1]!==nonce||first[2]!=='129'||first[3]!=='41'||first[4]!=='TT')throw Error('Real console→guest initial dimensions failed');const r=await fetch('http://127.0.0.1:'+hostPort,{signal:AbortSignal.timeout(5000)});if(await r.text()!==nonce)throw Error('Real console guest HTTP identity mismatch');http=true;child.stdin.write(resizeFrame({columns:91,rows:33}));}
  const changed=/REAL_GUEST_RESIZED ([a-f0-9]{32}) (\d+)x(\d+) (TT|TF|FT|FF)/.exec(plain);if(changed&&!resized){if(changed[1]!==nonce||changed[2]!=='91'||changed[3]!=='33'||changed[4]!=='TT')throw Error('Native resize not delivered end to end');resized=true;child.stdin.write(frame(1,Buffer.from([3])));}
 })().catch(e=>{rejectTest(e);child.kill();});});
 child.stderr.on('data',b=>error+=b);
 const completed=new Promise((resolve,reject)=>{timer=setTimeout(()=>{child.kill();reject(Error('Real ConPTY→guest deadline'));},30000);child.once('error',reject);child.once('close',code=>{
  clearTimeout(timer);const plain=data.replace(/\x1b\[[0-9;?]*[A-Za-z]/g,'');const host=/REAL_HOST_GEOMETRY (\{[^\r\n]+\})/.exec(plain),exit=/REAL_HOST_EXIT (\{[^\r\n]+\})/.exec(plain);
  if(code!==7||!host||!JSON.parse(host[1]).tty||!initial||!resized||!http||!plain.includes('REAL_GUEST_CTRL_C '+nonce)||!exit||!JSON.parse(exit[1]).rawRestored)reject(Error('Real ConPTY/guest proof incomplete: code='+code+' initial='+initial+' resize='+resized+' '+error.slice(-300)));
  else resolve({passed:true,realWindowsConPTY:true,realLinuxPTY:true,initial:[129,41],resized:[91,33],ctrlC:true,exitCode:7,hostRawRestored:true,loopbackHttp:true,noVisibleWindows:true});
 });});
 child.stdin.write(resizeFrame({columns:129,rows:41}));
 try{const result=await Promise.race([completed,failure]);fs.writeFileSync(path.join(root,'Build/conpty-guest.json'),JSON.stringify(result,null,2));return result;}
 finally{clearTimeout(timer);fs.writeFileSync(path.join(root,'Build/conpty-guest-debug.json'),JSON.stringify({stdout:data.slice(-65536),stderr:error.slice(-4096)}));if(child.exitCode===null)child.kill();}
}
module.exports={verify};

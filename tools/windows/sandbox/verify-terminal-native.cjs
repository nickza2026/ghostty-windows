'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),net=require('net'),{PassThrough}=require('stream'),{spawn}=require('child_process');
const cli=require('./runtime-cli.cjs'),{assemble}=require('./assemble.cjs'),{ssh,stop}=require('./verify-node-native.cjs');
const json=f=>JSON.parse(fs.readFileSync(f,'utf8').replace(/^\uFEFF/,''));
async function session(root,hostPort,nonce){
 const input=new PassThrough(),output=new PassThrough();output.columns=111;output.rows=37;
 let text='',sent=false,initial=false,resized=false,httpVerified=false,child,failed;
 const code=`const http=require('http');const nonce=${JSON.stringify(nonce)};const proof=()=>({nonce,columns:process.stdout.columns,rows:process.stdout.rows,inputTTY:process.stdin.isTTY,outputTTY:process.stdout.isTTY,platform:process.platform,cwd:process.cwd()});const s=http.createServer((q,r)=>{r.setHeader('content-type','application/json');r.end(JSON.stringify({nonce,guest:true}));});s.listen(8787,'0.0.0.0',()=>console.log('\\nNODE_LAYOUT_PROOF '+JSON.stringify(proof())));process.stdout.on('resize',()=>console.log('\\nNODE_RESIZE_PROOF '+JSON.stringify(proof())));process.on('SIGINT',()=>{console.log('\\nNODE_INTERRUPT_PROOF '+nonce);s.close(()=>process.exit(7));});setTimeout(()=>process.exit(98),30000);`;
 const encoded=Buffer.from(code).toString('base64');
 const command=`node -e "eval(Buffer.from('${encoded}','base64').toString())"; result=$?; exit "$result"\n`;
 let rejectEvent;const eventFailure=new Promise((r,j)=>rejectEvent=j);
 output.on('data',chunk=>{(async()=>{
  text+=chunk.toString('utf8');if(text.length>1048576)throw Error('Bounded terminal proof overflow');
  const plain=text.replace(/\x1b\[[0-9;?]*[A-Za-z]/g,'');
  if(!sent&&/sandbox@portable-sandbox[^\r\n]*\$/.test(plain)){sent=true;input.write(command);}
  const first=/\r?\nNODE_LAYOUT_PROOF (\{[^\r\n]+\})/.exec(plain);
  if(first&&!initial){initial=true;const p=JSON.parse(first[1]);if(p.nonce!==nonce||p.columns!==111||p.rows!==37||!p.inputTTY||!p.outputTTY||p.platform!=='linux'||p.cwd!=='/home/sandbox/workspaces')throw Error('Native initial PTY dimensions/identity incorrect');
   const r=await fetch('http://127.0.0.1:'+hostPort,{signal:AbortSignal.timeout(5000)});const body=await r.json();if(r.status!==200||body.nonce!==nonce||!body.guest)throw Error('Host dev forward did not reach owned guest service');httpVerified=true;
   output.columns=83;output.rows=29;output.emit('resize');
  }
  const changed=/\r?\nNODE_RESIZE_PROOF (\{[^\r\n]+\})/.exec(plain);
  if(changed&&!resized){const p=JSON.parse(changed[1]);if(p.nonce!==nonce||p.columns!==83||p.rows!==29)throw Error('Native SIGWINCH dimensions incorrect');resized=true;input.write(Buffer.from([3]));}
 })().catch(e=>{failed=e;rejectEvent(e);});});
 const c=cli.terminalCommand(root);const running=cli.interactiveTerminal(c.executable,c.args,root,{stdin:input,stdout:output,spawn:(...args)=>{child=spawn(...args);return child;}});
 let timer;const deadline=new Promise((r,j)=>{timer=setTimeout(()=>j(Error('Native terminal session deadline')),45000);});
 try{const exit=await Promise.race([running,eventFailure,deadline]);if(failed)throw failed;if(exit!==7||!initial||!resized||!httpVerified||!text.includes('NODE_INTERRUPT_PROOF '+nonce))throw Error('Incomplete Ctrl-C/exit/geometry/forward proof');return{initial:[111,37],resized:[83,29],sigwinch:true,ctrlC:true,exitCode:exit,httpHostToGuest:true};}
 finally{clearTimeout(timer);input.unpipe();input.destroy();if(child&&child.exitCode===null){child.kill();await running.catch(()=>{});}}
}
async function verify(root){
 root=path.resolve(root);const m=/^D:\\works\\ghostty-windows\\zig-out\\node-pty-test-([a-f0-9]{32})$/i.exec(root);if(!m||json(path.join(root,'sandbox-owned.json')).nonce!==m[1])throw Error('Explicit owned NTFS fixture only');
 const baseline=json(path.join(root,'Build/node-native.json'));if(!baseline.passed||!baseline.normalStop||!/^0 0/.test(baseline.originalForcedSshTty))throw Error('Original native zero-size baseline required');
 if(fs.existsSync(path.join(root,'Data/manager.json')))throw Error('Cannot replace running sources');
 fs.copyFileSync(path.join(root,'App/source-snapshot.json'),path.join(root,'Build/baseline-source-snapshot.json'));assemble(root);
 const report={schema:1,nonce:m[1],stage:'booting-fixed',passed:false,sourceSnapshot:json(path.join(root,'App/source-snapshot.json'))};const save=()=>fs.writeFileSync(path.join(root,'Build/terminal-fixed.json'),JSON.stringify(report,null,2));save();
 let active;
 try{
  const begun=await cli.ensure(root);active=begun.state.managerNonce;await cli.ready(root);report.stage='native-relay';save();
  report.terminal=await session(root,baseline.hostPort,crypto.randomBytes(16).toString('hex'));
  const token=crypto.randomBytes(16).toString('hex');ssh(root,['-T','portable-sandbox',`mkdir -p /home/sandbox/.local/bin; printf '${token}' > /home/sandbox/.local/bin/own-install-marker`]);report.userMarker=token;
  report.passed=true;report.stage='native-relay-passed';
 }catch(e){report.error=e.message;throw e;}finally{if(active){try{await stop(root,active);report.normalStop=true;}catch(e){report.cleanupError=e.message;report.passed=false;}}save();console.log(JSON.stringify({passed:report.passed,stage:report.stage,terminal:report.terminal,error:report.error,cleanupError:report.cleanupError,normalStop:report.normalStop,hostNativeConPTYTested:false}));}
}
if(require.main===module)verify(process.argv[2]).catch(e=>{console.error(e.message);process.exitCode=1});
module.exports={session,verify};

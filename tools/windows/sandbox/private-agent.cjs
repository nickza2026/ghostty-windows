'use strict';
const crypto=require('node:crypto'),path=require('node:path'),{spawn}=require('node:child_process');
const {environment}=require('./storage-policy.cjs');
const maximum=65536;
const integer=n=>{const b=Buffer.alloc(4);b.writeUInt32BE(n);return b;};
const string=b=>{b=Buffer.from(b);return Buffer.concat([integer(b.length),b]);};
const failure=()=>Buffer.from([5]);
function identity(privateKey){
  if(privateKey.type!=='private'||privateKey.asymmetricKeyType!=='ed25519')throw Error('Only a private Ed25519 identity is supported');
  const publicKey=crypto.createPublicKey(privateKey),spki=publicKey.export({type:'spki',format:'der'});
  if(spki.length!==44||spki.subarray(0,12).toString('hex')!=='302a300506032b6570032100')throw Error('Unexpected Ed25519 encoding');
  return{privateKey,publicKey,blob:Buffer.concat([string('ssh-ed25519'),string(spki.subarray(12))])};
}
function publicLine(key){return 'ssh-ed25519 '+key.blob.toString('base64')+' portable-sandbox\n';}
function load(root,pub){
  const fs=require('node:fs'),file=path.join(root,'Data/ssh/client_key');
  if(typeof pub!=='string'||pub.length>1024||/[\r\n\0]/.test(pub.trim()))throw Error('Invalid single public identity');
  if(fs.statSync(file).size>16384)throw Error('Portable key exceeds its bounded format');
  const bytes=fs.readFileSync(file);let key;
  try{key=identity(require('./private-openssh-key.cjs').importKey(bytes));}finally{bytes.fill(0);}
  if(pub.trim().split(/\s+/).slice(0,2).join(' ')!==publicLine(key).trim().split(/\s+/).slice(0,2).join(' '))throw Object.assign(Error('Portable SSH public/private key mismatch; no automatic replacement'),{code:'SSH_KEY_MISMATCH'});
  return key;
}
const validPipe=pipe=>typeof pipe==='string'&&/^\\\\\.\\pipe\\ghostty-sbx-[a-f0-9]{64}$/.test(pipe);
function invoke(exe,args,root,env){return new Promise((resolve,reject)=>{
  const child=spawn(exe,args,{cwd:root,env,windowsHide:true,shell:false,stdio:['ignore','pipe','pipe']});let output='';
  const timer=setTimeout(()=>{child.kill();reject(Error('Private agent native verification deadline'));},10000);
  child.stdout.on('data',b=>{output+=b.toString('utf8');if(output.length>16384)child.kill();});child.stderr.resume();
  child.once('error',()=>{clearTimeout(timer);reject(Error('Native agent verifier unavailable'));});child.once('close',code=>{clearTimeout(timer);resolve({code,output});});
});}
async function verifyClient(root,pipe,key){
  if(!validPipe(pipe))throw Error('Explicit private agent pipe required');
  const env={...environment(root),SSH_AUTH_SOCK:pipe},exe=path.join(process.env.SystemRoot||'C:\\Windows','System32/OpenSSH/ssh-add.exe');
  const listed=await invoke(exe,['-L'],root,env);
  const expected=publicLine(key).trim().split(/\s+/).slice(0,2).join(' '),lines=listed.output.trim().split(/\r?\n/);
  if(listed.code!==0||lines.length!==1||lines[0].split(/\s+/).slice(0,2).join(' ')!==expected)throw Error('Private agent did not enumerate exactly its package identity');
  const signed=await invoke(exe,['-T',path.join(root,'Data/ssh/client_key.pub')],root,env);
  if(signed.code!==0)throw Error('Native client rejected private-agent signing');
}
function answer(key,body){
  try{
    if(!Buffer.isBuffer(body)||body.length<1||body.length>maximum)return failure();
    if(body[0]===11&&body.length===1)return Buffer.concat([Buffer.from([12]),integer(1),string(key.blob),string('portable-sandbox')]);
    if(body[0]!==13)return failure();
    let at=1;const take=()=>{if(at+4>body.length)throw Error();const n=body.readUInt32BE(at);at+=4;if(n>maximum||at+n>body.length)throw Error();const b=body.subarray(at,at+n);at+=n;return b;};
    const requested=take(),data=take();
    if(at+4!==body.length||body.readUInt32BE(at)!==0||data.length>16384||!requested.equals(key.blob))return failure();
    const signature=crypto.sign(null,data,key.privateKey);
    return Buffer.concat([Buffer.from([14]),string(Buffer.concat([string('ssh-ed25519'),string(signature)]))]);
  }catch{return failure();}
}
async function start(root,key){
  const pipe='\\\\.\\pipe\\ghostty-sbx-'+crypto.randomBytes(32).toString('hex');
  const system=process.env.SystemRoot||'C:\\Windows';
  const child=spawn(path.join(system,'System32/WindowsPowerShell/v1.0/powershell.exe'),
    ['-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',path.join(__dirname,'private-agent-bridge.ps1'),'-PipeName',pipe],
    {cwd:root,env:environment(root),shell:false,windowsHide:true,stdio:['pipe','pipe','pipe']});
  let buffer=Buffer.alloc(0),ready=false,closed=false,diagnostic='',frames=0,window=performance.now();
  let resolveReady,rejectReady;const started=new Promise((resolve,reject)=>{resolveReady=resolve;rejectReady=reject;});
  const timer=setTimeout(()=>{rejectReady(Error('Private agent transport startup deadline'));child.kill();},15000);
  child.stdin.on('error',()=>{});
  child.stderr.on('data',b=>{if(diagnostic.length<8192)diagnostic+=b.toString('utf8');});
  child.on('error',()=>rejectReady(Error('Private agent transport unavailable')));
  child.on('exit',()=>{closed=true;clearTimeout(timer);if(!ready)rejectReady(Error('Private agent transport failed; no global-agent fallback'));});
  child.stdout.on('data',chunk=>{
    try{
      buffer=Buffer.concat([buffer,chunk]);if(buffer.length>(maximum+9)*5)throw Error();
      while(buffer.length>=4){
        const n=buffer.readUInt32BE(0);if(n<1||n>maximum+5)throw Error();if(buffer.length<n+4)break;
        const body=buffer.subarray(4,n+4);buffer=buffer.subarray(n+4);
        if(body[0]===1&&body.length===1&&!ready){ready=true;clearTimeout(timer);resolveReady();continue;}
        if(!ready||body[0]!==2||body.length<6)throw Error();
        const now=performance.now();if(now-window>=1000){window=now;frames=0;}
        const result=++frames<=100?answer(key,body.subarray(5)):failure();
        const response=Buffer.concat([body.subarray(0,5),result]);
        if(child.stdin.writableLength>maximum*4)throw Error();
        child.stdin.write(Buffer.concat([integer(response.length),response]));
      }
    }catch{rejectReady(Error('Private agent transport rejected malformed IPC'));child.kill();}
  });
  try{await started;}catch(e){clearTimeout(timer);if(!closed)child.kill();throw e;}
  return{pipe,child,isAlive:()=>!closed,close:()=>closeTransport(child,()=>closed)};
}
async function closeTransport(child,isClosed,timers={setTimeout,clearTimeout}){
  if(isClosed())return;
  let timer,onExit;
  const exited=new Promise(r=>{onExit=r;child.once('exit',onExit);});
  try{
    const deadline=new Promise(r=>{timer=timers.setTimeout(r,3000);});
    child.stdin.end();await Promise.race([exited,deadline]);
    if(!isClosed()){child.kill();await exited;}
  }finally{timers.clearTimeout(timer);child.removeListener('exit',onExit);}
}
module.exports={identity,publicLine,answer,start,string,integer,load,validPipe,verifyClient,closeTransport};

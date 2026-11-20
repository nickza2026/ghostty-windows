'use strict';
// Synthetic local-agent proof only: no SSH server/VM/account/profile access.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawn}=require('node:child_process');
const agent=require('./private-agent.cjs'),storage=require('./storage-policy.cjs');
function invoke(exe,args,options){return new Promise((resolve,reject)=>{
 const child=spawn(exe,args,{...options,stdio:['ignore','pipe','pipe']});let stdout='',stderr='';
 const timer=setTimeout(()=>{child.kill();reject(Error('Native agent proof deadline'));},10000);
 child.stdout.on('data',b=>{stdout+=b.toString();if(stdout.length>16384)child.kill();});child.stderr.on('data',b=>{if(stderr.length<16384)stderr+=b.toString();});
 child.once('error',e=>{clearTimeout(timer);reject(e);});child.once('close',status=>{clearTimeout(timer);resolve({status,stdout,stderr});});
});}
async function verify(){
 const nonce=crypto.randomBytes(16).toString('hex'),root=path.resolve(__dirname,'../../../zig-out/private-agent-proof-'+nonce);
 if(fs.existsSync(root))throw Error('Fresh proof required');fs.mkdirSync(root);
 fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce}));storage.prepare(root);
 fs.mkdirSync(path.join(root,'Data/ssh'));
 const pair=agent.identity(crypto.generateKeyPairSync('ed25519').privateKey),pub=path.join(root,'Data/ssh/client_key.pub');fs.writeFileSync(pub,agent.publicLine(pair));
 let running;const result={schema:1,nonce,passed:false,realCredentialsUsed:false,sshServerContacted:false,vmStarted:false};
 try{
  running=await agent.start(root,pair);const env={...storage.environment(root),SSH_AUTH_SOCK:running.pipe};
  await agent.verifyClient(root,running.pipe,pair);result.nativeEnumeration=true;result.nativeSigning=true;
  await Promise.all(Array.from({length:4},()=>agent.verifyClient(root,running.pipe,pair)));result.concurrentNativeClients=4;
  const collision=await invoke(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',path.join(__dirname,'private-agent-bridge.ps1'),'-PipeName',running.pipe],{cwd:root,env:storage.environment(root),windowsHide:true,shell:false});
  if(collision.status===0)throw Error('A second private pipe server was not rejected');result.pipeCollisionRejected=true;
  await agent.verifyClient(root,running.pipe,pair);
  const config=path.join(root,'Data/ssh/config');fs.writeFileSync(config,require('./policy.cjs').sshConfig({root,sshPort:42222,agentPipe:running.pipe}));
  const expanded=await invoke(path.join(process.env.SystemRoot,'System32/OpenSSH/ssh.exe'),['-G','-F',config,'portable-sandbox'],{cwd:root,env,windowsHide:true,shell:false});
  const fields=Object.fromEntries(expanded.stdout.split(/\r?\n/).filter(l=>/^(identityagent|identityfile|identitiesonly|forwardagent|addkeystoagent|stricthostkeychecking|passwordauthentication) /.test(l)).map(l=>[l.slice(0,l.indexOf(' ')),l.slice(l.indexOf(' ')+1)]));
  result.nativeConfig=fields;
  if(expanded.status!==0||fields.identityagent!==running.pipe||fields.identityfile!==pub.replaceAll('\\','/')||fields.identitiesonly!=='yes'||fields.forwardagent!=='no'||fields.passwordauthentication!=='no'||!['yes','true'].includes(fields.stricthostkeychecking)||!['no','false'].includes(fields.addkeystoagent))throw Error('Native client did not preserve the private-agent/no-fallback configuration');
  result.nativeConfigRoundTrip=true;
  const closedPipe=running.pipe;await running.close();running=undefined;result.closed=true;
  await new Promise((resolve,reject)=>{const socket=require('node:net').connect(closedPipe);const timer=setTimeout(()=>{socket.destroy();reject(Error('Closed private pipe remained accessible'));},3000);socket.once('connect',()=>{clearTimeout(timer);socket.destroy();reject(Error('Private pipe survived owner shutdown'));});socket.once('error',()=>{clearTimeout(timer);resolve();});});
  result.pipeGoneAfterOwnerClose=true;result.passed=true;
 }catch(e){result.error=e.message;throw e;}
 finally{if(running)await running.close();fs.writeFileSync(path.join(root,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));}
 return result;
}
if(require.main===module)verify().catch(()=>{process.exitCode=1;});module.exports={verify};

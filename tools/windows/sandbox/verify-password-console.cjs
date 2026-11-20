'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{frame,resizeFrame}=require('./terminal-protocol.cjs'),storage=require('./storage-policy.cjs'),{start}=require('./verify-conpty-host.cjs');
const syntheticPassword='สังเคราะห์-Only-Guest-42!';
async function verify(root,actual=false){
 const nonce=crypto.randomBytes(16).toString('hex'),target=actual?root:path.join(root,'Build/wizard-'+nonce);
 if(!actual){fs.mkdirSync(target);fs.writeFileSync(path.join(target,'sandbox-owned.json'),JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce}));fs.writeFileSync(path.join(target,'guest-profile.json'),JSON.stringify({schema:1,profile:'node'}));}
 if(actual&&(fs.existsSync(path.join(root,'Data/vm.json'))||fs.existsSync(path.join(root,'Data/guest-setup.json'))))throw Error('Actual factory wizard test requires a fresh unconfigured copy');
 storage.prepare(target);
 const probe=path.join(root,'Build/password-console-probe.cjs'),moduleFile=actual?path.join(root,'App/guest-config.cjs'):path.join(__dirname,'guest-config.cjs');
 const setup=actual?`await require(${JSON.stringify(path.join(root,'App/entry.cjs'))}).main(['setup-guest',${JSON.stringify(root)}]);`:`await c.setup(${JSON.stringify(target)});`;
 fs.writeFileSync(probe,`const c=require(${JSON.stringify(moduleFile)});(async()=>{${setup}console.log('PASSWORD_CONSOLE_PROOF '+JSON.stringify({valid:!!c.passwordHash(${JSON.stringify(target)}),rawRestored:process.stdin.isRaw===false}));})().catch(e=>{console.error(e.message);process.exitCode=1});`);
 const child=start(root,probe);child.stdin.on('error',()=>{});let data='',error='',first=false,second=false;let timer;
 const done=new Promise((resolve,reject)=>{timer=setTimeout(()=>{child.kill();reject(Error('Password console test deadline'));},20000);child.on('error',reject);child.stderr.on('data',b=>error+=b);child.stdout.on('data',b=>{
  data+=b.toString('utf8');if(data.length>65536){child.kill();reject(Error('Password output bound'));return;}
  if(!first&&data.includes('Linux sudo password: ')){first=true;child.stdin.write(frame(1,Buffer.from(syntheticPassword+'\r')));}
  if(!second&&data.includes('Confirm Linux password: ')){second=true;child.stdin.write(frame(1,Buffer.from(syntheticPassword+'\r')));}
 });child.on('close',code=>{clearTimeout(timer);const match=/PASSWORD_CONSOLE_PROOF (\{[^\r\n]+\})/.exec(data);if(code!==0||!match||!first||!second)return reject(Error('Native password prompt failed: '+error.slice(-600)));const p=JSON.parse(match[1]);const raw=fs.readFileSync(path.join(target,'Data/guest-setup.json'),'utf8');if(!p.valid||!p.rawRestored||data.includes(syntheticPassword)||raw.includes(syntheticPassword))return reject(Error('Password masking/storage/raw-mode check failed'));resolve({passed:true,realWindowsConPTY:true,utf8Password:true,plaintextEchoed:false,plaintextOnDisk:false,rawRestored:true,target});});});
 child.stdin.write(resizeFrame({columns:129,rows:41}));try{const result=await done;fs.writeFileSync(path.join(root,'Build/password-console.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));return result;}finally{clearTimeout(timer);if(child.exitCode===null)child.kill();}
}
if(require.main===module)verify(path.resolve(process.argv[2])).catch(e=>{console.error(e.message);process.exitCode=1});
module.exports={verify,syntheticPassword};

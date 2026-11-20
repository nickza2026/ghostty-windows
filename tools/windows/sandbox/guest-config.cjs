'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),readline=require('node:readline');
const {sha512crypt,validHash}=require('./guest-password-hash.cjs');
function read(file){if(fs.lstatSync(file).isSymbolicLink()||fs.statSync(file).size>8192)throw Error('Unsafe guest configuration');try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch{throw Error('Invalid guest configuration JSON');}}
function profile(root){
 const file=path.join(root,'guest-profile.json');if(!fs.existsSync(file))return{profile:'sdk',ports:[]};
 const value=read(file);if(value.schema!==1||!['sdk','clean','node'].includes(value.profile))throw Error('Invalid guest profile');
 const ports=value.ports===undefined?[]:value.ports;if(!Array.isArray(ports)||ports.length>8)throw Error('Invalid guest port list');
 const host=new Set(),guest=new Set();for(const p of ports){
  if(!p||Object.keys(p).sort().join(',')!=='guestPort,hostPort'||!Number.isInteger(p.hostPort)||p.hostPort<1024||p.hostPort>65535||!Number.isInteger(p.guestPort)||p.guestPort<1024||p.guestPort>65535||host.has(p.hostPort)||guest.has(p.guestPort))throw Error('Invalid or duplicate loopback port');
  host.add(p.hostPort);guest.add(p.guestPort);
 }
 return{profile:value.profile,ports};
}
function passwordHash(root){
 const file=path.join(root,'Data/guest-setup.json');if(!fs.existsSync(file))return undefined;
 const value=read(file),owner=read(path.join(root,'sandbox-owned.json'));
 if(value.schema!==1||value.rootId!==owner.nonce||!validHash(value.passwordHash))throw Error('Invalid guest setup; no automatic password reset');
 return value.passwordHash;
}
function secret(input,output,label){return new Promise((resolve,reject)=>{
 if(!input.isTTY||typeof input.setRawMode!=='function')return reject(Error('Guest password must be set in an interactive local terminal, never arguments/environment/chat'));
 const wasRaw=input.isRaw;let text='',finished=false;readline.emitKeypressEvents(input);
 function end(error){if(finished)return;finished=true;input.removeListener('keypress',key);input.setRawMode(Boolean(wasRaw));input.pause();output.write('\n');const bytes=Buffer.from(text,'utf8');text='';if(error){bytes.fill(0);reject(error);}else resolve(bytes);}
 function key(ch,k={}){
  if(k.ctrl&&k.name==='c')return end(Error('Guest setup cancelled'));
  if(k.name==='return'||k.name==='enter')return end();
  if(k.name==='backspace'){if(text){text=Array.from(text).slice(0,-1).join('');output.write('\b \b');}return;}
  if(k.ctrl||k.meta||!ch||ch.includes('\x1b'))return;
  if(ch.includes('\0')||Buffer.byteLength(text+ch)>1024)return end(Error('Guest password input exceeds its supported bounds'));
  text+=ch;output.write('*');
 }
 input.setRawMode(true);input.on('keypress',key);input.resume();output.write(label);
});}
async function setup(root,options={}){
 const selected=profile(root);if(selected.profile==='sdk')return;
 if(passwordHash(root))return;
 if(fs.existsSync(path.join(root,'Data/vm.json'))||fs.existsSync(path.join(root,'Data/guest.qcow2')))throw Error('Existing guest has no setup record; no automatic password reset or disk replacement');
 const input=options.stdin||process.stdin,output=options.stdout||process.stdout;
 output.write('Create a NEW Linux sudo password (not your Windows password). Prefer 12+ characters. It is not sent to chat.\n');
 let first,second;
 try{
  first=await secret(input,output,'Linux sudo password: ');second=await secret(input,output,'Confirm Linux password: ');
  if(!first.length||first.length!==second.length||!crypto.timingSafeEqual(first,second))throw Error('Guest passwords are empty or do not match');
  const hash=sha512crypt(first,crypto.randomBytes(12).toString('base64').replaceAll('+','.'),100000);
  const owner=read(path.join(root,'sandbox-owned.json'));
  fs.writeFileSync(path.join(root,'Data/guest-setup.json'),JSON.stringify({schema:1,rootId:owner.nonce,passwordHash:hash}),{flag:'wx',mode:0o600});
  output.write('Linux sudo password configured locally. SSH remains key-only; Windows privileges are unchanged.\n');
 }finally{first?.fill(0);second?.fill(0);}
}
module.exports={profile,passwordHash,setup};

'use strict';
const crypto=require('node:crypto');
// Import only the existing unencrypted, single Ed25519 package identity.
// No key rotation, passphrase prompting, format migration, or private-file output.
function importKey(input){
 let raw,der;
 try{
  if(!Buffer.isBuffer(input)||input.length>16384)throw Error();
  const text=input.toString('ascii').trim();
  const match=/^-----BEGIN OPENSSH PRIVATE KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)\r?\n-----END OPENSSH PRIVATE KEY-----$/.exec(text);
  if(!match)throw Error();const base64=match[1].replace(/[\r\n]/g,'');
  if(base64.length%4||!/^[A-Za-z0-9+/]+={0,2}$/.test(base64))throw Error();raw=Buffer.from(base64,'base64');if(raw.toString('base64')!==base64)throw Error();
  const magic=Buffer.from('openssh-key-v1\0');if(!raw.subarray(0,magic.length).equals(magic))throw Error();
  let at=magic.length;
  const uint=()=>{if(at+4>raw.length)throw Error();const n=raw.readUInt32BE(at);at+=4;return n;};
  const take=()=>{const n=uint();if(n>16384||at+n>raw.length)throw Error();const b=raw.subarray(at,at+n);at+=n;return b;};
  if(take().toString()!=='none'||take().toString()!=='none'||take().length!==0||uint()!==1)throw Error();
  const outer=take(),privateBlock=take();if(at!==raw.length||privateBlock.length%8)throw Error();
  let pos=0;const str=buffer=>{if(pos+4>buffer.length)throw Error();const n=buffer.readUInt32BE(pos);pos+=4;if(n>16384||pos+n>buffer.length)throw Error();const b=buffer.subarray(pos,pos+n);pos+=n;return b;};
  if(str(outer).toString()!=='ssh-ed25519')throw Error();const expected=str(outer);if(expected.length!==32||pos!==outer.length)throw Error();
  if(privateBlock.length<8||privateBlock.readUInt32BE(0)!==privateBlock.readUInt32BE(4))throw Error();pos=8;
  if(str(privateBlock).toString()!=='ssh-ed25519')throw Error();const pub=str(privateBlock),secret=str(privateBlock),comment=str(privateBlock);
  if(pub.length!==32||secret.length!==64||comment.length>1024||!pub.equals(expected)||!secret.subarray(32).equals(pub))throw Error();
  const padding=privateBlock.subarray(pos);if(padding.length>8)throw Error();for(let i=0;i<padding.length;i++)if(padding[i]!==i+1)throw Error();
  der=Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),secret.subarray(0,32)]);
  const privateKey=crypto.createPrivateKey({key:der,type:'pkcs8',format:'der'});
  const derived=crypto.createPublicKey(privateKey).export({type:'spki',format:'der'});
  if(derived.length!==44||!derived.subarray(12).equals(pub))throw Error();
  return privateKey;
 }catch{throw Error('Unsupported or corrupt portable Ed25519 key; no automatic replacement or migration');}
 finally{if(raw)raw.fill(0);if(der)der.fill(0);}
}
module.exports={importKey};

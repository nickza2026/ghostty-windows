'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const agent=require('./private-agent.cjs');
test('normal private-agent shutdown releases the fallback timer before manager lease is released',async()=>{
 const {EventEmitter}=require('node:events'),child=new EventEmitter();let closed=false,next=0;const active=new Set();
 child.stdin={end(){queueMicrotask(()=>{closed=true;child.emit('exit',0);});}};
 child.kill=()=>{throw Error('Normal close must not force its helper');};
 await agent.closeTransport(child,()=>closed,{setTimeout(){const n=++next;active.add(n);return n;},clearTimeout(n){active.delete(n);}});
 assert.equal(active.size,0,'A live fallback timer keeps the old package Node process alive after state cleanup');
 assert.equal(child.listenerCount('exit'),0);
});
test('private-agent fallback closes only its own child and removes its timer and listener',async()=>{
 const {EventEmitter}=require('node:events'),child=new EventEmitter();let closed=false,kills=0,cleared=0;
 child.stdin={end(){}};child.kill=()=>{kills++;queueMicrotask(()=>{closed=true;child.emit('exit',0);});};
 await agent.closeTransport(child,()=>closed,{setTimeout(fn){queueMicrotask(fn);return 1;},clearTimeout(id){assert.equal(id,1);cleared++;}});
 assert.equal(kills,1);assert.equal(cleared,1);assert.equal(child.listenerCount('exit'),0);
});
test('private agent supports one Ed25519 identity and standard signing, rejects mutation/unknown keys/flags/trailing bytes',()=>{
 const key=agent.identity(crypto.generateKeyPairSync('ed25519').privateKey);
 const listed=agent.answer(key,Buffer.from([11]));assert.equal(listed[0],12);assert.equal(listed.readUInt32BE(1),1);
 const data=Buffer.from('synthetic agent challenge');const request=Buffer.concat([Buffer.from([13]),agent.string(key.blob),agent.string(data),agent.integer(0)]);
 const signed=agent.answer(key,request);assert.equal(signed[0],14);
 let at=5;const algLength=signed.readUInt32BE(at);at+=4;assert.equal(signed.subarray(at,at+algLength).toString(),'ssh-ed25519');at+=algLength;const sigLength=signed.readUInt32BE(at);at+=4;
 assert.equal(sigLength,64);assert.equal(crypto.verify(null,data,key.publicKey,signed.subarray(at)),true);
 for(const bad of [Buffer.from([11,0]),Buffer.from([17]),Buffer.from([18]),Buffer.from([27]),request.subarray(0,request.length-1),Buffer.concat([request,Buffer.from([0])]),Buffer.concat([Buffer.from([13]),agent.string('wrong key'),agent.string(data),agent.integer(0)]),Buffer.concat([request.subarray(0,-4),agent.integer(1)])])assert.deepEqual(agent.answer(key,bad),Buffer.from([5]));
 assert.equal(agent.publicLine(key).startsWith('ssh-ed25519 '),true);
});

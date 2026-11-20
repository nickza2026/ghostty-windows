'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),{PassThrough}=require('node:stream'),{EventEmitter}=require('node:events');
const {dimensions,TerminalInput}=require('./terminal-protocol.cjs'),cli=require('./runtime-cli.cjs');
function decode(b){const frames=[];while(b.length){assert.ok(b.length>=5);const n=b.readUInt32BE(0);assert.ok(n<=32769&&b.length>=n+4);frames.push({type:b[4],data:b.subarray(5,4+n)});b=b.subarray(n+4);}return frames;}
test('interactive terminal sends initial dimensions BEFORE input, live resize, and restores raw mode',async()=>{
 const input=new PassThrough();input.isTTY=true;input.isRaw=false;const modes=[];input.setRawMode=v=>{input.isRaw=v;modes.push(v);};
 const output=new PassThrough();output.columns=111;output.rows=37;
 const child=new EventEmitter();Object.assign(child,{stdin:new PassThrough(),stdout:new PassThrough(),stderr:new PassThrough()});const chunks=[];child.stdin.on('data',b=>chunks.push(b));
 const running=cli.interactiveTerminal('synthetic-only',[],'fixture',{stdin:input,stdout:output,spawn:()=>child});
 try{
  input.write(Buffer.from('ทดสอบ\x03'));
  await new Promise(r=>setImmediate(r));output.columns=83;output.rows=29;output.emit('resize');await new Promise(r=>setImmediate(r));
  const frames=decode(Buffer.concat(chunks));assert.equal(frames[0].type,2);assert.deepEqual([...frames[0].data],[0,111,0,37]);
  assert.deepEqual(Buffer.concat(frames.filter(f=>f.type===1).map(f=>f.data)),Buffer.from('ทดสอบ\x03'));
  assert.equal(frames.at(-1).type,2);assert.deepEqual([...frames.at(-1).data],[0,83,0,29]);
 }finally{child.emit('close',7);assert.equal(await running,7);}
 assert.deepEqual(modes,[true,false]);assert.equal(output.listenerCount('resize'),0);
});
test('framed stream keeps binary input intact across bounded packets and never sends zero dimensions',async()=>{
 assert.deepEqual(dimensions({columns:0,rows:undefined}),{columns:120,rows:30});
 const encoder=new TerminalInput({columns:100,rows:25}),data=Buffer.alloc(98304,0xab),chunks=[];
 encoder.on('data',b=>chunks.push(b));encoder.end(data);await new Promise((r,j)=>{encoder.on('end',r);encoder.on('error',j);});
 const frames=decode(Buffer.concat(chunks));assert.equal(frames[0].type,2);assert.deepEqual(Buffer.concat(frames.slice(1).map(f=>f.data)),data);
});

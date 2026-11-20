'use strict';
const {Transform}=require('node:stream');
const maximum=32768;
function dimensions(output){
 const valid=n=>Number.isInteger(n)&&n>=1&&n<=65535;
 return{columns:valid(output.columns)?output.columns:120,rows:valid(output.rows)?output.rows:30};
}
function frame(type,data=Buffer.alloc(0)){
 if(!Buffer.isBuffer(data)||data.length>maximum||![1,2].includes(type))throw Error('Invalid terminal frame');
 const header=Buffer.alloc(5);header.writeUInt32BE(data.length+1);header[4]=type;return Buffer.concat([header,data]);
}
function resizeFrame(size){
 const selected=dimensions(size);if(selected.columns!==size.columns||selected.rows!==size.rows)throw Error('Invalid terminal dimensions');
 const b=Buffer.alloc(4);b.writeUInt16BE(size.columns);b.writeUInt16BE(size.rows,2);return frame(2,b);
}
class TerminalInput extends Transform{
 constructor(output){super();this.initial=dimensions(output);this.pendingSize=null;}
 _construct(done){this.push(resizeFrame(this.initial));done();}
 resize(output){const size=dimensions(output);if(this.destroyed)return;if(this.readableLength>65536)this.pendingSize=size;else this.push(resizeFrame(size));}
 _read(size){if(this.pendingSize){const latest=this.pendingSize;this.pendingSize=null;this.push(resizeFrame(latest));}super._read(size);}
 _transform(chunk,encoding,done){for(let at=0;at<chunk.length;at+=maximum)this.push(frame(1,chunk.subarray(at,at+maximum)));done();}
}
module.exports={dimensions,frame,resizeFrame,TerminalInput};

'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const {packagedCommand}=require('./verify-entry.cjs');
test('real CMD invokes quoted Unicode/space/apostrophe batch path and preserves semantic exit code',{skip:process.platform!=='win32'},()=>{
 const root=fs.mkdtempSync(path.resolve(__dirname,"../../../zig-out/cmd-ทดสอบ space '-"));
 try{
  const token=crypto.randomBytes(16).toString('hex');fs.writeFileSync(path.join(root,'Open-Terminal.cmd'),'@echo off\r\necho CMD_QUOTE_PROOF_'+token+'\r\nexit /b 7\r\n');
  const command=packagedCommand(root),r=spawnSync(command.executable,command.args,{cwd:root,shell:false,windowsHide:true,windowsVerbatimArguments:true,encoding:'utf8',timeout:5000});
  assert.equal(r.status,7,r.stderr);assert.match(r.stdout,new RegExp('CMD_QUOTE_PROOF_'+token));
 }finally{fs.rmSync(root,{recursive:true,force:true,maxRetries:10,retryDelay:50});}
});

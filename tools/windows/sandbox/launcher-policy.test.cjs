'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawnSync}=require('node:child_process');const {assemble}=require('./assemble.cjs');
const {powerShellFileArgs}=require('./prototype.cjs');
test('failed packaged CMD displays error prompt and preserves the original exit code', {skip:process.platform!=='win32'},()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'ghostty-launcher-policy-'));
 try{
  fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({name:'ghostty-sandbox-owned',schema:1,nonce:'test-only-owned'}));assemble(root);
  const node=path.join(root,'Runtime/node/node.exe');fs.mkdirSync(path.dirname(node),{recursive:true});fs.copyFileSync(process.execPath,node);
  fs.writeFileSync(path.join(root,'App/entry.cjs'),"console.error('SYNTHETIC_LAUNCH_FAILURE');process.exitCode=23;");
  const r=spawnSync(path.join(process.env.SystemRoot,'System32/cmd.exe'),['/d','/s','/c','"'+path.join(root,'Open-Terminal.cmd')+'"'],{cwd:root,windowsHide:true,windowsVerbatimArguments:true,shell:false,input:'\r\n',encoding:'utf8',timeout:10000});
  assert.ifError(r.error);assert.equal(r.status,23);assert.match(r.stderr,/SYNTHETIC_LAUNCH_FAILURE/);assert.match(r.stdout,/Sandbox exited with code 23/);assert.match(r.stdout,/Press any key/i);
  fs.writeFileSync(path.join(root,'App/entry.cjs'),"console.log('SYNTHETIC_SUCCESS');");
  const ok=spawnSync(path.join(process.env.SystemRoot,'System32/cmd.exe'),['/d','/s','/c','"'+path.join(root,'Open-Terminal.cmd')+'"'],{cwd:root,windowsHide:true,windowsVerbatimArguments:true,shell:false,encoding:'utf8',timeout:10000});
  assert.ifError(ok.error);assert.equal(ok.status,0);assert.doesNotMatch(ok.stdout,/Press any key/i);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

test('real RemoteSigned child overrides only inherited process restriction and still blocks remote unsigned files', {skip:process.platform!=='win32'},()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'ghostty-ps-policy-')),exe=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const run=(args,env=process.env)=>spawnSync(exe,args,{windowsHide:true,shell:false,encoding:'utf8',timeout:15000,env});
 const globalPolicy=()=>{const r=run(['-NoProfile','-NonInteractive','-Command',"Get-ExecutionPolicy -List | Where-Object {$_.Scope -ne 'Process'} | ConvertTo-Json -Compress"]);assert.equal(r.status,0);return r.stdout.trim();};
 const before=globalPolicy();
 try{
  const file=path.join(root,'trusted-test.ps1');fs.writeFileSync(file,"'POLICY='+(Get-ExecutionPolicy)\r\n");
  const restricted={...process.env,PSExecutionPolicyPreference:'Restricted'};
  const red=run(['-NoProfile','-NonInteractive','-File',file],restricted);assert.notEqual(red.status,0);assert.match(red.stderr,/running scripts is disabled|PSSecurityException|UnauthorizedAccess/);
  const green=run(powerShellFileArgs(file),restricted);assert.equal(green.status,0,green.stderr);assert.match(green.stdout,/POLICY=RemoteSigned/);
  fs.writeFileSync(file+':Zone.Identifier','[ZoneTransfer]\r\nZoneId=3\r\n');
  const origin=run(powerShellFileArgs(file),restricted);assert.notEqual(origin.status,0);assert.match(origin.stderr,/digitally signed|PSSecurityException|UnauthorizedAccess/);
  const data=path.join(root,'private-data');fs.mkdirSync(data);
  const acl=run(powerShellFileArgs(path.join(__dirname,'private-data.ps1'),['-Directory',data]),restricted);assert.equal(acl.status,0,acl.stderr);
  assert.equal(globalPolicy(),before,'Global/CurrentUser/GroupPolicy must remain unchanged');
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

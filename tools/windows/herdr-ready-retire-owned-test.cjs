'use strict';
// Explicit, task-scoped cleanup; never called by the launcher/build automatically.
// Node handles deep Windows npm paths. All filesystem operations stay in Node.
const fs=require('node:fs'); const path=require('node:path'); const cp=require('node:child_process'); const assert=require('node:assert/strict');
const w=path.resolve(__dirname,'../..');
const final=path.join(w,'zig-out/portable-packages/herdr-ready-20261029');
const moved=path.join(w,'zig-out/hr-ready-test-moved ไทย');
const partial=path.join(w,'zig-out/hr-ready-test-20261029');
const evidence=path.join(w,'zig-out/portable-tools-evidence/herdr-build-launch-20261028');
const completed=JSON.parse(fs.readFileSync(path.join(w,'zig-out/herdr-cmd-e2e-hfMmhg/result.json'),'utf8'));
assert(completed.passed && path.resolve(completed.root)===final);
for(const dir of [final,moved]) assert.equal(fs.readFileSync(path.join(dir,'.owned-ready-test'),'utf8'),'herdr-ready-cmd-test-v1');
const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
const quotes=[final,moved,partial].map(p=>"'"+p.replaceAll("'","''")+"\\'").join(',');
const check="$roots=@("+quotes+");$count=0;foreach($p in Get-CimInstance Win32_Process -Property ExecutablePath){foreach($r in $roots){if($p.ExecutablePath -and $p.ExecutablePath.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)){$count++}}};Write-Output $count";
const r=cp.spawnSync(ps,['-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(check,'utf16le').toString('base64')],{encoding:'utf8',windowsHide:true,timeout:20000});
assert.ifError(r.error); assert.equal(r.status,0,r.stderr); assert.equal(Number(r.stdout.trim()),0,'Owned runtime still active; preserve everything');
function validate(dir){
  assert(path.resolve(dir).toLowerCase().startsWith((path.join(w,'zig-out')+path.sep).toLowerCase()));
  for(let p=dir;p.length>=w.length;p=path.dirname(p)) assert(!fs.lstatSync(p).isSymbolicLink(),'Reparse ancestor: refuse deletion');
  let bytes=0;
  function walk(p){const s=fs.lstatSync(p);assert(!s.isSymbolicLink(),'Reparse child: refuse deletion');if(s.isDirectory())for(const n of fs.readdirSync(p))walk(path.join(p,n));else{assert(s.isFile());bytes+=s.size;}}
  walk(dir);return bytes;
}
const profile=path.join(final,'bin/portable-data/profiles/herdr');
const removals=[{path:profile,reason:'Only synthetic final acceptance profile; reinitialize fresh with production helpers'}];
if(fs.existsSync(partial)){
  assert(!fs.existsSync(path.join(partial,'package-manifest.json')));
  assert(!fs.existsSync(path.join(partial,'bin/portable-data/profiles')),'Partial build unexpectedly used; preserve it');
  const top=new Set(['bin','share','support','GHOSTTY-LICENSE.txt','Install-Portable-Git.cmd','Run-Herdr.cmd','Run.cmd']);
  for(const n of fs.readdirSync(partial))assert(top.has(n),'Unexpected unique work in partial build; preserve it');
  removals.push({path:partial,reason:'Known failed fresh build, before profile initialization'});
}
if(fs.existsSync(moved)){
  const proof=JSON.parse(fs.readFileSync(path.join(w,'zig-out/herdr-cmd-e2e-rNyRvK/result.json'),'utf8'));
  assert(proof.passed && path.resolve(proof.root)===moved);
  removals.push({path:moved,reason:'Completed owned relocation/restore test duplicate; small evidence kept'});
}
// Validate every target fully before the first deletion.
for(const item of removals)item.bytes=validate(item.path);
fs.mkdirSync(evidence,{recursive:true});
fs.writeFileSync(path.join(evidence,'cleanup-validated-targets.json'),JSON.stringify({removals,owned_processes:0,A_touched:false},null,2));
for(const item of removals)fs.rmSync(item.path,{recursive:true,force:false,maxRetries:3,retryDelay:200});
fs.unlinkSync(path.join(final,'.owned-ready-test'));
const result={passed:true,retiredBytes:removals.reduce((n,r)=>n+r.bytes,0),removals,programs_and_previous_user_delivery_preserved:true,A_touched:false};
fs.writeFileSync(path.join(evidence,'cleanup.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));

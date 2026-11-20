'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const {assemble}=require('./assemble.cjs'),{names}=require('./exfat-patch-install.cjs');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
function build(out,evidenceFile){
 out=path.resolve(out);if(fs.existsSync(out))throw Error('Fresh output required');fs.mkdirSync(out,{recursive:true});
 const original=path.resolve(__dirname,'../../../zig-out/sandbox-prototype-20261112-1450'),v1=path.resolve(__dirname,'../../../zig-out/sandbox-launcher-fix-20261113-2255/generated');
 const generated=path.join(out,'generated');fs.mkdirSync(generated);fs.writeFileSync(path.join(generated,'sandbox-owned.json'),JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce:'public-exfat-build-fixture'}));assemble(generated);
 let cliVerified=false;
 if(evidenceFile){
  const proof=JSON.parse(fs.readFileSync(evidenceFile,'utf8'));
  if(proof.passed!==true||proof.filesystem!=='exFAT'||proof.nativeRounds?.length!==2||proof.nativeRounds.some(r=>!r.nativeSsh||!r.utf8Persistence||!r.normalStop)||!proof.relocatedWithinExfat||!proof.packagedTerminal?.passed||!proof.packagedTerminal.cleanStop||proof.bootReceipts?.length!==6||proof.bootReceipts.some(r=>!r.ok||!r.qemuExited||r.qemuExitCode!==0))throw Error('Incomplete CLI evidence; no artifact promoted');
  const snapshot=JSON.parse(fs.readFileSync(path.join(generated,'App/source-snapshot.json'),'utf8'));
  if(JSON.stringify(snapshot)!==JSON.stringify(proof.sourceSnapshot))throw Error('Evidence source differs from candidate; no stale artifact promoted');
  cliVerified=true;
 }
 const bundle=path.join(out,'bundle'),patch=path.join(bundle,'exfat-fix-20261114');fs.mkdirSync(patch,{recursive:true});
 const files=[];for(const name of [...names.map(x=>'App/'+x),'App/source-snapshot.json','Open-Terminal.cmd','Open-IDE.cmd','Sandbox-Status.cmd','Stop-Sandbox.cmd','Force-Stop-Sandbox.cmd','Enable-ExFAT.cmd','Setup-Guest.cmd','START-HERE-TH.md']){
  const source=path.join(generated,name),dest=path.join(patch,'payload',name);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(source,dest);
  const before=[...new Set([original,v1].map(base=>fs.existsSync(path.join(base,name))?sha(path.join(base,name)):null))];files.push({name,before,after:sha(dest)});
 }
 fs.writeFileSync(path.join(patch,'manifest.json'),JSON.stringify({schema:1,files},null,2));fs.copyFileSync(path.join(__dirname,'exfat-patch-install.cjs'),path.join(patch,'install.cjs'));
 fs.writeFileSync(path.join(bundle,'Apply-ExFAT-Fix.cmd'),'@echo off\r\nsetlocal DisableDelayedExpansion\r\nset "NODE_OPTIONS="\r\nset "NODE_PATH="\r\n"%~dp0Runtime\\node\\node.exe" "%~dp0exfat-fix-20261114\\install.cjs"\r\nset "PATCH_EXIT=%ERRORLEVEL%"\r\npause\r\nexit /b %PATCH_EXIT%\r\n');
 fs.copyFileSync(path.join(__dirname,'start-here-th.md'),path.join(bundle,'README-EXFAT-TH.md'));
 const archive=path.join(out,'sandbox-exfat-candidate-20261114.zip');const r=spawnSync(path.join(process.env.SystemRoot,'System32/tar.exe'),['-a','-c','-f',archive,'-C',bundle,'Apply-ExFAT-Fix.cmd','README-EXFAT-TH.md','exfat-fix-20261114'],{windowsHide:true,encoding:'utf8',timeout:30000});if(r.status!==0)throw Error('Candidate archive failed');
 const check=path.join(out,'archive-check');fs.mkdirSync(check);const unpack=spawnSync(path.join(process.env.SystemRoot,'System32/tar.exe'),['-x','-f',archive,'-C',check],{windowsHide:true,encoding:'utf8',timeout:30000});if(unpack.status!==0)throw Error('Candidate archive extraction failed');
 for(const f of files)if(sha(path.join(check,'exfat-fix-20261114/payload',f.name))!==f.after)throw Error('Archived payload is not this candidate');
 const result={archive:path.basename(archive),bytes:fs.statSync(archive).size,sha256:sha(archive),publicCodeOnly:true,archivePayloadVerified:true,exfatCliVerified:cliVerified,exfatQualified:false,scope:cliVerified?'Windows exFAT VHDX CLI/SSH/persistence/relocation/redirected CMD; not GUI/cross-machine/power-loss':'unqualified candidate'};fs.writeFileSync(path.join(out,'package.json'),JSON.stringify(result,null,2));return result;
}
if(require.main===module){try{console.log(JSON.stringify(build(process.argv[2],process.argv[3])));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={build};

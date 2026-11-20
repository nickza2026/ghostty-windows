'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');const {spawnSync}=require('node:child_process');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
function build(out){
 out=path.resolve(out);if(fs.existsSync(out))throw Error('Fresh output required');fs.mkdirSync(out,{recursive:true});
 const baseline=path.resolve(__dirname,'../../../zig-out/sandbox-prototype-20261112-1450');
 // This is the historical policy-only v1 patch, not a builder for newer features.
 // Reuse its explicit public-code snapshot; never silently ship current sources
 // under the already-delivered v1 artifact name.
 const pinned=path.resolve(__dirname,'../../../zig-out/sandbox-launcher-fix-20261113-2255/generated');
 const snapshotV1=JSON.parse(fs.readFileSync(path.join(pinned,'App/source-snapshot.json'),'utf8'));
 const generated=path.join(out,'generated');fs.mkdirSync(path.join(generated,'App'),{recursive:true});fs.writeFileSync(path.join(generated,'sandbox-owned.json'),JSON.stringify({name:'ghostty-sandbox-owned',schema:1,nonce:'public-patch-build'}));
 for(const f of snapshotV1.sources){const source=path.join(pinned,'App',f.name);if(hash(source)!==f.sha256)throw Error('Historical public fixture changed');fs.copyFileSync(source,path.join(generated,'App',f.name));}
 for(const name of ['App/source-snapshot.json','Open-Terminal.cmd','Open-IDE.cmd','Sandbox-Status.cmd','Stop-Sandbox.cmd','Force-Stop-Sandbox.cmd'])fs.copyFileSync(path.join(pinned,name),path.join(generated,name));
 const bundle=path.join(out,'bundle'),patch=path.join(bundle,'launcher-fix-20261113');fs.mkdirSync(patch,{recursive:true});
 const names=['App/entry.cjs','App/prototype.cjs','App/source-snapshot.json','Open-Terminal.cmd','Open-IDE.cmd','Sandbox-Status.cmd','Stop-Sandbox.cmd','Force-Stop-Sandbox.cmd'];const files=[];
 for(const name of names){const dest=path.join(patch,'payload',name);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(path.join(generated,name),dest);files.push({name,before:hash(path.join(baseline,name)),after:hash(dest)});}
 const snapshot=JSON.parse(fs.readFileSync(path.join(generated,'App/source-snapshot.json'),'utf8'));
 const unchanged=snapshot.sources.filter(f=>!['entry.cjs','prototype.cjs'].includes(f.name)).map(f=>({name:'App/'+f.name,sha256:f.sha256}));
 for(const f of unchanged)if(hash(path.join(baseline,f.name))!==f.sha256)throw Error('Unexpected baseline change: '+f.name);
 fs.writeFileSync(path.join(patch,'manifest.json'),JSON.stringify({schema:1,files,unchanged},null,2));fs.copyFileSync(path.join(__dirname,'launcher-fix-install.cjs'),path.join(patch,'install.cjs'));
 fs.writeFileSync(path.join(bundle,'Apply-Launcher-Fix.cmd'),'@echo off\r\nsetlocal DisableDelayedExpansion\r\nset "NODE_OPTIONS="\r\nset "NODE_PATH="\r\n"%~dp0Runtime\\node\\node.exe" "%~dp0launcher-fix-20261113\\install.cjs"\r\nset "PATCH_EXIT=%ERRORLEVEL%"\r\npause\r\nexit /b %PATCH_EXIT%\r\n');
 fs.writeFileSync(path.join(bundle,'README-LAUNCHER-FIX-TH.txt'),'แตก ZIP นี้ลงในโฟลเดอร์ sandbox เดิม ให้ Apply-Launcher-Fix.cmd อยู่ข้าง Open-Terminal.cmd แล้วเปิด Apply-Launcher-Fix.cmd ก่อน เปิด Open-Terminal.cmd อีกครั้ง\r\nไม่แตะ Data/disk/บัญชี ไม่เปลี่ยน policy ทั้งเครื่อง และไม่ Unblock ไฟล์หรือข้าม Group Policy\r\nต้องใช้ NTFS; ถ้า PowerShell แจ้งเรื่องลายเซ็น/นโยบายองค์กรยังต้องตรวจแยก ไม่ใช้ Bypass อัตโนมัติ\r\n');
 const archive=path.join(out,'sandbox-launcher-fix-20261113.zip'),tar=path.join(process.env.SystemRoot,'System32/tar.exe');
 const r=spawnSync(tar,['-a','-c','-f',archive,'-C',bundle,'Apply-Launcher-Fix.cmd','README-LAUNCHER-FIX-TH.txt','launcher-fix-20261113'],{windowsHide:true,encoding:'utf8',timeout:30000});if(r.status!==0)throw Error('Patch archive failed: '+r.stderr);
 const test=spawnSync(tar,['-x','-O','-f',archive],{windowsHide:true,timeout:30000,stdio:['ignore','ignore','pipe']});if(test.status!==0)throw Error('Patch archive validation failed');
 const result={passed:true,archive:path.basename(archive),bytes:fs.statSync(archive).size,sha256:hash(archive),publicCodeOnly:true};fs.writeFileSync(path.join(out,'package.json'),JSON.stringify(result,null,2));return result;
}
if(require.main===module){try{console.log(JSON.stringify(build(process.argv[2])));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={build};

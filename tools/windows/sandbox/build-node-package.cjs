'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{spawnSync}=require('child_process'),{assemble}=require('./assemble.cjs');
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function publicTree(from,to,select=()=>true){
 const s=fs.lstatSync(from);if(s.isSymbolicLink())throw Error('No reparse public runtime');
 if(s.isDirectory()){fs.mkdirSync(to,{recursive:true});for(const name of fs.readdirSync(from))publicTree(path.join(from,name),path.join(to,name),select);}
 else if(s.isFile()&&select(from))fs.linkSync(from,to);else if(!s.isFile())throw Error('No special runtime files');
}
function inventory(root){const result=[];function walk(dir){for(const name of fs.readdirSync(dir)){const file=path.join(dir,name),s=fs.lstatSync(file);if(s.isSymbolicLink())throw Error('No reparse factory artifact');if(s.isDirectory())walk(file);else if(s.isFile())result.push({name:path.relative(root,file).replaceAll('\\','/'),bytes:s.size,sha256:sha(file)});else throw Error('Unsafe factory payload');}}walk(root);return result.sort((a,b)=>a.name.localeCompare(b.name));}
function prepare(out){
 out=path.resolve(out);const allowed=path.resolve(__dirname,'../../../zig-out')+path.sep;if(!out.startsWith(allowed)||fs.existsSync(out))throw Error('Fresh output under owned zig-out required');fs.mkdirSync(out);
 const source=path.resolve(__dirname,'../../../zig-out/sandbox-prototype-20261112-1450'),root=path.join(out,'Sandbox-Node-Portable'),nonce=crypto.randomBytes(16).toString('hex');fs.mkdirSync(root);
 fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({schema:1,name:'ghostty-sandbox-owned',nonce}));
 fs.writeFileSync(path.join(root,'guest-profile.json'),JSON.stringify({schema:1,profile:'node',ports:[{hostPort:18787,guestPort:8787}]},null,2));
 const allowedQemu=new Set(['qemu-system-x86_64.exe','qemu-img.exe']);
 publicTree(path.join(source,'Runtime'),path.join(root,'Runtime'),file=>!file.includes(path.sep+'qemu'+path.sep)||!file.toLowerCase().endsWith('.exe')||allowedQemu.has(path.basename(file).toLowerCase()));
 const nodeLicense=path.resolve(__dirname,'../../../zig-out/public-licenses/node-v22.19.0-LICENSE');
 if(!fs.existsSync(nodeLicense))throw Error('Fetch the official Node v22.19.0 LICENSE into the public license cache first');
 fs.copyFileSync(nodeLicense,path.join(root,'Runtime/node/LICENSE'));
 const manifests=fs.readdirSync(path.join(source,'Build')).filter(n=>/^acquisition-.+-complete\.json$/.test(n));if(manifests.length!==1)throw Error('No unique verified public acquisition');const acq=JSON.parse(fs.readFileSync(path.join(source,'Build',manifests[0]),'utf8'));
 if(acq.status!=='complete')throw Error('Public acquisition not complete');fs.mkdirSync(path.join(root,'Build'));
 fs.writeFileSync(path.join(root,'Build/acquisition-public-runtime-complete.json'),JSON.stringify({schema:1,status:'complete',binaries:acq.binaries.map(b=>({file:path.basename(b.file),sha256:b.sha256}))},null,2));
 assemble(root);fs.copyFileSync(path.join(__dirname,'start-node-th.md'),path.join(root,'START-HERE-TH.md'));
 const files=inventory(root);if(files.some(f=>/^Data\//i.test(f.name)||/guest-setup\.json$/.test(f.name)))throw Error('Factory contains private state');
 const result={schema:1,root,nonce,bytes:files.reduce((n,f)=>n+f.bytes,0),files,sourceSnapshot:JSON.parse(fs.readFileSync(path.join(root,'App/source-snapshot.json'),'utf8')),dataIncluded:false,profile:'node',qualification:'candidate; native tests required'};
 fs.writeFileSync(path.join(out,'factory.json'),JSON.stringify(result,null,2));return result;
}
function archive(out){
 out=path.resolve(out);const m=JSON.parse(fs.readFileSync(path.join(out,'factory.json'),'utf8'));if(fs.existsSync(path.join(m.root,'Data')))throw Error('Never archive a booted or configured factory');
 for(const f of m.files)if(sha(path.join(m.root,f.name))!==f.sha256)throw Error('Factory changed since snapshot');const file=path.join(out,'sandbox-node-portable-20261115.zip');if(fs.existsSync(file))throw Error('No archive reuse');
 const r=spawnSync(path.join(process.env.SystemRoot,'System32/tar.exe'),['-a','-c','-f',file,'-C',out,'Sandbox-Node-Portable'],{windowsHide:true,encoding:'utf8',timeout:900000});if(r.status!==0){if(fs.existsSync(file))fs.unlinkSync(file);throw Error('Fresh factory archive failed');}
 const check=path.join(out,'archive-check');fs.mkdirSync(check);const x=spawnSync(path.join(process.env.SystemRoot,'System32/tar.exe'),['-x','-f',file,'-C',check],{windowsHide:true,encoding:'utf8',timeout:600000});if(x.status!==0)throw Error('Factory extraction check failed');
 const extracted=path.join(check,'Sandbox-Node-Portable'),seen=inventory(extracted);if(JSON.stringify(seen)!==JSON.stringify(m.files))throw Error('Archive differs from this factory');
 const result={schema:1,archive:path.basename(file),bytes:fs.statSync(file).size,sha256:sha(file),factoryBytes:m.bytes,sourceCount:m.sourceSnapshot.sources.length,dataIncluded:false,archivePayloadVerified:true,qualification:'candidate until native verification against this snapshot'};
 fs.writeFileSync(path.join(out,'package.json'),JSON.stringify(result,null,2));return result;
}
function refresh(out){
 out=path.resolve(out);const m=JSON.parse(fs.readFileSync(path.join(out,'factory.json'),'utf8'));
 if(m.root!==path.join(out,'Sandbox-Node-Portable')||JSON.parse(fs.readFileSync(path.join(m.root,'sandbox-owned.json'),'utf8')).nonce!==m.nonce||fs.existsSync(path.join(m.root,'Data'))||fs.existsSync(path.join(out,'package.json')))throw Error('Only an unchanged, unbooted, unarchived owned candidate may refresh');
 if(JSON.stringify(inventory(m.root))!==JSON.stringify(m.files))throw Error('Candidate changed outside builder; preserve it');
 assemble(m.root);fs.copyFileSync(path.join(__dirname,'start-node-th.md'),path.join(m.root,'START-HERE-TH.md'));m.files=inventory(m.root);m.bytes=m.files.reduce((n,f)=>n+f.bytes,0);m.sourceSnapshot=JSON.parse(fs.readFileSync(path.join(m.root,'App/source-snapshot.json'),'utf8'));fs.writeFileSync(path.join(out,'factory.json'),JSON.stringify(m,null,2));return m;
}
if(require.main===module){try{const result=process.argv[2]==='archive'?archive(process.argv[3]):process.argv[2]==='refresh'?refresh(process.argv[3]):prepare(process.argv[3]);console.log(JSON.stringify({...result,files:result.files?result.files.length:undefined,sourceSnapshot:undefined}));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={prepare,archive,inventory,refresh};

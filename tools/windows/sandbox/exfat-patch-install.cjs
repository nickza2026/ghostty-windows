'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const names=['entry.cjs','runtime-cli.cjs','prototype.cjs','policy.cjs','fat-seed.cjs','guest-blueprint.cjs','acquire.cjs','range-download.cjs','ide-workspace.cjs','terminal-filter.cjs','private-data.ps1','preflight.ps1','storage-policy.cjs','private-agent.cjs','private-openssh-key.cjs','private-agent-bridge.ps1','private-agent-bridge.cs','guest-config.cjs','guest-password-hash.cjs','terminal-protocol.cjs','guest-terminal.py'];
const allowed=new Set([...names.map(x=>'App/'+x),'App/source-snapshot.json','Open-Terminal.cmd','Open-IDE.cmd','Sandbox-Status.cmd','Stop-Sandbox.cmd','Force-Stop-Sandbox.cmd','Enable-ExFAT.cmd','Setup-Guest.cmd','START-HERE-TH.md']);
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function noLinks(file){for(let p=path.resolve(file);;p=path.dirname(p)){if(fs.existsSync(p)&&fs.lstatSync(p).isSymbolicLink())throw Error('Reparse patch path refused');if(path.dirname(p)===p)break;}}
function install(patch=__dirname){
 const root=path.resolve(patch,'..');noLinks(patch);noLinks(root);
 if(path.resolve(process.execPath).toLowerCase()!==path.join(root,'Runtime/node/node.exe').toLowerCase())throw Error('Run Apply-ExFAT-Fix.cmd with the private portable Node');
 const owner=JSON.parse(fs.readFileSync(path.join(root,'sandbox-owned.json'),'utf8'));if(owner.name!=='ghostty-sandbox-owned'||owner.schema!==1)throw Error('Existing sandbox root required');
 if(fs.existsSync(path.join(root,'Data/manager.json')))throw Error('Stop the sandbox first; no automatic manager cleanup');
 const m=JSON.parse(fs.readFileSync(path.join(patch,'manifest.json'),'utf8'));
 if(m.schema!==1||m.files.length!==allowed.size||new Set(m.files.map(f=>f.name)).size!==allowed.size)throw Error('Invalid patch inventory');
 const todo=[];
 for(const f of m.files){
  if(!allowed.has(f.name)||!/^[a-f0-9]{64}$/.test(f.after)||!Array.isArray(f.before)||!f.before.length||f.before.some(h=>h!==null&&!/^[a-f0-9]{64}$/.test(h)))throw Error('Invalid fixed patch target');
  const target=path.join(root,f.name),payload=path.join(patch,'payload',f.name);noLinks(target);noLinks(payload);
  if(sha(payload)!==f.after)throw Error('Payload hash mismatch: '+f.name);
  const current=fs.existsSync(target)?sha(target):null;
  if(current===f.after)continue;
  if(!f.before.includes(current))throw Error('Unknown/modified file preserved: '+f.name);
  todo.push({...f,current});
 }
 for(const f of todo)if(f.current!==null){const backup=path.join(patch,'backup',f.name);noLinks(backup);fs.mkdirSync(path.dirname(backup),{recursive:true});if(fs.existsSync(backup)){if(sha(backup)!==f.current)throw Error('Unique backup preserved: '+f.name);}else fs.copyFileSync(path.join(root,f.name),backup,fs.constants.COPYFILE_EXCL);}
 const changed=[];
 try{
  for(const f of todo){const target=path.join(root,f.name),tmp=target+'.exfat-fix-'+crypto.randomBytes(8).toString('hex');try{fs.copyFileSync(path.join(patch,'payload',f.name),tmp,fs.constants.COPYFILE_EXCL);fs.renameSync(tmp,target);changed.push(f);if(sha(target)!==f.after)throw Error('Written file hash mismatch');}finally{if(fs.existsSync(tmp))fs.unlinkSync(tmp);}}
 }catch(e){for(const f of changed.reverse()){const target=path.join(root,f.name);if(sha(target)===f.after){if(f.current===null)fs.unlinkSync(target);else fs.copyFileSync(path.join(patch,'backup',f.name),target);}}throw e;}
 const result={passed:true,changed:todo.length,vmDataTouched:false,modeAutomaticallyEnabled:false,globalSettingsChanged:false};fs.writeFileSync(path.join(patch,'applied.json'),JSON.stringify(result,null,2));
 console.log('Program patch applied. VM disks, keys, accounts and storage opt-in were preserved.');
 console.log('Run Enable-ExFAT.cmd to explicitly accept reduced storage protection, then Open-Terminal.cmd.');return result;
}
if(require.main===module){try{install();}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={install,names};

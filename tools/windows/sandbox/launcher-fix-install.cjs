'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const digest=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const allowed=new Set(['App/entry.cjs','App/prototype.cjs','App/source-snapshot.json','Open-Terminal.cmd','Open-IDE.cmd','Sandbox-Status.cmd','Stop-Sandbox.cmd','Force-Stop-Sandbox.cmd']);
function noLinks(file){for(let p=path.resolve(file);;p=path.dirname(p)){if(fs.existsSync(p)&&fs.lstatSync(p).isSymbolicLink())throw Error('Reparse path refused');if(path.dirname(p)===p)break;}}
function install(patch=__dirname){
 const root=path.resolve(patch,'..');noLinks(patch);noLinks(root);
 if(path.resolve(process.execPath).toLowerCase()!==path.join(root,'Runtime/node/node.exe').toLowerCase())throw Error('Use Apply-Launcher-Fix.cmd and the package private Node');
 const owner=JSON.parse(fs.readFileSync(path.join(root,'sandbox-owned.json'),'utf8'));
 if(owner.name!=='ghostty-sandbox-owned'||owner.schema!==1)throw Error('Extract patch into the existing sandbox folder first');
 if(fs.existsSync(path.join(root,'Data/manager.json')))throw Error('Stop this sandbox with Stop-Sandbox.cmd before applying; no process was killed');
 const m=JSON.parse(fs.readFileSync(path.join(patch,'manifest.json'),'utf8'));
 if(m.schema!==1||m.files.length!==allowed.size||new Set(m.files.map(f=>f.name)).size!==allowed.size)throw Error('Invalid patch manifest');
 for(const f of m.files){
  if(!allowed.has(f.name)||!(/^[a-f0-9]{64}$/.test(f.before)&&/^[a-f0-9]{64}$/.test(f.after)))throw Error('Unexpected patch target');
  const target=path.join(root,f.name),source=path.join(patch,'payload',f.name);noLinks(target);noLinks(source);
  if(digest(source)!==f.after)throw Error('Patch payload hash mismatch: '+f.name);
  const current=digest(target);if(current!==f.before&&current!==f.after)throw Error('Unrecognized/modified file preserved: '+f.name);
 }
 for(const f of m.unchanged){if(!/^App\/[a-z0-9-]+\.(?:cjs|ps1)$/.test(f.name))throw Error('Invalid unchanged target');const file=path.join(root,f.name);noLinks(file);if(digest(file)!==f.sha256)throw Error('Unrecognized existing App file preserved: '+f.name);}
 const todo=m.files.filter(f=>digest(path.join(root,f.name))!==f.after);
 if(!todo.length){console.log('Launcher fix already applied. No VM data changed.');return {passed:true,changed:0};}
 const changed=[];
 try{
  // Validate everything before writing, and back up public program files only.
  for(const f of todo){const backup=path.join(patch,'backup',f.name);noLinks(backup);fs.mkdirSync(path.dirname(backup),{recursive:true});if(fs.existsSync(backup)){if(digest(backup)!==f.before)throw Error('Existing backup preserved: '+f.name);}else fs.copyFileSync(path.join(root,f.name),backup,fs.constants.COPYFILE_EXCL);}
  for(const f of todo){const target=path.join(root,f.name),tmp=target+'.launcher-fix-'+crypto.randomBytes(8).toString('hex');try{fs.copyFileSync(path.join(patch,'payload',f.name),tmp,fs.constants.COPYFILE_EXCL);fs.renameSync(tmp,target);changed.push(f);if(digest(target)!==f.after)throw Error('Written file verification failed');}finally{if(fs.existsSync(tmp))fs.unlinkSync(tmp);}}
 }catch(e){for(const f of changed.reverse()){const target=path.join(root,f.name);if(digest(target)===f.after)fs.copyFileSync(path.join(patch,'backup',f.name),target);}throw e;}
 const result={passed:true,changed:changed.length,vmDataTouched:false,globalPolicyChanged:false,processPolicy:'RemoteSigned',originAndGroupPolicyRespected:true};
 fs.writeFileSync(path.join(patch,'applied.json'),JSON.stringify(result,null,2));
 console.log('Launcher fix applied. VM disks/accounts unchanged. No global execution policy was changed.');
 console.log('Open Open-Terminal.cmd. PowerShell origin checks and Group Policy still apply.');return result;
}
if(require.main===module){try{install();}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={install};

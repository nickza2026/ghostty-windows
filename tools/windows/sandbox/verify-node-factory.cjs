'use strict';
const fs=require('fs'),path=require('path'),{verify:passwordWizard,syntheticPassword}=require('./verify-password-console.cjs'),{verify:consoleGuest}=require('./verify-conpty-guest.cjs'),{ssh,stop}=require('./verify-node-native.cjs');
const json=f=>JSON.parse(fs.readFileSync(f,'utf8'));
async function verify(out){
 out=path.resolve(out);if(!/^D:\\works\\ghostty-windows\\zig-out\\sandbox-node-candidate-20261115-[a-f0-9]{8}$/i.test(out))throw Error('Explicit generated candidate required');
 const m=json(path.join(out,'factory.json')),pkg=json(path.join(out,'package.json')),root=path.join(out,'archive-check/Sandbox-Node-Portable');
 if(!pkg.archivePayloadVerified||pkg.dataIncluded!==false||json(path.join(root,'sandbox-owned.json')).nonce!==m.nonce||JSON.stringify(json(path.join(root,'App/source-snapshot.json')))!==JSON.stringify(m.sourceSnapshot)||fs.existsSync(path.join(root,'Data')))throw Error('Fresh verified factory extraction required');
 const cli=require(path.join(root,'App/runtime-cli.cjs'));const report={schema:1,root,nonce:m.nonce,sourceSnapshot:m.sourceSnapshot,stage:'local-password',passed:false};const save=()=>fs.writeFileSync(path.join(out,'native-proof.json'),JSON.stringify(report,null,2));save();
 let active;
 try{
  report.password=await passwordWizard(root,true);report.stage='cold-start';save();
  const begun=await cli.ensure(root);active=begun.state.managerNonce;await cli.ready(root);report.stage='guest-baseline';save();
  const hash=json(path.join(root,'Data/guest-setup.json')).passwordHash;
  const script=`import ctypes,json,os,shutil,subprocess,pathlib\np=${JSON.stringify(syntheticPassword)}.encode()\nc=ctypes.CDLL('libcrypt.so.1');c.crypt.argtypes=[ctypes.c_char_p,ctypes.c_char_p];c.crypt.restype=ctypes.c_char_p\nexpected=${JSON.stringify(hash)}\nmatch=c.crypt(p,expected.encode()).decode()==expected\nno=subprocess.run(['sudo','-k','-n','true'],stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode\nyes=subprocess.run(['sudo','-k','-S','-p','','true'],input=p+b'\\n',stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode\nsubprocess.run(['sudo','-k'],check=True)\nprefix=subprocess.check_output(['npm','config','get','prefix']).decode().strip()\nbase=dict(uid=os.getuid(),home=os.environ.get('HOME'),node=subprocess.check_output(['node','--version']).decode().strip(),missing={n:shutil.which(n) is None for n in ['git','herdr','letta','g++','make']},cryptMatches=match,sudoNeedsPassword=no!=0,sudoWithPassword=yes==0,npmPrefix=prefix)\nd=pathlib.Path.home()/'.cache/sandbox-user-install-proof';d.mkdir(parents=True,exist_ok=False)\n(d/'package.json').write_text(json.dumps(dict(name='sandbox-user-install-proof',version='1.0.0',bin={'sandbox-user-install-proof':'main.js'})))\n(d/'main.js').write_text('#!/usr/bin/env node\\nconsole.log("USER_INSTALL_OK");\\n')\nsubprocess.run(['npm','install','--global','--offline','--ignore-scripts','--no-audit','--no-fund',str(d)],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)\nbase['userGlobalInstall']=subprocess.check_output(['sandbox-user-install-proof']).decode().strip()=='USER_INSTALL_OK'\nprint('FACTORY_NODE_PROOF '+json.dumps(base))\n`;
  const output=ssh(root,['-T','portable-sandbox',`/bin/bash -l -c '/usr/bin/python3 -'`],Buffer.from(script));report.baseline=JSON.parse(output.split('\n').find(l=>l.startsWith('FACTORY_NODE_PROOF ')).slice(19));
  const b=report.baseline;if(b.uid!==1000||b.home!=='/home/sandbox'||b.node!=='v24.22.1'||Object.values(b.missing).some(v=>!v)||!b.cryptMatches||!b.sudoNeedsPassword||!b.sudoWithPassword||b.npmPrefix!=='/home/sandbox/.local'||!b.userGlobalInstall)throw Error('Fresh thin factory contract failed');
  report.stage='real-console-guest';save();report.console=await consoleGuest(root,18787);
  report.stage='first-stop';save();await stop(root,active);active=undefined;report.firstNormalStop=true;
  const second=await cli.ensure(root);active=second.state.managerNonce;if(active===begun.state.managerNonce)throw Error('Stale manager reused');await cli.ready(root);
  const persisted=ssh(root,['-T','portable-sandbox',`/bin/bash -l -c 'sandbox-user-install-proof'`]).trim();if(persisted!=='USER_INSTALL_OK')throw Error('User-installed package not persistent');report.userInstallPersists=true;
  report.passed=true;report.stage='native-factory-passed';
 }catch(e){report.error=e.message;throw e;}finally{
  if(active){try{await stop(root,active);report.finalNormalStop=true;}catch(e){report.cleanupError=e.message;report.passed=false;}}
  save();console.log(JSON.stringify({passed:report.passed,stage:report.stage,baseline:report.baseline,console:report.console,userInstallPersists:report.userInstallPersists,firstNormalStop:report.firstNormalStop,finalNormalStop:report.finalNormalStop,error:report.error,cleanupError:report.cleanupError}));
 }
 return report;
}
if(require.main===module)verify(process.argv[2]).catch(e=>{console.error(e.message);process.exitCode=1});
module.exports={verify};

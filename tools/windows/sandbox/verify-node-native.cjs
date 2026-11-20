'use strict';
// Owned NTFS fixture only: public Runtime hardlinks, fresh base overlay, no
// existing Data/accounts. Public synthetic password is NEVER a factory default.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),net=require('net'),{spawnSync}=require('child_process');
const {assemble}=require('./assemble.cjs'),storage=require('./storage-policy.cjs'),cli=require('./runtime-cli.cjs');
const {sha512crypt}=require('./guest-password-hash.cjs');
const fixturePassword='FIXTURE_ONLY_NOT_A_USER_PASSWORD_20261115';
const json=f=>JSON.parse(fs.readFileSync(f,'utf8').replace(/^\uFEFF/,''));
function linkPublic(from,to){const s=fs.lstatSync(from);if(s.isSymbolicLink())throw Error('No reparse public runtime');if(s.isDirectory()){fs.mkdirSync(to,{recursive:true});for(const n of fs.readdirSync(from))linkPublic(path.join(from,n),path.join(to,n));}else if(s.isFile())fs.linkSync(from,to);else throw Error('Not a public program file');}
async function freePort(){return new Promise((resolve,reject)=>{const s=net.createServer();s.once('error',reject);s.listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>resolve(p));});});}
function ssh(root,command,input){const r=spawnSync(path.join(process.env.SystemRoot,'System32/OpenSSH/ssh.exe'),['-F',path.join(root,'Data/ssh/config'),...command],{cwd:root,env:cli.environment(root),windowsHide:true,shell:false,input,encoding:'utf8',timeout:30000,maxBuffer:1048576});if(r.status!==0)throw Error('Synthetic SSH check failed: '+(r.stderr||r.error?.message||r.status).slice(0,500));return r.stdout;}
async function stop(root,nonce){const current=await cli.existing(root);if(!current||current.state.managerNonce!==nonce)throw Error('No current owned manager to stop');await cli.request?.(current.state,'POST','/stop');if(!cli.request){await cli.main(['stop',root],{print(){}});}const until=Date.now()+45000;while(fs.existsSync(path.join(root,'Data/manager.json'))&&Date.now()<until)await new Promise(r=>setTimeout(r,100));const last=json(path.join(root,'Data/manager-last.json'));if(last.managerNonce!==nonce||last.phase!=='stopped')throw Error('No fresh normal-stop receipt');}
async function baseline(){
 const nonce=crypto.randomBytes(16).toString('hex'),root=path.resolve(__dirname,'../../../zig-out/node-pty-test-'+nonce),source=path.resolve(__dirname,'../../../zig-out/sandbox-prototype-20261112-1450');
 fs.mkdirSync(root);fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({name:'ghostty-sandbox-owned',schema:1,nonce}));
 linkPublic(path.join(source,'Runtime'),path.join(root,'Runtime'));fs.mkdirSync(path.join(root,'Build'));const files=fs.readdirSync(path.join(source,'Build')).filter(n=>/^acquisition-.+-complete\.json$/.test(n));if(files.length!==1)throw Error('No unique public acquisition');fs.copyFileSync(path.join(source,'Build',files[0]),path.join(root,'Build',files[0]));
 const hostPort=await freePort();fs.writeFileSync(path.join(root,'guest-profile.json'),JSON.stringify({schema:1,profile:'node',ports:[{hostPort,guestPort:8787}]}));
 assemble(root);storage.prepare(root);const passwordHash=sha512crypt(Buffer.from(fixturePassword),'NativeFixture15',5000);fs.writeFileSync(path.join(root,'Data/guest-setup.json'),JSON.stringify({schema:1,rootId:nonce,passwordHash}),{mode:0o600});
 const report={schema:1,nonce,root,hostPort,stage:'starting',passed:false};const save=()=>fs.writeFileSync(path.join(root,'Build/node-native.json'),JSON.stringify(report,null,2));save();console.log('NODE_NATIVE_FIXTURE='+root);
 let active;
 try{
  const begun=await cli.ensure(root);active=begun.state.managerNonce;await cli.ready(root);report.stage='native-baseline';save();
  const size=ssh(root,['-tt','portable-sandbox','stty size; node -p "process.stdout.columns"']);report.originalForcedSshTty=size.trim();
  const script=`import ctypes,json,os,shutil,subprocess\np=${JSON.stringify(fixturePassword)}.encode()\nc=ctypes.CDLL('libcrypt.so.1');c.crypt.argtypes=[ctypes.c_char_p,ctypes.c_char_p];c.crypt.restype=ctypes.c_char_p\nh=c.crypt(p,b'$6$rounds=5000$NativeFixture15$').decode()\nno=subprocess.run(['sudo','-k','-n','true'],stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode\nyes=subprocess.run(['sudo','-k','-S','-p','','true'],input=p+b'\\n',stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode\nprint('NODE_NATIVE_PROOF '+json.dumps(dict(uid=os.getuid(),home=os.environ.get('HOME'),node=subprocess.check_output(['node','--version']).decode().strip(),missing={n:shutil.which(n) is None for n in ['git','herdr','letta','g++','make']},crypt=h,sudoNeedsPassword=no!=0,sudoWithPassword=yes==0)))\n`;
  const out=ssh(root,['-T','portable-sandbox','/usr/bin/python3 -'],Buffer.from(script));const proof=JSON.parse(out.split('\n').find(l=>l.startsWith('NODE_NATIVE_PROOF ')).slice(18));report.native={...proof,crypt:undefined,cryptMatches:proof.crypt===passwordHash};
  if(!report.native.cryptMatches||proof.uid!==1000||proof.node!=='v24.22.1'||Object.values(proof.missing).some(v=>!v)||!proof.sudoNeedsPassword||!proof.sudoWithPassword)throw Error('Native node-only/sudo/libcrypt baseline failed');
  report.passed=true;report.stage='baseline-complete';
 }catch(e){report.error=e.message;throw e;}finally{if(active){await stop(root,active);report.normalStop=true;}save();console.log(JSON.stringify(report));}
}
if(require.main===module)baseline().catch(e=>{console.error(e.message);process.exitCode=1});
module.exports={ssh,stop,fixturePassword};

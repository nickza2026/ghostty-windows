'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {profile,passwordHash}=require('./guest-config.cjs'),{firewall,qemuArgs}=require('./policy.cjs');
const {PassThrough}=require('node:stream'),{setup}=require('./guest-config.cjs');
test('guest profile is explicit, legacy SDK stays unchanged; loopback maps strict bounded ports',()=>{
 const root=fs.mkdtempSync(path.resolve(__dirname,'../../../zig-out/guest-config-test-'));
 try{
  assert.deepEqual(profile(root),{profile:'sdk',ports:[]});
  const file=path.join(root,'guest-profile.json'),p={schema:1,profile:'node',ports:[{hostPort:18787,guestPort:8787}]};fs.writeFileSync(file,JSON.stringify(p));assert.equal(profile(root).profile,'node');
  for(const invalid of [{hostPort:0,guestPort:8787},{hostPort:18787,guestPort:22},{hostPort:18787,guestPort:8787,host:'0.0.0.0'}]){fs.writeFileSync(file,JSON.stringify({...p,ports:[invalid]}));assert.throws(()=>profile(root));}
  fs.writeFileSync(file,JSON.stringify({...p,profile:'anything'}));assert.throws(()=>profile(root));
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('runtime dev forward binds ONLY host loopback, absent from bootstrap; gateway reply precedes private egress rejection',()=>{
 const portForwards=[{hostPort:18787,guestPort:8787}],root=path.resolve('owned-fixture');
 const runtime=qemuArgs({root,sshPort:49152,portForwards}).join(' '),bootstrap=qemuArgs({root,sshPort:49152,portForwards,bootstrap:true}).join(' ');
 assert.match(runtime,/hostfwd=tcp:127\.0\.0\.1:18787-10\.0\.2\.15:8787/);assert.doesNotMatch(runtime,/0\.0\.0\.0:18787/);assert.doesNotMatch(bootstrap,/18787|8787/);assert.match(bootstrap,/restrict=on/);
 const rules=firewall([],portForwards).v4;assert.match(rules,/-s 10\.0\.2\.2 -d 10\.0\.2\.15 --dport 8787/);assert.ok(rules.indexOf('--sport 8787')<rules.indexOf('-A OUTPUT -d 10.0.0.0/8 -j REJECT'));assert.match(rules,/-A OUTPUT -d 127\.0\.0\.0\/8 -j REJECT/);
 assert.throws(()=>qemuArgs({root,sshPort:18787,portForwards}));assert.throws(()=>qemuArgs({root,sshPort:49152,portForwards:[...portForwards,...portForwards]}));
});
test('local password setup disables echo before each prompt, stores only a bound salted hash, and restores raw mode',async()=>{
 const root=fs.mkdtempSync(path.resolve(__dirname,'../../../zig-out/guest-password-test-'));
 try{
  fs.mkdirSync(path.join(root,'Data'));fs.writeFileSync(path.join(root,'sandbox-owned.json'),JSON.stringify({nonce:'synthetic-only-owner'}));fs.writeFileSync(path.join(root,'guest-profile.json'),JSON.stringify({schema:1,profile:'node'}));
  const input=new PassThrough();input.isTTY=true;input.isRaw=false;input.setRawMode=v=>{input.isRaw=v;};let seen='';const synthetic='Synthetic-only-password-42';
  const output={write(text){seen+=text;if(text.includes('Linux sudo password:')||text.includes('Confirm Linux password:')){assert.equal(input.isRaw,true);queueMicrotask(()=>{for(const ch of synthetic)input.emit('keypress',ch,{});input.emit('keypress','\r',{name:'return'});});}}};
  await setup(root,{stdin:input,stdout:output});assert.equal(input.isRaw,false);const file=fs.readFileSync(path.join(root,'Data/guest-setup.json'),'utf8');assert.ok(!file.includes(synthetic));assert.ok(!seen.includes(synthetic));assert.match(passwordHash(root),/^\$6\$rounds=100000\$/);
  fs.writeFileSync(path.join(root,'Data/vm.json'),'{}');const before=file;await setup(root,{stdin:input,stdout:output});assert.equal(fs.readFileSync(path.join(root,'Data/guest-setup.json'),'utf8'),before);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('unconfigured existing guest is preserved; malformed JSON errors disclose no input',async()=>{
 const root=fs.mkdtempSync(path.resolve(__dirname,'../../../zig-out/guest-no-reset-test-'));
 try{
  fs.mkdirSync(path.join(root,'Data'));fs.writeFileSync(path.join(root,'guest-profile.json'),JSON.stringify({schema:1,profile:'node'}));fs.writeFileSync(path.join(root,'Data/vm.json'),'unique-existing-guest');
  await assert.rejects(setup(root),/no automatic password reset/);assert.equal(fs.readFileSync(path.join(root,'Data/vm.json'),'utf8'),'unique-existing-guest');assert.ok(!fs.existsSync(path.join(root,'Data/guest-setup.json')));
  fs.writeFileSync(path.join(root,'guest-profile.json'),'DO_NOT_DISCLOSE_THIS_INPUT');assert.throws(()=>profile(root),e=>e.message==='Invalid guest configuration JSON');
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

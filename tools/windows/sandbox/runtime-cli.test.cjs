'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const cli = require('./runtime-cli.cjs');
const root = path.resolve('fake-package');
const state = { root, rootId: 'owned-nonce-12345678', token: 'a'.repeat(64), managerNonce: 'b'.repeat(64), port: 23456, phase: 'ready' };
const owner = { name: 'ghostty-sandbox-owned', schema: 1, nonce: state.rootId };
function fakeAgent(calls=[]){return{
  start:async()=>{calls.push('agent-start');return{pipe:'\\\\.\\pipe\\ghostty-sbx-'+'a'.repeat(64),child:new EventEmitter(),isAlive:()=>true,close:async()=>{calls.push('agent-close');}};},
  verifyClient:async()=>{calls.push('agent-verify');}
};}
function fakeFS() {
  const files = new Map([[path.join(root, 'sandbox-owned.json'), JSON.stringify(owner)],
    [path.join(root, 'Runtime', 'node', 'node.exe'), ''], [path.join(root, 'Data', 'bootstrap-verified.json'), '']]);
  return { files, existsSync: p => files.has(p), readFileSync: p => files.get(p),
    unlinkSync(p) { if (!files.delete(p)) { const error = Error('missing'); error.code = 'ENOENT'; throw error; } },
    writeFileSync(p, value, options) { if (options?.flag === 'wx' && files.has(p)) throw Error('exists'); files.set(p, value); } };
}
test('strict command and guest workspace parsing', () => {
  for (const args of [[], ['wat', root], ['stop', root, 'x'], ['ide', root, '/etc'], ['ide', root, '/home/sandbox/workspaces/../x'], ['terminal', root, 'x', 'y']]) assert.throws(() => cli.parse(args));
  assert.equal(cli.parse(['ide', root, '/home/sandbox/workspaces/demo']).project, '/home/sandbox/workspaces/demo');
});
test('authentication rejects origins, host aliases, malformed tokens and bodies', () => {
  const headers = { host: '127.0.0.1:23456', authorization: `Bearer ${state.token}` };
  assert.equal(cli.authorized({ headers }, state), true);
  for (const patch of [{ origin: 'null' }, { origin: '' }, { host: 'localhost:23456' }, { host: '127.0.0.1:1' },
    { authorization: 'Bearer x' }, { authorization: `Bearer ${'c'.repeat(64)}` }, { 'content-length': '1025' },
    { 'content-length': '-1' }, { 'transfer-encoding': 'chunked' }]) assert.equal(cli.authorized({ headers: { ...headers, ...patch } }, state), false);
  assert.equal(JSON.stringify(cli.publicState(state)).includes(state.token), false);
  for (const patch of [{ port: 0 }, { port: 65536 }, { token: 'x' }, { rootId: 'other' }, { phase: 'unknown' }]) assert.equal(cli.validState({ ...state, ...patch }, root, state.rootId), false);
});
test('stale state never spawns or kills; ownership requires authenticated API', async () => {
  const fs = fakeFS(); fs.files.set(path.join(root, 'Data', 'manager.json'), JSON.stringify({ ...state, pid: 4 }));
  let spawns = 0;
  await assert.rejects(cli.ensure(root, { fs, spawn() { spawns++; throw Error('forbidden'); }, request: async () => { throw Error('offline'); } }), /Stale/);
  assert.equal(spawns, 0);
  await assert.rejects(cli.existing(root, { fs, request: async () => ({ ...state, managerNonce: 'other' }) }), /ownership/);
  assert.equal((await cli.existing(root, { fs, request: async () => cli.publicState(state) })).answer.phase, 'ready');
});
test('guarded stale recovery serializes proof and new-manager publication without PID cleanup', async () => {
  const fs = fakeFS(), calls = [], file = path.join(root, 'Data/manager.json');
  fs.files.set(file, JSON.stringify(state));
  const fresh = { ...state, managerNonce: 'c'.repeat(64) };
  const recovery = {
    async acquireLease(r, scope) { calls.push('lease-' + scope); return { async close() { calls.push('close-' + scope); } }; },
    async recover(r, snapshot) { assert.equal(r, root); assert.equal(snapshot.state.managerNonce, state.managerNonce); assert.equal(snapshot.raw.toString(), JSON.stringify(state)); calls.push('preserve'); fs.files.delete(file); }
  };
  fs.openSync = () => 1; fs.closeSync = () => {};
  const result = await cli.ensure(root, { fs, recovery, prepareStorage: async () => calls.push('storage'),
    request: async s => { if (s.managerNonce === state.managerNonce) throw Error('offline'); return cli.publicState(s); },
    spawn() { calls.push('spawn'); fs.files.set(file, JSON.stringify(fresh)); const child = new EventEmitter(); child.unref = () => {}; queueMicrotask(() => child.emit('spawn')); return child; }
  });
  assert.equal(result.state.managerNonce, fresh.managerNonce);
  assert(calls.indexOf('lease-startup') < calls.indexOf('lease-manager'));
  assert(calls.indexOf('lease-manager') < calls.indexOf('preserve'));
  assert(calls.indexOf('preserve') < calls.indexOf('close-manager'));
  assert(calls.indexOf('close-manager') < calls.indexOf('spawn'));
  assert.equal(calls.at(-1), 'close-startup');
});
test('recovery denial preserves marker and never spawns a replacement', async () => {
  const fs = fakeFS(), file = path.join(root, 'Data/manager.json'), original = JSON.stringify(state), calls = [];
  fs.files.set(file, original);
  await assert.rejects(cli.ensure(root, { fs,
    request: async () => { throw Error('offline'); }, spawn() { throw Error('forbidden spawn'); },
    recovery: { async acquireLease(r, scope) { return { async close() { calls.push(scope); } }; }, async recover() { throw Error('Disk is still owned'); } }
  }), /Disk is still owned/);
  assert.equal(fs.files.get(file), original); assert.deepEqual(calls, ['manager', 'startup']);
});
test('interrupted atomic manager save leaves the prior state complete and unchanged', t => {
  const fs = require('node:fs'), os = require('node:os'), dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sandbox-state-save-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, 'manager.json'), prior = JSON.stringify(state); fs.writeFileSync(file, prior);
  const io = { ...fs, writeFileSync(p) { assert.notEqual(p, file); fs.writeFileSync(p, '{'); throw Error('simulated interrupted write'); } };
  assert.throws(() => cli.atomicStateWrite(file, { ...state, phase: 'stopped' }, io, state), /interrupted/);
  assert.equal(fs.readFileSync(file, 'utf8'), prior);
});
test('atomic state saves refuse another generation before writing', () => {
  let writes = 0;
  const fs = { existsSync: () => true, readFileSync: () => JSON.stringify({ ...state, managerNonce: 'c'.repeat(64) }), writeFileSync() { writes++; } };
  assert.throws(() => cli.atomicStateWrite('manager.json', state, fs, state), /ownership changed/);
  assert.equal(writes, 0);
});
test('missing private runtime and Windows SSH fail without fallback', async () => {
  const fs = fakeFS(); fs.files.delete(path.join(root, 'Runtime', 'node', 'node.exe'));
  assert.throws(() => cli.gate(root, fs), /Required/);
  assert.throws(() => cli.terminalCommand(root, {}, fs), /Required/);
  let started = false;
  await assert.rejects(cli.main(['terminal', root], { fs, env: {}, ready: async () => { started = true; } }), /Required/);
  assert.equal(started, false);
});
test('startup key rejection reports this manager failure instead of null-state TypeError', async () => {
  const fs = fakeFS(), file = path.join(root,'Data/manager.json');
  fs.files.set(file,JSON.stringify({...state,phase:'booting'}));
  await assert.rejects(cli.ready(root,{fs,request:async()=>{
    fs.files.delete(file);fs.files.set(path.join(root,'Data/manager-last.json'),JSON.stringify({...cli.publicState(state),phase:'failed',failureCode:'SSH_KEY_STORAGE_UNSUPPORTED'}));
    return {...cli.publicState(state),phase:'booting'};
  }}),/OpenSSH.*storage/);
});
test('an explicit open during authenticated shutdown waits for cleanup and then starts once', async () => {
  const fs = fakeFS(), file = path.join(root, 'Data/manager.json'); let requests = 0, spawns = 0;
  fs.files.set(file, JSON.stringify({ ...state, phase: 'stopping' })); fs.openSync = () => 1; fs.closeSync = () => {};
  const fresh = { ...state, managerNonce: 'd'.repeat(64), phase: 'ready' };
  const found = await cli.ready(root, { fs, prepareStorage: async () => {}, request: async s => {
    if (s.managerNonce === fresh.managerNonce) return cli.publicState(fresh);
    if (++requests === 2) { fs.files.delete(file); fs.files.set(path.join(root, 'Data/manager-last.json'), JSON.stringify({ ...cli.publicState(state), phase: 'stopped' })); }
    return { ...cli.publicState(state), phase: 'stopping' };
  }, spawn() { assert(!fs.files.has(file)); spawns++; fs.files.set(file, JSON.stringify(fresh)); const child = new EventEmitter(); child.unref = () => {}; queueMicrotask(() => child.emit('spawn')); return child; } });
  assert.equal(found.state.managerNonce, fresh.managerNonce); assert.equal(spawns, 1);
});
test('a stop arriving after this client began booting remains a cancellation, not a reboot loop', async () => {
  const fs = fakeFS(), file = path.join(root, 'Data/manager.json'); let requests = 0, spawns = 0;
  fs.files.set(file, JSON.stringify({ ...state, phase: 'booting' }));
  await assert.rejects(cli.ready(root, { fs, request: async () => ({ ...cli.publicState(state), phase: ++requests === 1 ? 'booting' : 'stopping' }),
    spawn() { spawns++; throw Error('must not restart a cancelled boot'); } }), /Guest is not ready/);
  assert.equal(spawns, 0);
});
test('startup does not reuse a different managers failure receipt',async()=>{
  const fs=fakeFS(),file=path.join(root,'Data/manager.json');fs.files.set(file,JSON.stringify({...state,phase:'booting'}));
  await assert.rejects(cli.ready(root,{fs,request:async()=>{fs.files.delete(file);fs.files.set(path.join(root,'Data/manager-last.json'),JSON.stringify({...cli.publicState(state),managerNonce:'c'.repeat(64),phase:'failed',failureCode:'SSH_KEY_STORAGE_UNSUPPORTED'}));return{...cli.publicState(state),phase:'booting'};}}),/Manager ended/);
});
for(const route of ['/stop','/force-stop'])test('operator can cancel restricted bootstrap with no automatic force or runtime: '+route,async()=>{
  const fs=fakeFS();let handler,power=0,force=0;
  const server={once(){},listen(p,h,cb){cb();},address:()=>({port:23456}),close(){}};
  await cli.manager(root,{fs,privateAgent:fakeAgent(),createServer(fn){handler=fn;return server;},prototype:{
    prepareStorage:async()=>({protection:'reduced'}),prepare:async()=>({agentIdentity:{}}),
    boot:async(r,stage,callback,options)=>{
      assert.equal(stage,'bootstrap');assert.equal(options.allowForce,false);
      options.onControl({powerDown:async()=>power++,forceStop:async()=>force++});
      const saved=JSON.parse(fs.files.get(path.join(root,'Data/manager.json'))),req=new EventEmitter();
      Object.assign(req,{method:'POST',url:route,headers:{host:`127.0.0.1:${saved.port}`,authorization:`Bearer ${saved.token}`}});
      let completed;const reply=new Promise(resolve=>{completed=resolve;});
      await handler(req,{writeHead(code){assert.equal(code,200);},end(){completed();}});req.emit('end');await reply;
      throw Error('owned operator cancellation before ready');
    }
  }});
  assert.equal(power,route==='/stop'?1:0);assert.equal(force,route==='/force-stop'?1:0);
  assert.equal(JSON.parse(fs.files.get(path.join(root,'Data/manager-last.json'))).phase,'stopped');
});
for (const protection of ['acl', 'reduced']) for (const current of [false, true]) test(`cold start ordering ${protection} current=${current}`, async () => {
  const fs = fakeFS(), calls = [], file = path.join(root, 'Data', 'manager.json');
  fs.files.delete(path.join(root, 'Data', 'bootstrap-verified.json'));
  const server = { once() {}, listen(p, h, cb) { cb(); }, address: () => ({ port: 23456 }), close() {} };
  const deps = { fs, privateAgent:fakeAgent(calls), createServer: () => server, prototype: {
    prepareStorage: async () => { assert.equal(fs.files.has(file), false); calls.push('storage'); return { protection }; },
    prepare: async () => { assert.equal(fs.files.has(file), true); calls.push('prepare'); return{agentIdentity:{}}; },
    bootstrapCurrent: () => current,
    boot: async (r, stage, callback,options) => { assert.equal(fs.files.has(file), true); assert.equal(Boolean(options.agentPipe),protection==='reduced'); calls.push(stage); }
  } };
  await cli.manager(root, deps);
  await cli.manager(root, deps);
  const expected = ['storage', 'prepare', ...(protection==='reduced'?['agent-start','agent-verify']:[]), ...(protection === 'reduced' || !current ? ['bootstrap'] : []), 'runtime',...(protection==='reduced'?['agent-close']:[])];
  assert.deepEqual(calls, [...expected, ...expected]);
});
test('bootstrap failure never starts runtime', async () => {
  const fs = fakeFS(), calls = [];
  const server = { once() {}, listen(p, h, cb) { cb(); }, address: () => ({ port: 23456 }), close() {} };
  await assert.rejects(cli.manager(root, { fs, createServer: () => server, prototype: {
    prepareStorage: async () => ({ protection: 'acl' }), prepare: async () => {}, bootstrapCurrent: () => false,
    boot: async (r, stage) => { calls.push(stage); throw Error('bootstrap failed'); }
  } }), /bootstrap failed/);
  assert.deepEqual(calls, ['bootstrap']);
});
test('private-agent native verification failure closes its own agent before any VM boot',async()=>{
 const fs=fakeFS(),calls=[],privateAgent=fakeAgent(calls);privateAgent.verifyClient=async()=>{calls.push('agent-verify');throw Error('native agent rejected');};
 const server={once(){},listen(p,h,cb){cb();},address:()=>({port:23456}),close(){}};
 await assert.rejects(cli.manager(root,{fs,privateAgent,createServer:()=>server,prototype:{prepareStorage:async()=>({protection:'reduced'}),prepare:async()=>({agentIdentity:{}}),boot:async()=>{calls.push('forbidden-boot');}}}),/native agent rejected/);
 assert.deepEqual(calls,['agent-start','agent-verify','agent-close']);assert.equal(JSON.parse(fs.files.get(path.join(root,'Data/manager-last.json'))).phase,'failed');
});
test('private-agent death during restricted bootstrap never promotes runtime or readiness',async()=>{
 const fs=fakeFS(),calls=[],privateAgent=fakeAgent(calls);let session,alive=true;const start=privateAgent.start;
 privateAgent.start=async()=>{session=await start();session.isAlive=()=>alive;return session;};
 const server={once(){},listen(p,h,cb){cb();},address:()=>({port:23456}),close(){}};
 await assert.rejects(cli.manager(root,{fs,privateAgent,createServer:()=>server,prototype:{prepareStorage:async()=>({protection:'reduced'}),prepare:async()=>({agentIdentity:{}}),boot:async(r,stage)=>{assert.equal(stage,'bootstrap');calls.push(stage);alive=false;session.child.emit('exit',1);}}}),/Private agent ended/);
 assert.deepEqual(calls,['agent-start','agent-verify','bootstrap','agent-close']);const last=JSON.parse(fs.files.get(path.join(root,'Data/manager-last.json')));assert.equal(last.phase,'failed');assert.equal(last.failureCode,'SSH_AGENT_UNAVAILABLE');
});
test('ensure prepares storage before opening logs without requiring bootstrap proof', async () => {
  const fs = fakeFS(), calls = [];
  fs.files.delete(path.join(root, 'Data', 'bootstrap-verified.json'));
  fs.openSync = () => { calls.push('log'); return 1; };
  fs.closeSync = () => { calls.push('close'); };
  await cli.ensure(root, { fs, prepareStorage: async () => { calls.push('storage'); },
    request: async () => cli.publicState(state), spawn() {
      calls.push('spawn'); fs.files.set(path.join(root, 'Data', 'manager.json'), JSON.stringify(state));
      const child = new EventEmitter(); child.unref = () => {};
      queueMicrotask(() => child.emit('spawn')); return child;
    } });
  assert.deepEqual(calls, ['storage', 'log', 'spawn', 'close']);
  calls.length = 0;
  await cli.ensure(root, { fs, prepareStorage: async () => { throw Error('must reuse manager'); }, request: async () => cli.publicState(state) });
  assert.deepEqual(calls, []);
});
test('concurrent claim loser closes server without VM mutation', async () => {
  const fs = fakeFS(); let closed = false;
  const server = { once() {}, listen(p, h, cb) { fs.files.set(path.join(root, 'Data', 'manager.json'), 'winner'); cb(); },
    address: () => ({ port: 23456 }), close() { closed = true; } };
  await assert.rejects(cli.manager(root, { fs, createServer: () => server, prototype: {
    prepareStorage: async () => ({ protection: 'acl' }), prepare: async () => { throw Error('VM mutation forbidden'); },
    boot: async () => { throw Error('VM mutation forbidden'); }
  } }), /exists/);
  assert.equal(closed, true);
});
test('terminal argument arrays and environment never inherit credentials', async () => {
  const command = cli.terminalCommand(root, { SystemRoot: 'C:\\Windows' }, { existsSync: () => true });
  assert.ok(command.args.includes('-T'));assert.ok(!command.args.includes('-tt'));
  assert.deepEqual(command.args.slice(3,5),['-e','none']);
  assert.match(command.args.at(-1),/^\/usr\/bin\/python3 -I -c 'import base64;exec\(compile\(base64\.b64decode\("[A-Za-z0-9+/=]+"\),"<portable-terminal>","exec"\)\)'$/);
  const env = cli.environment(root, { SSH_AUTH_SOCK: 'secret', GITHUB_TOKEN: 'secret', SystemRoot: 'C:\\Windows',
    ProgramData: 'C:\\ProgramData', HOME: 'C:\\host-account', USERPROFILE: 'C:\\host-account', USERNAME: 'host-user' });
  assert.equal(env.SSH_AUTH_SOCK, undefined); assert.equal(env.GITHUB_TOKEN, undefined);
  assert.equal(env.ProgramData, 'C:\\ProgramData'); assert.equal(env.USERNAME, undefined);
  assert.equal(env.USERPROFILE, path.join(root, 'Data'));
  assert.equal(env.HOME, path.join(root, 'Data'));
  const code = await cli.launch(command.executable, command.args, root, { spawn(exe, args, opts) {
    assert.equal(exe, command.executable); assert.deepEqual(args, command.args); assert.equal(opts.shell, false);
    assert.equal(opts.stdio, 'inherit'); const child = new EventEmitter(); queueMicrotask(() => child.emit('exit', 7)); return child;
  } });
  assert.equal(code, 7);
});
test('IDE fake-only launch uses private paths and Electron CLI install', async () => {
  const calls = [], source = { LOCALAPPDATA: 'C:\\Users\\example\\AppData\\Local' };
  const profile = require('./ide-workspace.cjs').workspace(root);
  const result = await cli.main(['ide', root], { env: source, fs: { existsSync: p => !p.endsWith(path.sep + 'data') }, ready: async () => {},
    stageWorkspace: () => ({ extensionArgs: ['--user-data-dir', profile.userData, '--extensions-dir', profile.extensions, '--install-extension', 'ms-vscode-remote.remote-ssh'],
      openArgs: ['--new-window', '--user-data-dir', profile.userData, '--extensions-dir', profile.extensions, profile.workspaceFile] }),
    spawn(exe, args, options) { calls.push({ exe, args, options }); const child = new EventEmitter(); queueMicrotask(() => child.emit('exit', 0)); return child; } });
  assert.equal(result, 0); assert.equal(calls.length, 2);
  assert.equal(calls[0].options.env.ELECTRON_RUN_AS_NODE, '1');
  assert.equal(calls[1].options.env.ELECTRON_RUN_AS_NODE, undefined);
  assert.equal(calls[0].args[0].endsWith(path.join('resources', 'app', 'out', 'cli.js')), true);
  for (const call of calls) { assert.equal(call.options.shell, false); assert.ok(call.args.includes(profile.userData)); assert.ok(call.args.includes(profile.extensions)); }
});
test('IDE portable installation data cannot override the dedicated private profile', () => {
  assert.throws(() => cli.codeCommand({ LOCALAPPDATA: path.resolve('public-app') }, { existsSync: () => true }), /portable data.*profile principal/);
});
test('IDE CLI follows the actual versioned public code.cmd asset without executing it', () => {
  const source = { LOCALAPPDATA: path.resolve('public-app') };
  const base = path.join(source.LOCALAPPDATA, 'Programs', 'Microsoft VS Code');
  const executable = path.join(base, 'Code.exe'); const tag = '8a7abeba6e';
  const script = path.join(base, tag, 'resources', 'app', 'out', 'cli.js');
  const launcher = path.join(base, 'bin', 'code.cmd');
  const files = new Set([executable, script, launcher]);
  const result = cli.codeCommand(source, { existsSync: p => files.has(p),
    readFileSync: p => { assert.equal(p, launcher); return '"%~dp0..\\Code.exe" "%~dp0..\\8a7abeba6e\\resources\\app\\out\\cli.js" %*'; } });
  assert.equal(result.cli, script); assert.equal(result.executable, executable);
});
for (const stopRoute of ['/stop', '/force-stop']) test(`manager holds callback until explicit ${stopRoute}`, async () => {
  const fs = fakeFS(); let handler, force = 0, bootOptions;
  const server = { once() {}, listen(port, host, cb) { assert.equal(host, '127.0.0.1'); cb(); }, address: () => ({ port: state.port }), close() {} };
  const running = cli.manager(root, { fs, createServer(fn) { handler = fn; return server; }, prototype: {
    prepareStorage: async () => ({ protection: 'acl' }), bootstrapCurrent: () => true,
    prepare: async () => {}, boot: async (r, stage, callback, options) => {
      bootOptions = options;
      const child = new EventEmitter();
      const held = callback({ child, forceStop: async () => { force++; } });
      const saved = JSON.parse(fs.files.get(path.join(root, 'Data', 'manager.json')));
      assert.equal(saved.phase, 'ready');
      const req = new EventEmitter(); Object.assign(req, { method: 'POST', url: stopRoute, headers: { host: `127.0.0.1:${saved.port}`, authorization: `Bearer ${saved.token}` } });
      await handler(req, { writeHead(code) { assert.equal(code, 200); }, end() {} }); req.emit('end'); await held;
    } } });
  await running;
  assert.equal(bootOptions.allowForce, false); assert.equal(typeof bootOptions.onControl, 'function'); assert.deepEqual(Object.keys(bootOptions).sort(),['allowForce','onControl']); assert.equal(force, stopRoute === '/force-stop' ? 1 : 0);
  assert.equal(fs.files.has(path.join(root, 'Data', 'manager.json')), false);
  assert.equal(JSON.parse(fs.files.get(path.join(root, 'Data', 'manager-last.json'))).phase, 'stopped');
});
test('guest boot failure remains failed and never reports ready', async () => {
  const fs = fakeFS();
  const server = { once() {}, listen(p, h, cb) { cb(); }, address: () => ({ port: 23456 }), close() {} };
  await assert.rejects(cli.manager(root, { fs, createServer: () => server, prototype: {
    prepareStorage: async () => ({ protection: 'acl' }), bootstrapCurrent: () => true,
    prepare: async () => {}, boot: async () => { throw Error('fresh guest failed'); }
  } }), /fresh guest failed/);
  assert.equal(fs.files.has(path.join(root, 'Data', 'manager.json')), false);
  assert.equal(JSON.parse(fs.files.get(path.join(root, 'Data', 'manager-last.json'))).phase, 'failed');
});

'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const workspace = path.resolve(__dirname, '../..');
const fixture = fs.mkdtempSync(path.join(workspace, 'zig-out', 'herdr-build-files-'));
fs.writeFileSync(path.join(fixture, '.owned'), 'herdr-build-files-test-v1');
const src = path.join(fixture, 'source'); const out = path.join(fixture, 'output');
for (const rel of ['bin/portable-data/npm/node_modules', 'bin/portable-data/runtimes/git', 'bin/portable-data/apps/herdr/0.9.5', 'bin/portable-data/shims']) fs.mkdirSync(path.join(src, rel), { recursive: true });
const deep = 'bin/portable-data/npm/node_modules/' + ('deep-package-name-0123456789/').repeat(10) + 'public.js';
fs.mkdirSync(path.dirname(path.join(src, deep)), { recursive: true }); fs.writeFileSync(path.join(src, deep), 'public synthetic package');
assert(path.join(src, deep).length > 300);
for (const rel of ['bin/portable-data/runtimes/git/public.txt', 'bin/portable-data/apps/herdr/0.9.5/public.txt', 'bin/portable-data/shims/git.exe', 'bin/portable-data/shims/git.proxy.json']) fs.writeFileSync(path.join(src, rel), 'synthetic; never executed');
fs.mkdirSync(path.join(out, 'bin/portable-data/shims'), { recursive: true });
const privateTarget = path.join(fixture, 'synthetic-private-do-not-follow'); fs.mkdirSync(privateTarget);
fs.writeFileSync(path.join(privateTarget, 'account-sentinel.json'), 'synthetic account sentinel; not a credential');
fs.symlinkSync(privateTarget, path.join(src, 'bin/portable-data/profiles'), 'junction');
const helper = path.join(__dirname, 'herdr-build-files.cjs');
function run(args) { const r = cp.spawnSync(process.execPath, [helper, ...args], { encoding: 'utf8', windowsHide: true, timeout: 20000 }); assert.ifError(r.error); return r; }
const copied = run(['copy-ready', src, out]); assert.equal(copied.status, 0, copied.stderr);
assert.equal(fs.readFileSync(path.join(out, deep), 'utf8'), 'public synthetic package');
assert(!fs.existsSync(path.join(out, 'bin/portable-data/profiles')), 'Private profile was copied');
// Even a profile junction must be excluded before manifest descent.
fs.symlinkSync(privateTarget, path.join(out, 'bin/portable-data/profiles'), 'junction');
const manifest = run(['manifest', out]); assert.equal(manifest.status, 0, manifest.stderr);
const files = JSON.parse(manifest.stdout); assert.equal(files.length, 5);
assert(files.every(f => !f.path.includes('profiles') && /^[a-f0-9]{64}$/i.test(f.sha256)));
assert(files.some(f => f.path.endsWith('public.js')));
const second = run(['copy-ready', src, out]); assert.notEqual(second.status, 0, 'Merged into used destination');
const out3 = path.join(fixture,'factory-output'); fs.mkdirSync(path.join(out3,'bin/portable-data/shims'),{recursive:true});
const copy3=run(['copy-ready',src,out3]); assert.equal(copy3.status,0,copy3.stderr);
const metaDir=path.join(out3,'bin/portable-data/profiles/herdr/tmp');fs.mkdirSync(metaDir,{recursive:true});
const metadata=path.join(metaDir,'build.json');fs.writeFileSync(metadata,JSON.stringify({schema:1,ready_Herdr:true,user_data_copied:false}));
const finalized=run(['finalize',out3,metadata]);assert.equal(finalized.status,0,finalized.stderr);
const factory=JSON.parse(fs.readFileSync(path.join(out3,'package-manifest.json'),'utf8'));
assert(Array.isArray(factory.files));assert.deepEqual(factory.files,files,'Direct JSON writer changed immutable manifest meaning');
assert.equal(run(['finalize',out3,metadata]).status,1,'Replaced existing factory catalog');
const bad = path.join(src, 'bin/portable-data/npm/node_modules/untrusted-link'); fs.symlinkSync(privateTarget, bad, 'junction');
const out2 = path.join(fixture, 'refused-output'); fs.mkdirSync(path.join(out2, 'bin/portable-data/shims'), { recursive: true });
const rejected = run(['copy-ready', src, out2]); assert.notEqual(rejected.status, 0); assert.match(rejected.stderr, /Reparse/);
const escaped = run(['manifest', workspace]); assert.notEqual(escaped.status, 0);
const result = { passed: true, fixture, deep_windows_copy_and_hash: true, no_source_profile_followed_or_copied: true,
  mutable_profile_excluded_before_manifest_descent: true, public_reparse_rejected: true,
  merge_and_workspace_escape_rejected: true, direct_factory_json_array_and_equivalence: true, host_or_A_touched: false };
fs.writeFileSync(path.join(fixture, 'results.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));

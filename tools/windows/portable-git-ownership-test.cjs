'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const roots = process.argv.slice(2).map(p => path.resolve(p));
assert.equal(roots.length, 2);
const name = 'ow-' + crypto.randomBytes(5).toString('hex');
const relative = '%(prefix)/../../../tmp/' + name + '/home/.letta/local/memfs/*';
const gitFor = root => path.join(root, 'bin/portable-data/runtimes/git/cmd/git.exe');
const scratchFor = root => path.join(root, 'bin/portable-data/tmp', name);
const first = scratchFor(roots[0]);
fs.mkdirSync(first, { recursive: false });
fs.writeFileSync(path.join(first, '.owned'), 'portable-git-ownership-v1');
const home = path.join(first, 'home');
fs.mkdirSync(home);
const config = path.join(home, '.gitconfig');
fs.writeFileSync(config, '');
const memory = path.join(home, '.letta/local/memfs/agent-local-synthetic/memory');
const outside = path.join(first, 'external-workspace');
const template = path.join(first, 'empty-template');
for (const p of [memory, outside, template]) fs.mkdirSync(p, { recursive: true });
function run(root, scratch, cwd, args, forceOwner = false) {
  const env = {
    SystemRoot: process.env.SystemRoot, WINDIR: process.env.SystemRoot,
    PATH: path.join(process.env.SystemRoot, 'System32'),
    HOME: path.join(scratch, 'home'), USERPROFILE: path.join(scratch, 'home'),
    TEMP: scratch, TMP: scratch, GIT_CONFIG_NOSYSTEM: '1',
    GIT_CONFIG_GLOBAL: path.join(scratch, 'home/.gitconfig'), GIT_TERMINAL_PROMPT: '0',
  };
  if (forceOwner) env.GIT_TEST_ASSUME_DIFFERENT_OWNER = '1';
  const r = cp.spawnSync(gitFor(root), args, { cwd, env, encoding: 'utf8', timeout: 15000, windowsHide: true });
  assert.ifError(r.error);
  return r;
}
function ok(r) { assert.equal(r.status, 0, r.stderr); return r.stdout; }
for (const repo of [memory, outside]) ok(run(roots[0], first, repo, ['-c', 'init.templateDir=' + template, 'init', '-q']));
const red = run(roots[0], first, memory, ['status', '--porcelain']);
assert.notEqual(red.status, 0, 'Expected real ownership rejection on first filesystem');
assert.match(red.stderr, /dubious ownership|does not record ownership/);
ok(run(roots[0], first, home, ['config', '--file', config, '--add', 'safe.directory', relative]));
ok(run(roots[0], first, memory, ['status', '--porcelain']));
ok(run(roots[0], first, memory, ['-c','user.name=Synthetic','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','commit','--allow-empty','-qm','owned synthetic memory']));
const sibling = run(roots[0], first, outside, ['status', '--porcelain']);
assert.notEqual(sibling.status, 0); assert.match(sibling.stderr, /dubious ownership/);
const next = path.join(home, '.letta/local/memfs/agent-local-another/memory');
fs.mkdirSync(next, { recursive: true });
ok(run(roots[0], first, next, ['-c', 'init.templateDir=' + template, 'init', '-q']));
ok(run(roots[0], first, next, ['status', '--porcelain']));
function assertNoLinks(p) {
  assert(!fs.lstatSync(p).isSymbolicLink(), 'Owned fixture contains a link');
  if (fs.statSync(p).isDirectory()) for (const entry of fs.readdirSync(p)) assertNoLinks(path.join(p, entry));
}
assertNoLinks(first);
const second = scratchFor(roots[1]); assert(!fs.existsSync(second));
fs.cpSync(first, second, { recursive: true, errorOnExist: true, force: false });
const movedMemory = path.join(second, path.relative(first, memory));
ok(run(roots[1], second, movedMemory, ['status', '--porcelain'], true));
const movedOutside = path.join(second, path.relative(first, outside));
const negative = run(roots[1], second, movedOutside, ['status', '--porcelain'], true);
assert.notEqual(negative.status, 0); assert.match(negative.stderr, /dubious ownership/);
const result = { passed: true, first, second, real_filesystem_red: true,
  prefix_relative_scoped_memory_trust: true, second_new_agent_works: true,
  memory_commit_works: true, unrelated_repos_still_rejected: true,
  moved_prefix_with_forced_different_owner_works: true, host_git_config_changed: false };
for (const p of [first, second]) fs.writeFileSync(path.join(p, 'results.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));

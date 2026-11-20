'use strict';
// Synthetic repository only. These commits are fixture data, never project work.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(process.argv[2]);
const workspace = path.resolve(__dirname, '..', '..');
const fixture = fs.mkdtempSync(path.join(workspace, 'zig-out', 'git-bash-hook-'));
const data = path.join(root, 'bin', 'portable-data');
assert.ok(fs.existsSync(path.join(data, 'runtimes', 'git', 'usr', 'bin', 'bash.exe')), 'Private Bash is required; never search for host/WSL Bash.');
const git = path.join(data, 'shims', 'git.exe');
const windows = process.env.SystemRoot;
const empty = path.join(fixture, 'empty.gitconfig'); fs.writeFileSync(empty, '');
const env = {
  SystemRoot: windows, WINDIR: windows, ComSpec: path.join(windows, 'System32', 'cmd.exe'),
  PATH: [path.join(data, 'shims'), path.join(data, 'runtimes', 'node'), path.join(windows, 'System32'), windows].join(';'),
  HOME: fixture, USERPROFILE: fixture, TEMP: fixture, TMP: fixture,
  GIT_CONFIG_GLOBAL: empty, GIT_CONFIG_NOSYSTEM: '1', GIT_TERMINAL_PROMPT: '0',
  PORTABLE_GIT_HOOK_PROOF: path.join(fixture, 'hook-proof.json'),
};
function run(args) {
  const r = cp.spawnSync(git, args, { cwd: fixture, env, encoding: 'utf8', windowsHide: true, timeout: 20000 });
  assert.ifError(r.error); assert.equal(r.status, 0, r.stderr); return r.stdout;
}
run(['-c', 'init.defaultBranch=main', 'init']);
const nodeProof = path.join(fixture, 'hook-node.cjs');
fs.writeFileSync(nodeProof, `const fs=require('node:fs');const cp=require('node:child_process');const version=cp.execFileSync('git',['--version'],{encoding:'utf8',windowsHide:true});fs.writeFileSync(process.env.PORTABLE_GIT_HOOK_PROOF,JSON.stringify({node:process.execPath,git:version,nestedGit:true}));`);
const msys = value => value.replaceAll('\\', '/').replace(/^([a-z]):\//i, (_, drive) => '/' + drive.toLowerCase() + '/');
const quote = value => "'" + value.replaceAll("'", "'\"'\"'") + "'";
const hook = `#!/usr/bin/env bash\nset -eu\nitems=("one with spaces" "two")\n[[ \${#items[@]} -eq 2 ]] || exit 41\n${quote(msys(process.execPath))} ${quote(msys(nodeProof))}\n`;
fs.writeFileSync(path.join(fixture, '.git', 'hooks', 'pre-commit'), hook);
fs.writeFileSync(path.join(fixture, 'MEMORY.md'), '# Synthetic memory fixture\n');
run(['add', 'MEMORY.md']);
run(['-c', 'user.name=Portable Git Test', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'test: initialize owned synthetic memory']);
const proof = JSON.parse(fs.readFileSync(env.PORTABLE_GIT_HOOK_PROOF, 'utf8'));
assert.equal(path.resolve(proof.node), path.resolve(process.execPath));
assert.match(proof.git, /^git version 2\.56\.0/);
assert.match(run(['rev-parse', 'HEAD']).trim(), /^[a-f0-9]{40}$/);
assert.equal(run(['remote']), '');
const result = { passed: true, fixture, BashArrayHookRan: true, privateNodeFromBash: true, nestedGitFromNode: true, noHooksSkipped: true, commitOnlyInSyntheticFixture: true, projectCommit: false, remote: false, realCredentials: false };
fs.writeFileSync(path.join(fixture, 'results.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));

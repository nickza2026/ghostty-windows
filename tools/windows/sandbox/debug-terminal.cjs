'use strict';
const { spawnSync } = require('node:child_process'); const { boot } = require('./prototype.cjs');
const { environment } = require('./runtime-cli.cjs'); const { inside } = require('./policy.cjs');
async function debug(root) {
  return boot(root, 'runtime', async ({ ssh }) => {
    const base = environment(root);
    delete base.ProgramData; // Retain the original failing minimal-env repro.
    const groups = [[], ['ProgramData'], ['ALLUSERSPROFILE'], ['ProgramData', 'ALLUSERSPROFILE']];
    for (const keys of groups) {
      const env = { ...base };
      for (const key of keys) if (process.env[key]) env[key] = process.env[key];
      const r = spawnSync(ssh, ['-F', inside(root, 'Data/ssh/config'), 'portable-sandbox', 'printf "ENV_PROBE_OK\\n"; id -u'],
        { shell: false, windowsHide: true, env, encoding: 'utf8', timeout: 6000 });
      console.log(JSON.stringify({ addedOsMetadataNames: keys, status: r.status, out: r.stdout, err: r.stderr?.slice(-300) }));
    }
    const cases = [
      ['nonlogin', [], 'printf "NONLOGIN_OK\\n"; id -u'],
      ['login-command', [], '/bin/bash -lc \'printf "LOGIN_COMMAND_OK\\n"\''],
      ['pty-command', ['-tt'], 'printf "PTY_COMMAND_OK\\n"; id -u'],
      ['pty-login', ['-tt'], 'printf "BEFORE_BASH_OK\\n"; cd /home/sandbox/workspaces && exec /bin/bash -l'],
    ];
    for (const [name, flags, command] of cases) {
      const r = spawnSync(ssh, ['-F', inside(root, 'Data/ssh/config'), ...flags, 'portable-sandbox', command],
        { shell: false, windowsHide: true, env: environment(root), encoding: 'utf8', timeout: 6000,
          input: 'printf "BASH_INPUT_OK\\n"\nexit\n', maxBuffer: 262144 });
      // Escape controls so a diagnostic cannot activate terminal protocols.
      console.log(JSON.stringify({ name, status: r.status, error: r.error?.message,
        out: r.stdout?.slice(-1200), err: r.stderr?.slice(-600) }));
    }
  });
}
if (require.main === module) debug(process.argv[2]).then(r => console.log(JSON.stringify(r))).catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { debug };

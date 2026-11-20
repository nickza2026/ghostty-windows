'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { renderUnits, unitPath } = require('./herdr-user-service-units.cjs');
const config = { repo: '/home/fixture/workspaces/herdr-web', node: '/opt/node/bin/node', runner: '/home/fixture/.local/lib/sandbox-herdr-services/runner.cjs', configPath: '/home/fixture/.local/state/sandbox-herdr-services/config.json' };

test('user units retain one same-user principal and explicit runtime paths', () => {
  const units = renderUnits(config);
  assert.equal(Object.keys(units).length, 2);
  for (const text of Object.values(units)) {
    assert(text.includes('Type=notify\nNotifyAccess=all\n'));
    // systemd treats quotes in WorkingDirectory= as literal path characters.
    assert(text.includes(`WorkingDirectory=${config.repo}\n`));
    assert(!text.includes('WorkingDirectory="'));
    assert(text.includes(`ExecStart="${config.node}" "${config.runner}"`));
    assert(text.includes(`"${config.configPath}"`));
    assert(text.includes('UMask=0077\n'));
    assert(text.includes('KillMode=mixed\n'));
    assert(text.includes('WantedBy=default.target\n'));
    assert(!/^(?:User|Group|ExecStop|ExecStartPre)=/m.test(text));
    assert(!/sudo|nohup|&\s*$|pkill|killall|rm -|StartLimitBurst=0/m.test(text));
  }
});

test('native restart owns web ordering without making native depend on web readiness', () => {
  const units = renderUnits(config), native = units['sandbox-herdr-native.service'], web = units['sandbox-herdr-web.service'];
  assert(native.includes('Wants=sandbox-herdr-web.service\n'));
  assert(native.includes('Before=sandbox-herdr-web.service\n'));
  assert(!native.includes('Requires=sandbox-herdr-web.service'));
  assert(web.includes('BindsTo=sandbox-herdr-native.service\n'));
  assert(web.includes('After=sandbox-herdr-native.service\n'));
  assert(web.includes('PartOf=sandbox-herdr-native.service\n'));
  assert(native.includes(' native ')); assert(web.includes(' web '));
  assert(native.includes('StartLimitBurst=3')); assert(web.includes('StartLimitBurst=3'));
});

test('paths reject systemd expansion, newlines, aliases and ambiguous normalization', () => {
  for (const value of ['', '/', 'relative', '/tmp/../etc', '/tmp//x', '/tmp/x\nExecStart=/evil', '/tmp/%h', '/tmp/$HOME', '/tmp/"x', '/tmp/a\\b']) assert.throws(() => unitPath(value));
  assert.equal(unitPath('/home/fixture/.local/bin/node'), '"/home/fixture/.local/bin/node"');
});

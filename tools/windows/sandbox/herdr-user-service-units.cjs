'use strict';
const assert = require('node:assert/strict');
const path = require('node:path').posix;

// Explicit Linux guest paths only. Never infer a host, user, runtime or checkout.
function unitPath(value) {
  assert(typeof value === 'string' && /^\/[A-Za-z0-9_./-]+$/.test(value), 'Unsupported service path');
  assert.equal(path.normalize(value), value, 'Service paths must be canonical');
  assert(value !== '/', 'Root is not a service file');
  return `"${value}"`;
}

function renderUnits({ repo, node, runner, configPath }) {
  unitPath(repo);
  const cwd = repo;
  const command = [node, runner].map(unitPath).join(' ');
  const config = unitPath(configPath);
  const shared = (mode, timeout) => `[Service]
Type=notify
NotifyAccess=all
WorkingDirectory=${cwd}
ExecStart=${command} ${mode} ${config}
UMask=0077
Restart=on-failure
RestartSec=4
TimeoutStartSec=${timeout}
TimeoutStopSec=35
KillMode=mixed

[Install]
WantedBy=default.target
`;
  return {
    'sandbox-herdr-native.service': `[Unit]
Description=Sandbox native Herdr (automatic AI restore disabled)
Wants=sandbox-herdr-web.service
Before=sandbox-herdr-web.service
StartLimitIntervalSec=120
StartLimitBurst=3

${shared('native', 45)}`,
    'sandbox-herdr-web.service': `[Unit]
Description=Sandbox Herdr Web (explicit host-loopback forwarding)
BindsTo=sandbox-herdr-native.service
After=sandbox-herdr-native.service
PartOf=sandbox-herdr-native.service
StartLimitIntervalSec=300
StartLimitBurst=3

${shared('web', 240)}`,
  };
}

module.exports = { renderUnits, unitPath };

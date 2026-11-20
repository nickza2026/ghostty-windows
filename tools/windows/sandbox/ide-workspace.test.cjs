'use strict';
const test = require('node:test'); const assert = require('node:assert/strict'); const path = require('node:path');
const { guestUri, workspace } = require('./ide-workspace.cjs');
test('external IDE uses guest URI, not a host filesystem mount or host account', () => {
  const cfg = workspace(path.resolve('owned'), '/home/sandbox/workspaces/โปรเจค one');
  assert.match(cfg.workspace.folders[0].uri, /^vscode-remote:\/\/ssh-remote\+portable-sandbox\/home\/sandbox\/workspaces\//);
  assert(!cfg.workspace.folders[0].path);
  assert.equal(cfg.settings['security.workspace.trust.enabled'], true);
  assert.equal(cfg.settings['telemetry.telemetryLevel'], 'off');
  assert.equal(cfg.settings['update.mode'], 'none');
  assert.equal(cfg.settings['extensions.autoUpdate'], false);
  assert(cfg.userData.startsWith(path.resolve('owned')));
  assert(cfg.extensions.startsWith(path.resolve('owned')));
});
test('workspace cannot inject SSH authority, host drive, or shell commands', () => {
  for (const value of ['D:\\projects', '/home/sandbox/workspaces-other', '/home/sandbox/workspaces/../secret',
    '/etc', '/home/sandbox/workspaces/\nHost attacker']) assert.throws(() => guestUri(value));
  assert(guestUri('/home/sandbox/workspaces/a;b').endsWith('/a%3Bb'));
});

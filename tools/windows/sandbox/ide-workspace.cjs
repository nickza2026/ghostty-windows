'use strict';
const path = require('node:path');
const fs = require('node:fs');
const { inside } = require('./policy.cjs');

function guestUri(project = '/home/sandbox/workspaces') {
  if (typeof project !== 'string' || /[\x00-\x1f\\]/.test(project) ||
      !project.startsWith('/home/sandbox/workspaces') ||
      (project !== '/home/sandbox/workspaces' && !project.startsWith('/home/sandbox/workspaces/')) ||
      project.split('/').some(part => part === '..' || part === '.')) throw Error('Invalid guest workspace');
  return 'vscode-remote://ssh-remote+portable-sandbox' + project.split('/').map(encodeURIComponent).join('/');
}
function workspace(root, project) {
  return {
    workspace: { folders: [{ uri: guestUri(project) }], settings: {} },
    settings: { 'remote.SSH.configFile': inside(root, 'Data/ssh/config'),
      'remote.SSH.remotePlatform': { 'portable-sandbox': 'linux' },
      'security.workspace.trust.enabled': true, 'telemetry.telemetryLevel': 'off',
      'update.mode': 'none', 'extensions.autoUpdate': false },
    userData: inside(root, 'Data/ide/vscode-user'),
    extensions: inside(root, 'Data/ide/extensions'),
    workspaceFile: inside(root, 'Data/ide/guest.code-workspace'),
  };
}
function noLinks(target) {
  for (let p = path.resolve(target); ; p = path.dirname(p)) {
    if (fs.existsSync(p) && fs.lstatSync(p).isSymbolicLink()) throw Error('IDE path reparse refused');
    if (path.dirname(p) === p) break;
  }
}
function stageWorkspace(root, project) {
  const result = workspace(root, project);
  noLinks(root);
  if (!fs.existsSync(inside(root, 'Data/ssh/trusted_host_key'))) throw Error('Guest host key not verified; IDE entry refused');
  const marker = inside(root, 'Data/ide/managed-profile.json');
  noLinks(marker);
  if (fs.existsSync(result.userData) && !fs.existsSync(marker)) throw Error('Unmanaged IDE profile must not be overwritten');
  const user = path.join(result.userData, 'User');
  for (const p of [user, result.extensions]) { noLinks(p); fs.mkdirSync(p, { recursive: true }); }
  if (!fs.existsSync(marker)) fs.writeFileSync(marker, JSON.stringify({ schema: 1, kind: 'portable-sandbox-ide' }), { flag: 'wx' });
  const settingsPath = path.join(user, 'settings.json'); noLinks(settingsPath);
  const existing = fs.existsSync(settingsPath) ? JSON.parse(fs.readFileSync(settingsPath, 'utf8')) : {};
  // Only this tool's dedicated private profile; preserve user customizations.
  fs.writeFileSync(settingsPath, JSON.stringify({ ...existing, ...result.settings }, null, 2));
  noLinks(result.workspaceFile);
  fs.writeFileSync(result.workspaceFile, JSON.stringify(result.workspace, null, 2));
  return { ...result, openArgs: ['--new-window', '--user-data-dir', result.userData,
    '--extensions-dir', result.extensions, result.workspaceFile],
    extensionArgs: ['--user-data-dir', result.userData, '--extensions-dir', result.extensions,
      '--install-extension', 'ms-vscode-remote.remote-ssh'] };
}
module.exports = { guestUri, workspace, stageWorkspace };

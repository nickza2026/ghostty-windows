'use strict';
// Test-only preload. Never shipped as application configuration.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const { syncBuiltinESMExports } = require('node:module');
const log = process.env.PORTABLE_STARTUP_GUARD_LOG;
function blocked(kind) {
  if (log) fs.appendFileSync(log, JSON.stringify({ blocked: kind }) + '\n');
  throw new Error('Isolated startup test blocked ' + kind);
}
const net = require('node:net');
const originalConnect = net.Socket.prototype.connect;
const ownedPorts = new Set();
const originalListen = net.Server.prototype.listen;
net.Server.prototype.listen = function (...args) {
  this.once('listening', () => {
    const address = this.address();
    if (address && typeof address === 'object' && ['127.0.0.1', '::1'].includes(address.address)) ownedPorts.add(address.port);
  });
  return originalListen.apply(this, args);
};
net.Socket.prototype.connect = function (...args) {
  const item = args[0];
  const pipe = typeof item === 'string' ? item : item && item.path;
  if (typeof pipe === 'string' && pipe.startsWith('\\\\.\\pipe\\')) return originalConnect.apply(this, args);
  const options = item && typeof item === 'object' ? item : { port: item, host: args[1] };
  if (['127.0.0.1', '::1', 'localhost'].includes(options.host) && ownedPorts.has(Number(options.port))) return originalConnect.apply(this, args);
  return blocked('network connection');
};
require('node:tls').connect = () => blocked('TLS connection');
globalThis.fetch = async () => blocked('fetch');
require('node:dns').lookup = (host, options, callback) => {
  if (typeof options === 'function') { callback = options; options = {}; }
  if (!['localhost', '127.0.0.1', '::1'].includes(host)) return blocked('external DNS lookup');
  const address = host === '::1' ? '::1' : '127.0.0.1';
  const family = address === '::1' ? 6 : 4;
  process.nextTick(() => options && options.all ? callback(null, [{ address, family }]) : callback(null, address, family));
};
for (const method of ['spawn', 'spawnSync', 'execFile', 'execFileSync']) {
  const original = cp[method];
  cp[method] = function (program, ...args) {
    const file = String(program).toLowerCase();
    const privateGit = path.join(process.env.PORTABLE_STARTUP_PACKAGE, 'bin', 'portable-data', 'shims', 'git.exe').toLowerCase();
    if (file !== 'git' && file !== 'git.exe' && path.resolve(file) !== privateGit) return blocked('non-Git child process');
    if (log) fs.appendFileSync(log, JSON.stringify({ allowed: 'private Git' }) + '\n');
    return original.call(this, program, ...args);
  };
}
cp.exec = cp.execSync = () => blocked('shell child process');
syncBuiltinESMExports();

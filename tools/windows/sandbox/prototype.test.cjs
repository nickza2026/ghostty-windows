'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { guestMarkers } = require('./prototype.cjs');
const { bootstrapBound } = require('./prototype.cjs');
test('current request cannot inherit a valid old guest readiness artifact', () => {
  const old = 'a'.repeat(32), current = 'b'.repeat(32), key = 'A'.repeat(68);
  const previous = `PORTABLE_SANDBOX ${old} HOSTKEY ssh-ed25519 ${key} root@guest\nPORTABLE_SANDBOX ${old} BOOTSTRAP_READY \n`;
  assert.equal(guestMarkers(previous, current).hostKey, null);
  assert.equal(guestMarkers(previous, current).bootstrap, false);
  const fresh = previous + `PORTABLE_SANDBOX ${current} HOSTKEY ssh-ed25519 ${key} root@guest\nPORTABLE_SANDBOX ${current} BOOTSTRAP_READY \n`;
  assert.equal(guestMarkers(fresh, current).bootstrap, true);
  assert.equal(guestMarkers(fresh, current).hostKey, `ssh-ed25519 ${key}`);
  assert.equal(guestMarkers(fresh + `PORTABLE_SANDBOX ${current} HOSTKEY ssh-ed25519 ${key}\n`, current).hostKey, null);
});
test('guest error is not a ready state and invalid boot identity fails closed', () => {
  const id = 'a'.repeat(32);
  assert.equal(guestMarkers(`PORTABLE_SANDBOX ${id} ERROR install-failed`, id).failed, true);
  assert.equal(guestMarkers('BOOTSTRAP_READY', id).bootstrap, false);
  assert.throws(() => guestMarkers('', 'invalid'));
});

test('runtime readiness matches the actual guest blueprint TOOLS_READY protocol', () => {
  const id = 'a'.repeat(32);
  assert.equal(guestMarkers(`PORTABLE_SANDBOX ${id} TOOLS_READY \n`, id).runtime, true);
  assert.equal(guestMarkers(`PORTABLE_SANDBOX ${id} READY \n`, id).runtime, false);
});

test('fresh failure cannot be hidden by a serial login prompt or carriage return', () => {
  const id = 'a'.repeat(32);
  for (const prefix of ['portable-sandbox login: ', '\r\x1b[0m']) {
    assert.equal(guestMarkers(`${prefix}PORTABLE_SANDBOX ${id} FAILED phase=npm-install\n`, id).failed, true);
  }
  assert.equal(guestMarkers(`login: PORTABLE_SANDBOX ${'b'.repeat(32)} FAILED\n`, id).failed, false);
  assert.equal(guestMarkers(`login: PORTABLE_SANDBOX ${id} TOOLS_READY\n`, id).runtime, false);
});

test('old bootstrap proof cannot authorize a replacement disk or VM instance', () => {
  const expected = { instanceId: 'vm-1', hostKey: 'public-key', disk: { fileId: '123', createdNs: '456' } };
  const record = { ...expected, bootId: 'a'.repeat(32) };
  assert.equal(bootstrapBound(record, expected), true);
  for (const patch of [{ instanceId: 'vm-2' }, { hostKey: 'other-key' }, { disk: { fileId: '789', createdNs: '456' } }, { disk: undefined }])
    assert.equal(bootstrapBound({ ...record, ...patch }, expected), false);
});

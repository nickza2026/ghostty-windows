'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { sha512crypt, validHash } = require('./guest-password-hash.cjs');

// No trusted independent local SHA512-crypt vector was available for this task.
// These structural/determinism tests do not establish libcrypt compatibility.
test('deterministic hashing, salt and rounds, without caller mutation', () => {
  const password = Buffer.from('test-only-password');
  const original = Buffer.from(password);
  const hash = sha512crypt(password, './Az09', 5000);
  assert.equal(hash, sha512crypt(password, './Az09', 5000));
  assert.ok(validHash(hash));
  assert.match(hash, /^\$6\$rounds=5000\$\.\/Az09\$/);
  assert.notEqual(hash, sha512crypt(password, './Az09', 5001));
  assert.notEqual(hash, sha512crypt(password, 'other', 5000));
  assert.deepEqual(password, original);
  assert.equal(sha512crypt(password, 'salt'), sha512crypt(password, 'salt', 100000));
});

test('bounds and type checks', () => {
  for (const password of ['text', new Uint8Array(1), Buffer.alloc(1025, 65), Buffer.from([65, 0, 66])]) {
    assert.throws(() => sha512crypt(password, 'salt', 5000), /Invalid password buffer/);
  }
  for (const salt of ['', 'a'.repeat(17), 'a$b', 'é', 'a\n', null]) assert.throws(() => sha512crypt(Buffer.from('x'), salt, 5000), /Invalid salt/);
  for (const rounds of [4999, 1000001, 5000.5, NaN, Infinity, '5000', null]) assert.throws(() => sha512crypt(Buffer.from('x'), 'salt', rounds), /Invalid rounds/);
  assert.ok(validHash(sha512crypt(Buffer.alloc(0), 'a', 5000)));
  assert.ok(validHash(sha512crypt(Buffer.alloc(1024, 65), 'a'.repeat(16), 5000)));
  assert.throws(() => sha512crypt(Buffer.from('é'.repeat(513)), 'salt', 5000));
});

test('hash validation rejects malformed and out-of-policy hashes', () => {
  const body = '.'.repeat(86);
  assert.ok(validHash(`$6$salt$${body}`));
  assert.ok(validHash(`$6$rounds=1000000$salt$${body}`));
  for (const value of [null, {}, '', `$5$salt$${body}`, `$6$rounds=4999$salt$${body}`, `$6$rounds=1000001$salt$${body}`, `$6$rounds=05000$salt$${body}`, `$6$$${body}`, `$6$salt$${body}\n`, `$6$salt$${body.slice(1)}`, `$6$salt$${'.'.repeat(85)}2`]) assert.equal(validHash(value), false);
});

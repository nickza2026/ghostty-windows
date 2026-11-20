'use strict';
const { test } = require('node:test'), assert = require('node:assert/strict');
const { validateProof, validateProgramWrite } = require('./verify-native-first-use.cjs');
const { syntheticPassword } = require('./verify-password-console.cjs');
const nonce = '1234567890abcdef1234567890abcdef';
const proof = { nonce, privateNode: true, stdinTTY: true, stdoutTTY: true, validHash: true, rawRestored: true, firstPrompt: true, confirmPrompt: true, programOutput: 'Linux sudo password: *****\nConfirm Linux password: *****\n' };
test('completed actual setup proof requires freshness, masking and both real prompts', () => assert.doesNotThrow(() => validateProof(proof, nonce)));
test('a previously valid stale artifact is never success for another request', () => assert.throws(() => validateProof(proof, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')));
for (const field of ['privateNode', 'stdinTTY', 'stdoutTTY', 'validHash', 'rawRestored', 'firstPrompt', 'confirmPrompt']) test('setup refuses failed ' + field, () => assert.throws(() => validateProof({ ...proof, [field]: false }, nonce)));
test('setup refuses plaintext echo, hashes and unmasked/incomplete output', () => {
  for (const programOutput of [proof.programOutput + syntheticPassword, proof.programOutput + '$6$rounds=100000$fixture$not-a-real-hash', 'Linux sudo password: \nConfirm Linux password: \n', 'only *****']) assert.throws(() => validateProof({ ...proof, programOutput }, nonce));
});
test('unexpected plaintext/hash writes fail before any probe capture or forwarding', () => {
  for (const text of ['*', '\n', '\b \b', 'Linux sudo password: ']) assert.doesNotThrow(() => validateProgramWrite(text));
  for (const text of [syntheticPassword, '$6$rounds=100000$fixture$not-a-real-hash', 'unexpected output']) {
    assert.throws(() => validateProgramWrite(text), error => error.message === 'Unexpected password setup output; not captured');
  }
});

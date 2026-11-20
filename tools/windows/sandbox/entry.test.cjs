'use strict';
const test = require('node:test'); const assert = require('node:assert/strict'); const path = require('node:path');
const { preflight, main, showFailure } = require('./entry.cjs');
test('startup diagnostic summaries omit arbitrary private errors and redact control tokens', () => {
  const summary = require('./entry.cjs').failureSummary;
  assert(!JSON.stringify(summary(Error('Private configuration: secret-value'))).includes('secret-value'));
  assert(!summary(Error('Manager token ' + 'a'.repeat(64))).message.includes('a'.repeat(64)));
  assert(!JSON.stringify(summary(Object.assign(Error('Manager private-detail=synthetic-secret'), { code: 'PRIVATE_SECRET_CODE' }))).includes('synthetic-secret'));
  assert.equal(summary(Object.assign(Error('Anything'), { code: 'PRIVATE_SECRET_CODE' })).code, 'STARTUP_FAILURE');
  assert.equal(summary(Error('Automatic manager recovery was refused: UNRECOGNIZED_SECRET')).message, 'See the terminal for the startup failure.');
  assert.equal(summary(Error('Manager startup deadline')).message, 'Manager startup deadline');
});
test('native startup errors stay readable until user input, without opening a shell', async () => {
  const { PassThrough } = require('node:stream'); const input = new PassThrough(), raw = []; let text = '';
  input.isTTY = true; input.setRawMode = v => raw.push(v);
  let ended = false;
  const done = showFailure(Error('Disk is still owned'), ['terminal', 'owned'], { stdin: input, stderr: { write: t => text += t } }).then(code => { ended = true; return code; });
  await new Promise(resolve => setImmediate(resolve)); assert.equal(ended, false); assert.match(text, /Disk is still owned/); assert.match(text, /Press a key/);
  input.write('x'); assert.equal(await done, 1); assert.deepEqual(raw, [true, false]);
});
test('noninteractive failures never wait or consume input', async () => {
  const input = { isTTY: false, resume() { throw Error('Do not consume stdin'); } }; let text = '';
  assert.equal(await showFailure(Error('Unsafe\nstate'), ['terminal', 'owned'], { stdin: input, stderr: { write: t => text += t } }), 1);
  assert.match(text, /Unsafe state/); assert(!text.includes('Press a key'));
});
test('hardware preflight cannot consume guest terminal input or inherit host credentials', () => {
  const root = path.resolve('owned');
  preflight(root, (exe, args, options) => {
    assert.deepEqual(args.slice(0, 6), ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-File', path.join(__dirname, 'preflight.ps1')]);
    assert.deepEqual(options.stdio, ['ignore', 'inherit', 'inherit']);
    assert.equal(options.env.TEMP, path.join(root, 'Data'));
    assert.equal(options.env.API_KEY, undefined);
    assert.equal(options.shell, false);
    return { status: 0 };
  }, { SystemRoot: 'C:\\Windows', API_KEY: 'fake-do-not-inherit' });
});
test('entry delegates bootstrap to manager after preflight', async () => {
  const root = path.resolve('owned'), calls = [];
  await main(['terminal', root], { execPath: path.join(root, 'Runtime/node/node.exe'),
    preflight() { calls.push('preflight'); }, runtime: {
      identity() { calls.push('identity'); }, main(args) { calls.push(args); }
    } });
  assert.deepEqual(calls, ['identity', 'preflight', ['terminal', root]]);
});
test('exFAT consent requires exact arguments and does not preflight or boot', async () => {
  const root = path.resolve('owned'); let enabled = 0;
  const deps = { execPath: path.join(root, 'Runtime/node/node.exe'), preflight() { throw Error('forbidden'); },
    print() {}, storage: { enable(r, options) { assert.equal(r, root); assert.deepEqual(options, { acknowledged: true }); enabled++; return {schema:1,storageMode:'exfat-reduced-protection'}; } } };
  for (const args of [['enable-exfat', root], ['enable-exfat', root, 'yes'], ['enable-exfat', root, '--accept-unprotected-storage', 'extra'], ['terminal', root, 'extra']])
    await assert.rejects(main(args, deps), /Invalid/);
  assert.equal(await main(['enable-exfat', root, '--accept-unprotected-storage'], deps), 0);
  assert.equal(enabled, 1);
});

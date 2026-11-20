'use strict';
const { downloadHttp } = require('./acquire.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { verifyBytes, archivePathGuard, guardListing, acquireArtifact } = require('./acquire.cjs');

test('resumed owned partial is published only after the whole pinned hash matches', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'sandbox-resume-test-'));
  const body = Buffer.from('prefix-and-complete-body');
  const spec = { name: 'public.bin', url: 'https://example.invalid/public.bin', algorithm: 'sha256',
    digest: crypto.createHash('sha256').update(body).digest('hex'), cap: 100 };
  const partial = path.join(directory, 'public.bin.11111111-1111-1111-1111-111111111111.partial');
  await fs.writeFile(partial, body.subarray(0, 7));
  const result = await acquireArtifact(spec, directory, undefined, { resume: true,
    resumeTransport: async ({ handle }) => { const offset = (await handle.stat()).size; await handle.write(body, offset, body.length - offset, offset); } });
  assert.equal(result.resumed, true);
  assert.deepEqual(await fs.readFile(result.file), body);
  const wrong = { ...spec, name: 'wrong.bin' };
  await fs.writeFile(path.join(directory, 'wrong.bin.22222222-2222-2222-2222-222222222222.partial'), 'corrupt');
  await assert.rejects(acquireArtifact(wrong, directory, undefined, { resume: true,
    resumeTransport: async ({ handle }) => { const offset = (await handle.stat()).size; await handle.write(body, offset, body.length - offset, offset); } }), /digest mismatch/);
  await assert.rejects(fs.stat(path.join(directory, 'wrong.bin')), { code: 'ENOENT' });
  // Keep these tiny owned test artifacts; never delete an unchecked computed tree.
});
test('pinned bytes fail closed', () => {
  const digest = crypto.createHash('sha256').update('good').digest('hex');
  assert.equal(verifyBytes(Buffer.from('good'), 'sha256', digest), digest);
  assert.throws(() => verifyBytes(Buffer.from('bad'), 'sha256', digest));
});
test('archive paths and links are contained; header ignored', () => {
  for (const p of ['../x', 'a/../x', 'C:\\x', '\\\\host\\x', '/x', 'x:stream', 'NUL.txt', 'x.']) assert.throws(() => archivePathGuard(p), p);
  assert.equal(archivePathGuard('$PLUGINSDIR/file.dll'), '$PLUGINSDIR/file.dll');
  guardListing('Path = C:\\archive.exe\n----------\nPath = bin/qemu.exe\nSize = 2\n');
  assert.throws(() => guardListing('----------\nPath = x\nSymbolic Link = target\n'));
});
test('failed requests never publish missing artifacts or reuse stale artifacts', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'ghostty-acquire-test-'));
  const spec = { name: 'artifact', url: 'https://invalid.example/', algorithm: 'sha256', digest: crypto.createHash('sha256').update('good').digest('hex'), cap: 100 };
  let calls = 0;
  const broken = async (_url, handle) => { calls++; await handle.writeFile('bad'); throw new Error('request failed'); };
  await assert.rejects(acquireArtifact(spec, root, broken), /request failed/);
  await assert.rejects(fs.stat(path.join(root, spec.name)), { code: 'ENOENT' });
  await fs.writeFile(path.join(root, spec.name), 'stale', { flag: 'wx' });
  await assert.rejects(acquireArtifact(spec, root, broken), /Invalid cached/);
  assert.equal(calls, 1);
  assert.equal(await fs.readFile(path.join(root, spec.name), 'utf8'), 'stale');
});
test('matching cache is explicitly recorded without a request', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'ghostty-acquire-test-'));
  const spec = { name: 'artifact', algorithm: 'sha256', digest: crypto.createHash('sha256').update('good').digest('hex'), cap: 100 };
  await fs.writeFile(path.join(root, spec.name), 'good', { flag: 'wx' });
  const result = await acquireArtifact(spec, root, () => { throw new Error('must not fetch'); });
  assert.equal(result.reused, true);
});
test('connection before socket creation and body stalls have wall-clock deadlines', async () => {
  const sink = { writeFile: async () => {} };
  await assert.rejects(downloadHttp('https://example.invalid/file', sink, 100, {
    timeoutMs: 15, fetchImpl: () => new Promise(() => {}),
  }), /stalled/);
  const response = { status: 200, body: { getReader: () => ({ read: () => new Promise(() => {}), cancel: async () => {} }) } };
  await assert.rejects(downloadHttp('https://example.invalid/file', sink, 100, {
    timeoutMs: 15, fetchImpl: async () => response,
  }), /stalled/);
});

'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { resumeDownload } = require('./range-download.cjs');
function file(seed = '') {
  return { data: Buffer.from(seed), async stat() { return { size: this.data.length }; },
    async write(b, offset, length, position) {
      assert.ok(position <= this.data.length, 'no holes');
      const next = Buffer.alloc(Math.max(this.data.length, position + length));
      this.data.copy(next); b.copy(next, position, offset, offset + length); this.data = next;
      return { bytesWritten: length };
    } };
}
const url = 'https://example.invalid/resource';
function ranged(source, calls) {
  return async (_, options) => {
    calls.push(options.headers.Range);
    const [start, end] = options.headers.Range.match(/\d+/g).map(Number);
    const last = Math.min(end, source.length - 1);
    return new Response(source.slice(start, last + 1), { status: 206,
      headers: { 'content-range': `bytes ${start}-${last}/${source.length}` } });
  };
}
test('seeded prefix resumes at absolute positions without claiming integrity', async () => {
  const handle = file('ab'), calls = [];
  const result = await resumeDownload({ url, handle, cap: 6, chunkBytes: 2, fetchImpl: ranged('abcdef', calls) });
  assert.equal(handle.data.toString(), 'abcdef');
  assert.deepEqual(calls, ['bytes=2-3', 'bytes=4-5']);
  assert.equal(result.resumedFrom, 2); assert.equal(result.verified, undefined);
});
test('corrupt existing prefix is not represented as verified', async () => {
  const handle = file('XX');
  const result = await resumeDownload({ url, handle, cap: 6, fetchImpl: ranged('abcdef', []) });
  assert.equal(handle.data.toString(), 'XXcdef'); assert.equal(result.verified, undefined);
});
for (const [name, response] of [
  ['range ignored', () => new Response('abcdef')],
  ['range gap', () => new Response('def', { status: 206, headers: { 'content-range': 'bytes 3-5/6' } })],
  ['oversize', () => new Response('cdef', { status: 206, headers: { 'content-range': 'bytes 2-5/99' } })],
]) test(name + ' preserves prefix and stops', async () => {
  const handle = file('ab'); let calls = 0;
  await assert.rejects(resumeDownload({ url, handle, cap: 6, fetchImpl: async () => { calls++; return response(); } }));
  assert.equal(calls, 3); assert.equal(handle.data.toString(), 'ab');
});
test('stream abort checkpoints actual bytes then resumes', async () => {
  const handle = file(); const calls = []; let first = true;
  const fetchImpl = async (...args) => {
    if (!first) return ranged('abcdef', calls)(...args);
    first = false;
    let reads = 0;
    return new Response(new ReadableStream({ pull(c) {
      if (reads++ === 0) c.enqueue(Buffer.from('ab')); else c.error(new Error('interrupted'));
    } }), { status: 206, headers: { 'content-range': 'bytes 0-5/6' } });
  };
  await resumeDownload({ url, handle, cap: 6, fetchImpl });
  assert.equal(handle.data.toString(), 'abcdef'); assert.deepEqual(calls, ['bytes=2-5']);
});
test('injected DNS/header stall has wall-clock timeout and finite retries', async () => {
  let calls = 0;
  const start = Date.now();
  await assert.rejects(resumeDownload({ url, handle: file(), cap: 6, timeoutMs: 15,
    fetchImpl: () => { calls++; return new Promise(() => {}); } }));
  assert.equal(calls, 3); assert.ok(Date.now() - start < 2000);
});
test('body stall resumes partial bytes on request deadline', async () => {
  let first = true; const handle = file();
  await resumeDownload({ url, handle, cap: 6, timeoutMs: 20, fetchImpl: async (...args) => {
    if (!first) return ranged('abcdef', [])(...args);
    first = false;
    return new Response(new ReadableStream({ start(c) { c.enqueue(Buffer.from('ab')); } }),
      { status: 206, headers: { 'content-range': 'bytes 0-5/6' } });
  } });
  assert.equal(handle.data.toString(), 'abcdef');
});
test('plaintext redirects never fetched', async () => {
  let calls = 0;
  await assert.rejects(resumeDownload({ url, handle: file(), cap: 6, fetchImpl: async () => {
    calls++; return new Response(null, { status: 302, headers: { location: 'http://example.invalid/' } });
  } }));
  assert.equal(calls, 3);
});
test('extra bytes after expected body are rejected even after final byte checkpoint', async () => {
  let reads = 0;
  await assert.rejects(resumeDownload({ url, handle: file(), cap: 2, fetchImpl: async () =>
    new Response(new ReadableStream({ pull(c) {
      if (reads++ === 0) c.enqueue(Buffer.from('ab'));
      else c.enqueue(Buffer.from('x'));
    } }), { status: 206, headers: { 'content-range': 'bytes 0-1/2' } }) }));
});
test('initial full response requires bounded consistent length', async () => {
  const handle = file();
  await resumeDownload({ url, handle, cap: 6, fetchImpl: async () =>
    new Response('abcdef', { headers: { 'content-length': '6' } }) });
  assert.equal(handle.data.toString(), 'abcdef');
  await assert.rejects(resumeDownload({ url, handle: file(), cap: 6,
    fetchImpl: async () => new Response('abcdef') }));
});
test('truncated chunk resumes at checkpoint and length mismatch never writes', async () => {
  const handle = file(); let first = true;
  await resumeDownload({ url, handle, cap: 6, fetchImpl: async (...args) => {
    if (!first) return ranged('abcdef', [])(...args);
    first = false;
    return new Response('ab', { status: 206, headers: { 'content-range': 'bytes 0-5/6' } });
  } });
  assert.equal(handle.data.toString(), 'abcdef');
  const other = file();
  await assert.rejects(resumeDownload({ url, handle: other, cap: 6, fetchImpl: async () =>
    new Response('abcdef', { status: 206, headers: { 'content-range': 'bytes 0-5/6', 'content-length': '5' } }) }));
  assert.equal(other.data.length, 0);
});
test('tiny ongoing progress cannot evade overall episode deadline', async () => {
  const handle = file();
  await assert.rejects(resumeDownload({ url, handle, cap: 10000, timeoutMs: 15, maxElapsedMs: 45,
    fetchImpl: async (_, options) => {
      const start = Number(options.headers.Range.match(/\d+/)[0]);
      return new Response(new ReadableStream({ start(c) { c.enqueue(Buffer.from('a')); } }),
        { status: 206, headers: { 'content-range': `bytes ${start}-9999/10000` } });
    } }), /episode deadline/);
  assert.ok(handle.data.length > 0 && handle.data.length < 10000);
});

'use strict';

// Transport only: callers MUST verify the whole pinned digest before publication.
function secureUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password) throw new Error('HTTPS without URL credentials required');
  return url.href;
}

async function resumeDownload({ url, handle, cap, fetchImpl = globalThis.fetch,
  chunkBytes = 2 * 1024 ** 2, timeoutMs = 90000, maxFailures = 3,
  maxElapsedMs = 30 * 60 * 1000, onProgress }) {
  url = secureUrl(url);
  for (const n of [cap, chunkBytes, timeoutMs, maxFailures, maxElapsedMs]) {
    if (!Number.isSafeInteger(n) || n <= 0) throw new Error('Positive safe integer limits required');
  }
  let bytes = (await handle.stat()).size;
  const resumedFrom = bytes;
  if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > cap) throw new Error('Partial exceeds size cap');
  let total, requests = 0, failures = 0;
  const episodeEnd = Date.now() + maxElapsedMs;
  // Even a complete partial must obtain the remote length; integrity is external.
  while (total === undefined || bytes < total) {
    const before = bytes;
    const controller = new AbortController();
    const remaining = Math.min(timeoutMs, episodeEnd - Date.now());
    if (remaining <= 0) throw new Error('Download episode deadline exceeded');
    let timer, reader, response;
    const deadline = new Promise((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new Error('Download request deadline exceeded'));
      }, remaining);
    });
    const bounded = promise => Promise.race([promise, deadline]);
    try {
      const end = Math.min(bytes + chunkBytes, total ?? cap) - 1;
      let target = url;
      for (let redirects = 0; ; redirects++) {
        requests++;
        response = await bounded(Promise.resolve().then(() => fetchImpl(target, {
          headers: { Range: `bytes=${bytes}-${end}`, 'Accept-Encoding': 'identity' },
          redirect: 'manual', signal: controller.signal,
        })));
        if (![301, 302, 303, 307, 308].includes(response.status)) break;
        if (response.body) void response.body.cancel().catch(() => {});
        if (redirects >= 8) throw new Error('Redirect limit exceeded');
        const location = response.headers.get('location');
        if (!location) throw new Error('Missing redirect location');
        target = secureUrl(new URL(location, target).href);
      }
      let expected;
      const lengthText = response.headers.get('content-length');
      const length = lengthText === null ? undefined : /^\d+$/.test(lengthText) ? Number(lengthText) : NaN;
      const encoding = response.headers.get('content-encoding');
      if (encoding && encoding !== 'identity') throw new Error('Encoded response rejected');
      if (response.status === 206) {
        const match = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get('content-range') || '');
        if (!match) throw new Error('Invalid Content-Range');
        const [start, last, size] = match.slice(1).map(Number);
        if (![start, last, size].every(Number.isSafeInteger) || start !== bytes ||
            size > cap || size <= last || last < start || last !== Math.min(end, size - 1) ||
            (total !== undefined && total !== size)) throw new Error('Inconsistent Content-Range');
        total = size;
        expected = last - start + 1;
      } else if (response.status === 200 && bytes === 0) {
        if (!Number.isSafeInteger(length) || length < 0 || length > cap ||
            (total !== undefined && length !== total)) throw new Error('Known bounded length required');
        total = length;
        expected = length;
      } else {
        throw new Error('Unexpected HTTP status for range');
      }
      if (length !== undefined && (!Number.isSafeInteger(length) || length !== expected)) throw new Error('Inconsistent Content-Length');
      if (!response.body) throw new Error('Missing response body');
      reader = response.body.getReader();
      let received = 0;
      for (;;) {
        const { done, value } = await bounded(reader.read());
        if (done) break;
        const buffer = Buffer.from(value);
        if (buffer.length > expected - received) throw new Error('Response exceeds declared range');
        let written = 0;
        while (written < buffer.length) {
          const result = await handle.write(buffer, written, buffer.length - written, bytes);
          if (!Number.isSafeInteger(result.bytesWritten) || result.bytesWritten <= 0 || result.bytesWritten > buffer.length - written) throw new Error('Invalid file write');
          written += result.bytesWritten;
          bytes += result.bytesWritten;
        }
        received += buffer.length;
      }
      if (received !== expected) throw new Error('Truncated response');
    } catch (_) {
      // Never expose signed URLs or provider error strings to callers/logs.
      bytes = (await handle.stat()).size;
      if (total !== undefined && bytes >= total) throw new Error('Response did not finish cleanly');
      if (bytes === before) failures++;
      else failures = 0;
      if (failures >= maxFailures) throw new Error('Download stopped after consecutive zero-progress failures');
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) void reader.cancel().catch(() => {});
      else if (response?.body) void response.body.cancel().catch(() => {});
    }
    bytes = (await handle.stat()).size;
    if (bytes > cap || (total !== undefined && bytes > total)) throw new Error('Partial exceeds declared size');
    if (bytes > before) failures = 0;
    if (onProgress) onProgress({ bytes, total, requests, resumedFrom });
  }
  return { bytes, total, requests, resumedFrom };
}

module.exports = { resumeDownload };

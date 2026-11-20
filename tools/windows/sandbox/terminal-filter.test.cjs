'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { TerminalFilter } = require('./terminal-filter.cjs');
async function filter(chunks) {
  const f = new TerminalFilter(); const out = []; f.on('data', b => out.push(b));
  for (const b of chunks) f.write(b); f.end(); await new Promise(resolve => f.on('end', resolve));
  return Buffer.concat(out).toString();
}
test('guest clipboard query/write is removed across arbitrary chunk boundaries', async () => {
  assert.equal(await filter(['text\x1b]5', '2;c;secret', '\x07tail']), 'texttail');
  assert.equal(await filter(['a\x1b]00052;c;?', '\x1b', '\\b']), 'ab');
  assert.equal(await filter(['a\x1b]52;c;', 'x'.repeat(1024 * 1024), '\x07z']), 'az');
  assert.equal(await filter(['a\x1b]52;c;unfinished']), 'a');
});
test('guest file hyperlinks are not reflected into clickable host paths', async () => {
  assert.equal(await filter(['\x1b]8;;file:///C:/Users/user\x1b\\label\x1b]8;;\x1b\\']), 'label');
});
test('normal UTF-8 and TUI cursor/colour/title sequences survive', async () => {
  const value = 'ทดสอบ\x1b[31mred\x1b[0m\x1b]0;guest title\x07';
  assert.equal(await filter([Buffer.from(value)]), value);
});

test('Kitty host-file/temp-file requests and passthrough payloads are discarded', async () => {
  assert.equal(await filter(['a\x1b_Gt=f;L3ByaXZhdGUvaG9zdC5wbmc=\x1b', '\\b']), 'ab');
  assert.equal(await filter(['a\x1bPtmux;\x1b\x1b]52;c;data\x07\x1b\\b']), 'ab');
  assert.equal(await filter(['a\x1b]1337;CopyToClipboard=data\x07b']), 'ab');
});

test('nested ESC strings inside an allowed OSC cannot reopen host channels', async () => {
  for (const opener of ['\x1b]52;c;clipboard', '\x1b_Gt=f;hostfile', '\x1bPtmux;payload']) {
    const end = opener.startsWith('\x1b]') ? '\x07' : '\x1b\\';
    const payload = Buffer.from('a\x1b]0;title' + opener + end + 'z');
    for (let split = 0; split <= payload.length; split++) {
      assert.equal(await filter([payload.subarray(0, split), payload.subarray(split)]), 'a\x1b]0;title\x1b\\z');
    }
  }
});

test('raw and encoded C1 strings cannot reach host channels', async () => {
  for (const encoded of [false, true]) {
    const c = n => Buffer.from(encoded ? [0xc2, n] : [n]);
    for (const end of [c(0x9c), Buffer.from('\x1b\\'), Buffer.from('\x07')]) {
      const value = Buffer.concat([Buffer.from('a'), c(0x9d), Buffer.from('52;c;secret'), end, Buffer.from('z')]);
      assert.equal(await filter([...value].map(b => Buffer.from([b]))), 'az');
    }
    for (const start of [0x90, 0x98, 0x9e, 0x9f]) {
      for (const transmission of ['f', 't']) {
        const value = Buffer.concat([Buffer.from('a'), c(start), Buffer.from(`Gt=${transmission};secret`), c(0x9c), Buffer.from('z')]);
        assert.equal(await filter([...value].map(b => Buffer.from([b]))), 'az');
      }
    }
  }
});

test('UTF-8 continuation bytes remain text across 100-byte and single-byte chunks', async () => {
  const text = 'ไทยทดสอบ😀🚀🌞'.repeat(100);
  const bytes = Buffer.from(text);
  for (const size of [1, 100]) {
    const chunks = [];
    for (let i = 0; i < bytes.length; i += size) chunks.push(bytes.subarray(i, i + size));
    assert.equal(await filter(chunks), text);
  }
});

test('C1 CSI normalizes; other controls and malformed UTF-8 fail closed', async () => {
  assert.equal(await filter([Buffer.from([0x9b, 0x33, 0x31, 0x6d, 0xc2, 0x9b, 0x30, 0x6d, 0x85])]), '\x1b[31m\x1b[0m');
  assert.equal(await filter([Buffer.from([0xe0, 0x9d]), Buffer.from('52;c;secret\x07z')]), 'z');
  assert.equal(await filter([Buffer.from([0xf0, 0x9f])]), '');
});

test('C1 ST terminates seven-bit strings and allowed title/font framing survives', async () => {
  for (const st of [Buffer.from([0x9c]), Buffer.from([0xc2, 0x9c])]) {
    for (const start of ['\x1b]52;c;secret', '\x1bPsecret', '\x1b_secret']) {
      assert.equal(await filter([Buffer.from(start), st.subarray(0, 1), st.subarray(1), Buffer.from('tail')]), 'tail');
    }
    assert.equal(await filter([Buffer.from('\x1b]0;title'), st]), '\x1b]0;title\x1b\\');
  }
  const font = '\x1b]50;monospace\x1b\\';
  assert.equal(await filter([font]), font);
  for (const start of [0x9d, 0x90, 0x98, 0x9e, 0x9f]) {
    assert.equal(await filter([Buffer.from([start]), Buffer.from('52;unfinished')]), '');
  }
});

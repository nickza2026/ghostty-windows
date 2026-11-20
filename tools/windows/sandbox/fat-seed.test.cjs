'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createSeed } = require('./fat-seed.cjs');

// Independent byte-level inspection, not a production reader/roundtrip API.
function inspect(image) {
  assert.equal(image.length, 1474560);
  assert.equal(image.readUInt16LE(11), 512);
  assert.equal(image[13], 1); assert.equal(image.readUInt16LE(14), 1);
  assert.equal(image[16], 2); assert.equal(image.readUInt16LE(17), 224);
  assert.equal(image.readUInt16LE(19), 2880); assert.equal(image[21], 0xf0);
  assert.equal(image.readUInt16LE(22), 9);
  assert.equal(image.readUInt16LE(24), 18); assert.equal(image.readUInt16LE(26), 2);
  assert.equal(image.readUInt32LE(28), 0); assert.equal(image[38], 0x29);
  assert.equal(image.subarray(43, 54).toString(), 'CIDATA     ');
  assert.equal(image.subarray(54, 62).toString(), 'FAT12   ');
  assert.deepEqual([...image.subarray(510, 512)], [0x55, 0xaa]);
  assert.deepEqual(image.subarray(512, 5120), image.subarray(5120, 9728));
  assert.deepEqual([...image.subarray(512, 515)], [0xf0, 0xff, 0xff]);
  assert.equal(image.subarray(9728, 9739).toString(), 'CIDATA     ');
  assert.equal(image[9739], 8);
  const result = new Map(), used = new Set();
  let pending = [], total = 0;
  for (let slot = 1; slot < 224; slot++) {
    const e = image.subarray(9728 + slot * 32, 9760 + slot * 32);
    if (!e[0]) break;
    if (e[11] === 15) { pending.push(e); continue; }
    assert.equal(e[11], 32); assert.equal(e.readUInt16LE(24), 0x21);
    let sum = 0;
    for (let i = 0; i < 11; i++) sum = ((sum >>> 1) | ((sum & 1) * 128)) + e[i] & 255;
    assert.ok(pending.length > 0);
    assert.equal(pending[0][0], 0x40 | pending.length);
    let units = [];
    pending.forEach((lfn, i) => {
      assert.equal(lfn[0], (pending.length - i) | (i === 0 ? 0x40 : 0));
      assert.equal(lfn[12], 0); assert.equal(lfn[13], sum); assert.equal(lfn.readUInt16LE(26), 0);
    });
    for (const lfn of pending.reverse()) for (const offset of [1,3,5,7,9,14,16,18,20,22,24,28,30]) units.push(lfn.readUInt16LE(offset));
    const end = units.indexOf(0);
    if (end >= 0) { assert.ok(units.slice(end + 1).every(x => x === 0xffff)); units = units.slice(0, end); }
    else assert.ok(units.every(x => x !== 0xffff));
    const name = String.fromCharCode(...units);
    pending = [];
    let n = e.readUInt16LE(26), size = e.readUInt32LE(28), chunks = [];
    if (!size) assert.equal(n, 0);
    while (n) {
      assert.ok(n >= 2 && n <= 2848); assert.ok(!used.has(n)); used.add(n); total++;
      chunks.push(image.subarray(16896 + (n - 2) * 512, 17408 + (n - 2) * 512));
      const word = image.readUInt16LE(512 + Math.floor(n * 1.5));
      const next = n % 2 ? word >>> 4 : word & 0xfff;
      if (next >= 0xff8) break;
      n = next; assert.notEqual(n, 0);
    }
    assert.equal(chunks.length, Math.ceil(size / 512));
    result.set(name, Buffer.concat(chunks).subarray(0, size));
  }
  assert.equal(pending.length, 0);
  return { files: result, total };
}

test('BPB, labels, exact LFNs, checksums, UTF-16 and odd/even FAT chains', () => {
  const files = { 'user-data': '#cloud-config\n', 'meta-data': 'instance-id: seed\n',
    'network-config': Buffer.alloc(1537, 0xa5), 'NET4.TXT': 'ipv4', 'NET6.TXT': 'ipv6',
    'BOOTID.TXT': 'boot', 'MiXeD.txt': '', 'abcdefghijklm': '13 units', 'é😀.txt': 'Unicode' };
  const parsed = inspect(createSeed(files));
  assert.deepEqual([...parsed.files.keys()], Object.keys(files));
  for (const [name, value] of Object.entries(files)) assert.deepEqual(parsed.files.get(name), Buffer.from(value));
});

test('empty volume and full data area', () => {
  assert.equal(inspect(createSeed({})).files.size, 0);
  const payload = Buffer.alloc(2847 * 512, 0x73);
  const parsed = inspect(createSeed({ full: payload }));
  assert.equal(parsed.total, 2847); assert.deepEqual(parsed.files.get('full'), payload);
  assert.throws(() => createSeed({ full: Buffer.alloc(payload.length + 1) }));
  assert.throws(() => createSeed({ full: payload, extra: 'x' }));
});

test('short aliases do not shadow logical filenames', () => {
  const image = createSeed({ other: 'a', 'F0000001.DAT': 'b' });
  assert.equal(image.subarray(9728 + 64, 9728 + 75).toString(), 'F0000002DAT');
  assert.deepEqual([...inspect(image).files.keys()], ['other', 'F0000001.DAT']);
});

test('directory and filename length boundaries', () => {
  inspect(createSeed({ ['a'.repeat(255)]: '' }));
  assert.throws(() => createSeed({ ['a'.repeat(256)]: '' }));
  const files = Object.fromEntries(Array.from({ length: 111 }, (_, i) => [`f${i}`, '']));
  assert.equal(inspect(createSeed(files)).files.size, 111);
  assert.throws(() => createSeed({ ...files, extra: '' }));
});

test('reject unsafe names, collisions, malformed input and content types', () => {
  for (const name of ['', '.', '..', 'a..b', '/abs', 'C:abs', 'a/b', 'a\\b', 'x\0y', 'x\ny', 'end.', 'end ', 'a*', '\ud800']) {
    assert.throws(() => createSeed({ [name]: '' }), name);
  }
  assert.throws(() => createSeed({ 'user-data': '', 'USER-DATA': '' }));
  assert.throws(() => createSeed({ cidata: '' }));
  for (const value of [null, [], 'text', 4, new Date()]) assert.throws(() => createSeed(value));
  for (const value of [null, 3, {}, new Uint8Array(2)]) assert.throws(() => createSeed({ file: value }));
  assert.throws(() => createSeed({ [Symbol('file')]: '' }));
});

'use strict';

// A superfloppy FAT12 volume: 1 reserved + 18 FAT + 14 root + 2847 data sectors.
const SECTOR = 512, SECTORS = 2880, ROOT = 19 * SECTOR;
const DATA = 33 * SECTOR, CLUSTERS = 2847;

function createSeed(filesObject) {
  if (!filesObject || typeof filesObject !== 'object' || Array.isArray(filesObject) ||
      (Object.getPrototypeOf(filesObject) !== Object.prototype && Object.getPrototypeOf(filesObject) !== null) ||
      Reflect.ownKeys(filesObject).some(k => typeof k !== 'string')) {
    throw new TypeError('Expected a plain filename-to-content object');
  }
  const seen = new Set();
  const logicalNames = new Set(Object.keys(filesObject).map(name => name.toUpperCase()));
  let aliasNumber = 0;
  let records = 1, clusters = 0;
  const files = Object.entries(filesObject).map(([name, value]) => {
    if (!name || name.length > 255 || name === '.' || name.includes('..') ||
        /[\x00-\x1f\x7f"*\/:<>?\\|]/.test(name) || /[. ]$/.test(name)) {
      throw new Error('Invalid FAT filename');
    }
    // Reject unpaired surrogates rather than emitting invalid UTF-16 LFNs.
    for (let i = 0; i < name.length; i++) {
      const c = name.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        const next = name.charCodeAt(++i);
        if (!(next >= 0xdc00 && next <= 0xdfff)) throw new Error('Invalid UTF-16 filename');
      } else if (c >= 0xdc00 && c <= 0xdfff) throw new Error('Invalid UTF-16 filename');
    }
    const key = name.toUpperCase();
    if (seen.has(key) || key === 'CIDATA') throw new Error('Duplicate/reserved filename');
    seen.add(key);
    if (typeof value !== 'string' && !Buffer.isBuffer(value)) throw new TypeError('Content must be UTF-8 text or Buffer');
    const size = typeof value === 'string' ? Buffer.byteLength(value) : value.length;
    if (size > CLUSTERS * SECTOR) throw new Error('Seed data exceeds capacity');
    const count = Math.ceil(size / SECTOR), lfnCount = Math.ceil(name.length / 13);
    records += lfnCount + 1;
    clusters += count;
    if (records > 224 || clusters > CLUSTERS) throw new Error('Seed directory/data exceeds capacity');
    // Always use an LFN, preserving exact spelling even for nominal 8.3 names.
    let stem;
    do { stem = `F${String(++aliasNumber).padStart(7, '0')}`; }
    while (logicalNames.has(`${stem}.DAT`));
    const alias = Buffer.from(`${stem}DAT`, 'ascii');
    return { name, value, size, count, lfnCount, alias };
  });
  const image = Buffer.alloc(SECTOR * SECTORS);
  image.set([0xeb, 0x3c, 0x90]); image.write('MSDOS5.0', 3, 'ascii');
  image.writeUInt16LE(SECTOR, 11); image[13] = 1; image.writeUInt16LE(1, 14);
  image[16] = 2; image.writeUInt16LE(224, 17); image.writeUInt16LE(SECTORS, 19);
  image[21] = 0xf0; image.writeUInt16LE(9, 22); image.writeUInt16LE(18, 24);
  image.writeUInt16LE(2, 26); image[38] = 0x29; image.writeUInt32LE(0x43494441, 39);
  image.write('CIDATA     ', 43, 'ascii'); image.write('FAT12   ', 54, 'ascii');
  image[510] = 0x55; image[511] = 0xaa;
  const fat = image.subarray(SECTOR, SECTOR * 10);
  fat.set([0xf0, 0xff, 0xff]);
  function setFat(n, value) {
    const offset = Math.floor(n * 3 / 2);
    if (n & 1) { fat[offset] = (fat[offset] & 15) | ((value & 15) << 4); fat[offset + 1] = value >> 4; }
    else { fat[offset] = value & 255; fat[offset + 1] = (fat[offset + 1] & 240) | (value >> 8); }
  }
  function stamp(entry) {
    // 1980-01-01, midnight (a valid FAT date).
    entry.writeUInt16LE(0x21, 16); entry.writeUInt16LE(0x21, 18); entry.writeUInt16LE(0x21, 24);
  }
  const volume = image.subarray(ROOT, ROOT + 32);
  volume.write('CIDATA     ', 0, 'ascii'); volume[11] = 8; stamp(volume);
  let slot = 1, cluster = 2;
  for (const file of files) {
    let checksum = 0;
    for (const b of file.alias) checksum = (((checksum & 1) << 7) + (checksum >> 1) + b) & 255;
    for (let seq = file.lfnCount; seq >= 1; seq--) {
      const entry = image.subarray(ROOT + slot++ * 32, ROOT + slot * 32);
      entry.fill(0xff); entry[0] = seq | (seq === file.lfnCount ? 0x40 : 0);
      entry[11] = 0x0f; entry[12] = 0; entry[13] = checksum; entry.writeUInt16LE(0, 26);
      const positions = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30];
      positions.forEach((offset, j) => {
        const i = (seq - 1) * 13 + j;
        entry.writeUInt16LE(i < file.name.length ? file.name.charCodeAt(i) : i === file.name.length ? 0 : 0xffff, offset);
      });
    }
    const entry = image.subarray(ROOT + slot++ * 32, ROOT + slot * 32);
    file.alias.copy(entry); entry[11] = 0x20; stamp(entry);
    entry.writeUInt16LE(file.count ? cluster : 0, 26); entry.writeUInt32LE(file.size, 28);
    if (file.count) {
      const content = Buffer.isBuffer(file.value) ? file.value : Buffer.from(file.value, 'utf8');
      content.copy(image, DATA + (cluster - 2) * SECTOR);
      for (let i = 0; i < file.count; i++, cluster++) setFat(cluster, i === file.count - 1 ? 0xfff : cluster + 1);
    }
  }
  fat.copy(image, 10 * SECTOR);
  return image;
}

module.exports = { createSeed };

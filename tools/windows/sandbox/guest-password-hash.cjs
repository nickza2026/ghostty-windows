'use strict';

const { createHash } = require('node:crypto');
const alphabet = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

function validHash(value) {
  if (typeof value !== 'string') return false;
  const match = /^\$6\$(?:rounds=([1-9][0-9]*)\$)?([./A-Za-z0-9]{1,16})\$([./A-Za-z0-9]{86})(?![\s\S])/.exec(value);
  if (!match || (match[1] && (!Number.isSafeInteger(Number(match[1])) || Number(match[1]) < 5000 || Number(match[1]) > 1000000))) return false;
  // Only two significant bits remain in the final crypt-base64 character.
  return alphabet.indexOf(match[3][85]) < 4;
}

function sha512crypt(passwordBuffer, salt, rounds = 100000) {
  if (!Buffer.isBuffer(passwordBuffer) || passwordBuffer.length > 1024 || passwordBuffer.includes(0)) throw new TypeError('Invalid password buffer');
  if (typeof salt !== 'string' || !/^[./A-Za-z0-9]{1,16}(?![\s\S])/.test(salt)) throw new TypeError('Invalid salt');
  if (!Number.isInteger(rounds) || rounds < 5000 || rounds > 1000000) throw new RangeError('Invalid rounds');
  const owned = new Set();
  const keep = (buffer) => { owned.add(buffer); return buffer; };
  const wipe = (buffer) => { buffer.fill(0); owned.delete(buffer); };
  const digest = (...parts) => {
    const hash = createHash('sha512');
    for (const part of parts) hash.update(part);
    return keep(hash.digest());
  };
  const repeated = (source, length) => {
    const result = keep(Buffer.alloc(length));
    for (let offset = 0; offset < length; offset += source.length) source.copy(result, offset, 0, Math.min(source.length, length - offset));
    return result;
  };
  try {
    const password = keep(Buffer.from(passwordBuffer));
    const saltBytes = keep(Buffer.from(salt, 'ascii'));
    const alternate = digest(password, saltBytes, password);
    const initial = createHash('sha512').update(password).update(saltBytes);
    for (let left = password.length; left > 0; left -= 64) initial.update(alternate.subarray(0, Math.min(left, 64)));
    for (let bits = password.length; bits > 0; bits = Math.floor(bits / 2)) initial.update(bits & 1 ? alternate : password);
    let current = keep(initial.digest());
    wipe(alternate);
    const pHash = createHash('sha512');
    for (let i = 0; i < password.length; i++) pHash.update(password);
    const pDigest = keep(pHash.digest());
    const p = repeated(pDigest, password.length);
    wipe(pDigest);
    const sHash = createHash('sha512');
    for (let i = 0; i < 16 + current[0]; i++) sHash.update(saltBytes);
    const sDigest = keep(sHash.digest());
    const s = repeated(sDigest, saltBytes.length);
    wipe(sDigest);
    for (let i = 0; i < rounds; i++) {
      const hash = createHash('sha512');
      hash.update(i & 1 ? p : current);
      if (i % 3 !== 0) hash.update(s);
      if (i % 7 !== 0) hash.update(p);
      hash.update(i & 1 ? current : p);
      const next = keep(hash.digest());
      wipe(current);
      current = next;
    }
    let encoded = '';
    const encode = (a, b, c, count) => {
      let word = (a << 16) | (b << 8) | c;
      for (let i = 0; i < count; i++) { encoded += alphabet[word & 63]; word >>>= 6; }
    };
    for (let i = 0; i < 21; i++) {
      const a = (i * 22) % 63;
      encode(current[a], current[(a + 21) % 63], current[(a + 42) % 63], 4);
    }
    encode(0, 0, current[63], 2);
    return `$6$rounds=${rounds}$${salt}$${encoded}`;
  } finally {
    // Best effort for owned Buffers only; V8/OpenSSL internal copies and the
    // returned immutable hash string cannot be guaranteed securely erased.
    for (const buffer of owned) buffer.fill(0);
  }
}

module.exports = { sha512crypt, validHash };

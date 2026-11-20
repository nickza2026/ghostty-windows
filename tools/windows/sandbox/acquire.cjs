'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { resumeDownload } = require('./range-download.cjs');
const MiB = 1024 * 1024;
const sources = [
  ['7zr.exe', 'https://github.com/ip7z/7zip/releases/download/26.06/7zr.exe', 'sha256', 'e80db2dad715a6c5adabe292d31ed54e11f4e9b99ca349827b50573b175891bc', 4],
  ['7z2606-x64.exe', 'https://github.com/ip7z/7zip/releases/download/26.06/7z2606-x64.exe', 'sha256', '9b697f65ecc2d9b0152f5ee96d72dde522a7827690349d9307935dacf40f42ec', 4],
  ['qemu-w64-setup-20260811.exe', 'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.exe', 'sha512', '5bcf9eed634e8575a37b74f445af41a2fe4106da512d0c30c368301d4c105037fdfab40a5287367a28a957624cddebbc8c07e16c88ab6634f554cdf3d16bf543', 260],
  ['debian.qcow2', 'https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2', 'sha512', 'ec8c175e39d59e711798c3a2f22ba11b9aee9bca1887c7e505a800aeffd5d7616099bd0e9fad869efba96100fe09d2c8b49d6d7001d501f0056c556bdc25b605', 650],
].map(([name, url, algorithm, digest, cap]) => ({ name, url, algorithm, digest, cap: cap * MiB }));
function verifyBytes(bytes, algorithm, expected) {
  const actual = crypto.createHash(algorithm).update(bytes).digest('hex');
  if (actual !== expected) throw new Error('Pinned digest mismatch');
  return actual;
}
async function hashFile(file, algorithm = 'sha256') {
  const hash = crypto.createHash(algorithm);
  const handle = await fs.open(file, 'r');
  try { for await (const chunk of handle.createReadStream()) hash.update(chunk); }
  finally { await handle.close(); }
  return hash.digest('hex');
}
function archivePathGuard(value) {
  if (!value || /[\x00-\x1f:]/.test(value) || /^[\\/]/.test(value) || value.split(/[\\/]/).some(p => p === '..' || p === '.' || /[. ]$/.test(p))) throw new Error(`Unsafe archive path: ${value}`);
  // Windows device names and alternate namespace spellings must not reach extraction.
  if (value.split(/[\\/]/).some(p => /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(p))) throw new Error('Device archive path');
  return value;
}
function guardListing(text, budget = 6 * 1024 ** 3) {
  const marker = text.search(/^----------\s*$/m);
  if (marker < 0) throw new Error('No archive entries separator');
  let entries = 0, total = 0;
  for (const block of text.slice(marker).split(/\r?\n\r?\n/)) {
    const match = /^Path = (.+)$/m.exec(block);
    if (!match) continue;
    archivePathGuard(match[1]); entries++;
    const size = /^Size = (\d+)$/m.exec(block);
    if (size) total += Number(size[1]);
    if (!Number.isSafeInteger(total) || total > budget) throw new Error('Archive expansion budget exceeded');
    if (/^(?:Symbolic Link|Hard Link|Reparse Point) = /mi.test(block) || /^Attributes = .*\b(?:L|Reparse)\b/mi.test(block) || /^Attributes = .*l[rwx-]{9}/mi.test(block) || /^Mode = l/m.test(block)) throw new Error('Archive link/reparse entry');
  }
  if (!entries) throw new Error('Empty/unrecognized archive');
}
async function noLinks(target) {
  let current = path.parse(path.resolve(target)).root;
  for (const part of path.resolve(target).slice(current.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    try { if ((await fs.lstat(current)).isSymbolicLink()) throw new Error(`Link/reparse path: ${current}`); }
    catch (e) { if (e.code === 'ENOENT') return; throw e; }
  }
}
async function absent(file) {
  try { await fs.lstat(file); } catch (e) { if (e.code === 'ENOENT') return; throw e; }
  throw new Error(`Refusing existing destination: ${file}`);
}
async function downloadHttp(url, handle, cap, options = {}) {
  const controller = new AbortController();
  const timeoutMs = options.timeoutMs ?? 30000;
  const deadline = Date.now() + (options.totalTimeoutMs ?? 300000);
  const fetcher = options.fetchImpl || fetch;
  async function bounded(operation) {
    let timer;
    try {
      return await Promise.race([operation, new Promise((resolve, reject) => {
        timer = setTimeout(() => { controller.abort(); reject(new Error('Download stalled/deadline exceeded')); }, Math.max(1, Math.min(timeoutMs, deadline - Date.now())));
      })]);
    } finally { clearTimeout(timer); }
  }
  let response, reader;
  try {
    for (let redirects = 0; ; redirects++) {
      if (redirects > 8 || new URL(url).protocol !== 'https:') throw new Error('Unsafe redirect');
      // A wall-clock deadline covers DNS/connect/TLS, not just an attached socket.
      response = await bounded(fetcher(url, { redirect: 'manual', signal: controller.signal,
        headers: { 'User-Agent': 'ghostty-sandbox-acquire' } }));
      if (![301, 302, 303, 307, 308].includes(response.status)) break;
      const next = response.headers.get('location');
      if (!next) throw new Error('Redirect missing location');
      await response.body?.cancel(); url = new URL(next, url).href;
    }
    if (response.status !== 200) throw new Error(`HTTP ${response.status}`);
    if (!response.body) throw new Error('Missing download body');
    reader = response.body.getReader(); let size = 0;
    for (;;) {
      const { done, value } = await bounded(reader.read()); if (done) break;
      size += value.length; if (size > cap) throw new Error('Download cap exceeded');
      await handle.writeFile(value);
    }
  } finally {
    controller.abort();
    if (reader) await reader.cancel().catch(() => {});
  }
}
async function acquireArtifact(spec, directory, fetcher = downloadHttp, options = {}) {
  const target = path.join(directory, spec.name);
  await noLinks(target);
  try {
    const st = await fs.lstat(target);
    if (!st.isFile() || st.size > spec.cap || await hashFile(target, spec.algorithm) !== spec.digest) throw new Error('Invalid cached artifact; retained, not reused');
    return { ...spec, file: target, reused: true };
  } catch (e) { if (e.code !== 'ENOENT') throw e; }
  let partial, resumed = false;
  if (options.resume) {
    const prefix = spec.name + '.';
    const candidates = [];
    for (const name of await fs.readdir(directory)) {
      if (!name.startsWith(prefix) || !/\.[a-f0-9-]{36}\.partial$/.test(name)) continue;
      const file = path.join(directory, name); await noLinks(file);
      const stat = await fs.lstat(file);
      if (stat.isFile() && stat.size > 0 && stat.size <= spec.cap) candidates.push({ file, size: stat.size });
    }
    candidates.sort((a, b) => b.size - a.size);
    if (candidates.length) { partial = candidates[0].file; resumed = true; }
  }
  partial ||= `${target}.${crypto.randomUUID()}.partial`;
  const handle = await fs.open(partial, resumed ? 'r+' : 'wx');
  try {
    // An interrupted response may already contain the entire pinned resource.
    // Only whole-file digest verification can establish that, never a label.
    const complete = resumed && await hashFile(partial, spec.algorithm) === spec.digest;
    if (!complete && options.resume) await (options.resumeTransport || resumeDownload)({ url: spec.url, handle, cap: spec.cap, onProgress: options.onProgress });
    else if (!complete) await fetcher(spec.url, handle, spec.cap);
  } finally { await handle.close(); }
  const st = await fs.stat(partial);
  if (st.size > spec.cap || await hashFile(partial, spec.algorithm) !== spec.digest) throw new Error('Pinned digest mismatch; partial retained');
  // Hard-link publication is atomic and cannot replace an unknown existing target.
  await fs.link(partial, target);
  return { ...spec, file: target, partial, reused: false, resumed };
}
function run(executable, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '', bytes = 0, failure;
    const timer = setTimeout(() => { failure = new Error('Extractor deadline exceeded'); child.kill(); }, 60000);
    for (const stream of [child.stdout, child.stderr]) stream.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > 4 * MiB) { failure = new Error('Extractor output cap exceeded'); child.kill(); } else output += chunk.toString();
    });
    child.on('error', e => { clearTimeout(timer); reject(e); });
    child.on('close', code => { clearTimeout(timer); if (failure || code !== 0) reject(failure || new Error(`Extractor failed (${code}); installer execution is forbidden`)); else resolve(output); });
  });
}
async function scan(directory) {
  const files = []; let bytes = 0;
  async function walk(dir) {
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name); await noLinks(file);
      const st = await fs.lstat(file);
      if (st.isDirectory()) await walk(file);
      else if (st.isFile()) { bytes += st.size; files.push(file); }
      else throw new Error('Non-regular extracted entry');
    }
  }
  await walk(directory); return { files, bytes };
}
async function extract(exe, archive, destination, budgetRoot) {
  const remaining = 8 * 1024 ** 3 - (await scan(budgetRoot)).bytes - 700 * MiB;
  guardListing(await run(exe, ['l', '-slt', archive]), remaining);
  await absent(destination); await fs.mkdir(destination);
  await run(exe, ['x', '-y', `-o${destination}`, archive]);
  return scan(destination);
}
async function main(root) {
  if (process.platform !== 'win32' || !root || !path.win32.isAbsolute(root) || !/^D:\\/i.test(path.resolve(root))) throw new Error('An absolute D: owned prototype root on Windows is required');
  root = path.resolve(root); await noLinks(root);
  const workspace = path.resolve(__dirname, '../../..');
  if (!root.toLowerCase().startsWith((workspace + path.sep).toLowerCase())) throw new Error('Prototype root must be inside the current workspace');
  const parent = path.dirname(root); await fs.access(parent);
  const space = await fs.statfs(parent, { bigint: true });
  if (space.bavail * space.bsize < 10n * 1024n ** 3n) throw new Error('At least 10 GiB free required');
  const manifest = path.join(root, 'sandbox-owned.json');
  try {
    await fs.mkdir(root);
    await fs.writeFile(manifest, JSON.stringify({ name: 'ghostty-sandbox-owned', schema: 1, nonce: crypto.randomUUID() }), { flag: 'wx' });
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    await noLinks(manifest);
    const owned = JSON.parse(await fs.readFile(manifest, 'utf8'));
    if (owned.name !== 'ghostty-sandbox-owned' || owned.schema !== 1 || typeof owned.nonce !== 'string' || owned.nonce.length < 16) throw new Error('Owned manifest required');
  }
  if ((await scan(root)).bytes > 8 * 1024 ** 3) throw new Error('Owned budget exceeded');
  for (const relative of ['Build/downloads', 'Runtime/base', 'Runtime/node', 'Runtime']) {
    const destination = path.join(root, relative); await noLinks(destination); await fs.mkdir(destination, { recursive: true });
  }
  console.log('Acquiring pinned public archives');
  const artifacts = [];
  for (const spec of sources) {
    console.log(`Verifying/acquiring ${spec.name}`);
    let last = -16 * MiB;
    artifacts.push(await acquireArtifact(spec, path.join(root, 'Build/downloads'), undefined, {
      resume: true,
      onProgress: info => {
        if (info.bytes - last >= 16 * MiB || info.bytes === info.total) {
          last = info.bytes;
          console.log(`${spec.name}: ${Math.round(info.bytes / MiB)}/${Math.round(info.total / MiB)} MiB`);
          require('node:fs').writeFileSync(path.join(root, 'Build/acquisition-progress.json'), JSON.stringify({
            artifact: spec.name, stage: 'transport-not-yet-integrity-verified', ...info,
          }));
        }
      },
    }));
  }
  const receipt = { schema: 1, nonce: crypto.randomUUID(), artifacts, verification: 'Pinned hashes only; no Authenticode assertion', nodeVersion: process.version, binaries: [] };
  const receiptPath = path.join(root, `Build/acquisition-${receipt.nonce}.json`);
  await fs.writeFile(receiptPath, JSON.stringify({ ...receipt, status: 'archives-verified' }, null, 2), { flag: 'wx' });
  console.log('Listing and extracting portable tools (never executing installers)');
  const full = path.join(root, 'Build/full7zip');
  await extract(artifacts[0].file, artifacts[1].file, full, root);
  const fullExe = path.join(full, '7z.exe');
  for (const file of [fullExe, path.join(full, '7z.dll')]) { if (!(await fs.stat(file)).isFile()) throw new Error('Missing full 7-Zip payload'); }
  const qemu = path.join(root, 'Runtime/qemu');
  const payload = await extract(fullExe, artifacts[2].file, qemu, root);
  const candidates = payload.files.filter(f => path.basename(f).toLowerCase() === 'qemu-system-x86_64.exe' && payload.files.some(g => path.dirname(g) === path.dirname(f) && path.basename(g).toLowerCase() === 'qemu-img.exe'));
  if (candidates.length !== 1) throw new Error('Expected unique same-subtree QEMU executable pair');
  receipt.payloadRoot = path.dirname(candidates[0]);
  const node = path.join(root, 'Runtime/node/node.exe'); await absent(node);
  await fs.copyFile(process.execPath, node, require('node:fs').constants.COPYFILE_EXCL);
  if (await hashFile(node) !== await hashFile(process.execPath)) throw new Error('Node copy mismatch');
  const base = path.join(root, 'Runtime/base/debian.qcow2'); await absent(base);
  await fs.copyFile(artifacts[3].file, base, require('node:fs').constants.COPYFILE_EXCL);
  if (await hashFile(base, sources[3].algorithm) !== sources[3].digest) throw new Error('Base copy mismatch');
  for (const [file, source] of [[artifacts[0].file, artifacts[0]], [fullExe, artifacts[1]], [path.join(full, '7z.dll'), artifacts[1]], [candidates[0], artifacts[2]], [path.join(receipt.payloadRoot, 'qemu-img.exe'), artifacts[2]], [node, null]]) {
    receipt.binaries.push({ file, sha256: await hashFile(file), sourceURL: source?.url || 'current process.execPath', sourceArchiveDigest: source?.digest || null });
  }
  if ((await scan(root)).bytes > 8 * 1024 ** 3) throw new Error('Owned budget exceeded');
  await fs.writeFile(path.join(root, `Build/acquisition-${receipt.nonce}-complete.json`), JSON.stringify({ ...receipt, status: 'complete' }, null, 2), { flag: 'wx' });
  console.log('Acquisition complete; verified portable payload receipt written');
}
module.exports = { sources, verifyBytes, archivePathGuard, guardListing, acquireArtifact, hashFile, downloadHttp };
if (require.main === module) main(process.argv.length === 3 ? process.argv[2] : null).catch(e => { console.error(`Acquisition failed: ${e.message}`); process.exitCode = 1; });

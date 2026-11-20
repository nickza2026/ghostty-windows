'use strict';
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto'), { spawnSync } = require('node:child_process');
const { assemble } = require('./assemble.cjs');
const repo = path.resolve(__dirname, '../../..');
const archiveHash = '532beebff9f7cf412a9bce9673bee63e98d6d65ae98e4ccf13c9a370fcacfcf3';
const binaryHash = '594097ee235653fa709ebe097633bd2588c91cf7285d517550470f0e24baf358';
async function sha(file) { const h = crypto.createHash('sha256'); for await (const b of fs.createReadStream(file)) h.update(b); return h.digest('hex'); }
function real(file) { for (let p = path.resolve(file); ; p = path.dirname(p)) { if (fs.lstatSync(p).isSymbolicLink()) throw Error('Reparse path refused'); if (path.dirname(p) === p) break; } }
function ownedFresh(out) { out = path.resolve(out); if (!out.startsWith(path.join(repo, 'zig-out') + path.sep) || fs.existsSync(out)) throw Error('Fresh owned zig-out output required'); real(path.dirname(out)); fs.mkdirSync(out); return out; }
function runTar(args) { const r = spawnSync(path.join(process.env.SystemRoot, 'System32/tar.exe'), args, { windowsHide: true, encoding: 'utf8', timeout: 900000, maxBuffer: 16 * 1024 * 1024 }); if (r.error || r.status !== 0) throw Error('Public archive operation failed'); return r.stdout; }
function safeList(archive, prefix) {
  const names = runTar(['-tf', archive]).split(/\r?\n/).filter(Boolean);
  if (!names.length) throw Error('Empty archive');
  for (const name of names) {
    const n = name.replaceAll('\\', '/'), parts = n.split('/').filter(Boolean);
    if (n.startsWith('/') || /[:\x00-\x1f]/.test(n) || parts.some(p => p === '.' || p === '..') || parts[0] !== prefix || parts.some(p => /[. ]$/.test(p)) || parts.some(p => /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(p)) || parts[1]?.toLowerCase() === 'data' || parts.some(p => /^guest-setup\.json$/i.test(p))) throw Error('Unsafe/private archive path');
  }
}
function copyPublic(from, to) {
  real(from); const s = fs.lstatSync(from);
  if (s.isDirectory()) { fs.mkdirSync(to); for (const n of fs.readdirSync(from)) copyPublic(path.join(from, n), path.join(to, n)); }
  else if (s.isFile()) fs.copyFileSync(from, to); else throw Error('Special public file refused');
}
async function inventory(root) {
  const files = [];
  async function walk(dir) { real(dir); for (const n of fs.readdirSync(dir)) { const file = path.join(dir, n), s = fs.lstatSync(file); if (s.isSymbolicLink()) throw Error('Reparse artifact refused'); if (s.isDirectory()) await walk(file); else if (s.isFile()) files.push({ name: path.relative(root, file).replaceAll('\\', '/'), bytes: s.size, sha256: await sha(file) }); else throw Error('Special artifact refused'); } }
  await walk(root); return files.sort((a, b) => a.name.localeCompare(b.name));
}
async function build(output, nativeRecipeFile) {
  const zip = path.join(repo, 'zig-out/sandbox-node-candidate-20261115-ebdfc56b/sandbox-node-portable-20261115.zip');
  let prefix = path.join(repo, 'zig-out/native-sandbox-build-9ed7622e15044791a25ea60debb45ed5/package');
  let executable = path.join(prefix, 'bin/localterm-dev.exe'), expectedBinaryHash = binaryHash;
  if (nativeRecipeFile) {
    nativeRecipeFile = path.resolve(nativeRecipeFile); real(nativeRecipeFile);
    if (!nativeRecipeFile.startsWith(path.join(repo, 'zig-out') + path.sep)) throw Error('Owned native build receipt required');
    const native = JSON.parse(fs.readFileSync(nativeRecipeFile, 'utf8').replace(/^\uFEFF/, ''));
    if (native.exitCode !== 0 || native.productName !== 'Sandbox' || native.originalFilename !== 'Sandbox.exe' || !/^[a-f0-9]{64}$/.test(native.sha256)) throw Error('Successful Sandbox build required');
    prefix = path.resolve(native.nativePrefix); executable = path.resolve(native.executable); expectedBinaryHash = native.sha256;
    if (!prefix.startsWith(path.join(repo, 'zig-out') + path.sep) || executable !== path.join(prefix, 'bin/Sandbox.exe')) throw Error('Native receipt path mismatch');
  }
  real(zip); real(executable); real(path.join(prefix, 'share'));
  if (fs.statSync(zip).size !== 555241887 || await sha(zip) !== archiveHash || await sha(executable) !== expectedBinaryHash) throw Error('Verified public input hash mismatch');
  safeList(zip, 'Sandbox-Node-Portable');
  const out = ownedFresh(output || path.join(repo, 'zig-out/native-preview-' + crypto.randomUUID()));
  const report = { schema: 1, out, passed: false, inputArchiveSha256: archiveHash, executableSha256: expectedBinaryHash, dataIncluded: false, ...(nativeRecipeFile ? { nativeRecipeFile, productName: 'Sandbox' } : {}) };
  const save = () => fs.writeFileSync(path.join(out, 'native-package.json'), JSON.stringify(report, null, 2)); save(); console.log(out);
  try {
    runTar(['-xf', zip, '-C', out]);
    const original = path.join(out, 'Sandbox-Node-Portable');
    await inventory(original);
    if (fs.existsSync(path.join(original, 'Data'))) throw Error('Factory archive has Data');
    const root = path.join(out, 'Sandbox-Native-Preview'); fs.renameSync(original, root);
    const nonce = crypto.randomBytes(16).toString('hex');
    fs.writeFileSync(path.join(root, 'sandbox-owned.json'), JSON.stringify({ schema: 1, name: 'ghostty-sandbox-owned', nonce }));
    const profile = JSON.parse(fs.readFileSync(path.join(root, 'guest-profile.json'), 'utf8')); if (profile.profile !== 'node') throw Error('Node-only factory required');
    assemble(root);
    copyPublic(executable, path.join(root, 'Sandbox.exe'));
    copyPublic(path.join(prefix, 'share'), path.join(root, 'share'));
    copyPublic(path.join(repo, 'LICENSE'), path.join(root, 'LICENSE-native-Ghostty'));
    fs.writeFileSync(path.join(root, 'NATIVE-PREVIEW-README.txt'), 'Sandbox native Windows preview: open root-level Sandbox.exe. Keep App, Runtime and share together. Requires supported WHPX.\r\nFirst use sets a NEW Linux sudo password inside the native terminal; never use your Windows password or send it to chat. Internet is required for the first guest Node download.\r\nClosing the native terminal disconnects only: it does NOT stop the VM. Use Sandbox-Status.cmd and Stop-Sandbox.cmd for explicit status/normal shutdown.\r\nNo host-shell fallback. No provider accounts, preset password, private SSH key or guest Data included.\r\nexFAT requires explicit reduced-protection consent using Enable-ExFAT.cmd; NTFS remains strict.\r\nThis is a preview, not human GUI acceptance. Ordinary portable builds are unchanged.\r\n');
    fs.copyFileSync(path.join(repo, 'docs/windows-native-sandbox-preview-th.md'), path.join(root, 'NATIVE-GUIDE-TH.md'));
    const files = await inventory(root);
    if (files.some(f => /^Data\//i.test(f.name) || /guest-setup\.json$/i.test(f.name))) throw Error('Private factory artifact refused');
    report.root = root; report.nonce = nonce; report.files = files; report.factoryBytes = files.reduce((n, f) => n + f.bytes, 0); report.sourceSnapshot = JSON.parse(fs.readFileSync(path.join(root, 'App/source-snapshot.json'), 'utf8'));
    const archive = path.join(out, 'sandbox-native-preview.zip');
    runTar(['-a', '-cf', archive, '-C', out, 'Sandbox-Native-Preview']); safeList(archive, 'Sandbox-Native-Preview');
    const check = path.join(out, 'archive-check'); fs.mkdirSync(check); runTar(['-xf', archive, '-C', check]);
    const testRoot = path.join(check, 'Sandbox-Native-Preview');
    if (JSON.stringify(await inventory(testRoot)) !== JSON.stringify(files)) throw Error('Fresh archive reextract differs');
    if (fs.existsSync(path.join(root, 'Data')) || fs.existsSync(path.join(testRoot, 'Data'))) throw Error('Factory must remain unconfigured');
    report.archive = archive; report.archiveSha256 = await sha(archive); report.archiveBytes = fs.statSync(archive).size;
    report.testRoot = testRoot; report.archiveReextractVerified = true; report.passed = true;
  } catch (error) { report.error = error.message; throw error; }
  finally { save(); }
  return report;
}
if (require.main === module) build(process.argv[2], process.argv[3]).then(r => console.log(JSON.stringify({ passed: r.passed, root: r.root, archive: r.archive, sha256: r.archiveSha256 }))).catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { build, inventory, sha, real, repo };

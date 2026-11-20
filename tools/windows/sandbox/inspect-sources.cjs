'use strict';

// Public release metadata only. No host config, credentials, or executables.
const urls = [
  'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.sha512',
  'https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS',
  'https://api.github.com/repos/ip7z/7zip/releases/tags/26.06',
  'https://api.github.com/repos/herdrdev/herdr/releases/tags/v0.9.5',
  'https://registry.npmjs.org/@letta-ai%2fletta-code/0.34.23',
];

async function inspect() {
  for (const url of urls) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(20000),
        headers: { 'User-Agent': 'PortableSandboxPrototype/1.0' },
      });
      console.log('URL', url, 'STATUS', response.status);
      if (!response.ok) continue;
      const text = await response.text();
      if (url.includes('api.github.com')) {
        const release = JSON.parse(text);
        console.log(JSON.stringify({ tag: release.tag_name, assets: release.assets?.map(a => ({
          name: a.name, size: a.size, digest: a.digest, url: a.browser_download_url,
        })) }));
      } else if (url.includes('registry.npmjs')) {
        const pkg = JSON.parse(text);
        console.log(JSON.stringify({ version: pkg.version, engines: pkg.engines,
          scripts: pkg.scripts, dependencies: pkg.dependencies, dist: pkg.dist }));
      } else {
        console.log(text.split(/\r?\n/).filter(line => url.includes('qemu') ||
          line.includes('generic-amd64') || line.includes('genericcloud-amd64')).slice(0, 5).join('\n'));
      }
    } catch (error) { console.log('FETCH_FAILED', url, error.message); }
  }
}

if (require.main === module) inspect().catch(error => { console.error(error.message); process.exitCode = 1; });

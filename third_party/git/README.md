# Portable Git

The installer downloads the pinned Git for Windows PortableGit x64 release
into `bin/portable-data/runtimes/git`, preserving the complete archive contents,
including upstream notices and dependencies. The pin records the official
GitHub release asset digest supplied during release verification.

`Install-Portable-Git.cmd` installs only this runtime and a native `git.exe`
forwarder in portable-data/shims. No host Git, account, HOME, registry, or
global configuration is changed. Existing unknown or modified installations
are rejected, not overwritten. Runtime and proxy provenance record SHA-256
integrity; these are corruption checks, not protection against an attacker
able to rewrite both executable and manifest.

PortableGit includes Bash, sh and env required by Letta's Bash-based commit
hooks; MinGit alone does not. The `.7z.exe` download is never executed. The
installer uses the absolute Windows `System32/tar.exe` reader to validate
names, types and sizes, then pinned official standalone 7zr 26.05 (public domain)
under `portable-data/runtimes/git-bootstrap` to extract. Windows libarchive can
list this archive but cannot decode its LZMA lc=8 stream. Neither Git's SFX nor
its configured post-install command runs. All child operations are hidden and
bounded; the extracted tree is checked before promotion. The extractor's
official GitHub asset URL, size and SHA-256 are fixed in the installer and
recorded in its own provenance.

An intact installation matching the previous pinned MinGit release may be
upgraded under the installer lock after all its manifest hashes and file count
are verified and no process executable uses that runtime. Promotion retains
the old tree until the new tree is in place, rolls back a failed rename, and
removes only the verified old backup. Modified or unrecognized trees fail closed.

The native forwarder resolves the runtime relative to itself, preserving
relocation, arguments, environment, working directory and standard handles.
A kill-on-close job owns the child before it starts, so terminating the
forwarder also terminates Git descendants. No host PATH fallback is used.

This pin uses the upstream `ucrt64` layout (verified from the archive), including
`cmd/git.exe`, `ucrt64/bin/git.exe`, `ucrt64/libexec/git-core/git-remote-https.exe` and
`LICENSE.txt`, `usr/bin/bash.exe`, `usr/bin/sh.exe` and `usr/bin/env.exe`.
Do not substitute the historical `mingw64` layout or copy only
the entry executable. Source packaging attaches setup as a first-use preflight
for isolated launchers; this alone is not proof that a user's existing package
or real Letta account has been updated or verified.

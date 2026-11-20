# Portable Node payload

Pinned official Windows x64 Node 24 Krypton LTS, selected from the official index on 2026-10-27. Run tools/windows/stage-portable-node.ps1 to download into a unique workspace zig-out directory. The pinned SHA256 is from the official HTTPS SHASUMS256.txt (not a detached-signature verification). Full upstream LICENSE and bundled dependency notices remain in the payload. No installer, npm operation, Letta installation, account or profile migration is performed.

Pass the emitted NODE_SOURCE to package-portable.ps1 -PortableTools -NodeSource. Runtime provenance uses relative file identities so packages remain relocatable. Refresh pins deliberately after reviewing a maintained LTS release; staging does not silently select a new version.

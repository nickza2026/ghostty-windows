# Herdr first-run launcher

The package launcher downloads the official Windows x64 ZIP for the exact release
in `source-pin.json`, verifies its SHA-256 before extraction, and retains every
release file, including ConPTY and its third-party notices. Source and upstream
release metadata URLs are recorded in the pin. No official installer is executed:
upstream install.ps1 writes the user PATH. No update/channel command is invoked.

This is a project-provided first-run launcher, **not an upstream-supported portable
mode**. It isolates environment paths and a fresh profile beneath this package's
`bin/portable-data/profiles/herdr`; it neither imports nor removes existing accounts.
This is not an OS security sandbox. Herdr and tools it launches retain the user's
normal filesystem and network permissions. Login and provider setup are separate
user actions. Do not run two copies against the same package data concurrently.

The pinned payload lives in `bin/portable-data/apps/herdr/0.9.5`. Reuse checks all
files against the installation hash manifest and rejects missing, changed, or extra
files. Corrupt or partial installs fail closed; the launcher never repairs them by
overwriting files and never falls back to an installed host Herdr. Keep this tree
immutable; user settings belong in the private profile instead. There is no automatic
update, release purge, registry modification, or machine-wide dependency install.

The launcher also builds the project-owned `herdr-private-shell.cs` console shim
with Windows' existing .NET Framework compiler. This is not part of upstream Herdr:
it supplies `-NoProfile`, private HOME/history initialization and inherited console
handles because v0.9.5's ordinary PowerShell pane path omits `-NoProfile`. Its source
and executable are hash-checked under `portable-data/apps/herdr-shell/v1`. Only a
fresh configuration is seeded; existing/custom user shell configuration is preserved
and is outside that default-shell assurance. Windows PowerShell/.NET and OS modules
remain OS dependencies, not a filesystem sandbox or an account-migration mechanism.

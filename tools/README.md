# TemnyiVPN release tooling

Scripts that build release packages and update payloads.

## Build pipeline

### Windows setup

```powershell
# Build app + installer + update manifest (does NOT publish):
powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1

# Same, but also publish the GitHub release:
powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1 -PublishRelease
```

`build_installer.ps1` runs, in order:

1. `flutter build windows` (skip with `-SkipFlutterBuild`)
2. `build_release_manifest.ps1` — walks the Release dir, writes
   `build/release/<version>/manifest.json` and `blobs.pack` (all unique file
   contents concatenated, deduplicated by SHA-256), and drops a copy of
   `manifest.json` next to the build output so the installer ships it
3. Inno Setup compiles `TemnyiVPN-Setup-<version>.exe`
4. with `-PublishRelease`: `gh release create` uploads three assets:
   the installer, `manifest.json`, and `blobs.pack`

### Linux package

Run on Linux with Flutter desktop support installed:

```bash
# Build the Linux app, a tarball, and an installable .deb package:
bash tools/build_linux_installer.sh

# Repackage an already-built Linux bundle:
bash tools/build_linux_installer.sh --skip-flutter-build
```

Outputs:

- `build/linux/dist/entropy_vpn-<version>-linux-x64.tar.gz`
- `build/linux/dist/temnyivpn_<version>_<arch>.deb`

Install the `.deb` on Debian/Ubuntu:

```bash
sudo apt install ./build/linux/dist/temnyivpn_<version>_<arch>.deb
```

The package installs the app to `/opt/entropy_vpn`, adds
`/usr/bin/entropy_vpn`, installs the desktop launcher, and bundles the Linux
core binaries from `tools/cores/linux` when present.

## How the in-app updater works

Each release ships:
- `manifest.json` — every shippable file with its size, SHA-256, and a
  `pack_offset` pointing into `blobs.pack`
- `blobs.pack` — every unique file's content concatenated, deduplicated by
  SHA-256

The privileged Windows service:

1. fetches the latest release from the GitHub API,
2. downloads `manifest.json`,
3. hashes the installed files and compares them against the manifest,
4. for each file whose hash differs, issues an HTTP `Range` request against
   `blobs.pack` for exactly `[pack_offset, pack_offset + size)` bytes — so a
   user with a tiny Dart-only delta downloads ~kilobytes, not the whole 100+
   MB pack,
5. verifies each downloaded slice's SHA-256, then applies the changed files in
   place.

SHA-256 is used purely to detect which files changed and to catch corrupt
downloads — there is no manifest signing. Transport security relies on HTTPS to
GitHub.

The schema version is currently `2`. Clients running schema-1 binaries cannot
auto-update across the schema bump; they need a one-time manual reinstall.

## Files

| File | Purpose |
|---|---|
| `build_installer.ps1` | Top-level build + (optional) publish |
| `build_linux_installer.sh` | Builds Linux tarball + installable `.deb` |
| `build_linux_release.sh` | Builds Linux tarball only |
| `build_release_manifest.ps1` | Generates `manifest.json` + `blobs.pack` |
| `release_exclude_globs.txt` | File-exclude list shared with the installer |

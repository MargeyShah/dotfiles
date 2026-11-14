# EmuDeck cross-device saves

Single entry point for making every emulator's save data physically live under
`<Emulation>/saves/<emu>` on a NAS shared between **Windows and Linux**, so any
machine reads/writes the same files and EmuDeck Cloud Saves backs them all up.
Shared game installs (RPCS3 `dev_hdd0`, Vita3K `ux0/app`) live under
`<Emulation>/storage/<emu>` so games are installed once.

```
Windows            Z:\Emulation\saves\<emu>\...        (same files)
Linux              <Linux mount>/Emulation/saves/<emu>\...
NAS  (one root)    <Emulation>/saves/<emu>/
EmuDeck Cloud      Emudeck/saves/<emu>/   (rclone, synced from $savesPath)
```

## 0. Start here: which direction?

**Ask the user which machine they are on / starting from before anything else.**
Never infer one OS's path from the other. The two sides are **not symmetric** —
they use different mounts, different mechanisms (symlink vs config key), and
different scripts — so the procedure depends on the starting OS.

| Role | Windows | Linux |
|---|---|---|
| NAS share | `\\192.168.0.3\myPlex` (SMB) | same share, mounted via NFS (e.g. `/mnt/emulation`) |
| Emulation root | `Z:\Emulation` | `<Linux mount>/Emulation` |
| Saves | `Z:\Emulation\saves` | `<Emulation>/saves` |
| Shared storage | `Z:\Emulation\storage` | `<Emulation>/storage` |

- **Starting on Windows** → follow [`emudeck-windows.md`](emudeck-windows.md):
  EmuDeck for Windows creates symbolic links (network-install mode); you only
  install a launcher/settings fix and **verify**. No emulator config changes.
- **Starting on Linux** → follow [`emudeck-linux.md`](emudeck-linux.md):
  run the enforcement engine (`emudeck-crossdevice-saves.sh`) after EmuDeck's
  first Setup; it creates symlinks / sets config keys and re-runs at every Setup.

If a mapping is unknown, **ask the user**; do not guess it.

## Filesystem expectations per OS

These are the invariants that make the two sides agree on one file tree:

- **Linux mount is NFS.** The engine is NFS-safe: it never `chown`s (NFS
  `sec=sys` rejects it) and copies preserve content+mtime+mode. Merges are
  newest-wins per file.
- **Windows mount is SMB.** Windows maps the share to a drive letter (`Z:`) and
  EmuDeck's links point at UNC targets (`\\server\share\...`). PowerShell may
  display a network symlink target as `UNC\server\share\...` — that is the same
  path as `\\server\share\...`; never compare raw `.Target` strings.
- **Windows cannot create a symlink *on* the SMB share** — only on local NTFS
  pointing at a UNC target. So the three RPCS3/Vita3K `storage\...` links are
  reported as `LIMITATION` (expected), not broken. Linux can create those POSIX
  symlinks; whether Windows sees through them depends on the SMB server
  following server-side symlinks.
- **Both OSes write the same files.** EmuDeck Cloud Saves syncs the whole
  `saves\` tree, so whatever the emulator touches on either OS is backed up.

## Agent iteration loop (both OS types)

To validate or repair a cross-device setup, iterate in this order:

1. **Linux (enforcement):** run
   `setup/emudeck/emudeck-crossdevice-saves.sh --check` (read-only), then the
   engine, then `--check` again — expect no `[check] fix` lines.
2. **Linux (persistence):** ensure `~/.config/EmuDeck/custom_scripts/` contains
   symlinks to the repo engine + `emulators.conf` (next EmuDeck Setup re-runs
   it). `setup/lib.sh` `emudeck_crossdevice_saves()` does this automatically.
3. **Windows (fix, once):**
   `powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -Install`.
4. **Windows (verify):**
   `powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-check.ps1`
   → expect **22 OK, 0 wrong/failed, 3 LIMITATION** (the RPCS3/Vita3K SMB links).
5. **Round-trip:** write a save on one OS, confirm it appears on the other and
   in EmuDeck Cloud Saves (see the end-to-end test in `emudeck-windows.md`).

Details, per-emulator tables, migration steps and troubleshooting live in the
two per-OS docs:

| File | Purpose |
|---|---|
| [`emudeck-linux.md`](emudeck-linux.md) | Engine, `emulators.conf` format, running/migrating, persistence |
| [`emudeck-windows.md`](emudeck-windows.md) | Launcher/settings fix, verification checklist, round-trip test, troubleshooting |

| Component | File |
|---|---|
| Linux enforcement engine | `emudeck-crossdevice-saves.sh` |
| Emulator definitions (Linux engine) | `emulators.conf` |
| Windows fix (launcher/settings) | `emudeck-windows-fix.ps1` |
| Windows verification checker | `emudeck-windows-check.ps1` |

## Version-tested

| Component | Version validated |
|---|---|
| EmuDeck for Windows app | `2.7.1.0` |
| EmuDeck update check reported | `v2.7.2-unstable.138` |
| Windows EmuDeck backend commit | `c4350af` |
| EmuDeck Linux upstream `main` inspected | `0c212a84c624cef443a6c14784810db84165fd9d` (2026-11-12) |

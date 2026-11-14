# EmuDeck cross-device saves — Windows verification checklist

This file is for the **Windows PC** that shares the same NAS `Emulation` folder as
the Linux box. **No emulator config changes are needed on Windows** — EmuDeck
for Windows creates a **symbolic link** (network-install mode) for every
emulator's save path pointing at `<Emulation>\saves\<emu>` on the NAS. All the
layout enforcement happens on the Linux side
(`setup/emudeck/emudeck-crossdevice-saves.sh`, runs after every Linux EmuDeck
Setup). Windows just needs *verification*.

Before checking anything, establish the mapping. Do not infer it:

| Role | Example |
|---|---|
| NAS share | `\\192.168.0.3\myPlex` |
| Windows drive | `Z:` |
| Emulation root | `Z:\Emulation` |
| Saves / storage | `Z:\Emulation\saves`, `Z:\Emulation\storage` |

The checker prints both the drive-letter and UNC forms. If you see a target
like `UNC\192.168.0.3\myPlex\...`, that is the same as
`\\192.168.0.3\myPlex\...`; PowerShell just formats network symlink targets
that way. Never compare raw `.Target` strings against `Z:\...`.

---

## 0. Launcher/settings fix (install once; survives updates)

One-time install (recommended; details below):

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -Install
```

Manual apply/check without the persistent hook:

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -CheckOnly
```

This repairs two upstream EmuDeck issues that show up as fast-disappearing red
errors when an emulator starts:

1. `settings.ps1` always creates a temporary `Z:` PSDrive with a UNC root, even
   when `Z:` is already a persistent SMB mapping. The temporary drive shadows
   the real mapping, so PowerShell 5.1 resolves `Z:\Emulation\saves` to a
   duplicated path such as
   `\\192.168.0.3\myPlex\192.168.0.3\myPlex\...\Emulation\saves`. That makes
   `Set-Content $savesPath/.watching` and `.emulator` fail, so EmuDeck's cloud
   markers are never written. The script rewrites the one `New-PSDrive` line to
   reuse the existing drive.
2. EmuDeck's `isLatestVersionGH` writes to an undefined variable when
   `%APPDATA%\emudeck\emu_versions.json` is missing, then fails to read the
   file. The script creates it with `{}`.

It is idempotent and keeps a `settings.ps1.crossdevice.bak`. EmuDeck
regenerates `settings.ps1` when settings change or Setup runs; the `-Install`
hook above re-applies the patch automatically before the next launch. If you
choose not to install the hook, re-run the plain command after each
Setup/update.

Two messages are harmless EmuDeck noise and deliberately not fixed:

- `git : From https://...` (`NativeCommandError`) — git writes normal fetch
  progress to stderr.
- `hideMe` → `Cannot convert null to IntPtr` — only when PowerShell has no
  interactive window handle (e.g. Windows Terminal or a redirected session); it
  does not affect the launch.

### Persistence across EmuDeck updates

EmuDeck regenerates `settings.ps1` whenever Setup runs or settings change, so
the patch must be re-applied. Install the persistent hook once:

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -Install
```

That:

- copies the fix to `%APPDATA%\EmuDeck\crossdevice\emudeck-windows-fix.ps1`
  (outside EmuDeck's `backend\`, which is git-reset on every launch);
- adds a marked block to `$PROFILE.CurrentUserAllHosts`
  (`%USERPROFILE%\Documents\WindowsPowerShell\profile.ps1` by default).

Every EmuDeck launcher is a `powershell.exe` process, so the profile runs the
stable fix before the launcher reads `settings.ps1`. This re-applies the patch
even after EmuDeck has regenerated the file. The hook is idempotent and silent.

Remove it again with:

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -Uninstall
```

`-Uninstall` removes the profile block and stable copy; it intentionally leaves
the current `settings.ps1` patch in place (it is harmless). If you update the
repo copy of the fix script, re-run `-Install` to refresh the stable copy.

`emu_versions.json` lives in `%APPDATA%\emudeck\` and is not touched by
EmuDeck updates; the fix recreates it if missing.

### Tested versions

| Component | Version |
|---|---|
| EmuDeck for Windows app | `2.7.1.0` |
| EmuDeck update check reported | `v2.7.2-unstable.138` |
| Windows EmuDeck backend commit | `c4350af` |
| EmuDeck Linux upstream `main` inspected | `0c212a84c624cef443a6c14784810db84165fd9d` (2026-11-12) |

The Windows fix is pattern-based: it looks for the exact
`$testdrive=New-PSDrive` line and the missing `emu_versions.json`. If a future
EmuDeck version changes that code, it reports `already patched` or
`could not find the $testdrive=New-PSDrive line` and makes no destructive
change. Re-inspect the launcher and update the script if needed.

Check versions with:

```powershell
(Get-Item "$env:LOCALAPPDATA\Programs\EmuDeck\EmuDeck.exe").VersionInfo.ProductVersion
git -C "$env:APPDATA\EmuDeck\backend" rev-parse --short HEAD
```

The Linux engine is version-independent: it reads EmuDeck's `settings.sh` and
uses the paths documented in `emudeck.md`; it does not depend on a specific
EmuDeck release.

---

Easiest way to verify everything at once (recommended):

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-check.ps1
```

If `emudeck-windows-fix.ps1` is in the same folder, the checker runs it
automatically before checking (unless `-CheckOnly` is passed).

It fixes the shared rclone.conf URL if Setup rewrote it, prints the mapping, then
checks every save/state link below and the mGBA/melonDS config paths. Run it
after each EmuDeck Setup/update.

Useful switches:

- `-CheckOnly` — skip the rclone URL fix and all repairs.
- `-Fix` — re-point a genuinely wrong link (merges files when the old target
  is a real folder under `saves\`).
- `-EmulationPath Z:\Emulation` / `-UncRoot \\192.168.0.3\myPlex` — override
  detection when a drive is not mapped in the current session.

(The rest of this file is the manual version of the same checks.)

In the commands below:

- `$E` is your NAS Emulation root on Windows, e.g. `Z:\Emulation`
- `$saves` = `$E\saves`
- `$emus` = `%APPDATA%\EmuDeck\Emulators`

---

## 1. Cloud sync (fix first — this was broken)

EmuDeck Cloud Saves uses the shared NAS file `tools\rclone\rclone.conf`.

1. Open `$E\tools\rclone\rclone.conf`.
2. Find `[Emudeck-NextCloud]` and check the `url`:

   ```
   url = https://your.host/remote.php/dav/files/REAL_USERNAME/   ← correct
   url = https://your.host/remote.php/dav/files/USERNAME/        ← BROKEN (literal placeholder)
   ```

   The literal `USERNAME` must be replaced with your actual NextCloud login.
   A broken URL makes every upload fail with `409 Conflict: Parent node does
   not exist` (check `$E\...\rclone.log` or EmuDeck logs). **EmuDeck's Setup can
   rewrite this file — re-check it after every Setup.**
3. Verify the remote is reachable (optional, from PowerShell):

   ```powershell
   & "$E\tools\rclone\rclone.exe" --config "$E\tools\rclone\rclone.conf" lsd "Emudeck-NextCloud:Emudeck/saves/"
   ```

   You should see the same `<emu>` folders as on the NAS.

---

## 2. Per-emulator save layout (what to verify)

EmuDeck for Windows creates **symbolic links** (network-install mode) that point
each emulator's internal save path at `$saves\<emu>`. Verify each one. The
pattern:

```powershell
# link source -> target
cmd /c dir /al "<link source>"              # shows <SYMLINKD> [\\server\share\...]
# or as admin:
fsutil reparsepoint query "<link source>"
# or:
Get-Item "<link source>" | Select-Object LinkType, Target
```

`Get-Item ... .Target` may display `UNC\server\share\...` for a network symlink;
that is the same path as `\\server\share\...`. The check script normalises this.

| Emulator | Link source (Windows) | Must point to |
|---|---|---|
| Eden | `$emus\eden-windows-msvc\user\nand\user\save` | `$saves\eden\saves` |
| Eden (profiles) | `$emus\eden-windows-msvc\user\nand\system\save\8000000000000010\su\avators` | `$saves\eden\profiles` |
| Citron | `$emus\citron\user\nand\user\save` | `$saves\citron\saves` |
| Citron (profiles) | `$emus\citron\user\nand\system\save\8000000000000010\su\avators` | `$saves\citron\profiles` |
| Dolphin | `$emus\Dolphin-x64\User\GC`, `...\Wii`, `...\StateSaves` | `$saves\dolphin\GC`, `\Wii`, `\states` |
| Cemu | `$emus\cemu\mlc01\usr\save` | `$saves\Cemu\saves` |
| RPCS3 | `$E\storage\rpcs3\dev_hdd0\home\00000001\savedata` (+ `\trophy`) | `$saves\rpcs3\saves` (+ `\trophy`) |
| PPSSPP | `$emus\PPSSPP\memstick\PSP\SAVEDATA` (+ `\PSP\PPSSPP_STATE`) | `$saves\ppsspp\saves` (+ `\states`) |
| RetroArch | `$emus\RetroArch\saves` (+ `\states`) | `$saves\retroarch\saves` (+ `\states`) |
| PCSX2 | `$emus\PCSX2-Qt\memcards` (+ `...\sstates`) | `$saves\pcsx2\saves` (+ `\states`) |
| DuckStation | `$emus\duckstation\memcards` (+ `...\savestates`) | `$saves\duckstation\saves` (+ `\states`) |
| Vita3K | `$E\storage\Vita3K\ux0\user\00\savedata` | `$saves\Vita3K\saves` |
| ShadPS4 | `$emus\ShadPS4-qt\user\savedata` | `$saves\shadps4\saves` |
| Xenia | `$emus\xenia\content` | `$saves\xenia\saves` |
| mGBA | config `savegamePath` / `savestatePath` in `$emus\mgba\config.ini` | `$saves\mgba\saves` (+ `\states`) |
| melonDS | config `SaveFilePath` / `SavestatePath` in `$emus\melonDS\melonDS.ini` | `$saves\melonds\saves` (+ `\states`) |

Config-driven emulators (RetroArch, PCSX2, DuckStation, mGBA, melonDS) can also
have their **config files** point at `$saves\<emu>` directly — either is fine
as long as the files land in `$saves\<emu>`.

RPCS3's `savedata`/`trophy` links and Vita3K's `savedata` link are supposed to
be created by EmuDeck's setup, but on an SMB share Windows cannot create them.
They are not a sign that the emulator has not been launched, and a trophy does
not need to be unlocked first: the link is attempted independently of the
emulator's data.

Those links live **on the NAS share itself**. Windows can create a symlink on
local NTFS that points at a UNC target, but it cannot create one **on** an SMB
share: the server rejects the reparse point (`The file or directory is not a
reparse point`) and EmuDeck suppresses the error. Running Reset config or
approving UAC will not change that.

Local cross-device sharing still works because RPCS3's VFS points `/dev_hdd0/`
at `storage\rpcs3\dev_hdd0` and Vita3K's `pref-path` points at
`storage\Vita3K`. The `saves` links are only what EmuDeck Cloud Saves needs, so
the checker reports these three as `LIMITATION`, not as broken.

The Linux engine can create the POSIX symlink on the share. If the NAS's SMB
server follows server-side symlinks, Windows will see the target data through
that path and cloud sync will work; if it does not, only local NAS sharing is
available for those two emulators.

If a save link is missing/wrong, re-run **EmuDeck → Reset config** for that
emulator (or re-run EmuDeck Setup), then re-verify. This does not apply to the
three `storage\...` links above: those need a symlink on the SMB share, which
Windows cannot create.

### Shared game storage (installs)

Emulators that install games share the install dir on the NAS so games are only
installed once:

- **RPCS3** → `$E\storage\rpcs3\dev_hdd0` (contains `game\`, `home\`). Confirm
  RPCS3's VFS on Windows points `/dev_hdd0/` there (same as Linux), so games
  installed on either OS are visible on the other.
- **Vita3K** → `$E\storage\Vita3K\ux0\app`, with
  `$E\roms\psvita\InstalledGames` symlinked to it.

> ⚠️ Run only one machine at a time against shared game storage — RPCS3/Vita3K
> hold DB caches there and concurrent writes can corrupt.

---

## 3. End-to-end round-trip test

The real test is a save crossing the loop in both directions.

**Windows → Linux:**
1. On Windows, launch **Eden** and play a game long enough to write a save, then quit.
2. Confirm a file appears under `$saves\eden\saves\0000000000000000\AFC9...\<game id>\`.
3. Run EmuDeck Cloud Saves (upload). Confirm the same path exists on
   `Emudeck-NextCloud:Emudeck/saves/eden/...`.
4. On Linux, launch the same game in Eden → it should load the Windows save.

**Linux → Windows:**
1. On Linux, play the same game, save, quit (cloud sync uploads on exit).
2. On Windows, run EmuDeck Cloud Saves (download) and launch the game → the
   Linux save is there.

Repeat for at least one more emulator (e.g. Dolphin with a GC memory card or
Cemu) to prove the link-based ones work, not just Eden.

---

## 4. Pass criteria (all must be true)

- [ ] `rclone.conf` URL uses the real NextCloud username (no literal `USERNAME`).
- [ ] `rclone lsd Emudeck-NextCloud:Emudeck/saves/` lists the emu folders.
- [ ] Every link in the table above points at `$saves\<emu>` (or its UNC
      equivalent, `\\server\share\Emulation\saves\<emu>`).
- [ ] The check script reports `0 wrong/failed`. RPCS3/Vita3K may show
      `LIMITATION` for their `storage\...` links; that is expected on an SMB
      share and does not affect local cross-device sharing.
- [ ] RPCS3 `/dev_hdd0/` and Vita3K `ux0\app` point at `$E\storage\<emu>\...`
      on both OSes (games installed once, shared).
- [ ] A save written on Windows shows up on Linux (and vice-versa) via the NAS.
- [ ] EmuDeck Cloud Saves uploads/downloads complete with no `409 Conflict` /
      `fail_upload` markers (check `$saves\<emu>\.fail_upload` is absent).
- [ ] After an EmuDeck update/Setup, re-run this checklist (Setup can recreate
      broken links or the bad rclone URL).

---

## Troubleshooting

- **Cloud sync 409 errors** → the `rclone.conf` URL (see section 1).
- **`New-PSDrive : A drive with the name 'Z' already exists`**, followed by
  `You cannot call a method on a null-valued expression` and/or
  `Could not find a part of the path '\\...\...\Emulation\saves\.watching'` →
  EmuDeck's `settings.ps1` created a temporary Z: PSDrive that shadows your
  persistent mapping. Run `setup\emudeck\emudeck-windows-fix.ps1`.
- **`Set-Content : Cannot bind argument to parameter 'Path' because it is null`**
  and/or `Cannot find path ...\emudeck\emu_versions.json` → the same missing
  EmuDeck data file. Run `setup\emudeck\emudeck-windows-fix.ps1`.
- **`git : From https://...` (`NativeCommandError`)** → harmless; git writes
  normal fetch progress to stderr.
- **`Cannot convert argument "hWnd" ... to type "System.IntPtr"`** → harmless
  EmuDeck `hideMe` noise when PowerShell has no interactive window handle
  (Windows Terminal / redirected session); it does not stop the launch.
- **`cloud_sync_watcher_user.ps1` warns `Cannot find path ...\saves\.emulator`** →
  harmless EmuDeck behaviour, not from these scripts. EmuDeck's launcher writes
  `saves\.emulator` before starting an emulator and removes it afterwards; when
  the watcher starts (or restarts) after that file is gone it falls back to
  watching **all** of `saves`. The `Watching for changes to ...\saves` line and
  the `.....` dots are that watcher's normal heartbeat. It does not affect the
  save layout and the file is excluded from rclone sync. If the file is never
  written at all, also run `setup\emudeck\emudeck-windows-fix.ps1` (the
  settings.ps1 bug above can break those writes).
- **A link shows `DANGLING` (target missing)** → the NAS wasn't mounted when it
  was created, or the share is at a different path now. Remount, then Reset
  config for that emulator.
- **A link shows `WRONG TARGET` pointing at `saves\dolphin\states` and you
  expect `StateSaves`** → that is normal; `states` is the canonical Windows
  folder. The Linux engine targets `states` too. Do not rename it.
- **The check says "all 13 are broken" with `unc\192.168.0.3` targets** → the
  old checker compared raw `.Target` strings. Those links were fine; use the
  current script, which normalises `UNC\server\share` to `\\server\share` and
  compares against the UNC form of `$saves`.
- **Save appears in both `storage\` and `saves\`** → an old split copy. Let the
  Linux engine (or a Reset config) merge them; newest-wins is applied.
- **Windows can't see Linux-created files** → check the NAS mount (SMB/NFS) has
  `saves\` readable/writable; the links on Windows just need the target to be
  mounted at the same drive letter every boot.

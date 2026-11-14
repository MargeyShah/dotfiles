# EmuDeck cross-device saves — Windows verification checklist

This file is for the **Windows PC** that shares the same NAS `Emulation` folder as
the Linux box. **No emulator config changes are needed on Windows** — EmuDeck
for Windows already creates a junction for every emulator's save path pointing
at `<Emulation>\saves\<emu>` on the NAS. All the layout enforcement happens on
the Linux side (`setup/emudeck/emudeck-crossdevice-saves.sh`, runs after every
Linux EmuDeck Setup). Windows just needs *verification*.

Easiest way to verify everything at once (recommended):

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-check.ps1
```

It fixes the shared rclone.conf URL if Setup rewrote it, then checks every
junction below and prints OK / broken. Run it after each EmuDeck Setup/update.
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

EmuDeck for Windows creates **junctions** that point each emulator's internal
save path at `$saves\<emu>`. Verify each one. The pattern:

```powershell
# junction source -> target
cmd /c dir /al "<junction source path>"     # shows <JUNCTION> if present
# or as admin:
fsutil reparsepoint query "<junction source path>"
# or:
Get-Item "<junction source path>" | Select-Object LinkType, Target
```

| Emulator | Junction / link source (Windows) | Must point to |
|---|---|---|
| Eden | `$emus\eden-windows-msvc\user\nand\user\save` | `$saves\eden\saves` |
| Eden (profiles) | `$emus\eden-windows-msvc\user\nand\system\save\8000000000000010\su\avators` | `$saves\eden\profiles` |
| Citron | `$emus\citron-windows-msvc\user\nand\user\save` | `$saves\citron\saves` |
| Dolphin | `$emus\Dolphin-x64\User\GC`, `...\Wii`, `...\StateSaves` | `$saves\dolphin\GC`, `\Wii`, `\StateSaves` |
| Cemu | `$emus\cemu\mlc01\usr\save` | `$saves\Cemu\saves` |
| RPCS3 | `$E\storage\rpcs3\dev_hdd0\home\00000001\savedata` (+ `\trophy`) | `$saves\rpcs3\saves` (+ `\trophy`) |
| PPSSPP | `$emus\PPSSPP\memstick\PSP\SAVEDATA` (+ `\PSP\PPSSPP_STATE`) | `$saves\ppsspp\saves` (+ `\states`) |
| RetroArch | `$emus\RetroArch\saves` (+ `\states`) | `$saves\retroarch\saves` (+ `\states`) |
| PCSX2 | `$emus\pcsx2\memcards` (+ savestates) | `$saves\pcsx2\saves` (+ `\states`) |
| DuckStation | `$emus\duckstation\memcards` (+ savestates) | `$saves\duckstation\saves` (+ `\states`) |
| Vita3K | `$E\storage\Vita3K\ux0\user\00\savedata` | `$saves\Vita3K\saves` |
| mGBA | `$emus\mgba` save/savestate dirs | `$saves\mgba\saves` (+ `\states`) |
| melonDS | `$emus\melonDS` SRAM dir | `$saves\melonds\saves` |
| ShadPS4 | `$emus\ShadPS4-qt\user\savedata` | `$saves\shadps4\saves` |
| Xenia | `$emus\xenia` content dir | `$saves\xenia\saves` |

Config-driven emulators (RetroArch, PCSX2, DuckStation, mGBA) may instead have
their **config files** point at `$saves\<emu>` directly — either is fine as long
as the files land in `$saves\<emu>`.

If any junction is missing/wrong, re-run **EmuDeck → Reset config** for that
emulator (or re-run EmuDeck Setup), then re-verify.

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
Cemu) to prove the junction-based ones work, not just Eden.

---

## 4. Pass criteria (all must be true)

- [ ] `rclone.conf` URL uses the real NextCloud username (no literal `USERNAME`).
- [ ] `rclone lsd Emudeck-NextCloud:Emudeck/saves/` lists the emu folders.
- [ ] Every junction in the table above points at `$saves\<emu>`.
- [ ] RPCS3 `/dev_hdd0/` and Vita3K `ux0\app` point at `$E\storage\<emu>\...`
      on both OSes (games installed once, shared).
- [ ] A save written on Windows shows up on Linux (and vice-versa) via the NAS.
- [ ] EmuDeck Cloud Saves uploads/downloads complete with no `409 Conflict` /
      `fail_upload` markers (check `$saves\<emu>\.fail_upload` is absent).
- [ ] After an EmuDeck update/Setup, re-run this checklist (Setup can recreate
      broken junctions or the bad rclone URL).

---

## Troubleshooting

- **Cloud sync 409 errors** → the `rclone.conf` URL (see section 1).
- **A junction shows `broken` (dangling target)** → the NAS wasn't mounted when
  it was created. Remount, then Reset config for that emulator.
- **Save appears in both `storage\` and `saves\`** → an old split copy. Let the
  Linux engine (or a Reset config) merge them; newest-wins is applied.
- **Windows can't see Linux-created files** → check the NAS mount (SMB/NFS) has
  `saves\` readable/writable; the junctions on Windows just need the target to
  be mounted at the same drive letter every boot.

# EmuDeck cross-device save sharing

Make every emulator's save data physically live under `<Emulation>/saves/<emu>`
on a NAS shared between **Windows and Linux**, so any machine reads/writes the
same files and EmuDeck Cloud Saves backs them all up. Generic and data-driven:
adding a new emulator is one line in `setup/emudeck/emulators.conf` — no logic
changes.

```
Windows            Z:\Emulation\saves\<emu>\...        (same files)
Linux              /mnt/emulation/Emulation\saves\<emu>\...
NAS  (one root)    <Emulation>/saves/<emu>/
EmuDeck Cloud      Emudeck/saves/<emu>/   (rclone, synced from $savesPath)
```

## Preflight: establish the path mapping first

**Agent preflight: ask the user for the Windows share/drive and the Linux mount
before changing anything.** Never infer one OS's path from the other. Record the
equivalents for the machine you are on:

| Role | Windows | Linux |
|---|---|---|
| NAS share | `\\192.168.0.3\myPlex` | wherever the same share is mounted (e.g. `/mnt/emulation`) |
| Emulation root | `Z:\Emulation` | `<Linux mount>/Emulation` |
| Saves | `Z:\Emulation\saves` | `<Emulation>/saves` |
| Shared storage | `Z:\Emulation\storage` | `<Emulation>/storage` |

The Windows drive letter is only a mount of the same share. The Windows check
script prints both the drive-letter and UNC forms before testing anything. If a
mapping is unknown, **ask the user**; do not guess it.

PowerShell displays a network symlink's target as `UNC\server\share\...` even
though the real target is `\\server\share\...`. That is the same path — never
compare raw `.Target` strings against a drive-letter path.

## Why this is needed

EmuDeck's Linux backend puts some emulators' saves somewhere else:

| Situation | Emulators | Consequence |
|---|---|---|
| Saves inside a big internal tree the emulator hardcodes | eden/citron (Switch `nand/user/save`), Cemu (`mlc01/usr/save`), Vita3K (`ux0/user/00/savedata`), RPCS3 (`dev_hdd0/.../savedata`) | EmuDeck Linux symlinks `saves/<emu>` → `storage/<emu>/...` (inverted). Each OS writes its own copy → split saves. |
| Saves in a local dir (flatpak user dir) | Dolphin (GC/Wii/StateSaves), PPSSPP (`PSP/SAVEDATA`, `PPSSPP_STATE`), RetroArch (`saves`/`states`), DuckStation (`memcards`/`savestates`) | Saves never reach the NAS at all, or `saves/<emu>` is a symlink back to the local dir. |
| Config-driven save path | PCSX2, mGBA, melonDS | Mostly fine once the config points at `savesPath`; the engine still enforces the physical dirs. |

The fix for every case is the same idea Windows already uses:
**the emulator's save path resolves to a physical folder in `saves/<emu>/`**.
On Linux that's a symlink; on Windows EmuDeck uses a symbolic link in
network-install mode (a junction cannot target a UNC path) or the config path.
Merges are newest-wins per file and NFS-safe (no chown, which NFS `sec=sys`
rejects).

## The engine

- `setup/emudeck/emudeck-crossdevice-saves.sh` — generic, idempotent, NFS-safe.
- `setup/emudeck/emulators.conf` — one line per emulator.

Line format (see the conf file header for the full reference):

```
emu|target_rel|from_paths|config_edits|options|storage_rel|storage_links|storage_config_edits
```

| Field | Meaning |
|---|---|
| `emu` | emulator id; also the folder under `<Emulation>/saves/` (and `storage/<emu>/`) |
| `target_rel` | physical folder under `<Emulation>/saves/` (e.g. `dolphin/GC`) |
| `from_paths` | `;`-separated paths that must resolve to the target (become symlinks). Normally an emulator-side dir; a stale alias under `saves/` is also allowed (used to collapse `saves/dolphin/StateSaves` into `states`). Use `${EMU_ROOT}` / `${HOME}`. `-`/empty = none. |
| `config_edits` | `;`-separated `configfile=key`; the key is set to the target path (config backed up as `*.crossdevice.bak`). Both `key = value` and `key: value` (vfs.yml-style) are handled. `-`/empty = none. |
| `options` | `win_priority` → keep existing target data (Windows authoritative, e.g. Eden); archive anything found at `from_paths` instead of merging. Otherwise merged newest-wins. |
| `storage_rel` | subpath under `<Emulation>/storage/<emu>/` that holds **shared game data** (installs), e.g. RPCS3 `dev_hdd0`, Vita3K `ux0/app`. `-`/empty = none. |
| `storage_links` | `;`-separated emulator-side dirs that must resolve to the storage target (symlink; existing data merged newest-wins). |
| `storage_config_edits` | `;`-separated `configfile=key` whose value is the storage target (e.g. RPCS3's `vfs.yml=/dev_hdd0/`). |

Config key matching is case-insensitive (PCSX2 writes `Savestates`, EmuDeck's
own scripts write `SaveStates`) and the existing key spelling is preserved. If
a key is missing from a sectioned INI, the engine prints a warning instead of
appending it to the wrong section.

### Adding a new emulator

1. Saves live at a fixed emulator-internal path → add a row with `from_paths`.
2. Saves are configurable → add a row with `config_edits`.
3. Emulator installs games into an internal dir (RPCS3 `dev_hdd0`, Vita3K
   `ux0/app`, ShadPS4 userdata, ...) → fill in the `storage_*` fields so that
   dir physically lives in `<Emulation>/storage/<emu>/` and every machine
   shares it (install once, play everywhere, no duplicate game storage).
4. Multiple install variants (Flatpak **and** AppImage/native) → list **all**
   their paths/config files in the row (`;`-separated). The engine handles each
   variant; whichever one is used resolves to the same shared target.

The engine creates the physical target, merges any existing data there, and
turns the emulator-side path into a symlink to it (or sets the config key).
Re-running is a no-op.

## Running it

On a new machine, after EmuDeck's first Setup:

```bash
# from this repo
setup/emudeck/emudeck-crossdevice-saves.sh --check         # report only; writes nothing
setup/emudeck/emudeck-crossdevice-saves.sh                 # auto-detects Emulation root from EmuDeck settings
setup/emudeck/emudeck-crossdevice-saves.sh /path/to/Emulation   # or be explicit
```

`--check` prints, for every row: whether the NAS target is a real dir or a
symlink, where each `from_paths` entry currently points, and the current value
of each config key. Use it first on a new Linux machine (or after an EmuDeck
update) to see what is actually broken before changing anything.

### Migrating a machine that already ran an older version

If this Linux machine already ran the engine before the Dolphin/RetroArch/Xenia
fixes, run these three commands in order:

```bash
cd ~/.scripts
setup/emudeck/emudeck-crossdevice-saves.sh --check   # read-only; shows the old layout
setup/emudeck/emudeck-crossdevice-saves.sh           # applies the fixes (idempotent)
setup/emudeck/emudeck-crossdevice-saves.sh --check   # should show no [check] fix lines

# refresh the copy EmuDeck runs at the end of every Setup
mkdir -p ~/.config/EmuDeck/custom_scripts
cp setup/emudeck/emudeck-crossdevice-saves.sh setup/emudeck/emulators.conf ~/.config/EmuDeck/custom_scripts/
chmod +x ~/.config/EmuDeck/custom_scripts/emudeck-crossdevice-saves.sh
```

The last three commands matter for persistence: without them, the next EmuDeck
Setup runs the **old** engine/conf from `custom_scripts` and can restore the
old Dolphin/RetroArch layout. `setup/lib.sh` does this copy automatically when
`emudeck_crossdevice_saves` runs.

Expected old-layout lines in the first `--check` (the second command fixes
them):

- `[dolphin] .../saves/dolphin/StateSaves` — Windows uses
  `saves/dolphin/states`; the run merges any `StateSaves` data into `states`
  and leaves `saves/dolphin/StateSaves` as a symlink to it.
- `[retroarch] ... target is a symlink: ...` — EmuDeck's inverted
  `saves/retroarch/... -> local flatpak dir` link. The run moves the data to
  the NAS and links the local dir back to the NAS target.
- `[xenia] ... target is a symlink: ...` — same for
  `roms/xbox360/content` / `~/.local/share/Xenia/content`.

If those lines are absent, this machine was already in the new layout; the
normal run is still safe and idempotent. Do not run EmuDeck Setup between the
commands (Setup runs this engine itself at the end). No emulator Reset config
is needed on Linux.

It is also wired into `setup/fresh_install.sh` → `setup/lib.sh`
(`emudeck_crossdevice_saves`, called after EmuDeck install), and **installed
into `~/.config/EmuDeck/custom_scripts/`** so every EmuDeck Setup re-applies it.
EmuDeck updates overwrite its `backend/` scripts but never `custom_scripts/`,
so this survives updates. To re-apply manually after a Setup that ran before
the engine was installed, just run the script again (idempotent).

### Persistence and tested versions

- **Linux:** `setup/lib.sh` copies the engine and `emulators.conf` to
  `~/.config/EmuDeck/custom_scripts/`; EmuDeck runs that directory at the end
  of Setup and does not overwrite it. If you change the repo copies, re-run
  `emudeck_crossdevice_saves` or copy the two files again to refresh the hook.
- **Windows:** `setup/emudeck/emudeck-windows-fix.ps1 -Install` copies the fix
  to `%APPDATA%\EmuDeck\crossdevice\` and adds a marked block to the
  `CurrentUserAllHosts` PowerShell profile. Every EmuDeck launcher loads that
  profile, so the `settings.ps1` patch is re-applied even after EmuDeck
  regenerates it. Remove with `-Uninstall`.
- **Never patch `EmuDeck/backend/`.** EmuDeck runs `git fetch`/`git reset
  --hard` on that tree at the start of every emulator launch, so backend edits
  disappear. The engine lives in `custom_scripts/`; the Windows fix lives in
  `settings.ps1`, `%APPDATA%\emudeck\emu_versions.json`, and the profile.

| Component | Version validated |
|---|---|
| EmuDeck for Windows app | `2.7.1.0` |
| EmuDeck update check reported | `v2.7.2-unstable.138` |
| Windows EmuDeck backend commit | `c4350af` |
| EmuDeck Linux upstream `main` inspected | `0c212a84c624cef443a6c14784810db84165fd9d` (2026-11-12) |

The Windows fix is pattern-based and reports `already patched` / `could not
find the $testdrive=New-PSDrive line` rather than damaging a newer
`settings.ps1`. The Linux engine is data-driven and does not depend on a
specific EmuDeck release; see `setup/emudeck-windows.md` for the Windows
version-check commands and the exact launcher errors.

### Windows side

Windows needs no new layout script: EmuDeck for Windows creates **symbolic
links** in network-install mode from each emulator's save dir to
`<Emulation>\saves\<emu>` on the NAS (it does not use junctions, because a
junction cannot target a UNC path). The link itself must live on local NTFS;
Windows cannot create a symlink **on** an SMB share. The config-driven
emulators point at the same NAS paths in drive-letter form.

Install the launcher/settings fix once (it survives EmuDeck updates). If you
prefer not to install the profile hook, run the plain command after each Setup
instead:

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -Install
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -CheckOnly
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-fix.ps1 -Uninstall
```

It fixes EmuDeck's temporary-Z:-PSDrive shadowing (which makes
`Set-Content $savesPath/.watching` resolve to a duplicated UNC path) and creates
the missing `%APPDATA%\emudeck\emu_versions.json`. See
`setup/emudeck-windows.md` for the exact errors and the harmless ones it leaves
alone (`git` stderr, `hideMe`).

The repo's `setup/emudeck/emudeck-windows-check.ps1` is the verification helper:

```powershell
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-check.ps1
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-check.ps1 -CheckOnly
powershell -ExecutionPolicy Bypass -File setup\emudeck\emudeck-windows-check.ps1 -Fix
```

If `emudeck-windows-fix.ps1` is next to the checker, the checker runs it
automatically before checking (unless `-CheckOnly` is passed).

It prints the Windows drive -> UNC mapping first, then checks every save/state
link and the mGBA/melonDS config paths. `-CheckOnly` skips the rclone URL fix
and all repairs; `-Fix` re-points a genuinely wrong link (merging files that
live under `saves\`).

Two things to remember on Windows:

1. **Same `rclone.conf`**: the NAS `tools/rclone/rclone.conf` is shared by both
   OSes — make sure the NextCloud URL uses your real username
   (`https://your.host/remote.php/dav/files/<username>/`, not a literal
   `USERNAME`). A bad URL makes every cloud sync fail with 409s.
2. **Dolphin savestates use `saves\dolphin\states`** (Windows naming). The
   emulator-side directory is still `...\Dolphin-x64\User\StateSaves`; only the
   NAS folder name is `states`, and the Linux engine targets the same folder.
   The checker reports it as `OK`.

### Known limits

- **xemu** (Xbox) stores saves inside its HDD image — not per-file; share the
  whole image if you want those cross-device.
- **RPCS3/Vita3K cloud saves on SMB**: their `savedata`/`trophy` links are
  supposed to live inside `storage\...` on the NAS, but Windows cannot create a
  symlink **on** an SMB share (only on local NTFS pointing at a UNC target).
  Local cross-device sharing still works through `storage` (RPCS3 VFS /
  Vita3K `pref-path`); EmuDeck Cloud Saves misses those saves unless the POSIX
  symlink is created on Linux and the SMB server follows server-side symlinks.
  The Windows checker reports these three as `LIMITATION`.
- **ShadPS4**: savedata is wired (`~/.local/share/shadPS4/savedata` →
  `saves/shadps4/saves`). Its game-install dirs (`storage/shadps4/games`,
  `storage/shadps4/dlc`) are not wired yet; add them with the `storage_*`
  fields using the same pattern as RPCS3/Vita3K below.
- **Frontends** (ES-DE gamelists, scraped media) are per-machine by design; the
  engine only touches emulator saves.
- Emulators with their own cloud-save/account storage (e.g. certain retroarch
  cores) are unaffected.

### Shared game storage (installs)

Emulators that install games into an internal dir share that dir on the NAS so
games are installed **once** and every machine uses them — no duplicate
storage. Encoded generically via the `storage_*` row fields (not hardcoded):

- **RPCS3**: `storage\rpcs3\dev_hdd0` (both OSes' EmuDeck point `dev_hdd0`
  there via vfs.yml; the engine enforces the vfs.yml key and symlinks any local
  copy into storage).
- **Vita3K**: `storage\Vita3K\ux0\app` (Windows symlinks
  `roms\psvita\InstalledGames` to it; the engine mirrors that symlink on Linux).
- **ShadPS4**: same pattern once added.

> ⚠️ Only run one machine at a time against shared game storage (RPCS3's
> `dev_hdd0`, Vita3K's `ux0\app`): the emulators hold DB caches there and two
> instances writing at once can corrupt. Saves (`saves\...`) are fine to touch
> from one machine at a time too for the same reason.

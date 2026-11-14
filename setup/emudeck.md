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

## Why this is needed

EmuDeck's Linux backend puts some emulators' saves somewhere else:

| Situation | Emulators | Consequence |
|---|---|---|
| Saves inside a big internal tree the emulator hardcodes | eden/citron (Switch `nand/user/save`), Cemu (`mlc01/usr/save`), Vita3K (`ux0/user/00/savedata`), RPCS3 (`dev_hdd0/.../savedata`) | EmuDeck Linux symlinks `saves/<emu>` → `storage/<emu>/...` (inverted). Each OS writes its own copy → split saves. |
| Saves in a local dir (flatpak user dir) | Dolphin (GC/Wii/StateSaves), PPSSPP (`PSP/SAVEDATA`, `PPSSPP_STATE`) | Saves never reach the NAS at all. |
| Config-driven save path | RetroArch, PCSX2, DuckStation, mGBA | Already fine once the config points at `savesPath`. |

The fix for every case is the same idea Windows already uses (junction):
**the emulator's save path resolves to a physical folder in `saves/<emu>/`**.
On Linux that's a symlink; on Windows it's a junction or the config path.
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
| `from_paths` | `;`-separated emulator-side paths that must resolve to the target (become symlinks). Use `${EMU_ROOT}` / `${HOME}`. `-`/empty = none. |
| `config_edits` | `;`-separated `configfile=key`; the key is set to the target path (config backed up as `*.crossdevice.bak`). Both `key = value` and `key: value` (vfs.yml-style) are handled. `-`/empty = none. |
| `options` | `win_priority` → keep existing target data (Windows authoritative, e.g. Eden); archive anything found at `from_paths` instead of merging. Otherwise merged newest-wins. |
| `storage_rel` | subpath under `<Emulation>/storage/<emu>/` that holds **shared game data** (installs), e.g. RPCS3 `dev_hdd0`, Vita3K `ux0/app`. `-`/empty = none. |
| `storage_links` | `;`-separated emulator-side dirs that must resolve to the storage target (symlink; existing data merged newest-wins). |
| `storage_config_edits` | `;`-separated `configfile=key` whose value is the storage target (e.g. RPCS3's `vfs.yml=/dev_hdd0/`). |

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
setup/emudeck/emudeck-crossdevice-saves.sh                 # auto-detects Emulation root from EmuDeck settings
setup/emudeck/emudeck-crossdevice-saves.sh /path/to/Emulation   # or be explicit
```

It is also wired into `setup/fresh_install.sh` → `setup/lib.sh`
(`emudeck_crossdevice_saves`, called after EmuDeck install), and **installed
into `~/.config/EmuDeck/custom_scripts/`** so every EmuDeck Setup re-applies it.
EmuDeck updates overwrite its `backend/` scripts but never `custom_scripts/`,
so this survives updates. To re-apply manually after a Setup that ran before
the engine was installed, just run the script again (idempotent).

### Windows side

Windows needs no new script: EmuDeck for Windows already junctions Switch
emulator save paths to `saves\<emu>`, and the config-driven emulators point at
the same NAS paths (drive-letter form). Two checks on Windows:

1. **Same `rclone.conf`**: the NAS `tools/rclone/rclone.conf` is shared by both
   OSes — make sure the NextCloud URL uses your real username
   (`https://your.host/remote.php/dav/files/<username>/`, not a literal
   `USERNAME`). A bad URL makes every cloud sync fail with 409s.
2. **Emulators write to `saves\<emu>`**: after running EmuDeck's Windows setup,
   confirm e.g. `saves\eden\saves`, `saves\dolphin\GC`, `saves\Cemu\saves`
   receive new files.

### Known limits

- **xemu** (Xbox) stores saves inside its HDD image — not per-file; share the
  whole image if you want those cross-device.
- **ShadPS4**: not wired yet (the engine already covers its `savedata` link and
  the save folder; when you bring it in, add its game-install dir to the
  `storage_*` fields using the same pattern as RPCS3/Vita3K below).
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

#!/usr/bin/env bash
# emudeck-crossdevice-saves.sh
#
# Generic, data-driven enforcer for cross-device EmuDeck save sharing.
#
# Goal: on a NAS-backed Emulation directory shared between Windows and Linux
# (same root on both OSes, e.g.  Z:\Emulation  on Windows and
#  /mnt/emulation/Emulation  on Linux), every emulator's SAVE data must
# physically live under  <Emulation>/saves/<emu>/  so that:
#   - any machine (Windows or Linux) reads/writes the same files, and
#   - EmuDeck cloud saves (which sync $savesPath) cover everything.
#
# It ALSO enforces shared GAME STORAGE: emulators that install games into an
# internal dir (RPCS3's dev_hdd0, Vita3K's ux0/app, ...) should keep that dir
# in <Emulation>/storage/<emu>/ so games are installed once and shared by every
# machine (no duplicate downloads/installs). This is generic too: it's driven
# by the same per-line definitions, not hardcoded per emulator.
#
# Emulators are described declaratively in the companion file emulators.conf,
# one line per emulator. Adding a new emulator = adding one line. Nothing here
# is hardcoded to a specific emulator. See emudeck.md for the full write-up.
#
# Line format (emulators.conf):
#   emu|target_rel|from_paths|config_edits|options|storage_rel|storage_links|storage_config_edits
#   emu          emulator id; also the folder under <Emulation>/saves/ (and
#                storage/<emu>/ for shared game data)
#   target_rel   physical folder under <Emulation>/saves/ that holds the saves
#   from_paths   ';'-separated emulator-side paths that must resolve to the
#                target (they become symlinks). Use "${EMU_ROOT}"/"${HOME}".
#                '-'/empty = none.
#   config_edits ';'-separated "configfile=key" entries. The key is set to the
#                target path (config backed up). Both "key = value" and
#                "key: value" (vfs.yml-style) separators are handled.
#                '-'/empty = none.
#   options      ';'-separated: win_priority  -> keep existing target data
#                (Windows authoritative), archive real dirs at from_paths
#                instead of merging. Otherwise merged newest-wins.
#   storage_rel  subpath under <Emulation>/storage/<emu>/ that holds shared
#                game data (e.g. "dev_hdd0", "ux0/app"). '-'/empty = none.
#   storage_links emulator-side dirs that must resolve to the storage target
#                (symlink; existing data merged newest-wins). '-'/empty = none.
#   storage_config_edits config edits (configfile=key) whose value is the
#                storage target. '-'/empty = none.
#
# Examples:
#   eden|eden/saves|${EMU_ROOT}/storage/eden/nand/user/save|-|win_priority|-|-|-
#   rpcs3|rpcs3/saves|${EMU_ROOT}/storage/rpcs3/dev_hdd0/home/00000001/savedata|-|-|dev_hdd0|${HOME}/.config/rpcs3/dev_hdd0|${HOME}/.config/rpcs3/vfs.yml=/dev_hdd0/
#
# Usage:
#   emudeck-crossdevice-saves.sh [EMU_ROOT] [SAVES_CONF]
#     EMU_ROOT    the Emulation root. Default: read from EmuDeck settings.sh.
#     SAVES_CONF  path to emulators.conf. Default: next to this script.
#
# Idempotent and NFS-safe (copies preserve content+mtime+mode without chown,
# which NFS sec=sys rejects). Safe to run at any time; also installed into
# ~/.config/EmuDeck/custom_scripts/ so it runs after every EmuDeck Setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Resolve the Emulation root
# ---------------------------------------------------------------------------
EMU_ROOT="${1:-}"
if [ -z "$EMU_ROOT" ]; then
    if [ -f "$HOME/.config/EmuDeck/settings.sh" ]; then
        # settings.sh uses quoted-string concatenation, e.g.
        #   emulationPath="/var/mnt/macadamia/plex"/Emulation
        # so grab everything up to the last quote and strip all quotes.
        EMU_ROOT="$(sed -n 's/^emulationPath="\(.*\)$/\1/p' "$HOME/.config/EmuDeck/settings.sh" | head -n1 | tr -d '"')"
    fi
fi
EMU_ROOT="${EMU_ROOT%/}"
if [ -z "$EMU_ROOT" ] || [ ! -d "$EMU_ROOT" ]; then
    echo "ERROR: cannot find the Emulation root (got '$EMU_ROOT')."
    echo "       Pass it explicitly: $(basename "$0") /path/to/Emulation"
    exit 1
fi
# sanity: an Emulation root contains saves/storage/roms
if [ ! -d "$EMU_ROOT/saves" ] && [ ! -d "$EMU_ROOT/storage" ] && [ ! -d "$EMU_ROOT/roms" ]; then
    echo "ERROR: '$EMU_ROOT' does not look like an Emulation root (no saves/storage/roms)."
    echo "       Pass it explicitly: $(basename "$0") /path/to/Emulation"
    exit 1
fi
SAVES_ROOT="$EMU_ROOT/saves"
STORAGE_ROOT="$EMU_ROOT/storage"

CONF="${2:-$SCRIPT_DIR/emulators.conf}"
[ -f "$CONF" ] || { echo "ERROR: definitions file not found: $CONF"; exit 1; }

# ---------------------------------------------------------------------------
# NFS-safe copy helper: content + mtime + mode, no chown.
# ---------------------------------------------------------------------------
nfs_copy() {
    local src="$1" dst="$2"
    cp "$src" "$dst" 2>/dev/null || cp "$src" "$dst"
    touch -r "$src" "$dst" 2>/dev/null || true
    chmod --reference="$src" "$dst" 2>/dev/null || true
}

# newest-wins merge of $src tree into $dst tree (NFS-safe)
merge_newest_wins() {
    local src="${1%/}" dst="${2%/}"
    [ -d "$src" ] || return 0
    mkdir -p "$dst"
    local f rel
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        if [ -f "$dst/$rel" ]; then
            if [ "$f" -nt "$dst/$rel" ]; then
                mkdir -p "$(dirname "$dst/$rel")"
                nfs_copy "$f" "$dst/$rel"
            fi
        else
            mkdir -p "$(dirname "$dst/$rel")"
            nfs_copy "$f" "$dst/$rel"
        fi
    done < <(find "$src" -type f -print0 2>/dev/null)
}

# make $from a symlink to $target, preserving any existing data (newest-wins)
enforce_link() {
    local from="$1" target="$2" win_priority="$3"
    [ -n "$from" ] || return 0
    mkdir -p "$(dirname "$from")"
    # The target must be a real directory (the physical home of the data).
    # If it is currently a symlink (inverted layout), drop the link first.
    [ -L "$target" ] && unlink "$target"
    mkdir -p "$target"
    if [ -L "$from" ]; then
        # already a link; repoint it (idempotent)
        ln -snf "$target" "$from"
        echo "  link ok: $from -> $target"
    elif [ -d "$from" ]; then
        if [ "$win_priority" = "1" ]; then
            echo "  win_priority: archiving existing data at $from (Windows stays authoritative)"
            local archive_dir
            archive_dir="$STORAGE_ROOT/_crossdevice-archive/$(date +%Y%m%d%H%M%S)"
            mkdir -p "$archive_dir"
            mv "$from" "$archive_dir/$(basename "$from")"
        else
            echo "  merging existing data at $from into $target (newest wins)"
            merge_newest_wins "$from" "$target"
            rm -rf "$from"
        fi
        ln -snf "$target" "$from"
        echo "  linked: $from -> $target"
    else
        ln -snf "$target" "$from"
        echo "  linked: $from -> $target"
    fi
}

# point a config key at a path (backed up). Handles both "key = value" (ini)
# and "key: value" (vfs.yml-style) separators, preserving the existing style.
# No-op when the key already resolves to the target (keeps working configs
# untouched, e.g. values with a trailing slash).
enforce_config() {
    local cfg="$1" key="$2" target="$3"
    [ -n "$cfg" ] || return 0
    [ -f "$cfg" ] || { echo "  config not found (skip): $cfg"; return 0; }
    # backup once per config (timestamped)
    local bak="${cfg}.crossdevice.bak"
    [ -f "$bak" ] || cp "$cfg" "$bak"

    local sep="="
    if grep -qE "^\s*${key}\s*:" "$cfg"; then sep=": "; fi
    local quote=""
    if grep -qE "^\s*${key}\s*${sep}\s*\"" "$cfg"; then quote='"'; fi

    # already pointing at the target? leave it alone (path-normalized compare)
    local cur tgt_norm
    cur="$(grep -E "^\s*${key}\s*(=|:)\s*.*" "$cfg" | head -n1 \
           | sed -E "s#^\s*${key}\s*(=|:)\s*##")"
    cur="${cur%\"}"; cur="${cur#\"}"
    tgt_norm="${target%/}"
    if [ -n "$cur" ] && { [ "$cur" = "$tgt_norm" ] || [ "$cur" = "$tgt_norm/" ]; }; then
        echo "  config ok (already set): $cfg : $key = $target"
        return 0
    fi

    if grep -qE "^\s*${key}\s*(=|:)" "$cfg"; then
        sed -i -E "s#^(\s*${key}\s*(=|:)\s*).*#\1${quote}${target}${quote}#" "$cfg"
    else
        printf '\n%s%s"%s"\n' "$key" "$sep" "$target" >> "$cfg"
    fi
    echo "  config set: $cfg : $key $sep $target"
}

# ---------------------------------------------------------------------------
# Process definitions
# ---------------------------------------------------------------------------
echo "=== EmuDeck cross-device layout (root: $EMU_ROOT) ==="
mkdir -p "$SAVES_ROOT"

while IFS='|' read -r emu target_rel from_paths config_edits options storage_rel storage_links storage_config_edits; do
    [ -n "$emu" ] || continue
    case "$emu" in \#*) continue ;; esac
    for var in emu target_rel from_paths config_edits options storage_rel storage_links storage_config_edits; do
        eval "$var=\"\${$var//\\\$\{EMU_ROOT\}/$EMU_ROOT}\""
        eval "$var=\"\${$var//\\\$\{HOME\}/$HOME}\""
    done

    # ---- saves ----
    target="$SAVES_ROOT/$target_rel"
    win_priority=0
    case ";$options;" in *";win_priority;"*) win_priority=1 ;; esac
    echo "[$emu] saves target: $target"

    IFS=';' read -r -a froms <<< "$from_paths"
    for f in "${froms[@]:-}"; do
        [ -n "$f" ] && [ "$f" != "-" ] && enforce_link "$f" "$target" "$win_priority"
    done

    IFS=';' read -r -a cfgs <<< "$config_edits"
    for c in "${cfgs[@]:-}"; do
        [ -n "$c" ] && [ "$c" != "-" ] || continue
        enforce_config "${c%%=*}" "${c#*=}" "$target"
    done

    # ---- shared game storage (installs) ----
    if [ -n "$storage_rel" ] && [ "$storage_rel" != "-" ]; then
        storage_target="$STORAGE_ROOT/$emu/$storage_rel"
        echo "[$emu] shared game storage: $storage_target"
        mkdir -p "$(dirname "$storage_target")" "$storage_target"

        IFS=';' read -r -a slinks <<< "$storage_links"
        for s in "${slinks[@]:-}"; do
            [ -n "$s" ] && [ "$s" != "-" ] && enforce_link "$s" "$storage_target" 0
        done

        IFS=';' read -r -a scfgs <<< "$storage_config_edits"
        for s in "${scfgs[@]:-}"; do
            [ -n "$s" ] && [ "$s" != "-" ] || continue
            enforce_config "${s%%=*}" "${s#*=}" "$storage_target"
        done
    fi
done < "$CONF"

echo "=== done ==="

#!/bin/bash
# Export this device's Plasma (KDE) theme + panel configuration into the repo
# as code, so it can be committed and reproduced/migrated.
#
# Plasma 6 stores the active panel layout and per-panel plasmoids in
# ~/.config/plasma-org.kde.plasma.desktop-appletsrc, general theme/colors in
# ~/.config/kdeglobals, window decorations in ~/.config/kwinrc, and installed
# color schemes / global themes (look-and-feel) under ~/.local/share/plasma and
# ~/.local/share/color-schemes. This script copies a curated, non-secret subset
# into dotfiles/kde/ (mirroring the paths) so you can commit them.
#
# Usage:
#   # On the KDE Bazzite/Plasma device, from a clone of the dotfiles repo:
#   ~/.scripts/setup/bazzite/kde-config-export.sh
#   # then commit the files that land under dotfiles/kde/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DST="$REPO_ROOT/dotfiles/kde"
mkdir -p "$DST"

# -- ~/.config files (panel/plasmoids, general settings, window mgr) ----------
# Hostname-scope these so a multi-device repo doesn't merge blindly.
HOST="${HOST:-$(hostname)}"
CONF="$DST/hosts/$HOST/.config"
mkdir -p "$CONF"

copy_cfg() {
    local src="$1"
    [ -f "$src" ] || return 0
    mkdir -p "$CONF/$(dirname "$src")"
    cp -f "$src" "$CONF/$src"
    echo "  $src"
}

copy_cfg "plasma-org.kde.plasma.desktop-appletsrc"   # panels + plasmoids + wallpaper
copy_cfg "kdeglobals"                                 # color scheme, fonts, general
copy_cfg "kwinrc"                                     # window decorations / effects
copy_cfg "kwinrulesrc"                                # per-window rules
copy_cfg "plasmashellrc"
copy_cfg "plasmarc"

# -- local/share assets (color schemes, look-and-feel) -------------------------
SHARE="$DST/hosts/$HOST/.local/share"
for d in "color-schemes" "plasma/look-and-feel" "plasma/layout-templates" "plasma/plasmoids" "fonts" "konsole"; do
    [ -e "$HOME/.local/share/$d" ] || continue
    mkdir -p "$SHARE/$(dirname "$d")"
    cp -a "$HOME/.local/share/$d" "$SHARE/$d"
    echo "  .local/share/$d"
done

echo ""
echo "KDE config exported to: $DST"
echo "Review it (scan for any private data), then commit. To apply later, copy"
echo "dotfiles/kde/hosts/<host>/.config/* back into a target's ~/.config."
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
# Privacy / redaction:
#   - Aborts if any source config looks like it contains a secret
#     (password / token / api key), so secrets can't silently slip in.
#   - Rewrites absolute home paths (/home/...) to ~/ so the committed config
#     is portable and does not leak your username.
#   - Known caveat: the whole-dir copies under .local/share (plasmoids,
#     konsole, fonts) are copied verbatim. Most user data lives elsewhere, but
#     review them by eye — e.g. clipboard/history or notes plasmoids could put
#     copied secrets under plasma/plasmoids if installed.
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

# Refuse to export a config that might hold a secret.
SECRET_RE='(password|passwd|token|api[_-]?key|apikey|secret|bearer|refresh_token|client_secret)'
for f in plasma-org.kde.plasma.desktop-appletsrc kdeglobals kwinrc kwinrulesrc plasmashellrc plasmarc; do
    src="$HOME/.config/$f"
    [ -f "$src" ] || continue
    if grep -qiE "$SECRET_RE" "$src"; then
        echo "ABORT: '$src' looks like it may contain a secret (password/token/api key)." >&2
        echo "Review and redact it before enabling export." >&2
        exit 1
    fi
done

copy_cfg() {
    local name="$1"
    local src="$HOME/.config/$name"
    [ -f "$src" ] || return 0
    mkdir -p "$CONF/$(dirname "$name")"
    cp -f "$src" "$CONF/$name"
    # Scrub absolute home paths so committed config stays portable + username-free.
    sed -i "s|$HOME/|~/|g; s|/home/$USER/|~/|g" "$CONF/$name"
    echo "  $name"
}

copy_cfg "plasma-org.kde.plasma.desktop-appletsrc"   # panels + plasmoids + wallpaper
copy_cfg "kdeglobals"                                 # color scheme, fonts, general
copy_cfg "kwinrc"                                     # window decorations / effects
copy_cfg "kwinrulesrc"                                # per-window rules
copy_cfg "plasmashellrc"
copy_cfg "plasmarc"

# -- local/share assets (color schemes, look-and-feel) -------------------------
# NOTE: copied verbatim (cp -a). Most runtime/user data is NOT here, but review
# anything under plasma/plasmoids or konsole for accidentally-copied secrets.
# `fonts` is intentionally excluded: it's ~25 MB of binary TTFs. Install fonts
# via the image/package layer instead, not by committing binaries.
SHARE="$DST/hosts/$HOST/.local/share"
for d in "color-schemes" "plasma/look-and-feel" "plasma/layout-templates" "plasma/plasmoids" "konsole"; do
    [ -e "$HOME/.local/share/$d" ] || continue
    mkdir -p "$SHARE/$(dirname "$d")"
    cp -a "$HOME/.local/share/$d" "$SHARE/$d"
    echo "  .local/share/$d"
done

echo ""
echo "KDE config exported to: $DST"
echo "Review it (scan for any private data), then commit. To apply later, copy"
echo "dotfiles/kde/hosts/<host>/.config/* back into a target's ~/.config."
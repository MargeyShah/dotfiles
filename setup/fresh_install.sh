#!/bin/bash
# Unified install script for server / desktop / disney (work) profiles.
# Auto-detects OS: mac (brew), wsl (apt), ubuntu (apt).
# Bazzite is detected but NOT handled here — it is image-based (rpm-ostree) and
# uses a flatpak-first + Ubuntu-Distrobox model; run setup/fresh_install_bazzite.sh
# instead (this script refuses to run on it). The Bazzite bootstrap does re-run
# this script *inside* its Ubuntu Distrobox with `--profile dotfiles`, so the
# container toolchain uses this exact code path rather than a bespoke copy.
#
# Granular failure handling: each step is tracked, overwritten files are
# backed up to a temp dir, and the temp dir is only removed on full success.
#
# Shared helpers, the OOP app framework, and dotfile_setup() live in
# setup/lib.sh (sourced below). App objects are app_<name>() functions that
# each own their OS branching, install method, and role gating. Profiles are
# just ordered lists of app names run through the install_apps dispatcher.
#
# Usage:
#   fresh_install.sh                      # interactive menu
#   fresh_install.sh --profile dotfiles   # skip the menu (used by Bazzite)
#   fresh_install.sh --yes                # skip the confirmation prompt
#   fresh_install.sh --nvim               # only refresh the nvim config

set -o pipefail
set -eE
# Unmatched globs expand to nothing instead of a literal `*`.
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ---------- Arguments ----------
PROFILE=""
ASSUME_YES="no"
NVIM_ONLY="no"
while [ $# -gt 0 ]; do
    case "$1" in
        --profile=*) PROFILE="${1#*=}" ;;
        --profile)
            [ $# -ge 2 ] || { echo "--profile needs a value"; exit 1; }
            PROFILE="$2"; shift ;;
        --yes|-y) ASSUME_YES="yes" ;;
        --nvim)   NVIM_ONLY="yes" ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# ---------- Main ----------
if [[ $(id -u) -eq 0 ]]; then
    echo "This script should not be run as root."
    exit 1
fi

# On-the-fly nvim-handroll pull only (works on every OS, including Bazzite).
if [ "$NVIM_ONLY" = "yes" ]; then
    nvim_handroll
    exit 0
fi

# Bazzite is image-based (rpm-ostree); its install model is flatpak-first plus
# an Ubuntu Distrobox, not apt/brew on the host. Send the user to the right script.
if [[ "$FAMILY" == "bazzite" ]]; then
    echo "This script does not manage Bazzite (image-based / rpm-ostree)."
    echo "Use instead: ${SCRIPT_DIR}/fresh_install_bazzite.sh"
    exit 1
fi

# Clean any leftover temp dir from a previous (failed) run, then start fresh.
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

if [ -z "$PROFILE" ]; then
    display_menu
    case "$choice" in
        1) PROFILE="server" ;;
        2) PROFILE="desktop" ;;
        3) PROFILE="disney" ;;
        4) PROFILE="dotfiles" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

case "$PROFILE" in
    server|desktop|disney|dotfiles) ;;
    *) echo "Invalid profile: ${PROFILE} (expected server|desktop|disney|dotfiles)"; exit 1 ;;
esac

if [ "$ASSUME_YES" != "yes" ]; then
    read -rp "Do you want to continue? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Script aborted."
        exit 1
    fi
fi

case "$PROFILE" in
    server)
        dotfile_setup
        install_server
        [[ "$OS" == "ubuntu" ]] && remove_snap
        ;;
    desktop)
        dotfile_setup
        install_desktop
        [[ "$OS" == "ubuntu" ]] && remove_snap
        ;;
    disney)
        dotfile_setup
        install_disney
        ;;
    dotfiles)
        dotfile_setup
        ;;
esac

# Set zsh as default shell (non-fatal: user can change manually if it fails)
step "final: chsh"
if [[ "$SHELL" != *zsh* ]]; then
    chsh -s "$(which zsh)" 2>/dev/null || echo "WARN: could not set zsh as default shell (run 'chsh -s \$(which zsh)' manually)"
fi

# Success: remove temp dir (including backups)
rm -rf "$TEMP_DIR"
echo "Done! Restart terminal."

#!/bin/bash
# Single fresh-install entrypoint for every host.
#
# Auto-detects the OS family and runs the matching flow:
#
#   mac / wsl / ubuntu  apt/brew install on the host, by profile:
#                         server    -> deps + server apps (+ snap removal)
#                         desktop   -> deps + desktop apps (+ snap removal)
#                         disney    -> deps + work-Mac apps
#                         dotfiles  -> deps + dotfiles only
#
#   bazzite             image-based (rpm-ostree): the host is untouched apart
#                       from flatpak/brew/ujust work. The apt CLI toolchain
#                       lives in an Ubuntu Distrobox, provisioned by re-running
#                       this script inside it with the chosen profile:
#                         "Unix PC" -> host extras + box --profile desktop
#                         dotfiles  -> host core + box --profile dotfiles
#                       Inside the box, host-only GUI apps (GUI_APPS) are
#                       skipped, so the profile is the apt CLI toolchain only.
#
# Granular failure handling: each step is tracked, overwritten files are
# backed up to a temp dir, and the temp dir is only removed on full success.
#
# Shared helpers, the OOP app framework, app objects, profiles, dotfiles,
# Bazzite host steps and the menu all live in setup/lib.sh (sourced below).
#
# Usage:
#   fresh_install.sh                      # interactive menu
#   fresh_install.sh --profile dotfiles    # skip the menu
#   fresh_install.sh --yes                # skip the confirmation prompt
#   fresh_install.sh --nvim               # only refresh the nvim config
#   fresh_install.sh --no-gaming          # Bazzite: skip EmuDeck/Decky
#   fresh_install.sh --no-extras          # Bazzite: skip ujust/brew extras

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
# Bazzite gaming/system extras are on by default: every target host is a gaming
# host. The flags are harmless on the other families (they are only consulted by
# bazzite_desktop_extras).
GAMING_EXTRAS="yes"
SYSTEM_EXTRAS="yes"
while [ $# -gt 0 ]; do
    case "$1" in
        --profile=*) PROFILE="${1#*=}" ;;
        --profile)
            [ $# -ge 2 ] || { echo "--profile needs a value"; exit 1; }
            PROFILE="$2"; shift ;;
        --yes|-y)      ASSUME_YES="yes" ;;
        --nvim)        NVIM_ONLY="yes" ;;
        --no-gaming)   GAMING_EXTRAS="no" ;;
        --no-extras)   SYSTEM_EXTRAS="no" ;;
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

# Temp/step-log dir must exist before lib.sh's ERR trap can reference STEP_LOG.
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

if [ -z "$PROFILE" ]; then
    display_menu
fi

case "$PROFILE" in
    server|desktop|disney|dotfiles) ;;
    *) echo "Invalid profile: ${PROFILE} (expected server|desktop|disney|dotfiles)"; exit 1 ;;
esac

if [[ "$FAMILY" == "bazzite" ]]; then
    case "$PROFILE" in
        server|disney)
            echo "Profile '${PROFILE}' does not apply to Bazzite."
            echo "Bazzite is an image-based gaming desktop; use 'Unix PC' (desktop) or 'dotfiles'."
            exit 1
            ;;
    esac
fi

if [ "$ASSUME_YES" != "yes" ]; then
    read -rp "Do you want to continue? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Script aborted."
        exit 1
    fi
fi

if [[ "$FAMILY" == "bazzite" ]]; then
    # Host work first (so the box can be created), then the extras tier, then
    # provision the container by re-running this script inside it. A Distrobox
    # shares $HOME, so the dotfiles it symlinks are the host's too.
    bazzite_core
    if [[ "$PROFILE" == "desktop" ]]; then
        bazzite_desktop_extras
    fi
    provision_container "$PROFILE"

    # Success: remove temp dir (including backups).
    rm -rf "$TEMP_DIR"
    echo "Done! Enter the toolchain with 'distrobox enter ${CONTAINER_NAME}' (or run 'box')."
    if rpm-ostree status 2>/dev/null | grep -q 'ghcr.io/margeyshah/bazzite'; then
        echo ""
        echo "NOTE: CoolerControl (liquidctl + coolercontrol) ships in the image as an"
        echo "      rpm-ostree layer. Reboot to activate it:  systemctl reboot"
    fi
    exit 0
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

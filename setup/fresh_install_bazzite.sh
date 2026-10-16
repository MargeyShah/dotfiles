#!/bin/bash
# Bazzite fresh-install / bootstrap.
#
# Bazzite is an image-based (rpm-ostree) Fedora atomic OS. It is NOT managed
# like the apt/brew hosts that fresh_install.sh targets:
#
#   * Host software is FLATPAK-FIRST. GUI apps come from Flathub; the host is
#     never modified with rpm-ostree layers / dnf / copr by this script.
#   * The apt-based CLI toolchain lives in an Ubuntu Distrobox container, which
#     becomes the default terminal. (Distrobox + Podman ship with Bazzite.)
#   * Containerised services use Podman/Quadlet, not Docker. `podman-docker` is
#     baked into the custom image so the `docker` CLI works against Podman.
#
# This script assumes the machine has already been rebased onto the custom
# image built from MargeyShah/bazzite (which bakes in the flatpaks + files +
# signing + podman-docker). It then:
#
#   1. verifies it is running on Bazzite (and warns if not on the custom image),
#   2. installs the host GUI apps as flatpaks (idempotent; mirrors the image),
#   3. creates the Ubuntu Distrobox container,
#   4. provisions the container with the CLI toolchain (container_provision.sh),
#   5. makes the container the default terminal,
#   6. symlinks the dotfiles on the host (dotfile_config from lib.sh).
#
# App objects and helpers are shared with fresh_install.sh via setup/lib.sh.

set -o pipefail
set -eE
# Unmatched globs expand to nothing instead of a literal `*`.
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

CONTAINER_NAME="bazzite-ubuntu"
DISTROBOX_INI="${SCRIPT_DIR}/bazzite/distrobox.ini"
CONTAINER_PROVISION="${SCRIPT_DIR}/bazzite/container_provision.sh"

# Flathub IDs mirroring the desktop GUI apps from the apt profiles. GUI apps are
# flatpaks on Bazzite, so these replace the element/vscode apt repo installs.
# Keep this list in sync with default-flatpaks in the MargeyShah/bazzite recipes.
DESKTOP_FLATPAKS=(
    im.riot.Riot                     # Element
    com.visualstudio.code            # Visual Studio Code
    org.signal.Signal                # Signal Desktop
    dev.vencord.Vesktop              # Vesktop (Discord)
    com.plexamp.Plexamp              # Plexamp
    sh.ppy.osu                       # osu! (lazer)
    com.github.mtkennerly.ludusavi   # Ludusavi (save backups)
    com.heroicgameslauncher.hgl      # Heroic Games Launcher
    it.mijorus.gearlever             # Gear Lever (AppImage manager)
    org.prismlauncher.PrismLauncher  # Prism Launcher (Minecraft)
    info.cemu.Cemu                   # Cemu (Wii U)
    net.rpcs3.RPCS3                  # RPCS3 (PS3)
    org.DolphinEmu.dolphin-emu       # Dolphin (GameCube/Wii)
    dev.goats.xivlauncher            # XIVLauncher (FFXIV)
)

# Apps with no Flathub package, installed as AppImages and integrated via Gear
# Lever. Format: "owner/repo|display-name|asset-filename-regex".
# (Playnite is intentionally absent: there is no Linux build.)
APPIMAGE_APPS=(
    "imputnet/helium-linux|Helium|helium-.*-x86_64\.AppImage$"
    "wimpysworld/sidra|Sidra|Sidra-linux-x86_64\.AppImage$"
)

# ---------- Guards ----------

if [[ $(id -u) -eq 0 ]]; then
    echo "This script should not be run as root."
    exit 1
fi

if [[ "$FAMILY" != "bazzite" ]]; then
    echo "This script is for Bazzite only (detected: ${OS})."
    echo "For mac/wsl/ubuntu use: ${SCRIPT_DIR}/fresh_install.sh"
    exit 1
fi

if ! pkg_exists distrobox; then
    echo "ERROR: distrobox not found. It ships with Bazzite; is this a stock image?"
    exit 1
fi

# Warn (do not fail) if the host is not on the custom image — flatpaks still
# install, but podman-docker and the signing policy come from that image.
if command -v rpm-ostree >/dev/null 2>&1; then
    if ! rpm-ostree status 2>/dev/null | grep -qiE 'ghcr\.io/margeyshah/bazzite'; then
        echo "WARN: this host does not look like it is rebased to the MargeyShah/bazzite image."
        echo "      podman-docker et al. may be missing. See the image README to rebase."
    fi
fi

# Temp/step-log dir must exist before lib.sh's ERR trap can reference STEP_LOG.
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# ---------- Steps ----------

# Host GUI apps as flatpaks (flatpak-first; no rpm layering).
install_flatpaks() {
    step "bazzite: flatpaks"
    command -v flatpak >/dev/null 2>&1 || { echo "WARN: flatpak missing; skipping flatpaks"; return 0; }

    # Ensure Flathub is configured (Bazzite enables it by default).
    if ! flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi

    local app
    for app in "${DESKTOP_FLATPAKS[@]}"; do
        if flatpak info "$app" >/dev/null 2>&1; then
            echo "flatpak already installed: $app"
        else
            flatpak install -y --noninteractive flathub "$app"
        fi
    done
}

# Resolve the download URL of the newest release asset matching a regex.
resolve_asset_url() {
    local repo="$1" pattern="$2"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep -oE '"browser_download_url": *"[^"]+"' \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | grep -E "$pattern" \
        | head -n1
}

# Apps without a Flathub package, installed as AppImages and integrated into the
# app menu via Gear Lever (it.mijorus.gearlever). Idempotent: skips if present.
install_appimages() {
    step "bazzite: appimages"
    [ "${#APPIMAGE_APPS[@]}" -eq 0 ] && return 0
    command -v flatpak >/dev/null 2>&1 || { echo "WARN: flatpak missing; skipping AppImages"; return 0; }

    mkdir -p "$HOME/Applications"
    local entry repo name pattern url dest
    for entry in "${APPIMAGE_APPS[@]}"; do
        IFS='|' read -r repo name pattern <<<"$entry"
        dest="$HOME/Applications/${name}.AppImage"
        if [ -f "$dest" ]; then
            echo "AppImage already installed: $name"
        else
            url="$(resolve_asset_url "$repo" "$pattern")"
            if [ -z "$url" ]; then
                echo "WARN: no AppImage asset matching '$pattern' in ${repo}; skipping $name"
                continue
            fi
            echo "Downloading $name from $url"
            curl -fL "$url" -o "$dest"
            chmod +x "$dest"
        fi

        # Integrate into the app menu + update checks with Gear Lever.
        if flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
            flatpak run it.mijorus.gearlever --integrate "$dest" 2>/dev/null \
                || echo "WARN: Gear Lever could not integrate $name (open Gear Lever manually)"
        else
            echo "WARN: Gear Lever not installed; $name left unintegrated in $HOME/Applications"
        fi
    done
}

# Gaming extras installed via Bazzite's own `ujust` targets (not flatpaks, not
# baked into the image). Opt-in because they are gaming/Game-Mode specific:
#   - EmuDeck  : `ujust get-emudeck install` (installs an AppImage + wizard)
#   - Decky    : `ujust setup-decky install` (only useful in Steam Game Mode)
# Both are interactive-capable but support a non-interactive action argument.
install_gaming_extras() {
    step "bazzite: gaming extras (emudeck, decky)"
    command -v ujust >/dev/null 2>&1 || { echo "WARN: ujust not found; skipping EmuDeck/Decky"; return 0; }

    # EmuDeck (status prints 'install' or 'uninstall').
    if ujust get-emudeck status 2>/dev/null | grep -qx install; then
        echo "EmuDeck already installed."
    else
        ujust get-emudeck install || echo "WARN: EmuDeck install failed (run 'ujust get-emudeck' manually)"
    fi

    # Decky Loader (status prints 'install'/'install-prerelease'/'uninstall').
    if ujust setup-decky status 2>/dev/null | grep -q install; then
        echo "Decky Loader already installed."
    else
        ujust setup-decky install || echo "WARN: Decky install failed (run 'ujust setup-decky' manually)"
    fi
}

# Verify the podman-docker shim (baked into the custom image) so `docker` works.
install_podman_docker() {
    step "bazzite: podman-docker"
    if pkg_exists docker; then
        echo "docker CLI present (podman-docker shim)."
        return 0
    fi
    echo "WARN: 'docker' CLI not found. It is baked into the MargeyShah/bazzite image"
    echo "      via podman-docker. To add it manually: sudo rpm-ostree install podman-docker && systemctl reboot"
}

# Create (idempotently) the Ubuntu Distrobox container.
create_container() {
    step "bazzite: distrobox container"
    if distrobox list 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
        echo "distrobox container '$CONTAINER_NAME' already exists."
        return 0
    fi
    if [ -f "$DISTROBOX_INI" ]; then
        distrobox assemble create --file "$DISTROBOX_INI"
    else
        distrobox create --name "$CONTAINER_NAME" --image ubuntu:24.04 --yes
    fi
}

# Provision the toolchain inside the container.
provision_container() {
    step "bazzite: distrobox provision"
    if [ ! -f "$CONTAINER_PROVISION" ]; then
        echo "WARN: $CONTAINER_PROVISION missing; skipping in-container provisioning."
        return 0
    fi
    distrobox enter "$CONTAINER_NAME" -- bash "$CONTAINER_PROVISION"
}

# Make the container the default terminal by auto-entering it from an
# interactive host shell. Marker-guarded so re-runs don't duplicate it.
set_default_terminal() {
    step "bazzite: default terminal"
    local rc="$HOME/.bashrc"
    local begin="# >>> bazzite distrobox terminal >>>"
    local end="# <<< bazzite distrobox terminal <<<"

    if [ -f "$rc" ] && grep -qF "$begin" "$rc"; then
        echo "default-terminal snippet already present in $rc"
        return 0
    fi

    {
        echo ""
        echo "$begin"
        echo "# Auto-enter the Ubuntu toolchain container for interactive shells."
        echo "# CONTAINER_ID is set once inside a distrobox, so this cannot recurse."
        echo "if [ -n \"\$PS1\" ] && [ -z \"\$CONTAINER_ID\" ] && command -v distrobox >/dev/null 2>&1; then"
        echo "    exec distrobox enter ${CONTAINER_NAME} -- zsh -l"
        echo "fi"
        echo "$end"
    } >> "$rc"
    echo "Added default-terminal snippet to $rc (takes effect in new shells)."
}

# ---------- Flow ----------

# Optional gaming extras (EmuDeck + Decky) via ujust. Non-interactive override:
#   ./fresh_install_bazzite.sh --gaming      (install them)
#   ./fresh_install_bazzite.sh --no-gaming   (skip them)
GAMING_EXTRAS="ask"
case "${1:-}" in
    --gaming)    GAMING_EXTRAS="yes" ;;
    --no-gaming) GAMING_EXTRAS="no"  ;;
esac

echo "Bazzite bootstrap"
echo "  container: ${CONTAINER_NAME}"
echo "  flatpaks:  ${DESKTOP_FLATPAKS[*]}"
echo "  appimages: ${APPIMAGE_APPS[*]}"
read -rp "Do you want to continue? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Script aborted."
    exit 1
fi

# Gaming extras are gaming/Game-Mode specific, so ask unless overridden by flag.
if [[ "$GAMING_EXTRAS" == "ask" ]]; then
    read -rp "Install gaming extras (EmuDeck + Decky Loader)? (y/n): " g
    if [[ "$g" == "y" || "$g" == "Y" ]]; then GAMING_EXTRAS="yes"; else GAMING_EXTRAS="no"; fi
fi

install_flatpaks
install_appimages
install_podman_docker
[[ "$GAMING_EXTRAS" == "yes" ]] && install_gaming_extras
create_container
provision_container
set_default_terminal

step "bazzite: dotfiles"
dotfile_config

# Success: remove temp dir (including backups).
rm -rf "$TEMP_DIR"
echo "Done! Open a new terminal to enter the ${CONTAINER_NAME} container."

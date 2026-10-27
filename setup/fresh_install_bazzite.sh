#!/bin/bash
# Bazzite fresh-install / bootstrap.
#
# Bazzite is an image-based (rpm-ostree) Fedora atomic OS. It is NOT managed
# like the apt/brew hosts that fresh_install.sh targets:
#
#   * Host software is FLATPAK-FIRST. GUI apps come from Flathub; the host is
#     never modified with rpm-ostree layers / dnf / copr by this script.
#   * The apt-based CLI toolchain lives in an Ubuntu Distrobox container, entered
#     on demand. (Distrobox + Podman ship with Bazzite.)
#   * Containerised services use Podman/Quadlet, not Docker. `podman-docker` is
#     baked into the custom image so the `docker` CLI works against Podman.
#
# This script assumes the machine has already been rebased onto the custom
# image built from MargeyShah/bazzite (which bakes in the flatpaks + files +
# signing + podman-docker). It then:
#
#   1. verifies it is running on Bazzite (and warns if not on the custom image),
#   2. installs the AppImage apps (Helium/Sidra) via Gear Lever,
#   3. installs gaming extras (EmuDeck, Decky + plugins) and system extras
#      (Proton Plus, Sunshine, Wake-on-LAN, Virtualization, CoolerControl, etc.),
#   4. grants Flameshot the screenshot portal permission,
#   5. installs zsh on the host via Homebrew and makes it the login shell,
#   6. creates the Ubuntu Distrobox container, and
#   7. provisions it by running the regular setup/fresh_install.sh inside the
#      container with `--profile dotfiles` (no bespoke provisioning script).
#
# Terminals are NOT modified: no Ptyxis profile is written and no shell rc file
# is touched. Enter the container on demand (`distrobox enter`, or the `box`
# fzf picker in dotfiles/zsh/config.zsh).
#
# This is deliberately a thin harness: everything declarative lives in the image
# (flatpaks, GNOME extensions + defaults, the Element keyring flatpak override,
# desktop gsettings), so the script only does per-user/post-install work and the
# container.
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

# Apps with no Flathub package, installed as AppImages and integrated via Gear
# Lever. Format: "owner/repo|display-name|asset-filename-regex".
# (Playnite is intentionally absent: there is no Linux build.)
APPIMAGE_APPS=(
    "imputnet/helium-linux|Helium|helium-.*-x86_64\.AppImage$"
    "wimpysworld/sidra|Sidra|Sidra-linux-x86_64\.AppImage$"
    "pkgforge-dev/ghostty-appimage|Ghostty|Ghostty-.*-x86_64\.AppImage$"
    # Vesktop's x86_64 asset has no arch suffix (arm64 does: -arm64.AppImage).
    "Vencord/Vesktop|Vesktop|Vesktop-[0-9.]+\.AppImage$"
)

# Decky Loader plugins to install from the Decky store (deckbrew), by store
# display name. Installed into ~/homebrew/plugins by verifying + extracting the
# store zip; no config is synced between machines.
DECKY_PLUGINS=(
    "CSS Loader"
    "SteamGridDB"
    "ProtonDB Badges"
    "HLTB for Deck"
    "TabMaster"
    "PlayCount"
    "IsThereAnyDeal for Deck"
    "Decky LSFG-VK"
    "AutoFlatpaks"
    "Decky Terminal"
    "Audio Loader"
    "Game Theme Music"
    "Quick Launch"
    "Volume Mixer"
    "EmuDecky"
    "MusicControl"
)
DECKY_STORE_URL="https://plugins.deckbrew.xyz/plugins"
DECKY_ARTIFACT_URL="https://cdn.tzatzikiweeb.moe/file/steam-deck-homebrew/versions"

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

# Grant Flameshot the screenshot portal so its hotkey/portal path works.
# This cannot live in the image: flatpak's permission store is per-user
# (~/.local/share/flatpak/db/<table>, a GVariant DB), with no system-wide
# equivalent, so it has to be written in the user's session.
grant_flameshot_portal() {
    step "bazzite: flameshot portal permission"
    command -v flatpak >/dev/null 2>&1 || { echo "WARN: flatpak missing; skipping Flameshot permission"; return 0; }
    if ! flatpak info org.flameshot.Flameshot >/dev/null 2>&1; then
        echo "WARN: Flameshot flatpak not installed; skipping portal permission"
        return 0
    fi
    # No --user/--system flag exists for permission-set; the store is per-user.
    flatpak permission-set screenshot screenshot org.flameshot.Flameshot yes \
        || echo "WARN: could not grant Flameshot the screenshot portal"
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
# app menu via Gear Lever (it.mijorus.gearlever).
#
# AppImages live in ~/AppImages (Gear Lever's own directory) and each step is
# checked independently, so a re-run only does what is missing:
#   * already integrated  -> nothing (Gear Lever's --list-installed status)
#   * downloaded, not yet -> integrate only
#   * neither             -> download, then integrate
install_appimages() {
    step "bazzite: appimages"
    [ "${#APPIMAGE_APPS[@]}" -eq 0 ] && return 0
    command -v flatpak >/dev/null 2>&1 || { echo "WARN: flatpak missing; skipping AppImages"; return 0; }

    mkdir -p "$HOME/AppImages"
    # Download + integrate from a staging dir. Gear Lever treats a byte-identical
    # file already sitting in its own ~/AppImages as "already integrated" and
    # then skips creating the .desktop entry, so files must be handed over from
    # somewhere else.
    local stage="$TEMP_DIR/appimages"
    mkdir -p "$stage"

    local entry repo name pattern url managed src
    for entry in "${APPIMAGE_APPS[@]}"; do
        IFS='|' read -r repo name pattern <<<"$entry"
        managed="$HOME/AppImages/${name,,}.appimage"
        src="$stage/${name}.AppImage"

        if appimage_integrated "$name"; then
            echo "AppImage already integrated: $name"
            continue
        fi

        # Step 1: obtain the file (staged, or moved out of Gear Lever's dir).
        if ! appimage_downloaded "$src"; then
            if appimage_downloaded "$managed"; then
                mv "$managed" "$src"
                echo "Re-integrating existing AppImage: $name"
            else
                url="$(resolve_asset_url "$repo" "$pattern")"
                if [ -z "$url" ]; then
                    echo "WARN: no AppImage asset matching '$pattern' in ${repo}; skipping $name"
                    continue
                fi
                echo "Downloading $name from $url"
                curl -fL "$url" -o "$src"
                chmod +x "$src"
            fi
        fi

        # Step 2: integrate into the app menu + update checks with Gear Lever.
        # --yes avoids Gear Lever's interactive "integrate? (y/N)" prompt, which
        # otherwise blocks (and appears to hang) the script.
        if flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
            flatpak run it.mijorus.gearlever --integrate --yes "$src" 2>/dev/null \
                || echo "WARN: Gear Lever could not integrate $name (open Gear Lever manually)"
        else
            echo "WARN: Gear Lever not installed; $name left unintegrated in $HOME/AppImages"
        fi
    done
}

# Gaming extras installed via Bazzite's own `ujust` targets (not flatpaks, not
# baked into the image). Always installed: every Bazzite host this targets is a
# gaming host. (Use --no-gaming to skip.)
#   - EmuDeck  : `ujust get-emudeck install` (installs an AppImage + wizard)
#   - Decky    : `ujust setup-decky install` (Decky Loader; used in Game Mode)
#   - Bazzite Buddy : `ujust get-decky-bazzite-buddy install` (changelog plugin)
# All are interactive-capable but expose a non-interactive action argument.
install_gaming_extras() {
    step "bazzite: gaming extras (emudeck, decky)"
    command -v ujust >/dev/null 2>&1 || { echo "WARN: ujust not found; skipping EmuDeck/Decky"; return 0; }

    # EmuDeck.
    if ujust_installed get-emudeck; then
        echo "EmuDeck already installed."
    else
        ujust get-emudeck install || echo "WARN: EmuDeck install failed (run 'ujust get-emudeck' manually)"
    fi

    # Decky Loader (status may be 'install' or 'install-prerelease').
    if ujust_installed setup-decky; then
        echo "Decky Loader already installed."
    else
        ujust setup-decky install || echo "WARN: Decky install failed (run 'ujust setup-decky' manually)"
    fi

    # Bazzite Buddy (official ublue changelog plugin; not in the deckbrew store,
    # so installed via its own ujust recipe into ~/homebrew/plugins/Bazzite Buddy).
    # It requires Decky Loader, so only install it once Decky is really present.
    if ! ujust_installed setup-decky; then
        echo "WARN: Decky Loader not installed; skipping Bazzite Buddy"
    elif ujust_installed get-decky-bazzite-buddy; then
        echo "Bazzite Buddy already installed."
    else
        ujust get-decky-bazzite-buddy install || echo "WARN: Bazzite Buddy install failed (run 'ujust get-decky-bazzite-buddy' manually)"
    fi
}

# Install Decky plugins from the Decky store (deckbrew). Each plugin zip is
# hash-verified (sha256 from the store index) and extracted into
# ~/homebrew/plugins; a plugin's top-level folder is a slug (e.g. SDH-CssLoader),
# so "already installed" is detected via the plugin.json "name" field
# (decky_plugin_installed in lib.sh).
# Fail-soft: any single plugin failing never aborts the run. No config sync.
install_decky_plugins() {
    step "bazzite: decky plugins"
    [ "${#DECKY_PLUGINS[@]}" -eq 0 ] && return 0
    command -v python3 >/dev/null 2>&1 || { echo "WARN: python3 missing; skipping Decky plugins"; return 0; }
    pkg_exists unzip || { echo "WARN: unzip missing; skipping Decky plugins"; return 0; }

    local plugins_dir="$HOME/homebrew/plugins"
    mkdir -p "$plugins_dir"

    local store_json="$TEMP_DIR/decky-store.json"
    if ! curl -fsSL "$DECKY_STORE_URL" -o "$store_json"; then
        echo "WARN: could not fetch Decky store; skipping plugin installs"
        return 0
    fi

    local name hash zip got
    for name in "${DECKY_PLUGINS[@]}"; do
        if decky_plugin_installed "$name"; then
            echo "Decky plugin already installed: $name"
            continue
        fi

        hash="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(next((p["versions"][0]["hash"] for p in d if p.get("name")==sys.argv[2]),""))' "$store_json" "$name")"
        if [ -z "$hash" ]; then
            echo "WARN: '$name' not found in Decky store; skipping"
            continue
        fi

        zip="$TEMP_DIR/decky-${hash:0:12}.zip"
        if ! curl -fsSL "${DECKY_ARTIFACT_URL}/${hash}.zip" -o "$zip"; then
            echo "WARN: download failed for Decky plugin: $name"; continue
        fi
        got="$(sha256sum "$zip" | awk '{print $1}')"
        if [ "$got" != "$hash" ]; then
            echo "WARN: checksum mismatch for Decky plugin: $name; skipping"
            rm -f "$zip"
            continue
        fi
        unzip -q -o "$zip" -d "$plugins_dir"
        rm -f "$zip"
        echo "Installed Decky plugin: $name"
    done
}

# System extras: hardware/gaming-adjacent tools Bazzite supports, applied via
# Bazzite's own ujust targets plus a couple of Homebrew casks. Always-on
# (skip with --no-extras). Note: CoolerControl is the one rpm-ostree layer.
install_system_extras() {
    step "bazzite: system extras"

    if command -v ujust >/dev/null 2>&1; then
        # Proton Plus (flatpak), Sunshine (flatpak) and CoolerControl (rpm) are
        # baked into the MargeyShah/bazzite image, so they are not installed here.
        # Wake-on-LAN (udev/systemd config; persists across reboots).
        ujust wol enable || echo "WARN: Wake-on-LAN failed (run 'ujust wol enable')"
        # Boot straight to Windows from a Steam launcher entry (dual-boot).
        ujust setup-boot-windows-steam || echo "WARN: boot-to-Windows failed (run 'ujust setup-boot-windows-steam')"
        # Virtualization (virt-manager flatpak + kargs + libvirtd); reboot needed.
        ujust setup-virtualization virt-on || echo "WARN: virtualization failed (run 'ujust setup-virtualization')"
        # Add the user to the 'input' group for controller drivers.
        ujust add-user-to-input-group add || echo "WARN: input group failed (run 'ujust add-user-to-input-group add')"
    else
        echo "WARN: ujust not found; skipping ujust-based system extras"
    fi

    # LM Studio + VSCodium: Bazzite ships them via Homebrew casks in ublue-os/tap.
    if brew_shellenv; then
        brew trust ublue-os/tap 2>/dev/null || true
        brew tap ublue-os/tap 2>/dev/null || true
        pkg_exists lm-studio || brew install --cask lm-studio-linux \
            || echo "WARN: LM Studio failed (run 'brew install --cask lm-studio-linux')"
        pkg_exists codium || brew install --cask vscodium-linux \
            || echo "WARN: VSCodium failed (run 'brew install --cask vscodium-linux')"
    else
        echo "WARN: Homebrew not found; skipping LM Studio + VSCodium"
    fi
}

# Host shell: zsh from Homebrew (never rpm-ostree; Bazzite ships Homebrew).
# There is no chsh on this image, so the login shell is changed with usermod.
install_host_zsh() {
    step "bazzite: host zsh"
    local brew_bin
    brew_bin="$(command -v brew 2>/dev/null || true)"
    [ -n "$brew_bin" ] || brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
    if [ ! -x "$brew_bin" ]; then
        echo "WARN: Homebrew not found at ${brew_bin} (Bazzite ships it)."
        echo "      Install/repair Homebrew (via ujust) and re-run; skipping host zsh."
        return 0
    fi

    # Put brew on PATH for this process (it is not in a plain login shell's PATH).
    eval "$("$brew_bin" shellenv)" || true

    if brew list zsh >/dev/null 2>&1; then
        echo "zsh already installed via Homebrew."
    else
        brew install zsh || { echo "WARN: 'brew install zsh' failed"; return 0; }
    fi

    local zsh_path
    zsh_path="$(brew --prefix)/bin/zsh"
    if [ ! -x "$zsh_path" ]; then
        echo "WARN: zsh not found at ${zsh_path}; not changing the login shell."
        return 0
    fi

    # PAM/login only accept shells listed in /etc/shells.
    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null \
            && echo "Added ${zsh_path} to /etc/shells."
    fi

    if command -v chsh >/dev/null 2>&1; then
        sudo chsh -s "$zsh_path" "$(id -un)" \
            || echo "WARN: 'chsh -s ${zsh_path}' failed"
    else
        sudo usermod -s "$zsh_path" "$(id -un)" \
            || echo "WARN: 'usermod -s ${zsh_path}' failed"
    fi
    echo "Host login shell is now ${zsh_path} (takes effect on next login)."
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

# Provision the container by running the regular fresh_install.sh inside it with
# the dotfiles-only profile. The container reuses the exact same OOP app
# framework as every other host (no bespoke provisioning script), and because a
# Distrobox shares $HOME the symlinks it writes are the host's too.
provision_container() {
    step "bazzite: container provision (fresh_install.sh --profile dotfiles)"
    distrobox enter "$CONTAINER_NAME" -- \
        bash "$SCRIPT_DIR/fresh_install.sh" --profile dotfiles --yes
}

# ---------- Flow ----------

# Gaming + system extras are always installed: every Bazzite host this targets
# is a gaming host. Escape hatches: --no-gaming, --no-extras.
GAMING_EXTRAS="yes"
SYSTEM_EXTRAS="yes"
for arg in "$@"; do
    case "$arg" in
        --no-gaming) GAMING_EXTRAS="no" ;;
        --no-extras) SYSTEM_EXTRAS="no" ;;
    esac
done

echo "Bazzite bootstrap"
echo "  container: ${CONTAINER_NAME}"
echo "  appimages: ${APPIMAGE_APPS[*]}"
echo "  decky:     ${DECKY_PLUGINS[*]}"
read -rp "Do you want to continue? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Script aborted."
    exit 1
fi

install_appimages
install_podman_docker
install_host_zsh
grant_flameshot_portal
if [[ "$GAMING_EXTRAS" == "yes" ]]; then
    install_gaming_extras
    install_decky_plugins
fi
[[ "$SYSTEM_EXTRAS" == "yes" ]] && install_system_extras
create_container
# Container provisioning also symlinks the dotfiles (shared $HOME), so there is
# no separate host-side dotfile_config step.
provision_container

# Success: remove temp dir (including backups).
rm -rf "$TEMP_DIR"
echo "Done! Enter the toolchain with 'distrobox enter ${CONTAINER_NAME}' (or run 'box')."
if rpm-ostree status 2>/dev/null | grep -q 'ghcr.io/margeyshah/bazzite'; then
    echo ""
    echo "NOTE: CoolerControl (liquidctl + coolercontrol) ships in the image as an"
    echo "      rpm-ostree layer. Reboot to activate it:  systemctl reboot"
fi

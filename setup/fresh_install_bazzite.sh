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
#   2b. installs the AppImage apps (Helium/Sidra) via Gear Lever,
#   3. installs gaming extras (EmuDeck, Decky + plugins) and system extras
#      (Proton Plus, Sunshine, Wake-on-LAN, Virtualization, CoolerControl, etc.),
#   4. creates the Ubuntu Distrobox container,
#   5. provisions the container with the CLI toolchain (container_provision.sh),
#   6. makes the container the default terminal (Ptyxis custom command; switch via `dbt`),
#   7. symlinks the dotfiles on the host (dotfile_config from lib.sh).
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
    io.github.jeffshee.Hidamari      # Hidamari (video wallpaper)
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

    # Element needs to reach the Secret Service (keyring) for its secret storage.
    if flatpak info im.riot.Riot >/dev/null 2>&1; then
        flatpak override --user \
            --talk-name=org.freedesktop.secrets \
            im.riot.Riot \
            || echo "WARN: could not apply Element keyring override"
    fi
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
        # --yes avoids Gear Lever's interactive "integrate? (y/N)" prompt, which
        # otherwise blocks (and appears to hang) the script.
        if flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
            flatpak run it.mijorus.gearlever --integrate --yes "$dest" 2>/dev/null \
                || echo "WARN: Gear Lever could not integrate $name (open Gear Lever manually)"
        else
            echo "WARN: Gear Lever not installed; $name left unintegrated in $HOME/Applications"
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

    # EmuDeck (status prints 'install' or 'uninstall').
    if ujust get-emudeck status 2>/dev/null | grep -qx install; then
        echo "EmuDeck already installed."
    else
        ujust get-emudeck install || echo "WARN: EmuDeck install failed (run 'ujust get-emudeck' manually)"
    fi

    # Decky Loader (status prints 'install'/'install-prerelease'/'uninstall').
    # Exact-match so the 'uninstall' status is not mistaken for installed.
    if ujust setup-decky status 2>/dev/null | grep -qxE 'install(-prerelease)?'; then
        echo "Decky Loader already installed."
    else
        ujust setup-decky install || echo "WARN: Decky install failed (run 'ujust setup-decky' manually)"
    fi

    # Bazzite Buddy (official ublue changelog plugin; not in the deckbrew store,
    # so installed via its own ujust recipe into ~/homebrew/plugins/Bazzite Buddy).
    # It requires Decky Loader, so only install it once Decky is really present.
    if ! ujust setup-decky status 2>/dev/null | grep -qxE 'install(-prerelease)?'; then
        echo "WARN: Decky Loader not installed; skipping Bazzite Buddy"
    elif ujust get-decky-bazzite-buddy status 2>/dev/null | grep -qx install; then
        echo "Bazzite Buddy already installed."
    else
        ujust get-decky-bazzite-buddy install || echo "WARN: Bazzite Buddy install failed (run 'ujust get-decky-bazzite-buddy' manually)"
    fi
}

# True (0) if a Decky plugin with this store display name is already installed.
decky_plugin_installed() {
    local want="$1"
    python3 - "$HOME/homebrew/plugins" "$want" <<'PY'
import glob, json, sys
for f in glob.glob(sys.argv[1] + "/*/plugin.json"):
    try:
        if json.load(open(f)).get("name") == sys.argv[2]:
            sys.exit(0)
    except Exception:
        pass
sys.exit(1)
PY
}

# Install Decky plugins from the Decky store (deckbrew). Each plugin zip is
# hash-verified (sha256 from the store index) and extracted into
# ~/homebrew/plugins; a plugin's top-level folder is a slug (e.g. SDH-CssLoader),
# so "already installed" is detected via the plugin.json "name" field.
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
        # Proton Plus (flatpak) — Proton/Wine version manager.
        ujust get-protonplus || echo "WARN: Proton Plus failed (run 'ujust get-protonplus')"
        # Sunshine game-streaming host (flatpak).
        ujust setup-sunshine enable-flatpak || echo "WARN: Sunshine failed (run 'ujust setup-sunshine')"
        # Wake-on-LAN (udev/systemd config; persists across reboots).
        ujust wol enable || echo "WARN: Wake-on-LAN failed (run 'ujust wol enable')"
        # Boot straight to Windows from a Steam launcher entry (dual-boot).
        ujust setup-boot-windows-steam || echo "WARN: boot-to-Windows failed (run 'ujust setup-boot-windows-steam')"
        # Virtualization (virt-manager flatpak + kargs + libvirtd); reboot needed.
        ujust setup-virtualization virt-on || echo "WARN: virtualization failed (run 'ujust setup-virtualization')"
        # Add the user to the 'input' group for controller drivers.
        ujust add-user-to-input-group add || echo "WARN: input group failed (run 'ujust add-user-to-input-group add')"
        # CoolerControl fan/pump curves — LAYERS rpm packages (liquidctl,
        # coolercontrol) and needs a reboot. The deliberate extra rpm exception.
        ujust install-coolercontrol install || echo "WARN: CoolerControl failed (run 'ujust install-coolercontrol')"
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

# Host-side desktop tweaks applied on the Bazzite HOST (not in the Distrobox:
# the container shares $HOME but not the host D-Bus/dconf session, so gsettings
# run there would not reach the host GNOME session). Each entry is a full
# command line; append more lines to add tweaks without touching the runner.
# Run before the container is created/configured, so it happens while the
# script is still firmly in the host shell.
HOST_CONFIG_CMDS=(
    "gsettings set org.gnome.desktop.wm.preferences focus-new-windows 'smart'"
    "gsettings set org.gnome.desktop.wm.preferences auto-raise true"
)

# Run each HOST_CONFIG_CMDS entry, fail-soft (one bad command never aborts the
# run) and report what happened.
apply_host_config() {
    step "bazzite: host config"
    [ "${#HOST_CONFIG_CMDS[@]}" -eq 0 ] && return 0

    local cmd
    for cmd in "${HOST_CONFIG_CMDS[@]}"; do
        echo "host config: $cmd"
        if eval "$cmd" 2>&1; then
            :
        else
            echo "WARN: host config command failed: $cmd"
        fi
    done
}

# Make the container the default terminal via Ptyxis's profile "Use Custom
# Command" (Bazzite's documented shell-swap pattern). The custom command is the
# full `distrobox enter <box> -- zsh -l`, with default-container left at the
# host ("session"/"My Computer").
#
# IMPORTANT (Bazzite docs + bazzite#3283): setting default-container to a
# distrobox AND using a custom command to force a shell do NOT combine — the
# distrobox agent reads the host's SHELL (bash) and ignores the custom shell, so
# terminals land in bash. The working approach is: host container + full
# `distrobox enter ... -- zsh -l` in the custom command.
#
# This also replaces an older approach that appended an `exec distrobox enter
# ...` block to ~/.bashrc; that block is removed here so existing installs
# migrate. Switching terminals remains the `dbt` fzf menu (dotfiles/zsh/config.zsh).
set_default_terminal() {
    step "bazzite: default terminal"

    # --- 1. Migrate: strip the old ~/.bashrc auto-entry block, if present. ---
    local rc="$HOME/.bashrc"
    local begin="# >>> bazzite distrobox terminal >>>"
    local end="# <<< bazzite distrobox terminal <<<"
    if [ -f "$rc" ] && grep -qF "$begin" "$rc"; then
        awk -v b="$begin" -v e="$end" '
            $0 == b { skip = 1; next }
            $0 == e { skip = 0; next }
            !skip   { print }
        ' "$rc" > "${rc}.tmp" && mv "${rc}.tmp" "$rc"
        echo "Removed old distrobox-terminal block from $rc (Ptyxis handles it now)."
    fi
    # Drop the sentinel toggled by the old db-off/db-on-style hooks.
    rm -f "$HOME/.no-distrobox"

    # --- 2. Configure Ptyxis's default profile (host + custom command). ---
    # These settings live on the HOST (dconf), so route through the host when the
    # script is running inside a Distrobox; otherwise apply directly.
    local run_on_host
    if command -v dconf >/dev/null 2>&1; then
        run_on_host() { "$@"; }
    elif command -v host-spawn >/dev/null 2>&1; then
        run_on_host() { host-spawn "$@"; }
    else
        echo "WARN: no dconf/host-spawn; cannot configure Ptyxis default profile."
        echo "      Manually: Ptyxis Preferences -> Profile -> Use Custom Command = 'distrobox enter ${CONTAINER_NAME} -- zsh -l'"
        return 0
    fi

    # New Ptyxis (>= 46) stores profile settings under /org/gnome/Ptyxis/Profiles/
    # keyed by UUID; query the default profile UUID rather than hard-coding it.
    local profile_uuid
    profile_uuid="$(run_on_host dconf read /org/gnome/Ptyxis/default-profile-uuid 2>/dev/null \
        | tr -d \"\' \ 2>/dev/null || true)"
    # Strip the single-quotes dconf uses for string values.
    profile_uuid="$(printf '%s' "$profile_uuid" | sed "s/^'//; s/'$//")"

    if [ -z "$profile_uuid" ]; then
        echo "WARN: could not determine Ptyxis default profile; not configuring it."
        echo "      Manually: Ptyxis Preferences -> Profile -> Use Custom Command = 'distrobox enter ${CONTAINER_NAME} -- zsh -l'"
        return 0
    fi

    # Configure a "session" profile that runs the container via a custom command
    # (see the function docstring above for why default-container stays "session").
    local ok=1
    run_on_host dconf write "/org/gnome/Ptyxis/Profiles/${profile_uuid}/default-container" "'session'" 2>/dev/null || ok=0
    run_on_host dconf write "/org/gnome/Ptyxis/Profiles/${profile_uuid}/use-custom-command" "true" 2>/dev/null || ok=0
    run_on_host dconf write "/org/gnome/Ptyxis/Profiles/${profile_uuid}/custom-command" "'distrobox enter ${CONTAINER_NAME} -- zsh -l'" 2>/dev/null || ok=0
    run_on_host dconf write "/org/gnome/Ptyxis/Profiles/${profile_uuid}/login-shell" "false" 2>/dev/null || ok=0

    if [ "$ok" -eq 1 ]; then
        echo "Set Ptyxis default profile '${profile_uuid}' to enter ${CONTAINER_NAME} (zsh -l)."
        echo "New terminals will open in the ${CONTAINER_NAME} container (run 'dbt' to switch)."
    else
        echo "WARN: failed to fully configure the Ptyxis profile. Set it manually:"
        echo "      Ptyxis Preferences -> Profile -> 'Use Custom Command' = 'distrobox enter ${CONTAINER_NAME} -- zsh -l'."
    fi
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
echo "  flatpaks:  ${DESKTOP_FLATPAKS[*]}"
echo "  appimages: ${APPIMAGE_APPS[*]}"
echo "  decky:     ${DECKY_PLUGINS[*]}"
read -rp "Do you want to continue? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Script aborted."
    exit 1
fi

# Host-side desktop tweaks first: they must run on the host (not in the
# container) and before distrobox is configured.
apply_host_config
install_flatpaks
install_appimages
install_podman_docker
if [[ "$GAMING_EXTRAS" == "yes" ]]; then
    install_gaming_extras
    install_decky_plugins
fi
[[ "$SYSTEM_EXTRAS" == "yes" ]] && install_system_extras
create_container
provision_container
set_default_terminal

step "bazzite: dotfiles"
dotfile_config

# Success: remove temp dir (including backups).
rm -rf "$TEMP_DIR"
echo "Done! New terminals open in the ${CONTAINER_NAME} container (run 'dbt' to switch to the host shell or another box)."

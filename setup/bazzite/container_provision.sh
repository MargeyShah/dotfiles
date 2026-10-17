#!/bin/bash
# Runs INSIDE the Ubuntu Distrobox container (not on the Bazzite host).
#
# Bazzite's host is immutable + flatpak-first, so the apt-based terminal
# toolchain lives here, in an Ubuntu container. We reuse the same OOP app
# framework as fresh_install.sh by sourcing setup/lib.sh (the container shares
# the host's $HOME, so ~/.scripts is available). Inside the container the
# detected FAMILY is "ubuntu", which is exactly what the framework's ubuntu
# branches target.
#
# Only dependency-management apps run here. Host concerns (systemd, snap, ssh,
# cron, dotfile *policy*) stay on the host or in fresh_install_bazzite.sh.

set -o pipefail
set -eE
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "${SCRIPT_DIR}/../lib.sh"

# Force the ubuntu family regardless of what detection found.
OS="ubuntu"
FAMILY="ubuntu"

# lib.sh's step()/on_fail() write into $TEMP_DIR; ensure it exists.
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Container is not a "server": keep interactive tools (zellij, etc.).
PROFILE="${PROFILE:-desktop}"

# ---- Container-specific overrides -------------------------------------------
# app_nvim is brew-only in lib.sh (a fresh mac/ubuntu installs Linuxbrew first).
# The container has no Homebrew, so install Neovim from apt instead.
app_nvim() {
    step "nvim"
    pkg_exists nvim && return
    sudo apt install -y neovim
}

# The container needs no Homebrew at all; skip it explicitly in case it ever
# slips into a shared list.
app_brew() { step "homebrew (skipped in container)"; return 0; }

# app_just in lib.sh uses the mpr/makedeb route, which isn't available in a bare
# ubuntu:24.04 container. Prefer apt, fall back to cargo.
app_just() {
    step "just"
    pkg_exists just && return
    sudo apt install -y just 2>/dev/null || cargo install just
}

# Android Platform Tools (adb/fastboot). No Flathub package exists, so it's
# installed in the container; /dev is shared with the host for device access.
app_android_tools() {
    step "android-platform-tools"
    pkg_exists adb && return
    sudo apt install -y android-tools-adb android-tools-fastboot
}

# OpenCode CLI — installed here (in the Ubuntu Distrobox) rather than on the
# Bazzite host, matching the ~/.opencode/bin PATH in dotfiles/.zshrc. Uses the
# official installer.
app_opencode() {
    step "opencode"
    pkg_exists opencode && return
    curl -fsSL https://opencode.ai/install | bash
}

# ---- Install ----------------------------------------------------------------
install_apps bazzite_deps \
    base \
    zinit \
    fzf \
    nvim \
    cargo \
    luarocks \
    starship \
    zellij \
    pyenv \
    pyenv_version \
    nvm \
    nerd_fonts \
    opencode \
    gh \
    kubectl \
    just \
    ssh \
    android_tools \
    duf zoxide fd ripgrep xh dog procs dust gping lsd tree_sitter

# Make zsh the shell everywhere inside the container, by forcing $SHELL (not by
# editing /etc/passwd via chsh).
#
# The terminal enters the box via Ptyxis's profile "Use Custom Command" =
# `distrobox enter bazzite-ubuntu -- zsh -l` (set on the host by
# fresh_install_bazzite.sh), so the login shell is already zsh. But distrobox
# carries the host's SHELL=bash into the box, and zsh login shells do NOT source
# /etc/profile.d/distrobox_profile.sh (which would otherwise correct SHELL from
# /etc/passwd). Tools that read $SHELL — zellij panes, nvim :term, etc. — would
# therefore see bash. /etc/zsh/zshenv is sourced on EVERY zsh invocation, so it
# is the one reliable place to make $SHELL agree everywhere.
#
# (The old approach of `chsh -s zsh` in /etc/passwd was removed: it does not
# affect $SHELL for zsh, and was redundant with the Ptyxis custom command.)
if command -v zsh >/dev/null 2>&1; then
    if ! grep -qF 'export SHELL="/usr/bin/zsh"' /etc/zsh/zshenv 2>/dev/null; then
        printf '\n# Container default shell: force SHELL=zsh so all tools (zellij, nvim :term, etc.) agree.\nexport SHELL="/usr/bin/zsh"\n' \
            | sudo tee -a /etc/zsh/zshenv >/dev/null
        echo "Set SHELL=/usr/bin/zsh in /etc/zsh/zshenv (all zsh invocations)."
    else
        echo "SHELL=/usr/bin/zsh already set in /etc/zsh/zshenv."
    fi
else
    echo "WARN: zsh not installed in the container; SHELL not overridden."
fi

echo "Container provisioning complete."

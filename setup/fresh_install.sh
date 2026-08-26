#!/bin/bash
# Unified install script for server / desktop / disney (work) profiles.
# Auto-detects OS: mac (brew), wsl (apt), ubuntu (apt).
# Granular failure handling: each step is tracked, overwritten files are
# backed up to a temp dir, and the temp dir is only removed on full success.

set -o pipefail
set -eE

PYENV_VERSION=3.14.7
KUBECTL_VERSION=v1.37

# ---------- Variables ----------
PROJECT_DIR="${HOME}/.scripts"
TEMP_DIR="${HOME}/install"
BACKUP_DIR="${TEMP_DIR}/backup"
STEP_LOG="${TEMP_DIR}/steps.log"

# ---------- OS detection ----------
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "mac"
    elif [[ -f /etc/wsl.conf ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    else
        echo "ubuntu"
    fi
}
OS="$(detect_os)"

# ---------- Helpers ----------
Sudo() {
    local firstArg=$1
    if [ "$(type -t "$firstArg")" = function ]; then
        shift && command sudo bash -c "$(declare -f "$firstArg");$firstArg $*"
    elif [ "$(type -t "$firstArg")" = alias ]; then
        alias sudo='\sudo '
        eval "sudo $*"
    else
        command sudo "$@"
    fi
}

cp_or_ln() {
    local src=$1
    local dst=$2
    if [[ "$OS" == "mac" ]]; then
        gcp -Rs "$src" "$dst"
    else
        cp -rs "$src" "$dst"
    fi
}

# Generic "is this app installed" check (by command name).
pkg_exists() {
    command -v "$1" &>/dev/null
}

# Install a package via the appropriate package manager.
pkg_install() {
    if [[ "$OS" == "mac" ]]; then
        brew install "$@"
    else
        sudo apt install -y "$@"
    fi
}

# ---------- Granular failure tracking ----------
step() {
    echo "$1" >> "$STEP_LOG"
}

backup_path() {
    local p="$1"
    if [ -e "$p" ]; then
        mkdir -p "$BACKUP_DIR"
        if [[ "$OS" == "mac" ]]; then
            gcp -R "$p" "$BACKUP_DIR/" 2>/dev/null || true
        else
            cp -a "$p" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    fi
}

on_fail() {
    local failed_step
    failed_step="$(tail -n 1 "$STEP_LOG" 2>/dev/null || echo "unknown")"
    echo ""
    echo "=============================================="
    echo "INSTALL FAILED at step: ${failed_step}"
    echo "Backups preserved in: ${BACKUP_DIR}"
    echo "=============================================="
    exit 1
}
trap 'on_fail' ERR

# Append a line to a root-owned file only if it isn't already present.
append_if_missing() {
    local line="$1" file="$2"
    [ -n "$line" ] || return
    if ! sudo grep -qF -- "$line" "$file" 2>/dev/null; then
        echo "$line" | sudo tee -a "$file" >/dev/null
    fi
}

# Sync system config (fstab + crontabs) from the repo, deduping existing lines.
sync_system_config() {
    step "system: fstab"
    while IFS= read -r line; do
        append_if_missing "$line" /etc/fstab
    done < "$PROJECT_DIR/setup/etc/fstab"

    step "system: crontab (root)"
    local root_file
    root_file="$(sudo crontab -l -u root 2>/dev/null || true)"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -qF -- "$line" <<<"$root_file" || root_file+=$'\n'"$line"
    done < "$PROJECT_DIR/setup/cron/root"
    printf '%s\n' "$root_file" | sudo crontab -u root -

    step "system: crontab (margey)"
    local cur_user
    cur_user="$(id -un)"
    local user_file
    user_file="$(sudo crontab -l -u "$cur_user" 2>/dev/null || true)"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -qF -- "$line" <<<"$user_file" || user_file+=$'\n'"$line"
    done < "$PROJECT_DIR/setup/cron/margey"
    printf '%s\n' "$user_file" | sudo crontab -u "$cur_user" -
}

# ---------- Common install (all profiles) ----------
install_common() {
    step "common: base packages"
    if [[ "$OS" != "mac" ]]; then
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt install -y build-essential procps curl file gzip unzip wget cpio \
            ca-certificates zsh apt-transport-https gnupg git gettext ninja-build cmake gpg \
            libclang-dev
    fi

    step "common: zinit"
    if [ ! -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]; then
        mkdir -p "$HOME/.local/share/zinit"
        git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"
    fi

    step "common: homebrew"
    if ! pkg_exists brew; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    step "common: fzf"
    if ! pkg_exists fzf && [ ! -d "$HOME/.fzf" ]; then
        if [[ "$OS" == "mac" ]]; then
            brew install fzf
            "$(brew --prefix)/opt/fzf/install" --all
        else
            git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
            "$HOME/.fzf/install"
        fi
    fi

    step "common: nvim"
    if ! pkg_exists nvim; then
        if [[ "$OS" == "mac" ]]; then
            xcode-select --install 2>/dev/null || true
            brew install ninja cmake gettext curl
        fi
        git clone https://github.com/neovim/neovim
        cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo
        if [[ "$OS" == "mac" ]]; then
            sudo make install
        else
            cd build && cpack -G DEB && sudo dpkg -i nvim-linux-*.deb
        fi
        cd "$TEMP_DIR"
    fi

    step "common: cargo/rust"
    if ! pkg_exists cargo; then
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    fi

    step "common: cargo QOL tools"
    if ! pkg_exists tree-sitter; then cargo install tree-sitter-cli; fi
    if ! pkg_exists procs; then cargo install procs; fi
    if ! pkg_exists dust; then cargo install du-dust; fi
    if ! pkg_exists gping; then cargo install gping; fi
    if ! pkg_exists lsd; then cargo install lsd; fi

    step "common: QOL packages"
    if [[ "$OS" == "mac" ]]; then
        for p in duf zoxide fd xh dog; do
            pkg_exists "$p" || brew install "$p"
        done
    else
        sudo apt install -y duf zoxide fd-find
        if ! pkg_exists xh; then
            # xh (http client) - install via cargo (the install.sh is interactive)
            cargo install xh
        fi
        if ! pkg_exists dog; then
            # dog (dns client, renamed to doggo) - install via cargo as it's not in apt
            cargo install doggo
        fi
    fi

    step "common: nerd fonts"
    if [[ "$OS" == "mac" ]]; then
        cd "$HOME/Library/Fonts" && {
            wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
            unzip -o NerdFontsSymbolsOnly.zip
            rm -f readme.md NerdFontsSymbolsOnly.zip
        }
        cd "$TEMP_DIR"
    else
        mkdir -p "$HOME/.local/share/fonts"
        cd "$HOME/.local/share/fonts"
        curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/UbuntuMono.zip
        unzip -o UbuntuMono.zip
        rm -f UbuntuMono.zip
        cd "$TEMP_DIR"
    fi

    step "common: pyenv"
    if ! pkg_exists pyenv && [ ! -d "$HOME/.pyenv" ]; then
        if [[ "$OS" == "mac" ]]; then
            brew install pyenv pyenv-virtualenv
        else
            sudo apt install -y make libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
                libsqlite3-dev wget curl llvm libncursesw5-dev xz-utils tk-dev \
                libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
            curl https://pyenv.run | bash
        fi
    fi

    step "common: nvm"
    if ! pkg_exists nvm && [ ! -d "$HOME/.nvm" ]; then
        if [[ "$OS" == "mac" ]]; then
            brew install nvm
        else
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        fi
    fi

    step "common: pyenv version + neovim"
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    pyenv install "$PYENV_VERSION" 2>/dev/null || true
    pyenv global "$PYENV_VERSION"
    pyenv virtualenv "$PYENV_VERSION" neovim3 2>/dev/null || true
    "$PYENV_ROOT/versions/$PYENV_VERSION/envs/neovim3/bin/python3" -m pip install pynvim
}

# ---------- Desktop profile (Linux) ----------
install_desktop() {
    step "desktop: element-desktop"
    if ! pkg_exists element-desktop; then
        wget -qO- https://packages.element.io/debian/element-io-archive-keyring.gpg | sudo tee /usr/share/keyrings/element-io-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/element-io-archive-keyring.gpg] https://packages.element.io/debian/ default main" | sudo tee /etc/apt/sources.list.d/element-io.list
        sudo apt update
        sudo apt install element-desktop -y
    fi

    step "desktop: xone (xbox controller)"
    if ! pkg_exists xone; then
        echo "Installing Xbox Wireless Dongle support, please unplug your dongle."
        echo "Press enter once you've validated it is unplugged"
        read -r _ || true
        git clone https://github.com/medusalix/xone
        cd xone
        ./install.sh --release
        xone-get-firmware.sh
        cd "$TEMP_DIR"
    fi

    step "desktop: vscode"
    if ! pkg_exists code; then
        sudo apt install -y wget gpg
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
        sudo tee /etc/apt/sources.list.d/vscode.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
        sudo apt update
        sudo apt install -y code
    fi

step "desktop: neofetch"
    if ! pkg_exists neofetch; then
        pkg_install neofetch
    fi

    step "desktop: rsync"
    if ! pkg_exists rsync; then
        sudo apt install rsync -y
    fi

    step "desktop: zellij"
    if ! pkg_exists zellij; then
        if [[ "$OS" == "mac" ]]; then
            brew install zellij
        else
            cargo install zellij
        fi
    fi
}

# ---------- Server profile (Linux) ----------
install_server() {
    step "server: just"
    if ! pkg_exists just; then
        git clone 'https://mpr.makedeb.org/just'
        cd just
        makedeb -si
        cd "$TEMP_DIR"
    fi

    step "server: sdkman"
    if ! pkg_exists sdk; then
        curl -s "https://get.sdkman.io" | bash
    fi

    step "server: virtualbox"
    if ! pkg_exists vboxmanage; then
        wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc \
            | sudo gpg --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg --dearmor
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $(lsb_release -sc) contrib" \
            | sudo tee /etc/apt/sources.list.d/virtualbox.list
        sudo apt update
        sudo apt install -y linux-headers-"$(uname -r)" dkms
        echo "virtualbox virtualbox/module-compilation-allowed boolean true" \
            | sudo debconf-set-selections
        sudo apt install -y virtualbox-7.1
    fi

    if ! sudo VBoxManage list extpacks 2>/dev/null | grep -q "Extension Pack"; then
        cd "$TEMP_DIR"
        VBOX_VERSION="$(VBoxManage --version)"
        VBOX_BUILD="$(echo "$VBOX_VERSION" | sed 's/r.*//')"
        VBOX_REV="$(echo "$VBOX_VERSION" | sed 's/^\([0-9.]*\)r\([0-9]*\).*/\2/')"
        wget "https://download.virtualbox.org/virtualbox/${VBOX_BUILD}/Oracle_VirtualBox_Extension_Pack-${VBOX_BUILD}-${VBOX_REV}.vbox-extpack"
        echo y | sudo VBoxManage extpack install "Oracle_VirtualBox_Extension_Pack-${VBOX_BUILD}-${VBOX_REV}.vbox-extpack"
        cd "$PROJECT_DIR"
    fi

    step "server: kubectl"
    if ! pkg_exists kubectl; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/Release.key" \
            | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/ /" \
            | sudo tee /etc/apt/sources.list.d/kubernetes.list
        sudo apt update
        sudo apt install kubectl -y
    fi

    step "server: awscli"
    if ! pkg_exists aws; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
    fi

    step "server: gh"
    if ! pkg_exists gh; then
        type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)
        sudo mkdir -p -m 755 /etc/apt/keyrings
        out=$(mktemp)
        wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            && cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
            && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
            && rm -f "$out"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh -y
    fi

    step "server: speedtest"
    if ! pkg_exists speedtest; then
        curl -s https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz | tar xz
        sudo mv speedtest /usr/local/bin/
    fi

    step "server: docker"
    if ! pkg_exists docker; then
        sudo apt update
        sudo apt install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
        sudo apt update
        sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    fi

    step "server: openssh-server + ssh-agent"
    sudo apt install openssh-server -y
    sudo systemctl enable ssh
    sudo systemctl start ssh
    chmod 600 "$HOME/.ssh/id_rsa" 2>/dev/null || true
    chmod 600 "$HOME/.ssh/id_rsa.pub" 2>/dev/null || true
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_rsa" 2>/dev/null || true

step "server: crontab"
    if ! pkg_exists crontab; then
        sudo apt install cron -y
    fi
    sync_system_config
}

# ---------- Disney (work) profile (Mac) ----------
install_disney() {
    step "disney: poetry"
    if ! pkg_exists poetry; then brew install poetry; fi

    step "disney: brew taps"
    brew tap devproductivity/devx-cli git@github.prod.hulu.com:devproductivity/homebrew-devx-cli.git
    brew tap ced/homebrew-ced git@github.bamtech.co:ced/homebrew-ced.git

    step "disney: external tools"
    for p in jfrog-cli kubectl awscli gh; do
        pkg_exists "$p" || brew install "$p"
    done

    step "disney: internal tools"
    for p in devx-cli frogger; do
        pkg_exists "$p" || brew install "$p"
    done

    step "disney: kitty"
    if ! pkg_exists kitty; then
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
    fi
}

# ---------- Dotfiles ----------
dotfile_setup() {
    step "dotfiles: backup existing config"
    backup_path "$HOME/.zprofile"
    backup_path "$HOME/.zshrc"
    backup_path "$HOME/.config/nvim"
    backup_path "$HOME/.config/kitty"
    backup_path "$HOME/.local/share/zinit/snippets"

    step "dotfiles: remove existing config"
    rm -f "$HOME/.zprofile"
    rm -f "$HOME/.zshrc"
    rm -rf "$HOME/.config/nvim"
    rm -rf "$HOME/.config/kitty"
    rm -rf "$HOME/.local/share/zinit/snippets"

    step "dotfiles: create dirs"
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/share/zinit/snippets"

    if [[ "$OS" == "mac" ]]; then
        brew install coreutils
    fi

    step "dotfiles: prerequisites"
    if ! pkg_exists starship; then
        if [[ "$OS" == "mac" ]]; then
            brew install starship
        else
            curl -sS https://starship.rs/install.sh | sh -s -- -y
        fi
    fi
    if [ ! -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]; then
        mkdir -p "$HOME/.local/share/zinit"
        git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"
    fi

    step "dotfiles: symlink config"
    cp_or_ln "$PROJECT_DIR/dotfiles/.config/nvim" "$HOME/.config"
    cp_or_ln "$PROJECT_DIR/dotfiles/.config/kitty" "$HOME/.config"
    for _f in "$PROJECT_DIR"/dotfiles/zsh/*; do
        cp_or_ln "$_f" "$HOME/.local/share/zinit/snippets/"
    done
    cp_or_ln "$PROJECT_DIR/dotfiles/.zshrc" "$HOME/.zshrc"

    if [[ "$OS" != "mac" ]]; then
        step "dotfiles: root symlinks"
        sudo mkdir -p /root/.config
        sudo mkdir -p /root/.local/share/zinit/snippets
        Sudo cp_or_ln "$PROJECT_DIR/dotfiles/.config/nvim/" /root/.config
        Sudo cp_or_ln "$PROJECT_DIR/dotfiles/.config/kitty" /root/.config
        for _f in "$PROJECT_DIR"/dotfiles/zsh/*; do
            Sudo cp_or_ln "$_f" /root/.local/share/zinit/snippets/
        done
        Sudo cp_or_ln "$PROJECT_DIR/dotfiles/.zshrc" /root/.zshrc
    fi

    if [[ "$PROFILE" == "server" ]]; then
        step "dotfiles: system config (fstab + crontab)"
        sync_system_config
    fi
}

# ---------- Snap removal (ubuntu only) ----------
remove_snap() {
    step "snap: remove"
    snap --version
    snap list
    sudo systemctl disable snapd.service
    sudo systemctl disable snapd.socket
    sudo systemctl disable snapd.seeded.service
    sudo snap remove firefox
    sudo snap remove gtk-common-themes
    sudo snap remove gnome-3-38-2004
    sudo snap remove snapd-desktop-integration
    sudo snap remove snap-store
    sudo snap remove core20
    sudo snap remove bare
    sudo snap remove snapd
    sudo systemctl stop snapd
    sudo systemctl disable snapd
    sudo systemctl mask snapd
    sudo apt purge snapd -y
    sudo apt-mark hold snapd
    sudo apt autoremove --purge snapd
    sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd/ "$HOME/snap/"
}

# ---------- Menu ----------
display_menu() {
    echo "Detected OS: ${OS}"
    echo "Select a profile:"
    echo "1. server   (Linux server)"
    echo "2. desktop  (Linux desktop)"
    echo "3. disney   (Mac work)"
    echo "4. dotfiles only"
    read -rp "Enter your choice: " choice
}

# ---------- Main ----------
if [[ $(id -u) -eq 0 ]]; then
    echo "This script should not be run as root."
    exit 1
fi

# Clean any leftover temp dir from a previous (failed) run, then start fresh.
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

display_menu

case "$choice" in
    1) PROFILE="server" ;;
    2) PROFILE="desktop" ;;
    3) PROFILE="disney" ;;
    4) PROFILE="dotfiles" ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

read -rp "Do you want to continue? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Script aborted."
    exit 1
fi

case "$PROFILE" in
    server)
        install_common
        install_server
        dotfile_setup
        [[ "$OS" == "ubuntu" ]] && remove_snap
        ;;
    desktop)
        install_common
        install_desktop
        dotfile_setup
        [[ "$OS" == "ubuntu" ]] && remove_snap
        ;;
    disney)
        install_common
        install_disney
        dotfile_setup
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

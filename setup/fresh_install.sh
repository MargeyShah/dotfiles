#!/bin/bash
# Unified install script for server / desktop / disney (work) profiles.
# Auto-detects OS: mac (brew), wsl (apt), ubuntu (apt).
# Granular failure handling: each step is tracked, overwritten files are
# backed up to a temp dir, and the temp dir is only removed on full success.
#
# Apps are modeled as self-contained "objects" (app_<name>() functions) that
# each own their OS branching, install method, and role gating. Profiles are
# just ordered lists of app names run through the install_apps dispatcher.

set -o pipefail
set -eE

PYENV_VERSION=3.14.7
KUBECTL_VERSION=v1.37

NVIM_HANDROLL_REPO="https://github.com/joermo/dotfiles"
NVIM_HANDROLL_SRC="${HOME}/.local/share/nvim-handroll"

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
# FAMILY normalizes wsl -> ubuntu (both are apt-based). All install/manager
# logic branches on FAMILY (mac | ubuntu) so future distros slot in cleanly.
FAMILY="$OS"
[[ "$FAMILY" == "wsl" ]] && FAMILY="ubuntu"

# ---------- Helpers ----------
cp_or_ln() {
    local src=$1
    local dst=$2
    if [[ "$OS" == "mac" ]]; then
        gcp -Rs "$src" "$dst"
    else
        cp -rs "$src" "$dst"
    fi
}

# Pull the nvim-handroll config from joermo/dotfiles and symlink it to ~/.config/nvim.
nvim_handroll() {
    if [ ! -d "$NVIM_HANDROLL_SRC" ]; then
        git clone --depth 1 "$NVIM_HANDROLL_REPO" "$NVIM_HANDROLL_SRC"
    else
        git -C "$NVIM_HANDROLL_SRC" pull --depth 1
    fi
    mkdir -p "$HOME/.config"
    rm -rf "$HOME/.config/nvim"
    ln -sfn "$NVIM_HANDROLL_SRC/nvim-handroll" "$HOME/.config/nvim"
}

# Generic "is this app installed" check (by command name).
pkg_exists() {
    command -v "$1" >/dev/null 2>&1
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

# Normalize whitespace and check if a line exists on stdin. 0=present, 1=absent.
line_present() {
    local line="$1" norm
    norm="$(printf '%s' "$line" | awk '{ $1=$1; print }')"
    awk -v n="$norm" '{ $1=$1; if ($0==n) f=1 } END{ exit f?0:1 }'
}

# Append a line to a root-owned file only if it isn't already present.
append_if_missing() {
    local line="$1" file="$2"
    [ -n "$line" ] || return
    if ! line_present "$line" < <(sudo cat "$file" 2>/dev/null); then
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
        line_present "$line" <<<"$root_file" || root_file+=$'\n'"$line"
    done < "$PROJECT_DIR/setup/cron/root"
    printf '%s\n' "$root_file" | sudo crontab -u root -

    step "system: crontab (margey)"
    local cur_user
    cur_user="$(id -un)"
    local user_file
    user_file="$(sudo crontab -l -u "$cur_user" 2>/dev/null || true)"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        line_present "$line" <<<"$user_file" || user_file+=$'\n'"$line"
    done < "$PROJECT_DIR/setup/cron/margey"
    printf '%s\n' "$user_file" | sudo crontab -u "$cur_user" -
}

# ---------- OOP install framework ----------

# Manager-aware existence check. Uses the RESOLVED package name (not the binary),
# so e.g. apt's "fd-find" is checked via dpkg, not `command -v fd`.
installed_by() {
    case "$1" in
        apt)   dpkg -s "$2" >/dev/null 2>&1 ;;
        brew)  brew list "$2" >/dev/null 2>&1 ;;
        cargo) command -v "$2" >/dev/null 2>&1 ;;
    esac
}

# Repo/tap boilerplate — the "objects" scaffold, OS-branch ready.
# apt_repo writes a deb822 .sources file (modern apt format).
apt_repo() {
    local name="$1" keyring="$2" uri="$3" suite="$4" arch="$5"; shift 5
    sudo mkdir -p /etc/apt/keyrings
    sudo tee "/etc/apt/sources.list.d/${name}.sources" >/dev/null <<EOF
Types: deb
URIs: $uri
Suites: $suite
Components: $*
Architectures: $arch
Signed-By: $keyring
EOF
    sudo apt update
}

# brew_tap <tap> [url]
brew_tap() {
    if [ -n "$2" ]; then
        brew tap "$1" "$2"
    else
        brew tap "$1"
    fi
}

# Simple-app registry: logical name -> "manager:package" for the current FAMILY.
# Resolved via case statements (bash 3.2-compatible; no associative arrays).
# "Simple" = a direct apt/brew/cargo install with no repo/tap/key prep.
resolve_pkg() {
    local app="$1"
    # Cargo-only apps (same crate regardless of FAMILY).
    case "$app" in
        tree-sitter) echo "cargo:tree-sitter-cli"; return ;;
        procs)       echo "cargo:procs";          return ;;
        dust)        echo "cargo:du-dust";        return ;;
        gping)       echo "cargo:gping";          return ;;
        lsd)         echo "cargo:lsd";            return ;;
    esac
    case "$FAMILY" in
        mac)
            case "$app" in
                duf)    echo "brew:duf";    return ;;
                zoxide) echo "brew:zoxide"; return ;;
                fd)     echo "brew:fd";     return ;;
                xh)     echo "brew:xh";     return ;;
                dog)    echo "brew:doggo";  return ;;
            esac
            ;;
        ubuntu)
            case "$app" in
                duf)      echo "apt:duf";      return ;;
                zoxide)   echo "apt:zoxide";   return ;;
                fd)       echo "apt:fd-find";  return ;;
                rsync)    echo "apt:rsync";    return ;;
                neofetch) echo "apt:neofetch"; return ;;
                xh)       echo "cargo:xh";     return ;;
                dog)      echo "cargo:doggo";  return ;;
            esac
            ;;
    esac
    echo ""
}

# Cargo installs a crate but the resulting binary may differ (du-dust -> dust).
cargo_bin() {
    case "$1" in
        tree-sitter) echo tree-sitter ;;
        procs)       echo procs ;;
        dust)        echo dust ;;
        gping)       echo gping ;;
        lsd)         echo lsd ;;
        xh)          echo xh ;;
        dog)         echo doggo ;;
    esac
}

# install_pkg <logical> — install a simple app via the manager chosen by FAMILY.
install_pkg() {
    local app="$1" spec m pkg bin
    spec="$(resolve_pkg "$app")"
    [ -z "$spec" ] && return
    m="${spec%%:*}"; pkg="${spec#*:}"
    case "$m" in
        apt)   installed_by apt "$pkg" || sudo apt install -y "$pkg" ;;
        brew)  installed_by brew "$pkg" || brew install "$pkg" ;;
        cargo) bin="$(cargo_bin "$app")"; [ -z "$bin" ] && bin="$pkg"; installed_by cargo "$bin" || cargo install "$pkg" ;;
    esac
}

# Dispatcher: run each app function in order.
install_apps() {
    local label="$1"; shift
    for app in "$@"; do
        "app_$app"
    done
}

# ---------- App objects ----------

# --- Simple registry wrappers (option A: explicit) ---
app_duf()      { step "duf";      install_pkg duf; }
app_zoxide()   { step "zoxide";   install_pkg zoxide; }
app_fd()       { step "fd";       install_pkg fd; }
app_rsync()    { step "rsync";    install_pkg rsync; }
app_neofetch() { step "neofetch"; install_pkg neofetch; }
app_procs()    { step "procs";    install_pkg procs; }
app_dust()     { step "dust";     install_pkg dust; }
app_gping()    { step "gping";    install_pkg gping; }
app_lsd()      { step "lsd";      install_pkg lsd; }
app_xh()       { step "xh";       install_pkg xh; }
app_dog()      { step "dog";      install_pkg dog; }
app_tree_sitter() { step "tree-sitter"; install_pkg tree-sitter; }

# --- Bespoke apps ---

app_base() {
    step "base packages"
    if [[ "$FAMILY" != "mac" ]]; then
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt install -y build-essential procps curl file gzip unzip wget cpio \
            ca-certificates zsh apt-transport-https gnupg git gettext ninja-build cmake gpg \
            libclang-dev
    fi
}

app_zinit() {
    step "zinit"
    if [ ! -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]; then
        mkdir -p "$HOME/.local/share/zinit"
        git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"
    fi
}

app_brew() {
    step "homebrew"
    pkg_exists brew && return
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

app_fzf() {
    step "fzf"
    pkg_exists fzf && return
    [ -d "$HOME/.fzf" ] && return
    if [[ "$FAMILY" == "mac" ]]; then
        brew install fzf
        "$(brew --prefix)/opt/fzf/install" --all
    else
        git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
        "$HOME/.fzf/install"
    fi
}

app_nvim() {
    step "nvim"
    pkg_exists nvim && return
    if [[ "$FAMILY" == "mac" ]]; then
        xcode-select --install 2>/dev/null || true
        brew install ninja cmake gettext curl
    fi
    git clone https://github.com/neovim/neovim
    cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo
    if [[ "$FAMILY" == "mac" ]]; then
        sudo make install
    else
        cd build && cpack -G DEB && sudo dpkg -i nvim-linux-*.deb
    fi
    cd "$TEMP_DIR"
}

app_nvim_config() {
    step "nvim config"
    nvim_handroll
}

app_cargo() {
    step "cargo/rust"
    pkg_exists cargo && return
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
}

app_starship() {
    step "starship"
    pkg_exists starship && return
    if [[ "$FAMILY" == "mac" ]]; then
        brew install starship
    else
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
}

# ORDER: app_cargo must run before app_zellij on ubuntu (cargo install).
app_zellij() {
    step "zellij"
    # Not on the server (interactive multiplexer for desktop/DWM hosts).
    [[ "$PROFILE" == "server" ]] && return
    pkg_exists zellij && return
    if [[ "$FAMILY" == "mac" ]]; then
        brew install zellij
    else
        cargo install zellij
    fi
}

app_pyenv() {
    step "pyenv"
    pkg_exists pyenv && return
    [ -d "$HOME/.pyenv" ] && return
    if [[ "$FAMILY" == "mac" ]]; then
        brew install pyenv pyenv-virtualenv
    else
        sudo apt install -y make libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
            libsqlite3-dev wget curl llvm libncursesw5-dev xz-utils tk-dev \
            libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
        curl https://pyenv.run | bash
    fi
}

# ORDER: app_pyenv must run before app_pyenv_version.
app_pyenv_version() {
    step "pyenv version + neovim"
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    pyenv install "$PYENV_VERSION" 2>/dev/null || true
    pyenv global "$PYENV_VERSION"
    pyenv virtualenv "$PYENV_VERSION" neovim3 2>/dev/null || true
    "$PYENV_ROOT/versions/$PYENV_VERSION/envs/neovim3/bin/python3" -m pip install pynvim
}

app_nvm() {
    step "nvm"
    pkg_exists nvm && return
    [ -d "$HOME/.nvm" ] && return
    if [[ "$FAMILY" == "mac" ]]; then
        brew install nvm
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi
}

app_nerdfonts() {
    step "nerd fonts"
    if [[ "$FAMILY" == "mac" ]]; then
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
}

# --- Repo apps (ubuntu-only for now; OOP-ready for future OS) ---

app_element() {
    step "element-desktop"
    pkg_exists element-desktop && return
    case "$FAMILY" in
        ubuntu)
            wget -qO- https://packages.element.io/debian/element-io-archive-keyring.gpg | sudo tee /usr/share/keyrings/element-io-archive-keyring.gpg > /dev/null
            echo "deb [signed-by=/usr/share/keyrings/element-io-archive-keyring.gpg] https://packages.element.io/debian/ default main" | sudo tee /etc/apt/sources.list.d/element-io.list
            sudo apt update
            sudo apt install element-desktop -y
            ;;
        mac) : ;; # TODO: brew install --cask element
    esac
}

app_vscode() {
    step "vscode"
    pkg_exists code && return
    case "$FAMILY" in
        ubuntu)
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
            ;;
        mac) : ;; # TODO: brew install --cask visual-studio-code
    esac
}

app_docker() {
    step "docker"
    pkg_exists docker && return
    case "$FAMILY" in
        ubuntu)
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
            ;;
        mac) : ;; # TODO: brew install --cask docker
    esac
}

app_gh() {
    step "gh"
    pkg_exists gh && return
    case "$FAMILY" in
        ubuntu)
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
            ;;
        mac) brew install gh ;;
    esac
}

app_kubectl() {
    step "kubectl"
    pkg_exists kubectl && return
    case "$FAMILY" in
        ubuntu)
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/Release.key" \
                | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/ /" \
                | sudo tee /etc/apt/sources.list.d/kubernetes.list
            sudo apt update
            sudo apt install kubectl -y
            ;;
        mac) brew install kubectl ;;
    esac
}

app_vbox() {
    step "virtualbox"
    pkg_exists vboxmanage && return
    case "$FAMILY" in
        ubuntu)
            wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc \
                | sudo gpg --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg --dearmor
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $(lsb_release -sc) contrib" \
                | sudo tee /etc/apt/sources.list.d/virtualbox.list
            sudo apt update
            sudo apt install -y linux-headers-"$(uname -r)" dkms
            echo "virtualbox virtualbox/module-compilation-allowed boolean true" \
                | sudo debconf-set-selections
            sudo apt install -y virtualbox-7.1
            ;;
        mac) : ;; # TODO: brew install --cask virtualbox
    esac

    if ! sudo VBoxManage list extpacks 2>/dev/null | grep -q "Extension Pack"; then
        cd "$TEMP_DIR"
        VBOX_VERSION="$(VBoxManage --version)"
        VBOX_BUILD="$(echo "$VBOX_VERSION" | sed 's/r.*//')"
        VBOX_REV="$(echo "$VBOX_VERSION" | sed 's/^\([0-9.]*\)r\([0-9]*\).*/\2/')"
        wget "https://download.virtualbox.org/virtualbox/${VBOX_BUILD}/Oracle_VirtualBox_Extension_Pack-${VBOX_BUILD}-${VBOX_REV}.vbox-extpack"
        echo y | sudo VBoxManage extpack install "Oracle_VirtualBox_Extension_Pack-${VBOX_BUILD}-${VBOX_REV}.vbox-extpack"
        cd "$PROJECT_DIR"
    fi
}

app_just() {
    step "just"
    pkg_exists just && return
    case "$FAMILY" in
        ubuntu)
            git clone 'https://mpr.makedeb.org/just'
            cd just
            makedeb -si
            cd "$TEMP_DIR"
            ;;
        mac) brew install just ;;
    esac
}

app_aws() {
    step "awscli"
    pkg_exists aws && return
    case "$FAMILY" in
        ubuntu)
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
            ;;
        mac) brew install awscli ;;
    esac
}

app_speedtest() {
    step "speedtest"
    pkg_exists speedtest && return
    curl -s https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz | tar xz
    sudo mv speedtest /usr/local/bin/
}

app_sdkman() {
    step "sdkman"
    pkg_exists sdk && return
    curl -s "https://get.sdkman.io" | bash
}

app_openssh() {
    step "openssh-server + ssh-agent"
    sudo apt install openssh-server -y
    sudo systemctl enable ssh
    sudo systemctl start ssh
    chmod 600 "$HOME/.ssh/id_rsa" 2>/dev/null || true
    chmod 600 "$HOME/.ssh/id_rsa.pub" 2>/dev/null || true
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_rsa" 2>/dev/null || true
}

app_cron() {
    step "crontab"
    if ! pkg_exists crontab; then
        sudo apt install cron -y
    fi
    sync_system_config
}

# --- Disney (work Mac) apps ---

app_poetry() {
    step "poetry"
    pkg_exists poetry && return
    brew install poetry
}

app_devx() {
    step "disney: brew taps + tools"
    brew_tap devproductivity/devx-cli git@github.prod.hulu.com:devproductivity/homebrew-devx-cli.git
    brew_tap ced/homebrew-ced git@github.bamtech.co:ced/homebrew-ced.git
    for p in jfrog-cli kubectl awscli gh devx-cli frogger; do
        pkg_exists "$p" || brew install "$p"
    done
}

app_kitty() {
    step "kitty"
    pkg_exists kitty && return
    curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
}

# ---------- Profiles (ordered app lists) ----------

# ORDER matters within these lists (see inline comments).
install_common() {
    install_apps common \
        base \
        zinit \
        brew \
        fzf \
        nvim \
        nvim_config \
        cargo \
        starship \
        zellij \
        pyenv \
        pyenv_version \
        nvm \
        nerd_fonts \
        duf zoxide fd xh dog procs dust gping lsd tree_sitter
}

# Dotfiles-only dependencies: the same app objects as install_common, so the
# standalone "dotfiles" profile installs exactly what the dotfiles need.
dotfile_deps() {
    install_apps dotfiles \
        zinit brew starship zellij nvim_config
}

install_desktop() {
    install_apps desktop \
        element vscode rsync neofetch
}

install_server() {
    install_apps server \
        just sdkman vbox kubectl gh aws speedtest docker openssh cron
}

# Disney = work Mac profile. Only runs its apps when work-profiled.
install_disney() {
    [[ "$PROFILE" == "disney" ]] || return
    install_apps disney \
        poetry devx kitty
}

# ---------- Dotfiles ----------
dotfile_setup() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo ""
        echo "WARNING: Found a legacy oh-my-zsh install at $HOME/.oh-my-zsh"
        echo "This setup uses zinit and does not use oh-my-zsh."
        read -rp "Remove the leftover oh-my-zsh directory? [y/N]: " rm_omz
        if [[ "$rm_omz" == "y" || "$rm_omz" == "Y" ]]; then
            rm -rf "$HOME/.oh-my-zsh"
            echo "Removed $HOME/.oh-my-zsh"
        else
            echo "Skipping removal of $HOME/.oh-my-zsh"
        fi
    fi

    step "dotfiles: backup existing config"
    backup_path "$HOME/.zprofile"
    backup_path "$HOME/.zshrc"
    backup_path "$HOME/.config/nvim"
    backup_path "$HOME/.config/kitty"
    backup_path "$HOME/.local/share/zinit/snippets"

    step "dotfiles: remove existing config"
    rm -f "$HOME/.zprofile"
    rm -f "$HOME/.zshrc"
    rm -rf "$HOME/.config/kitty"
    rm -rf "$HOME/.local/share/zinit/snippets"

    step "dotfiles: create dirs"
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/share/zinit/snippets"

    if [[ "$OS" == "mac" ]]; then
        brew install coreutils
    fi

    step "dotfiles: prerequisites"
    dotfile_deps

    step "dotfiles: symlink config"
    nvim_handroll
    cp_or_ln "$PROJECT_DIR/dotfiles/.config/kitty" "$HOME/.config"
    for _f in "$PROJECT_DIR"/dotfiles/zsh/*; do
        cp_or_ln "$_f" "$HOME/.local/share/zinit/snippets/"
    done
    cp_or_ln "$PROJECT_DIR/dotfiles/.zshrc" "$HOME/.zshrc"

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

# On-the-fly nvim-handroll pull only.
if [[ "$1" == "--nvim" ]]; then
    nvim_handroll
    exit 0
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

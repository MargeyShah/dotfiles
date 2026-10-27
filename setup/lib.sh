# shellcheck shell=bash
# Shared library for the fresh-install scripts.
#
# Sourced by fresh_install.sh. Sourcing applies the shell options and ERR trap
# below, so callers should not redefine them.
#
# Layout is grouped by function TYPE. Keep new helpers in the matching section:
#   1. constants                 2. OS/identity detection
#   3. failure tracking          4. generic shell helpers
#   5. idempotency checks        6. package-manager primitives
#   7. app objects               8. profiles
#   9. dotfiles                 10. snap removal
#  11. Bazzite host steps       12. menu
#
# Family values: mac | ubuntu (wsl normalizes to ubuntu) | bazzite
set -o pipefail
set -eE
# Unmatched globs expand to nothing instead of a literal `*`.
shopt -s nullglob

# ---------- 1. Constants ----------

PYENV_VERSION=3.14.7
KUBECTL_VERSION=v1.37

NVIM_HANDROLL_REPO="https://github.com/joermo/dotfiles"
NVIM_HANDROLL_SRC="${HOME}/.local/share/nvim-handroll"

PROJECT_DIR="${HOME}/.scripts"
TEMP_DIR="${HOME}/install"
BACKUP_DIR="${TEMP_DIR}/backup"
STEP_LOG="${TEMP_DIR}/steps.log"

# Own-machine SSH key distribution (see app_ssh).
PISTACHIO_HOST="pistachio"
PISTACHIO_IP="192.168.0.2"
PISTACHIO_USER="margey"

# Bazzite: the Ubuntu Distrobox that holds the apt CLI toolchain.
CONTAINER_NAME="bazzite-ubuntu"

# Host-only GUI apps. They are installed on a normal host, but skipped inside a
# Distrobox: there they would duplicate the host's GUIs (on Bazzite the same
# apps are baked into the image as Flatpaks). Everything else in a profile
# still runs in the box, so --profile desktop inside the Distrobox means "all
# the apt CLI tools" without duplicate GUI apps.
GUI_APPS="element vscode"

# Bazzite AppImages (no suitable Flathub package) integrated via Gear Lever.
# Format: "owner/repo|display-name|asset-filename-regex".
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

# ---------- 2. OS/identity detection ----------
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "mac"
    elif [[ -f /etc/wsl.conf ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    elif [ -f /run/ostree-booted ] && grep -qiE 'bazzite' /etc/os-release 2>/dev/null; then
        # Bazzite / Universal Blue: image-based (rpm-ostree) Fedora atomic.
        echo "bazzite"
    else
        echo "ubuntu"
    fi
}
OS="$(detect_os)"
# FAMILY normalizes wsl -> ubuntu (both are apt-based). All install/manager
# logic branches on FAMILY (mac | ubuntu | bazzite) so future distros slot in
# cleanly. Bazzite keeps its own family because its install model is entirely
# different (flatpak on host + an Ubuntu Distrobox for the apt CLI toolchain).
FAMILY="$OS"
[[ "$FAMILY" == "wsl" ]] && FAMILY="ubuntu"

# True when running inside a Distrobox (distrobox-init exports $CONTAINER_ID,
# which needs no binary, so this is safe on hosts without distrobox).
is_distrobox() {
    [ -n "${CONTAINER_ID:-}" ]
}

# Source dotfiles/zsh/env.zsh once. It is the single source of truth for the
# HOSTS_* lists and the is_* predicates used by the dotfiles.
load_host_lists() {
    [ -n "${__HOST_LISTS_LOADED:-}" ] && return 0
    [ -f "$PROJECT_DIR/dotfiles/zsh/env.zsh" ] || return 1
    # shellcheck source=../dotfiles/zsh/env.zsh
    source "$PROJECT_DIR/dotfiles/zsh/env.zsh"
    __HOST_LISTS_LOADED=yes
}

# in_host_list <host> <entry...> — case-insensitive membership test.
in_host_list() {
    local h="$1"; shift
    local entry
    shopt -s nocasematch
    for entry in "$@"; do
        if [ "$entry" = "$h" ]; then shopt -u nocasematch; return 0; fi
    done
    shopt -u nocasematch
    return 1
}

# True if this host appears in any OS-class list (i.e. one of our machines).
is_known_host() {
    load_host_lists || return 1
    in_host_list "${HOST:-$(hostname)}" \
        "${HOSTS_WSL[@]}" "${HOSTS_LINUX[@]}" "${HOSTS_MAC[@]}"
}

# True if this is a Linux desktop host. Delegates to env.zsh's
# is_linux_desktop() so the host-list logic has a single definition.
is_linux_desktop_host() {
    load_host_lists || return 1
    is_linux_desktop
}

# ---------- 3. Granular failure tracking ----------
step() {
    echo "$1" >> "$STEP_LOG"
}

backup_path() {
    local p="$1"
    if [ -e "$p" ]; then
        mkdir -p "$BACKUP_DIR"
        # Plain `cp` (built-in on every OS) so backups work before coreutils is
        # installed on a fresh mac.
        cp -R "$p" "$BACKUP_DIR/" 2>/dev/null || true
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

# ---------- 4. Generic shell helpers ----------

# Symlink src -> dst. ln -sfn replaces an existing symlink/file in place, so no
# coreutils/gcp is needed and there is no `cp -s` directory-nesting weirdness.
link() {
    local src=$1
    local dst=$2
    ln -sfn "$src" "$dst"
}

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

# ---------- 5. Idempotency checks ----------
# Each check answers "is this step already done?" so a re-run can skip only the
# work that is actually missing (download vs. integrate vs. install target).

# Generic "is this app installed" check (by command name).
pkg_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Manager-aware existence check. Uses the RESOLVED package name (not the binary),
# so e.g. apt's "fd-find" is checked via dpkg, not `command -v fd`.
installed_by() {
    case "$1" in
        apt)   dpkg -s "$2" >/dev/null 2>&1 ;;
        brew)  brew list "$2" >/dev/null 2>&1 ;;
        cargo) command -v "$2" >/dev/null 2>&1 ;;
    esac
}

# True if an AppImage file is already on disk (and executable-suitable).
appimage_downloaded() {
    [ -f "$1" ]
}

# True if Gear Lever has already integrated this app. Uses Gear Lever's own
# status (`--list-installed --json`) rather than guessing from filenames, and
# matches on the app name so a moved/re-named file still counts.
appimage_integrated() {
    local want="$1" json
    command -v flatpak >/dev/null 2>&1 || return 1
    json="$(flatpak run it.mijorus.gearlever --list-installed --json 2>/dev/null)" || return 1
    [ -n "$json" ] || return 1
    if command -v python3 >/dev/null 2>&1; then
        # Gear Lever appends version/commit to some names ("Ghostty (97eea4)"),
        # so accept an exact match or a "<name> ..." prefix.
        printf '%s' "$json" | python3 -c '
import json, sys
want = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for app in data.get("installed", []):
    name = app.get("name") or ""
    if name == want or name.startswith(want + " "):
        sys.exit(0)
sys.exit(1)
' "$want"
    else
        printf '%s' "$json" | grep -q "\"name\": *\"${want}\""
    fi
}

# True if a ujust recipe reports itself installed (`ujust <recipe> status`).
ujust_installed() {
    command -v ujust >/dev/null 2>&1 || return 1
    ujust "$1" status 2>/dev/null | grep -qxE 'install(-prerelease)?'
}

# True if a Decky plugin with this store display name is already installed.
# Plugin folders are slugs (e.g. SDH-CssLoader), so match the plugin.json name.
decky_plugin_installed() {
    local want="$1"
    command -v python3 >/dev/null 2>&1 || return 1
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

# ---------- 6. Package-manager primitives ----------

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

# Put Homebrew on PATH for this script process. Apple Silicon mac (/opt/homebrew)
# and Linuxbrew; the installer only updates shell rc files, not this process.
brew_shellenv() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [[ -x "$b" ]]; then eval "$("$b" shellenv)"; return 0; fi
    done
    return 1
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
                duf)      echo "brew:duf";      return ;;
                zoxide)   echo "brew:zoxide";   return ;;
                fd)       echo "brew:fd";       return ;;
                ripgrep)  echo "brew:ripgrep";  return ;;
                luarocks) echo "brew:luarocks"; return ;;
                xh)       echo "brew:xh";       return ;;
                dog)      echo "brew:doggo";    return ;;
            esac
            ;;
        ubuntu)
            case "$app" in
                duf)      echo "apt:duf";      return ;;
                zoxide)   echo "apt:zoxide";   return ;;
                fd)       echo "apt:fd-find";  return ;;
                ripgrep)  echo "apt:ripgrep";  return ;;
                luarocks) echo "apt:luarocks"; return ;;
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

# Dispatcher: run each app function in order. Host-only GUI apps are skipped
# inside a Distrobox (see GUI_APPS); every other app runs wherever it is called.
install_apps() {
    local label="$1"; shift
    local app
    for app in "$@"; do
        if is_distrobox && [[ " ${GUI_APPS} " == *" ${app} "* ]]; then
            echo "skip ${app} (host GUI app; not installed inside a Distrobox)"
            continue
        fi
        "app_$app"
    done
}

# ---------- 7. App objects ----------

# --- Simple registry wrappers (option A: explicit) ---
app_duf()      { step "duf";      install_pkg duf; }
app_zoxide()   { step "zoxide";   install_pkg zoxide; }
app_fd()       { step "fd";       install_pkg fd; }
app_ripgrep()  { step "ripgrep";  install_pkg ripgrep; }
app_luarocks() { step "luarocks"; install_pkg luarocks; }
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
    brew_shellenv || true                 # installed already, just off PATH?
    if ! pkg_exists brew; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew_shellenv || true
    fi
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
    brew install neovim
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

# GNU coreutils (ls/grep/etc.) on macOS; not required by the installer itself.
app_coreutils() {
    step "coreutils"
    [[ "$FAMILY" == "mac" ]] || return 0
    installed_by brew coreutils || brew install coreutils
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
    export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
    command -v pyenv >/dev/null 2>&1 || export PATH="$PYENV_ROOT/bin:$PATH"
    if ! command -v pyenv >/dev/null 2>&1; then
        echo "WARN: pyenv not found; skipping Python ${PYENV_VERSION} + pynvim"
        return 0
    fi
    eval "$(pyenv init -)" 2>/dev/null || true

    # Best-effort: never let an unavailable Python version abort the install.
    trap - ERR
    pyenv versions --bare 2>/dev/null | grep -qx "$PYENV_VERSION" \
        || pyenv install "$PYENV_VERSION" 2>/dev/null || true
    pyenv virtualenvs --bare 2>/dev/null | grep -qx "neovim3" \
        || pyenv virtualenv "$PYENV_VERSION" neovim3 2>/dev/null || true
    trap 'on_fail' ERR

    if pyenv versions --bare 2>/dev/null | grep -qx "$PYENV_VERSION"; then
        pyenv global "$PYENV_VERSION" 2>/dev/null || true
    else
        echo "WARN: Python ${PYENV_VERSION} unavailable; skipping pyenv global"
    fi

    local env_py="$PYENV_ROOT/versions/$PYENV_VERSION/envs/neovim3/bin/python3"
    if [ -x "$env_py" ]; then
        "$env_py" -m pip install pynvim || echo "WARN: could not install pynvim"
    else
        echo "WARN: neovim3 virtualenv missing; skipping pynvim"
    fi
}

# Installs the nvm manager AND a default Node (npm). nvm is a shell function,
# not a binary, so we key off ~/.nvm/nvm.sh instead of pkg_exists.
app_nvm() {
    step "nvm + node"
    export NVM_DIR="$HOME/.nvm"
    # nvm's installer aborts when $NVM_DIR is set but absent and doesn't match
    # its computed default (e.g. when XDG_CONFIG_HOME differs); pre-create it.
    mkdir -p "$NVM_DIR"
    if [[ "$FAMILY" == "mac" ]]; then
        installed_by brew nvm || brew install nvm
        # Homebrew keeps nvm.sh under its keg; expose it where .zshrc looks.
        local pfx
        pfx="$(brew --prefix nvm 2>/dev/null || true)"
        if [ -n "$pfx" ] && [ -s "$pfx/nvm.sh" ]; then
            mkdir -p "$NVM_DIR"
            ln -sfn "$pfx/nvm.sh" "$NVM_DIR/nvm.sh"
            [ -s "$pfx/libexec/nvm-exec" ] && ln -sfn "$pfx/libexec/nvm-exec" "$NVM_DIR/nvm-exec"
        fi
    else
        if [ ! -s "$NVM_DIR/nvm.sh" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        fi
    fi

    # nvm internals can fail non-fatally (e.g. probing a missing `default`
    # alias); disable the ERR trap around it like app_pyenv_version does.
    trap - ERR
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" || true
    if command -v nvm >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
        nvm install --lts || true
        nvm alias default 'lts/*' || true
    fi
    trap 'on_fail' ERR
}

app_nerd_fonts() {
    step "nerd fonts"
    if [[ "$FAMILY" == "mac" ]]; then
        cd "$HOME/Library/Fonts" && {
            curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
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
# element and vscode are host GUI apps (see GUI_APPS): install_desktop skips
# them inside a Distrobox.

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
            # apt first (Ubuntu ships it); makedeb/mpr isn't in a bare container
            # and isn't worth the extra repo, so fall back to cargo.
            sudo apt install -y just 2>/dev/null || cargo install just
            ;;
        mac) brew install just ;;
    esac
}

# Android Platform Tools (adb/fastboot). No Flathub package exists. On Bazzite
# this lives in the Ubuntu Distrobox, where /dev is shared with the host for
# device access.
app_android_tools() {
    step "android-platform-tools"
    pkg_exists adb && return
    case "$FAMILY" in
        ubuntu) sudo apt install -y android-tools-adb android-tools-fastboot ;;
        mac) brew install --cask android-platform-tools ;;
    esac
}

# OpenCode CLI. Installed to ~/.opencode/bin (the PATH entry the dotfiles add).
app_opencode() {
    step "opencode"
    pkg_exists opencode && return
    curl -fsSL https://opencode.ai/install | bash
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

    trap - ERR
    chmod 600 "$HOME/.ssh/id_rsa" 2>/dev/null || true
    chmod 600 "$HOME/.ssh/id_rsa.pub" 2>/dev/null || true
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_rsa" 2>/dev/null || true
    trap 'on_fail' ERR
}

app_cron() {
    step "crontab"
    if ! pkg_exists crontab; then
        sudo apt install cron -y
    fi
    sync_system_config
}

# SSH identity + git commit signing. Key generation and git signing run
# everywhere; the key push to pistachio + GitHub runs only on our own listed
# hosts (see dotfiles/zsh/env.zsh), and gh is never auto-authenticated.
# OS-agnostic (runs on the host for apt/brew and inside the Bazzite Distrobox,
# which shares $HOME), so the key and git config apply everywhere at once.
app_ssh() {
    step "ssh key + git signing"
    local key="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # ssh-keygen/ssh-copy-id come from openssh-client (built into macOS).
    if ! pkg_exists ssh-keygen; then
        case "$FAMILY" in
            ubuntu|bazzite) sudo apt install -y openssh-client ;;
        esac
    fi

    # 1. Generate an ed25519 identity if one doesn't exist yet.
    if [ ! -f "$key" ]; then
        ssh-keygen -t ed25519 -N "" -C "margey@$(hostname)" -f "$key"
    fi
    chmod 600 "$key" 2>/dev/null || true
    chmod 644 "$key.pub" 2>/dev/null || true

    # 2. Trust the host + copy the key to pistachio, and 3. register the key on
    # GitHub — only on our own (listed) machines, so a random host never pushes
    # its key anywhere. The hostname lists live in dotfiles/zsh/env.zsh (single
    # source of truth); unknown hosts are skipped. gh is never auto-authed.
    local h="${HOST:-$(hostname)}" known_host="no"
    if is_known_host; then known_host="yes"; fi

    trap - ERR
    if [ "$known_host" = "yes" ]; then
        # 2. Trust the host + copy the key to pistachio (best-effort; may prompt).
        grep -qF "$PISTACHIO_IP" "$HOME/.ssh/known_hosts" 2>/dev/null \
            || ssh-keyscan -H "$PISTACHIO_IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
                "${PISTACHIO_USER}@${PISTACHIO_IP}" true >/dev/null 2>&1; then
            echo "Copying SSH key to ${PISTACHIO_HOST} (${PISTACHIO_USER}@${PISTACHIO_IP}); may prompt for a password..."
            ssh-copy-id -i "$key.pub" "${PISTACHIO_USER}@${PISTACHIO_IP}" \
                || echo "WARN: could not copy key to ${PISTACHIO_HOST}"
        fi

        # 3. Register the public key on GitHub (best-effort; never auto-auths).
        if pkg_exists gh; then
            gh ssh-key add "$key.pub" --title "margey@$(hostname) (ed25519)" 2>/dev/null \
                || echo "NOTE: SSH key already on GitHub, or run 'gh auth login' then re-run to add it."
        fi
    else
        echo "Skipping pistachio key copy + GitHub key push (host ${h} is not in env.zsh host lists)"
    fi
    trap 'on_fail' ERR

    # 4. Sign commits with this SSH key so they show as Verified on GitHub.
    git config --global gpg.format ssh
    git config --global user.signingkey "$key.pub"
    git config --global commit.gpgsign true
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

# ---------- 8. Profiles (ordered app lists) ----------

# Shared dependency set for every profile, including dotfiles-only. Ordered so
# brew runs first (it provides git on a fresh mac), then everything the
# dotfiles and the nvim config need. Called once per profile from main() via
# dotfile_setup(), which then writes the config. `nvim_config` is absent because
# dotfile_config calls nvim_handroll() itself.
install_deps() {
    install_apps deps \
        base \
        brew \
        zinit \
        coreutils \
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
        gh \
        kubectl \
        just \
        opencode \
        android_tools \
        ssh \
        duf zoxide fd ripgrep xh dog procs dust gping lsd tree_sitter
}

install_desktop() {
    install_apps desktop \
        element vscode rsync neofetch
}

install_server() {
    install_apps server \
        cron just sdkman vbox kubectl gh aws speedtest docker openssh
}

# Disney = work Mac profile. Only runs its apps when work-profiled.
install_disney() {
    [[ "$PROFILE" == "disney" ]] || return
    install_apps disney \
        poetry devx kitty
}

# ---------- 9. Dotfiles ----------

# Pull the nvim-handroll config from joermo/dotfiles and symlink it to ~/.config/nvim.
nvim_handroll() {
    if [ ! -d "$NVIM_HANDROLL_SRC/.git" ]; then
        rm -rf "$NVIM_HANDROLL_SRC"
        git clone --depth 1 "$NVIM_HANDROLL_REPO" "$NVIM_HANDROLL_SRC"
    else
        # Fetch + hard reset instead of `git pull`: this is a shallow, read-only
        # mirror of someone else's repo, and `git pull` aborts with "divergent
        # branches" whenever the local shallow clone and origin have both moved
        # (or a plugin bumped lazy-lock.json locally).
        git -C "$NVIM_HANDROLL_SRC" fetch --depth 1 origin
        git -C "$NVIM_HANDROLL_SRC" reset --hard origin/main
        git -C "$NVIM_HANDROLL_SRC" clean -fdq
    fi
    mkdir -p "$HOME/.config"
    rm -rf "$HOME/.config/nvim"
    ln -sfn "$NVIM_HANDROLL_SRC/nvim-handroll" "$HOME/.config/nvim"
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

# Config-only half of dotfile_setup(): back up, remove and symlink the dotfiles.
# No package installs happen here, so it is also safe to call on its own.
# (System config — fstab/crontab — belongs to the install side: see app_cron,
# which installs the cron package before calling sync_system_config.)
dotfile_config() {
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

    # zellij's managed config carries box-shell (its default_shell), which opens
    # every pane inside the Distrobox. That only makes sense on Linux desktops:
    # servers never auto-start zellij, and box-shell is meaningless without
    # distrobox. Gate on the hostname lists (servers are excluded).
    local want_zellij="no" _host="${HOST:-$(hostname)}"
    if is_linux_desktop_host; then
        want_zellij="yes"
    fi

    step "dotfiles: backup existing config"
    backup_path "$HOME/.zprofile"
    backup_path "$HOME/.zshrc"
    backup_path "$HOME/.config/nvim"
    backup_path "$HOME/.config/kitty"
    [ "$want_zellij" = "yes" ] && backup_path "$HOME/.config/zellij"
    backup_path "$HOME/.config/starship.toml"
    backup_path "$HOME/.local/share/zinit/snippets"
    backup_path "$HOME/.ssh/config"

    step "dotfiles: remove existing config"
    rm -f "$HOME/.zprofile"
    rm -f "$HOME/.zshrc"
    rm -rf "$HOME/.config/kitty"
    [ "$want_zellij" = "yes" ] && rm -rf "$HOME/.config/zellij"
    rm -f "$HOME/.config/starship.toml"
    rm -rf "$HOME/.local/share/zinit/snippets"
    # Stale misnamed file (ssh reads ~/.ssh/config, not .config); superseded by
    # the managed ~/.ssh/config symlink below.
    rm -f "$HOME/.ssh/.config"

    step "dotfiles: create dirs"
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/share/zinit/snippets"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    step "dotfiles: symlink config"
    nvim_handroll
    link "$PROJECT_DIR/dotfiles/.config/kitty" "$HOME/.config/kitty"
    if [ "$want_zellij" = "yes" ]; then
        link "$PROJECT_DIR/dotfiles/.config/zellij" "$HOME/.config/zellij"
    else
        echo "Skipping zellij config (linux desktop only; not on ${_host:-this host})."
    fi
    link "$PROJECT_DIR/dotfiles/.config/starship.toml" "$HOME/.config/starship.toml"
    for _f in "$PROJECT_DIR"/dotfiles/zsh/*; do
        link "$_f" "$HOME/.local/share/zinit/snippets/"
    done
    # zinit copies + compiles local snippets into sibling cache dirs (named
    # after the absolute source path, e.g. home--margey--...--snippets/config.zsh)
    # and keeps loading those instead of re-reading edits through the symlink.
    # Clear them so updated snippets take effect on the next shell. (-mindepth 1
    # keeps the snippets dir itself, so the symlinks above survive; the cache
    # dirs are real dirs, the symlinks are not -type d.)
    find "$HOME/.local/share/zinit/snippets" -mindepth 1 -maxdepth 1 -type d \
        -exec rm -rf {} + 2>/dev/null || true
    link "$PROJECT_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
    link "$PROJECT_DIR/dotfiles/ssh/config" "$HOME/.ssh/config"
}

# Full dotfiles setup for a normal host: install the shared dependency set,
# then write the config. install_deps must run first because the dotfiles and
# the nvim config depend on it. The dotfiles-only profile is self-contained
# through this call.
dotfile_setup() {
    step "dotfiles: dependencies"
    install_deps
    dotfile_config
}

# ---------- 10. Snap removal (ubuntu only) ----------
remove_snap() {
    step "snap: remove"
    # Nothing to do if snap isn't present; never abort the run over it.
    command -v snap >/dev/null 2>&1 || { echo "snap not installed; skipping"; return 0; }
    snap --version || true
    snap list || true
    for svc in snapd.service snapd.socket snapd.seeded.service; do
        sudo systemctl disable "$svc" 2>/dev/null || true
    done
    for pkg in firefox gtk-common-themes gnome-3-38-2004 snapd-desktop-integration \
               snap-store core20 bare snapd; do
        sudo snap remove "$pkg" 2>/dev/null || true
    done
    sudo systemctl stop snapd 2>/dev/null || true
    sudo systemctl disable snapd 2>/dev/null || true
    sudo systemctl mask snapd 2>/dev/null || true
    sudo apt purge snapd -y || true
    sudo apt-mark hold snapd || true
    sudo apt autoremove --purge -y || true
    sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd/ "$HOME/snap/"
}

# ---------- 11. Bazzite host steps ----------
# Bazzite is image-based (rpm-ostree) with a flatpak-first host and an Ubuntu
# Distrobox for the apt CLI toolchain. Everything declarative (flatpaks, GNOME
# extensions, gsettings) lives in the MargeyShah/bazzite image; these steps are
# the per-user/post-install work that cannot be baked in.

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
# Returns an empty string (and status 0) when nothing matches, so the caller can
# warn and skip instead of aborting under `set -o pipefail`.
resolve_asset_url() {
    local repo="$1" pattern="$2"
    { curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep -oE '"browser_download_url": *"[^"]+"' \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | grep -E "$pattern" \
        | head -n1; } || true
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
# (decky_plugin_installed above).
# Fail-soft: any single plugin failing never aborts the run. No config sync.
install_decky_plugins() {
    step "bazzite: decky plugins"
    [ "${#DECKY_PLUGINS[@]}" -eq 0 ] && return 0
    command -v python3 >/dev/null 2>&1 || { echo "WARN: python3 missing; skipping Decky plugins"; return 0; }
    pkg_exists unzip || { echo "WARN: unzip missing; skipping Decky plugins"; return 0; }

    local plugins_dir="$HOME/homebrew/plugins"
    mkdir -p "$plugins_dir"

    local store_json="$TEMP_DIR/decky-store.json"
    if ! curl -fsSL "$DECKY_STORE_URL" -o "$store_json" || [ ! -s "$store_json" ]; then
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
print(next((p["versions"][0]["hash"] for p in d if p.get("name")==sys.argv[2]),""))' "$store_json" "$name" 2>/dev/null || true)"
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
# Bazzite's own ujust targets plus a couple of Homebrew casks. (Skip with
# --no-extras.) Note: CoolerControl is the one rpm-ostree layer, and it ships
# in the image rather than being installed here.
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
    # (VSCodium is the CLI-companion editor; the image already provides VS Code
    # as a Flatpak, so both editors are intentionally present.)
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
    local ini="${SCRIPT_DIR}/bazzite/distrobox.ini"
    if [ -f "$ini" ]; then
        distrobox assemble create --file "$ini"
    else
        distrobox create --name "$CONTAINER_NAME" --image ubuntu:24.04 --yes
    fi
}

# Provision the container by running this same script inside it with the given
# profile. The container reuses the exact same OOP app framework as every other
# host (no bespoke provisioning script), and because a Distrobox shares $HOME
# the symlinks it writes are the host's too.
provision_container() {
    local profile="$1"
    step "bazzite: container provision (fresh_install.sh --profile ${profile})"
    distrobox enter "$CONTAINER_NAME" -- \
        bash "$SCRIPT_DIR/fresh_install.sh" --profile "$profile" --yes
}

# Core host steps: run for every Bazzite profile.
bazzite_core() {
    install_podman_docker
    install_host_zsh
    grant_flameshot_portal
    create_container
}

# Desktop extras: the "Unix PC" tier on the image-based host. Skipped by the
# dotfiles-only profile, and individually skippable with --no-gaming/--no-extras.
bazzite_desktop_extras() {
    install_appimages
    if [[ "$GAMING_EXTRAS" == "yes" ]]; then
        install_gaming_extras
        install_decky_plugins
    fi
    if [[ "$SYSTEM_EXTRAS" == "yes" ]]; then
        install_system_extras
    fi
}

# ---------- 12. Menu ----------

# Interactive profile selection. Sets PROFILE to the chosen profile name.
display_menu() {
    local choice
    echo "Detected OS: ${OS}"
    echo "Select a profile:"
    if [[ "$FAMILY" == "bazzite" ]]; then
        echo "1. Unix PC   (Bazzite desktop: host extras + Distrobox toolchain)"
        echo "2. dotfiles only"
        read -rp "Enter your choice: " choice
        case "$choice" in
            1) PROFILE="desktop" ;;
            2) PROFILE="dotfiles" ;;
            *) echo "Invalid choice"; exit 1 ;;
        esac
        return
    fi

    echo "1. server    (Linux server)"
    echo "2. Unix PC   (Linux desktop)"
    echo "3. disney    (Mac work)"
    echo "4. dotfiles only"
    read -rp "Enter your choice: " choice
    case "$choice" in
        1) PROFILE="server" ;;
        2) PROFILE="desktop" ;;
        3) PROFILE="disney" ;;
        4) PROFILE="dotfiles" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
}

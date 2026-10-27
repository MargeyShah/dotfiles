# pipX / uv
# https://github.com/pypa/pipx | https://docs.astral.sh/uv/
# ~/.local/bin is where pipx and uv (uv/uvx) install their binaries.
export PATH="$PATH:$HOME/.local/bin"

# golang
export PATH=$PATH:/usr/local/go/bin

# NVM is lazy-loaded from .zshrc (load-nvm)

# ---------- LM Studio (lms) ----------
# `lms` lives in ~/.lmstudio/bin. Linux desktop hosts only (mac/wsl/servers
# don't have it).
if is_linux_desktop; then
    export PATH="$PATH:$HOME/.lmstudio/bin"
fi

# ---------- Mac ----------
if is_env mac; then
    # Brew Setup
    # https://brew.sh/
    [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

    # Work (Mac)
    if is_work_mac; then

        sshi(){
            ssh -i ${HOME}/.ssh/coreeng.pem ec2-user@"$1"
        }

        PS2_BASTIONS=(
            "bastion-1-ps2-prod.us-east-1.twdcgrid.net"
            "bastion-2-ps2-prod.us-east-1.twdcgrid.net"
            "bastion-1-ps2-nonprod.us-east-1.twdcgrid.net"
            "bastion-2-ps2-nonprod.us-east-1.twdcgrid.net"
        )

        function ps2(){
            ssh -A $(printf '%s\n' "${PS2_BASTIONS[@]}" | fzf)
        }
    fi
fi

# ---------- Linux / WSL ----------
if is_linuxlike; then
    # Import Linuxbrew (skip on NixOS)
    if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] \
        && ! ( [ -f /etc/NIXOS ] || grep -qi '^ID=nixos' /etc/os-release 2>/dev/null ); then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    # If dir exists, add to path
    if [ -d "$HOME/platform-tools" ] ; then
        export PATH="$HOME/platform-tools:$PATH"
    fi
fi

# ---------- Zellij ----------
# Interactive multiplexer; auto-starts on terminal load (non-server only).
# Started eagerly so the terminal has reported its real size before zellij
# creates its session (deferring to precmd caused a tiny window on WSL).
# No ZELLIJ_AUTO_ATTACH: each terminal tab starts its own fresh session.
#
# zellij runs only on the host shell: is_server() is true inside a Distrobox
# (see env.zsh), so containers never auto-start it. Zellij's panes themselves
# are spawned inside the box via default_shell in config.kdl.

if ! is_server; then
    command -v zellij >/dev/null 2>&1 && eval "$(zellij setup --generate-auto-start zsh)"
fi

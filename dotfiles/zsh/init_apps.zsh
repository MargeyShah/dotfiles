# pipX
# https://github.com/pypa/pipx
export PATH="$PATH:$HOME/.local/bin"

# golang
export PATH=$PATH:/usr/local/go/bin

# NVM is lazy-loaded from .zshrc (load-nvm)

# ---------- Mac ----------
if is_env mac; then
    # Brew Setup
    # https://brew.sh/
    [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

    # Work (Mac)
    if is_work_mac; then
        export AWS_DEFAULT_PROFILE=HULU_SSO
        export DOOZER_HOME=/Users/margey.shah/Documents/test/doozer
        export VAULT_ADDR="https://secrets.staging.hulu.com"

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

if ! is_server; then
    command -v zellij >/dev/null 2>&1 && eval "$(zellij setup --generate-auto-start zsh)"
fi

# pipX
# https://github.com/pypa/pipx
export PATH="$PATH:$HOME/.local/bin"

# golang
export PATH=$PATH:/usr/local/go/bin

# NVM is lazy-loaded from .zshrc (load-nvm)

# Brew Setup
# https://brew.sh/
if is_env mac; then # Mac
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if is_env linux; then # Unix (non-NixOS)
    # Not NIX OS, import brew
    if ! ( [ -f /etc/NIXOS ] || grep -qi '^ID=nixos' /etc/os-release 2>/dev/null ); then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    # If dir exists, add to path
    if [ -d "$HOME/platform-tools" ] ; then
        export PATH="$HOME/platform-tools:$PATH"
    fi
fi

# ---------- Work (Mac) ----------
if is_env mac && is_hostname FR95FPVKK6; then
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

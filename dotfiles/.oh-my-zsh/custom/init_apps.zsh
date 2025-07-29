# pipX
# https://github.com/pypa/pipx
export PATH="$PATH:$HOME/.local/bin"

# golang
export PATH=$PATH:/usr/local/go/bin

# NVM Setup - Node/NPM version manager
# https://github.com/nvm-sh/nvm
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# Brew Setup
# https://brew.sh/
if [ "$(uname)" = 'Darwin' ]; then # Mac
    eval "$(/opt/homebrew/bin/brew shellenv)"
    alias gcp=gcp
fi


if [ "$(uname)" = 'Linux' ]; then # Unix
    # Not NIX OS, import brew
    if ! ( [ -f /etc/NIXOS ] || grep -qi '^ID=nixos' /etc/os-release 2>/dev/null ); then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    # If dir exists, add to path
    if [ -d "$HOME/platform-tools" ] ; then
        export PATH="$HOME/platform-tools:$PATH"
    fi
fi


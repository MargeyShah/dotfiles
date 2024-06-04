# pipX
# https://github.com/pypa/pipx
export PATH="$PATH:$HOME/.local/bin"

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
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi


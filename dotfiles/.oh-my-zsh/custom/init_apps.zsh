# pipX
# https://github.com/pypa/pipx
export PATH="$PATH:/Users/margey.shah/.local/bin"

# PyEnv Setup - Python version manager
# https://github.com/pyenv/pyenv
export PYTHONDONTWRITEBYTECODE=1
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# NVM Setup - Node/NPM version manager
# https://github.com/nvm-sh/nvm
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"


# Zoxide setup - smart cd replacement (command is 'z')
# https://github.com/ajeetdsouza/zoxide
eval "$(zoxide init zsh)"

# fzf setup
# https://github.com/junegunn/fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Brew Setup
# https://brew.sh/
if [ "$(uname)" = 'Darwin' ]; then # Mac
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if [ "$(uname)" = 'Linux' ]; then # Unix
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# SDKMAN Setup - version manager for java adjacent development kits
# https://sdkman.io/
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
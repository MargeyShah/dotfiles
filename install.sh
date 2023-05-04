# This script will require a device that can run homebrew (https://brew.sh)
# Installs homebrew to install other apps
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Installs sdkman to install and manage multiple versions of SDKs.
curl -s "https://get.sdkman.io" | bash

# oh-my-zsh, better shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# oh-my-zsh plugins
brew install zsh-autosuggestions
echo "source \$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" >> $HOME/.oh-my-zsh/custom/scripts.zsh
brew install fzf
$(brew --prefix)/opt/fzf/install

# nvim
brew install nvim


# Python, pyenv manages python versions, good with pipenv.
brew install pyenv

# Adds taps for devx-cli and frogger usage
brew tap devproductivity/devx-cli git@github.prod.hulu.com:devproductivity/homebrew-devx-cli.git
brew tap ced/homebrew-ced git@github.bamtech.co:ced/homebrew-ced.git

# Install external tools
brew install jfrog-cli
brew install kubectl
brew install awscli
brew install gh


# Install internal tools
brew install devx-cli
brew install frogger


# Set zsh as default shell if it isn't already
chsh -s $(which zsh)

# Open pyenv 
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> $HOME/.oh-my-zsh/custom/scripts.zsh
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> $HOME/.oh-my-zsh/custom/scripts.zsh
echo 'eval "$(pyenv init -)"' >> $HOME/.oh-my-zsh/custom/scripts.zsh

source $HOME/.oh-my-zsh/custom/scripts.zsh

pyenv install 3.11
pyenv global 3.11

pip install pipenv

# Done, add zsh-autosuggestions to ~/.zshrc plugins, restart terminal.




#!/bin/bash

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

# Node version manager
brew install nvm

# nvim
cd /tmp
xcode-select --install
brew install ninja cmake gettext curl
git clone https://github.com/neovim/neovim
cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install
cd -

# Python, pyenv manages python versions, good with poetry.
brew install pyenv
brew install poetry

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

# Cargo - Rust PKG Manager
curl https://sh.rustup.rs -sSf | sh

# QOL Mods
cargo install tree-sitter-cli
cargo install du-dust
brew install dog 
brew install lsd
brew install duf
brew install gping
brew install procs
brew install zoxide
brew install xh
brew install fd

# Set zsh as default shell if it isn't already
chsh -s $(which zsh)

# Open pyenv 
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> $HOME/.oh-my-zsh/custom/scripts.zsh
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> $HOME/.oh-my-zsh/custom/scripts.zsh
echo 'eval "$(pyenv init -)"' >> $HOME/.oh-my-zsh/custom/scripts.zsh

source $HOME/.oh-my-zsh/custom/scripts.zsh

pyenv install 3.11.4
pyenv global 3.11.4

# NeoVim Configuration
pyenv virtualenv 3.11.4 neovim3
pyenv activate neovim3
pipenv install neovim

# Kitty (Terminal Emulator)
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin

# Remove generated config/directories
rm $HOME/.zprofile
rm $HOME/.zshrc
rm -rf $HOME/.config/nvim
rm -rf $HOME/.config/vim
rm -rf $HOME/.config/kitty
rm -rf $HOME/.oh-my-zsh

# Setup directories if they don't exist
mkdir -p $HOME/.config/nvim
mkdir -p $HOME/.config/vim
mkdir -p $HOME/.config/kitty
mkdir -p $HOME/.oh-my-zsh

# Setup symlinks 
cd ../dotfiles
ln -s $HOME/scripts/dotfiles/.config/nvim/* "$HOME/.config/nvim"
ln -s $HOME/scripts/dotfiles/.config/vim/* "$HOME/.config/vim"
ln -s $HOME/scripts/.oh-my-zsh/* $HOME/.oh-my-zsh
ln -s kitty/* $HOME/.config/kitty 
ln -s .zprofile "$HOME/.zprofile"
ln -s .zshrc "$HOME/.zshrc"

source .zprofile
source .zshrc

# Setup Node Version Manager
nvm install --lts
nvm use --lts

# Install Neovim NPM Package
npm install -g neovim

echo "You'll need to install the latest nerd fonts (view the README.md for more info https://github.com/ryanoasis/nerd-fonts/releases)"
echo "https://github.com/LunarVim/LunarVim for a potential new setup"

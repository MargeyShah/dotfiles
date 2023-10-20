#! /bin/zsh -

dotfileSetup() {
  # Remove generated config/directories
  sudo rm -f ${HOME}/.zprofile
  sudo rm -f ${HOME}/.zshrc
  sudo rm -rf ${HOME}/.config/nvim
  sudo rm -rf ${HOME}/.config/vim
  sudo rm -rf ${HOME}/.config/kitty
  sudo rm -rf ${HOME}/.oh-my-zsh/custom/alias.zsh
  sudo rm -rf ${HOME}/.oh-my-zsh/custom/scripts.zsh
  
  # Setup directories if they don't exist
  mkdir -p ${HOME}/.config/nvim
  mkdir -p ${HOME}/.config/vim
  mkdir -p ${HOME}/.config/kitty
  mkdir -p ${HOME}/.oh-my-zsh

  # Setup symlinks 
  cp -rs ${PROJECT_DIR}/dotfiles/.config/nvim ${HOME}/.config
  cp -rs ${PROJECT_DIR}/dotfiles/.config/vim ${HOME}/.config
  cp -rs ${PROJECT_DIR}/dotfiles/.config/kitty ${HOME}/.config
  cp -rs ${PROJECT_DIR}/dotfiles/.oh-my-zsh/custom ${HOME}/.oh-my-zsh
  cp -rs ${PROJECT_DIR}/dotfiles/.zprofile ${HOME}/.zprofile
  cp -rs ${PROJECT_DIR}/dotfiles/.zshrc ${HOME}/.zshrc
}

failedInstall(){
  echo "Installation failed due to an error, clearing files"
  sudo rm -f $(which nvim) 
  sudo rm -rf ${HOME}/.zsh
  sudo rm -rf ${HOME}/install
  sudo rm -rf ${HOME}/.config/nvim
  sudo rm -rf ${HOME}/.config/vim
  sudo rm -f ${HOME}/.zcompdump
  sudo rm -f ${HOME}/.viminfo
  sudo rm -rf /root/.oh-my-zsh
  sudo rm -rf /root/.local/state/nvim
  sudo rm -f /root/.zshrc
  sudo rm -rf /root/.pyenv
  sudo rm -rf ${HOME}/install
  sudo rm -rf ${HOME}/.oh-my-zsh/custom/alias.zsh
  sudo rm -rf ${HOME}/.oh-my-zsh/custom/scripts.zsh
  sudo rm -rf ${HOME}/.pyenv
  sudo rm -rf ${HOME}/.local/state/nvim
  sudo rm -rf ${HOME}/.zprofile
  sudo rm -rf ${HOME}/.zshrc
  sudo rm -rf ${HOME}/.oh-my-zsh
  sudo rm -rf ${HOME}/.viminfo
  sudo rm -rf ${TEMP_DIR}
  exit 1
}

backup(){
    mkdir -p ${HOME}/backups
    cp ${HOME}/.oh-my-zsh  ${HOME}/backups/.oh-my-zsh
    cp ${HOME}/.ssh ${HOME}/backups/.ssh
}

# If script has an error, run cleanup.
trap 'failedInstall' ERR

# Variable Setup
PROJECT_DIR=${HOME}/.scripts
PYENV_VERSION=3.11.4
TEMP_DIR=${HOME}/tmp

mkdir -p ${HOME}/tmp && cd ${TEMP_DIR}

# This script will require a device that can run homebrew (https://brew.sh)
# Installs homebrew to install other apps
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"


# Installs sdkman to install and manage multiple versions of SDKs.
curl -s "https://get.sdkman.io" | bash

# oh-my-zsh, better shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
backup

# oh-my-zsh plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
brew install fzf
$(brew --prefix)/opt/fzf/install --all

# Node version manager
brew install nvm

# nvim
xcode-select --install
brew install ninja cmake gettext curl
git clone https://github.com/neovim/neovim
cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install
cd ${TEMP_DIR}

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
curl https://sh.rustup.rs -sSf | sh -s -- -y
source "${HOME}/.cargo/env"

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
brew install pyenv-virtualenv

# Set zsh as default shell if it isn't already
chsh -s $(which zsh)

# Load pyenv 
echo 'export PYENV_ROOT="${HOME}/.pyenv"' >> ${HOME}/.oh-my-zsh/custom/scripts.zsh
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ${HOME}/.oh-my-zsh/custom/scripts.zsh
echo 'eval "$(pyenv init -)"' >> ${HOME}/.oh-my-zsh/custom/scripts.zsh
source ${HOME}/.oh-my-zsh/custom/scripts.zsh

pyenv install ${PYENV_VERSION} 
pyenv global ${PYENV_VERSION}

# NeoVim Configuration
pyenv virtualenv ${PYENV_VERSION} neovim3
pyenv activate neovim3 | sh
pyenv install neovim | sh


# Kitty (Terminal Emulator)
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin

# Remove generated config/directories
dotfileSetup

source ${HOME}/.zprofile
source ${HOME}/.zshrc
source ${HOME}/.oh-my-zsh/custom/scripts.zsh
source ${HOME}/.oh-my-zsh/custom/alias.zsh

# Add fonts for terminal emu
cd ~/Library/Fonts && { 
  wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
  unzip NerdFontsSymbolsOnly.zip
  rm readme.md
  rm NerdFontsSymbolsOnly.zip
}
cd ${TEMP_DIR}

# Setup Node Version Manager
nvm install --lts
nvm use --lts

# Install Neovim NPM Package
npm install -g neovim

sudo rm -rf ${TEMP_DIR}
echo "You'll need to install the latest nerd fonts (view the README.md for more info https://github.com/ryanoasis/nerd-fonts/releases)"
echo "https://github.com/LunarVim/LunarVim for a potential new setup"

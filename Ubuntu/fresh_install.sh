#!/bin/bash

# Function to display menu and get user's choice
display_menu() {
    echo "Select an option:"
    echo "1. PC"
    echo "2. Server"
    read -p "Enter your choice: " choice
}

# Get the optarg
if [[ $# -eq 1 ]]; then
    optarg="$1"
    USER_DIR="/home/${optarg}"
else
    echo "Usage: $0 <string>"
    exit 1
fi

# Display menu and get user's choice
display_menu

# Process user's choice
case $choice in
    1)
        echo "You selected: PC"
        ;;
    2)
        echo "You selected: Server"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

# Ask user for confirmation
read -p "Do you want to continue? (y/n): " confirm
if [[ $confirm == "y" || $confirm == "Y" ]]; then
    echo "Variable: $variable"
    echo "Script completed."
else
    echo "Script aborted."
    exit 1
fi

# Configure variables
TEMP_DIR=${USER_DIR}/install
PYENV_VERSION=3.11.4

echo $USER_DIR
echo $TEMP_DIR

# Debugging (echo output) on
set -x

# Work in temp dir to handle temp downloads.
mkdir ${TEMP_DIR}
cd ${TEMP_DIR}

# Get updates, do updates
apt update -y 
apt upgrade -y

##############################################
### Shell & backup utiliies

# Install dependencies/basics
apt install build-essential procps curl \
 file gzip unzip wget cpio \
 ca-certificates zsh \
 apt-transport-https gnupg \
 git gettext ninja-build \
 cmake gpg  -y

### oh-my-zsh, better shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

### oh-my-zsh plugins - zsh-autosuggestions, fzf
git clone https://github.com/zsh-users/zsh-autosuggestions ${USER_DIR}/.zsh/zsh-autosuggestions
echo "source  ${USER_DIR}/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" >> ${USER_DIR}/.oh-my-zsh/custom/scripts.zsh
apt install fzf -y

### nvim - vim with plugins + config
git clone https://github.com/neovim/neovim
cd neovim && git checkout stable && make CMAKE_BUILD_TYPE=RelWithDebInfo
cd build && cpack -G DEB && sudo dpkg -i nvim-linux64.deb
cd ${TEMP_DIR}
git clone https://github.com/joermo/dotfiles.git ${USER_DIR}/.config

### rsync = backups, setup with cron to schedule
apt install rsync -y

##############################################
### Python

# Python, pyenv manages python versions, good with poetry.
# Install dependencies
apt install make libssl-dev zlib1g-dev \
 libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
 libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev -y
curl https://pyenv.run | bash


### VSCode
# Add GPG key
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg

# Add apt repo to list
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg

# Update apt repo list and install
sudo apt update
sudo apt install code # or code-insiders

##############################################
### Misc Configuration
# Show system specs in terminal                                                                                                    
apt install neofetch -y       

# Install pyenv and set default version.
pyenv install ${PYENV_VERSION}
pyenv global ${PYENV_VERSION}

removeSnap
##############################################

if [[ $choice == "1" ]]; then
    echo "Running PC Specific installations."
    isDesktop
else
    echo "Running Server Specific installations."
    isServer
fi

echo "Done, add zsh-autosuggestions to ${USER_DIR}/.zshrc plugins, restart terminal."



isDesktop() {
  ##############################################
  ### Element Messenger

  # Get GPG keys
  wget -O /usr/share/keyrings/element-io-archive-keyring.gpg https://packages.element.io/debian/element-io-archive-keyring.gpg
  
  #‍ Add repo to apt list
  echo "deb [signed-by=/usr/share/keyrings/element-io-archive-keyring.gpg] https://packages.element.io/debian/ default main" | sudo tee /etc/apt/sources.list.d/element-io.list

  # Update apt repo list and install
  apt update
  apt install element-desktop -y
  
  ##############################################

  # XONE XBOX wireless controller setup
  echo "Installing Xbox Wireless Dongle support, please unplug your dongle."
  echo "Press enter once you've validated it is unplugged"
  read -r _
  git clone https://github.com/medusalix/xone
  cd xone
  ./install.sh --release
  xone-get-firmware.sh

  ##############################################

  echo "rsync is a backup utility to store a backup of your files with versioning"
  echo "If you would like to setup a schedule for rsync to backup your files, continue after updating ./cron/jobs"
  echo "Setup crontab using root user (crontab -e) (path is /var/spool/cron/crontabs/root) with command:"
  echo "(crontab -u root -l; cat ./cron/jobs ) | crontab -u root -"
}


isServer() {
  ### just - makefile but better (justfile)
  git clone 'https://mpr.makedeb.org/just'
  cd just
  makedeb -si
  cd ${TEMP_DIR}

  # Installs sdkman to install and manage multiple versions of SDKs.
  curl -s "https://get.sdkman.io" | bash
  ##############################################
  ### VirtualBox
  # Download & add GPG keys
  curl https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor > oracle_vbox_2016.gpg
  curl https://www.virtualbox.org/download/oracle_vbox.asc | gpg --dearmor > oracle_vbox.gpg

  sudo install -o root -g root -m 644 oracle_vbox_2016.gpg /etc/apt/trusted.gpg.d/
  sudo install -o root -g root -m 644 oracle_vbox.gpg /etc/apt/trusted.gpg.d/
  echo "deb [arch=amd64] http://download.virtualbox.org/virtualbox/debian $(lsb_release -sc) contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list

  # Add VirtualBox repo
  echo "deb [arch=amd64] http://download.virtualbox.org/virtualbox/debian $(lsb_release -sc) contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list

  # Install VirtualBox + extension pack
  apt update
  apt install linux-headers-$(uname -r) dkms -y
  apt install virtualbox-7.0 -y
  cd ${TEMP_DIR}
  VER=$(curl -s https://download.virtualbox.org/virtualbox/LATEST.TXT)
  wget https://download.virtualbox.org/virtualbox/${VER}/Oracle_VM_VirtualBox_Extension_Pack-${VER}.vbox-extpack
  VBoxManage extpack install Oracle_VM_VirtualBox_Extension_Pack-*.vbox-extpack

  ##############################################
  ### Server Infra Tooling

  ### Kubernetes
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
  apt update
  apt install kubectl -y

  ### awscli
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install

  ### GitHub CLI
  type -p curl >/dev/null || (sudo apt update)
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh -y

  ### Speedtest CLI
  curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
  apt install speedtest -y

  ##############################################
  ### Docker

  # Add Docker's official GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Setup Docker apt repo
  echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    "$(. /etc/os-release && echo "${VERSION_CODENAME}")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Update apt with new repo
  apt update

  # Install Docker/Compose/Buildx
  apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

  ##############################################
  ### Misc Installations

  # Install SSH server for access                                                                                          
  apt install openssh-server -y     
  systemctl enable ssh
  systemctl start ssh                                                                                                                                                                                                sudo systemctl enable ssh                                                                                                                                                                                  sudo systemctl start ssh        

  # Set key permissions
  chmod 600 ${USER_DIR}/.ssh/id_rsa
  chmod 600 ${USER_DIR}/.ssh/id_rsa.pub

  # Start the ssh-agent in the background
  eval $(ssh-agent -s)
  # Set ssh-agent to use the key 
  ssh-add ${USER_DIR}/.ssh/id_rsa

  # Set zsh as default shell if it isn't already
  chsh -s $(which zsh)

  # Configure pyenv
  echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ${USER_DIR}/.oh-my-zsh/custom/scripts.zsh
  echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ${USER_DIR}/.oh-my-zsh/custom/scripts.zsh
  echo 'eval "$(pyenv init -)"' >> ${USER_DIR}/.oh-my-zsh/custom/scripts.zsh

  # Setup crontab using root user (crontab -e) (path is /var/spool/cron/crontabs/$USER)
  (crontab -u root -l; cat ./cron/jobs ) | crontab -u root -

  source ${USER_DIR}/.oh-my-zsh/custom/scripts.zsh

  ##############################################
}

removeSnap() {
  echo "Removing Snap"
  snap --version
  snap list
  systemctl disable snapd.service
  systemctl disable snapd.socket
  systemctl disable snapd.seeded.service
  snap remove firefox
  snap remove gtk-common-themes
  snap remove gnome-3-38-2004
  snap remove snapd-desktop-integration
  snap remove snap-store
  snap remove core20
  snap remove bare
  snap remove snapd
  systemctl stop snapd
  systemctl disable snapd
  systemctl mask snapd
  apt purge snapd -y
  apt-mark hold snapd
  apt autoremove --purge snapd
  rm -rf /snap
  rm -rf /var/snap
  rm -rf /var/lib/snapd
  rm -rf /var/cache/snapd/
  rm -rf ~/snap/
}
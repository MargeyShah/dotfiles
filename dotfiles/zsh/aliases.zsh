# ---------- Aliases ----------
alias vi="vim"
alias vim="nvim"
alias kc="kubectl"
alias tf="terraform"
alias tfi="terraform init"
alias -g gp="grep"
alias python="python3"
alias cfn="cloudformation"
alias themes="kitty +kitten themes"
alias icat="kitty +kitten icat"
alias ls="lsd"
alias duf="df"
alias ping="gping"
alias ps="procs"
alias c='cd'
alias ce="z"
alias dig="doggo"
alias grep="rg"
alias j='just'
alias oc="opencode"

xh() { command xh "$@" --style monokai; }

# ---------- Networking ----------
alias portsused='sudo netstat -tulpn | grep LISTEN'
alias rootcron='sudo nano /etc/crontab'

# ---------- Docker common (all docker commands start with "d") ----------
alias dstop='sudo docker stop $(docker ps -a -q)'
alias dstopall='sudo docker stop $(sudo docker ps -aq)'
alias drm='sudo docker rm $(docker ps -a -q)'
alias dprunevol='sudo docker volume prune'
alias dprunesys='sudo docker system prune -a'
alias ddelimages='sudo docker rmi $(docker images -q)'
alias derase='dstopcont ; drmcont ; ddelimages ; dvolprune ; dsysprune'
alias dprune='ddelimages ; dprunevol ; dprunesys'

# ---------- Keybindings ----------
# Ctrl+Left/Right = word navigation. Cover both the short (\e[5D / \e[5C) and
# extended (\e[1;5D / \e[1;5C) CSI forms so it works across terminals.
bindkey '\e[1;5D' backward-word
bindkey '\e[1;5C' forward-word
bindkey '\e[5D' backward-word
bindkey '\e[5C' forward-word

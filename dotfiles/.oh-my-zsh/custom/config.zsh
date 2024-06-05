alias vi="vim"
alias vim="nvim"
alias kc="kubectl"
alias tf="terraform"
alias tfi="terraform init"
alias -g gp="grep"
alias python="python3"
alias cfn="cloudformation"
alias kc="kubectl"
alias themes="kitty +kitten themes"
alias icat="kitty +kitten icat"
alias ls="lsd"
alias duf="df"
alias ping="gping"
alias ps="procs"
alias c='cd'
alias ce="z"
alias dig="dog"
alias xh='xh "$@" --style monokai'
alias grep="rg"

function run()
{
	for var in "$@"
	do
		${HOME}/scripts/$var.sh
	done
}

matrixup() {
  cd $HOME/matrix-docker-ansible-deploy
  ansible-playbook -i inventory/hosts setup.yml --tags=setup-all,start --vault-password-file inventory/host_vars/matrix.thegrand.co/pass.txt -K
  ansible-playbook -i inventory/hosts $HOME/matrix-docker-ansible-deploy/inventory/host_vars/coturn.yml -K
  cd -
}

dotfiles() {
  $HOME/.scripts/Personal/Ubuntu/fresh_install.sh $1
}

matrix() {
  ssh margey@192.168.1.26
}

function q(){
 ssh $(cat ~/.oh-my-zsh/custom/resources/local_ssh_ips | fzf)
}

function run_disowned() {
  "$@" & disown
}

function dos() {
  # run_disowned and silenced
  run_disowned "$@" 1>/dev/null 2>/dev/null
}


function dcexec() {
  sudo docker exec -it "$@" bash;
}

function currdir() {
  CURRDIR=$(pwd)
}


# NETWORKING
alias portsused='sudo netstat -tulpn | grep LISTEN'
alias rootcron='sudo nano /etc/crontab'

# DOCKER COMMON - All docker commands start with "d"
alias dstop='sudo docker stop $(docker ps -a -q)'
alias dstopall='sudo docker stop $(sudo docker ps -aq)'
alias drm='sudo docker rm $(docker ps -a -q)'
alias dprunevol='sudo docker volume prune'
alias dprunesys='sudo docker system prune -a'
alias ddelimages='sudo docker rmi $(docker images -q)'
alias derase='dstopcont ; drmcont ; ddelimages ; dvolprune ; dsysprune'
alias dprune='ddelimages ; dprunevol ; dprunesys'

if [ "$(hostname)" = 'Pistachio' ]; then
  # CrowdSec
  alias cmet='sudo docker compose -f $HOME/docker/docker-compose-t2.yml exec -t crowdsec cscli metrics'
  alias cupd='sudo docker compose -f $HOME/docker/docker-compose-t2.yml exec -t crowdsec cscli hub update'
  alias clist='sudo docker compose -f $HOME/docker/docker-compose-t2.yml exec -t crowdsec cscli collections list'
  alias cscli='sudo docker compose -f $HOME/docker/docker-compose-t2.yml exec -t crowdsec cscli'
  alias csunban='sudo docker compose -f $HOME/docker/docker-compose-t2.yml exec -t crowdsec cscli decisions delete --ip'

  # Media Server - Docker
  alias dcrun2='currdir; cd $HOME/docker ; sudo docker compose -f $HOME/docker/docker-compose-t2.yml'
  alias dclogs2='currdir; cd $HOME/docker ; sudo docker compose -f $HOME/docker/docker-compose-t2.yml logs -tf --tail="50"'
  alias dcup2='dcrun2 up -d'
  alias dcdown2='dcrun2 down'
  alias dcrec2='dcrun2 up -d --force-recreate'
  alias dcstop2='dcrun2 stop'
  alias dcrestart2='dcrun2 restart'
  alias dcpull2='currdir; cd $HOME/docker ; sudo docker compose -f $HOME/docker/docker-compose-t2.yml pull'


  # Gatherly Infrastructure - Docker
  alias dcrun='currdir; cd $HOME/gatherly ; sudo docker compose -f $HOME/gatherly/docker-compose.yml   '
  alias dclogs='currdir; cd /docker ; sudo docker compose -f $HOME/gatherly/docker-compose.yml logs -tf --tail="50" '
  alias dcup='dcrun up -d '
  alias dcdown='dcrun down '
  alias dcrec='dcrun up -d --force-recreate '
  alias dcstop='dcrun stop '
  alias dcrestart='dcrun restart '
  alias dcpull='currdir; cd $HOME/gatherly ; sudo docker compose -f $HOME/gatherly/docker-compose.yml  pull '

  # Gatherly Apps (Web frontend/backend) - Docker
  alias gtrun='currdir; cd $HOME/gatherly-dev ; sudo docker compose -f $HOME/gatherly-dev/docker-compose.yml   '
  alias gtlogs='currdir; cd /docker ; sudo docker compose -f $HOME/gatherly-dev/docker-compose.yml logs -tf --tail="50" '
  alias gtup='gtrun up -d '
  alias gtdown='gtrun down '
  alias gtrec='gtrun up -d --force-recreate '
  alias gtstop='gtrun stop '
  alias gtrestart='gtrun restart '
  alias gtpull='currdir; cd $HOME/gatherly-dev ; sudo docker compose -f $HOME/gatherly-dev/docker-compose.yml  pull '

  # Supabase Infra
  alias sbrun='currdir; cd $HOME/gatherly/supabase ; sudo docker compose -f $HOME/gatherly/supabase/docker-compose.yml -f $HOME/gatherly/supabase/docker-compose-logging.yml   '
  alias sblogs='currdir; cd $HOME/gatherly/supabase ; sudo docker compose -f $HOME/gatherly/supabase/docker-compose.yml -f $HOME/gatherly/supabase/docker-compose-logging.yml logs -tf --tail="50" '
  alias sbup='sbrun up -d '
  alias sbdown='sbrun down '
  alias sbrec='sbrun up -d --force-recreate '
  alias sbstop='sbrun stop '
  alias sbrestart='sbrun restart '
  alias sbpull='currdir; cd $HOME/gatherly/supabase ; sudo docker compose -f $HOME/gatherly/supabase/docker-compose.yml -f $HOME/gatherly/supabase/docker-compose-logging.yml  pull '
fi

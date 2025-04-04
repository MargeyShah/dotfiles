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
  $HOME/.scripts/Personal/Universal/fresh_install.sh $1
}

function q(){
  ssh $(cat ~/.oh-my-zsh/custom/resources/local_ssh_ips | fzf)
  # if [ -f "/etc/wsl.conf" ]; then
  #   ssh -X $(cat ~/.oh-my-zsh/custom/resources/local_ssh_ips | fzf)
  # else
  #   ssh $(cat ~/.oh-my-zsh/custom/resources/local_ssh_ips | fzf)
  # fi
}

function run_disowned() {
  "$@" & disown
}

function dos() {
  # run_disowned and silenced
  run_disowned "$@" 1>/dev/null 2>/dev/null
}


function dcexec() {
  sudo docker exec -it "$@" 
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
  DOCKER_COMPOSE_T2="$HOME/docker/docker-compose.yml"
  DOCKER_COMPOSE_GATHERLY="$HOME/gatherly/docker-compose.yml"
  DOCKER_COMPOSE_GATHERLY_DEV="$HOME/gatherly-dev/docker-compose.yml"
  DOCKER_COMPOSE_SUPABASE="$HOME/gatherly/supabase/docker-compose.yml"
  DOCKER_COMPOSE_SUPABASE_LOGGING="$HOME/gatherly/supabase/docker-compose-logging.yml"

  # CrowdSec
  alias cmet='sudo docker compose -f $HOME/docker/docker-compose.yml exec -t crowdsec cscli metrics'
  alias cupd='sudo docker compose -f $HOME/docker/docker-compose.yml exec -t crowdsec cscli hub update'
  alias clist='sudo docker compose -f $HOME/docker/docker-compose.yml exec -t crowdsec cscli collections list'
  alias cscli='sudo docker compose -f $HOME/docker/docker-compose.yml exec -t crowdsec cscli'
  alias csunban='sudo docker compose -f $HOME/docker/docker-compose.yml exec -t crowdsec cscli decisions delete --ip'

# Define the paths to your docker-compose files

  # Helper function to change directory and run docker compose commands
  run_compose() {
      local compose_path="$1"
      shift  # Remove the compose path from arguments

      local currdir=$(pwd)
      cd "$(dirname "$compose_path")"  # Change to directory containing compose file
      sudo docker compose -f "$compose_path" "$@"
      cd "$currdir"  # Change back to original directory
  }

  # Function to handle "up" command with option for --remove-orphans
  compose_up() {
      local compose_path="$1"
      shift

      local args=()
      local include_flag=true

      for arg in "$@"; do
          if [[ "$arg" == "--remove-orphans" ]]; then
              include_flag=false
          else
              args+=("$arg")
          fi
      done

      if [ "$include_flag" = true ]; then
          run_compose "$compose_path" "${args[@]}" up -d --remove-orphans
      else
          run_compose "$compose_path" "${args[@]}" up -d
      fi
  }

  # Media Server - Docker
  dcup2() { compose_up "$DOCKER_COMPOSE_T2" "$@"; }
  dclogs2() { run_compose "$DOCKER_COMPOSE_T2" logs -tf --tail="50" "$@"; }
  dcdown2() { run_compose "$DOCKER_COMPOSE_T2" down "$@"; }
  dcrec2() { run_compose "$DOCKER_COMPOSE_T2" up -d --force-recreate "$@"; }
  dcstop2() { run_compose "$DOCKER_COMPOSE_T2" stop "$@"; }
  dcrestart2() { run_compose "$DOCKER_COMPOSE_T2" restart "$@"; }
  dcpull2() { run_compose "$DOCKER_COMPOSE_T2" pull "$@"; }

  # Gatherly Infrastructure - Docker
  dcup() { compose_up "$DOCKER_COMPOSE_GATHERLY" "$@"; }
  dclogs() { run_compose "$DOCKER_COMPOSE_GATHERLY" logs -tf --tail="50" "$@"; }
  dcdown() { run_compose "$DOCKER_COMPOSE_GATHERLY" down "$@"; }
  dcrec() { run_compose "$DOCKER_COMPOSE_GATHERLY" up -d --force-recreate "$@"; }
  dcstop() { run_compose "$DOCKER_COMPOSE_GATHERLY" stop "$@"; }
  dcrestart() { run_compose "$DOCKER_COMPOSE_GATHERLY" restart "$@"; }
  dcpull() { run_compose "$DOCKER_COMPOSE_GATHERLY" pull "$@"; }

  # Gatherly Apps (Web frontend/backend) - Docker
  gtup() { compose_up "$DOCKER_COMPOSE_GATHERLY_DEV" "$@"; }
  gtlogs() { run_compose "$DOCKER_COMPOSE_GATHERLY_DEV" logs -tf --tail="50" "$@"; }
  gtdown() { run_compose "$DOCKER_COMPOSE_GATHERLY_DEV" down "$@"; }
  gtrec() { run_compose "$DOCKER_COMPOSE_GATHERLY_DEV" up -d --force-recreate "$@"; }
  gtstop() { run_compose "$DOCKER_COMPOSE_GATHERLY_DEV" stop "$@"; }
  gtrestart() { run_compose "$DOCKER_COMPOSE_GATHERLY_DEV" restart "$@"; }
  gtpull() { run_compose "$DOCKER_COMPOSE_GATHERLY_DEV" pull "$@"; }

  # Supabase Infra
  # Since Supabase uses two compose files, a special "sbrun" function is added for that setup
  sbrun() {
      local currdir=$(pwd)
      cd "$HOME/gatherly/supabase"
      sudo docker compose -f "$DOCKER_COMPOSE_SUPABASE" -f "$DOCKER_COMPOSE_SUPABASE_LOGGING" "$@"
      cd "$currdir"
  }
  sbup() { sbrun up -d "$@"; }
  sblogs() { sbrun logs -tf --tail="50" "$@"; }
  sbdown() { sbrun down "$@"; }
  sbrec() { sbrun up -d --force-recreate "$@"; }
  sbstop() { sbrun stop "$@"; }
  sbrestart() { sbrun restart "$@"; }
  sbpull() { sbrun pull "$@"; }

  # Debrid order of operations fix
  debridfix () {
    cd /home/margey/docker/stacks/blackhole
    sudo docker compose --profile blackhole_all down
    cd /home/margey/docker
    sudo docker compose stop rclone zurg
    sudo docker compose stop sonarr radarr prowlarr plex
    sleep 10
    sudo docker compose up -d rclone
    cd /home/margey/docker/stacks/blackhole
    sleep 10
    sudo docker compose --profile blackhole_all up -d
    cd /home/margey/docker
    sudo docker compose up -d sonarr radarr prowlarr plex
  }
fi

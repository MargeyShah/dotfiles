# ---------- Server-only docker-compose helpers ----------
# Only defined on server hosts (is_server); the generic docker aliases live in
# aliases.zsh and the interactive helpers in config.zsh.
if is_server; then
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

  # Helper to parse docker arguments
  parse_docker_args() {
      GLOBAL_ARGS=()
      CMD_ARGS=()
      local in_profile=false
      for arg in "$@"; do
          if [ "$in_profile" = true ]; then
              GLOBAL_ARGS+=("$arg")
              in_profile=false
          elif [[ "$arg" == "--profile" || "$arg" == "-p" ]]; then
              GLOBAL_ARGS+=("--profile")
              in_profile=true
          elif [[ "$arg" == --profile=* || "$arg" == -p=* ]]; then
              # Allow format -p=media or --profile=media
              GLOBAL_ARGS+=("--profile=${arg#*=}")
          else
              CMD_ARGS+=("$arg")
          fi
      done

      # Default to profile all if no profile and no specific services/cmd_args are provided
      if [ ${#GLOBAL_ARGS[@]} -eq 0 ] && [ ${#CMD_ARGS[@]} -eq 0 ]; then
          GLOBAL_ARGS=("--profile" "all")
      fi
  }

  # Helper function to change directory and run docker compose commands
  run_compose_parsed() {
      local compose_path="$1"
      shift

      local currdir=$(pwd)
      cd "$(dirname "$compose_path")"  # Change to directory containing compose file
      sudo docker compose -f "$compose_path" "${GLOBAL_ARGS[@]}" "$@" "${CMD_ARGS[@]}"
      cd "$currdir"  # Change back to original directory
  }

  # Function to handle "up" command with option for --remove-orphans
  compose_up() {
      local compose_path="$1"
      shift
      parse_docker_args "$@"

      local include_orphans=true
      local filtered_cmd_args=()
      for arg in "${CMD_ARGS[@]}"; do
          if [[ "$arg" == "--remove-orphans" ]]; then
              include_orphans=false
          else
              filtered_cmd_args+=("$arg")
          fi
      done
      CMD_ARGS=("${filtered_cmd_args[@]}")

      if [ "$include_orphans" = true ]; then
          run_compose_parsed "$compose_path" up -d --remove-orphans
      else
          run_compose_parsed "$compose_path" up -d
      fi
  }

  # Media Server - Docker
  dcup2() { compose_up "$DOCKER_COMPOSE_T2" "$@"; }
  dclogs2() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_T2" logs -tf --tail="50"; }
  dcdown2() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_T2" down; }
  dcrec2() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_T2" up -d --force-recreate; }
  dcstop2() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_T2" stop; }
  dcrestart2() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_T2" restart; }
  dcpull2() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_T2" pull; }

  # Gatherly Infrastructure - Docker
  dcup() { compose_up "$DOCKER_COMPOSE_GATHERLY" "$@"; }
  dclogs() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY" logs -tf --tail="50"; }
  dcdown() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY" down; }
  dcrec() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY" up -d --force-recreate; }
  dcstop() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY" stop; }
  dcrestart() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY" restart; }
  dcpull() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY" pull; }

  # Gatherly Apps (Web frontend/backend) - Docker
  gtup() { compose_up "$DOCKER_COMPOSE_GATHERLY_DEV" "$@"; }
  gtlogs() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY_DEV" logs -tf --tail="50"; }
  gtdown() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY_DEV" down; }
  gtrec() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY_DEV" up -d --force-recreate; }
  gtstop() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY_DEV" stop; }
  gtrestart() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY_DEV" restart; }
  gtpull() { parse_docker_args "$@"; run_compose_parsed "$DOCKER_COMPOSE_GATHERLY_DEV" pull; }

  # Supabase Infra
  # Since Supabase uses two compose files, a special "sbrun" function is added for that setup
  sbrun_parsed() {
      local currdir=$(pwd)
      cd "$HOME/gatherly/supabase"
      sudo docker compose -f "$DOCKER_COMPOSE_SUPABASE" -f "$DOCKER_COMPOSE_SUPABASE_LOGGING" "${GLOBAL_ARGS[@]}" "$@" "${CMD_ARGS[@]}"
      cd "$currdir"
  }
  sbup() { parse_docker_args "$@"; sbrun_parsed up -d; }
  sblogs() { parse_docker_args "$@"; sbrun_parsed logs -tf --tail="50"; }
  sbdown() { parse_docker_args "$@"; sbrun_parsed down; }
  sbrec() { parse_docker_args "$@"; sbrun_parsed up -d --force-recreate; }
  sbstop() { parse_docker_args "$@"; sbrun_parsed stop; }
  sbrestart() { parse_docker_args "$@"; sbrun_parsed restart; }
  sbpull() { parse_docker_args "$@"; sbrun_parsed pull; }

    # Debrid order of operations fix
    debridfix () {
      cd "$HOME/docker"
      sudo docker compose --profile debrid down
      sudo umount /disks/pistachio/plex/Media/remote/realdebrid
      sleep 5
      sudo docker compose up -d decypharr
      sleep 5
      sudo docker compose up -d sonarr radarr prowlarr plex jf prowlarr
    }

    # Zsh completion helper for docker-compose wrappers
    _docker_compose_wrapper_complete() {
        # The last argument is the subcommand (e.g., up, logs, down),
        # and all preceding arguments are the compose file paths.
        local subcommand="${@[-1]}"
        local -a compose_files
        compose_files=("${@[1,-2]}")

        local -a new_words
        new_words=("docker" "compose")
        for file in "${compose_files[@]}"; do
            new_words+=("-f" "$file")
        done
        new_words+=("$subcommand" "${words[@]:1}")

        local offset=$(( 2 + 2 * ${#compose_files[@]} ))
        words=("${new_words[@]}")
        (( CURRENT += offset ))
        _docker
    }

    # Register completions for Media Server (T2)
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_T2' up" dcup2 dcrec2
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_T2' logs" dclogs2
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_T2' down" dcdown2
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_T2' stop" dcstop2
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_T2' restart" dcrestart2
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_T2' pull" dcpull2

    # Register completions for Gatherly Infrastructure
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY' up" dcup dcrec
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY' logs" dclogs
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY' down" dcdown
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY' stop" dcstop
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY' restart" dcrestart
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY' pull" dcpull

    # Register completions for Gatherly Apps (Web)
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY_DEV' up" gtup gtrec
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY_DEV' logs" gtlogs
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY_DEV' down" gtdown
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY_DEV' stop" gtstop
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY_DEV' restart" gtrestart
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_GATHERLY_DEV' pull" gtpull

    # Register completions for Supabase (Multiple Compose files)
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_SUPABASE' '$DOCKER_COMPOSE_SUPABASE_LOGGING' up" sbup sbrec
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_SUPABASE' '$DOCKER_COMPOSE_SUPABASE_LOGGING' logs" sblogs
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_SUPABASE' '$DOCKER_COMPOSE_SUPABASE_LOGGING' down" sbdown
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_SUPABASE' '$DOCKER_COMPOSE_SUPABASE_LOGGING' stop" sbstop
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_SUPABASE' '$DOCKER_COMPOSE_SUPABASE_LOGGING' restart" sbrestart
    compdef "_docker_compose_wrapper_complete '$DOCKER_COMPOSE_SUPABASE' '$DOCKER_COMPOSE_SUPABASE_LOGGING' pull" sbpull
fi

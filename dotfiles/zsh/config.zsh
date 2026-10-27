# ---------- Distrobox ----------
# `box` enters a Distrobox from the host shell. If exactly one container exists
# it enters that one directly; with several it shows an fzf picker.
box() {
    local -a boxes
    local b
    while IFS= read -r b; do
        [ -n "$b" ] && boxes+=("$b")
    done < <(
        distrobox list --no-color 2>/dev/null \
            | awk -F'|' 'NF >= 2 { n = $2; gsub(/^[ \t]+|[ \t]+$/, "", n); if (n != "" && n != "NAME") print n }'
    )

    if [ ${#boxes} -eq 0 ]; then
        echo "box: no Distrobox containers found" >&2
        return 1
    fi

    local choice
    if [ ${#boxes} -eq 1 ]; then
        choice="${boxes[1]}"
    else
        choice="$(printf '%s\n' "${boxes[@]}" | fzf --prompt='box> ')" || return 0
        [ -n "$choice" ] || return 0
    fi

    distrobox enter "$choice"
}

# ---------- Repo helpers ----------
function run()
{
	for var in "$@"
	do
		${HOME}/scripts/$var.sh
	done
}

matrixup() {
  cd $HOME/matrix-docker-ansible-deploy
  git pull && just update
  ansible-playbook -i inventory/hosts setup.yml --tags=setup-all,start --vault-password-file inventory/host_vars/matrix.thegrand.co/pass.txt
  cd -
}

dotfiles() {
  $HOME/.scripts/setup/fresh_install.sh
}

nvimup() {
  bash "$HOME/.scripts/setup/fresh_install.sh" --nvim
}

# ---------- SSH hosts ----------
# Local SSH hosts for quick connect (used by q())
LOCAL_SSH_IPS=(
  "margey@Pistachio"
  "pi@octopi"
  "margey@Macadamia"
)

function q(){
  ssh $(printf '%s\n' "${LOCAL_SSH_IPS[@]}" | fzf)
}

# ---------- Process helpers ----------
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

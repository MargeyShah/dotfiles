# ---------- Hostname-based environment loading ----------
# Define the hostname lists for each environment class.
# These drive which snippets/config load on a given machine.

export HOSTS_WSL=( "Element-Windows" )
export HOSTS_LINUX=( "Pistachio" "octopi" "Macadamia" )
export HOSTS_MAC=( "FR95FPVKK6" )

export HOSTS_SERVER=( "Pistachio" )
export HOSTS_WORK_MAC=( "FR95FPVKK6" )

# current_env -> "wsl" | "linux" | "mac"
# Explicit hostname lists win (role overrides); unlisted hosts fall back to
# physical OS detection so this stays aligned with setup/fresh_install.sh.
current_env() {
    local h="${HOST:-$(hostname)}"
    if [[ " ${HOSTS_WSL[@]} " == *" $h "* ]]; then
        echo "wsl"
    elif [[ " ${HOSTS_LINUX[@]} " == *" $h "* ]]; then
        echo "linux"
    elif [[ " ${HOSTS_MAC[@]} " == *" $h "* ]]; then
        echo "mac"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "mac"
    elif [[ -f /etc/wsl.conf ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    else
        echo "linux"
    fi
}

# is_env <wsl|linux|mac> — true if current env matches
is_env() {
    [[ "$(current_env)" == "$1" ]]
}

# is_linuxlike — true on apt/Linuxbrew hosts (linux or WSL), i.e. not mac
is_linuxlike() {
    is_env linux || is_env wsl
}

# is_server — true if the current host is a server
is_server() {
    local h="${HOST:-$(hostname)}"
    [[ " ${HOSTS_SERVER[@]} " == *" $h "* ]]
}

# is_work_mac — true if the current host is the work Mac
is_work_mac() {
    local h="${HOST:-$(hostname)}"
    [[ " ${HOSTS_WORK_MAC[@]} " == *" $h "* ]]
}

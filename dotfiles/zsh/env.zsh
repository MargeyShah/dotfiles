# ---------- Hostname-based environment loading ----------
# Define the hostname lists for each environment class.
# These drive which snippets/config load on a given machine.

export HOSTS_WSL=( "Element-Windows" )
export HOSTS_LINUX=( "Pistachio" "octopi" "Macadamia" )
export HOSTS_MAC=( "FR95FPVKK6" )

# current_env -> "wsl" | "linux" | "mac" | "unknown"
current_env() {
    local h="${HOST:-$(hostname)}"
    if [[ " ${HOSTS_WSL[@]} " == *" $h "* ]]; then
        echo "wsl"
    elif [[ " ${HOSTS_LINUX[@]} " == *" $h "* ]]; then
        echo "linux"
    elif [[ " ${HOSTS_MAC[@]} " == *" $h "* ]]; then
        echo "mac"
    else
        echo "unknown"
    fi
}

# is_env <wsl|linux|mac|unknown> — true if current env matches
is_env() {
    [[ "$(current_env)" == "$1" ]]
}

# is_hostname <name> — true if the current host matches
is_hostname() {
    [[ "${HOST:-$(hostname)}" == "$1" ]]
}

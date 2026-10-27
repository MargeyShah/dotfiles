# ---------- Hostname-based environment loading ----------
# Define the hostname lists for each environment class.
# These drive which snippets/config load on a given machine.

# OS-class lists (exactly one matches per host).
export HOSTS_WSL=( "Element-Windows" )
export HOSTS_LINUX=( "Pistachio" "octopi" "Macadamia" "Element-Bazzite" )
export HOSTS_MAC=( "FR95FPVKK6" "Pine" )

# Role lists — subsets of the OS-class lists above (a host in a role list
# must also be in its OS-class list, e.g. server ⊂ linux, work_mac ⊂ mac).
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

# is_linux_desktop — true if the current host is in the Linux desktop list.
# (is_env linux has an "any Linux" fallback for unlisted hosts, so it is not
# strict enough for per-host gating; this tests the explicit list only.)
is_linux_desktop() {
    local h="${HOST:-$(hostname)}"
    [[ " ${HOSTS_LINUX[@]} " == *" $h "* ]]
}

# is_server — true on a server host, and inside a Distrobox container.
# Containers are treated like servers so zellij does not run there (zellij
# lives on the host shell). $CONTAINER_ID is set by distrobox/podman inside the
# box and needs no binary, so this is safe on hosts without distrobox installed.
is_server() {
    [ -n "${CONTAINER_ID:-}" ] && return 0
    local h="${HOST:-$(hostname)}"
    [[ " ${HOSTS_SERVER[@]} " == *" $h "* ]]
}

# is_work_mac — true if the current host is the work Mac
is_work_mac() {
    local h="${HOST:-$(hostname)}"
    [[ " ${HOSTS_WORK_MAC[@]} " == *" $h "* ]]
}

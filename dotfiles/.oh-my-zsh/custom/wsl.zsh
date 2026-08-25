if [ -f "/etc/wsl.conf" ]; then
    eval "$(ssh-agent -s)">/dev/null
    ssh-add ${HOME}/.ssh/id_ed25519_professional 2>/dev/null
fi

pbcopy() {
    printf '\033]52;c;%s\a' "$(base64 -w0)"
}

# ---------- WSL ----------
if is_env wsl; then
    # LS_COLORS fix for WSL2 folder coloring. Can't move to another file.
    LS_COLORS="ow=01;36;40" && export LS_COLORS

    # Start ssh-agent and load the professional key
    if command -v ssh-agent >/dev/null 2>&1; then
        eval "$(ssh-agent -s)" >/dev/null
        ssh-add ${HOME}/.ssh/id_ed25519_professional 2>/dev/null
    fi

    # WSL pbcopy (copy to Windows clipboard)
    pbcopy() {
        printf '\033]52;c;%s\a' "$(base64 -w0)"
    }
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# ---------- Zinit (Plugin Manager) ----------
export ZINIT_HOME="$HOME/.local/share/zinit/zinit.git"
if [[ ! -f "$ZINIT_HOME/zinit.zsh" ]]; then
    print -P "%F{220}Installing Zinit (zdharma-continuum/zinit)...%f"
    command mkdir -p "$(dirname "$ZINIT_HOME")"
    command git clone https://github.com/zdharma-continuum/zinit "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# ---------- Prompt: Starship ----------
export STARSHIP_LOG=error
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# ---------- Custom snippets (from dotfiles repo) ----------
# Kept in ~/.local/share/zinit/snippets/ -> symlinked to ~/.scripts/dotfiles/zsh/
zinit snippet "$HOME/.local/share/zinit/snippets/env.zsh"
zinit snippet "$HOME/.local/share/zinit/snippets/init_apps.zsh"
zinit snippet "$HOME/.local/share/zinit/snippets/config.zsh"

# ---------- Completion ----------
autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
compflags="-d ${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump"
# Skip insecure-dir check when running as root (e.g. sudo -E zsh)
[[ $EUID -eq 0 ]] && compflags="-u $compflags"
compinit ${=compflags}

# Better completion UX
zstyle ':completion:*' menu select
zstyle ':completion:*' rehash true
zstyle ':completion:*' verbose yes

# Case-insensitive + partial matching
zstyle ':completion:*' matcher-list \
    'm:{a-z}={A-Za-z}' \
    'r:|=' \
    'l:|=* r:|=*'

# Group matches
zstyle ':completion:*' group-name ''

# Group descriptions
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'

# Colored completion menus
zstyle ':completion:*' list-colors ''

# Better process completion
zstyle ':completion:*:*:*:*:processes' command \
    'ps -u $USER -o pid,user,comm -w -w'

# ---------- Plugins ----------
# Fish-style suggestions (turbo async)
zinit ice wait lucid
zinit light zsh-users/zsh-autosuggestions

# Syntax highlighting (must be last; turbo async)
zinit ice wait lucid
zinit light zsh-users/zsh-syntax-highlighting

# ---------- History ----------
# ignores duplicate history commands
setopt hist_ignore_all_dups

# Increase zsh command history
HISTFILE=~/.zsh_history
HISTSIZE=999999
SAVEHIST=$HISTSIZE

# ---------- SDKMAN ----------
# version manager for java adjacent development kits
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# ---------- Zoxide ----------
# smart cd replacement (command is 'z')
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ---------- Lazy pyenv ----------
# https://github.com/pyenv/pyenv
export PYENV_ROOT="$HOME/.pyenv"

load-pyenv() {
    unset -f pyenv python python2 python3 pip pip2 pip3 2>/dev/null
    unalias pyenv python python2 python3 pip pip2 pip3 2>/dev/null
    command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    if [ -f /etc/NIXOS ] || grep -qi '^ID=nixos' /etc/os-release 2>/dev/null; then
        eval "$(pyenv virtualenv-init -)"
    fi
}

unalias pyenv python python2 python3 pip pip2 pip3 2>/dev/null
for cmd in pyenv python python2 python3 pip pip2 pip3; do
    eval "$cmd() { load-pyenv; command $cmd \"\$@\"; }"
done

# ---------- fzf (lazy) ----------
__fzf_init() {
    [[ -n "$_FZF_INIT_DONE" ]] && return
    _FZF_INIT_DONE=1
    [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
    command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)
}
precmd_functions+=(__fzf_init)

# ---------- Lazy NVM (nvm owns node) ----------
export NVM_DIR="$HOME/.nvm"

# Expose nvm's node/npm to child processes (nvim, tree-sitter, etc.) without
# sourcing nvm.sh on every shell. nvm/node/npm still lazy-load below for
# switching versions. Picks the highest installed version.
if ! command -v node >/dev/null 2>&1 && [ -d "$NVM_DIR/versions/node" ]; then
    _nvm_bin="$(
        for _d in "$NVM_DIR"/versions/node/v*(/N); do
            [ -x "$_d/bin/node" ] && print -r -- "${${_d:t}#v} $_d"
        done |
        awk '{ split($1, a, "."); printf "%d %d %d %s\n", a[1], a[2], a[3], $2 }' |
        sort -n -k1,1 -k2,2 -k3,3 |
        tail -n1 |
        awk '{ print $4 }'
    )"
    [ -n "$_nvm_bin" ] && export PATH="$_nvm_bin/bin:$PATH"
    unset _nvm_bin _d
fi

load-nvm() {
    unset -f nvm node npm npx 2>/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
    # Homebrew keeps nvm.sh under its keg; use it if ~/.nvm/nvm.sh is absent.
    if ! command -v nvm >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
        local _brew_nvm
        _brew_nvm="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
        [[ -s "$_brew_nvm" ]] && source "$_brew_nvm"
    fi
    command -v nvm >/dev/null 2>&1 || return 0
    # Activate the default version so nvm's node precedes any other (e.g. homebrew)
    nvm use default --silent 2>/dev/null
    # Ensure nvm's active node bin is first in PATH (nvm doesn't always prepend here)
    local node_bin
    node_bin="$(dirname "$(nvm which node 2>/dev/null)")"
    [[ -n "$node_bin" && "$PATH" != "$node_bin:"* ]] && export PATH="$node_bin:$PATH"
    rehash
}

# nvm is a function, so call it directly (not via `command`)
nvm() { load-nvm; nvm "$@"; }

for cmd in node npm npx; do
    eval "$cmd() { load-nvm; command $cmd \"\$@\"; }"
done

# ---------- opencode ----------
export PATH="$HOME/.opencode/bin:$PATH"

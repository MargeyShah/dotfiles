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

eval "$(zoxide init zsh)"
function run()
{
	for var in "$@"
	do
		${HOME}/scripts/$var.sh
	done
}


sshi(){
  ssh -i ${HOME}/.ssh/coreeng.pem ec2-user@"$1"
}

function ps2(){
 ssh -A $(cat ~/.oh-my-zsh/custom/ps2_bastions | fzf)
}

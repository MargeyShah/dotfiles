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
  ansible-playbook -i inventory/hosts setup.yml --tags=seutp-all,start --vault-password-file inventory/host_vars/matrix.thegrand.co/pass.txt -K
  ansible-playbook -i inventory/hosts $HOME/matrix-docker-ansible-deploy/inventory/host_vars/coturn.yml -K
  cd -
}

dotfiles() {
  $HOME/.scripts/Personal/Ubuntu/fresh_install.sh $1
}

matrix() {
  ssh margey@192.168.1.26
}

function q(){
 ssh $(cat ~/.oh-my-zsh/custom/resources/local_ssh_ips | fzf)
}

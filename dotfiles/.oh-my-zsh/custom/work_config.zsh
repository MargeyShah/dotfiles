if [ "$(hostname)" = 'MAC-YH44TR' ]; then
    export AWS_DEFAULT_PROFILE=HULU_SSO
    export DOOZER_HOME=/Users/margey.shah/Documents/test/doozer
    export VAULT_ADDR="https://secrets.staging.hulu.com"

    sshi(){
    ssh -i ${HOME}/.ssh/coreeng.pem ec2-user@"$1"
    }

    function ps2(){
    ssh -A $(cat ~/.oh-my-zsh/custom/ps2_bastions | fzf)
    }
fi
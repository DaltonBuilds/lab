alias k='kubectl'

source /etc/bash_completion # not needed on macos

source <(kubectl completion bash)

complete -o default -F __start_kubectl k

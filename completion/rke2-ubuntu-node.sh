
# bash completion for rke2-ubuntu-node.sh
_rke2_node_complete() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  local opts="--allow-leaf-ca --ca --dns --gw --hostname --iface --images --install-url --ip-cidr --pass --registry --role --server-url --skip-verify --template --token --token-file --user --version -h --help"
  COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
}
complete -F _rke2_node_complete rke2-ubuntu-node.sh

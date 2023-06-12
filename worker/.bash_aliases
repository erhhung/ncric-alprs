# get AWS region
awsrgn() {
  local az=$(_instmeta placement/availability-zone)
  echo ${az/%[a-z]/}
}

# show ECR domain name
ecrdomain() {
  local account=$(_instmeta identity-credentials/ec2/info | \
    jq -r .AccountId)
  echo "$account.dkr.ecr.$(awsrgn).amazonaws.com"
}

alias d='docker '
alias di='d images'
alias k='kubectl '
alias h='helm '

drmc() {
  docker rm $(docker ps -qa --no-trunc --filter "status=exited") 2> /dev/null
}
drmi() {
  docker rmi $(docker images --filter "dangling=true" -q --no-trunc) 2> /dev/null
  docker rmi $(docker images | grep "none" | awk '/ / { print $3 }') 2> /dev/null
}

# get/set kubectl namespace
kns() {
  if [[ -z ${1+x} ]]; then
    # invoked without args
    kubectl config view -o json \
      | jq -r '."current-context" as $cc |
          .contexts[] |
          select(.name == $cc) |
          .context.namespace // "default"'
  else
    kubectl config set-context \
      --current --namespace "$1"
  fi
}

__container_shell_init_script() {
  # do NOT use any single quotes!
  cat <<"EOT"
# use /tmp if $HOME is read-only
[ -w $HOME ] || export HOME=/tmp
cd $HOME
touch .hushlogin
cat <<"EOF" > .profile
# get user name via "id" in case uid has no name
PS1="\[\033[1;36m\]\$(id -un 2> /dev/null)\[\033[1;31m\]@\[\033[1;32m\]\h:\[\033[1;35m\]\w\[\033[1;31m\]\$\[\033[0m\] "
alias cdd="cd \$OLDPWD"
alias ls="ls --color=auto"
alias ll="ls -alF"
alias lt="ll -tr"
alias l=less
EOF
EOT
  cat <<EOT
$@ # run any additional commands
(hash bash 2> /dev/null) && exec bash --rcfile ~/.profile -l \
                         || exec   sh -l
EOT
}

# dexec <container> [command]
dexec() {
  local cont=$1; shift

  # start container if not running
  local id=$(docker ps -q --filter name=$cont)
  [ -z "$id" ] && docker start "$cont" > /dev/null 2>&1

  if [[ -z ${1+x} ]]; then # run shell if no command
    set -- sh -c "$(__container_shell_init_script)"
  fi
  docker exec -it "$cont" "$@"
}

# kexec <pod>[:container] [command]
kexec() {
  local pod=$1 cont=(); shift

  if [[ "$pod" =~ ^[^:]+:[^:]+$ ]]; then
    # pod:container => pod -c container
    cont=(-c "${pod/*:/}")
    pod=${pod/:*/}
  else
    # if there's > 1 container, explicitly choose first one to avoid warning
    cont=($(kubectl get pod "$pod" -o jsonpath='{.spec.containers[*].name}'))
    cont=(-c $cont)
  fi
  if [[ -z ${1+x} ]]; then # run shell if no command
    set -- sh -c "$(__container_shell_init_script)"
  fi
  kubectl exec "$pod" "${cont[@]}" -it -- "$@"
}

# drun <image> [opts...] [command]
# command, if more than one word,
# must be quoted as a single arg
drun() {
  local cmd opts image=$1; shift
  if [[ "$1" != -* ]]; then
    cmd="$1"; shift
    opts=( "$@" )
  else
    cmd="${@: -1}"
    opts=( "$@" )
    unset opts[${#opts[@]}-1]
  fi

  local cont name=()
  cont=${image/*\//}
  cont=${cont/:*/}

  # container name = image name unless taken
  local id=$(docker ps -aq --filter name=$cont)
  [ -z "$id" ] && name=(--name "$cont")

  eval "cmd=($cmd)" # separate command & args
  docker run -it "${opts[@]}" "${name[@]}" "$image" "${cmd[@]}"
}

# docker run -it --rm bash/sh
# dsh <image> [opts...]
dsh() {
  local image=${1:-amazonlinux:2}
  # must pass $cmd to drun() as a single argument!
  local cmd="-c '`__container_shell_init_script`'"
  drun "$image" --rm "${@:2}" --entrypoint sh "$cmd"
}

# kubectl run -it --rm bash/sh
# ksh [image] [opts...]
# image: uses ECR if prefixed ./
# default image is "amazonlinux:2"
ksh() {
  local pod script image=${1:-amazonlinux:2}

  # decorate pod name with random chars
  # to avoid collision with similar pod
  pod=$(n=10000; printf "%s-temp-admin-%04d" $USER $((RANDOM % n)))
  [[ "$image" == ./* ]] && image="$(ecrdomain)/${image:2}"
  script="$(__container_shell_init_script)"

  kubectl -n default run $pod \
    -l="app=temp-admin" -it --rm "${@:2}" \
    --quiet --restart=Never --image "$image" \
    --command -- sh -c "$script"
}

# $@ = words array
__complete__word1() {
  [[ $COMP_CWORD -eq 1 ]] && __complete__words "$@"
}
# $@ = words array
__complete__words() {
  local words=("$@") cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "${words[*]}" -- "$cur"))
}

# get Docker images
_complete_dimgs() {
  local words=($(docker images --format '{{.Repository}}:{{.Tag}}' \
                 | grep -v '<none>' | sed -En 's/:latest$//;p'))
  __complete__word1 "${words[@]}"
}

# get container IDs/names
_complete_dexec() {
  local words=($(docker ps -a --format '{{.ID}} {{.Names}}'))
  __complete__word1 "${words[@]}"
}

# get pod names
_complete_kexec() {
  local words=($(kubectl get pods -o name 2> /dev/null \
                 | sed -En 's/^pod\///;p'))
  __complete__word1 "${words[@]}"
}

# get namespaces
_complete_kns() {
  local words=($(kubectl get namespaces -o name 2> /dev/null \
                 | sed -En 's/^namespace\///;p'))
  __complete__word1 "${words[@]}"
}

eval "$(kubectl completion bash)"
complete -o default -F __start_kubectl k

# ecrpush is script in /usr/local/bin
complete -F _complete_dimgs ecrpush
complete -F _complete_dexec dexec
complete -F _complete_kexec kexec
complete -F _complete_dimgs drun
complete -F _complete_dimgs dsh
complete -F _complete_dimgs ksh
complete -F _complete_kns   kns

_alprs_url() {
  local conf="s3://$CONFIG_BUCKET/shuttle/shuttle.yaml"
  aws s3 cp $conf - --quiet | \
    yq '.postgres.config |
        (.username + ":" + .password) as $creds | .jdbcUrl |
        sub(".+//([^?]+).*$", "postgresql://" + $creds + "@${1}")'
}
_atlas_url() {
  local conf="s3://$CONFIG_BUCKET/flapper/flapper.yaml"
  aws s3 cp $conf - --quiet | \
    yq '.datalakes[] | select(.name == "atlas") |
        (.username + ":" + .password) as $creds | .url |
        sub(".+//(.+)$", "postgresql://" + $creds + "@${1}")'
}
_alprs() {
  psql $(_alprs_url) "$@"
}
_atlas() {
  psql $(_atlas_url) "$@"
}
alprs() {
  pgcli $(_alprs_url) "$@"
}
atlas() {
  pgcli $(_atlas_url) "$@"
}

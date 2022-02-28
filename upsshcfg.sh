#!/usr/bin/env bash

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}

_reqcmds terraform egrep jq || exit $?

_altcmd() {
  local cmd
  for cmd in "$@"; do
    if hash $cmd 2> /dev/null; then
      printf $cmd && return
    fi
  done
  return 1
}

 known=".ssh/known_hosts"
config=".ssh/config"

# first make backup copies in case update goes awry...
mkdir -p /tmp/.ssh && cp -a ~/$config ~/$known /tmp/.ssh/

env=$(terraform output -raw env)
# use gsed on BSD/macOS
sed=$(_altcmd gsed sed)

# remove obsolete host entries from ~/.ssh/known_hosts
while read host id; do
  # save ID to show later
  eval "export $host=$id"
  $sed -Ei "/^$id/d" ~/$known
done < <(
  $sed -En "{N;s/^Host +(alprs$env[a-z]+).+HostName +(i-.+)$/\1 \2/p;D}" ~/$config
)

# update ~/.ssh/config
while read host id; do
  case $host in
    bastion)       host=bast ;;
    postgresql)    host=pg   ;;
    elasticsearch) host=es   ;;
    conductor)     host=cond ;;
    datastore)     host=data ;;
    indexer)       host=idx  ;;
    *)             continue
  esac
  host="alprs$env$host"
  $sed -Ei "/^Host +$host.*$/{\$!{N;s/^Host +$host.+HostName.+$/Host $host\n  HostName $id/;t;P;D}}" ~/$config
  printf "%-13s %s => %s\n" $host: $(eval "echo \$$host") $id
done < <(
  terraform output -json | \
    jq -r 'to_entries[] | select(.key | endswith("_instance_id")) |
                              "\(.key | rtrimstr("_instance_id")) \(.value.value)"'
)

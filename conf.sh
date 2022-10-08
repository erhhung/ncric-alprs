#!/usr/bin/env bash

# push/pull/diff "config/ENV.tfvars" file against
# its repository at s3://alprs-infra-ENV/tfstate/
#
# usage: conf.sh <push|pull|diff> [dev|prod]

cd "$(dirname "$0")/config"

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
# https://dandavison.github.io/delta/installation.html
_reqcmds aws delta || exit $?

if [[ ! "$1" =~ ^(push|pull|diff)$ ||
      ! "$2" =~ ^(dev|prod)?$ ]]; then
  echo >&2 "Usage: conf.sh <push|pull|diff> [dev|prod]"
  [ "$1" ] && exit 1 || exit 0
fi

action=$1 env=$2

env_via_ls() {
  local tfvars=($(ls -1 {dev,prod}.tfvars 2> /dev/null))
  [ ${#tfvars[@]} -eq 1 ] || return $?
  env="${tfvars/.*/}"
}

env_via_tf() {
  printf 'Retrieving Terraform output variables...'
  env=$(../tf.sh output -raw env 2>&1)
  if [ $? -ne 0 ]; then
    echo >&2 -e "\n$env"
    return 1
  fi
  echo "DONE."
}

# determine env via $2 or ls or Terraform output
[ "$env" ] || env_via_ls || env_via_tf || exit $?

conf_local="$env.tfvars"
conf_remote="s3://alprs-infra-$env/tfstate/$conf_local"

if [[ "$action" != pull && ! -f $conf_local ]]; then
  echo >&2 "File not found: config/$conf_local"
  exit 1
fi

s3_cp() {
  local profile=alprs
  [ "$env" == dev ] && profile+=com || profile+=gov
  aws --profile $profile s3 cp "$@" || exit $?
}

push() {
  local conf_backup="$conf_remote.backup"
  echo "Writing: $conf_backup"
  s3_cp $conf_remote $conf_backup
  echo "Writing: $conf_remote"
  s3_cp $conf_local $conf_remote
}

pull() {
  local conf_backup="$conf_local.backup"
  if [ -f $conf_local ]; then
    echo "Writing: config/$conf_backup"
    cp -a $conf_local $conf_backup
  fi
  echo "Writing: config/$conf_local"
  s3_cp $conf_remote $conf_local
}

diff() {
  local diff=$(which diff)
  local temp_remote=$conf_local.remote
  echo "Reading: $conf_remote"
  s3_cp    $conf_remote $temp_remote
  $diff -q $conf_local  $temp_remote &> /dev/null
  if (($?)); then
    delta -s $temp_remote $conf_local && exit 1
  else
    echo -e "\xf0\x9f\x91\x8d No differences found."
  fi
}

$action

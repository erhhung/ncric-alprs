#!/usr/bin/env bash

# optionally combine "cwagent-main.yaml" with host-specific "cwagent-name.yaml"
# outputs JSON containing "cwagent.json" for Terraform's "external" data source
#
# usage: cwagent.sh [name] [VAR1=value1] [VAR2=value2] ...

cd "`dirname "$0"`"

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
# envsubst: brew install gettext
_reqcmds envsubst  yq jq || exit $?

_altcmd() {
  local cmd
  for cmd in "$@"; do
    if hash $cmd 2> /dev/null; then
      printf $cmd && return
    fi
  done
  return 1
}
# use yq v4 syntax
yq=$(_altcmd yq4 yq)

if [[ "$1" != *=* ]]; then
  name="$1"; shift
fi
while [ $# -gt 0 ]; do
  eval "export $1"; shift
done

if [ "$name" ]; then
  "$yq" -o json eval-all \
    'select(fileIndex == 0) *
     select(fileIndex == 1)' \
    cwagent-main.yaml \
    cwagent-$name.yaml
else
  "$yq" -o json cwagent-main.yaml
fi | \
  # envsubst concatenated YAML
  envsubst | jq -sR '{json:.}'

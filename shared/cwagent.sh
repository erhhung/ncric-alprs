#!/usr/bin/env bash

# optionally combine "cwagent_main.yaml" with host-specific "cwagent_logs.yaml"
# outputs JSON containing "cwagent.json" for Terraform's "external" data source
#
# usage: cwagent.sh [folder] [VAR1=value1] [VAR2=value2] ...

cd "$(dirname "$0")"

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
  folder="$1"; shift
fi
while [ $# -gt 0 ]; do
  eval "export $1"; shift
done

"$yq" -o json <( (
  cat cwagent_main.yaml
  if [ "$folder" ]; then
    logs="../$folder/cwagent_logs.yaml"
    [ -f "$logs" ] && cat "$logs"
  fi
# run envsubst on concatenated YAML
) | envsubst) | jq -sR '{"json":.}'

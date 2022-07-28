#!/usr/bin/env bash

# convert key=value pairs in given .tfvars/.conf
# file to YAML, and then to JSON for Terraform's
# "external" data source

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds yq || exit $?

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

sed -E 's/^ *([a-z0-9]+) *= */\1: /' "$1" | \
  "$yq" -o=json -I=0 -M -

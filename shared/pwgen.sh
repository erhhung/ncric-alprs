#!/usr/bin/env bash

# generate n-character (default is 10) passwords and
# output JSON for Terraform's "external" data source
#
#   usage: pwgen.sh [n=10] [name1] ... [nameN]
# example: pwgen.sh
#          pwgen.sh 8 foo bar
#  output: {"secret":"olaefie8Su"}
#          {"foo":"iel4AhGh","bar":"aNoo3pha"}

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
# pwgen: brew install pwgen
_reqcmds pwgen jq || exit $?

n=$1
# test whether $1 is an integer, and use 10 if not
[ ${n-0} -eq ${n-1} 2> /dev/null ] && shift || n=10

N=$#
# if no names provided, use "secret"
[ $N -eq 0 ] && N=1 && set -- secret

pwgen $n $N  | jq -nRMc '
   [inputs] as $secrets |
  reduce range($secrets | length) as $i
  ({}; . *= {($ARGS.positional[$i]): $secrets[$i]})' \
  --args "$@"

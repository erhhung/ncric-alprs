#!/usr/bin/env bash

# generate x n-character passwords (n is an
# optional parameter; default=10) and output
# JSON for Terraform's "external" data source
#
#   usage: pwgen.sh [n=10] [x=1]
# example: pwgen.sh 10 2
#  output: {"secret1":"olaefie8Su","secret2":"Cie0ii0dee"}

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds pwgen jq || exit $?

pwgen ${1:-10} ${2:-1}  | jq -nRMc '
   [inputs] as $secrets |
  reduce range($secrets | length) as $i
  ({}; . *= {"secret\($i + 1)": $secrets[$i]})'

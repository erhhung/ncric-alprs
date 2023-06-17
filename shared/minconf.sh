#!/usr/bin/env bash

# extract only the effective lines in input conf file
# outputs JSON for Terraform's "external" data source
#
# usage: minconf.sh <file> [VAR1=value1] [VAR2=value2] ...

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
_reqcmds envsubst jq || exit $?

file="$1"; shift
while [ $# -gt 0 ]; do
  eval "export $1"; shift
  dosub=true
done

# don't feed minified output through envsubst
# unless at least one VAR=value was provided
sed -E '/^[[:blank:]]*(#|$)/d; s/[[:blank:]]*#.*//' "$file" | \
  ([ "$dosub" ] && envsubst || cat) | \
  jq -sR '{text: .|rtrimstr("\n")}'

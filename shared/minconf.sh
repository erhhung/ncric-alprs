#!/usr/bin/env bash

# extract only the effective lines in input conf file
# outputs JSON for Terraform's "external" data source

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
done

sed -E '/^[[:blank:]]*(#|$)/d; s/[[:blank:]]*#.*//' "$file" | \
  envsubst | jq -sR '{"text":.}'

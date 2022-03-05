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
_reqcmds yq || exit 1

sed -E 's/^ *([a-z0-9]+) *= */\1: /' "$1" | yq r -j -

#!/usr/bin/env bash

# run "terraform taint" command on each argument while
# expanding recognized names into their full addresses

#   usage: taint.sh <alias_or_address> ...
# example: taint.sh bastion postgresql

cd $(dirname "$0")

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds terraform || exit $?

full_addr() {
  case "$1" in
    bastion)
      echo "module.$1_host.aws_instance.host"
      ;;
    postgresql| \
    elasticsearch| \
    conductor| \
    datastore| \
    indexer)
      echo "module.$1_server.aws_instance.host"
      ;;
    *)
      echo "$1"
  esac
}

for addr in "$@"; do
  terraform taint "$(full_addr "$addr")"
done

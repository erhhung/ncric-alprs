#!/usr/bin/env bash

# run "terraform taint" command on each argument while
# expanding recognized names into their full addresses

#   usage: taint.sh <alias_or_address|all> ...
# example: taint.sh bastion postgresql

[ "${1,,}" == all ] && set -- \
  postgresql \
  elasticsearch \
  conductor \
  datastore \
  indexer \
  bastion \
  worker

cd "`dirname "$0"`"

_altcmd() {
  local cmd
  for cmd in "$@"; do
    if hash $cmd 2> /dev/null; then
      printf $cmd && return
    fi
  done
  return 1
}

# use GNU grep on BSD/macOS
# ggrep: brew install grep
grep=$(_altcmd ggrep grep)

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
    worker)
      echo "module.$1_node.aws_instance.host"
      ;;
    *)
      echo "$1"
  esac
}

highlight() {
  $grep -E --color=never  '^\w+' | \
  $grep -P --color=always 'Resource instance \K\S+'
  # Perl regex \K restarts match from that position
}

for addr in "$@"; do
  output=$(./tf.sh taint "$(full_addr "$addr")" 2>&1)
  [ $? -eq 0 ] && highlight <<< "$output" && continue
  echo >&2 "$output"
  exit 1
done

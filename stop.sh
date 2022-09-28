#!/usr/bin/env bash

# gracefully stop major services on all
# or specified hosts in preparation for
# reprovisioning those instances.
#
# usage: stop.sh [name_no_tf_ext] ...

cd "`dirname "$0"`"

# prompt user for Y/N
# single-key response
# <message> [default]
ask() {
  local prompt default reply

  if [ "${2:-}" = "Y" ]; then
    prompt="Y/n"
    default=Y
  elif [ "${2:-}" = "N" ]; then
    prompt="y/N"
    default=N
  else
    prompt="y/n"
    default=
  fi

  while true; do
    printf "\e[s$1 [$prompt] "
    read reply < /dev/tty

    if [ -z "$reply" ]; then
      reply=$default
    fi
    case "$reply" in
      Y*|y*) return 0 ;;
      N*|n*) return 1 ;;
    esac
  done
}

# defaults (in optimal order)
HOSTS=(
  worker
  bastion
  indexer
  datastore
  conductor
  elasticsearch
  postgresql
)
[ "$1" ] && HOSTS=("$@")

host_abbrev() {
  case $1 in
    postgresql)    echo pg   ;;
    elasticsearch) echo es   ;;
    conductor)     echo cond ;;
    datastore)     echo data ;;
    indexer)       echo idx  ;;
    bastion)       echo bast ;;
    worker)        echo work ;;
    *)             return 1
  esac
}

echo >&2 "Stop services on hosts:"
for  host in ${HOSTS[@]}; do
  if host_abbrev  $host > /dev/null; then
    echo >&2 "  * $host"
    hosts+=($host)
  fi
done
if [ ${#hosts} -eq 0 ]; then
  echo >&2 "No valid host provided!"
  exit 1
fi
ask >&2 "Proceed?" N || exit 0

printf '\nRetrieving Terraform output variables...'
env=$(./tf.sh output -raw env)
echo "DONE."

stop_bastion() {
  sudo service rundeckd stop
  pkill npm  # lattice-org
}

stop_worker() {
  pkill shuttle
  pkill flapper
}

stop_service() {
  sudo pkill java  # conductor/datastore/indexer
}

stop_elasticsearch() {
  sudo service nginx         stop
  sudo service kibana        stop
  sudo service elasticsearch stop
}

stop_postgresql() {
  sudo service postgresql stop
}

for host in ${hosts[@]}; do
  abbrev=$(host_abbrev $host)
  script=$(declare -f stop_$host || \
           declare -f stop_service)

  printf "Stopping services on host \"$host\"..."
  # skip first line of script, the function declaration
  ssh "alprs${env}${abbrev}" "$(tail +2 <<< "$script")" > /dev/null 2>&1
  echo "DONE."
done

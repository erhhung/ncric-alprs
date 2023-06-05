#!/usr/bin/env bash

# gracefully stop major services on all
# or specified hosts in preparation for
# reprovisioning those instances.
#
# usage: stop.sh [name_no_tf_ext] ...

cd "`dirname "$0"`"

env_via_tfvars() {
  local tfvars=($(cd config; ls -1 {dev,prod}.tfvars 2> /dev/null))
  [ ${#tfvars[@]} -eq 1 ] || return $?
  env="${tfvars/.*/}"
}

env_via_tfstate() {
  printf "Retrieving Terraform output variables..."
  env=$(./tf.sh output -raw env 2>&1)
  if [ $? -ne 0 ]; then
    echo >&2 -e "\n$env"
    return 1
  fi
  echo "DONE."
}

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
  postgresql2
  postgresql1
)
[ "$1" ] && HOSTS=("$@")

host_abbrev() {
  case $1 in
    postgresql1)   echo pg1  ;;
    postgresql2)   echo pg2  ;;
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
ask >&2 "Proceed?" N && echo || exit 0

# determine env via .tfvars file or tf state
env_via_tfvars || env_via_tfstate || exit $?

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

stop_postgresql1() {
  sudo service postgresql stop
}
stop_postgresql2() {
  sudo service postgresql stop
}

 BLUE='\033[0;34m'
NOCLR='\033[0m'

for host in ${hosts[@]}; do
  abbrev=$(host_abbrev $host)
  script=$(declare -f stop_$host || \
           declare -f stop_service)

  printf "Stopping services on host \"${BLUE}${host}${NOCLR}\"..."
  # skip first line of script, the function declaration
  ssh "alprs${env}${abbrev}" "$(tail +2 <<< "$script")" > /dev/null 2>&1
  echo "DONE."
done

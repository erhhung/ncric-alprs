#!/usr/bin/env bash

# ensure all servers have completed bootstrapping
# and critical services are running on each server
#
# USAGE: check.sh [hosts...]

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
  lf=true
}

# determine env via .tfvars file or tf state
env_via_tfvars || env_via_tfstate || exit $?

[ "$1" ] || set -- \
  postgresql1 \
  postgresql2 \
  elasticsearch \
  conductor \
  datastore \
  indexer \
  bastion \
  worker

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

# get max width of args
max_width() {
  local str len max=0
  for str in "$@"; do
    len=${#str}
    ((max=len>max?len:max))
  done
  echo $max
}

# pgrep only ignores its own process,
# whereas we also need to ignore bash
proc_grep() {
  [ "`ps auxw | grep "$1" | grep -v grep | grep -v 'bash -c'`" ]
}

check_bootstrap() (
  if [ ! -f /bootstrap.log ]; then
    echo -e "${YELLOW}Bootstrapping${NOCLR} not started yet!"
    exit 2
  fi
  if tail -1 /bootstrap.log | grep -q "END BOOTSTRAP"; then
    echo -e "${GREEN}Bootstrapping${NOCLR} completed."
    exit 0
  fi
  if proc_grep bootstrap.sh; then
    echo -e "${YELLOW}/bootstrap.sh${NOCLR} still running."
    exit 2
  fi
  echo -e "${RED}Bootstrapping${NOCLR} FAILED!"
  echo -e $WHITE"`tail -5 /bootstrap.log`"$NOCLR
  exit 1
)

# <port...>
check_listening() (
  w=$(max_width $@)
  for port in $@; do
    if nc -z localhost $port; then
      printf -v port "${GREEN}${port}${NOCLR}"
      printf "Port %$((w+11))s listening.\n" $port
    else
      echo -e "Port ${RED}${port}${NOCLR} not listening!"
      exit 1
    fi
  done
)

# <path...>
check_disk_free() (
  w=$(max_width "$@")
  for path in "$@"; do
    pcnt=$(df "$path" | sed -En 's/.+( ([0-9]+))%.+/\2/p')
    if [ 0$pcnt -le 90 ]; then
      printf -v path "${GREEN}${path}${NOCLR}"
      printf "Volume %-$((w+11))s ${pcnt}%%.\n" "$path"
    else
      echo -e "Volume ${RED}${path}${NOCLR} over 90% (${RED}${pcnt}%${NOCLR})!"
      exit 1
    fi
  done
)

# <app...>
check_available() (
  w=$(max_width "$@")
  for app in "$@"; do
    if hash "$app" 2> /dev/null; then
      printf -v app "\"${GREEN}${app}${NOCLR}\""
      printf "App %-$((w+13))s available.\n" "$app"
    else
      echo -e "App \"${RED}${app}${NOCLR}\" not available!"
      exit 1
    fi
  done
)

# <process...>
check_running() (
  w=$(max_width "$@")
  for proc in "$@"; do
    if proc_grep "$proc"; then
      printf -v proc "\"${GREEN}${proc}${NOCLR}\""
      printf "Process %-$((w+13))s running.\n" "$proc"
    else
      echo -e "Process \"${RED}${proc}${NOCLR}\" not running!"
      exit 1
    fi
  done
)

check_postgresql1() {
  check_bootstrap      || return $?
  check_listening 5432 || return $?
  check_disk_free $HOME /opt/postgresql
}
check_postgresql2() {
  check_bootstrap      || return $?
  check_listening 5432 || return $?
  check_disk_free $HOME /opt/postgresql
}

check_elasticsearch() {
  check_bootstrap || return $?
  check_listening 9200 9300 5601 \
                  9201 9301 443  || return $?
  check_disk_free $HOME /opt/elasticsearch
}

check_conductor() {
  check_bootstrap      || return $?
  check_running   java || return $?
  check_listening 5701 || return $?
  check_disk_free $HOME
}

check_datastore() {
  check_bootstrap           || return $?
  check_running   java      || return $?
  check_listening 8080 8443 || return $?
  check_disk_free $HOME
}

check_indexer() {
  check_bootstrap           || return $?
  check_running   java      || return $?
  check_listening 8080 8443 || return $?
  check_disk_free $HOME
}

check_bastion() {
  check_bootstrap           || return $?
  check_running   java npm  || return $?
  check_listening 4440 9000 || return $?
  check_disk_free $HOME
}

check_worker() {
  check_bootstrap || return $?
  check_available shuttle \
                  flapper || return $?
  check_disk_free $HOME
}

funcs=$(cat <<EOF
  GREEN='\033[0;32m'
 YELLOW='\033[1;33m'
    RED='\033[0;31m'
  WHITE='\033[1;37m'
  NOCLR='\033[0m'

`declare -f max_width`
`declare -f proc_grep`
`declare -f check_bootstrap`
`declare -f check_listening`
`declare -f check_disk_free`
`declare -f check_available`
`declare -f check_running`
EOF
)

  BLUE='\033[0;34m'
 GREEN='\033[0;32m'
   RED='\033[0;31m'
 NOCLR='\033[0m'
THMSUP='\xf0\x9f\x91\x8d'
THMSDN='\xf0\x9f\x91\x8e'

for host in "$@"; do
  abbrev=$(host_abbrev $host)
  if [ $? -ne 0 ]; then
    [ "$lf" ] && echo >&2
    echo >&2 -e "${RED}Invalid host \"$host\"!${NOCLR}"
    result="FAILED!"
    break
  fi
  check=$(declare -f check_$host)

  [ "$lf" ] && echo
  echo -e "Checking host \"${BLUE}${host}${NOCLR}\"..."
  ssh "alprs${env}${abbrev}" "$funcs; $check; check_$host"
  if [ $? -ne 0 ]; then
    result="FAILED!"
    break
  fi
  lf=true
done
[ ! "$result" ] && color="$THMSUP $GREEN" \
                || color="$THMSDN $RED"
echo -e "\n${color}Check ${result:-successful.}${NOCLR}"
[ ! "$result" ]

#!/usr/bin/env bash

# ensure all servers have completed bootstrapping
# and critical services are running on each server

cd "`dirname "$0"`"

HOSTS=(
  postgresql
  elasticsearch
  conductor
  datastore
  indexer
  bastion
  worker
)

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

printf 'Retrieving Terraform output variables...'
env=$(./tf.sh output -raw env)
echo "DONE."

check_bootstrap() (
  if [ ! -f /bootstrap.log ]; then
    echo -e "${YELLOW}Bootstrapping${NOCLR} not started yet!"
    exit 2
  fi
  if tail -1 /bootstrap.log | grep -q "END BOOTSTRAP"; then
    echo -e "${GREEN}Bootstrapping${NOCLR} completed."
    exit 0
  fi
  if pgrep -f bootstrap.sh > /dev/null; then
    echo -e "${YELLOW}/bootstrap.sh${NOCLR} still running."
    exit 2
  fi
  echo -e "${RED}Bootstrapping${NOCLR} FAILED!"
  echo -e $WHITE"`tail -5 /bootstrap.log`"$NOCLR
  exit 1
)

# <app...>
check_available() (
  for app in "$@"; do
    if hash $app 2> /dev/null; then
      printf -v app "\"${GREEN}${app}${NOCLR}\""
      # left justify for 7-character app name
      printf "App %-20s available.\n" "$app"
    else
      echo -e "App \"${RED}${app}${NOCLR}\" not available!"
      exit 1
    fi
  done
)

# <port...>
check_listening() (
  for port in $@; do
    if nc -z localhost $port; then
      printf "Port ${GREEN}%4d${NOCLR} listening.\n" $port
    else
      echo -e "Port ${RED}${port}${NOCLR} not listening!"
      exit 1
    fi
  done
)

# <process...>
check_running() (
  for proc in "$@"; do
    if pgrep -f "$proc" > /dev/null; then
      printf -v proc "\"${GREEN}${proc}${NOCLR}\""
      # left justify for 4-character proc name
      printf "Process %-17s running.\n" "$proc"
    else
      echo -e "Process \"${RED}${proc}${NOCLR}\" not running!"
      exit 1
    fi
  done
)

check_postgresql() {
  check_bootstrap || return $?
  check_listening 5432
}

check_elasticsearch() {
  check_bootstrap || return $?
  check_listening 9200 9300 5601 \
                  9201 9301 443
}

check_conductor() {
  check_bootstrap    || return $?
  check_running java || return $?
  check_listening 5701
}

check_datastore() {
  check_bootstrap    || return $?
  check_running java || return $?
  check_listening 8080 8443
}

check_indexer() {
  check_bootstrap    || return $?
  check_running java || return $?
  check_listening 8080 8443
}

check_bastion() {
  check_bootstrap        || return $?
  check_running java npm || return $?
  check_listening 4440 9000
}

check_worker() {
  check_bootstrap || return $?
  check_available shuttle flapper
}

funcs=$(cat <<EOF
  GREEN='\033[0;32m'
 YELLOW='\033[1;33m'
    RED='\033[0;31m'
  WHITE='\033[1;37m'
  NOCLR='\033[0m'

`declare -f check_bootstrap`
`declare -f check_available`
`declare -f check_listening`
`declare -f check_running`
EOF
)

  BLUE='\033[0;34m'
 GREEN='\033[0;32m'
   RED='\033[0;31m'
 NOCLR='\033[0m'
THMSUP='\xf0\x9f\x91\x8d'
THMSDN='\xf0\x9f\x91\x8e'

for host in ${HOSTS[@]}; do
  abbrev=$(host_abbrev     $host)
  check=$(declare -f check_$host)

  echo -e "\nChecking host \"${BLUE}${host}${NOCLR}\"..."
  ssh "alprs${env}${abbrev}" "$funcs; $check; check_$host"

  [ $? -ne 0 ] && result="FAILED!" && break
done
[ ! "$result" ] && color="$THMSUP $GREEN" \
                || color="$THMSDN $RED"
echo -e "\n${color}Check ${result:-successful.}${NOCLR}"
[ ! "$result" ]

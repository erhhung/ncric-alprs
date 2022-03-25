#!/usr/bin/env bash

# This user data script bootstraps an EC2 instance.

cd /root 2> /dev/null
script=$(basename "$0" .sh)
exec > >(tee -a /$script.log | logger -t $script ) 2>&1
echo -e "[$(date -R)] ===== BEGIN ${script^^} =====\n"
echo "Bash version: ${BASH_VERSINFO[@]}"
set -xeo pipefail

# run <func> [user]
run() {
  local func=$1 user=$2
  echo "[${user:-root}] $func"
  if [ $user ]; then
    export -f $func
    su $user -c "bash -c 'cd \$HOME; $func'"
  else
    $func
  fi
}

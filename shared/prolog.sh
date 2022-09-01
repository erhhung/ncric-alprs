#!/usr/bin/env bash

# This user data script bootstraps an EC2 instance.
# It forms the head of every custom "/bootstrap.sh",
# and is concatenated by the instance's "boot.tftpl"
# and "boot.sh", followed by its custom "install.sh",
# and finally ending with "epilog.sh".

__ts() {
  date "+%Y-%m-%d %T"
}

cd /root 2> /dev/null
script=$(basename "$0" .sh)
exec > >(tee -a /$script.log | logger -t $script ) 2>&1
echo -e "[`__ts`|root] ===== BEGIN ${script^^} =====\n"
echo "Bash version: ${BASH_VERSINFO[@]}"
echo -e "TERM=$TERM\n"
set  -eo pipefail

# run <func> [user] [args...]
run() {
  local func=$1 user=${2:-root} args="${@:3}"
  echo -e "\n[`__ts`|$user] $func $args"
  export -f $func
  if [ $user == root ]; then
    # always run in subshell
    (cd /root; set -x; $func "${@:3}")
  else
    su $user -c "bash -c 'cd \$HOME; set -x; $func $args'"
  fi
}

export -f __ts

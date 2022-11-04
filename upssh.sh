#!/usr/bin/env bash

# update ~/.ssh/config with current instance IDs.
# script expects the config to contain names and
# sections as formatted in "sshconfig".
#
# usage: upssh.sh

cd "`dirname "$0"`"

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds jq || exit $?

_altcmd() {
  local cmd
  for cmd in "$@"; do
    if hash $cmd 2> /dev/null; then
      printf $cmd && return
    fi
  done
  return 1
}

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

# determine env via .tfvars file or tf state
env_via_tfvars || env_via_tfstate || exit $?

 known=".ssh/known_hosts"
config=".ssh/config"

# first make backup copies in case the update goes awry...
mkdir -p /tmp/.ssh && cp -a ~/$config ~/$known /tmp/.ssh/

# use GNU sed on BSD/macOS
# gsed: brew install gnu-sed
sed=$(_altcmd gsed sed)

old_host_ids() {
  $sed -En "{N;s/^Host +(alprs$env[a-z]+).+HostName +(i-.+)$/\1 \2/p;D}" ~/$config
}

printf 'Removing old hosts from "known_hosts"...'
while read host id; do
  # save ID to show later
  eval "export $host=$id"
  $sed -Ei "/^$id/d" ~/$known
done < <(
  old_host_ids
)
echo "DONE."

get_outputs() {
  ./tf.sh output -json | \
    jq -r  "to_entries[] | select(.key | endswith(\"_$1\")) |
                              \"\(.key | rtrimstr(\"_$1\")) \(.value.value)\""
}

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

# update ~/.ssh/config
while read host id; do
  host="alprs$env$(host_abbrev $host)" || continue

  $sed -Ei "/^Host +$host.*$/{\$!{N;s/^Host +$host.+HostName.+$/Host $host\*\n  HostName $id/;t;P;D}}" ~/$config
  printf "%-$((10 + ${#env}))s %s => %s\n" $host: $(eval "echo \$$host") $id
done < <(
  get_outputs instance_id
)

printf 'Updating "/etc/hosts" on bastion host...'
script=$(cat <<'EOF'
add_host() {
  if awk '{print $2}' /etc/hosts | egrep -q "^$1$"; then
    sudo sed -Ei "s/^[0-9.]+[[:space:]]+$1([[:space:]].*)?$/$2\\t$1/" /etc/hosts
  else
    echo -e "$2\t$1" | sudo tee -a /etc/hosts > /dev/null
  fi
};
EOF
)

script+=$(cat <<EOF
while read host ip; do
  add_host \$host \$ip
done <<'EOT'
$(get_outputs private_ip)
EOT
EOF
)

ssh "alprs${env}bast" "$script" > /dev/null 2>&1
echo "DONE."

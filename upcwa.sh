#!/usr/bin/env bash

# update CloudWatch Agent configurations on all servers
# AFTER Terraform apply (first ensure SSH configuration
# has been updated via "upssh.sh")

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

update_cwagent() {
  CWAGENT_HOME=/opt/aws/amazon-cloudwatch-agent
  aws s3 cp s3://$(hostname | sed -En 's|^alprs([^-]+)-(.+)$|alprs-infra-\1/userdata/\2|p')/cwagent.json $CWAGENT_HOME/etc/amazon-cloudwatch-agent.json
  $CWAGENT_HOME/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:$CWAGENT_HOME/etc/amazon-cloudwatch-agent.json
}

# skip the function declaration on first line
script=$(declare -f update_cwagent | tail +2)

  BLUE='\033[0;34m'
 GREEN='\033[0;32m'
   RED='\033[0;31m'
 NOCLR='\033[0m'
THMSUP='\xf0\x9f\x91\x8d'
THMSDN='\xf0\x9f\x91\x8e'

for host in ${HOSTS[@]}; do
  abbrev=$(host_abbrev $host)

  [ "$lf" ] && echo
  echo -e "Updating CloudWatch Agent on host \"${BLUE}${host}${NOCLR}\"..."
  ssh "alprs${env}${abbrev}" -- sudo su -lc "${script@Q}"

  [ $? -ne 0 ] && result="FAILED!" && break
  lf=true
done
[ ! "$result" ] && color="$THMSUP $GREEN" \
                || color="$THMSDN $RED"
echo -e "\n${color}Update ${result:-successful.}${NOCLR}"
[ ! "$result" ]

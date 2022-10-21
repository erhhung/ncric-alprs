#!/usr/bin/env bash

# update CloudWatch Agent configurations on all servers
# AFTER Terraform apply (first ensure SSH configuration
# has been updated via "upssh.sh")

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

update_cwagent() {
  CWAGENT_HOME=/opt/aws/amazon-cloudwatch-agent
  aws s3 cp s3://$(hostname | sed -En 's|^alprs([^-]+)-(.+)$|alprs-infra-\1/userdata/\2|p')/cwagent.json $CWAGENT_HOME/etc/amazon-cloudwatch-agent.json
  $CWAGENT_HOME/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:$CWAGENT_HOME/etc/amazon-cloudwatch-agent.json
}

# skip the function declaration on first line
script=$(declare -f update_cwagent | tail +2)

for host in ${HOSTS[@]}; do
  abbrev=$(host_abbrev $host)

  echo -e "\nUpdating CloudWatch Agent on host \"$host\"..."
  ssh "alprs${env}${abbrev}" -- sudo su -lc "${script@Q}"

  [ $? -ne 0 ] && result="FAILED!" && break
done
echo -e "\nUpdate ${result:-successful.}" && [ ! "$result" ]

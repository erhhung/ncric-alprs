#!/usr/bin/env bash

cd $(dirname "$0")
mkdir -p .disabled

HOSTS=(
  bastion
  postgresql
  elasticsearch
  conductor
#  datastore
#  indexer
)
[ "$1" ] && HOSTS=("$@")

for host in ${HOSTS[@]}; do
  [ -f "$host.tf" ] && mv "$host.tf" .disabled/
done

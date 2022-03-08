#!/usr/bin/env bash

cd $(dirname "$0")
mkdir -p .disabled
cd .disabled

HOSTS=(
  bastion
  postgresql
  elasticsearch
  conductor
  datastore
  indexer
  shared
)
[ "$1" ] && HOSTS=("$@")

for host in ${HOSTS[@]}; do
  [ -f "$host.tf" ] && mv "$host.tf" ..
done

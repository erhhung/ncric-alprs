#!/usr/bin/env bash

# move the specified or default set of .tf files,
# if any exist, from this folder to the .disabled
# folder to exclude them from stack provisioning

#   usage: disable.sh [name_no_tf_ext] ...
# example: disable.sh ebs

cd "`dirname "$0"`"
mkdir -p .disabled

# defaults
TF_FILES=(
  postgresql
  elasticsearch
  conductor
  datastore
  indexer
  bastion
  rundeck
  worker
  webapp
  shared
)
[ "$1" ] && TF_FILES=("$@")

for tf in ${TF_FILES[@]}; do
  [ -f "${tf/%.tf/}.tf" ] && \
    mv "${tf/%.tf/}.tf" .disabled
done

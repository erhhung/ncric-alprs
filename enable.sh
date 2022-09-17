#!/usr/bin/env bash

# move the specified or default set of .tf files,
# if any exist, from the .disabled folder to this
# folder so they are used for stack provisioning

#   usage: enable.sh [name_no_tf_ext] ...
# example: enable.sh ebs

cd $(dirname "$0")
mkdir -p .disabled
cd .disabled

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
  [ -f "$tf.tf" ] && mv "$tf.tf" ..
done

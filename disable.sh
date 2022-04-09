#!/usr/bin/env bash

# move the specified or default set of .tf files,
# if any exist, from this folder to the .disabled
# folder to exclude them from stack provisioning

#   usage: disable.sh [name_no_tf_ext] ...
# example: disable.sh ebs

cd $(dirname "$0")
mkdir -p .disabled

# defaults
TF_FILES=(
  shared
  bastion
  postgresql
  elasticsearch
  conductor
  datastore
  indexer
)
[ "$1" ] && TF_FILES=("$@")

for tf in ${TF_FILES[@]}; do
  [ -f "$tf.tf" ] && mv "$tf.tf" .disabled
done

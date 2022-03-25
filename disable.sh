#!/usr/bin/env bash

cd $(dirname "$0")
mkdir -p .disabled

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

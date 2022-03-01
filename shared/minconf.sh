#!/usr/bin/env bash

# extract only the effective lines in input conf file
# outputs JSON for Terraform's "external" data source

file="$1"; shift
while [ $# -gt 0 ]; do
  eval "export $1"; shift
done

sed -E '/^[[:blank:]]*(#|$)/d; s/[[:blank:]]*#.*//' "$file" | \
  envsubst | jq -sR '{"text":.}'

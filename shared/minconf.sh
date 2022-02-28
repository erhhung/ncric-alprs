#!/bin/sh

# extract only the effective lines in input conf file
# outputs JSON for Terraform's "external" data source

sed -E '/^[[:blank:]]*(#|$)/d; s/[[:blank:]]*#.*//' "$1" | jq -sR '{"text":.}'

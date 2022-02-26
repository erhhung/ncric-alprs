#!/bin/bash

script="postgresql-install"
exec > >(tee /var/log/$script.log | logger -t $script ) 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== BEGIN ${script^^} ====="
set -xeo pipefail

# two databases, including "atlas"
# use letsencrypt to generate cert

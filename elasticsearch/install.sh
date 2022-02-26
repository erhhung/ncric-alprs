#!/bin/bash

script="elasticsearch-install"
exec > >(tee /var/log/$script.log | logger -t $script ) 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== BEGIN ${script^^} ====="
set -xeo pipefail

install_java() {
  apt update
  apt install -y openjdk-11-jdk
}

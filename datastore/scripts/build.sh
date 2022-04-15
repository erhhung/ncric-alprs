#!/usr/bin/env bash

# usage: build.sh [branch]
# optional branch override (default is main)

if [ ! -d ~/openlattice ]; then
  echo >&2 'Git repo ~/openlattice not found!'
  exit 1
fi

set -euxo pipefail
cd ~/openlattice

git stash > /dev/null
git checkout ${1:-main}
git pull --rebase --prune
git submodule update --recursive
git stash pop 2> /dev/null || true

cd rhizome
# pull critical fix not yet
# merged into parent module
git pull origin develop
cd ..

./gradlew clean :datastore:distTar -x test

if [ -d /opt/openlattice/datastore ]; then
  mv /opt/openlattice/datastore /opt/openlattice/datastore_$(date +"%Y-%m-%d_%H-%M-%S")
else
  mkdir -p /opt/openlattice
fi
mv -f ./datastore/build/distributions/datastore.tgz /opt/openlattice/

cd /opt/openlattice
tar xzvf datastore.tgz

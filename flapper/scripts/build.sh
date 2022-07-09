#!/usr/bin/env bash

# usage: build.sh [branch]
# optional branch override (default is main)

PROJECT=flapper

if [ ! -d ~/openlattice ]; then
  echo >&2 'Git repo "openlattice" not found!'
  exit 1
fi

set -euxo pipefail
cd ~/openlattice

if [ ! -d $PROJECT ]; then
  echo >&2 "Git repo \"$PROJECT\" not found!"
  exit 1
fi

cd $PROJECT
git stash > /dev/null
git checkout ${1:-main}
git pull --rebase --prune
git stash pop 2> /dev/null || true

# don't build from the super-repo
./gradlew clean :distTar -x test

if [ -d /opt/openlattice/$PROJECT ]; then
  mv /opt/openlattice/$PROJECT /opt/openlattice/${PROJECT}_$(date +"%Y-%m-%d_%H-%M-%S")
fi
mv -f build/distributions/$PROJECT.tgz /opt/openlattice/

cd /opt/openlattice
tar xzvf $PROJECT.tgz

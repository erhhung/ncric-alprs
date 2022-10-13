#!/usr/bin/env bash

# usage: build.sh [branch]
# optional branch override (default is develop)

PROJECT=indexer

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

git stash > /dev/null
git checkout ${1:-develop}
git pull --rebase --prune
git submodule update --recursive
git stash pop 2> /dev/null || true

cd rhizome
# pull critical fix not yet
# merged into parent module
git pull origin develop
cd ..

./gradlew clean :$PROJECT:distTar -x test

dest=/opt/openlattice/$PROJECT
if [ -d "$dest" ]; then
  mv $dest ${dest}_$(date +"%Y-%m-%d_%H-%M-%S")
fi
mv -f $PROJECT/build/distributions/$PROJECT.tgz /opt/openlattice/

cd /opt/openlattice
tar xzvf $PROJECT.tgz

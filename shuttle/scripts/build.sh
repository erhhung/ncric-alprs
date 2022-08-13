#!/usr/bin/env bash

# usage: build.sh [branch]
# optional branch override (default is main)

PROJECT=shuttle

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
git checkout ${1:-main}
git pull --rebase --prune
git submodule update --recursive
git stash pop 2> /dev/null || true

cd rhizome
# pull critical fix not yet
# merged into parent module
git pull origin develop
cd ..

# change hardcoded base and integration URLs to $API_URL (exported externally)
sed -Ei "s#https://(api|integration)(\.\w+)?\.openlattice\.com/?#$API_URL/#" \
  ./api/src/main/java/com/openlattice/client/RetrofitFactory.java

./gradlew clean :$PROJECT:distTar -x test

if [ -d /opt/openlattice/$PROJECT ]; then
  mv /opt/openlattice/$PROJECT /opt/openlattice/${PROJECT}_$(date +"%Y-%m-%d_%H-%M-%S")
fi
mv -f $PROJECT/build/distributions/$PROJECT.tgz /opt/openlattice/

cd /opt/openlattice
tar xzvf $PROJECT.tgz

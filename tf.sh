#!/usr/bin/env bash

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds pee docker || exit $?

_log() {
  # show color output but strip color from log file
  pee cat "sed 's/\x1b\[[0-9;]*[mGKHF]//g' >> $log"
}

docker_build() {
  echo "Building Docker image \"$tag:latest\"..."
  docker build \
    --no-cache \
    -t $tag  . \
    --progress plain  2>&1 |    _log
  [ ${PIPESTATUS[0]} -eq 0 ] && _log <<< "" || exit ${PIPESTATUS[0]}
}

docker_run() {
  docker run \
    -it --rm \
    -h infra \
    -v $(pwd):/infra \
    -v $HOME/.aws:/root/.aws \
    -v $HOME/.ssh:/root/.ssh \
    --name astrometrics \
    $tag "$@" 2>&1 | _log
  exit ${PIPESTATUS[0]}
}

cd "$(dirname  "$0")"
log=$(basename "$0" .sh).log; rm -f "$log"
tag=$(sed -En "s/LABEL name=\"(.+)\"/\1/p" Dockerfile)
[ "$(docker images --format '{{.Repository}}' $tag)" ] || docker_build
docker_run terraform "$@"

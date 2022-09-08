#!/usr/bin/env bash

cd "$(dirname "$0")"

if [ ! "$1" ]; then
  script=$(basename "$0")
  tfvars=$(find config -name '*.tfvars' | head -1)
  cat <<EOF
Run Terraform command from custom Docker container
that has all the necessary tools already installed.

  Usage: $script <terraform_command>
Example: $script plan -var-file $tfvars
EOF
  exit
fi

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
log=$(basename "$0" .sh).log
rm -f "$log"

docker_build() {
  _log >&2 <<< "Building Docker image \"$tag:latest\"..."
  docker build \
    --no-cache \
    -t $tag  . \
    --progress plain  2>&1 |    _log >&2
  [ ${PIPESTATUS[0]} -eq 0 ] && _log >&2 <<< "" || exit ${PIPESTATUS[0]}
}

docker_run() {
  docker run \
    -it --rm \
    -h infra \
    -v $(pwd):/infra \
    -v $HOME/.aws:/root/.aws \
    -v $HOME/.ssh:/root/.ssh \
    --name maiveric-infra \
    $tag "$@" 2>&1 | _log
  exit ${PIPESTATUS[0]}
}

tag=$(sed -En "s/LABEL name=\"(.+)\"/\1/p" Dockerfile)
[ "$(docker images --format {{.ID}} $tag)" ] || docker_build
docker_run terraform "$@"

#!/usr/bin/env bash

# zip "project" folder into "astrometrics.rdproject.jar"
# and output JSON for Terraform's "external" data source

ENV=$1 # dev|prod

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds zip md5sum || exit $?

_altcmd() {
  local cmd
  for cmd in "$@"; do
    if hash $cmd 2> /dev/null; then
      printf $cmd && return
    fi
  done
  return 1
}

clean_up() {
  rm -rf $tmp_dir
}
trap clean_up EXIT

tmp_dir=$(mktemp -d)
src_dir=$(realpath "$(dirname "$0")")
prj_dir="$src_dir/project"
cp -a $prj_dir/* $tmp_dir
cd $tmp_dir

[ -d META-INF ] || exit $?

# use GNU sed on BSD/macOS
# gsed: brew install gnu-sed
sed=$(_altcmd gsed sed)

# replace ENV in job email subjects
(cd rundeck-AstroMetrics/jobs

 ENV="Rundeck:${ENV^^}"
_ENV='Rundeck:PROD'
while read file; do
  $sed -i "s/$_ENV/$ENV/" $file
done < <(
  grep -l $_ENV *.xml
))

JAR="$src_dir/astrometrics.rdproject.jar"
rm -f "$JAR"

# source files must have identical timestamps
# in order to get identical zip file checksum
find . -type f -exec touch -t 202201010000 "{}" \;

# -r recurse subdirs
# -D no dir entries
# -X no extra attrs
# -9 compress harder
# -T test integrity
# -q quiet operation
# -x exclude files
zip -rDX9Tq "$JAR" . -x \*.yaml

md5=($(md5sum "$JAR"))
echo -n '{"md5":"'$md5'"}'

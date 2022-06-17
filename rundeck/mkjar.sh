#!/usr/bin/env bash

# zip "project" folder into "astrometrics.rdproject.jar"
# and output JSON for Terraform's "external" data source

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds zip md5 || exit $?

cd "$(dirname "$0")/project"
[ -d META-INF ] || exit $?

JAR=../astrometrics.rdproject.jar
rm -f $JAR

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
zip -rDX9Tq $JAR . -x \*.yaml

echo -n '{"md5":"'$(md5 -q $JAR)'"}'

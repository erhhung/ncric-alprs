#!/usr/bin/env bash

# build "pyntegrationsncric.whl" and output
# JSON for Terraform "external" data source

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds md5 || exit $?

cd $(dirname "$0")/pyntegrationsncric
[ -f setup.py ] || exit $?

clean_up() {
  rm -rf dist build *-info
}
clean_up
trap clean_up EXIT

WHL=../../pyntegrationsncric.whl
rm -f $WHL

python3 ./setup.py -q bdist_wheel &> /dev/null

# repack wheel (just zip file) after updating stable
# timestamps in order to get identical file checksum
cd dist
unzip -oq *.whl
find . -type f -exec touch -t 202201010000 "{}" \;

# -r recurse subdirs
# -D no dir entries
# -X no extra attrs
# -9 compress harder
# -T test integrity
# -q quiet operation
# -x exclude files
zip -rDX9Tq $WHL . -x \*.whl

echo -n '{"md5":"'$(md5 -q $WHL)'"}'
cd ..

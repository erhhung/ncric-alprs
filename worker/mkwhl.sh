#!/usr/bin/env bash

# build specified Python wheel package (pyntegrationsncric.whl or
# olpy.whl) and output JSON for Terraform's "external" data source

PROJECT=$1 # pyntegrationsncric|olpy
API_URL=$2 # https://api.astrometrics.us

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

clean_up() {
  cd /tmp; rm -rf $PROJECT
}
trap clean_up EXIT

prj_dir="$(realpath "$(dirname "$0")/$PROJECT")"
rm -rf /tmp/$PROJECT
cp -a  "$prj_dir" /tmp
cd /tmp/$PROJECT

[ -f setup.py ] || exit $?

# replace "base_url" parameter values
BASE_URL='https://api.openlattice.com'
while read file; do
  sed -i '' "s|$BASE_URL|$API_URL|" $file
done < <(grep -rl $BASE_URL)

WHL="${prj_dir}.whl"
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

#!/usr/bin/env bash

# build specified Python wheel package (pyntegrationsncric.whl or
# olpy.whl) and output JSON for Terraform's "external" data source

PROJECT=$1 # pyntegrationsncric|olpy
API_URL=$2 # https://api.[dev.]astrometrics.us
 REGION=$3 # us-gov-west-1|us-west-2

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds python3 unzip zip md5sum || exit $?

_altcmd() {
  local cmd
  for cmd in "$@"; do
    if hash $cmd 2> /dev/null; then
      printf $cmd && return
    fi
  done
  return 1
}

# convert x.y.z version to 9-digit number for comparison
# _ver2num 3.14.159 = 003014159
_ver2num() {
  printf "%03d%03d%03d" $(tr . ' ' <<< "$1") 2> /dev/null
}

p3ver=$(python3 -V)
p3ver=$(_ver2num ${p3ver/* /})
if [ $p3ver -lt 003009000 ]; then
  echo >&2 "Python 3.9 or later required."
  exit 1
fi

clean_up() {
  cd /tmp; # rm -rf $tmp_dir
}
trap clean_up EXIT

tmp_dir="$(mktemp -d)"
prj_dir="$(realpath "$(dirname "$0")/$PROJECT")"
cp -a $prj_dir/* $tmp_dir
cd $tmp_dir

[ -f setup.py ] || exit $?

# use GNU sed on BSD/macOS
# gsed: brew install gnu-sed
sed=$(_altcmd gsed sed)

# replace "base_url" parameter values
# _URL='http://datastore:8080'
# while read file; do
#   $sed -i "s|$_URL|$API_URL|" $file
# done < <(
#   grep -rl $_URL .
# )

# replace AWS region parameter values
_REGION='us-gov-west-1'
while read file; do
  $sed -i "s/$_REGION/$REGION/" $file
done < <(
  grep -rl $_REGION .
)

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

md5=($(md5sum $WHL))
echo -n '{"md5":"'$md5'"}'

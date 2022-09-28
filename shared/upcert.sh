#!/usr/bin/env bash

# replace "rhizome.jks" and "rhizome_ssl.cer", and
# return {expires} date for Terraform's "external"
# data source that is at least 3 months from today
#
#   usage: upcert.sh <domain>
# example: upcert.sh dev.astrometrics.us

cd "`dirname "$0"`"

if [ -z "$1" ]; then
  echo >&2 "Usage: upcert.sh <domain>"
  exit 1
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
_reqcmds openssl keytool || exit $?

jks_file="config/security/rhizome.jks"
cer_file="config/security/rhizome_ssl.cer"
jks_alias="rhizomessl"
jks_pass="rhizome"
key_pass="rhizome"

# cert_date <which> <format>
#  which: start|end
# format: iso|unix
cert_date() {
  local which=$1 format=$2 args date opts fmt
  [ "$which" == start ] && args=(-startdate) || args=(-enddate)
  date=$(openssl x509 "${args[@]}" -noout -in $cer_file -inform der)
  [[ "$OSTYPE" == darwin* ]] && opts=(-juf "%b %d %T %Y %Z") || opts=(-ud)
  [ "$format" == unix ] && fmt="%s" || fmt="%Y-%m-%dT%TZ"
  date "${opts[@]}" "${date/*=/}" +"$fmt"
}

# inc_date <unix_ts> <amount> <unit>
# amount: e.g. "+1", "-3"
#   unit: e.g. month, day
inc_date() {
  local ts=$1 amount=$2 unit=$3 inc opts
  if [[ "$OSTYPE" == darwin* ]]; then
    inc="${amount}${unit:0:1}"
    opts=(-juv $inc -f %s $ts)
  else
    inc="$amount $unit"
    opts=(-ud "$(date -ud @$ts) $inc")
  fi
  date "${opts[@]}" +%s
}

all_done() {
  local expires=$(cert_date end iso)
  echo -n '{"expires":"'"$expires"'"}'
  exit
}

if [ -f $cer_file ]; then
  expires=$(cert_date end unix)
  # do nothing unless past renewal date
  renewal=$(inc_date $expires -3 month)
  [ $(date +%s) -le $renewal ] && all_done
fi
rm -f $jks_file $cer_file

C="US"
S="California"
L="Walnut Creek"
O="MaiVERIC"
OU="ALPRS"
CN="*.$1"

keytool -genkeypair \
  -validity 720 \
  -keyalg EC \
  -keystore  $jks_file  \
  -storepass $jks_pass  \
  -keypass   $key_pass  \
  -alias     $jks_alias \
  -dname "CN=$CN, OU=$OU, O=$O, L=$L, S=$S, C=$C" 1>&2

keytool -exportcert \
  -keystore  $jks_file  \
  -storepass $jks_pass  \
  -alias     $jks_alias \
  -file      $cer_file  1>&2

all_done

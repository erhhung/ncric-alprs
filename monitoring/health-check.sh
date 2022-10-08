#!/usr/bin/env bash

# cron job run by /etc/cron.d/health-check
#
# performs an end-user login to the frontend app,
# and sends an email notification if login fails

cd "$(dirname "$0")"

[ "$1" ] || exit 1
CRONJOB_NAME=$(basename "$0" .sh)
MAIL_TO=$1

# wait at least 20 minutes to ensure
# all servers are fully bootstrapped
up_mins=$(awk '{print int($1/60)}' /proc/uptime)
[ 0$up_mins -lt 20 ] && exit

LOCK_FILE="/var/lock/$CRONJOB_NAME.lock"
 LOG_FILE="`pwd`/$CRONJOB_NAME.log"
FAIL_LIST="`pwd`/failure-list.log"
MAIL_BODY="/tmp/$CRONJOB_NAME.msg"

# don't run another job if the
# previous one hasn't finished
[ -e  $LOCK_FILE ] && exit 3
touch $LOCK_FILE

ts() {
  date "+%F %T"
}

exec > $MAIL_BODY 2>&1
echo -e "\n[`ts`] ===== BEGIN $CRONJOB_NAME ====="

exiting() {
  echo "[`ts`] ===== END $CRONJOB_NAME ====="
  if [ "$failed" ]; then
    ts >> $FAIL_LIST

    local count=$(wc -l $FAIL_LIST | awk '{print $1}')
    # only send email if failure has repeated
    # and send just once on prolonged failure
    [  0$count -eq 2 ] && notify "$(fail_msg)"
  else
    [  -e $FAIL_LIST ] && notify "$(pass_msg)"
    rm -f $FAIL_LIST
  fi

  cat $MAIL_BODY >> $LOG_FILE
  rm -f $MAIL_BODY $LOCK_FILE
}
trap exiting EXIT

# extract user credentials and
# settings from "/bootstrap.sh"
vars=(
  ENV
  APP_URL
  API_URL
  CLIENT_ID
  auth0_email
  auth0_pass
)
regex=$(IFS=\|; echo "${vars[*]}")
# find matches: export KEY="value"
eval $(egrep "($regex)=\"" /bootstrap.sh | awk '{print $2}')

MAIL_FROM=${auth0_email/*@/monitor@}
auth0_domain="maiveric.us.auth0.com"

# <since>
elasped() {
  _output() {
    [ 0$1 -eq 0 ] && return
    [ 0$1 -eq 1 ] && echo $1 $2
    echo $1 ${2}s,
  }

  local days hours mins secs output=()
  # add 5 seconds to ensure we round up the minute
  secs=$((`date "+%s"` - `date -d "$1" "+%s"` + 5))
  mins=$((secs / 60)) hours=$((mins  / 60))
                       days=$((hours / 24))
  mins=$((mins % 60)) hours=$((hours % 24))

  output+=(`_output $days  day`)
  output+=(`_output $hours hour`)
  output+=(`_output $mins  minute`)
  output=$(echo "${output[@]}")
  # trim trailing comma
  echo "${output:0:-1}"
}

fail_msg() {
  cat <<EOT
Subject={
  Charset=UTF-8,
  Data="[AstroMetrics:${ENV^^}] Health check FAILED!"
},
Body={
  Html={
    Charset=UTF-8,
    Data="
<html>
<body>
<b>$APP_URL — $auth0_email login failed!</b>
<pre>$(< $MAIL_BODY)
</pre>
</body>
</html>"
  }
}
EOT
}

pass_msg() {
  local elapsed=$(elapsed "`head -1 $FAIL_LIST`")
  cat <<EOT
Subject={
  Charset=UTF-8,
  Data="[AstroMetrics:${ENV^^}] Health check PASSED!"
},
Body={
  Html={
    Charset=UTF-8,
    Data="
<html>
<body>
<b>$APP_URL — service has been restored.</b><br>
The outage lasted approximately <b>$elapsed.</b>
<pre>$(< $MAIL_BODY)
</pre>
</body>
</html>"
  }
}
EOT
}

# <message>
notify() {
  echo "Sending notification email to $MAIL_TO..."
  aws ses send-email \
    --from $MAIL_FROM \
    --to   $MAIL_TO \
    --message "$1" \
    --output yaml 2> /dev/null
}

endpoint="https://$auth0_domain/oauth/token"
echo "[`ts`] POST $endpoint"

params=(
  client_id=$CLIENT_ID
  grant_type=password
  username=$auth0_email
  password=$auth0_pass
  audience=https://$auth0_domain/userinfo
  scope=openid
)
jwt=$(curl -sX POST "$endpoint" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "$(IFS=\&; echo "${params[*]}")" | jq -r .id_token)

# JWTs always begin with "ey"
if [[ "$jwt" != ey* ]]; then
  failed=true
  exit 1
fi

# <route> [opts...] [-X method]
curl_api() {
  local endpoint method="${@: -1}"
  endpoint="$API_URL/datastore/$1"
  [ "$method" == POST ] || method=GET
  printf "[`ts`] %4s $endpoint\n" $method

  local status args=(
    -H  "Authorization: Bearer $jwt"
    -so /dev/null -w '%{http_code}\n'
    "${@:2}" "$endpoint"
  )
  status=$(curl "${args[@]}" 2> /dev/null)
  if [ "$status" != 200 ]; then
    echo "[`ts`] Request FAILED with status $status!"
    failed=true
    return 1
  fi
}

# activate the OpenLattice user
curl_api principals/sync || exit $?

# obtain information about this app
curl_api app/lookup/astrometrics || exit $?

# query "ol.appdetails" containing
# AGENCY_VEHICLE_RECORDS_ENTITY_SETS
curl_api search/6d17e1c0-d61b-4ec8-80ce-1e82b4a64166 \
    -d '{"start":0, "maxHits":1, "searchTerm":"*"}' \
    -H "Content-Type: application/json" -X POST || exit $?

echo "[`ts`] Health check completed successfully."

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

# "/var/lock/jobs" created in "/bootstrap.sh" using
# systemd-tmpfiles conf "/etc/tmpfiles.d/jobs.conf"
LOCK_FILE="/var/lock/jobs/$CRONJOB_NAME.lock"

 LOG_FILE="`pwd`/$CRONJOB_NAME.log"
FAIL_LIST="`pwd`/failure-list.log"
CURL_BODY="/tmp/$CRONJOB_NAME-curl"
MAIL_BODY="/tmp/$CRONJOB_NAME-mail"

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
    [ 0$count -eq 2 ] && alert "$(fail_msg)"

  elif [ -e $FAIL_LIST ]; then
    local count=$(wc -l $FAIL_LIST | awk '{print $1}')
    # don't alert unless failure was alerted
    [ 0$count -ge 2 ] && alert "$(pass_msg)"

    rm -f $FAIL_LIST
  fi
  cat $MAIL_BODY >> $LOG_FILE
  rm -f $LOCK_FILE $CURL_BODY $MAIL_BODY
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
elapsed() {
  _output() {
    if [ 0$1 -eq 1 ]; then
      echo $1 $2,
    elif [ 0$1 -gt 1 ]; then
      echo $1 ${2}s,
    fi
  }

  local days hours mins secs output=()
  # add 45 seconds to ensure we round up to 10 minutes
  ((secs  = `date "+%s"` - `date -d "$1" "+%s"` + 45))
  ((mins  =  secs  / 60))
  ((hours =  mins  / 60))
  ((days  =  hours / 24))
  ((mins  %= 60))
  ((hours %= 24))

  output+=(`_output $days  day`)
  output+=(`_output $hours hour`)
  output+=(`_output $mins  minute`)
  output=$(echo "${output[@]}")
  # trim trailing comma
  echo "${output:0:-1}"
}

fail_msg() {
  local initial=$(head -1 $FAIL_LIST)
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
<b>$APP_URL — $auth0_email login failed!</b><br>
The initial failure occurred at <b>$initial</b>.
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
alert() {
  echo -e "\nSending email alert to $MAIL_TO..."
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
# write body to file; return status
status=$(curl -X POST "$endpoint" \
  -s -m 30 --connect-timeout 20 \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "$(IFS=\&; echo "${params[*]}")" \
  -o $CURL_BODY -w '%{http_code}')

if [ 0$status -eq 200 ]; then
  jwt=$(jq -r .id_token $CURL_BODY)
else
  echo "[`ts`] Request FAILED with status $status!"
  [ -f $CURL_BODY ] && \
    echo "Auth0 response: $(xargs < $CURL_BODY)"
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
    -s -m 30 --connect-timeout 20
    -H "Authorization: Bearer $jwt"
    -o /dev/null -w '%{http_code}'
    "${@:2}" "$endpoint"
  )
  status=$(curl "${args[@]}" 2> /dev/null)
  if [ 0$status -ne 200 ]; then
    echo "[`ts`] Request FAILED with status $status!"
    failed=true datastore=true
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

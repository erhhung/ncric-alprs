# This user data script is a continuation of the
# "shared/boot.tftpl" template script:  download
# and run the host-specific "bootstrap.sh" script
# from S3. This script intentionally does not use
# the AWS CLI because it may not be installed yet
# on the host OS.

URL="http://169.254.169.254/latest"

az=$(curl -fsm .25 $URL/meta-data/placement/availability-zone)
region=${az:0:-1}

meta() {
  local iam="curl -fsm .25 $URL/meta-data/iam/security-credentials"
  local res=$($iam/`$iam/` | sed -rn 's/.*"'"$2"'"[^"]+"([^"]*).*/\1/p')
  [ "$res" ] && eval "$1=\"$res\""
}
meta key_id AccessKeyId
meta secret SecretAccessKey
meta token  Token

date="$(date -R)"
hash="$(echo -en "GET\n\n\n$date\nx-amz-security-token:$token\n/$bucket/$file" | \
  openssl sha1 -binary -hmac $secret | \
  openssl base64)"

curl -so /bootstrap.sh \
  -H "Host: $bucket.s3.$region.amazonaws.com" \
  -H "Date: $date" \
  -H "Authorization: AWS $key_id:$hash" \
  -H "x-amz-security-token: $token" \
  -L https://$bucket.s3.$region.amazonaws.com/$file

# make sure response isn't an XML-based error message
if [[ "$(head -1 /bootstrap.sh)" =~ ^#\!/.+ ]]; then
  chmod +x /bootstrap.sh
  exec     /bootstrap.sh
else
  mv /bootstrap.sh /bootstrap.log
  echo >&2 -e "[$(date "+%Y-%m-%d %T")] BOOT FAILED! Retrying in 10 seconds...\n$(< /bootstrap.log)"
  sleep 10
  curl -so /boot.sh $URL/user-data
  chmod +x /boot.sh
  exec     /boot.sh
fi

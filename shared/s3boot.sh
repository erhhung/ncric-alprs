# This user-data cloud-init script is appended
# onto the "shared/boot.tftpl" template script.

meta() {
  local iam='curl -fsm .25 http://169.254.169.254/latest/meta-data/iam/security-credentials'
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
  -H "Host: $bucket.s3.amazonaws.com" \
  -H "Date: $date" \
  -H "Authorization: AWS $key_id:$hash" \
  -H "x-amz-security-token: $token" \
  https://$bucket.s3.amazonaws.com/$file

chmod +x /bootstrap.sh
exec     /bootstrap.sh

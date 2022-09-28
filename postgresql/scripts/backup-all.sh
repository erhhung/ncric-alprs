#!/usr/bin/bash

# cron job run by /etc/cron.d/backup_all
#
# NOTE: the cron job has been disabled and replaced
#       by daily EBS snapshots taken by AWS Backup
#
# archives all databases in this PostgreSQL server to S3 using "pg_basebackup"
# (a temporary EBS volume will be created and mounted at /opt/postgresql/temp)

[ "$1" ]             || exit 1
[ `whoami` == root ] || exit 2
BACKUP_NAME=$(basename "$0" .sh)
BACKUP_BUCKET=$1

DATA_DEV="/dev/nvme1n1"
DATA_DIR="/opt/postgresql/data"
TEMP_DEV="/dev/nvme2n1"
TEMP_DIR="/opt/postgresql/temp"

# role defined in "iam-roles.tf"
ASSUME_ROLE="ALPRSEBSManagerRole"
VOLUME_NAME="PostgreSQL Temp"

 LOG_FILE="/opt/postgresql/$BACKUP_NAME.log"
LOCK_FILE="/var/lock/$BACKUP_NAME"

# don't start another backup if
# previous one hasn't completed
[ -e  $LOCK_FILE ] && exit 3
touch $LOCK_FILE

ts() {
  date "+%Y-%m-%d %T"
}
started=$(date "+%s")

exec >> $LOG_FILE 2>&1
echo -e "\n[`ts`] ===== BEGIN $BACKUP_NAME ====="

exiting() {
  if [ "$(type -t delete_temp)" == function ]; then
    local elapsed=$((`date "+%s"` - started))
    # refresh assumed role credentials
    # in case backup took over 10 hours
    [ 0$elapsed -gt 36000 ] && get_creds
    delete_temp
  fi
  echo "[`ts`] ===== END $BACKUP_NAME ====="
  rm -f $LOCK_FILE
}
trap exiting EXIT

metadata() {
  local value=$(curl -s "http://169.254.169.254/latest/meta-data/$1");
  [[ "$value" =~ "404 - Not Found" ]] && return 1 || echo "$value"
}

identity() {
  aws sts get-caller-identity \
    --query Arn --output text
}

role_arn=$(identity) && echo "[`ts`] Current role: $role_arn"
role_arn="$(sed -En 's|^arn:(aws[^:]*):sts::([0-9]+).+$|arn:\1:iam::\2|p' \
  <<< "$role_arn"):role/$ASSUME_ROLE"

get_creds() {
  eval export $(aws sts assume-role \
                  --role-arn $role_arn \
                  --role-session-name postgresql-backup | \
    jq -r '.Credentials |
           "AWS_ACCESS_KEY_ID=\"\(.AccessKeyId)\"
            AWS_SECRET_ACCESS_KEY=\"\(.SecretAccessKey)\"
            AWS_SESSION_TOKEN=\"\(.SessionToken)\""')
}
get_creds && echo "[`ts`] Assumed role: $(identity)"

volume_id() {
  aws ec2 describe-volumes \
    --query 'Volumes[?Tags[?Value==`'"$VOLUME_NAME"'`]].VolumeId' \
    --output text
}

# <volume_id>
volume_state() {
  local state=$(aws ec2 describe-volumes \
                  --volume-ids $1 \
                  --query 'Volumes[].State' \
                  --output text 2> /dev/null)
  echo ${state:-deleted}
}

# <volume_id>
attach_state() {
  local state=$(aws ec2 describe-volumes \
                  --volume-ids $1 \
                  --query 'Volumes[].Attachments[].State' \
                  --output text 2> /dev/null)
  echo ${state:-detached}
}

# <volume_id> <state_func> <operator> <value> <sleep>'
wait_state() {
  local vol=$1 func=$2 oper=$3 val=$4 delay=${5:-5}
  local state expr elapsed=0

  while true; do
    state=$($func $vol)
    echo  "[`ts`] $vol: $state"
    expr=("$state" "$oper" "$val")
    test  "${expr[@]}" && break
    [ $elapsed -lt 60 ] || return $?
    ((elapsed += delay))
    sleep $delay
  done
}

create_temp() {
  local vol=$(volume_id)
  if [ ! "$vol" ]; then
    local zone size tags
    zone=$(metadata placement/availability-zone)
    size=$(( $(lsblk $DATA_DEV -nbo SIZE) / 1024**3 ))
    tags="ResourceType=volume,Tags=[{Key=Name,Value=$VOLUME_NAME}]"

    vol=$(aws ec2 create-volume \
            --availability-zone $zone \
            --size              $size \
            --volume-type       gp3 \
            --throughput        500 \
            --encrypted \
            --tag-specifications "$tags" \
            --query VolumeId \
            --output text) || return $?
  fi
  wait_state $vol volume_state != creating 5 || return $?

  local state=$(volume_state $vol)
  if [ "$state" == available ]; then
    local inst=$(metadata instance-id)
    aws ec2 attach-volume \
      --volume-id   $vol  \
      --instance-id $inst \
      --device  /dev/xvdc > /dev/null || return $?
  fi
  wait_state $vol attach_state == attached 3 || return $?

  local device=$TEMP_DEV mount=$TEMP_DIR label=temporary
  [ -d $mount ] && df | grep -q $mount && return

  if ! file -sL $device | grep -q filesystem; then
    mkfs.xfs -f -L $label $device > /dev/null || return $?
  fi
  mkdir -p $mount
  mount -t xfs -o defaults,nofail LABEL=$label $mount || return $?
  chown postgres:postgres $mount
  rm -rf $mount/*
}

delete_temp() {
  local mount=$TEMP_DIR vol=$(volume_id)
  df | grep -q $mount && umount $mount
  [ -d $mount ]       && rm -rf $mount
  [ "$vol" ] || return 0

  local state=$(attach_state $vol)
  if [ "$state" == attached ]; then
    aws ec2 detach-volume \
      --volume-id $vol \
      --force > /dev/null || return $?
  fi
  wait_state $vol attach_state != detaching 5 || return $?

  aws ec2 delete-volume --volume-id $vol
  wait_state $vol volume_state == deleted 3
}

# <mount_point>
fs_stats() {
  df -h $1 | tail -1 | awk '{print $1" | Total: "$2"iB | Used: "$3"iB ("$5") | Avail: "$4"iB"}'
}

echo "[`ts`] Data volume: $(fs_stats $DATA_DIR)"
create_temp || exit $?
echo "[`ts`] Temp volume: $(fs_stats $TEMP_DIR)"

echo "[`ts`] Running pg_basebackup as user \"postgres\"..."
su -l postgres -c "nice pg_basebackup -D $TEMP_DIR -X stream" || exit $?
echo "[`ts`] Temp volume: $(fs_stats $TEMP_DIR)"

# destination file may be overwritten multiple times per day via cron job
dest="s3://$BACKUP_BUCKET/postgresql/pg_backup_$(date "+%Y-%m-%d").tar.bz"
echo "[`ts`] Compressing and writing: $dest"
(
# use original instance role to access S3
unset AWS_ACCESS_KEY_ID \
      AWS_SECRET_ACCESS_KEY \
      AWS_SESSION_TOKEN

# increase multipart_chunksize from 8MB
# to avoid exceeding the 10K part limit:
# https://docs.aws.amazon.com/cli/latest/topic/s3-config.html
aws configure set s3.multipart_chunksize 64MB
set -o pipefail

# https://www.peterdavehello.org/2015/02/use-multi-threads-to-compress-files-when-taring-something/
nice tar cf - -C $TEMP_DIR -I "pbzip2 -m1024" . | \
  nice aws s3 cp - $dest --no-progress || exit $?

aws s3 ls --human-readable $dest | \
  awk '{print "["$1" "$2"] Backup file:  "$5" | Size: "$3$4}'
)

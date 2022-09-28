#!/usr/bin/bash

# cron job run by /etc/cron.d/backup_flock
#
# archives raw data in the "flock_reads" table that are older than
# the retention period to S3, and then deletes them from the table

[ "$1" ] || exit 1
BACKUP_NAME=$(basename "$0" .sh)
BACKUP_BUCKET=$1

# days to keep data in "flock_reads" table
RETENTION_DAYS=7

 LOG_FILE="/opt/postgresql/$BACKUP_NAME.log"
LOCK_FILE="/var/lock/$BACKUP_NAME"

# don't start another backup if
# previous one hasn't completed
[ -e  $LOCK_FILE ] && exit 3
touch $LOCK_FILE

ts() {
  date "+%Y-%m-%d %T"
}

exec >> $LOG_FILE 2>&1
echo -e "\n[`ts`] ===== BEGIN $BACKUP_NAME ====="

exiting() {
  echo "[`ts`] ===== END $BACKUP_NAME ====="
  rm -f $LOCK_FILE
}
trap exiting EXIT

# increase multipart_chunksize from 8MB
# to avoid exceeding the 10K part limit:
# https://docs.aws.amazon.com/cli/latest/topic/s3-config.html
aws configure set s3.multipart_chunksize 64MB
set -o pipefail

psql() {
  `which psql` \
    -d org_1446ff84711242ec828df181f45e4d20 \
    -c "$1" -tAq
}

# <date> <dest> [cols]
backup() {
  local date=$1 dest=$2 cols=${3:-'*'}
  echo "[`ts`] Compressing and writing: $dest"

  psql "COPY (SELECT $cols
              FROM   integrations.flock_reads
              WHERE  timestamp >= '$date'
                AND  timestamp <  '$date'::date + 1)
        TO STDOUT" | \
    nice pbzip2 -m1024 -c - | \
    nice aws s3 cp - $dest --no-progress || return $?

  aws s3 ls --human-readable $dest | \
    awk '{print "["$1" "$2"] Backup file: "$5" | Size: "$3$4}'
}

join() {
  local delim=$1 first=$2
  shift 2 && printf %s "$first" "${@/#/$delim}"
}

# get column names and nullify image value
cols=($(psql "SELECT column_name
              FROM   information_schema.columns
              WHERE  table_name = 'flock_reads'
              ORDER  BY ordinal_position"))
cols=$(join ', ' "${cols[@]}")
cols=${cols/' image,'/' NULL::bytea AS image,'}

while read date; do
  dest="s3://$BACKUP_BUCKET/flock/flock_reads_${date}_without_images.csv.bz"
  backup $date $dest $cols || exit $?

  dest="s3://$BACKUP_BUCKET/flock/flock_reads_${date}_with_images.csv.bz"
  backup $date $dest || exit $?

  echo "[`ts`] Deleting raw data from $date..."
  psql "DELETE FROM integrations.flock_reads
         WHERE timestamp >= '$date'
           AND timestamp <  '$date'::date + 1)"
done < <(
  psql "SELECT DISTINCT(timestamp::date)
        FROM   integrations.flock_reads
        WHERE  timestamp < current_date - $RETENTION_DAYS - 1
        ORDER  BY timestamp"
)

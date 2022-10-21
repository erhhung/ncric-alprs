#!/usr/bin/bash

# cron job run by /etc/cron.d/backup_flock
#
# archives raw data in the "flock_reads" table that are older than
# the retention period to S3, and then deletes them from the table.
# runs pg_repack on "flock_reads" afterwards to reclaim disk space

[ "$1" ] || exit 1
CRONJOB_NAME=$(basename "$0" .sh)
BACKUP_BUCKET=$1

NCRIC_DB="org_1446ff84711242ec828df181f45e4d20"
# days to keep data in "flock_reads" table
RETENTION_DAYS=3

 LOG_FILE="$PG_HOME/jobs/$CRONJOB_NAME.log"
LOCK_FILE="/var/lock/$CRONJOB_NAME.lock"

# don't run another job if the
# previous one hasn't finished
[ -e  $LOCK_FILE ] && exit 3
touch $LOCK_FILE

ts() {
  date "+%F %T"
}

exec >> $LOG_FILE 2>&1
echo -e "\n[`ts`] ===== BEGIN $CRONJOB_NAME ====="

exiting() {
  echo "[`ts`] ===== END $CRONJOB_NAME ====="
  rm -f $LOCK_FILE
}
trap exiting EXIT

# increase multipart_chunksize from 8MB
# to avoid exceeding the 10K part limit:
# https://docs.aws.amazon.com/cli/latest/topic/s3-config.html
aws configure set s3.multipart_chunksize 64MB
set -o pipefail

# <sql> [opts]...
psql() {
  # (set -o noglob; echo >&2 -E [psql]: $1)
  `which psql` -d $NCRIC_DB -c "$1" -tA "${@:2}"
}

# <dow> <date> <dest> [cols]
backup() {
  local dow=$1 date=$2 dest=$3 cols=${4:-'*'}
  echo "[`ts`] Compressing and writing: $dest"

  psql "COPY (SELECT $cols
                FROM integrations.flock_reads_$dow
               WHERE timestamp >= '$date'
                 AND timestamp <  '$date'::date + 1
            ORDER BY cameranetworkname, timestamp)
        TO STDOUT" -q | \
    nice pbzip2 -m1024 -c - | \
    nice aws s3 cp - $dest --no-progress || return $?

  # timestamp shown is file creation
  aws s3 ls --human-readable $dest | \
    awk '{print "["$1" "$2"] Backup file: "$5" | Size: "$3$4}'
}

# <dow>
repack() {
  local dow=$1
  # https://reorg.github.io/pg_repack/
  # https://www.percona.com/blog/2021/06/24/understanding-pg_repack-what-can-go-wrong-and-how-to-avoid-it/
  echo "[`ts`] Running pg_repack on flock_reads_$dow..."
  pg_repack $NCRIC_DB \
    -t integrations.flock_reads_$dow \
    -o timestamp \
    -j $(nproc)  \
    -DZ -T 300 2>&1 | \
    `which ts`  -s "[           %T]"
}

# <delim> [elts]...
join() {
  local delim=$1 first=$2
  shift 2 && printf %s "$first" "${@/#/$delim}"
}

# get column names and nullify image value
cols=($(psql "SELECT column_name
                FROM information_schema.columns
               WHERE table_name = 'flock_reads_sun'
            ORDER BY ordinal_position" -q))
cols=$(join ', ' "${cols[@]}")
cols=${cols/' image,'/' NULL::bytea AS image,'}

# if today is a Tuesday, then the _mon (yesterday's)
# table should be actively written to, so start from
# 7 days ago (_tue) and backup + repack tables until
# 2 days ago (_sun)
day=-7

while [ $day -lt -1 ]; do
   # +%a outputs 3-char day-of-week
   dow=$(date -d "$day days" "+%a")
   dow=${dow,,}
  date=$(
    psql "SELECT DISTINCT(timestamp::date)
            FROM integrations.flock_reads_$dow
           WHERE timestamp < current_date - $RETENTION_DAYS - 1
        ORDER BY timestamp::date LIMIT 1" -q
  )
  if [ "$date" ]; then
    repack=true
  else
    if [ "$repack" ]; then
      unset repack
      repack $dow
    else
      echo "[`ts`] Found no data to archive from flock_reads_$dow."
    fi
    ((day++))
    continue
  fi

  sql="FROM integrations.flock_reads_$dow
      WHERE timestamp >= '$date'
        AND timestamp <  '$date'::date + 1"
  rows=$(psql "SELECT COUNT(*) $sql")

  printf "[`ts`] Archiving %'d rows from flock_reads_$dow for $date...\n" $rows
  dest="s3://$BACKUP_BUCKET/flock/flock_reads_${date}_${dow}"

  backup $dow $date "${dest}_without_images.csv.bz" "$cols" || exit $?
  backup $dow $date "${dest}_with_images.csv.bz"            || exit $?

  printf "[`ts`] Deleting %'d rows from flock_reads_$dow for $date...\n" $rows
  psql "DELETE $sql" || exit $?
done

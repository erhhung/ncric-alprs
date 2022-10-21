#!/usr/bin/bash

# cron job run by /etc/cron.d/drop_temps
#
# drops forgotten temp integration tables
# (e.g. "boss4_catchup_2022_9_30_22_5_33")
# that are older than the retention period

CRONJOB_NAME=$(basename "$0" .sh)

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

# <sql> [opts]...
psql() {
  # (set -o noglob; echo >&2 -E [psql]: $1)
  `which psql` -d $NCRIC_DB -c "$1" -tA "${@:2}"
}

cutoff=$(date -d "-$RETENTION_DAYS days -1 day" "+%F")
echo "[`ts`] Looking for temp tables prior to $cutoff..."

while read table date; do
  echo "[`ts`] Dropping temp table from $date: $table..."
  psql "DROP TABLE $table CASCADE" || exit $?
done < <(
  psql "SELECT table_name,
               SUBSTRING(table_name, '^.+_(\d{4}(_\d{1,2}){2})')::date AS table_date
          FROM information_schema.tables
         WHERE table_schema = 'integrations'
           AND table_name ~ '^.+_\d{4}(_\d{1,2}){5}$'
           AND SUBSTRING(table_name, '^.+_(\d{4}(_\d{1,2}){2})')::date < '$cutoff'::date
      ORDER BY table_date, table_name" -qF' '
)

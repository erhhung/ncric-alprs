#!/bin/bash

[ "$1" ] || exit $?
BACKUP_BUCKET=$1

# don't start another backup if
# previous one hasn't completed
[ -e  /var/lock/pg_basebackup ] && exit
touch /var/lock/pg_basebackup

TEMP="/opt/postgresql/temp"
 LOG="/opt/postgresql/backups.log"

__ts() {
  date "+%Y-%m-%d %T"
}

exec >> $LOG 2>&1
echo -e "\n[`__ts`] ===== BEGIN pg_basebackup ====="

clean() {
  [ "$1" ] || rm -f /var/lock/pg_basebackup
  rm -rf $TEMP/*
}
clean NO_UNLOCK
trap clean EXIT

fs_stats() {
  df -h $TEMP | tail -1 | awk '{print $1" | Total: "$2"iB | Used: "$3"iB ("$5") | Avail: "$4"iB"}'
}
echo "[`__ts`] INIT $(fs_stats)"

# destination file will be overwritten multiple times per day by cron job
dest="s3://$BACKUP_BUCKET/postgresql/pg_backup_$(date "+%Y-%m-%d").tar.bz"

nice pg_basebackup -D $TEMP -X stream
echo "[`__ts`] TEMP $(fs_stats)"

s3_stats() {
  aws s3 ls --human-readable $dest | awk '{print "["$1" "$2"] "$5" | Size: "$3$4}'
}

nice tar cjf - -C $TEMP . | nice aws s3 cp - $dest --no-progress
echo -e "$(s3_stats)\n[`__ts`] ===== END pg_basebackup ====="

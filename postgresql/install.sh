# This user data script is a continuation
# of the shared "boot.sh" script.

create_xfs_volume() (
  [ -d /opt/postgresql ] && exit
  if ! file -sL /dev/nvme1n1 | grep -q filesystem; then
    mkfs.xfs -f -L postgresql /dev/nvme1n1
  fi
  tab=$(printf "\t")
  cat <<EOF >> /etc/fstab
LABEL=postgresql${tab}/opt/postgresql${tab}xfs${tab}defaults,nofail${tab}0 2
EOF
  mkdir /opt/postgresql
  mount -a
  df -h /opt/postgresql
)

install_postgresql() (
  curl -s https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
  cd /etc/apt/sources.list.d
  cat <<EOF > postgresql-pgdg.list
deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main
EOF
  apt-get update
  wait_apt_get
  apt-get install -y postgresql-14 postgresql-contrib
  cd /home/$USER
  cat <<'EOF' >> .bash_aliases


psql() {
  [ "$USER" == 'postgres' ] && $(which psql) "$@" || \
    \sudo -E su postgres -c   "$(which psql)  $@"
}
EOF
)

config_postgresql() (
  cd /etc/security/limits.d
  cat <<'EOF' > 10-defaults.conf
* soft nofile  300000
* hard nofile  300000
* hard memlock unlimited
* soft memlock unlimited
EOF
  cat <<'EOF' > 90-postgresql.conf
postgres soft memlock unlimited
postgres hard memlock unlimited
EOF
  cd /etc/systemd/system
  mkdir -p postgresql.service.d
  cd postgresql.service.d
  cat <<'EOF' > override.conf
[Service]
LimitMEMLOCK=infinity
LimitNOFILE=300000
EOF
  cd /etc/sysctl.d
  hugepages=$(
    # shared_buffers = 32GB of 64GB total,
    # so set hugepages to accommodate 32GB
    awk '/MemTotal.*kB/ {mt=$2} /Hugepagesize.*kB/ {
      hps=$2; print int(mt / hps * .55)
    }' /proc/meminfo
  )
  cat <<EOF > 90-hugepages.conf
vm.nr_hugepages = $hugepages
EOF
  service procps force-reload

  cd /opt/postgresql
  if [ ! -d data ]; then
    mkdir data temp
    ln -s /etc/postgresql/14/main conf
    ln -s /usr/lib/postgresql/14/bin
    ln -s /var/log/postgresql logs
    chown -Rh postgres:postgres .
    su postgres -c 'bin/initdb data'
  fi

  cd conf
  mv postgresql.conf postgresql-default.conf
  aws s3 cp $PG_CONF postgresql.conf --no-progress
  shared_buffers=$(awk '/MemTotal.*kB/ {print int($2 /1024/1024 / 2)+1}' /proc/meminfo)
  sed -Ei "s/^shared_buffers.+$/shared_buffers = ${shared_buffers}GB/" postgresql.conf
  mv pg_hba.conf pg_hba-default.conf
  aws s3 cp $PG_HBA pg_hba.conf --no-progress
  run generate_cert
  mv /tmp/server.* .
  chown -h postgres:postgres *
)

wait_service() {
  local name=$1 port=$2 count=12
  while ! nc -z localhost $port && [ $((count--)) -ge 0 ]; do
    echo "[`__ts`] Waiting for $name on port $port..."
    sleep 5
  done
  if [ $count -lt 0 ]; then
    echo >&2 "$name failed to start!"
    return 1
  fi
}

start_postgresql() {
  systemctl daemon-reload
  systemctl restart postgresql
  systemctl enable  postgresql
  wait_service PostgreSQL 5432
  systemctl status  postgresql --no-pager
}

create_databases() {
  cd /opt/postgresql
  [ -d users ] && exit
  mkdir users
  cd users
  for db in alprs atlas rundeck; do
    user="${db}_user"
    pass="${db}_pass"
    echo "${!pass}" > $user
    psql <<EOT
CREATE USER $user WITH PASSWORD '${!pass}';
EOT
  done
  chmod 400 *
  for db in alprs rundeck; do
    user="${db}_user"
    psql <<EOT
CREATE DATABASE $db WITH OWNER = $user;
REVOKE ALL ON DATABASE $db FROM PUBLIC;
GRANT  ALL ON DATABASE $db   TO $user;
EOT
  done
  psql <<'EOT'
ALTER USER atlas_user CREATEDB CREATEROLE;
EOT
}

create_db_objects() {
  cd /opt/postgresql
  [ -d init ] && exit
  mkdir init
  cd init
  aws s3 cp $ALPRS_SQL alprs.sql.gz --no-progress
  gunzip -f alprs.sql.gz
  sed -Ei "s|https://astrometrics\\.us|$APP_URL|" alprs.sql
  psql alprs < alprs.sql
  aws s3 cp $NCRIC_SQL ncric.sql.gz --no-progress
  gunzip -f ncric.sql.gz
  psql < ncric.sql
}

create_backup_sh() {
  cat <<EOF > backup.sh
#!/bin/bash

TEMP="/opt/postgresql/temp"

# destination file will be overwritten multiple times per day by cron job
dest="s3://$BACKUP_BUCKET/postgresql/pg_backup_\$(date "+%Y-%m-%d").tar.bz"

clean() {
  rm -rf \$TEMP/*
}
clean
trap clean EXIT

nice pg_basebackup -D \$TEMP -X stream
nice tar cjf - -C \$TEMP . | nice aws s3 cp - \$dest --no-progress
EOF
  chmod +x backup.sh
}

add_backup_cron() (
  cd /etc/cron.d
  cat <<'EOF' > pg_backup
USER=root
HOME=/root
PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin:/snap/bin

# min hr dom mon dow user command
0 2,8,12,16,20 * * * root su postgres -c 'bash -c "$HOME/backup.sh"'
EOF
  chmod 644 pg_backup
)

run create_xfs_volume
run install_postgresql
run config_postgresql
run start_postgresql
run create_databases  postgres
run create_db_objects postgres
run create_backup_sh  postgres
run add_backup_cron

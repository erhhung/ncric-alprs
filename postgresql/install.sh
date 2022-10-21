# This user data script is a continuation
# of the shared "boot.sh" script.

export NCRIC_DB="org_1446ff84711242ec828df181f45e4d20"

create_xfs_volume() (
  device=/dev/nvme1n1
  volume=/opt/postgresql
   label=postgresql
  [ -d $volume ] && exit
  if ! file -sL $device | grep -q filesystem; then
    mkfs.xfs -f -L $label $device
  fi
  printf -v tab "\t"
  cat <<EOF >> /etc/fstab
LABEL=${label}${tab}${volume}${tab}xfs${tab}defaults,nofail${tab}0 2
EOF
  mkdir $volume
  mount -a
  df -h $volume
)

resize_xfs_volume() (
  device=/dev/nvme1n1
  volume=/opt/postgresql
  # grow file system if size is
  # less than block device size
  printf -v fs_size "%.0f" $(stat -f $volume -c "%b * %s / 1024^3" | bc -l)
  bd_size=$(( $(lsblk $device -nbo SIZE) / 1024**3 ))
  [ $fs_size -ge $bd_size ] && exit
  xfs_growfs -d $volume
  df -h $volume
)

install_postgresql() (
  curl -s https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
  cd /etc/apt/sources.list.d
  cat <<EOF > postgresql-pgdg.list
deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main
EOF
  apt_update
  # "dev" packages are required to run "pgxn install"
  eval_with_retry "wait_apt_get && apt-get install -y postgresql-14 postgresql-contrib \
                     pgxnclient postgresql-server-dev-14 liblz4-dev libreadline-dev"
)

install_extensions() {
  case `whoami` in
    root)
      [ "`find /usr/lib/postgresql -name pg_repack.so`" ] && exit
      eval_with_retry "wait_apt_get && apt-get install -y postgresql-14-repack"
      # pgxn install pg_repack
      ;;
    postgres)
      wait_service # wait if "database system is starting up"
      psql -d $NCRIC_DB -tAc "SELECT extname FROM pg_extension" | \
                     grep -q pg_repack && exit
      pgxn load -d $NCRIC_DB pg_repack
      ;;
  esac
}

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
    mkdir data
    ln -s /etc/postgresql/14/main conf
    ln -s /usr/lib/postgresql/14/bin
    ln -s /var/log/postgresql logs
    chown -Rh postgres:postgres .
    su postgres -c 'bin/initdb data'
  fi

  cd conf
  mv postgresql.conf postgresql-default.conf
  aws s3 cp $S3_URL/postgresql/postgresql.conf . --no-progress
  shared_buffers=$(awk '/MemTotal.*kB/ {print int($2 /1024/1024 / 2)+1}' /proc/meminfo)
  sed -Ei "s/^shared_buffers.+$/shared_buffers = ${shared_buffers}GB/" postgresql.conf
  mv pg_hba.conf pg_hba-default.conf
  aws s3 cp $S3_URL/postgresql/pg_hba.conf . --no-progress
  run generate_cert
  mv /tmp/server.* .
  chown -h postgres:postgres *
)

wait_service() {
  case `whoami` in
    root)
      local name=$1 port=$2 count=12
      while ! nc -z localhost $port && [ $((count--)) -ge 0 ]; do
        echo "[`__ts`] Waiting for $name on port $port..."
        sleep 5
      done
      if [ $count -lt 0 ]; then
        echo >&2 "$name failed to start!"
        return 1
      fi
      ;;
    postgres)
      local err="database system is starting up"
      while eval_with_retry "psql -c '\conninfo'" 2>&1 | \
            grep -q "$err"; do
        echo "The $err..."
      done
      return 0
      ;;
  esac
}

start_postgresql() {
  systemctl daemon-reload
  systemctl restart postgresql
  systemctl enable  postgresql
  wait_service PostgreSQL 5432
  systemctl status  postgresql --no-pager
}

create_databases() (
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
)

config_databases() (
  cd /opt/postgresql
  [ -d init ] && exit
  mkdir init
  cd init
  aws s3 cp $S3_URL/postgresql/alprs.sql.gz . --no-progress
  gunzip -f alprs.sql.gz
  sed -Ei "s|https://astrometrics\\.us|$APP_URL|" alprs.sql
  psql alprs < alprs.sql
  aws s3 cp $S3_URL/postgresql/ncric.sql.gz . --no-progress
  gunzip -f ncric.sql.gz
  psql < ncric.sql
)

user_dotfiles() {
  case `whoami` in
    root)
      cat <<'EOF' >> /etc/environment
PG_HOME="/opt/postgresql"
EOF
      ;;
    postgres)
      (cd /home/$DEFAULT_USER; cp .bashrc .bash_aliases .emacs ~/)
      aws s3 sync $S3_URL/postgresql . --exclude '*' --include '.*' --no-progress
      ;;
    $DEFAULT_USER)
      echo -e \\n >> .bash_aliases
      cat <<'EOF' >> .bash_aliases
alias pg='\sudo -u postgres -i bash'

psql() {
  [ "$USER" == 'postgres' ] && $(which psql) "$@" || \
    \sudo -E su postgres -c   "$(which psql)  $@"
}
EOF
      ;;
  esac
}

install_scripts() {
  mkdir -p scripts
  cd scripts
  aws s3 sync $S3_URL/postgresql/scripts . --no-progress
  chmod 755 *.sh
  # create folder for log files
  mkdir -p /opt/postgresql/jobs
}

config_cronjobs() (
  cd /etc/cron.d
  _mkcron() {
    cat <<EOT
USER=$1
HOME=/var/lib/postgresql
PG_HOME=/opt/postgresql
PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin:/snap/bin

# min hr dom mon dow user command
EOT
    cat
  }
  cat <<EOT | _mkcron postgres > backup_flock
20 2 * * * postgres bash -c "\$HOME/scripts/backup-flock.sh $BACKUP_BUCKET"
EOT
  cat <<EOT | _mkcron root > backup_all.disabled
20 6 * * * root bash -c "\$HOME/scripts/backup-all.sh $BACKUP_BUCKET"
EOT
  cat <<EOF | _mkcron postgres > drop_temps
20 4 * * * postgres bash -c "\$HOME/scripts/drop-temps.sh"
EOF
  chmod 644 *
  service cron reload
)

export -f wait_service

run create_xfs_volume
run resize_xfs_volume
run install_postgresql
run install_extensions
run config_postgresql
run start_postgresql
run create_databases   postgres
run config_databases   postgres
run install_extensions postgres
run user_dotfiles
run user_dotfiles      postgres
run user_dotfiles      $DEFAULT_USER
run install_scripts    postgres
run config_cronjobs

# This user-data cloud-init script is a continuation
# of PostgreSQL's "boot.sh" script.

create_xfs_volume() (
  [ -d /opt/postgresql ] && exit
  mkfs.xfs -f -L postgresql /dev/nvme1n1
  mkdir /opt/postgresql
  tab=$(printf "\t")
  cat <<EOF >> /etc/fstab
LABEL=postgresql${tab}/opt/postgresql${tab}xfs${tab}defaults,nofail${tab}0 2
EOF
  mount -a
  df -h /opt/postgresql
)

install_postgresql() (
  curl -s https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
  cat <<EOF > /etc/apt/sources.list.d/postgresql-pgdg.list
deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main
EOF
  apt-get update
  apt-get install -y postgresql-14 postgresql-contrib
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
  cat <<'EOF' > postgresql.service.d/override.conf
[Service]
LimitMEMLOCK=infinity
LimitNOFILE=300000
EOF
  cd /opt/postgresql
  [ -d data ] && exit
  ln -s /etc/postgresql/14/main conf
  ln -s /usr/lib/postgresql/14/bin
  ln -s /var/log/postgresql logs
  mkdir -p data
  chown -Rh postgres:postgres .
  su postgres -c 'bin/initdb data'
  cd conf
  mv postgresql.conf postgresql-default.conf
  cat <<EOF > postgresql.conf
$(sed 's/[[:blank:]]*$//' <<< "$PG_CONF")
EOF
  mv pg_hba.conf pg_hba-default.conf
  cat <<EOF > pg_hba.conf
$(sed 's/[[:blank:]]*$//' <<< "$PG_HBA")
EOF
  # shared_buffers = 32GB of 64GB total,
  # so set hugepages to accommodate 32GB
  sysctl -w vm.nr_hugepages=$(
    awk '/MemTotal.*kB/ {mt=$2} /Hugepagesize.*kB/ {
      hps=$2; print int(mt / hps * .55)
    }' /proc/meminfo
  )
  run generate_cert
  mv /tmp/server.* .
  chown -h postgres:postgres *
)

start_postgresql() {
  systemctl daemon-reload
  systemctl restart postgresql
  systemctl enable  postgresql
  systemctl status  postgresql --no-pager
}

run create_xfs_volume
run install_postgresql
run config_postgresql
run start_postgresql

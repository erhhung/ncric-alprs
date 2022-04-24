# This user data script is a continuation
# of the bastion host's "boot.sh" script.

install_java() (
  hash java 2> /dev/null && exit
  amazon-linux-extras install -y java-openjdk11
  java --version
  cat <<'EOF' >> /etc/environment
JAVA_HOME="/usr/lib/jvm/jre-11-openjdk"
EOF
)

install_rundeck() (
  [ -d /var/lib/rundeck ] && exit
  # https://docs.rundeck.com/docs/administration/install/linux-rpm.html#installing-rundeck
  curl https://raw.githubusercontent.com/rundeck/packaging/main/scripts/rpm-setup.sh \
    2> /dev/null | bash -s rundeck
  yum install -y rundeck rundeck-cli
)

config_rundeck() (
  case `whoami` in
    root)
      cd /etc/rundeck
      # change the default admin password
      sed -i "s/admin:admin/admin:$rundeck_pass/" realm.properties
      ;;
    $USER)
      mkdir -p rundeck .rd
      # config file for CLI
      cat <<EOF > .rd/rd.conf
export RD_URL="http://localhost:4440"
export RD_USER="admin"
export RD_PASSWORD="$rundeck_pass"
EOF
      chmod 600 .rd/rd.conf
      ;;
  esac
)

wait_service() {
  local name=$1 port=$2 count=12
  while ! nc -z localhost $port && [ $((count--)) -ge 0 ]; do
    echo "[$(date "+%D %r")] Waiting for $name on port $port..."
    sleep 10
  done
  if [ $count -lt 0 ]; then
    echo >&2 "$name failed to start!"
    return 1
  fi
}

start_rundeck() {
  systemctl daemon-reload
  systemctl restart rundeckd
  chkconfig rundeckd on
  wait_service Rundeck 4440
  systemctl status rundeckd
}

import_project() {
  cd rundeck
  aws s3 cp $USR_S3_URL/rundeck/astrometrics.rdproject.jar . --no-progress
  if rd projects list 2> /dev/null | grep -q AstroMetrics; then
    rd projects delete \
      -p AstroMetrics -y
    sleep 1
  fi
  rd projects create \
    -p AstroMetrics
  sleep 1
  rd projects archives import \
    -f astrometrics.rdproject.jar \
    -p AstroMetrics
}

run install_java
run install_rundeck
run config_rundeck
run start_rundeck
run config_rundeck $USER
run import_project $USER

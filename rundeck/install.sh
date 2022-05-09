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
    rundeck)
      mkdir -p projects/AstroMetrics/etc
      cd projects/AstroMetrics/etc
      cat <<EOF > resources.xml
<?xml version="1.0" encoding="UTF-8"?>

<project>
  <node name="Worker"
        description="Rundeck Worker"
        tags="AstroMetrics, worker"
        hostname="$WORKER_IP"
        username="ubuntu"
        osArch="aarch64"
        osFamily="unix"
        osName="Linux"
        osVersion="$WORKER_OS"
        ssh-authentication="privateKey"
        ssh-key-storage-path="keys/worker"
        sudo-password-storage-path="keys/worker"
        sudo-command-enabled="true"
        file-copier="ssh-copier"
  />
</project>
EOF
      ;;
    $USER)
      mkdir -p .rd
      # config file for CLI
      cat <<EOF > .rd/rd.conf
export RD_URL="http://localhost:4440"
export RD_USER="admin"
export RD_PASSWORD="$rundeck_pass"
export RD_PROJECT="AstroMetrics"
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

# eval_with_retry <cmd> [tries]
eval_with_retry() {
  local cmd=$1 tries=${2:-3}
  while [[ ! $(eval $cmd) && $((--tries)) -gt 0 ]]; do
    echo "Retrying: $cmd"
    sleep 1
  done
  sleep 1
}

import_project() {
  local jar proj="AstroMetrics"
  jar="${proj,,}.rdproject.jar"
  mkdir -p rundeck
  cd rundeck
  aws s3 cp "$USR_S3_URL/rundeck/$jar" . --no-progress
  if rd projects list 2> /dev/null | grep -q $proj; then
    eval_with_retry "rd projects delete -p $proj -y"
  fi
  eval_with_retry "rd projects create -p $proj"
  rd projects archives import -f $jar -p $proj
}

import_ssh_key() {
  echo "$rundeck_key" > /tmp/worker
  rd keys create \
    -t privateKey \
    -f /tmp/worker \
    -p keys/worker
  rm /tmp/worker
}

set_property() {
  local file=$1 key=$2 value="$3"
  ( grep -v "$key:" $file
    echo "$key: $value"
  ) | sort > $file~
  mv  $file~ $file
}

config_project() {
  local config=/tmp/config
  rd projects configure get -p AstroMetrics | \
    sed -e :a -e '/./,$!d;/^\n*$/{$d;N;};/\n$/ba' > $config
  set_property $config project.ssh-authentication   privateKey
  set_property $config project.ssh-key-storage-path keys/worker
  set_property $config project.ssh-keypath
  rd projects configure set -p AstroMetrics -f $config
  cat $config
  rm  $config
}

curl_rundeck() {
  local cookies=/tmp/cookies
  [ -f $cookies ] || echo "#EMPTY" > $cookies
  curl -b $cookies -c $cookies -s \
    "http://localhost:4440/$1" "${@:2}"
}

config_worker() {
  # first authenticate and
  # store JSESSIONID cookie
  curl_rundeck j_security_check \
    -d j_password=$rundeck_pass \
    -d j_username=admin -i | \
    grep -q user/error && return 1

  params=(
    project=AstroMetrics
    serviceName=ResourceModelSource
    configPrefix=resources.source
  )
  uri='project/AstroMetrics/nodes/sources'
  token=$(curl_rundeck $uri | grep web_ui_token | \
        sed -En 's/.+"TOKEN":"([0-9a-f]+)".+/\1/p')
  route='framework/saveProjectPluginsAjax'
  route+="?$(IFS=\&; echo "${params[*]}")"
  curl_rundeck "$route" \
    -H "x-rundeck-token-uri: /$uri"  \
    -H "x-rundeck-token-key: $token" \
    -H 'Content-Type: application/json' \
    -d '{"plugins":[{
        "type":"file",
        "extra":{},
        "config":{
          "format":"resourcexml",
          "file":"/var/lib/rundeck/projects/AstroMetrics/etc/resources.xml",
          "requireFileExists":"true",
          "writeable":"true"
        }}]}'
}

export -f eval_with_retry
export -f set_property
export -f curl_rundeck

run install_java
run install_rundeck
run config_rundeck
run config_rundeck rundeck
run start_rundeck
run config_rundeck $USER
run import_project $USER
run import_ssh_key $USER
run config_project $USER
run config_worker  $USER

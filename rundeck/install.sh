# This user data script is a continuation
# of the bastion host's "boot.sh" script.

export NCRIC_DB="org_1446ff84711242ec828df181f45e4d20"
# NOTE: the --shuttle-config option expects TWO values: config bucket and region
export SHUTTLE_ARGS="--shuttle-config $CONFIG_BUCKET REGION --read-rate-limit 0"

install_java() (
  hash java 2> /dev/null && exit
  eval_with_retry "amazon-linux-extras install -y java-openjdk11"
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
  VERSION=4.6.1.20220914-1
  # list available versions: yum list rundeck --showduplicates
  eval_with_retry "yum install -y rundeck-$VERSION rundeck-cli"
)

install_plugins() (
  mkdir -p plugins
  cd plugins
  # https://github.com/rundeck-plugins/openssh-node-execution
  PLUGIN=openssh-node-execution VERSION=2.0.2
  curl -sLO https://github.com/rundeck-plugins/$PLUGIN/releases/download/$VERSION/$PLUGIN-$VERSION.zip
  unzip -ojd $PLUGIN-$VERSION $PLUGIN-$VERSION.zip '*/ssh-*.sh'
  unzip -o                    $PLUGIN-$VERSION.zip '*/resources/*'
  # work around "rd_secure_passphrase: invalid indirect expansion" error
  # https://github.com/rundeck-plugins/openssh-node-execution/issues/21
  sed -Ei 's/\$\{\!rd_secure_passphrase\}/${rd_secure_passphrase+x}/g' $PLUGIN-$VERSION/ssh-*.sh
  cd ~/libext
  # https://github.com/rundeck-plugins/rundeck-s3-log-plugin
  PLUGIN=rundeck-s3-log-plugin VERSION=1.0.13
  curl -sLO https://github.com/rundeck-plugins/$PLUGIN/releases/download/v$VERSION/$PLUGIN-$VERSION.jar
)

config_rundeck() (
  case `whoami` in
    root)
      cd /etc/ssh
      # send RD_* environment variables to remote workers
      sed -Ei $'/^Host \*$/a \\\tSendEnv RD_*' ssh_config
      cd /etc/init.d
      # update init.d script to use patched openssh-node-execution plugin
      cmd='sleep 2m; cp -a plugins/openssh-node-execution*/ libext/cache'
      sed -Ei "s|^(.+runuser.+-c).+$|\1 '$cmd' \&> /dev/null \&\n\0|" rundeckd
      ;;
    rundeck)
      aws s3 sync $S3_URL/rundeck/email email --no-progress
      # https://docs.rundeck.digitalstacks.net/l/en/document-formats/resource-xml
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
        always-set-pty="true"
        ssh-send-env="true"
        ssh-authentication="privateKey"
        ssh-key-storage-path="keys/worker"
        sudo-password-storage-path="keys/worker"
        sudo-command-enabled="true"
        file-copier="ssh-copier"
  />
</project>
EOF
      cd /etc/rundeck
      # change default admin password and
      # allow login as devadmin|prodadmin
      while read -r expr; do
        sed -Ei "$expr" realm.properties
      done <<EOT
/^${ENV}admin:/d
s/^admin:[^,]+,/admin: $rundeck_pass,/
s/^admin:.+$/\0\n$ENV\0/
EOT
      # install "rundeck-config.properties" and "framework.properties",
      # customized to use PostgreSQL instead of H2 as primary database,
      # and S3 bucket instead of local disk to store job execution logs
      aws s3 sync s3://$CONFIG_BUCKET/rundeck/ . --no-progress
      find . -type f -exec chmod 640 {} \;
      ;;
    $DEFAULT_USER)
      mkdir -p .rd
      # config file for CLI
      cat <<EOF > .rd/rd.conf
export RD_URL="http://localhost:4440"
export RD_USER="admin"
export RD_PASSWORD="$rundeck_pass"
export RD_PROJECT="AstroMetrics"
EOF
      chmod 600 .rd/rd.conf
      sleep 20
      ;;
  esac
)

wait_service() {
  local name=$1 port=$2 count=12
  while ! nc -z localhost $port && [ $((count--)) -ge 0 ]; do
    echo "[`__ts`] Waiting for $name on port $port..."
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

import_project() (
  proj=AstroMetrics
  mkdir -p rundeck
  cd rundeck

  if eval_with_retry "rd projects list" | grep -q $proj; then
    # project already exists; backup before overwriting
    echo "Archiving Rundeck project \"$proj\"..."
    jar="${proj,,}_$(date "+%Y-%m-%d").rdproject.jar"
    args=(-p $proj -f $jar -i jobs -i configs -i executions)
    eval_with_retry "rd projects archives export ${args[*]}"
    aws s3 cp $jar s3://$BACKUP_BUCKET/rundeck/$jar --no-progress
  else
    echo "Creating Rundeck project \"$proj\"..."
    eval_with_retry "rd projects create -p $proj"
  fi

  jar="${proj,,}.rdproject.jar"
  aws s3 cp "$S3_URL/rundeck/$jar" . --no-progress
  eval_with_retry "rd projects archives import -f $jar -p $proj"

  if [ "$ENV" == dev ]; then
    jobs=($(rd jobs list -% %id))  # disable all jobs on DEV
    rd jobs unschedulebulk -i $(IFS=,; echo "${jobs[*]}") -y
  fi
  rd jobs list -f - -F yaml | \
    yq '.[] | ["job=", .id, " scheduled=", .scheduleEnabled]
            | join("")'
)

import_ssh_key() {
  local path=keys/worker
  local file=/tmp/worker
  # $rundeck_key is private key here
  printf "%s" "$rundeck_key" > $file
  eval_with_retry "rd keys delete -p $path" &> /dev/null || true
  eval_with_retry "rd keys create -p $path -t privateKey -f $file"
  rm $file
}

extra_aliases() {
  echo -e \\n >> .bash_aliases
  cat <<'EOF' >> .bash_aliases
disable_rundeck_jobs() {
  rd jobs list -f - -F yaml | \
    yq '.[] | ["job=", .id, " scheduled=", .scheduleEnabled]
            | join("")'
  ask >&2 "\nProceed?" N || return 0
  local jobs=($(rd jobs list -% %id))
  rd jobs unschedulebulk -i $(IFS=,; echo "${jobs[*]}") -y
}
EOF
}

curl_rundeck() {
  local cookies=/tmp/cookies
  [ -f $cookies ] || echo "#EMPTY" > $cookies
  curl -b $cookies -c $cookies -s \
    "http://localhost:4440/$1" "${@:2}"
  echo
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

set_property() {
  local file=$1 key=$2 value="$3"
  ( grep -v "$key:" $file
    echo "$key: $value"
  ) | sort > $file~
  mv  $file~ $file
}

# https://docs.rundeck.digitalstacks.net/l/en/node-execution/ssh-node-execution
config_project() {
  local proj=AstroMetrics config=/tmp/config
  # use sed to trim leading/trailing newlines
  rd projects configure get -p $proj | \
    sed -e :a -e '/./,$!d;/^\n*$/{$d;N;};/\n$/ba' > $config
  # ensure process tree gets terminated if job times out
  set_property $config project.always-set-pty       true
  # ensure RD_* environment variables are sent to Worker
  set_property $config project.ssh-send-env         true
  set_property $config project.ssh-authentication   privateKey
  set_property $config project.ssh-key-storage-path keys/worker
  set_property $config project.ssh-keypath
  rd projects configure set -p $proj -f $config
  cat $config
  rm  $config

  shopt -s expand_aliases
  set +x; . .bash_aliases; set -x
  cd rundeck
  local az=$(myaz)
  cat <<EOF > keys.txt
keys/region            ${az:0:-1}
keys/api_url           http://datastore:8080
keys/s3_bucket         $SFTP_BUCKET
keys/s3_prefix/boss4   boss4
keys/s3_prefix/scso    scso
keys/s3_prefix/flock   flock
keys/s3_prefix/hotlist hotlist
keys/shuttle_args      ${SHUTTLE_ARGS/REGION/${az:0:-1}}
keys/db_host           $PG_HOST
keys/db_name           $NCRIC_DB
keys/db_user           atlas_user
keys/db_pass           $atlas_pass
keys/client_id         $CLIENT_ID
keys/ol_user           $auth0_email
keys/ol_pass           $auth0_pass
EOF
  local path value
  while read path value; do
    mkdir -p /tmp/$(dirname $path)
    printf "%s" "$value" > /tmp/$path
    eval_with_retry "rd keys delete -p $path" &> /dev/null || true
    eval_with_retry "rd keys create -p $path -t password -f /tmp/$path"
  done < keys.txt
  rm -rf /tmp/keys
}

export -f wait_service
export -f eval_with_retry
export -f set_property
export -f curl_rundeck

run install_java
run install_rundeck
run install_plugins rundeck
run config_rundeck
run config_rundeck rundeck
run start_rundeck
run config_rundeck $DEFAULT_USER
run import_project $DEFAULT_USER
run import_ssh_key $DEFAULT_USER
run extra_aliases  $DEFAULT_USER
run config_worker  $DEFAULT_USER
run config_project $DEFAULT_USER

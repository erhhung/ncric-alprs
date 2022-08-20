# This user data script is a continuation of
# the shared "boot.sh" script. It's included
# on Conductor/Datastore/Indexer hosts only.

etc_hosts() (
  cd /etc
  [ "$CONDUCTOR_IP" ] && host=conductor ip=$CONDUCTOR_IP
  [ "$DATASTORE_IP" ] && host=datastore ip=$DATASTORE_IP
  [ "$host" ] || exit 0
  grep -q $host hosts && exit
  tab=$(printf "\t")
  cat <<EOF >> hosts

${ip}${tab}${host}
EOF
)

create_user() (
  cd /home/$USER
  egrep -q '^openlattice:' /etc/passwd && exit
  cat <<EOF >> .bashrc
export CONFIG_BUCKET="$CONFIG_BUCKET"
EOF
  echo -e \\n >> .bash_aliases
  cat <<'EOF' >> .bash_aliases
alias psj='ps auxw | grep -v grep | grep java'
alias mol='most +1000000 /opt/openlattice/logging/*[!0-9].log'
EOF
  # adduser copies files from /etc/skel
  # into the new user's home directory
  cp -a .bashrc .bash_aliases .gitconfig .emacs \
    .screenrc .sudo_as_admin_successful /etc/skel
  adduser --disabled-login --gecos "" openlattice

  cat <<'EOF' >> .bash_aliases
alias ol='sudo su -l openlattice '
alias olstart='ol -c scripts/start.sh'
alias olstop='ol -c "killall java"'
EOF
  cat <<'EOF' >> /home/openlattice/.bashrc

cd $HOME/scripts
EOF
  cd /etc/sudoers.d
  usermod -aG sudo openlattice
  cat <<'EOF' > 91-openlattice-user
openlattice ALL=(ALL) NOPASSWD:ALL
EOF
)

install_java() (
  hash java 2> /dev/null && exit
  eval_with_retry "wait_apt_get && apt-get install -y openjdk-11-jdk"
  java --version
  cat <<'EOF' >> /etc/environment
JAVA_HOME="/usr/lib/jvm/java-11-openjdk-arm64"
EOF
)

install_delta() (
  cd /tmp
  hash delta 2> /dev/null && exit
  wget -q https://github.com/dandavison/delta/releases/download/0.12.0/git-delta_0.12.0_arm64.deb
  eval_with_retry "wait_apt_get && dpkg -iE git-delta_0.12.0_arm64.deb"
  rm git-delta*
)

init_destdir() {
  mkdir -p /opt/openlattice
  chown -Rh openlattice:openlattice /opt/openlattice
}

copy_scripts() {
  aws s3 sync $S3_URL/${HOST,,}/scripts scripts --no-progress
  find scripts -type f -name '*.sh' -exec chmod +x {} \;
}

git_clone() {
  local url=$1 dest=$2
  # supply token if cloning MaiVERIC private repo
  if [[ "$url" == *//github.com/maiveric/* ]]; then
    # https://github.blog/2012-09-21-easier-builds-and-deployments-using-git-over-https-and-oauth/
    url=${url/\/\/github.com\//\/\/$GH_TOKEN:x-oauth-basic@github.com\/}
  fi
  git clone $url $dest
}

clone_repos() {
  rm -rf openlattice
  git_clone https://github.com/openlattice/openlattice.git
  cd openlattice
  rmdir neuron
  git sub init
  git sub deinit neuron
}

config_service() {
  az_url="http://169.254.169.254/latest/meta-data/placement/availability-zone"
  region=$(curl -s $az_url | sed 's/[a-z]$//')
  cd openlattice/${HOST,,}/src/main/resources
  cat <<EOF > aws.yaml
region: $region
bucket: $CONFIG_BUCKET
folder: ${HOST,,}
EOF
  if [ "$FROM_EMAIL" ]; then
    cd ~/openlattice/conductor-client/src/main/kotlin/com/openlattice/search/renderers
    for file in Alpr*EmailRenderer.kt; do
      sed -Ei "s/FROM_EMAIL =.+/FROM_EMAIL = \"$FROM_EMAIL\"/" $file
    done
  fi
}

build_service() {
  # build and then install
  scripts/build.sh develop
}

wait_service() {
  local name=$1 host=$2 port=$3
  while ! nc -z $host $port; do
    echo "[`__ts`] Waiting for $name on $host:$port..."
    sleep 10
  done
}

start_service() {
  heap_size=$(awk '/MemTotal.*kB/ {print int($2 /1024/1024 / 2)+1}' /proc/meminfo)
  exports=$(cat <<EOT

export ${HOST}_XMS="-Xms${heap_size}g"
export ${HOST}_XMX="-Xmx${heap_size}g"
EOT
)
  grep -q _XMS .bashrc || echo "$exports" >> .bashrc
  eval "$exports"
  case $HOST in
    DATASTORE) wait_service CONDUCTOR $CONDUCTOR_IP 5701 ;;
    INDEXER)   wait_service DATASTORE $DATASTORE_IP 8080 ;;
  esac
  sleep 30
  # optional flags, like edmsync, may
  # be defined by individual services
  scripts/start.sh "${SVC_FLAGS[@]}"
}

archive_build() (
  service=${HOST,,}
  src=${service}.tgz
  cd /opt/openlattice
  [ -f $src ] || exit 0
  dest="s3://$BACKUP_BUCKET/$service/${service}_$(date "+%Y-%m-%d").tar.gz"
  aws s3 cp $src $dest --no-progress
)

# invoke REST API that triggers indexing of all EDM objects
# since Elasticsearch will have no content when provisioned
trigger_index() (
  [ $HOST == INDEXER ] || exit 0
  sleep 30
  params=(
    client_id=$CLIENT_ID
    grant_type=password
    username=$auth0_email
    password=$auth0_pass
    audience=https://$auth0_domain/userinfo
    scope=openid
  )
  jwt=$(curl -sX POST https://$auth0_domain/oauth/token \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "$(IFS=\&; echo "${params[*]}")" | jq -r .id_token)
  set -x
  curl -H "Authorization: Bearer $jwt" \
    -so /dev/null -w '%{http_code}\n' \
    http://datastore:8080/datastore/search/edm/index
)

export -f git_clone
export -f wait_service

run etc_hosts
run create_user
run install_java
run install_delta
run init_destdir
run copy_scripts   openlattice
run clone_repos    openlattice
run config_service openlattice
run build_service  openlattice
run start_service  openlattice
run archive_build
run trigger_index

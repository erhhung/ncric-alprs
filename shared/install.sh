# This user data script is a continuation
# of the host-specific "boot.sh" script.

create_user() (
  cd /home/$USER
  egrep -q '^openlattice:' /etc/passwd && exit
  cp .bash_aliases .gitconfig .emacs .screenrc \
    .sudo_as_admin_successful /etc/skel
  adduser --disabled-login --gecos "" openlattice
  cat <<'EOF' >> .bash_aliases

alias ol='sudo su -l openlattice'
EOF
  cat <<'EOF' >> /home/openlattice/.bashrc

cd $HOME/ncric-transfer/scripts/${HOSTNAME/#*-/}
EOF
  cd /etc/sudoers.d
  usermod -aG sudo openlattice
  cat <<'EOF' > 91-openlattice-user
openlattice ALL=(ALL) NOPASSWD:ALL
EOF
)

install_java() (
  hash java 2> /dev/null && exit
  wait_apt_get
  apt-get install -y openjdk-11-jdk
  java --version
  cat <<'EOF' >> /etc/environment
JAVA_HOME="/usr/lib/jvm/java-11-openjdk-arm64"
EOF
)

install_delta() (
  cd /tmp
  hash delta 2> /dev/null && exit
  wget -q https://github.com/dandavison/delta/releases/download/0.12.0/git-delta_0.12.0_arm64.deb
  wait_apt_get
  dpkg -i git-delta_0.12.0_arm64.deb
  rm git-delta*
)

init_destdir() (
  mkdir -p /opt/openlattice
  chown -Rh openlattice:openlattice /opt/openlattice
)

clone_repos() {
  rm -rf openlattice ncric-transfer
  git clone https://github.com/openlattice/openlattice.git
  cd openlattice
  rmdir neuron
  git sub init
  git sub deinit neuron
  cd ..
  git clone https://github.com/openlattice/ncric-transfer.git
  cd ncric-transfer
  git co main
  git up
}

config_service() {
  az_url="http://169.254.169.254/latest/meta-data/placement/availability-zone"
  region=$(curl -s $az_url | sed 's/[a-z]$//')
  cd ~/openlattice/${HOST,,}/src/main/resources
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
  cd ncric-transfer/scripts/${HOST,,}
  # build script also installs
  ./build-latest.sh develop
}

wait_service() {
  local name=$1 host=$2 port=$3
  while ! nc -z $host $port; do
    echo "[$(date "+%D %r")] Waiting for $name on $host:$port..."
    sleep 10
  done
}

launch_service() {
  heap_size=$(awk '/MemTotal.*kB/ {print int($2 /1024/1024 / 2)+1}' /proc/meminfo)
  exports=$(cat <<EOT

export ${HOST}_XMS="-Xms${heap_size}g"
export ${HOST}_XMX="-Xmx${heap_size}g"
EOT
)
  echo "$exports" >> .bashrc
  eval "$exports"
  case $HOST in
    DATASTORE) wait_service CONDUCTOR $CONDUCTOR_IP 5701 ;;
    INDEXER)   wait_service DATASTORE $DATASTORE_IP 8080 ;;
  esac
  cd ncric-transfer/scripts/${HOST,,}
  # optional flags, like edmsync, may
  # be defined by individual services
  ./boot.sh "${SVC_FLAGS[@]}"
}

export -f wait_service

run create_user
run install_java
run install_delta
run init_destdir
run clone_repos    openlattice
run config_service openlattice
run build_service  openlattice
run launch_service openlattice

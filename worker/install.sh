# This user data script is a continuation
# of the shared "boot.sh" script.

install_java() (
  hash java 2> /dev/null && exit
  wait_apt_get
  apt-get install -y openjdk-11-jdk
  java --version
  cat <<'EOF' >> /etc/environment
JAVA_HOME="/usr/lib/jvm/java-11-openjdk-arm64"
EOF
)

install_python() (
  hash pip3 2> /dev/null && exit
  wait_apt_get
  apt-get install -y python3.8 python3-pip
  pip3 --version
)

install_pylibs() (
  cd /tmp
  lib=pyntegrationsncric
  pip3 freeze | grep -q $lib && exit
  pip3 install boto3 sqlalchemy pandas dask auth0-python
  aws s3 cp "$S3_URL/worker/$lib.whl" . --no-progress
  # rename file to conform to wheel naming convention
  whl=$(unzip -l $lib.whl | sed -En "s|.+($lib-[0-9.]+)\.dist-info/WHEEL|\1-py3-none-any.whl|p")
  mv  $lib.whl $whl
  pip3 install $whl
  rm $whl
)

install_delta() (
  cd /tmp
  hash delta 2> /dev/null && exit
  wget -q https://github.com/dandavison/delta/releases/download/0.12.0/git-delta_0.12.0_arm64.deb
  wait_apt_get
  dpkg -i git-delta_0.12.0_arm64.deb
  rm git-delta*
)

user_dotfiles() {
  cat <<EOF >> .bashrc
export MEDIA_BUCKET="$MEDIA_BUCKET"
export SFTP_BUCKET="$SFTP_BUCKET"
EOF
  SITE_PACKAGES_PATH=$(python3 -m site --user-site)
  PYNTEGRATIONS_PATH="$SITE_PACKAGES_PATH/pyntegrationsncric/pyntegrations"
  [ -d $PYNTEGRATIONS_PATH ] || exit $?
  # only variables defined in /etc/environment will be
  # picked up by Rundeck jobs, even though they're run
  # via SSH as the ubuntu user with exports in .bashrc
  cat <<EOF | sudo tee -a /etc/environment
PYNTEGRATIONS_PATH="$PYNTEGRATIONS_PATH"
EOF
}

auth_ssh_key() {
  cd .ssh
  # $rundeck_key is public key here
  grep -q "$rundeck_key" authorized_keys || \
     echo "$rundeck_key" >> authorized_keys
}

config_sshd() (
  cd /etc/ssh
  grep -q 'AcceptEnv RD_' sshd_config && exit
  # accept RD_* environment variables from Rundeck
  sed -i '/AcceptEnv/a AcceptEnv RD_*' sshd_config
  service ssh reload
)

clone_repos() {
  rm -rf shuttle
  git clone https://github.com/openlattice/shuttle.git
}

build_shuttle() {
  cd shuttle
  ./gradlew clean :distTar -x test
  SHUTTLE_PATH="/opt/openlattice/shuttle/shuttle-0.0.4-SNAPSHOT/bin/shuttle"
  cat <<EOF | sudo tee -a /etc/environment
SHUTTLE_PATH="$SHUTTLE_PATH"
EOF
}

run install_java
run install_python
run install_pylibs $USER
run install_delta
run user_dotfiles  $USER
run auth_ssh_key   $USER
run config_sshd
run clone_repos    $USER
run build_shuttle  $USER

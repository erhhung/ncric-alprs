# This user data script is a continuation
# of the shared "boot.sh" script.

apt_install() {
  apt_update
  wait_apt_get
  apt-get install -y libpq-dev
}

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

install_delta() (
  cd /tmp
  hash delta 2> /dev/null && exit
  wget -q https://github.com/dandavison/delta/releases/download/0.12.0/git-delta_0.12.0_arm64.deb
  wait_apt_get
  dpkg -i git-delta_0.12.0_arm64.deb
  rm git-delta*
)

init_destdir() {
  mkdir -p /opt/openlattice
  chown -Rh $USER:$USER /opt/openlattice
}

config_sshd() (
  cd /etc/ssh
  grep -q 'AcceptEnv RD_' sshd_config && exit
  # accept RD_* environment variables from Rundeck
  sed -i '/AcceptEnv/a AcceptEnv RD_*' sshd_config
  service ssh reload
)

auth_ssh_key() {
  cd .ssh
  # $rundeck_key is public key here
  grep -q "$rundeck_key" authorized_keys || \
     echo "$rundeck_key" >> authorized_keys
}

copy_scripts() {
  aws s3 sync $S3_URL/worker/scripts scripts --no-progress
  find scripts -type f -name '*.sh' -exec chmod +x {} \;
}

clone_repos() {
  rm -rf openlattice
  git clone https://github.com/openlattice/openlattice.git
  cd openlattice
  rmdir neuron
  git sub init
  git sub deinit neuron
  git clone https://github.com/openlattice/api-clients clients
}

install_pylibs() (
  wheels=(pyntegrationsncric olpy)
  pip3 freeze | grep -q $wheels && exit
  # install required packages: see appendix 2, "Setting
  # up ETL Environment", in the "Data Integration Guide"
  pip3 install boto3 psycopg2 sqlalchemy pandas pandarallel dask auth0-python geopy testresources
  cd openlattice/clients/python
  pip3 install .

  mkdir -p ~/packages
  cd ~/packages
  aws s3 sync $S3_URL/worker . --exclude '*' --include '*.whl' --no-progress
  for wheel in ${wheels[@]}; do
    # rename file to conform to wheel naming convention
    whl=$(unzip -l $wheel.whl | sed -En "s|.+($wheel-[0-9.]+)\.dist-info/WHEEL|\1-py3-none-any.whl|p")
    mv -f $wheel.whl $whl
    pip3  install -I $whl
  done
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

build_shuttle() (
  # build and then install
  scripts/shuttle/build.sh develop
  SHUTTLE_PATH=/opt/openlattice/shuttle/bin/shuttle
  sudo ln -sf  $SHUTTLE_PATH /usr/local/bin/shuttle
  grep -q SHUTTLE_PATH /etc/environment && exit
  cat <<EOF | sudo tee -a /etc/environment
SHUTTLE_PATH="$SHUTTLE_PATH"
EOF
)

run apt_install
run install_java
run install_python
run install_delta
run init_destdir
run config_sshd
run auth_ssh_key   $USER
run copy_scripts   $USER
run clone_repos    $USER
run install_pylibs $USER
run user_dotfiles  $USER
run build_shuttle  $USER

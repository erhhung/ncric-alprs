# This user-data cloud-init script is a continuation
# of a host-specific "boot.sh" script.

create_user() (
  cd /home/$USER
  egrep -q '^openlattice:' /etc/passwd && exit
  cp .bash_aliases .emacs /etc/skel
  adduser --disabled-login --gecos "" openlattice
  cat <<'EOF' >> .bash_aliases

alias ol='sudo su -l openlattice'
EOF
)

install_java() (
  hash java 2> /dev/null && exit
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
  dpkg -i git-delta_0.12.0_arm64.deb
  rm git-delta*
)

init_destdir() (
  mkdir -p /opt/openlattice
  chown -Rh openlattice:openlattice /opt/openlattice
)

clone_repos() (
  git clone https://github.com/openlattice/ncric-transfer.git
  pushd ncric-transfer
  git co main
  git up
  popd
  git clone https://github.com/openlattice/openlattice.git
  pushd openlattice
  git co main
  git up
  popd
)

build_service() (
  cd ncric-transfer/scripts/${HOST,,}
  ./build-latest.sh # also installs
)

launch_service() (
  cd /opt/openlattice/${HOST,,}
)

run create_user
run install_java
run install_delta
run init_destdir
run clone_repos    openlattice
run build_service  openlattice
run launch_service openlattice

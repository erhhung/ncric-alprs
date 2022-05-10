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
}

auth_ssh_key() {
  cd .ssh
  grep -q "$rundeck_key" authorized_keys || \
     echo "$rundeck_key" >> authorized_keys
}

clone_repos() {
  rm -rf shuttle
  git clone https://github.com/openlattice/shuttle.git
}

build_agent() {
  cd shuttle
  ./gradlew clean :distTar -x test
}

run install_java
run install_delta
run user_dotfiles $USER
run auth_ssh_key  $USER
run clone_repos   $USER
run build_agent   $USER

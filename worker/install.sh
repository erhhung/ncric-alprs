# This user data script is a continuation
# of the shared "boot.sh" script.

etc_hosts() (
  cd /etc
  grep -q postgresql hosts && exit
  printf -v tab "\t"
  cat <<EOF >> hosts

$POSTGRESQL1_IP${tab}postgresql1
$POSTGRESQL2_IP${tab}postgresql2
$DATASTORE_IP${tab}datastore
EOF
)

apt_install() {
  apt_update
  eval_with_retry "wait_apt_get && apt-get install -y python3-dev libpq-dev libevent-dev"
}

upgrade_pip() {
  pip3 install -U pip
  # upgrade existing pyOpenSSL package
  # to use latest cryptography package
  pip3 install -U pyOpenSSL
}

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
  VERSION=0.12.0 ARCH=arm64
  wget -q https://github.com/dandavison/delta/releases/download/$VERSION/git-delta_${VERSION}_$ARCH.deb
  eval_with_retry "wait_apt_get && dpkg -iE git-delta_${VERSION}_$ARCH.deb"
  rm git-delta*
)

install_docker() (
  hash docker 2> /dev/null && exit
  eval_with_retry "wait_apt_get && apt-get install -y docker.io"
  usermod -aG docker $DEFAULT_USER
)

install_kube() (
  case `whoami` in
    root)
      cd /usr/local/bin
      K8S_VER=$(curl -Ls https://dl.k8s.io/release/stable.txt)
      wget -q https://dl.k8s.io/release/$K8S_VER/bin/linux/arm64/kubectl
      chmod +x kubectl
      ;;
    $DEFAULT_USER)
      aws eks update-kubeconfig \
        --name alprs \
        --role-arn $EKS_ROLE_ARN
      context=$(kubectl config current-context)
      kubectl config rename-context $context alprs
      ;;
  esac
)

install_helm() (
  curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash -
  helm plugin install https://github.com/databus23/helm-diff
  #helm plugin install https://github.com/erhhung/helm-ssm
)

install_pgcli() {
  pip3 install pgcli
  mkdir -p .config/pgcli
  aws s3 cp $S3_URL/postgresql/pgcli.conf .config/pgcli/config --no-progress
}

install_psql() (
  curl -s https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
  cd /etc/apt/sources.list.d
  cat <<EOF > postgresql-pgdg.list
deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main
EOF
  apt_update
  eval_with_retry "wait_apt_get && apt-get install -y postgresql-client-14"
)

init_destdir() {
  mkdir -p /opt/openlattice
  chown -Rh $DEFAULT_USER:$DEFAULT_USER /opt/openlattice
  chmod go+w /usr/local/bin
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

copy_scripts() (
  aws s3 sync $S3_URL/worker/scripts scripts --no-progress
  find scripts -type f -name '*.sh' -exec chmod +x {} \;

  ecrpush="scripts/ecrpush"
  [ -f $ecrpush ] && \
    chmod +x $ecrpush && \
    mv $ecrpush /usr/local/bin
)

git_clone() {
  local url=$1 dest=$2
  # supply token if cloning MaiVERIC private repo
  if [[ "$url" == *//github.com/maiveric/* ]]; then
    # https://github.blog/2012-09-21-easier-builds-and-deployments-using-git-over-https-and-oauth/
    url=${url/\/\/github.com\//\/\/oauth2:$GITHUB_TOKEN@github.com\/}
  fi
  git clone $url $dest
}

clone_repos() {
  rm -rf clients
  git_clone https://github.com/maiveric/ol-api-clients.git clients
  rm -rf openlattice
  git_clone https://github.com/maiveric/ol-openlattice.git openlattice
  cd openlattice
  rmdir neuron
  git sub init
  git sub deinit neuron
  git_clone https://github.com/maiveric/ol-flapper.git flapper
}

install_pylibs() (
  wheels=(pyntegrationsncric olpy)
  pip3 freeze | grep -q $wheels && exit
  # install required packages: see appendix 2, "Setting
  # up ETL Environment", in the "Data Integration Guide"
  pip3 install boto3 psycopg2 sqlalchemy pandas pandarallel dask auth0-python geopy testresources
  cd clients/python
  pip3 install .

  mkdir -p ~/packages
  cd ~/packages
  aws s3 sync $S3_URL/worker . --exclude '*' --include '*.whl' --no-progress
  for wheel in ${wheels[@]}; do
    # rename file to conform to wheel naming convention
    whl=$(unzip -l $wheel.whl | sed -En "s|.+($wheel-[0-9.]+)\.dist-info/WHEEL|\1-py3-none-any.whl|p")
    mv -f $wheel.whl $whl
    pip3 install $whl
  done
)

user_dotfiles() (
  cat <<EOF > .git-credentials
https://oauth2:$GITHUB_TOKEN@github.com
https://oauth2:$GITLAB_TOKEN@gitlab.com
EOF
  aws s3 sync $S3_URL/postgresql . --exclude '*' --include '.*' --no-progress
  cat <<EOF >> .bashrc
export CONFIG_BUCKET="$CONFIG_BUCKET"
export MEDIA_BUCKET="$MEDIA_BUCKET"
export SFTP_BUCKET="$SFTP_BUCKET"

export API_URL="$API_URL"
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
)

extra_aliases() {
  echo -e \\n >> .bash_aliases
  aws s3 cp $S3_URL/worker/.bash_aliases - --no-progress >> .bash_aliases
}

build_cli_app() (
  # build and then install
  app=$1 path="${1^^}_PATH"
  scripts/$app/build.sh develop
  eval $path=/opt/openlattice/$app/bin/$app
  [ -f ${!path} ] || exit $?
  sudo ln -sf ${!path} /usr/local/bin/$app
  grep -q $path /etc/environment && exit
  cat <<EOF | sudo tee -a /etc/environment
$path="${!path}"
EOF
)

config_flapper() (
  path=/opt/openlattice/flapper/conf
  FLAPPER_CONF="$path/flapper.yaml"
  mkdir -p $path
  aws s3 sync s3://$CONFIG_BUCKET/flapper $path --no-progress
  [ -f $FLAPPER_CONF ] || exit $?
  grep -q $path /etc/environment && exit
  cat <<EOF | sudo tee -a /etc/environment
FLAPPER_CONF="$FLAPPER_CONF"
EOF
)

export -f git_clone

run etc_hosts
run apt_install
run upgrade_pip    $DEFAULT_USER
run install_java
run install_delta
run install_docker
run install_kube
run install_kube   $DEFAULT_USER
run install_helm   $DEFAULT_USER
run install_pgcli  $DEFAULT_USER
run install_psql
run init_destdir
run config_sshd
run auth_ssh_key   $DEFAULT_USER
run copy_scripts   $DEFAULT_USER
run clone_repos    $DEFAULT_USER
run install_pylibs $DEFAULT_USER
run user_dotfiles  $DEFAULT_USER
run extra_aliases  $DEFAULT_USER
run build_cli_app  $DEFAULT_USER shuttle
run build_cli_app  $DEFAULT_USER flapper
run config_flapper $DEFAULT_USER

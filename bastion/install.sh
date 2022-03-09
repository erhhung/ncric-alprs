# This user-data cloud-init script is a continuation
# of the bastion host's "boot.sh" script.

install_node() (
  hash node 2> /dev/null && exit
  yum install -y gcc-c++ make
  curl -sL https://rpm.nodesource.com/setup_14.x | bash -
  yum install -y nodejs
  node -v && npm -v
)

install_delta() (
  cd /tmp
  hash delta 2> /dev/null && exit
  wget -q https://github.com/dandavison/delta/releases/download/0.12.0/delta-0.12.0-x86_64-unknown-linux-gnu.tar.gz
  tar xzvf delta-0.12.0-x86_64-unknown-linux-gnu.tar.gz -C /usr/bin --strip 1 delta-0.12.0-x86_64-unknown-linux-gnu/delta
  rm -f delta-*.tar.gz
)

etc_hosts() (
  cd /etc
  tab=$(printf "\t")
  cat <<EOF >> hosts

$PG_IP${tab}postgresql
$ES_IP${tab}elasticsearch
EOF
)

clone_repo() (
  git clone https://github.com/openlattice/astrometrics.git
  cd astrometrics
  git co develop
  git up
)

build_webapp() {
  cat <<EOF >> .bashrc

export FONTAWESOME_NPM_AUTH_TOKEN="$FA_TOKEN"
EOF
  . .bashrc
  cd astrometrics
  cat <<'EOF' > .npmrc
@fortawesome:registry=https://npm.fontawesome.com/
//npm.fontawesome.com/:_authToken=${FONTAWESOME_NPM_AUTH_TOKEN}
EOF
  npm install
  npm audit fix
  npm run build:prod
}

run install_node
run install_delta
run etc_hosts
run yum_update
run clone_repo    $USER
run build_webapp  $USER

set +x
echo "[$(date -R)] ===== END ${script^^} ====="

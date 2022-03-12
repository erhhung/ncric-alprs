# This user data script is a continuation
# of the bastion host's "boot.sh" script and
# the "webapp/install.tftpl" template script.

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

clone_repo() {
  git clone https://github.com/openlattice/astrometrics.git
  cd astrometrics
  git co develop
  git up
}

config_webapp() {
  cd astrometrics/src
  sed -Ei "/auth0CdnUrl:/i\  baseUrl: '$API_URL'," index.js
  sed -Ei 's/cdn.auth0.com/cdn.us.auth0.com/'      index.js
  cd ../config/auth
  sed -Ei "s/ID_${ENV^^} =.+/ID_${ENV^^} = '$AUTH0_ID';/"   auth0.config.js
  sed -Ei "s/DOMAIN =.+/DOMAIN = 'maiveric.us.auth0.com';/" auth0.config.js
  cd ../webpack
  # change website base path from /astrometrics to /
  sed -Ei "s|BASE_PATH =.+$|BASE_PATH = '/';|" webpack.config.base.js
}

build_webapp() {
  cd astrometrics
  cat <<EOF > .npmrc
@fortawesome:registry=https://npm.fontawesome.com/
//npm.fontawesome.com/:_authToken=$FA_TOKEN
EOF
  npm install
  npm audit fix
  npm run build:$ENV -- --env.mapboxToken=$MB_TOKEN
}

deploy_webapp() {
  aws s3 sync astrometrics/build $APP_S3_URL
}

run install_node
run install_delta
run yum_update
run clone_repo    $USER
run config_webapp $USER
run build_webapp  $USER
run deploy_webapp $USER

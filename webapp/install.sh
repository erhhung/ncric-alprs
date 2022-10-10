# This user data script is a continuation
# of the bastion host's "boot.sh" script and
# the "webapp/install.tftpl" template script.

install_node() (
  hash node 2> /dev/null && exit
  eval_with_retry "yum install -y gcc-c++ make"
  curl -sL https://rpm.nodesource.com/setup_14.x | bash -
  eval_with_retry "yum install -y nodejs"
  node -v && npm -v
)

install_delta() (
  cd /tmp
  hash delta 2> /dev/null && exit
  VERSION=0.12.0 ARCH=x86_64-unknown-linux-gnu
  wget -q https://github.com/dandavison/delta/releases/download/$VERSION/delta-${VERSION}-$ARCH.tar.gz
  tar xzvf delta-${VERSION}-$ARCH.tar.gz -C /usr/bin --strip 1 delta-${VERSION}-$ARCH/delta
  rm -f delta-*.tar.gz
)

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
  rm -rf astrometrics
  git_clone https://github.com/maiveric/ol-astrometrics.git astrometrics
  cd astrometrics
  git co develop
  git up
  cd $HOME
  rm -rf lattice-orgs
  git_clone https://github.com/maiveric/ol-lattice-orgs.git lattice-orgs
  cd lattice-orgs
  git co develop
  git up
}

# indent lines from stdin by n spaces
indent_code() {
  local sp=${1:-0}
  eval "printf -v sp ' %.0s' {1..$sp}"
  [ "$1" ] && sed "s/^/$sp/" || cat
}

# replace_code <file> <match> <in|ex> <match> <in|ex>
# in|ex: start/end line is <in>clusive or <ex>clusive
# the replacement content will be obtained from stdin
replace_code() {
  set +x
  local   file=$1 code=$(cat)
  local match0=$2  ex0=$3 line
  local match1=$4  ex1=$5 state
  (
    while IFS= read line; do
      case $state in
        started)
          if [[ "$line" == *$match1* ]]; then
            [ "$ex1" == ex ] && echo "$line"
            state=ended
          fi
          ;;
        ended)
          echo "$line"
          ;;
        *)
          if [[ "$line" == *$match0* ]]; then
            [ "$ex0" == ex ] && echo "$line"
            echo "$code"
            if [[ "$line" == *$match1* ]]; then
              # echo start/end line at most
              # once if they match the same
              [ "$ex1$ex0" == exin ] && echo "$line"
              state=ended
            else
              state=started
            fi
          else
            echo "$line"
          fi
          ;;
      esac
    done <   "$file"
  ) | sponge "$file"
  set -x
}

config_app() (
  cat <<EOF > .npmrc
@fortawesome:registry=https://npm.fontawesome.com/
//npm.fontawesome.com/:_authToken=$FA_TOKEN
EOF
  cd src
  grep -q 'auth0CdnUrl:'                                                   index.js && \
    sed -Ei 's/cdn.auth0.com/cdn.us.auth0.com/'                            index.js || \
    sed -Ei "/auth0ClientId:/i\  auth0CdnUrl: 'https://cdn.us.auth0.com'," index.js
  grep -q 'baseUrl:'                                 index.js || \
    sed -Ei "/auth0CdnUrl:/i\  baseUrl: '$API_URL'," index.js
  cd ../config/auth
  sed -Ei "s/ID_${ENV^^} =.+/ID_${ENV^^} = '$AUTH0_ID';/"   auth0.config.js
  sed -Ei "s/DOMAIN =.+/DOMAIN = 'maiveric.us.auth0.com';/" auth0.config.js
  cd ../webpack
  sed -Ei "s|BASE_PATH =.+$|BASE_PATH = '/';|" webpack.config.base.js
)

config_webapp() {
  cd astrometrics
  config_app

  # tweak branding and support contact
  cd src
  while read file; do
    sed -Ei 's/\bAstrometrics\b/AstroMetrics/' $file
  done < <(egrep -rl '\bAstrometrics\b')
  while read file; do
    sed -Ei "s/[a-zA-Z0-9_.+-]+@openlattice\\.com\b/$SUPPORT_EMAIL/g" $file
  done < <(egrep -rl '@openlattice\.com\b')

  # show Data Quality tab to all users
  # (currently showing to owners only)
  cd containers/app
  cat <<'EOF' | indent_code 8 | \
    replace_code AppContainer.js \
      '<Route path={Routes.EXPLORE} component={ExploreContainer} />' ex \
      '<Redirect to={Routes.EXPLORE} />'                             ex
<Route path={Routes.QUALITY} component={QualityContainer} />
{
  isAdmin && (
    <Route path={Routes.AUDIT} component={AuditContainer} />
  )
}
EOF
  cat <<'EOF' | indent_code 4 | \
    replace_code AppNavigationContainer.js \
      '<NavLinkWrapper to={Routes.EXPLORE}>' in \
      '</NavigationContentWrapper>'          ex
<NavLinkWrapper to={Routes.EXPLORE}>
  Search
</NavLinkWrapper>
<NavLinkWrapper to={Routes.QUALITY}>
  Data Quality
</NavLinkWrapper>
{
  isAdmin && (
    <NavLinkWrapper to={Routes.AUDIT}>
      Audit Log
    </NavLinkWrapper>
  )
}
EOF
  cd ../quality
  cat <<'EOF' | indent_code 4 | \
    replace_code QualityDashboard.js \
      'rows.sort' in 'rows.sort' in
// sort table by Count in descending order, then by Agency in ascending order
rows.sort((a, b) => a[2] != b[2] ? b[2] - a[2] : a[0].localeCompare(b[0]));
EOF
}

config_orgapp() {
  cd lattice-orgs
  export ENV=dev
  config_app
}

change_logo() (
  cd node_modules/lattice-auth/build
  logo=$(aws s3 cp s3://$WEBAPP_BUCKET/$1-logo.png - | base64 -w0)
  # newer versions of lattice-auth use the exports syntax, so search both patterns
  sed -Ei 's|logo:"data:[^"]+"|logo:"data:image/png;base64,'$logo'"|'       index.js
  sed -Ei 's|exports="data:[^"]+"|exports="data:image/png;base64,'$logo'"|' index.js
)

start_orgapp() {
  cd lattice-orgs
  npm install
  change_logo maiveric
  nohup npm run app &> app.log & disown
}

build_webapp() {
  cd astrometrics
  # do NOT run "audit fix" as that changes
  # "lattice-auth" version in package.json
  # (should be "0.21.2-any-base-url")
  npm install
  change_logo astrometrics
  npm run build:$ENV -- --env.mapboxToken=$MB_TOKEN
}

deploy_webapp() {
  build=astrometrics/build
  # don't upload "favicon_v2.png" because
  # new version has already been uploaded
  rm -f $build/favicon_v2.png
  aws s3 sync $build s3://$WEBAPP_BUCKET --no-progress
}

archive_build() {
  service=astrometrics
  build=$service/build
  dest="s3://$BACKUP_BUCKET/$service/${service}_$(date "+%F").tar.gz"
  tar czf - -C $build . | aws s3 cp - $dest --no-progress
}

export -f git_clone
export -f indent_code
export -f replace_code
export -f config_app
export -f change_logo

run install_node
run install_delta
run clone_repos   $DEFAULT_USER
run config_webapp $DEFAULT_USER
run config_orgapp $DEFAULT_USER
run start_orgapp  $DEFAULT_USER
run build_webapp  $DEFAULT_USER
run deploy_webapp $DEFAULT_USER
run archive_build $DEFAULT_USER

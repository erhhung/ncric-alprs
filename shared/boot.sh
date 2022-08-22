set_hostname() (
  hostname="alprs${ENV}-${HOST,,}"
  echo $hostname > /etc/hostname
  hostname $hostname
)

set_timezone() {
  timedatectl set-timezone America/Los_Angeles
  service cron restart
  timedatectl
}

# eval_with_retry <cmd> [tries]
eval_with_retry() {
  local cmd="$1" tries=${2:-3}
  while ! eval "$cmd" && [ $((--tries)) -gt 0 ]; do
    echo "RETRYING: $cmd"
    sleep 5
  done
  sleep 1
}

wait_apt_get() {
  while [ "$(lsof -t /var/lib/dpkg/lock \
                     /var/lib/apt/lists/lock \
                     /var/cache/apt/archives/lock)" ]; do
    echo "Waiting on apt/dpkg..."
    sleep 5
  done
}

apt_update() {
  eval_with_retry "wait_apt_get && apt-get update"
}

apt_install() {
  apt_update
  eval_with_retry "wait_apt_get && add-apt-repository -y ppa:git-core/ppa"
  eval_with_retry "wait_apt_get && apt-get dist-upgrade -y"
  eval_with_retry "wait_apt_get && apt-get install -y figlet emacs-nox moreutils most \
                            jq git unzip net-tools nmap pwgen libxml2-utils python3-pip"

  VERSION=v4.27.2 ARCH=linux_arm64
  curl -sLo /usr/bin/yq https://github.com/mikefarah/yq/releases/download/$VERSION/yq_$ARCH
  chmod +x  /usr/bin/yq
}

motd_banner() (
  cd /etc/update-motd.d
  [ -f 11-help-text ] && exit
  cat <<EOF > 11-help-text
#!/bin/sh
figlet -f small "${HOST^^}" | sed '\$d'
EOF
  chmod -x 10-help-text 5* 8* 9*
  chmod +x 11-help-text 90* *reboot*
)

custom_prompt() (
  cd /etc/profile.d
  [ -f custom_prompt.sh ] && exit
  cat <<'EOF' > custom_prompt.sh
#!/bin/bash
export PROMPT_COMMAND='PS1="\[\033[1;36m\]\u\[\033[1;31m\]@\[\033[1;32m\]\h:\[\033[1;35m\]\w\[\033[1;31m\]$\[\033[0m\] "'
EOF
  chmod +x custom_prompt.sh
)

install_awscli() (
  cd /tmp
  curl  -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-$(uname -p).zip
  unzip -oq awscliv2.zip
  ./aws/install --update
  aws --version
  rm -rf /tmp/aws*
  cd /home/$USER
  cat <<'EOF' >> .bashrc

complete -C "$(which aws_completer)" aws
EOF
)

authorize_keys() {
  cd .ssh
  while read key || [ "$key" ]; do
    grep -q "$key" authorized_keys || \
       echo "$key" >> authorized_keys
  done < <(aws s3 cp $S3_URL/shared/authorized_keys -)
}

user_dotfiles() {
  aws s3 sync $S3_URL/shared . --exclude '*' --include '.*' --no-progress
  mkdir -p .cache && touch .cache/motd.legal-displayed
  touch .sudo_as_admin_successful
  chmod +x .lessfilter
  cat <<EOF >> .bashrc

export BACKUP_BUCKET="$BACKUP_BUCKET"
EOF
}

root_dotfiles() (
  cd /home/$USER
  /usr/bin/cp -f .bashrc .bash_aliases .lessfilter .screenrc .gitconfig .emacs /root
)

install_utils() (
  cd /usr/local/bin
  pip3 install pygments --upgrade
  aws s3 cp $S3_URL/shared/lesspipe.sh .
  chmod +x ./lesspipe.sh
)

install_certbot() {
  snap install core
  snap refresh core
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot
}

generate_cert() (
  cd /tmp
  curl -sLo cert.sh http://exampleconfig.com/static/raw/openssl/centos7/etc/pki/tls/certs/make-dummy-cert
  myFQDN=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
  ed -s cert.sh <<EOF
5,11d
5i
  echo US
  echo California
  echo Walnut Creek
  echo MaiVERIC
  echo ALPRS
  echo $myFQDN
  echo root@$myFQDN
.
22d
w
q
EOF
  chmod +x cert.sh
  ./cert.sh server.pem
  openssl storeutl -keys  server.pem | sed '1d;$d' > server.key
  openssl storeutl -certs server.pem | sed '1d;$d' > server.crt
  rm server.pem cert.sh
  chmod 400 server.key
)

install_cwagent() (
  shopt -s expand_aliases
  . .bash_aliases
  cd /tmp
  az=$(myaz) region=${az:0:-1}
  deb=amazon-cloudwatch-agent.deb
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/download-cloudwatch-agent-commandline.html
  curl -sO https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/ubuntu/arm64/latest/$deb
  eval_with_retry "wait_apt_get && apt-get install -y collectd && dpkg -iE ./$deb"
  rm ./$deb
)

config_cwagent() (
  cd /opt/aws/amazon-cloudwatch-agent/etc
  aws s3 cp $S3_URL/${HOST,,}/cwagent.json amazon-cloudwatch-agent.json
)

start_cwagent() (
  cd /opt/aws/amazon-cloudwatch-agent
  # amazon-cloudwatch-agent.json will be converted
  # and replaced with amazon-cloudwatch-agent.toml
  ./bin/amazon-cloudwatch-agent-ctl -a fetch-config \
    -m ec2 -s -c file:etc/amazon-cloudwatch-agent.json
)

export -f eval_with_retry
export -f wait_apt_get
export -f apt_update

run set_hostname
run set_timezone
run apt_install
run motd_banner
run custom_prompt
run install_awscli
run authorize_keys $USER
run user_dotfiles  $USER
run root_dotfiles
run install_utils
run install_cwagent
run config_cwagent
run start_cwagent

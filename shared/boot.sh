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

custom_prompt() (
  cd /etc/profile.d
  [ -f custom_prompt.sh ] && exit
  cat <<'EOF' > custom_prompt.sh
#!/bin/bash
export PROMPT_COMMAND='PS1="\[\033[1;36m\]\u\[\033[1;31m\]@\[\033[1;32m\]\h:\[\033[1;35m\]\w\[\033[1;31m\]$\[\033[0m\] "'
EOF
  chmod +x custom_prompt.sh
)

wait_apt_get() {
  while [ "$(pgrep apt-get)$(pgrep dpkg)" ]; do
    echo "Waiting on apt-get/dpkg..."
    sleep 10
  done
}

apt_install() {
  add-apt-repository -y ppa:git-core/ppa
  wait_apt_get
  apt-get dist-upgrade -y
  wait_apt_get
  apt-get install -y figlet emacs-nox moreutils most jq git unzip net-tools pwgen
  snap install yq
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

install_awscli() (
  cd /tmp
  curl  -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip
  unzip -oq awscliv2.zip
  ./aws/install
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
  cat <<EOF >> .bashrc

export BACKUP_BUCKET="$BACKUP_BUCKET"
EOF
}

root_dotfiles() (
  cd /home/$USER
  /usr/bin/cp -f .bash_aliases .bashrc .emacs /root
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

run set_hostname
run set_timezone
run custom_prompt
run apt_install
run motd_banner
run install_awscli
run authorize_keys $USER
run user_dotfiles  $USER
run root_dotfiles

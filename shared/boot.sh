# This user-data cloud-init script bootstraps a Ubuntu 20.04 server.
# It is appended to the host-specific "boot.tftpl" template script.

cd /root
script="user-data"
exec > >(tee /var/log/$script.log | logger -t $script ) 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== BEGIN ${script^^} ====="
printf "COMMAND: %q" "$0"; (($#)) && printf ' %q' "$@"
echo -e "\nBash version: ${BASH_VERSINFO[@]}"
set -xeo pipefail

# run <func> [user]
run() {
  local func=$1 user=$2
  echo "[${user:-root}] $func"
  if [ $user ]; then
    export -f $func
    su $user -c "bash -c 'cd \$HOME; $func'"
  else
    $func
  fi
}

set_hostname() (
  hostname="alprs${ENV}-${HOST,,}"
  echo $hostname > /etc/hostname
  hostname $hostname
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

apt_install() (
  apt-get update
  apt-get dist-upgrade -y
  apt-get install -y figlet emacs-nox moreutils most unzip net-tools pwgen
)

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
  curl -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf /tmp/aws*
)

user_dotfiles() {
  aws s3 sync $S3_URL/shared . --exclude '*' --include '.*'
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
	echo MaiVERIC, Inc.
	echo ALPR
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
run custom_prompt
run apt_install
run motd_banner
run install_awscli
run user_dotfiles $USER
run root_dotfiles

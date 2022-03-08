# This user-data cloud-init script bootstraps an Amazon Linux2 server.
# It is appended onto the bastion host's "boot.tftpl" template script.

cd /root
script=$(basename "$0" .sh)
exec > >(tee /$script.log | logger -t $script ) 2>&1
echo "[$(date -R)] ===== BEGIN ${script^^} ====="
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

upgrade_bash() {
  [ ${BASH_VERSINFO[0]}${BASH_VERSINFO[1]} -ge 51 ] && return
  yum groupinstall -y "Development Tools"
  cd /tmp
  wget -q https://ftp.gnu.org/gnu/bash/bash-5.1.16.tar.gz
  tar xzf bash-5.1.16.tar.gz
  cd bash-5.1.16
  ./configure --prefix=/
  make && make install
  rm -rf /tmp/bash-5.1.16*
  self=$(realpath "$0")
  echo "RESTARTING..."
  hash -r; sleep 1
  exec "$self" "$@"
}

set_hostname() (
  cd /etc/cloud
  egrep -q '^preserve_hostname: true' cloud.cfg && exit
  ed cloud.cfg <<END
9i

preserve_hostname: true
.
w
q
END
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

yum_update() {
  yum update -y
}

yum_install() {
  yum_update
  rpm -qa | grep -q epel-release-7 || \
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  yum --enablerepo epel install -y figlet emacs-nox moreutils most jq htop pwgen certbot
}

motd_banner() (
  cd /etc/update-motd.d
  [ -f 31-banner ] && exit
  cat <<EOF > 31-banner
#!/bin/sh
figlet -f small "${HOST^^}"
EOF
  chmod -x 30-banner
  chmod +x 31-banner
  update-motd
)

upgrade_awscli() (
  cd /tmp
  curl -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
  unzip -oq awscliv2.zip
  ./aws/install
  rm -rf /tmp/aws*
)

user_dotfiles() {
  aws s3 sync $S3_URL/shared  . --exclude '*' --include '.*' --exclude '.bash*'
  aws s3 sync $S3_URL/bastion . --exclude '*' --include '.*'
}

root_dotfiles() (
  cd /home/$USER
  /usr/bin/cp -f .bash_aliases .bashrc .emacs /root
)

run upgrade_bash
run set_hostname
run custom_prompt
run yum_install
run motd_banner
run upgrade_awscli
run user_dotfiles $USER
run root_dotfiles

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
  yum --enablerepo epel install -y figlet emacs-nox moreutils most jq htop pwgen nmap
  VERSION=v4.22.1; BINARY=yq_linux_amd64
  wget https://github.com/mikefarah/yq/releases/download/$VERSION/$BINARY \
    -q -O /usr/bin/yq && chmod +x /usr/bin/yq
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

authorize_keys() {
  cd .ssh
  while read key || [ "$key" ]; do
    grep -q "$key" authorized_keys || \
       echo "$key" >> authorized_keys
  done < <(aws s3 cp $USR_S3_URL/shared/authorized_keys -)
}

user_dotfiles() {
  aws s3 sync $USR_S3_URL/shared  . --exclude '*' --include '.*' --exclude '.bash*' --no-progress
  aws s3 sync $USR_S3_URL/bastion . --exclude '*' --include '.*' --no-progress
}

root_dotfiles() (
  cd /home/$USER
  /usr/bin/cp -f .bash_aliases .bashrc .emacs /root
)

etc_hosts() (
  cd /etc
  grep -q postgresql hosts && exit
  tab=$(printf "\t")
  cat <<EOF >> hosts
$PG_IP${tab}postgresql
$ES_IP${tab}elasticsearch
EOF
)

run upgrade_bash
run set_hostname
run custom_prompt
run yum_install
run motd_banner
run upgrade_awscli
run authorize_keys $USER
run user_dotfiles  $USER
run root_dotfiles
run etc_hosts

upgrade_bash() {
  cd /tmp
  eval_with_retry 'yum groupinstall -y "Development Tools"'
  curl -s https://ftp.gnu.org/gnu/bash/bash-5.1.16.tar.gz | tar -xz
  (cd bash* && ./configure -q --prefix=/ && make -s && make install)
  rm -rf bash*
  set +x; cd /
  echo -e "\nRESTARTING...\n"
  hash -r; sleep 1
  exec /bootstrap.sh
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

set_timezone() {
  timedatectl set-timezone America/Los_Angeles
  systemctl restart crond
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
  [ $tries -gt 0 ]
}

yum_update() {
  eval_with_retry "yum update -y"
}

yum_install() (
  yum_update
  rpm -qa | grep -q epel-release-7 || \
            eval_with_retry "yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
  eval_with_retry "yum --enablerepo epel install -y figlet emacs-nox moreutils most jq htop pwgen nmap python3-pip"

  VERSION=v4.27.2 ARCH=linux_amd64
  curl -sLo /usr/bin/yq https://github.com/mikefarah/yq/releases/download/$VERSION/yq_$ARCH
  chmod +x  /usr/bin/yq
)

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

custom_prompt() (
  cd /etc/profile.d
  [ -f custom_prompt.sh ] && exit
  cat <<'EOF' > custom_prompt.sh
#!/bin/bash
export PROMPT_COMMAND='PS1="\[\033[1;36m\]\u\[\033[1;31m\]@\[\033[1;32m\]\h:\[\033[1;35m\]\w\[\033[1;31m\]$\[\033[0m\] "'
EOF
  chmod +x custom_prompt.sh
)

upgrade_awscli() (
  cd /tmp
  curl  -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip
  unzip -oq awscliv2.zip
  ./aws/install --update
  aws --version
  rm -rf /tmp/aws*
)

export_buckets() {
  local bucket cmd
  for bucket in "${ALL_BUCKETS[@]}"; do
    cmd="export $bucket"
    echo "$cmd"
    eval "$cmd"
  done
}

authorize_keys() {
  cd .ssh
  while read key || [ "$key" ]; do
    grep -q "$key" authorized_keys || \
       echo "$key" >> authorized_keys
  done < <(aws s3 cp $S3_URL/shared/authorized_keys - --quiet)
}

user_dotfiles() {
  aws s3 sync $S3_URL/shared    . --exclude '*' --include '.*' --exclude '.bash*' --no-progress
  aws s3 sync $S3_URL/${HOST,,} . --exclude '*' --include '.*' --no-progress
  chmod +x .lessfilter
}

root_dotfiles() (
  cd /home/$DEFAULT_USER
  cat <<EOF >> .bashrc

$(for bucket in "${ALL_BUCKETS[@]}"; do echo -en "\nexport $bucket"; done)
EOF
  /usr/bin/cp -f .bashrc .bash_aliases .lessfilter .screenrc .gitconfig .emacs /root
)

install_utils() (
  cd /usr/local/bin
  pip3 install pygments --upgrade
  aws s3 cp $S3_URL/shared/lesspipe.sh . --no-progress
  chmod +x ./lesspipe.sh
)

upgrade_utils() (
  cd /tmp
  # upgrade coreutils 8.22 to 8.30 to support "numfmt --format" decimal precision
  curl -s http://mirrors.kernel.org/gnu/coreutils/coreutils-8.30.tar.xz | tar -xJ
  (cd coreutils* && FORCE_UNSAFE_CONFIGURE=1 ./configure -q --prefix=/usr && make -s && make install)
  rm -rf coreutils*
)

etc_hosts() (
  cd /etc
  grep -q postgresql hosts && exit
  printf -v tab "\t"
  cat <<EOF >> hosts

$POSTGRESQL1_IP${tab}postgresql1
$POSTGRESQL2_IP${tab}postgresql2
$ELASTICSEARCH_IP${tab}elasticsearch
EOF
)

install_scripts() (
  mkdir -p health-check; cd health-check
  aws s3 cp $S3_URL/bastion/health-check.sh . --no-progress
  # also make ~/ readable so logs can be sent to CloudWatch
  chmod +rx health-check.sh ~
)

config_cronjobs() (
  cd /etc/cron.d
  cat <<EOF > health-check
USER=$DEFAULT_USER
HOME=/home/$DEFAULT_USER
PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/$DEFAULT_USER/.local/bin

# min hr dom mon dow user command
*/10 * * * * $DEFAULT_USER bash -c "\$HOME/health-check/health-check.sh $DEVOPS_EMAIL"
EOF
  chmod 644 *
  service crond reload
)

# this is necessary on CentOS to allow apps to
# create temp files like locks under /run/lock
config_tmpfiles() (
  cd /etc/tmpfiles.d
  # see: man tmpfiles.d
  cat <<EOF > jobs.conf
# Type Path Mode UID GID Age Argument
d /var/lock/jobs 0755 $DEFAULT_USER $DEFAULT_USER - -
EOF
  systemd-tmpfiles --create --remove
)

install_cwagent() (
  shopt -s expand_aliases
  set +x; . .bash_aliases; set -x
  cd /tmp
  az=$(myaz) region=${az:0:-1}
  rpm=amazon-cloudwatch-agent.rpm
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/download-cloudwatch-agent-commandline.html
  curl -sO https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/amazon_linux/amd64/latest/$rpm
  eval_with_retry "amazon-linux-extras install -y collectd && rpm -F ./$rpm"
  rm ./$rpm
)

config_cwagent() (
  cd /etc/profile.d
  cat <<'EOF' > cwagent_path.sh
PATH="$PATH:/opt/aws/amazon-cloudwatch-agent/bin"
EOF
  chmod +x cwagent_path.sh
  cd /opt/aws/amazon-cloudwatch-agent/etc
  aws s3 cp $S3_URL/${HOST,,}/cwagent.json amazon-cloudwatch-agent.json --no-progress
)

start_cwagent() (
  cd /opt/aws/amazon-cloudwatch-agent
  # amazon-cloudwatch-agent.json will be converted
  # and replaced with amazon-cloudwatch-agent.toml
  ./bin/amazon-cloudwatch-agent-ctl -a fetch-config \
    -m ec2 -s -c file:etc/amazon-cloudwatch-agent.json
)

extra_aliases() {
  echo -e \\n >> .bash_aliases
  cat <<'EOF' >> .bash_aliases
alias logs='most +999999 ~/health-check/*.log'
EOF
}

if [ ${BASH_VERSINFO[0]}${BASH_VERSINFO[1]} -lt 51 ]; then
  run upgrade_bash; exit
fi

export_buckets

export -f eval_with_retry
export -f yum_update

run set_hostname
run set_timezone
run yum_install
run motd_banner
run custom_prompt
run upgrade_awscli
run authorize_keys $DEFAULT_USER
run user_dotfiles  $DEFAULT_USER
run root_dotfiles
run install_utils
run upgrade_utils
run etc_hosts
run install_scripts $DEFAULT_USER
run config_cronjobs
run config_tmpfiles
run install_cwagent
run config_cwagent
run start_cwagent
run extra_aliases $DEFAULT_USER

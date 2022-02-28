# This user-data cloud-init script bootstraps an Amazon Linux2 server.
# It is appended to the bastion host's "boot.tftpl" script template.

script="user-data"
exec > >(tee /var/log/$script.log | logger -t $script ) 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== BEGIN ${script^^} ====="
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

upgrade_bash() (
  [ ${BASH_VERSINFO[0]} -eq 4 -a \
    ${BASH_VERSINFO[1]} -eq 4 ] && exit
  yum groupinstall -y "Development Tools"
  cd /tmp
  wget -q http://ftp.gnu.org/gnu/bash/bash-4.4.tar.gz
  tar xzf bash-4.4.tar.gz
  cd bash-4.4
  ./configure --prefix=/
  make && make install
  rm -rf /tmp/bash-4.4*
)

set_hostname() (
  cd /etc/cloud
  egrep -q '^preserve_hostname: true' cloud.cfg && exit
  ed cloud.cfg <<END
9i

# This will cause the set+update hostname module to not operate (if true)
preserve_hostname: true
.
w
q
END
  hostname="alprs${ENV}-${HOST,,}"
  echo $hostname > /etc/hostname
  hostname $hostname
)

yum_install() {
  yum update  -y
  yum install -y emacs-nox htop jq certbot
  yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  yum --enablerepo epel install -y figlet most
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

custom_prompt() (
  cd /etc/profile.d
  [ -f custom_prompt.sh ] && exit
  cat <<'EOF' > custom_prompt.sh
#!/bin/bash
export PROMPT_COMMAND='PS1="\[\033[1;36m\]\u\[\033[1;31m\]@\[\033[1;32m\]\h:\[\033[1;35m\]\w\[\033[1;31m\]$\[\033[0m\] "'
EOF
  chmod +x custom_prompt.sh
)

root_dotfiles() {
  cd /home/$USER
  /usr/bin/cp -f .bash_aliases .bashrc .emacs $HOME/
}

upgrade_awscli() (
  cd /tmp
  curl -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf /tmp/aws*
)

bashrc_aliases() (
  [ -f .bash_aliases ] && exit
  cat <<'EOF' > .bash_aliases
# Emacs -*-Shell-Script-*- Mode

export LSCOLORS=GxFxCxDxBxegedabagaced
export EDITOR="/usr/bin/emacs"
export PAGER="/usr/bin/most"

export LESSQUIET=1 \
LESS='-RKMi -x4 -z-4' \
LESS_ADVANCED_PREPROCESSOR=1 \
LESS_TERMCAP_mb=$'\E[1;31m' \
LESS_TERMCAP_md=$'\E[1;36m' \
LESS_TERMCAP_me=$'\E[0m' \
LESS_TERMCAP_so=$'\E[01;44;33m' \
LESS_TERMCAP_se=$'\E[0m' \
LESS_TERMCAP_us=$'\E[1;32m' \
LESS_TERMCAP_ue=$'\E[0m'

alias cdd='cd - > /dev/null'
alias pwd='printf "%q\n" "$(builtin pwd)/"'
alias ls='ls --color=auto'
alias ll='ls -alF'
alias lt='ls -ltr'
alias la='ls -A'
alias s='screen'
alias du0='_diskusage . 0'
alias du1='_diskusage . 1'
alias sudo='sudo -E '
alias l=less
alias mud='most /var/log/user-data.log'

alias yu='sudo yum update -y'
alias yi='sudo yum install'

alias myip='printf "public: %s\n local: %s\n" "$(_instmeta public-ipv4)" "$(_instmeta local-ipv4)"'
alias myid='_instmeta instance-id'
alias myaz='_instmeta placement/availability-zone'
alias mytype='_instmeta instance-type'
alias myhost='_instmeta local-hostname'

# my instance metadata
# _instmeta <rel_path>
_instmeta() {
  echo $(curl -s "http://instance-data/latest/meta-data/$1")
}

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}

__touch_date() {
  local d=$(date '+%Y%m%d%H%M.00')
  if [ "$1" != '-t' ]; then
    echo "$d"
    return
  fi
  if [ "$1" == "-t" ]; then
    if [[ ! "$2" =~ ^[0-9]{0,12}$ ]]; then
      echo >&2 'Custom time must be all digits!'
      return 1
    fi
    if [ $((${#2} % 2)) -eq 1 ]; then
      echo >&2 'Even number of digits required!'
      return 1
    fi
    local n=$((12 - ${#2}))
    echo "${d:0:$n}$2.00"
  fi
}

_touch() {
  local d; d=$(__touch_date "$@") || return $?
  [ "$1" == '-t' ] && shift 2
  touch -cht "$d" "$@"
}
alias t='_touch'

touchall() {
  local d fargs=()
  if [ "$1" == '-d' ]; then
    fargs=(-type d); shift
  fi
  d=$(__touch_date "$@") || return $?
  [ "$d" ] && shift 2
  find "${@:-.}" "${fargs[@]}" -exec touch -cht "$d" "{}" \;
}
alias ta='touchall'
alias tad='touchall -d'

dnsips() {
  nslookup "$1" | grep 'Address: ' | colrm 1 9 | sort -V
}
sslcert() {
  # openssl s_client -connect {HOSTNAME}:{PORT} -showcerts
  nmap -p ${2:-443} --script ssl-cert "$1"
}
listening() {
  netstat -ant | grep LISTEN | grep -E 'tcp4?' | sort -V
}
_diskusage() {
  local path="${1:-.}" depth=${2:-1}
  du -d $depth -x -h "$path" 2> >(grep -v 'Permission denied') | sort -h
}

# delete files and/or dirs older than x days
# rmold [--confirm] <days> [path] [findopts]
rmold() {
  if [ -z "$1" ]; then
    echo 'rmold [--confirm] <days> [path] [find_opts]'
    echo 'Performs dry run unless --confirm specified'
    return
  fi

  local conf=$1
  [ "$conf" == '--confirm' ] && shift

  local days=$1; shift
  if ! [ ${days:-0} -eq ${days:-1} 2> /dev/null ]; then
    echo >&2 'Days must be an integer!'
    return 1
  fi

  if [[ "$conf" == '--confirm' ]]; then
    find "$@" ! -path . -maxdepth 1 -mtime "+$days" -exec rm -rf "{}" \;
  else
    find "$@" ! -path . -maxdepth 1 -mtime "+$days" -printf "%T@ [%TD %TH:%TM] %s %p\n" 2> /dev/null \
      | sort -n | awk '{ hum[1]=" B";
      hum[1024**4]="TB"; hum[1024**3]="GB";
      hum[1024**2]="MB"; hum[1024   ]="KB";
      for (x = 1024**4; x > 0; x /= 1024) {
        if ($4 >= x) {
          printf $2" "$3"  %3.f %s  %s\n", $4/x, hum[x], $5; break;
        }
      }}';
  fi
}

# show JSON from stdin in color
jql() {
  _jql() { jq -C . | less -R; }
  (($#)) && (cat "$@" | _jql) || _jql
}

# show S3 bucket size/count
# usage: bsize <bucket>
bsize() (
  bucket=$1

  if [ -z "$bucket" ]; then
    echo 'Show S3 bucket size/count'
    echo 'Usage: bsize <bucket>'
    exit
  fi

  # ensure aws/jq/numfmt installed
  _reqcmds aws jq numfmt || exit 1

  # get bucket region
  region=$(aws s3api get-bucket-location \
             --bucket $bucket 2> /dev/null | \
    jq -r '.LocationConstraint // "us-east-1"')
  if [ -z "$region" ]; then
    echo >&2 "Cannot determine bucket location!"
    exit 1
  fi

  stypes=(
    StandardStorage
    IntelligentTieringFAStorage
    IntelligentTieringIAStorage
    IntelligentTieringAAStorage
    IntelligentTieringAIAStorage
    IntelligentTieringDAAStorage
    StandardIAStorage
    StandardIASizeOverhead
    StandardIAObjectOverhead
    OneZoneIAStorage
    OneZoneIASizeOverhead
    ReducedRedundancyStorage
    GlacierInstantRetrievalStorage
    GlacierStorage
    GlacierStagingStorage
    GlacierObjectOverhead
    GlacierS3ObjectOverhead
    DeepArchiveStorage
    DeepArchiveObjectOverhead
    DeepArchiveS3ObjectOverhead
    DeepArchiveStagingStorage)

  # _bsize <metric> <stype>
  _bsize() {
    utnow=$(date +%s)
    period=$((60*60*24*2))
    metric=$1 stype=$2

aws cloudwatch get-metric-statistics  \
  --start-time  $(($utnow - $period)) \
  --end-time    $utnow  \
  --period      $period \
  --region      $region \
  --namespace   AWS/S3  \
  --metric-name $metric \
  --dimensions  Name=BucketName,Value=$bucket \
                Name=StorageType,Value=$stype \
  --statistics  Average 2> /dev/null | \
  jq -r '.Datapoints[].Average // 0'
  }

  total=$(
    (for stype in ${stypes[@]}; do
       _bsize BucketSizeBytes $stype
     done; echo 0) | \
      paste -sd+ - | bc
  )
  count=$(_bsize NumberOfObjects AllStorageTypes)

  # _print <label> <number> <units> <format> [suffix]
  _print() {
read label number units format suffix <<< "$@"
echo "$label"

numfmt $number \
  --to="$units" \
  --suffix="$suffix" \
  --format="$format" | \
  sed -En 's/([^0-9]+)$/ \1/p'
  }

  cols=($(
    _print Size "0${total}" iec-i "%.2f" B
    [ "0${count}" -lt 1000 ] && echo Count $count || \
      _print Count "0${count}" si "%.2f"
  ))
  printf "%5s: %6s %s\n" "${cols[@]}"
)

# empty entire S3 bucket
# usage: emptyb <bucket>
emptyb() (
  bucket=$1

  if [ -z "$bucket" ]; then
    echo 'Empty entire S3 bucket'
    echo 'Usage: emptyb <bucket>'
    exit
  fi

  # ensure aws/jq installed
  _reqcmds aws jq || exit 1

  PAGER="" PAGE_SIZE=500

  # _delobjs <type> <label>
  _delobjs() {
    type=$1 label=$2 token
    opts=() page objs count

while [ "$token" != null ]; do
  page="$(
aws s3api list-object-versions \
  --bucket $bucket "${opts[@]}" \
  --query="[{Objects: ${type}[].{Key:Key,VersionId:VersionId}}, NextToken]" \
  --page-size $PAGE_SIZE \
  --max-items $PAGE_SIZE \
  --output json)" || exit $?

  objs="$(jq '.[0] | .+={Quiet:true}' <<< "$page")"
count="$(jq '.Objects | length' <<< "$objs")"
token="$(jq -r '.[1]' <<< "$page")"
  opts=(--starting-token "$token")

  if [ $count -gt 0 ]; then
    aws s3api delete-objects \
      --bucket $bucket \
      --delete "$objs"
    jq -r '.Objects[].Key | "['$label'] "+.' <<< "$objs"
  fi
done
  }
  _delobjs Versions      VER
  _delobjs DeleteMarkers DEL
)
EOF
  cat <<'EOF' > .bashrc
# Emacs -*-Shell-Script-*- Mode

# not sure why Ctrl-L is broken
# after upgrading to Bash 4.4
bind -x '"\C-l": clear;'

# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

# User specific aliases and functions
if [ -f $HOME/.bash_aliases ]; then
  . $HOME/.bash_aliases
fi
EOF
)

add_dotemacs() (
  [ -f .emacs ] && exit
  cat <<'EOF' > .emacs
;; ===== Disable Startup Message =====
(setq inhibit-startup-message t)

(package-initialize)

;; ===== Hide Menu and Tool Bars =====
(if (display-graphic-p)
  (tool-bar-mode 0))
(menu-bar-mode t)

;; ===== Set Window Size Based On Resolution =====
(defun set-frame-size-according-to-resolution ()
  (interactive)
  (if window-system
  (progn
    (if (> (x-display-pixel-width) 1280)
           (add-to-list 'default-frame-alist (cons 'width 140))
           (add-to-list 'default-frame-alist (cons 'width 80)))
    (add-to-list 'default-frame-alist
         (cons 'height (/ (- (x-display-pixel-height) 220)
                             (frame-char-height))))
    )))

(set-frame-size-according-to-resolution)

;; ===== Launch Window In Front =====
(if (display-graphic-p)
  (x-focus-frame nil))

;; ===== Set Local site-lisp Path =====
(add-to-list 'load-path "/usr/local/share/emacs/site-lisp")
(add-to-list 'load-path "/usr/local/share/emacs/24.5/site-lisp")

;; ===== Set ELPA archives =====
(setq package-archives
  '(("gnu"   . "http://elpa.gnu.org/packages/")
     ("melpa" . "http://melpa.org/packages/")
   ))

;; ===== Load Theme =====
(if (boundp 'custom-theme-load-path)
  (progn
    (add-to-list 'custom-theme-load-path "~/.emacs.d/elpa/dracula-theme-20200124.1953")
  ))

;; ===== Set Fonts =====
(modify-frame-parameters
  (selected-frame)
  '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*")))

(add-hook
  'after-make-frame-functions
    (lambda (frame)
      (modify-frame-parameters
        frame
        '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*"))
      )))

;; ===== Line By Line Scrolling =====
(setq scroll-step 1)

;; ===== Turn Off Tab Character =====
(setq-default indent-tabs-mode nil)

;; ===== Disable Auto-Indentation of New Lines =====
(when (fboundp 'electric-indent-mode) (electric-indent-mode -1))

;; ===== Make Tab Key Do Indent First Then Completion =====
(setq-default tab-always-indent t)

;; ===== Set Default Tab Width =====
(setq-default tab-width 2)
(setq standard-indent   2)
(setq sh-basic-offset   2)
(setq sh-indentation    2)

;; ===== Support Wheel Mouse Scrolling =====
(if (display-graphic-p)
  (mouse-wheel-mode t))

;; ===== Prevent Emacs From Making Backup Files =====
(setq make-backup-files nil)

;; ===== Show Line+Column Numbers on Mode Line =====
  (line-number-mode t)
(column-number-mode t)

;; ===== Define Auto-Loading of Scripting Major Modes =====
(add-to-list 'interpreter-mode-alist '("bash"   . shell-script-mode))
(add-to-list 'interpreter-mode-alist '("python" . python-mode))

;; ===== Make Text Mode The Default Mode For New Buffers =====
(setq default-major-mode 'text-mode)

;; ===== Prevent Emacs From Inserting a NewLine at EOF =====
(setq next-line-add-newline nil)
(setq require-final-newline nil)
EOF
)

add_screenrc() (
  [ -f .screenrc ] && exit
  cat <<'EOF' > .screenrc
startup_message off
caption always "%{= kc}%H (load: %l)%-21=%{= .m}%D %m/%d/%Y %0c"
termcapinfo xterm* ti@:te@
defscrollback 5000

screen -t task  1 bash --login
screen -t shell 2 bash --login
screen -t htop  3 htop
select 1
EOF
)

run bashrc_aliases $USER
run add_dotemacs   $USER
run add_screenrc   $USER
run upgrade_bash
run set_hostname
run yum_install
run motd_banner
run custom_prompt
run root_dotfiles
run upgrade_awscli

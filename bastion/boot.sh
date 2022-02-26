# this cloud-init script bootstraps an Amazon Linux2 server

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
  yum install -y emacs-nox htop jq
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

# Black        0;30     Dark Gray     1;30
# Blue         0;34     Light Blue    1;34
# Green        0;32     Light Green   1;32
# Cyan         0;36     Light Cyan    1;36
# Red          0;31     Light Red     1;31
# Magenta      0;35     Light Magenta 1;35
# Brown/Orange 0;33     Yellow        1;33
# Light Gray   0;37     White         1;37

export   BLACK='\033[0;30m'
export   WHITE='\033[1;37m'
export    GRAY='\033[0;37m'
export    BLUE='\033[0;34m'
export   GREEN='\033[0;32m'
export    CYAN='\033[0;36m'
export     RED='\033[0;31m'
export MAGENTA='\033[0;35m'
export  YELLOW='\033[1;33m'
export   NOCLR='\033[0m'

# cd $OLDPWD only works in Bash
alias cdd='cd - > /dev/null'
# print cwd in shell escaped form
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

# require given commands
# to be $PATH accessible
# example: _reqcmds aws jq || return 1
_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}

alias myip='printf "public: %s\n local: %s\n" "$(_instmeta public-ipv4)" "$(_instmeta local-ipv4)"'
alias myid='_instmeta instance-id'
alias myaz='_instmeta placement/availability-zone'
alias mytype='_instmeta instance-type'

# my instance metadata
# _instmeta <rel_path>
_instmeta() {
  echo $(curl -s "http://instance-data/latest/meta-data/$1")
}

# helper for _touch and touchall
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

# usage: _touch [-t time] <files...>
# -t: digits in multiples of 2 replacing right-most
#     digits of current time in yyyyMMddHHmm format
_touch() {
  local d; d=$(__touch_date "$@") || return $?
  [ "$1" == '-t' ] && shift 2
  touch -cht "$d" "$@"
}
alias t='_touch'

# recursively touch files & directories
# usage: touchall [-d] [-t time] [path]
# -d: touch directories only
# -t: digits in multiples of 2 replacing right-most
#     digits of current time in yyyyMMddHHmm format
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

# get IP addresses from specified nslookup host
dnsips() {
  nslookup "$1" | grep 'Address: ' | colrm 1 9 | sort -V
}
# see SSL certificate information for a website
sslcert() {
  # openssl s_client -connect {HOSTNAME}:{PORT} -showcerts
  nmap -p ${2:-443} --script ssl-cert "$1"
}
# show TCP4 ports currently in LISTENING state
listening() {
  netstat -ant | grep LISTEN | grep -E 'tcp4?' | sort -V
}
# show disk usage (please use du0/du1 aliases)
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

  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-dimensions.html
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
      page="$(aws s3api list-object-versions \
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

;; Added by Package.el. This must come before configurations of
;; installed packages. Don't delete this line. If you don't want
;; it, just comment it out by adding a semicolon to the start of
;; the line. You may delete these explanatory comments.
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
    ;; use 120 char wide window for largeish displays,
    ;; smaller 80 column windows for smaller displays.
    ;; pick whatever numbers make sense for you
    (if (> (x-display-pixel-width) 1280)
           (add-to-list 'default-frame-alist (cons 'width 140))
           (add-to-list 'default-frame-alist (cons 'width 80)))
    ;; for the height, subtract a couple hundred pixels
    ;; from the screen height (for panels, menubars and
    ;; whatnot), then divide by the height of a char to
    ;; get the height we want
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
(setq package-archives '(("gnu"   . "http://elpa.gnu.org/packages/")
                         ("melpa" . "http://melpa.org/packages/")
                        ))

;; ===== Load Theme =====
(if (boundp 'custom-theme-load-path)
  (progn
    (add-to-list 'custom-theme-load-path "~/.emacs.d/elpa/dracula-theme-20200124.1953")
  ))

;(if (display-graphic-p)
;; https://draculatheme.com/emacs/
;  (load-theme 'dracula t)
;)

;; ===== Set Fonts =====
(modify-frame-parameters
  (selected-frame)
  '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*")))

(add-hook 'after-make-frame-functions
          (lambda (frame)
            (modify-frame-parameters
              frame
              '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*"))
              )))

;; ===== Set Colors =====
;; Set cursor and mouse-pointer colors
;(set-cursor-color "red")
;(set-mouse-color "goldenrod")
;; Set region background color
;(set-face-background 'region "blue")
;; Set Emacs background color
;(set-background-color "black")

;; ===== Set Highlight Current Line Minor Mode =====
;; In every buffer, the line which contains the cursor
;; will be fully highlighted
;(global-hl-line-mode t)

;; ===== Line By Line Scrolling =====
;; This makes the buffer scroll by only a single line when the up
;; or down cursor keys push the cursor (tool-bar-mode) outside the
;; buffer. The standard emacs behaviour is to reposition the cursor
;; in the center of screen, but this can make scrolling confusing
(setq scroll-step 1)

;; ===== Turn Off Tab Character =====
;; Emacs normally uses both tabs and spaces to indent lines. If you
;; prefer, all indentation can be made from spaces only. To request
;; this, set `indent-tabs-mode' to `nil'. This is a per-buffer variable;
;; altering the variable affects only the current buffer, but it can be
;; disabled for all buffers.
;; Use (setq ...) to set value locally to a buffer
;; Use (setq-default ...) to set value globally
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

;; ===== Write Backup Files in Designated Folder =====
;; Enable backup files
;(setq make-backup-files t)
;; Enable versioning with default values
;(setq version-control t)
;; Save all backup file in this directory
;(setq backup-directory-alist (quote ((".*" . "~/.emacs.d/backups/"))))

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
run upgrade_awscli

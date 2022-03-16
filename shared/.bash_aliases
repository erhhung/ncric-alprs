# Emacs -*-Shell-Script-*- Mode

export LSCOLORS=GxFxCxDxBxegedabagaced \
EDITOR='emacs' \
PAGER='most' \
AWS_PAGER='' \
DELTA_PAGER='less' \
MOST_SWITCHES='-sw +u'

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
alias sudo='sudo -E '
alias du0='_diskusage . 0'
alias du1='_diskusage . 1'
alias s='screen'

alias ag='sudo apt-get '
alias agu='ag update'
alias agi='ag install'
alias agd='ag dist-upgrade -y'
alias agr='ag autoremove -y --purge'

alias l='less'
alias mbs='most +10000 /bootstrap.log'
alias mol='most +1000000 /opt/openlattice/logging/*.log'
alias tol='tail -f /opt/openlattice/logging/*.log'

alias myip='printf "public: %s\n local: %s\n" "$(_instmeta public-ipv4)" "$(_instmeta local-ipv4)"'
alias myid='_instmeta instance-id'
alias myaz='_instmeta placement/availability-zone'
alias mytype='_instmeta instance-type'
alias myhost='_instmeta local-hostname'

# my instance metadata
# _instmeta <rel_path>
_instmeta() {
  echo $(curl -s "http://169.254.169.254/latest/meta-data/$1")
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

# show TCP4 ports currently in LISTENING state
listening() {
  netstat -ant | grep LISTEN | grep -E 'tcp4?' | sort -V
}
# show disk usage (please use du0/du1 aliases)
_diskusage() {
  local path="${1:-.}" depth=${2:-1}
  du -d $depth -x -h "$path" 2> >(grep -v 'Permission denied') | sort -h
}

# view website SSL certificate details
# sslcert [host=localhost] [port=8443]
sslcert() {
  local host=${1:-localhost} port=${2:-8443}
  if [ ${host-0} -eq ${host-1} 2> /dev/null ]; then
    port=$host; host=localhost
  fi

  openssl s_client \
    -servername $host \
    -connect $host:$port \
    -showcerts <<< '' 2> /dev/null | \
    openssl x509 -inform pem -noout -text
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

# Emacs -*-Shell-Script-*- Mode

export LSCOLORS=GxFxCxDxBxegedabagaced
export TIME_STYLE=long-iso
export EDITOR=emacs
export PAGER=less
export AWS_PAGER=''
export DELTA_PAGER=less
export MOST_SWITCHES='-sw +u'

export LESSQUIET=1
export LESS='-RKMi -x4 -z-4'
export LESS_ADVANCED_PREPROCESSOR=1
export LESSCOLORIZER=pygmentize
export LESS_TERMCAP_mb=$'\E[1;31m'
export LESS_TERMCAP_md=$'\E[1;36m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_us=$'\E[1;32m'
export LESS_TERMCAP_ue=$'\E[0m'

export   BLACK='\033[0;30m'
export    GRAY='\033[1;30m'
export  LTGRAY='\033[0;37m'
export   WHITE='\033[1;37m'
export     RED='\033[0;31m'
export  ORANGE='\033[1;31m'
export   GREEN='\033[0;32m'
export LTGREEN='\033[1;32m'
export   OCHRE='\033[0;33m'
export  YELLOW='\033[1;33m'
export    BLUE='\033[0;34m'
export  LTBLUE='\033[1;34m'
export MAGENTA='\033[0;35m'
export    PINK='\033[1;35m'
export    CYAN='\033[0;36m'
export  LTCYAN='\033[1;36m'
export   NOCLR='\033[0m'

alias cdd='cd - > /dev/null'
alias pwd='printf "%q\n" "$(builtin pwd)/"'
alias ls='ls --color=auto'
alias ll='ls -alFG --color=always'
alias lt='ls -altr --color=always'
alias la='ls -A'
alias sudo='sudo -E '
alias time=`which time`' -f "\n Total time: %E\n  User mode: %Us\nKernel mode: %Ss\nPercent CPU: %P" '
alias s=screen

alias l=less
alias m=most
alias mbs='most +10000 /bootstrap.log'

# suppress stack output
pushd() {
  command pushd "$@" > /dev/null
}
popd() {
  command popd  "$@" > /dev/null
}

# require given commands
# to be $PATH accessible
# example: _reqcmds aws jq || return
_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}

# my instance metadata
# _instmeta <rel_path>
_instmeta() {
  local value=$(curl -s "http://169.254.169.254/latest/meta-data/$1")
  [[ "$value" =~ "404 - Not Found" ]] && return 1 || echo "$value"
}

alias myip='printf " local: %s\npublic: %s\n" \
         "$(_instmeta local-ipv4)" \
         "$(_instmeta public-ipv4 || echo none)"'
alias myid='_instmeta instance-id'
alias myaz='_instmeta placement/availability-zone'
alias mytype='_instmeta instance-type'
alias myhost='_instmeta local-hostname'

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
  local d; d=$(__touch_date "$@") || return
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
  d=$(__touch_date "$@") || return
  [ "$d" ] && shift 2
  find "${@:-.}" "${fargs[@]}" -exec touch -cht "$d" "{}" \;
}
alias ta='touchall'
alias tad='touchall -d'

# get IPs from the specified nslookup host
dnsips() {
  nslookup "$1" | grep 'Address: ' | colrm 1 9 | sort -V
}

# show TCP4 ports currently in LISTENING state
listening() {
  netstat -ant | grep LISTEN | grep -E 'tcp4?' | sort -V
}

_diskusage() {
  local depth=${1:-1} path=${2:-.}
  du -d $depth -x -h "${path/%\//}" \
     2> >(grep -v 'Permission denied') | sort -h
}
alias du0='_diskusage 0'
alias du1='_diskusage 1'

# view website SSL certificate details
# sslcert [host=localhost] [port=443]
sslcert() {
  local host=${1:-localhost} port=${2:-443}
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
    find "$@" ! -path . -maxdepth 1 -mtime "+$days" \
        -exec rm -rf "{}" \;
  else
    find "$@" ! -path . -maxdepth 1 -mtime "+$days" \
        -printf "%T@ [%TD %TH:%TM] %s %p\n" 2> /dev/null \
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
lj() {
  # ensure jq installed
  _reqcmds jq || return
  __lj() { jq -C . | less -LR; }
  (($#)) && (cat "$@" | __lj) || __lj
}
# show YAML from stdin in color
ly() {
  # ensure pygmentize installed
  _reqcmds pygmentize || return
  __ly() {
    pygmentize -l yaml -O style=native 2> /dev/null | \
      less -LR
  }
  (($#)) && (cat "$@" | __ly) || __ly
}
# show XML from stdin in color
_lx() {
  # ensure xmllint/pygmentize installed
  _reqcmds xmllint pygmentize || return
  local style=$1; shift
  __lx() {
    xmllint --pretty $style - | \
      pygmentize -l xml -O style=native 2> /dev/null | \
      less -LR
  }
  (($#)) && (cat "$@" | __lx) || __lx
}
alias lx=' _lx 1'
alias lx0='_lx 0'
alias lx1='_lx 1'
alias lx2='_lx 2'

urlencode() {
  local url
  (($#)) && url="$@" || url=$(cat)

  python3 -c "import sys,urllib.parse as ul;
print(ul.quote_plus(sys.stdin.read().strip()))" <<< "$url"
}
alias ue=urlencode

# urldecode [-v var] URL
#  -v assign decoded URL to variable
#     var instead of output to stdout
urldecode() {
  local var url
  if [[ "$1" == '-v' && $# -ge 2 ]]; then
    var="$2"
    shift 2
  fi
  (($#)) && url="$@" || url=$(cat)

  url="${url//+/ }"
  url="${url//%/\\x}"
  [ "$var" ] && printf -v "$var" %b "$url" \
             || printf       "%b\n" "$url"
}
# decode + prettify
_urldecode() {
  local url path query param
  (($#)) && url="$@" || url=$(cat)

  read path query < <(tr \? ' ' <<< "$url")
  echo -e "$LTGREEN$path$NOCLR"

  eval "echo -e \"$(
    while read param; do urldecode "$param"
    done < <(sed 's/&/\n/g' <<< "$query") | \
    sed -E 's/^([^=]+)=(.*)$/${LTBLUE}\1$WHITE = ${NOCLR}\2/'
  )\""
}
alias ud=_urldecode

# convert between yaml and json
alias yaml2json='python3 -c "import sys,yaml,json; json.dump(yaml.full_load(sys.stdin),sys.stdout,indent=2)"'
alias json2yaml='python3 -c "import sys,yaml,json; yaml.dump(     json.load(sys.stdin),sys.stdout,indent=2,sort_keys=False)"'

# sum size values with units from stdin
# usage: sum [unit|1]
#        show sum value without unit if given
#        otherwise show with auto iec-i unit
#  e.g.: sum Gi <<< "250Mi 50Gi 1.5Ti 1024"
sum() {
  _reqcmds numfmt || return

  local total size sizes=(`cat`)
  local u1 u2 unit usys args

  for size in ${sizes[@]}; do
    # separate value and unit
    [[ $size =~ ^([-0-9.]+)([A-Za-z]*)$ ]]
    size=${BASH_REMATCH[1]}
    unit=${BASH_REMATCH[2]}

    [ "$size" ] || continue
    if [ -z "$unit" ]; then
      total=$(bc <<< "0$total + 0$size")
      continue
    fi
    case ${unit,,} in
       k|m|g|t|p|e|1|'') usys=si    ;;
      ki|mi|gi|ti|pi|ei) usys=iec-i ;;
      *) echo >&2 "Invalid unit: $unit"
         return 1
    esac
    u1=${unit:0:1} u2=${unit:1:1} unit=${u1^^}${u2,,}
    args=(--from $usys --to-unit 1 $size$unit)
    total=$(bc <<< "0$total + 0$(numfmt ${args[@]})")
  done

  if [ "$1" ]; then
    # show value only in specified unit
    u1=${1:0:1} u2=${1:1:1} unit=${u1^^}${u2,,}
    args=(--to-unit $unit)
  else
    # show size and unit based on value
    args=(--to iec-i)
  fi
  numfmt ${args[@]} --round nearest $total
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
    local metric=$1 stype=$2
    local period=$((60*60*24*2))
    local utnow=$(date +%s)

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
    local  label number units format suffix
    read   label number units format suffix <<< "$@"
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

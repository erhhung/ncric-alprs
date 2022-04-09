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

alias yi='sudo yum install'
alias yu='sudo yum update -y'

alias l='less'
alias mbs='most +10000 /bootstrap.log'

alias myip='printf " local: %s\npublic: %s\n" \
         "$(_instmeta local-ipv4)" \
         "$(_instmeta public-ipv4 || echo none)"'
alias myid='_instmeta instance-id'
alias myaz='_instmeta placement/availability-zone'
alias mytype='_instmeta instance-type'
alias myhost='_instmeta local-hostname'

# my instance metadata
# _instmeta <rel_path>
_instmeta() {
  local value=$(curl -s "http://169.254.169.254/latest/meta-data/$1")
  [[ "$value" =~ "404 - Not Found" ]] && return 1 || echo "$value"
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
listening() {
  netstat -ant | grep LISTEN | grep -E 'tcp4?' | sort -V
}
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

jql() {
  _jql() { jq -C . | less -R; }
  (($#)) && (cat "$@" | _jql) || _jql
}

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

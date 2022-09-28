#!/usr/bin/env bash

# generate custom CloudWatch Dashboard configuration for
# the 7 AstroMetrics hosts; outputs JSON for Terraform's
# "external" data source
#
# usage: dashboard.sh <env> <region>

   ENV=$1 # dev|prod
REGION=$2 # us-west-2|us-gov-west-1

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds yq jq || exit $?

_altcmd() {
  local cmd
  for cmd in "$@"; do
    if hash $cmd 2> /dev/null; then
      printf $cmd && return
    fi
  done
  return 1
}
# use yq v4 syntax
yq=$(_altcmd yq4 yq)

# dashboard body structure:
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/CloudWatch-Dashboard-Body-Structure.html

add_header() {
  cat <<EOT
# define common config for widgets to be referenced
# using YAML anchors and purged from the final JSON
templates:
  metric_widget: &metric_widget
    type: metric
    height: 3
    x: 0
  metric_props: &metric_props
    view: singleValue
    stat: Average
    period: 300
    stacked: false
    sparkline: true
    region: $REGION

# show metrics from the past 3 hours by default
start: PT3H
periodOverride: auto
widgets:
EOT
}

#  <host> <title> <metric> [metric]...
#   host: postgresql|elasticsearch|conductor|datastore|indexer|bastion|worker
#  title: display name of host
# metric: user_cpu|memory|root_disk|data_disk
add_widget() {
  local host=$1 title=$2 width=6 fstype
  shift 2

  ((width *= $#)) # add 6 per metric shown
  ((y     += 3))  # add 3 per widget shown

  cat <<EOT
  - <<: *metric_widget
    width: $width
    y: $y
    properties:
      <<: *metric_props
      title: $title
      metrics:
EOT
  while [ "$1" ]; do
    case  "$1" in
      user_cpu)
        cat <<EOT
        # https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/search-expression-syntax.html
        - - expression: >-
              SUM(SEARCH('
              Namespace=CWAgent
              MetricName=(
              cpu_usage_system OR
              cpu_usage_user OR
              cpu_usage_nice
              )
              host=alprs$ENV-$host
              cpu=cpu-total
              ', 'Average', 300))
            label: CPU Usage
EOT
        ;;
      memory)
        cat <<EOT
        - - CWAgent
          - mem_used_percent
          - host
          - alprs$ENV-$host
          - label: Memory Usage
EOT
        ;;
      root_disk)
        [ "$host" == bastion ] && fstype=xfs \
                               || fstype=ext4
        cat <<EOT
        - - CWAgent
          - disk_used_percent
          - host
          - alprs$ENV-$host
          - path
          - /
          - device
          - nvme0n1p1
          -  fstype
          - $fstype
          - label: Root Disk Usage
EOT
        ;;
      data_disk)
        cat <<EOT
        - - CWAgent
          - disk_used_percent
          - host
          - alprs$ENV-$host
          - path
          - /opt/$host
          - device
          - nvme1n1
          - fstype
          - xfs
          - label: Data Disk Usage
EOT
        ;;
      *)
        exit 1
        ;;
    esac
    shift
  done
}

# IMPORTANT! Metric dimensions specified here should
#            be synced with those in "cloudwatch.tf"
y=-3
{ add_header
  add_widget postgresql    PostgreSQL    user_cpu memory root_disk data_disk
  add_widget elasticsearch Elasticsearch user_cpu memory root_disk data_disk
  add_widget conductor     Conductor     user_cpu memory root_disk
  add_widget datastore     Datastore     user_cpu memory root_disk
  add_widget indexer       Indexer       user_cpu memory root_disk
  add_widget bastion      "Bastion Host" user_cpu memory root_disk
  add_widget worker        Worker        user_cpu memory root_disk
} \
  | "$yq" -o json \
  |   jq  '{"json": del(.templates) | tojson}'

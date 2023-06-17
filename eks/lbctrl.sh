#!/usr/bin/env bash

# download the latest AWS Load Balancer Controller
# IAM policy document from GitHub and output JSON
# for Terraform's "external" data source
# https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html

#   usage: lbctrl.sh <region> <github-token>
# example: lbctrl.sh us-west-2 github_pat_XX
#  output: {"json":"{...}"}

_reqcmds() {
  local cmd
  for cmd in "$@"; do
    if ! hash $cmd 2> /dev/null; then
      echo >&2 "Please install \"$cmd\" first!"
      return 1
    fi
  done
}
_reqcmds curl jq || exit $?

if [[ "$1" == us-gov-* ]]; then
  file="iam_policy_us-gov.json"
elif [ "$1" ]; then
  file="iam_policy.json"
else
  echo >&2 "Region required."
  exit 1
fi

if [[ "$2" != github_pat_* ]]; then
  echo >&2 "GitHub token required."
  exit 1
fi
GITHUB_TOKEN=$2

REPO="kubernetes-sigs/aws-load-balancer-controller"
version=$(curl -sH "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/$REPO/releases/latest | \
  jq -r .tag_name)
curl -s https://raw.githubusercontent.com/$REPO/$version/docs/install/$file | \
  jq -sR '{json:.}'

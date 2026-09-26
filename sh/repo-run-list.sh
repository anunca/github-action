#!/usr/bin/env bash
set -Eeuo pipefail

REPOS=$(gh repo list --json nameWithOwner --jq '.[].nameWithOwner')
STATUS=${STATUS:-}
[[ ! -z $STATUS ]] && STATUS="--status $STATUS"

for REPO in ${REPOS[@]}; do
  echo -e "\n$REPO"
  gh run list --repo "$REPO" --all $STATUS
done

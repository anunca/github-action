#!/usr/bin/env bash
set -Eeuo pipefail

gh repo list \
  --json nameWithOwner,defaultBranchRef \
  --jq '.[] | select(.defaultBranchRef != null) |
        [.nameWithOwner, .defaultBranchRef.name] | @tsv' |
while IFS=$'\t' read -r repo branch; do
  protected=$(gh api "repos/$repo/branches/$branch" --jq '.protected')
  printf '%-50s %-20s %s\n' "$repo" "$branch" "$protected"
done

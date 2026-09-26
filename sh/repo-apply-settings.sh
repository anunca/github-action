#!/usr/bin/env bash
set -Eeuo pipefail

preview() {
  printf '\n%s\n\n' "Preview private repository settings"

  {
    printf '%s\t%s\n' \
      "FULL NAME" \
      "VISIBILITY"

    gh api --paginate \
    "/user/repos?affiliation=owner&visibility=private&per_page=100" \
    --jq '.[] |
          select(.archived == false and .fork == false) |
          [.full_name, .visibility] |
          @tsv'
  } | column -t -s $'\t'
}

apply() {
  printf '\n%s\n' "Apply private repository settings"
  gh api --paginate \
  "/user/repos?affiliation=owner&visibility=private&per_page=100" \
  --jq '.[] |
        select(.archived == false and .fork == false) |
        .full_name' |
  while IFS= read -r repo; do
    echo "Updating $repo"

    if gh api --method PATCH "repos/$repo" \
      -F has_issues=false \
      -F has_discussions=false \
      -F has_wiki=false \
      -F has_projects=false \
      -F delete_branch_on_merge=true \
      --jq '"Updated \(.full_name)"'
    then
      :
    else
      echo "FAILED: $repo" >&2
    fi
  done
}

verify() {
  printf '\n%s\n\n' "Verify private repository settings"

  {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "REPOSITORY" \
      "ISSUES" \
      "DISCUSSIONS" \
      "WIKI" \
      "PROJECTS" \
      "DELETE_BRANCH"

    gh api --paginate \
      "/user/repos?affiliation=owner&visibility=private&per_page=100" \
      --jq '.[].full_name' |
    while IFS= read -r repo; do
      gh api "repos/$repo" \
        --jq '[
          .full_name,
          .has_issues,
          .has_discussions,
          .has_wiki,
          .has_projects,
          .delete_branch_on_merge
        ] | @tsv'
    done
  } | column -t -s $'\t'
}

preview
apply
verify

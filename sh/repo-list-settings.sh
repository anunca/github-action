#!/usr/bin/env bash
set -Eeuo pipefail

gh_api_visibility() {
  printf '\n%s\n\n' "Preview repository visibility"

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

gh_api_repo() {
  printf '\n%s\n' $repo
  gh api "repos/$repo" --jq '{
    repository: .full_name,
    visibility,
    default_branch,
    archived,
    issues: .has_issues,
    projects: .has_projects,
    wiki: .has_wiki,
    discussions: .has_discussions,
    merge_commit: .allow_merge_commit,
    squash_merge: .allow_squash_merge,
    rebase_merge: .allow_rebase_merge,
    auto_merge: .allow_auto_merge,
    delete_branch_on_merge,
    security: .security_and_analysis
  }'
}

gh_api_repo_actions_permissions() {
  printf '\n%s\n' "$repo 'Actions permissions'"
  gh api "repos/$repo/actions/permissions"
}

gh_api_repo_actions_permissions_workflow() {
  printf '\n%s\n' "$repo 'Default GITHUB_TOKEN permissions'"
  gh api "repos/$repo/actions/permissions/workflow"
}

gh_api_repo_rulesets() {
  printf '\n%s\n' "$repo 'Repository rulesets'"
  # gh api "repos/$repo/rulesets"
}

gh_api_repo_default_branche() {
  printf '\n%s\n' "$repo 'Default-branch protection'"
  branch=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
  gh api "repos/$repo/branches/$branch" \
    --jq '{branch: .name, protected: .protected}'
}

gh_api_repo_environments() {
  printf '\n%s\n' "$repo 'Environments'"
  gh api "repos/$repo/environments"
}

gh_secret_list() {
  printf '\n%s\n' "$repo 'Actions secrets—names only'"
  gh secret list --repo "$repo"
}

gh_variable_list() {
  printf '\n%s\n' "'$repo Actions variables'"
  gh variable list --repo "$repo"
}

gh_api_visibility

limit=100
# Get all repositories not archived and no fork (source)
repos=$(gh repo list \
  --no-archived \
  --source \
  --visibility private \
  --limit $limit \
  --json nameWithOwner \
  --jq '.[].nameWithOwner')

for repo in ${repos[@]}; do
  gh_api_repo
  gh_api_repo_actions_permissions
  gh_api_repo_actions_permissions_workflow
  gh_api_repo_rulesets
  gh_api_repo_default_branche
  gh_api_repo_environments
  gh_secret_list
  gh_variable_list
done

#!/usr/bin/env bash
set -Eeuo pipefail

owner="${OWNER:?OWNER is required}"
scope="${RESOURCE_SCOPE:-all}"
retention_days="${RETENTION_DAYS:-1}"
dry_run="${DRY_RUN:-true}"
include_archived="${INCLUDE_ARCHIVED:-false}"
exclusions="${EXCLUDED_REPOSITORIES:-}"
summary_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

case "$scope" in
  all|workflow-runs|run-logs|artifacts|caches) ;;
  *) echo "Invalid RESOURCE_SCOPE: $scope" >&2; exit 2 ;;
esac

if ! [[ "$retention_days" =~ ^[1-9][0-9]*$ ]]; then
  echo "RETENTION_DAYS must be a positive whole number." >&2
  exit 2
fi

case "$dry_run" in true|false) ;; *) echo "DRY_RUN must be true or false." >&2; exit 2 ;; esac
case "$include_archived" in true|false) ;; *) echo "INCLUDE_ARCHIVED must be true or false." >&2; exit 2 ;; esac

lowercase() {
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

if date -u -d "1 day ago" +%s >/dev/null 2>&1; then
  date_flavor="gnu"
elif date -u -v-1d +%s >/dev/null 2>&1; then
  date_flavor="bsd"
else
  echo "A compatible GNU or BSD date command is required." >&2
  exit 2
fi

days_ago_epoch() {
  if [[ "$date_flavor" == "gnu" ]]; then
    date -u -d "$1 days ago" +%s
  else
    date -u -v-"$1"d +%s
  fi
}

epoch_to_iso() {
  if [[ "$date_flavor" == "gnu" ]]; then
    date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
  fi
}

timestamp_to_epoch() {
  if [[ "$date_flavor" == "gnu" ]]; then
    date -u -d "$1" +%s
  else
    date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s
  fi
}

authenticated_owner="$(gh api user --jq .login)"
if [[ "$(lowercase "$authenticated_owner")" != "$(lowercase "$owner")" ]]; then
  echo "ACTIONS_ADMIN_TOKEN belongs to '$authenticated_owner', but repository owner is '$owner'." >&2
  exit 3
fi

cutoff_epoch="$(days_ago_epoch "$retention_days")"
cutoff_iso="$(epoch_to_iso "$cutoff_epoch")"
repo_file="$(mktemp)"
trap 'rm -f "$repo_file"' EXIT

is_excluded() {
  local full_name="$1" short_name="${1#*/}" item item_lower
  local full_name_lower short_name_lower
  [[ -n "$exclusions" ]] || return 1
  full_name_lower="$(lowercase "$full_name")"
  short_name_lower="$(lowercase "$short_name")"
  IFS=',' read -ra excluded_items <<< "$exclusions"
  for item in "${excluded_items[@]}"; do
    item="${item#${item%%[![:space:]]*}}"
    item="${item%${item##*[![:space:]]}}"
    item_lower="$(lowercase "$item")"
    if [[ -n "$item" && ( "$item_lower" == "$full_name_lower" || "$item_lower" == "$short_name_lower" ) ]]; then
      return 0
    fi
  done
  return 1
}

older_than_cutoff() {
  local timestamp="$1" timestamp_epoch
  [[ -n "$timestamp" ]] || return 1
  timestamp_epoch="$(timestamp_to_epoch "$timestamp")"
  (( timestamp_epoch < cutoff_epoch ))
}

delete_endpoint() {
  local endpoint="$1" label="$2"
  if [[ "$dry_run" == "true" ]]; then
    echo "DRY RUN: would delete $label"
  else
    gh api --method DELETE "$endpoint" >/dev/null
    echo "Deleted $label"
  fi
}

api_count() {
  local endpoint="$1" field="$2"
  gh api "$endpoint" --jq ".$field"
}

echo "Finding repositories owned by $owner ..."
gh api --paginate "/user/repos?affiliation=owner&per_page=100&sort=full_name" \
  --jq '.[] | [.full_name, .archived] | @tsv' > "$repo_file"

if [[ ! -s "$repo_file" ]]; then
  echo "::error::No repositories were discovered for '$owner'." >&2
  echo "Verify that ACTIONS_ADMIN_TOKEN can access repositories owned by '$owner' and has the required repository permissions." >&2
  exit 4
fi

printf '# GitHub Actions cleanup\n\n' >> "$summary_file"
printf -- '- Owner: `%s`\n- Resource selection: `%s`\n- Cutoff: `%s`\n- Dry run: `%s`\n\n' \
  "$owner" "$scope" "$cutoff_iso" "$dry_run" >> "$summary_file"
printf '| Repository | Workflows | Runs | Artifacts | Caches | Deleted/matched |\n' >> "$summary_file"
printf '|---|---:|---:|---:|---:|---:|\n' >> "$summary_file"

repositories_scanned=0
repositories_with_actions=0
repositories_skipped=0
total_matched=0

while IFS=$'\t' read -r repo archived; do
  [[ -n "$repo" ]] || continue

  if is_excluded "$repo"; then
    echo "Skipping excluded repository: $repo"
    ((repositories_skipped += 1))
    continue
  fi
  if [[ "$archived" == "true" && "$include_archived" != "true" ]]; then
    echo "Skipping archived repository: $repo"
    ((repositories_skipped += 1))
    continue
  fi

  ((repositories_scanned += 1))
  workflows="$(api_count "repos/$repo/actions/workflows?per_page=1" total_count)"
  runs="$(api_count "repos/$repo/actions/runs?per_page=1" total_count)"
  artifacts="$(api_count "repos/$repo/actions/artifacts?per_page=1" total_count)"
  caches="$(api_count "repos/$repo/actions/caches?per_page=1" total_count)"

  if (( workflows == 0 && runs == 0 && artifacts == 0 && caches == 0 )); then
    continue
  fi

  ((repositories_with_actions += 1))
  repo_matched=0
  echo "Processing $repo (workflows=$workflows runs=$runs artifacts=$artifacts caches=$caches)"

  if [[ "$scope" == "all" || "$scope" == "artifacts" ]]; then
    records="$(gh api --paginate "repos/$repo/actions/artifacts?per_page=100" \
      --jq '.artifacts[] | [.id, .created_at, .name] | @tsv')"
    while IFS=$'\t' read -r id created name; do
      [[ -n "$id" ]] || continue
      if older_than_cutoff "$created"; then
        delete_endpoint "repos/$repo/actions/artifacts/$id" "artifact '$name' ($id) from $repo"
        ((repo_matched += 1))
      fi
    done <<< "$records"
  fi

  if [[ "$scope" == "all" || "$scope" == "caches" ]]; then
    records="$(gh api --paginate "repos/$repo/actions/caches?per_page=100" \
      --jq '.actions_caches[] | [.id, .last_accessed_at, .key, .ref] | @tsv')"
    while IFS=$'\t' read -r id last_accessed key ref; do
      [[ -n "$id" ]] || continue
      if older_than_cutoff "$last_accessed"; then
        delete_endpoint "repos/$repo/actions/caches/$id" "cache '$key' ($id, $ref) from $repo"
        ((repo_matched += 1))
      fi
    done <<< "$records"
  fi

  if [[ "$scope" == "run-logs" ]]; then
    records="$(gh api --paginate "repos/$repo/actions/runs?per_page=100&status=completed" \
      --jq '.workflow_runs[] | [.id, .created_at, .status, .name] | @tsv')"
    while IFS=$'\t' read -r id created status name; do
      [[ -n "$id" ]] || continue
      if [[ "$status" == "completed" ]] && older_than_cutoff "$created"; then
        delete_endpoint "repos/$repo/actions/runs/$id/logs" "logs for run '$name' ($id) from $repo"
        ((repo_matched += 1))
      fi
    done <<< "$records"
  fi

  if [[ "$scope" == "all" || "$scope" == "workflow-runs" ]]; then
    records="$(gh api --paginate "repos/$repo/actions/runs?per_page=100&status=completed" \
      --jq '.workflow_runs[] | [.id, .created_at, .status, .name] | @tsv')"
    while IFS=$'\t' read -r id created status name; do
      [[ -n "$id" ]] || continue
      if [[ "$status" == "completed" ]] && older_than_cutoff "$created"; then
        delete_endpoint "repos/$repo/actions/runs/$id" "workflow run '$name' ($id) from $repo"
        ((repo_matched += 1))
      fi
    done <<< "$records"
  fi

  total_matched=$((total_matched + repo_matched))
  printf '| `%s` | %s | %s | %s | %s | %s |\n' \
    "$repo" "$workflows" "$runs" "$artifacts" "$caches" "$repo_matched" >> "$summary_file"
done < "$repo_file"

printf '\n## Totals\n\n' >> "$summary_file"
printf -- '- Repositories scanned: **%s**\n- Repositories with Actions resources: **%s**\n- Repositories skipped: **%s**\n- Resources deleted/matched: **%s**\n' \
  "$repositories_scanned" "$repositories_with_actions" "$repositories_skipped" "$total_matched" >> "$summary_file"

echo "Done: $repositories_with_actions repositories with Actions; $total_matched resources matched."

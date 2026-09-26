#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cp "$repository_root/test/bin/gh" "$test_dir/gh"
chmod +x "$test_dir/gh"

run_case() {
  local scope="$1" expected="$2" summary_file
  summary_file="$(mktemp)"

  PATH="$test_dir:$PATH" \
  OWNER="anunca" \
  RESOURCE_SCOPE="$scope" \
  RETENTION_DAYS="1" \
  DRY_RUN="true" \
  INCLUDE_ARCHIVED="false" \
  EXCLUDED_REPOSITORIES="" \
  GITHUB_STEP_SUMMARY="$summary_file" \
    bash "$repository_root/sh/cleanup-actions.sh"

  grep -q 'Repositories scanned: \*\*3\*\*' "$summary_file"
  grep -q 'Repositories with Actions resources: \*\*2\*\*' "$summary_file"
  grep -q "Resources deleted/matched: \*\*$expected\*\*" "$summary_file"
  grep -q "| \`anunca/with-actions\` | 1 | 2 | 2 | 2 | $expected |" "$summary_file"
  rm -f "$summary_file"
}

run_case all 3
run_case workflow-runs 1
run_case run-logs 1
run_case artifacts 1
run_case caches 1

echo "All cleanup resource-scope fixtures passed."

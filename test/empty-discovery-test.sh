#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup_script="$repo_root/sh/cleanup-actions.sh"

bash -n "$cleanup_script"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"
cat > "$test_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$*" == "api user --jq .login" ]]; then
  printf '%s\n' "${OWNER:-anunca}"
  exit 0
fi

if [[ "$1" == "api" && "$2" == "--paginate" && "$3" == "/user/repos?affiliation=owner&per_page=100&sort=full_name" ]]; then
  exit 0
fi

echo "Unexpected gh invocation: $*" >&2
exit 99
MOCK
chmod +x "$test_dir/bin/gh"

set +e
output="$(
  PATH="$test_dir/bin:$PATH" \
  OWNER=anunca \
  RESOURCE_SCOPE=all \
  RETENTION_DAYS=1 \
  DRY_RUN=true \
  INCLUDE_ARCHIVED=false \
  EXCLUDED_REPOSITORIES= \
  GITHUB_STEP_SUMMARY="$test_dir/summary.md" \
  bash "$cleanup_script" 2>&1
)"
status=$?
set -e

if [[ "$status" -ne 4 ]]; then
  echo "Expected exit status 4 for empty repository discovery, got $status." >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if [[ "$output" != *"No repositories were discovered for 'anunca'."* ]]; then
  echo "Expected the empty-discovery error message." >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "All cleanup smoke tests passed."

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKFLOW="$ROOT_DIR/.github/workflows/release-pr.yml"

assert_exactly_one() {
  local expected=$1
  local count
  count=$(sed 's/^[[:space:]]*//' "$WORKFLOW" | grep -Fxc "$expected" || true)
  if [[ $count -ne 1 ]]; then
    echo "expected exactly one '$expected' step in $WORKFLOW, found $count" >&2
    exit 1
  fi
}

assert_ordered() {
  local before=$1
  local after=$2
  local before_line after_line

  before_line=$(awk -v pat="$before" '{ sub(/^[ \t]+/, ""); if ($0 == pat) { print NR; exit } }' "$WORKFLOW")
  after_line=$(awk -v pat="$after" '{ sub(/^[ \t]+/, ""); if ($0 == pat) { print NR; exit } }' "$WORKFLOW")

  if [[ -z "$before_line" || -z "$after_line" ]]; then
    echo "ordering check failed: could not find line matching '$before' or '$after' in $WORKFLOW" >&2
    exit 1
  fi
  if [[ "$before_line" -ge "$after_line" ]]; then
    echo "expected '$before' (line $before_line) to appear before '$after' (line $after_line) in $WORKFLOW" >&2
    exit 1
  fi
}

assert_exactly_one 'run: bash scripts/test_release_workflow.sh'
assert_exactly_one 'run: bash scripts/test_sync_release_version.sh'
assert_exactly_one 'run: bash scripts/test_validate_release_metadata.sh'

assert_exactly_one 'run: bash scripts/validate_release_metadata.sh'

assert_ordered 'run: bash scripts/test_release_workflow.sh' 'run: bash scripts/validate_release_metadata.sh'
assert_ordered 'run: bash scripts/test_sync_release_version.sh' 'run: bash scripts/validate_release_metadata.sh'
assert_ordered 'run: bash scripts/test_validate_release_metadata.sh' 'run: bash scripts/validate_release_metadata.sh'

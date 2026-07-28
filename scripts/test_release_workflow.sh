#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKFLOW="$ROOT_DIR/.github/workflows/release-pr.yml"

assert_exactly_one() {
  local expected=$1
  local count
  count=$(grep -Fc "$expected" "$WORKFLOW" || true)
  if [[ $count -ne 1 ]]; then
    echo "expected exactly one '$expected' step in $WORKFLOW, found $count" >&2
    exit 1
  fi
}

assert_exactly_one 'run: bash scripts/test_release_workflow.sh'
assert_exactly_one 'run: bash scripts/test_sync_release_version.sh'
assert_exactly_one 'run: bash scripts/test_validate_release_metadata.sh'

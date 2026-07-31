#!/usr/bin/env bash

set -euo pipefail

repo="$GITHUB_REPOSITORY"
prior_run_id="$(gh api \
  --method GET \
  "repos/$repo/actions/workflows/test262.yml/runs?branch=main&status=success&per_page=20" \
  --jq '[.workflow_runs[] | select((.id | tostring) != env.CURRENT_RUN_ID)][0].id')"
if [[ -z "$prior_run_id" || "$prior_run_id" == "null" ]]; then
  echo "::error title=Test262 baseline unavailable::no successful main run was found"
  exit 1
fi

baseline_dir="$(mktemp -d)"
trap 'rm -rf "$baseline_dir"' EXIT
if ! gh run download "$prior_run_id" \
  --repo "$repo" \
  --name test262-combined-report \
  --dir "$baseline_dir"
then
  echo "::error title=Test262 baseline unavailable::could not download combined report from main run $prior_run_id"
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for mode in strict non-strict; do
  baseline="$baseline_dir/test262-$mode-results.json"
  candidate="test262-$mode-results.json"
  if [[ ! -f "$baseline" || ! -f "$candidate" ]]; then
    echo "::error title=Test262 comparison incomplete::missing $mode baseline or candidate artifact"
    failed=1
    continue
  fi
  node "$script_dir/test262_failing_diff.js" "$baseline" "$candidate" || failed=1
done

if [[ "$failed" -ne 0 ]]; then
  echo "::error title=Test262 per-test regression::baseline comparison failed"
  exit 1
fi

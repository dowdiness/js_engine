#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact_dir="$script_dir/artifacts"
viewer_mode="${1:-interactive}"
credential_canary='p1-fake-credential-canary-do-not-leak'

if [[ "$viewer_mode" != "interactive" && "$viewer_mode" != "--scripted-viewer" ]]; then
  echo "usage: $0 [--scripted-viewer]" >&2
  exit 2
fi

if command -v moon >/dev/null 2>&1; then
  moon_bin="$(command -v moon)"
elif [[ -x /home/antisatori/.moon/bin/moon ]]; then
  moon_bin=/home/antisatori/.moon/bin/moon
else
  echo "moon executable not found" >&2
  exit 1
fi

mkdir -p "$artifact_dir"

echo "PROTOTYPE: checking pure ToolBroker probe and native viewer"
(
  cd "$script_dir"
  "$moon_bin" check cmd/probe --target native --deny-warn
  "$moon_bin" check cmd/viewer --target native --deny-warn
  "$moon_bin" test . --target native --deny-warn
)

echo "PROTOTYPE: running deterministic native ToolBroker probe"
(
  cd "$script_dir"
  "$moon_bin" run cmd/probe --target native --quiet
) > "$artifact_dir/transitions.jsonl"

transition_count="$(wc -l < "$artifact_dir/transitions.jsonl")"
scenario_count="$({
  sed -n 's/.*"scenario":"\([^"]*\)".*/\1/p' \
    "$artifact_dir/transitions.jsonl"
} | LC_ALL=C sort -u | wc -l)"

if [[ "$transition_count" -ne 97 ]]; then
  echo "PROTOTYPE: expected 97 transitions, observed $transition_count" >&2
  exit 1
fi
if [[ "$scenario_count" -ne 19 ]]; then
  echo "PROTOTYPE: expected 19 scenarios, observed $scenario_count" >&2
  exit 1
fi
if grep -Fq "$credential_canary" "$artifact_dir/transitions.jsonl"; then
  echo "PROTOTYPE: credential canary leaked into transitions.jsonl" >&2
  exit 1
fi

printf '%s\n' \
  'schema=agent-runtime-p1-transcript/v1' \
  "scenarios=$scenario_count" \
  "transitions=$transition_count" \
  'scenario_assertions=passed' \
  'credential_canary_occurrences=0' \
  'target=native' \
  > "$artifact_dir/probe-summary.txt"

echo "PROTOTYPE: launching native authority/cancellation viewer"
if [[ "$viewer_mode" == "--scripted-viewer" ]]; then
  printf '%s\n' \
    inject-authority \
    validate-injection \
    prepare-rejection \
    deliver-rejection \
    start-cancel-scenario \
    submit-write \
    validate-write \
    approve-write \
    cancel-before-dispatch \
    late-dispatch \
    resubmit-after-cancel \
    quit \
    | (cd "$script_dir" && "$moon_bin" run cmd/viewer --target native --quiet) \
    | tee "$artifact_dir/human-walkthrough.txt"
else
  (cd "$script_dir" && "$moon_bin" run cmd/viewer --target native --quiet) \
    | tee "$artifact_dir/human-walkthrough.txt"
fi

if grep -Fq "$credential_canary" \
  "$artifact_dir/transitions.jsonl" \
  "$artifact_dir/human-walkthrough.txt"; then
  echo "PROTOTYPE: credential canary leaked into a published artifact" >&2
  exit 1
fi

(
  cd "$artifact_dir"
  sha256sum transitions.jsonl human-walkthrough.txt probe-summary.txt \
    > artifact-sha256.txt
)

echo "PROTOTYPE: 19/19 scenarios and 97/97 transitions passed"
echo "PROTOTYPE: credential canary occurrences in artifacts: 0"

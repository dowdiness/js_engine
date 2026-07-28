#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact_dir="$script_dir/artifacts"
viewer_mode="${1:-interactive}"

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
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "PROTOTYPE: checking pure reducer, stable-facade harness, and native viewers"
(
  cd "$script_dir"
  "$moon_bin" check core --target native --deny-warn
  "$moon_bin" check . --target native --deny-warn
  "$moon_bin" check cmd/probe --target native --deny-warn
  "$moon_bin" check cmd/event_log --target native --deny-warn
  "$moon_bin" check cmd/viewer --target native --deny-warn
  "$moon_bin" test . --target native --deny-warn
)

echo "PROTOTYPE: running deterministic native event replay matrix twice"
(
  cd "$script_dir"
  "$moon_bin" run cmd/probe --target native --quiet
) > "$artifact_dir/actions.jsonl"
(
  cd "$script_dir"
  "$moon_bin" run cmd/probe --target native --quiet
) > "$tmp_dir/actions-second.jsonl"
cmp "$artifact_dir/actions.jsonl" "$tmp_dir/actions-second.jsonl"

(
  cd "$script_dir"
  "$moon_bin" run cmd/event_log --target native --quiet
) > "$artifact_dir/required-events.jsonl"

python3 - "$artifact_dir/actions.jsonl" "$artifact_dir/required-events.jsonl" \
  > "$artifact_dir/probe-summary.txt" <<'PY'
import json
import sys

actions_path, events_path = sys.argv[1:]
with open(actions_path, encoding="utf-8") as handle:
    rows = [json.loads(line) for line in handle if line.strip()]
with open(events_path, encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]

assert len(rows) == 47, len(rows)
assert len(events) == 9, len(events)
assert [event["sequence"] for event in events] == list(range(1, 10))

def row(scenario, action):
    matches = [r for r in rows if r.get("scenario") == scenario and r.get("action") == action]
    assert len(matches) == 1, (scenario, action, len(matches))
    return matches[0]

approval = row("post_write_result_crash", "replay_approval_wait")
assert approval["replay_state"]["phase"] == "WaitingApproval"
assert approval["replay_state"]["approval_status"] == "pending"
assert approval["adapter_state"]["fake_external_write_commits"] == 0

required = row("post_write_result_crash", "replay")
assert required["replay_state"]["phase"] == "Completed"
assert required["replay_state"]["completion"] == {
    "status": "ok",
    "output": {"user_id": "user-1", "status": "active", "updated": True},
}
assert required["adapter_state"]["fake_external_write_commits"] == 1
assert required["adapter_state"]["replay_adapter_invocations"] == 0

repeat = row("post_write_result_crash", "replay_completed_again")
assert repeat["event_count"] == 9
assert repeat["replay_cursor"] == 9
assert repeat["adapter_state"]["fake_external_write_commits"] == 1
assert repeat["adapter_state"]["replay_adapter_invocations"] == 0

cancelled = row("cancelled_session_recovery", "replay_cancelled")
assert cancelled["replay_state"]["phase"] == "Cancelled"
assert cancelled["adapter_state"]["fake_external_write_commits"] == 0

unknown = row("commit_before_result_boundary", "replay_outcome_unknown")
assert unknown["replay_state"]["phase"] == "AwaitingToolResult"
assert unknown["adapter_state"]["fake_external_write_commits"] == 1
assert unknown["adapter_state"]["replay_adapter_invocations"] == 0

reconciled = row("commit_before_result_boundary", "reconcile_unknown_outcome")
assert reconciled["adapter_state"]["write_attempts"] == 2
assert reconciled["adapter_state"]["fake_external_write_commits"] == 1
assert reconciled["adapter_state"]["idempotency_cache_hits"] == 1

for scenario in (
    "source_hash_mismatch",
    "runtime_fingerprint_mismatch",
    "host_config_mismatch",
    "input_mismatch",
):
    rejected = row(scenario, "replay")
    assert rejected["last_replay_engine_started"] is False
    assert rejected["replay_cursor"] == 0
    assert rejected["adapter_state"]["adapter_attempts"] == 0

divergence = row("request_sequence_divergence", "replay")
assert divergence["outcome"] == "replay_rejected:request_payload_mismatch"
assert divergence["replay_cursor"] == 4
assert divergence["adapter_state"]["adapter_attempts"] == 0

summary = row("summary", "verdict")
assert summary["verdict"] == "GO"
assert summary["action_rows"] == 46
assert summary["jsonl_rows_including_summary"] == 47

print("schema=agent-runtime-p3-probe-summary/v1")
print("target=native")
print(f"action_rows={len(rows) - 1}")
print("summary_rows=1")
print(f"jsonl_rows={len(rows)}")
print(f"required_domain_events={len(events)}")
print("rejected_replay_cases=7")
print("required_fake_external_write_commits=1")
print("required_replay_adapter_invocations=0")
print("unknown_outcome_automatic_adapter_invocations=0")
print("unknown_outcome_same_key_reconciliation_write_commits=1")
print("deterministic_repeat=byte_identical")
print("verdict=GO")
print("scope=Engine crash only; host in-memory log and fake idempotency registry survive")
PY

printf '%s\n' \
  'controlled=fixed source,input,results,session ID,request order,synchronous generator,native target' \
  'not_used=time,random,locale,environment UUID,provider,network,concurrency,timers,microtasks' \
  'not_measured=tagged error-result replay,host process crash,durable append,fsync,torn log,adapter retention expiry,client delivery acknowledgement' \
  'drift_rejected=source SHA-256,runtime fingerprint,host config SHA-256,input,request payload,event sequence,result identity' \
  'boundary=commit-before-result needs explicit same-key reconciliation against a surviving idempotency registry; otherwise PIVOT' \
  > "$artifact_dir/nondeterminism-and-boundaries.txt"

echo "PROTOTYPE: launching native terminal control viewer"
if [[ "$viewer_mode" == "--scripted-viewer" ]]; then
  printf '%s\n' \
    start dispatch return-result crash replay approve dispatch crash replay \
    reset start dispatch return-result cancel crash replay \
    reset start dispatch return-result approve dispatch-without-result crash replay reconcile crash replay \
    quit \
    | (cd "$script_dir" && "$moon_bin" run cmd/viewer --target native --quiet) \
    > "$artifact_dir/human-walkthrough.txt"
else
  (cd "$script_dir" && "$moon_bin" run cmd/viewer --target native --quiet) \
    | tee "$artifact_dir/human-walkthrough.txt"
fi

(
  cd "$artifact_dir"
  sha256sum \
    actions.jsonl \
    required-events.jsonl \
    probe-summary.txt \
    nondeterminism-and-boundaries.txt \
    human-walkthrough.txt \
    red-probe.txt \
    > artifact-sha256.txt
)

echo "PROTOTYPE: 46 action rows, 1 summary row, and 9 canonical events verified"
echo "PROTOTYPE: required crash replay kept write commits at 1 and replay adapter calls at 0"
echo "PROTOTYPE: repeated run was byte-identical"

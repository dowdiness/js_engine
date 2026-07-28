#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
workspace_dir=$(cd -- "$script_dir/.." && pwd)
moon_bin=${MOON_BIN:-moon}
outer_timeout_seconds=${P2_OUTER_TIMEOUT_SECONDS:-15}
build_dir="$workspace_dir/_build/native/debug/build/dowdiness/js_engine_agent_runtime_worker_supervisor"
worker_build_bin="$build_dir/cmd/worker/worker.exe"
probe_bin="$build_dir/cmd/probe/probe.exe"
run_dir=""
worker_bin=""

find_workers() {
  local pid command remainder
  while read -r pid command remainder; do
    if [[ -n "$worker_bin" && "$command" == "$worker_bin" ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(ps -eo pid=,args=)
}

assert_no_workers() {
  local pid
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    printf 'P2 cleanup failure: worker PID %s remains\n' "$pid" >&2
    return 1
  done < <(find_workers)
}

cleanup_workers() {
  local -a pids=()
  local pid attempt remaining
  while read -r pid; do
    [[ -n "$pid" ]] && pids+=("$pid")
  done < <(find_workers)
  ((${#pids[@]} == 0)) && return 0
  kill -KILL -- "${pids[@]}" 2>/dev/null || true
  for ((attempt = 0; attempt < 200; attempt++)); do
    remaining=0
    for pid in "${pids[@]}"; do
      [[ -e "/proc/$pid" ]] && remaining=1
    done
    ((remaining == 0)) && return 0
    sleep 0.01
  done
  printf 'P2 emergency cleanup could not confirm worker exit:' >&2
  for pid in "${pids[@]}"; do
    [[ -e "/proc/$pid" ]] && printf ' %s' "$pid" >&2
  done
  printf '\n' >&2
  return 1
}

cleanup() {
  local original_status=$?
  local worker_status file_status
  trap - EXIT INT TERM
  set +e
  cleanup_workers
  worker_status=$?
  if [[ -n "$worker_bin" && -f "$worker_bin" ]]; then
    rm -f -- "$worker_bin"
  fi
  if [[ -n "$run_dir" && -d "$run_dir" ]]; then
    rmdir -- "$run_dir"
  fi
  file_status=$?
  if ((original_status != 0)); then
    exit "$original_status"
  fi
  if ((worker_status != 0 || file_status != 0)); then
    exit 1
  fi
  exit 0
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! "$outer_timeout_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  printf 'P2 outer timeout must be a numeric duration in seconds\n' >&2
  exit 2
fi

cd -- "$script_dir"
"$moon_bin" build cmd/worker --target native
"$moon_bin" build cmd/probe --target native
run_dir=$(mktemp -d /tmp/js-engine-p2-worker.XXXXXXXX)
worker_bin="$run_dir/worker.exe"
cp -- "$worker_build_bin" "$worker_bin"
timeout --kill-after=2s "${outer_timeout_seconds}s" "$probe_bin" "$worker_bin"
assert_no_workers

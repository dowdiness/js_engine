# PROTOTYPE: Killable native worker supervisor

## Verdict

**GO for native Linux/WSL killability and restartability of one fixed direct
worker.** The 2026-07-29 run completed 14/14 attempts, reaped every worker,
ended with zero active children, and started a healthy fresh worker directly
after each of six failure classes. A separate intentionally interrupted run
also recorded protected emergency reap and left no worker behind.

This is not a hostile-code sandbox, a production IPC protocol, or production
Agent Runtime code. It must stay off `main`.

## Question

Can a native supervisor keep control when a direct child running js_engine
completes normally, hangs in JavaScript, panics, emits excessive output, or
corrupts the prototype IPC stream? Can the same supervisor observe an abrupt
nonzero worker exit without first sending a signal and then restart?

## Working assumptions

1. Every non-terminating JavaScript program runs only in one direct child; the
   supervisor and test driver never evaluate it.
2. The fixed worker fixtures spawn no descendants. The supervisor redirects
   stdin from `/dev/null` and drains stdout and stderr concurrently.
3. A private native `waitpid(pid, WNOHANG)` adapter is the sole reaper. It is
   never mixed with `Process::wait` or `@process.wait_pid`.

The first prototype code edit was 2026-07-28 JST. The GO result was recorded on
2026-07-29 JST, before the 2026-07-30 two-working-day deadline.

## Fixed policy

- Worker deadline: 1,000 ms
- Combined stdout/stderr trigger: 1,048,576 bytes
- Kill-to-reap confirmation limit: 2,000 ms
- Post-reap pipe-drain limit: 500 ms
- Pipe reads: at most 4,096 raw bytes per read
- Process scope: one direct PID, no descendants
- Outer harness fail-safe: 15 seconds by default

The output policy triggers on byte 1,048,577. Data retained for the current IPC
line stays bounded by the 1 MiB policy plus one fixed read. Bytes already queued
in the kernel pipe are drained after SIGKILL and therefore can make the final
observed count exceed 1 MiB; the recorded run ended at 1,118,208 bytes. This is
an execution/output-storage guard, not a hard kernel-delivery quota.

## Design

`run.sh` builds a fixed worker and controller and executes the whole matrix with
one command. It copies the worker to a unique per-run path so concurrent runs
cannot target each other's cleanup scope. The controller:

1. spawns the worker executable directly with an empty inherited environment;
2. reads stdout and stderr in independent async tasks using bounded
   `read_some` calls;
3. validates exactly one newline-delimited UTF-8 JSON completion message;
4. records both attempt-relative and run-relative core monotonic time;
5. makes the first failure trigger sticky, requests SIGKILL once, and polls
   `waitpid(WNOHANG)` until the exact exit code or signal is observed and reaped;
6. installs a cancellation-protected, two-second kill/reap defer immediately
   after spawn, using the same sole reaper;
7. flushes each full-state JSONL event so an interrupted run retains its last
   observed cleanup state;
8. starts the next generation only after both pipe readers finish and active
   child count is zero.

The shell EXIT path is scoped to the unique worker executable for that run. It
sends SIGKILL only to matching leftovers, polls their exact PIDs for at most two
seconds, and removes the unique executable only after the PIDs disappear.

The pinned `moonbitlang/async@0.19.1` process path cannot distinguish a signal
from an exit code on Linux because it exposes `WEXITSTATUS` without the raw wait
status. The private adapter is therefore necessary evidence infrastructure for
this disposable native prototype.

The fixed MoonBit panic fixture emits `P2 fixed worker panic` and, in this
async-linked executable, does not terminate promptly by itself. The controller
recognizes that exact fixture diagnostic, requests SIGKILL, observes signal 9,
and reaps the child. This proves containment and restart for the fixed panic
fixture; it is not a general panic-classification protocol.

The separate `worker_abrupt_exit` fixture calls `_exit(86)`. The supervisor
observed exit 86 without requesting a signal, reaped it, and then completed a
fresh recovery worker. This is deliberately an abrupt nonzero-exit observation,
not a measured crash-by-signal claim.

## Reproduce

From the repository root, the required matrix is one command:

```bash
PATH=/home/antisatori/.moon/bin:$PATH integration/agent_runtime_prototype/worker_supervisor/run.sh > /tmp/agent-runtime-p2.jsonl
```

For scoped verification:

```bash
cd integration/agent_runtime_prototype/worker_supervisor
PATH=/home/antisatori/.moon/bin:$PATH moon check . --target native --deny-warn
PATH=/home/antisatori/.moon/bin:$PATH moon test . --target native
```

`run.sh` has a 15-second outer fail-safe. Its EXIT trap only targets the exact
per-run worker executable path, and a successful run additionally checks that no
such worker remains. After one normal build, the recorded fail-safe diagnostic
was reproduced with `MOON_BIN=/usr/bin/true P2_OUTER_TIMEOUT_SECONDS=0.2
./run.sh`; the override is test-only and the default remains 15 seconds.

## Recorded native/WSL result

Environment:

- Linux `6.6.114.1-microsoft-standard-WSL2` x86_64
- Moon `0.1.20260713`; moonc `v0.10.4+2cc641edf`
- Parent commit `9e8410b0a790154a1ebf193ceaa4b05ed5f9ec7e`
- Artifact: `artifacts/native-wsl-run.jsonl`
- SHA-256: `e9b03ddc98000b05266cb03f189b1b41ca55f6254762abcfe3fb2c2bc2c02792`

| Scenario | Classification | Terminal | Total bytes | Elapsed µs | Kill→reap µs |
|---|---|---:|---:|---:|---:|
| normal | normal_completion | exit 0 | 71 | 9,137 | — |
| infinite_js | deadline_exceeded | signal 9 | 0 | 1,007,801 | 5,115 |
| recovery_after_infinite_js | recovery_completion | exit 0 | 73 | 12,960 | — |
| worker_panic | worker_panic | signal 9 | 22 | 12,967 | 3,654 |
| recovery_after_worker_panic | recovery_completion | exit 0 | 73 | 18,194 | — |
| worker_abrupt_exit | abrupt_exit | exit 86 | 0 | 18,180 | — |
| recovery_after_worker_abrupt_exit | recovery_completion | exit 0 | 73 | 11,427 | — |
| oversized_output | output_limit_exceeded | signal 9 | 1,118,208 | 46,283 | 4,114 |
| recovery_after_oversized_output | recovery_completion | exit 0 | 73 | 13,473 | — |
| malformed_json | malformed_json | signal 9 | 17 | 10,686 | 4,903 |
| recovery_after_malformed_json | recovery_completion | exit 0 | 73 | 14,744 | — |
| pipe_close_mid_message | pipe_closed_mid_message | signal 9 | 17 | 16,966 | 4,601 |
| recovery_after_pipe_close | recovery_completion | exit 0 | 73 | 17,669 | — |
| near_deadline | near_deadline_completion | exit 0 | 78 | 814,049 | — |

All five requested-SIGKILL observations were below 6 ms, against the 2,000 ms
limit. The oversized-output trigger event records exactly 1,048,577 bytes; the
larger terminal total is drained pipe backlog. The near-deadline completion
message was observed at 810,516 µs. Every event has full worker/IO/kill/terminal
state plus attempt-relative and globally nondecreasing run-relative time. The
distinct summary schema records 14 attempts, six failure classes, six fresh
recoveries, and zero active children.

The intentionally interrupted diagnostic is
`artifacts/forced-stop-cleanup.jsonl` (SHA-256
`8a9a31f70183ef2649b8f6a00c40723d351bb1475828ec5b6c7b41e23a4c80a1`).
It exited with status 124 after six flushed records. Its last record is
`emergency_cleanup_completed`: the direct worker was reaped after external
SIGTERM won the race with the protected cleanup's SIGKILL request, and active
children became zero. No matching worker or per-run temp directory remained.
This is one of one intentional outer-timeout cleanup probes; it is separate
from the 14-attempt required matrix denominator.

## Boundary and future PIVOT conditions

The result establishes process killability, exact direct-child wait status,
bounded retained IPC data, and post-failure restart on native Linux/WSL. It does
not establish general process-group cleanup, descendant cleanup,
filesystem/network isolation, memory/CPU/syscall limits, arbitrary inherited-FD
closure, cross-platform behavior, or security against hostile code.

Cancellation during the `spawn_orphan` await itself occurs before the internal
defer can be registered; only the supported `run.sh` shell cleanup mitigates
that interval. Arbitrary embedding-time cancellation is unmeasured. The live
near-deadline worker completed normally at about 811 ms; the valid-exit versus
deadline-kill race branch is whitebox-tested, not an end-to-end race result.

PIVOT to an established external supervisor/container boundary if a product
stage requires descendants, a hard no-overshoot output quota, hostile inputs,
portable process isolation, or removal of the private native wait adapter. Any
unreaped PID, unexpected outer fail-safe activation during the required matrix,
or kill-to-reap time above two seconds remains a STOP result.

# Issue #695 URI timeout reproduction

`scripts/test262_uri_load_repro.js` is a measurement-only harness for the two
near-timeout Test262 cases reported by #689:

- `built-ins/encodeURI/S15.1.3.3_A2.3_T1.js`
- `built-ins/encodeURIComponent/S15.1.3.4_A2.3_T1.js`

It invokes the existing native `cmd/test262_runner` without changing runner
semantics. Every iteration executes the same four-task list (each URI case
twice) in strict and non-strict modes. The isolated condition passes
`--threads 1`; the load condition passes the CI-equivalent `--threads 4`.
Both conditions use the same release JS engine command and the unchanged
`--timeout 5` setting. A separate known non-terminating control is run in
each mode/condition and must produce a runner result with `status: "timeout"`
and process exit `0`.

Run from the repository root after building the release engine and native
runner:

```bash
moon build --target js --release cmd/main
moon build --target native cmd/test262_runner
node scripts/test262_uri_load_repro.js \
  --runner ./_build/native/debug/build/cmd/test262_runner/test262_runner.exe \
  --engine 'node _build/js/release/build/cmd/main/main.js' \
  --test262 ./test262 \
  --iterations 3 \
  --output docs/decisions/issue-695-uri-load-reproduction.json
```

The JSON artifact retains the per-test `duration_ms`, `status`, and `mode`,
the runner process exit/signal and outer-timeout state, the runner summary,
and the raw stdout/stderr for every invocation. `assessment` compares URI
timeout counts between conditions; it is evidence for #707, not a mitigation
decision. The committed result below was recorded from the #695 baseline
(`ae6172ffe1d385b8297198d2ad5947542b642c21`) with the repository's JS release
profile and the configured Test262 revision.

Recorded baseline outcome: all 24 URI tasks in each condition passed in both
modes, with zero URI timeouts. The four-worker per-test mean was 2,535.8 ms
versus 1,901.3 ms in isolation (1.3×), so load inflation was observed but the
reported timeout was not reproduced. All four mode/condition control runs
returned runner exit `0` while recording `status: "timeout"` at roughly 5 s.
This is evidence for the follow-up decision; it does not select a mitigation.

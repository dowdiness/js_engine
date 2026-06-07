///|
fn make_bench_csv(mean : Double, cv : Double) -> String {
  CSV_HEADER_TEXT +
  "\n" +
  "isolate/bytecode/property_get,component,execution,3,15,3," +
  format_fixed(mean, 1) +
  ",1,2,0," +
  format_fixed(cv, 1) +
  ",false\n"
}

///|
test "bench focus parses CSV after prelude output" {
  let csv_text = csv_text_from_stdout(
    "warning before csv\n" + make_bench_csv(34.0, 2.0),
  )
  let rows = parse_rows(csv_text)
  inspect(rows["isolate/bytecode/property_get"]["mean_ms"], content="34.0")
}

///|
test "bench focus shlex handles quoted command strings" {
  json_inspect(shlex_split("sh -c \"printf 'hi there'\""), content=[
    "sh", "-c", "printf 'hi there'",
  ])
}

///|
test "bench focus summarizes medians and missing rows" {
  let rows_by_run = [
    parse_rows(make_bench_csv(34.0, 2.0)),
    parse_rows(make_bench_csv(36.0, 3.0)),
    parse_rows(make_bench_csv(35.0, 1.0)),
  ]
  let summary = summarize_row("isolate/bytecode/property_get", rows_by_run)
  inspect(summary.runs, content="3")
  inspect(summary.median_ms, content="35")
  inspect(summary.mean_ms, content="35")
  inspect(summary.min_ms, content="34")
  inspect(summary.max_ms, content="36")
  inspect(summary.median_in_run_cv_pct, content="2")
  let missing = summarize_row("missing", rows_by_run)
  inspect(missing.runs, content="0")
}

///|
async test "bench focus writes raw CSVs and renders the table" {
  let root = "_build/bench-focus-mbt-test"
  @afs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  let command = "printf 'prefix\\n" +
    CSV_HEADER_TEXT +
    "\\nisolate/bytecode/property_get,component,execution,3,15,3,34.0,1,2,0,2.0,false\\n'"
  let run = run_bench_focus(
    BenchConfig(
      runs=2,
      rows=["isolate/bytecode/property_get"],
      command~,
      output_root=root,
      timestamp=Some("fixture"),
      fail_on_missing=false,
      command_timeout_ms=5000,
    ),
  )
  inspect(run.code, content="0")
  assert_true(run.stdout.contains("Command: printf"))
  assert_true(
    run.stdout.contains(
      "| `isolate/bytecode/property_get` | 2/2 | 34.000 ms | 34.000 ms | 34.000 ms | 34.000 ms | 0.0% | 2.0% |",
    ),
  )
  assert_true(@fs.path_exists(root + "/fixture/run-01.csv"))
  inspect(
    @fs.read_file_to_string(root + "/fixture/run-02.csv"),
    content=make_bench_csv(34.0, 2.0),
  )
}

///|
async test "bench focus forwards failing benchmark output" {
  let root = "_build/bench-focus-mbt-fail-test"
  @afs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  let run = run_bench_focus(
    BenchConfig(
      runs=1,
      rows=["isolate/bytecode/property_get"],
      command="sh -c \"printf out; printf err >&2; exit 7\"",
      output_root=root,
      timestamp=Some("fixture"),
      fail_on_missing=false,
      command_timeout_ms=5000,
    ),
  )
  inspect(run.code, content="1")
  assert_true(run.stdout.contains("out"))
  assert_true(run.stderr.contains("err"))
  assert_true(run.stderr.contains("benchmark command failed with exit code 7"))
}

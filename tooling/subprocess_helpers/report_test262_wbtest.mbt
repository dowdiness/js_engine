///|
fn sample_run_info() -> RunInfo {
  {
    id: 1234567,
    sha: "abcdef123456",
    created_at: "2026-06-07T12:34:56Z",
    url: "https://example.invalid/runs/1234567",
  }
}

///|
fn sample_strict_summary() -> Test262Summary {
  { total: 1000, passed: 800, failed: 50, skipped: 100, timeout: 40, error: 10 }
}

///|
fn sample_nonstrict_summary() -> Test262Summary {
  {
    total: 2000,
    passed: 1200,
    failed: 300,
    skipped: 400,
    timeout: 90,
    error: 10,
  }
}

///|
test "report loader defaults optional timeout and error counts" {
  let artifact =
    #|{"summary":{"total":10,"passed":7,"failed":2,"skipped":1}}
  let summary = load_summary_text(artifact)
  inspect(summary.total, content="10")
  inspect(summary.timeout, content="0")
  inspect(summary.error, content="0")
}

///|
test "report renderer preserves per-mode denominators and baseline wording" {
  let baseline = Some({
    strict_min: 790,
    nonstrict_min: 1300,
    updated: "2026-06-01",
  })
  let expected =
    #|**Test262** — CI run [1234567](https://example.invalid/runs/1234567) on tip `abcdef1`, 2026-06-07. Each test file is run twice (strict + non-strict); the two are reported separately because summing would double-count files.
    #|
    #|| Mode | Discovered | Skipped | Executed | Passed | Failed | Timeouts | Passed / Executed | Passed / Discovered |
    #||---|---:|---:|---:|---:|---:|---:|---:|---:|
    #|| strict | 1,000 | 100 | 850 | 800 | 50 | 40 | **94.1%** | 80.0% |
    #|| non-strict | 2,000 | 400 | 1,500 | 1,200 | 300 | 90 | **80.0%** | 60.0% |
    #|
    #|CI regression baseline: `test262-baseline.json` (min 1,300 non-strict / 790 strict passed, updated 2026-06-01; currently -100 / +10 above). **REGRESSION**
    #|
    #|_Note: 20 runner error(s) excluded from the Timeouts column; inspect results JSON for details._
  assert_eq(
    render_report(
      sample_run_info(),
      sample_strict_summary(),
      sample_nonstrict_summary(),
      baseline,
    ),
    expected,
  )
}

///|
test "report renderer keeps GitHub run ids above Int32 range" {
  let run = {
    id: 24730849102L,
    sha: "abcdef123456",
    created_at: "2026-06-07T12:34:56Z",
    url: "https://example.invalid/runs/24730849102",
  }
  assert_true(
    render_report(
      run,
      sample_strict_summary(),
      sample_nonstrict_summary(),
      None,
    ).has_prefix("**Test262** — CI run [24730849102]"),
  )
}

///|
test "run_info_from_json decodes a numeric gh databaseId above Int32 range" {
  // `gh run view --json databaseId` emits the id as a JSON number, not a
  // quoted string. `Int64::from_json` only accepts strings, so the prior
  // `@json.from_json` path failed with "expected number in string
  // representation"; json_int64_field now decodes the number directly.
  let raw =
    #|{"databaseId":27203832547,"headSha":"abcdef123456","createdAt":"2026-06-09T12:34:56Z","url":"https://example.invalid/runs/27203832547"}
  let run = run_info_from_json(@json.parse(raw))
  assert_eq(run.id, 27203832547L)
  assert_eq(run.sha, "abcdef123456")
}

///|
test "changelog renderer includes baseline deltas without table output" {
  let baseline = Some({
    strict_min: 790,
    nonstrict_min: 1100,
    updated: "2026-06-01",
  })
  let expected =
    #|test262 (each file run in both strict and non-strict modes,
    #|reported separately — summing would double-count files):
    #|
    #|- **Passed / Executed**: 94.1% strict (800 / 850),
    #|  80.0% non-strict (1,200 / 1,500).
    #|- **Passed / Discovered**: 80.0% strict (800 / 1,000),
    #|  60.0% non-strict (1,200 / 2,000).
    #|- **Skipped**: 100 strict, 400 non-strict.
    #|
    #|Measured on CI run 1234567 (tip `abcdef1`, 2026-06-07).
    #|Regression baseline: +100 non-strict / +10 strict vs `test262-baseline.json` (min 1,100 / 790).
  assert_eq(
    render_changelog(
      sample_run_info(),
      sample_strict_summary(),
      sample_nonstrict_summary(),
      baseline,
    ),
    expected,
  )
}

///|
async test "find_results locates downloaded strict and non-strict artifacts recursively" {
  let root = "_build/report-test262-mbt-test"
  @afs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @afs.mkdir(root + "/nested/strict", recursive=true)
  @afs.mkdir(root + "/nested/non-strict", recursive=true)
  @afs.write_file(
    root + "/nested/strict/test262-strict-results.json",
    "{}",
    create_mode=CreateOrTruncate,
  )
  @afs.write_file(
    root + "/nested/non-strict/test262-non-strict-results.json",
    "{}",
    create_mode=CreateOrTruncate,
  )
  let (strict, nonstrict) = find_results(root)
  assert_eq(strict, root + "/nested/strict/test262-strict-results.json")
  assert_eq(
    nonstrict,
    root + "/nested/non-strict/test262-non-strict-results.json",
  )
}

///|
async test "find_results merges shard artifacts when canonical files are absent" {
  let root = "_build/report-test262-mbt-shard-test"
  @afs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  // Two shards per mode: shard 1 has 80 passed/10 failed, shard 2 has 70/20
  let s1 = "{\"engine\":\"test\",\"date\":\"1970-01-01T00:00:00Z\",\"summary\":{\"total\":90,\"passed\":80,\"failed\":10,\"skipped\":0,\"timeout\":0,\"error\":0},\"categories\":{},\"results\":[]}"
  let s2 = "{\"engine\":\"test\",\"date\":\"1970-01-01T00:00:00Z\",\"summary\":{\"total\":90,\"passed\":70,\"failed\":20,\"skipped\":0,\"timeout\":0,\"error\":0},\"categories\":{},\"results\":[]}"
  for mode in ["strict", "non-strict"] {
    for i in 1..<3 {
      let dir = root +
        "/test262-" +
        mode +
        "-shard-" +
        i.to_string() +
        "of2-results"
      @afs.mkdir(dir, recursive=true)
      let content = if i == 1 { s1 } else { s2 }
      @afs.write_file(
        dir +
        "/test262-" +
        mode +
        "-shard-" +
        i.to_string() +
        "of2-results.json",
        content,
        create_mode=CreateOrTruncate,
      )
    }
  }
  let (strict_path, nonstrict_path) = find_results(root)
  assert_eq(strict_path, root + "/test262-strict-results.json")
  assert_eq(nonstrict_path, root + "/test262-non-strict-results.json")
  // Verify merged summary sums across shards (80+70=150 passed, 10+20=30 failed)
  let strict_root = json_object(
    @json.parse(@fs.read_file_to_string(strict_path)),
    "merged strict",
  )
  let summary = json_object(
    required_field(strict_root, "summary", "merged strict"),
    "strict summary",
  )
  assert_eq(json_int_field(summary, "passed", "strict summary"), 150)
  assert_eq(json_int_field(summary, "failed", "strict summary"), 30)
}

///|
async test "panic find_results rejects an incomplete shard set" {
  let root = "_build/report-test262-mbt-incomplete-shard-test"
  @afs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  let shard_json = "{\"engine\":\"test\",\"date\":\"1970-01-01T00:00:00Z\",\"summary\":{\"total\":90,\"passed\":80,\"failed\":10,\"skipped\":0,\"timeout\":0,\"error\":0},\"categories\":{},\"results\":[]}"
  // Only shard 1of2 present; shard 2of2 absent — validate_shard_completeness must abort
  for mode in ["strict", "non-strict"] {
    let dir = root + "/test262-" + mode + "-shard-1of2-results"
    @afs.mkdir(dir, recursive=true)
    @afs.write_file(
      dir + "/test262-" + mode + "-shard-1of2-results.json",
      shard_json,
      create_mode=CreateOrTruncate,
    )
  }
  find_results(root) |> ignore
}

///|
async test "panic find_results rejects duplicate shard indices" {
  let root = "_build/report-test262-mbt-duplicate-shard-test"
  @afs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  let shard_json = "{\"engine\":\"test\",\"date\":\"1970-01-01T00:00:00Z\",\"summary\":{\"total\":90,\"passed\":80,\"failed\":10,\"skipped\":0,\"timeout\":0,\"error\":0},\"categories\":{},\"results\":[]}"
  // Two strict artifacts both claiming shard 1of2 — count matches but indices are not {1,2}
  for dir_suffix in ["results", "results-dup"] {
    let dir = root + "/test262-strict-shard-1of2-" + dir_suffix
    @afs.mkdir(dir, recursive=true)
    @afs.write_file(
      dir + "/test262-strict-shard-1of2-results.json",
      shard_json,
      create_mode=CreateOrTruncate,
    )
  }
  // Non-strict needs at least one file to pass the guard before strict is validated
  let ns_dir = root + "/test262-non-strict-shard-1of2-results"
  @afs.mkdir(ns_dir, recursive=true)
  @afs.write_file(
    ns_dir + "/test262-non-strict-shard-1of2-results.json",
    shard_json,
    create_mode=CreateOrTruncate,
  )
  find_results(root) |> ignore
}

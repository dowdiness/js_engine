///|
fn shlex_split(command : String) -> Array[String] raise {
  let args : Array[String] = []
  let buf = StringBuilder()
  let chars = command.to_array()
  let mut quote : Char? = None
  let mut token_started = false
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    match quote {
      Some(q) =>
        if ch == q {
          quote = None
        } else if ch == '\\' && i + 1 < chars.length() {
          i += 1
          buf.write_char(chars[i])
        } else {
          buf.write_char(ch)
        }
      None =>
        if ch == ' ' || ch == '\t' || ch == '\n' {
          if token_started || !buf.is_empty() {
            args.push(buf.to_string())
            buf.reset()
            token_started = false
          }
        } else if ch == '\'' || ch == '"' {
          quote = Some(ch)
          token_started = true
        } else if ch == '\\' {
          if i + 1 < chars.length() {
            i += 1
            buf.write_char(chars[i])
            token_started = true
          } else {
            buf.write_char(ch)
            token_started = true
          }
        } else {
          buf.write_char(ch)
          token_started = true
        }
    }
    i += 1
  }
  if quote is Some(_) {
    fail("No closing quotation")
  }
  if token_started || !buf.is_empty() {
    args.push(buf.to_string())
  }
  args
}

///|
async fn auto_thread_count() -> Int {
  let detected = @async.with_timeout_opt(1000, () => {
    collect_output_hard("getconf", ["_NPROCESSORS_ONLN"])
  }) catch {
    _ => None
  }
  match detected {
    Some(capture) if capture.code == 0 => {
      let count = @string.parse_int(capture.stdout.trim()) catch { _ => 0 }
      if count > DEFAULT_THREAD_COUNT {
        count
      } else {
        DEFAULT_THREAD_COUNT
      }
    }
    _ => DEFAULT_THREAD_COUNT
  }
}

///|
fn auto_detect_engine() -> String? {
  for
    path in [
      "target/js/release/build/cmd/main/main.js", "target/js/debug/build/cmd/main/main.js",
      "_build/js/release/build/cmd/main/main.js", "_build/js/debug/build/cmd/main/main.js",
    ] {
    if is_readable_file(path) {
      return Some("node " + path)
    }
  }
  None
}

///|
fn validate_config(config : RunnerConfig) -> Unit raise {
  if config.mode != "both" &&
    config.mode != "strict" &&
    config.mode != "non-strict" {
    fail(
      "argument --mode: invalid choice: '\{config.mode}' (choose from 'both', 'strict', 'non-strict')",
    )
  }
  if config.start < 0 {
    fail("--start must be >= 0")
  }
  match config.count {
    Some(value) if value < 0 => fail("--count must be >= 0")
    _ => ()
  }
  if config.shard is Some(_) && (config.start != 0 || config.count is Some(_)) {
    fail("--shard cannot be combined with --start/--count")
  }
}

///|
async fn verify_engine(engine_cmd : Array[String], out : StringBuilder) -> Unit {
  out.write_string("Verifying engine...\n")
  guard engine_cmd.length() > 0 else { fail("Engine command is empty") }
  let check = @async.with_timeout_opt(30000, () => {
    collect_output_hard(engine_cmd[0], engine_cmd[1:] + ["1 + 1"])
  }) catch {
    err => fail("Engine command not found: \{engine_cmd[0]} (\{err})")
  }
  match check {
    None => out.write_string("Warning: Engine verification timed out\n")
    Some(capture) =>
      if capture.code != 0 {
        out.write_string(
          "Warning: Engine returned non-zero exit code: \{capture.code}\n",
        )
        out.write_string("  stdout: \{capture.stdout.trim()}\n")
        out.write_string("  stderr: \{capture.stderr.trim()}\n")
      }
  }
}

///|
async fn run_test_tasks(
  engine_cmd : Array[String],
  test262_dir : String,
  test_tasks : Array[(String, String)],
  timeout : Int,
  threads : Int,
  skip_metadata : @metadata.SkipMetadata,
  harness_options : HarnessOptions,
  progress_log : String,
  merged_log : String,
) -> (Array[TestResult], Double) {
  let jobs : Array[async () -> TestResult] = []
  for task in test_tasks {
    let test_path = task.0
    let mode = task.1
    jobs.push(() => {
      let result = run_single_test(
        engine_cmd,
        test262_dir,
        test_path,
        timeout,
        mode~,
        skip_metadata~,
        harness_options~,
      )
      write_result_logs(progress_log, merged_log, result)
      result
    })
  }
  let start_time = @async.now()
  let results = @async.all(jobs, max_concurrent=threads)
  (results, (@async.now() - start_time).to_double() / 1000.0)
}

///|
fn status_mark(status : String) -> String {
  match status {
    "pass" => "."
    "fail" => "F"
    "skip" => "S"
    "timeout" => "T"
    "error" => "E"
    _ => "?"
  }
}

///|
fn write_verbose_marks(
  out : StringBuilder,
  results : Array[TestResult],
) -> Unit {
  for i, result in results {
    out.write_string(status_mark(result.status))
    if (i + 1) % 80 == 0 {
      out.write_char('\n')
    }
  }
  if results.length() > 0 {
    out.write_char('\n')
  }
}

///|
pub async fn run_runner(config : RunnerConfig) -> ToolRun {
  validate_config(config)
  let out = StringBuilder()
  let err = StringBuilder()
  let engine = match config.engine {
    Some(value) => value
    None =>
      match auto_detect_engine() {
        Some(value) => {
          out.write_string("Using engine: \{value}\n")
          value
        }
        None =>
          fail(
            "No built JS bundle found. Run `moon build --target js` first. Searched: target/js/release/build/cmd/main/main.js, target/js/debug/build/cmd/main/main.js, _build/js/release/build/cmd/main/main.js, _build/js/debug/build/cmd/main/main.js",
          )
      }
  }
  let mut threads = match config.threads {
    Some(value) => value
    None => auto_thread_count()
  }
  if threads < 1 {
    threads = 1
  }
  let engine_cmd = shlex_split(engine)
  let test262_dir = absolute_path(config.test262)
  guard is_readable_dir(test262_dir) else {
    fail("test262 directory not found: \{test262_dir}")
  }
  verify_engine(engine_cmd, out) catch {
    e => fail("\{e}")
  }
  let test_files = if config.tests_file != "" {
    out.write_string("Loading tests from \{config.tests_file}...\n")
    let loaded = load_tests_file(config.tests_file, test262_dir) catch {
      err => fail("failed to read tests file \{config.tests_file}: \{err}")
    }
    let filtered = if config.filter == "" {
      loaded
    } else {
      loaded.filter(tf => {
        normalize_test262_path(tf, test262_dir~).contains(config.filter)
      })
    }
    out.write_string("Loaded \{filtered.length()} test files\n")
    filtered
  } else {
    out.write_string("Discovering tests in \{test262_dir}...\n")
    let discovered = discover_tests(test262_dir, filter_pattern=config.filter)
    out.write_string("Found \{discovered.length()} test files\n")
    discovered
  }
  let test_tasks = build_test_tasks(test_files, config.mode)
  let (selected_tasks, selection_messages) = apply_task_selection(
    test_tasks,
    shard_spec=config.shard,
    start=config.start,
    count=config.count,
    resume_from=config.resume_from,
    test262_dir~,
  ) catch {
    err =>
      if config.resume_from != "" {
        fail("failed to read resume file \{config.resume_from}: \{err}")
      } else {
        fail("\{err}")
      }
  }
  for message in selection_messages {
    out.write_string(message + "\n")
  }
  let mode_label = if config.mode == "both" {
    "strict+non-strict"
  } else {
    config.mode
  }
  out.write_string(
    "Running \{selected_tasks.length()} test tasks (\{test_files.length()} files, \{mode_label})\n",
  )
  out.write_string(
    "Using \{threads} parallel worker(s) with \{config.timeout}s timeout per test\n",
  )
  if config.harness_options.is_modified() {
    out.write_string(
      "Using modified Test262 harness helpers: \{config.harness_options.helper_names().join(", ")}\n",
    )
  }
  let skip_metadata = @metadata.load_skip_metadata(root=config.repo_root)
  initialize_result_logs(config.log, config.merged_log) catch {
    err => fail("failed to open result log: \{err}")
  }
  let (results, total_time) = run_test_tasks(
    engine_cmd,
    test262_dir,
    selected_tasks,
    config.timeout,
    threads,
    skip_metadata,
    config.harness_options,
    config.log,
    config.merged_log,
  )
  if config.verbose {
    write_verbose_marks(out, results)
  }
  out.write_string("\nCompleted in \{format_decimal(total_time, 1)}s\n")
  let agg = aggregate_results(results, test262_dir~)
  out.write_string(
    print_report_text(
      agg,
      results,
      config.summary,
      config.harness_options.methodology_label(),
    ),
  )
  let output_file = if config.output == "" {
    "test262-results.json"
  } else {
    config.output
  }
  save_results(
    results,
    agg,
    output_file,
    harness_options=config.harness_options,
  )
  out.write_string("  Results saved to: \{output_file}\n")
  // Conformance failures are result data (recorded in the JSON), not a
  // process failure. Exit codes signal runner health only: 0 = completed
  // and wrote results; 1 = runtime/internal error (raised before this
  // point, including a failed save_results); 2 = CLI usage error.
  { stdout: out.to_string(), stderr: err.to_string(), code: 0 }
}

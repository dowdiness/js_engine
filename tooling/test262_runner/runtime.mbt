///|
/// Parse a configured `--engine` command string into argv without a shell.
/// This is the Test262 runner's only tokenization seam; do not reintroduce a
/// local quote parser.
fn parse_engine_command(engine : String) -> Array[String] raise {
  @helpers.tokenize_command(engine)
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
  on_progress : async (Int, Int, Double) -> Unit,
) -> (Array[TestResult], Double) {
  let done_count = Ref(0)
  let total = test_tasks.length()
  let start_time = @async.now()
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
      done_count.val += 1
      let elapsed_s = (@async.now() - start_time).to_double() / 1000.0
      on_progress(done_count.val, total, elapsed_s)
      result
    })
  }
  let results = @async.all(jobs, max_concurrent=threads)
  (results, (@async.now() - start_time).to_double() / 1000.0)
}

///|
fn is_interactive() -> Bool {
  @env.get_env_var("CI").unwrap_or("") == "" &&
  @env.get_env_var("TERM").unwrap_or("") != "dumb"
}

///|
fn render_progress_bar(done : Int, total : Int) -> String {
  let pct = if total == 0 { 100 } else { done * 100 / total }
  let width = 30
  let filled = if total == 0 { width } else { done * width / total }
  let bar = if filled >= width {
    String::make(width, '=')
  } else {
    String::make(filled, '=') + ">" + String::make(width - filled - 1, ' ')
  }
  "[" +
  bar +
  "] " +
  done.to_string() +
  "/" +
  total.to_string() +
  " (" +
  pct.to_string() +
  "%)"
}

///|
fn format_eta(elapsed_s : Double, done : Int, total : Int) -> String {
  guard done > 0 && done < total else { return "" }
  let eta_s = (elapsed_s / done.to_double() * (total - done).to_double()).to_int()
  if eta_s < 60 {
    " ETA: \{eta_s}s"
  } else {
    " ETA: \{eta_s / 60}m\{eta_s % 60}s"
  }
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
  let engine_cmd = parse_engine_command(engine)
  let test262_dir = @path_utils.absolute_path(config.test262)
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
  let interactive = is_interactive()
  let last_pct_bucket = Ref(-1)
  let on_progress : async (Int, Int, Double) -> Unit = (done, total, elapsed_s) => {
    if interactive {
      let line = render_progress_bar(done, total) +
        format_eta(elapsed_s, done, total)
      @stdio.stderr.write("\r" + line) catch {
        _ => ()
      }
    } else {
      let bucket = if total == 0 { 10 } else { done * 10 / total }
      if bucket > last_pct_bucket.val {
        last_pct_bucket.val = bucket
        let pct = if total == 0 { 100 } else { done * 100 / total }
        let eta = format_eta(elapsed_s, done, total)
        @stdio.stderr.write(
          "[" +
          done.to_string() +
          "/" +
          total.to_string() +
          "] " +
          pct.to_string() +
          "%" +
          eta +
          "\n",
        ) catch {
          _ => ()
        }
      }
    }
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
    on_progress,
  )
  if interactive {
    @stdio.stderr.write("\n") catch {
      _ => ()
    }
  }
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

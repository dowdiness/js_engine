///|
async fn collect_output_hard(
  cmd : String,
  args : ArrayView[String],
) -> ProcessCapture {
  let (r_out, w_out) = @process.read_from_process()
  let (r_err, w_err) = @process.read_from_process()
  @async.with_task_group() <| group => {
    let exit_code = group.spawn(() => {
      @process.run(
        cmd,
        args,
        stdout=w_out,
        stderr=w_err,
        cancel_handler=@process.hard_cancel(),
      )
    })
    let stdout = group.spawn(() => {
      defer r_out.close()
      r_out.read_all()
    })
    let stderr = group.spawn(() => {
      defer r_err.close()
      r_err.read_all()
    })
    {
      code: exit_code.wait(),
      stdout: stdout.wait().text(),
      stderr: stderr.wait().text(),
    }
  }
}

///|
fn truncate_reason(reason : String) -> String {
  if reason.length() > 200 {
    reason[:200].to_owned()
  } else {
    reason
  }
}

///|
fn negative_field(
  negative : Map[String, Json],
  key : String,
  default : String,
) -> String {
  match negative.get(key) {
    Some(value) => json_to_string(value)
    None => default
  }
}

///|
fn result_for_completed_process(
  test_path : String,
  mode : String,
  meta : TestMetadata,
  is_async : Bool,
  capture : ProcessCapture,
  duration_ms : Double,
) -> TestResult {
  let stdout = capture.stdout.trim().to_owned()
  let stderr = capture.stderr.trim().to_owned()
  let exit_code = capture.code
  match meta.negative {
    Some(negative) => {
      let neg_phase = negative_field(negative, "phase", "runtime")
      let neg_type = negative_field(negative, "type", "")
      if exit_code != 0 ||
        stdout.contains("Error:") ||
        stderr.contains("Error:") {
        let error_output = stdout + " " + stderr
        if neg_type != "" && error_output.contains(neg_type) {
          TestResult(path=test_path, status="pass", duration_ms~, mode~)
        } else if neg_type != "" {
          if neg_phase == "parse" {
            TestResult(
              path=test_path,
              status="pass",
              reason="parse error (expected \{neg_type})",
              duration_ms~,
              mode~,
            )
          } else {
            TestResult(
              path=test_path,
              status="pass",
              reason="error thrown (expected \{neg_type})",
              duration_ms~,
              mode~,
            )
          }
        } else {
          TestResult(path=test_path, status="pass", duration_ms~, mode~)
        }
      } else {
        TestResult(
          path=test_path,
          status="fail",
          reason="Expected \{neg_type} error but test passed normally",
          duration_ms~,
          mode~,
        )
      }
    }
    None =>
      if is_async {
        let combined = stdout + "\n" + stderr
        if combined.contains("Test262:AsyncTestFailure") {
          for line in combined.split("\n") {
            match line.find("Test262:AsyncTestFailure:") {
              Some(index) =>
                return TestResult(
                  path=test_path,
                  status="fail",
                  reason=truncate_reason(
                    line[index + "Test262:AsyncTestFailure:".length():]
                    .trim()
                    .to_owned(),
                  ),
                  duration_ms~,
                  mode~,
                )
              None => ()
            }
          }
          TestResult(
            path=test_path,
            status="fail",
            reason="async test failure (no details)",
            duration_ms~,
            mode~,
          )
        } else if combined.contains("Test262:AsyncTestComplete") {
          if exit_code != 0 {
            TestResult(
              path=test_path,
              status="fail",
              reason="async test completed but exited with code \{exit_code}",
              duration_ms~,
              mode~,
            )
          } else {
            TestResult(path=test_path, status="pass", duration_ms~, mode~)
          }
        } else if exit_code != 0 ||
          stdout.contains("Error:") ||
          stdout.contains("Test262Error") {
          let error_msg = if stdout != "" { stdout } else { stderr }
          TestResult(
            path=test_path,
            status="fail",
            reason=truncate_reason(error_msg),
            duration_ms~,
            mode~,
          )
        } else {
          TestResult(
            path=test_path,
            status="fail",
            reason="async test did not call $DONE",
            duration_ms~,
            mode~,
          )
        }
      } else if exit_code == 0 &&
        !stdout.contains("Error:") &&
        !stdout.contains("Test262Error") {
        TestResult(path=test_path, status="pass", duration_ms~, mode~)
      } else {
        let error_msg = if stdout != "" { stdout } else { stderr }
        TestResult(
          path=test_path,
          status="fail",
          reason=truncate_reason(error_msg),
          duration_ms~,
          mode~,
        )
      }
  }
}

///|
async fn run_single_test(
  engine_cmd : Array[String],
  test262_dir : String,
  test_path : String,
  timeout : Int,
  mode? : String = "non-strict",
  skip_metadata~ : @metadata.SkipMetadata,
  harness_options? : HarnessOptions = HarnessOptions(),
) -> TestResult {
  let source = @fs.read_file_to_string(test_path) catch {
    err =>
      return TestResult(
        path=test_path,
        status="error",
        reason=@debug.to_string(err),
        mode~,
      )
  }
  let meta = parse_metadata(source)
  match
    skip_metadata.skip_reason(test_path, meta.features, meta.flags, Some(mode)) {
    Some(reason) =>
      return TestResult(path=test_path, status="skip", reason~, mode~)
    None => ()
  }
  let is_async = meta.flags.any(flag => flag == "async")
  let is_module = meta.flags.any(flag => flag == "module")
  let harness = load_harness(
    test262_dir,
    meta.includes,
    meta.raw,
    is_async~,
    harness_options~,
  )
  let full_source = if mode == "strict" && !meta.raw {
    "\"use strict\";\n" + harness + "\n" + source
  } else {
    harness + "\n" + source
  }
  let is_annex_b = test_path.contains("annexB")
  let cmd = append_engine_flags(
    engine_cmd, test_path, source, is_module, is_annex_b,
  ) catch {
    err =>
      return TestResult(path=test_path, status="error", reason="\{err}", mode~)
  }
  cmd.push(full_source)
  guard cmd.length() > 0 else {
    return TestResult(
      path=test_path,
      status="error",
      reason="empty engine command",
      mode~,
    )
  }
  let exe = cmd[0]
  let args = cmd[1:]
  let start_time = @async.now()
  let result = @async.with_timeout_opt(timeout * 1000, () => {
    collect_output_hard(exe, args)
  }) catch {
    err => {
      let duration_ms = (@async.now() - start_time).to_double()
      return TestResult(
        path=test_path,
        status="error",
        reason=truncate_reason("\{err}"),
        duration_ms~,
        mode~,
      )
    }
  }
  let duration_ms = (@async.now() - start_time).to_double()
  match result {
    None =>
      TestResult(
        path=test_path,
        status="timeout",
        reason="Exceeded \{timeout}s timeout",
        duration_ms~,
        mode~,
      )
    Some(capture) =>
      result_for_completed_process(
        test_path, mode, meta, is_async, capture, duration_ms,
      )
  }
}

///|
fn discover_tests_in_dir(
  dir : String,
  rel_prefix : String,
  filter_pattern : String,
  tests : Array[String],
) -> Unit raise {
  let entries = @fs.read_dir(dir)
  entries.sort()
  for entry in entries {
    let full_path = join_path(dir, entry)
    let rel_path = if rel_prefix == "" {
      entry
    } else {
      join_path(rel_prefix, entry)
    }
    if is_readable_dir(full_path) {
      if rel_path.has_prefix("intl402") || rel_path.has_prefix("staging") {
        continue
      }
      discover_tests_in_dir(full_path, rel_path, filter_pattern, tests)
    } else if is_readable_file(full_path) &&
      entry.has_suffix(".js") &&
      !entry.contains("_FIXTURE") {
      if filter_pattern == "" || rel_path.contains(filter_pattern) {
        tests.push(full_path)
      }
    }
  }
}

///|
fn discover_tests(
  test262_dir : String,
  filter_pattern? : String = "",
) -> Array[String] raise {
  let test_dir = join_path(test262_dir, "test")
  let tests : Array[String] = []
  discover_tests_in_dir(test_dir, "", filter_pattern, tests)
  tests
}

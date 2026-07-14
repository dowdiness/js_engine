///|
const TEST_ROOT = "_build/test262_runner_wbtest"

///|
fn write_text(path : String, text : String) -> Unit raise {
  ensure_parent_dir(path)
  @fs.write_string_to_file(path, text)
}

///|
fn write_test_file(
  path : String,
  frontmatter? : String = "description: test",
  body? : String = "",
) -> Unit raise {
  write_text(path, "/*---\n" + frontmatter + "\n---*/\n" + body + "\n")
}

///|
fn assert_raises(f : () -> Unit raise) -> Unit {
  try {
    f()
    abort("expected failure")
  } catch {
    _ => ()
  }
}

///|
async fn run_node_script(script : String) -> ProcessCapture? {
  // CI runners can be slow to spawn node + evaluate SharedArrayBuffer/Atomics
  // harness scripts; 3s was flaky under parallel Test262 jobs.
  let capture = @async.with_timeout_opt(15000, () => {
    collect_output_hard("node", ["-e", script])
  }) catch {
    err => {
      let msg = @debug.to_string(err)
      if msg.contains("No such file or directory") ||
        msg.contains("not found") ||
        msg.contains("The system cannot find the file specified") {
        None
      } else {
        fail("Unexpected node execution failure: \{msg}")
      }
    }
  }
  match capture {
    None => fail("Node harness probe timed out")
    Some(capture) => Some(capture)
  }
}

///|
test "command tokenization preserves backslash inside single quotes" {
  json_inspect(parse_engine_command("engine 'path\\to\\file'"), content=[
    "engine", "path\\to\\file",
  ])
}

///|
test "command tokenization matches subprocess helper contract" {
  json_inspect(parse_engine_command("sh -c \"printf 'hi there'\""), content=[
    "sh", "-c", "printf 'hi there'",
  ])
  json_inspect(parse_engine_command("a\\ b"), content=["a b"])
  try {
    ignore(parse_engine_command("'open"))
    abort("expected failure")
  } catch {
    _ => ()
  }
  try {
    ignore(parse_engine_command("\"open"))
    abort("expected failure")
  } catch {
    _ => ()
  }
}

///|
test "task selection mirrors Python runner helpers" {
  let tasks : Array[(String, String)] = []
  for i in 0..<10 {
    tasks.push(("/suite/test/language/t\{i}.js", "strict"))
  }
  json_inspect(slice_tasks(tasks, start=2, count=Some(3)), content=[
    ("/suite/test/language/t2.js", "strict"),
    ("/suite/test/language/t3.js", "strict"),
    ("/suite/test/language/t4.js", "strict"),
  ])
  debug_inspect(parse_shard_spec(" 3 / 4 "), content="(3, 4)")
  assert_raises(() => ignore(parse_shard_spec("2-of-4")))
  json_inspect(shard_tasks(tasks, 2, 3), content=[
    ("/suite/test/language/t4.js", "strict"),
    ("/suite/test/language/t5.js", "strict"),
    ("/suite/test/language/t6.js", "strict"),
  ])

  let test262_root = @path_utils.join_path(TEST_ROOT, "selection/test262")
  let test_dir = @path_utils.join_path(test262_root, "test/language")
  let normal = @path_utils.join_path(test_dir, "normal.js")
  let raw = @path_utils.join_path(test_dir, "raw.js")
  let module_test = @path_utils.join_path(test_dir, "module.js")
  let only_strict = @path_utils.join_path(test_dir, "only-strict.js")
  let no_strict = @path_utils.join_path(test_dir, "no-strict.js")
  let missing = @path_utils.join_path(test_dir, "missing.js")
  write_test_file(normal)
  write_test_file(raw, frontmatter="flags: [raw]")
  write_test_file(module_test, frontmatter="flags: [module]")
  write_test_file(only_strict, frontmatter="flags: [onlyStrict]")
  write_test_file(no_strict, frontmatter="flags: [noStrict]")
  let files = [normal, raw, module_test, only_strict, no_strict, missing]
  json_inspect(build_test_tasks(files, "both"), content=[
    (normal, "non-strict"),
    (normal, "strict"),
    (raw, "non-strict"),
    (module_test, "non-strict"),
    (only_strict, "strict"),
    (no_strict, "non-strict"),
    (missing, "non-strict"),
    (missing, "strict"),
  ])

  let tests_file = @path_utils.join_path(TEST_ROOT, "selection/tests.txt")
  write_text(
    tests_file, "# comment\nlanguage/normal.js\n test/language/raw.js # inline\n",
  )
  json_inspect(load_tests_file(tests_file, test262_root), content=[
    @path_utils.absolute_path(normal),
    @path_utils.absolute_path(raw),
  ])

  let resume_file = @path_utils.join_path(TEST_ROOT, "selection/results.json")
  write_text(
    resume_file,
    (
      #|{"results":[
      #|  {"path":"test/language/normal.js","mode":"non-strict","status":"pass"},
      #|  {"path":"test/language/raw.js","mode":"non-strict","status":"fail"},
      #|  {"path":"test/language/raw.js","mode":"strict","status":"skip"}
      #|]}
    ),
  )
  let selection = [
    (@path_utils.join_path(test_dir, "normal.js"), "non-strict"),
    (@path_utils.join_path(test_dir, "normal.js"), "strict"),
    (@path_utils.join_path(test_dir, "raw.js"), "non-strict"),
    (@path_utils.join_path(test_dir, "raw.js"), "strict"),
    (@path_utils.join_path(test_dir, "module.js"), "non-strict"),
  ]
  let (sliced, messages) = apply_task_selection(
    selection,
    start=1,
    count=Some(3),
    resume_from=resume_file,
    test262_dir=@path_utils.join_path(test262_root, "test"),
  )
  json_inspect(sliced, content=[
    (@path_utils.join_path(test_dir, "normal.js"), "strict"),
  ])
  inspect(messages.length(), content="2")
  inspect(messages[0], content="Selected task slice: start=1, count=3 (3/5)")
  inspect(
    messages[1].contains(
      "Resume: skipped 2 completed task(s) from " + resume_file,
    ),
    content="true",
  )

  let (sharded, shard_messages) = apply_task_selection(
    selection,
    shard_spec=Some((1, 2)),
    test262_dir=@path_utils.join_path(test262_root, "test"),
  )
  json_inspect(sharded, content=[
    (@path_utils.join_path(test_dir, "normal.js"), "non-strict"),
    (@path_utils.join_path(test_dir, "normal.js"), "strict"),
    (@path_utils.join_path(test_dir, "raw.js"), "non-strict"),
  ])
  inspect(shard_messages[0].contains("Selected shard 1/2"), content="true")
}

///|
test "build_test_tasks falls back to defaults when task metadata read fails" {
  let test_dir = @path_utils.join_path(TEST_ROOT, "selection/fallback")
  let missing = @path_utils.join_path(test_dir, "missing.js")
  let bad_path = @path_utils.join_path(test_dir, "bad-file")
  let malformed = @path_utils.join_path(test_dir, "malformed.js")
  let valid = @path_utils.join_path(test_dir, "valid.js")
  ensure_dir(bad_path)
  write_text(
    malformed,
    (
      #|/*---
      #|flags: [raw
    ),
  )
  write_test_file(valid)

  let tasks = build_test_tasks([missing, bad_path, malformed, valid], "both")
  json_inspect(tasks, content=[
    (missing, "non-strict"),
    (missing, "strict"),
    (bad_path, "non-strict"),
    (bad_path, "strict"),
    (malformed, "non-strict"),
    (malformed, "strict"),
    (valid, "non-strict"),
    (valid, "strict"),
  ])
}

///|
test "resume keys and artifact schema fields match the contract" {
  let root = @path_utils.join_path(TEST_ROOT, "resume/test262")
  let test_root = @path_utils.join_path(root, "test")
  let results_file = @path_utils.join_path(TEST_ROOT, "resume/results.json")
  write_text(
    results_file,
    (
      #|{"results":[
      #|  {"path":"test262/test/language/add.js","mode":"strict","status":"pass"},
      #|  {"path":"language/add.js","mode":"non-strict","status":"timeout"},
      #|  {"path":"language/if.js","mode":"strict","status":"running"}
      #|]}
    ),
  )
  let completed = load_completed_task_keys(results_file, test262_dir=root)
  let tasks = [
    (@path_utils.join_path(test_root, "language/add.js"), "strict"),
    (@path_utils.join_path(test_root, "language/add.js"), "non-strict"),
    (@path_utils.join_path(test_root, "language/if.js"), "strict"),
  ]
  json_inspect(filter_completed_tasks(tasks, completed, test262_dir=root), content=[
    (@path_utils.join_path(test_root, "language/if.js"), "strict"),
  ])

  let results = [
    TestResult(
      path=@path_utils.join_path(test_root, "language/expressions/pass.js"),
      status="pass",
      mode="strict",
    ),
    TestResult(
      path=@path_utils.join_path(test_root, "language/expressions/fail.js"),
      status="fail",
      reason="boom",
      mode="non-strict",
    ),
    TestResult(
      path=@path_utils.join_path(test_root, "language/expressions/skip.js"),
      status="skip",
      reason="why",
      mode="strict",
    ),
  ]
  let artifact = results_artifact(
    results,
    aggregate_results(results, test262_dir=root),
  )
  let root_obj : Map[String, Json] = @json.from_json(artifact) catch {
    _ => abort("artifact object")
  }
  let summary : Map[String, Json] = @json.from_json(root_obj["summary"]) catch {
    _ => abort("summary object")
  }
  let categories : Map[String, Json] = @json.from_json(root_obj["categories"]) catch {
    _ => abort("categories object")
  }
  inspect(categories.contains("language/expressions"), content="true")
  inspect(categories.contains("../.."), content="false")
  inspect(summary["passed"].stringify(), content="1")
  inspect(summary["failed"].stringify(), content="1")
  inspect(summary["skipped"].stringify(), content="1")
  inspect(summary["pass_rate"].stringify(), content="50.00")
  inspect(artifact.stringify().contains("\"methodology\""), content="false")

  let modified = results_artifact(
    results,
    aggregate_results(results, test262_dir=root),
    harness_options=HarnessOptions(helpers=[HELPER_CODE_POINT_RANGE]),
  )
  inspect(modified.stringify().contains("modified harness"), content="true")
}

///|
test "harness options parse and transform helpers deterministically" {
  let parsed = HarnessOptions::from_cli([
    "codePointRange, atomicsTimeoutProfile=short",
  ])
  json_inspect(parsed.helper_names(), content=[
    HELPER_CODE_POINT_RANGE,
    HELPER_ATOMICS_TIMEOUT_PROFILE + "=" + ATOMICS_TIMEOUT_PROFILE_SHORT,
  ])

  let parsed_default = HarnessOptions::from_cli([
    "atomicsTimeoutProfile=default",
  ])
  json_inspect(parsed_default.helper_names(), content=[])
  inspect(parsed_default.is_modified(), content="false")
  inspect(parsed_default.preamble(), content="")

  assert_raises(() => ignore(HarnessOptions::from_cli(["notReal"])))
  assert_raises(() => {
    ignore(HarnessOptions::from_cli(["atomicsTimeoutProfile=bad"]))
  })

  let helper = HarnessOptions(
    helpers=[HELPER_CODE_POINT_RANGE],
    atomics_timeout_profile=ATOMICS_TIMEOUT_PROFILE_SHORT,
  )
  let preamble = helper.preamble()
  inspect(
    preamble.contains("__TEST262_LIMITED_ATOMICS_TIMEOUT"),
    content="true",
  )
  inspect(preamble.contains("Number(timeout)"), content="true")
  inspect(
    preamble.contains("Number.isNaN(__TEST262_LIMITED_ATOMICS_TIMEOUT_NUM)"),
    content="true",
  )

  let transformed_regexp = helper.transform_include(
    "path/to/regExpUtils.js",
    REGEXP_UTILS_BUILD_STRING,
  )
  let transformed_other = helper.transform_include(
    "path/to/other.js", "const already = 1;",
  )
  inspect(
    transformed_regexp.contains("typeof $262.codePointRange"),
    content="true",
  )
  inspect(
    transformed_regexp.contains("result += $262.codePointRange(start, end);"),
    content="true",
  )
  inspect(transformed_other, content="const already = 1;")
}

///|
test "atomics short timeout preamble normalizes non-number and missing inputs" {
  let helper = HarnessOptions(
    atomics_timeout_profile=ATOMICS_TIMEOUT_PROFILE_SHORT,
  )
  let preamble = helper.preamble()
  inspect(
    preamble.contains(
      "var __TEST262_LIMITED_ATOMICS_TIMEOUT_NUM = Number(timeout);",
    ),
    content="true",
  )
  inspect(
    preamble.contains(
      "if (Number.isNaN(__TEST262_LIMITED_ATOMICS_TIMEOUT_NUM)) {",
    ),
    content="true",
  )
  inspect(
    preamble.contains(
      "__TEST262_LIMITED_ATOMICS_TIMEOUT_NUM = Number.POSITIVE_INFINITY;",
    ),
    content="true",
  )
  inspect(
    preamble.contains(
      "return (__TEST262_LIMITED_ATOMICS_TIMEOUT_NUM > __TEST262_ATOMICS_TIMEOUT_MS) ? __TEST262_ATOMICS_TIMEOUT_MS : __TEST262_LIMITED_ATOMICS_TIMEOUT_NUM;",
    ),
    content="true",
  )
  inspect(
    preamble.contains("if (typeof timeout !== 'number' || timeout < 0)"),
    content="false",
  )
  inspect(
    preamble.contains(
      "Atomics.wait = function(typedArray, index, value, timeout)",
    ),
    content="true",
  )
  inspect(
    preamble.contains(
      "return __TEST262_ORIGINAL_ATOMICS_WAIT(typedArray, index, value, __TEST262_LIMITED_ATOMICS_TIMEOUT(timeout));",
    ),
    content="true",
  )
  inspect(
    preamble.contains(
      "return __TEST262_ORIGINAL_ATOMICS_WAIT_ASYNC(typedArray, index, value, __TEST262_LIMITED_ATOMICS_TIMEOUT(timeout));",
    ),
    content="true",
  )
}

///|
async test "atomics short timeout wrapper passes coerced timeouts at runtime" {
  let root = @path_utils.join_path(TEST_ROOT, "harness/runtime-atomics")
  let harness_dir = @path_utils.join_path(root, "harness")
  write_text(@path_utils.join_path(harness_dir, "sta.js"), "")
  write_text(@path_utils.join_path(harness_dir, "assert.js"), "")
  let harness = load_harness(
    root,
    [],
    false,
    harness_options=HarnessOptions(
      atomics_timeout_profile=ATOMICS_TIMEOUT_PROFILE_SHORT,
    ),
  )
  let script = harness +
    (
      #|let captured = [];
      #|__TEST262_ORIGINAL_ATOMICS_WAIT = function(typedArray, index, value, timeout) {
      #|  captured.push(timeout);
      #|};
      #|const ta = new Int32Array(new SharedArrayBuffer(4));
      #|Atomics.wait(ta, 0, 0, 200);
      #|Atomics.wait(ta, 0, 0, "foo");
      #|Atomics.wait(ta, 0, 0, undefined);
      #|Atomics.wait(ta, 0, 0, -1);
      #|console.log(captured.join(','));
    )
  match run_node_script(script) {
    None => inspect(true, content="true")
    Some(capture) => {
      inspect(capture.code, content="0")
      inspect(capture.stdout.trim(), content="100,100,100,-1")
    }
  }
}

///|
async test "atomics short timeout wrapper passes coerced timeouts for waitAsync when native delegate exists" {
  let root = @path_utils.join_path(TEST_ROOT, "harness/runtime-atomics")
  let harness_dir = @path_utils.join_path(root, "harness")
  write_text(@path_utils.join_path(harness_dir, "sta.js"), "")
  write_text(@path_utils.join_path(harness_dir, "assert.js"), "")
  let harness = load_harness(
    root,
    [],
    false,
    harness_options=HarnessOptions(
      atomics_timeout_profile=ATOMICS_TIMEOUT_PROFILE_SHORT,
    ),
  )
  let script = (
      #|let captured = [];
      #|const native_wait_async = Atomics.waitAsync;
      #|const has_native_wait_async = typeof native_wait_async === 'function';
      #|if (has_native_wait_async) {
      #|  Atomics.waitAsync = function(typedArray, index, value, timeout) {
      #|    captured.push(timeout);
      #|    return native_wait_async(typedArray, index, value, timeout);
      #|  };
      #|} else {
      #|  console.log('native-waitAsync-unavailable');
      #|}
    ) +
    harness +
    (
      #|if (has_native_wait_async) {
      #|  const ta = new Int32Array(new SharedArrayBuffer(4));
      #|  Atomics.waitAsync(ta, 0, 0, 200);
      #|  Atomics.waitAsync(ta, 0, 0, "foo");
      #|  Atomics.waitAsync(ta, 0, 0, undefined);
      #|  Atomics.waitAsync(ta, 0, 0, -1);
      #|  console.log(captured.join(','));
      #|}
    )
  match run_node_script(script) {
    None => inspect(true, content="true")
    Some(capture) => {
      inspect(capture.code, content="0")
      if capture.stdout.contains("native-waitAsync-unavailable") {
        inspect(true, content="true")
      } else {
        inspect(capture.stdout.trim(), content="100,100,100,-1")
      }
    }
  }
}

///|
async test "atomics short timeout wrapper passes coerced timeouts for waitAsync with injected fallback delegate" {
  let root = @path_utils.join_path(TEST_ROOT, "harness/runtime-atomics")
  let harness_dir = @path_utils.join_path(root, "harness")
  write_text(@path_utils.join_path(harness_dir, "sta.js"), "")
  write_text(@path_utils.join_path(harness_dir, "assert.js"), "")
  let harness = load_harness(
    root,
    [],
    false,
    harness_options=HarnessOptions(
      atomics_timeout_profile=ATOMICS_TIMEOUT_PROFILE_SHORT,
    ),
  )
  let script = (
      #|let captured = [];
      #|Atomics.waitAsync = function(_typedArray, _index, _value, timeout) {
      #|  captured.push(timeout);
      #|  return { value: timeout };
      #|};
    ) +
    harness +
    (
      #|const ta = new Int32Array(new SharedArrayBuffer(4));
      #|Atomics.waitAsync(ta, 0, 0, 200);
      #|Atomics.waitAsync(ta, 0, 0, "foo");
      #|Atomics.waitAsync(ta, 0, 0, undefined);
      #|Atomics.waitAsync(ta, 0, 0, -1);
      #|console.log(captured.join(','));
    )
  match run_node_script(script) {
    None => inspect(true, content="true")
    Some(capture) => {
      inspect(capture.code, content="0")
      inspect(capture.stdout.trim(), content="100,100,100,-1")
    }
  }
}

///|
test "relative_path only returns dot for equal normalized paths" {
  let base = @path_utils.absolute_path(
    @path_utils.join_path(TEST_ROOT, "relative"),
  )
  inspect(@path_utils.relative_path(base, base), content=".")

  let other = @path_utils.relative_path(
    @path_utils.join_path(base, "child"),
    @path_utils.join_path(base, "sibling"),
  )
  inspect(other, content="../child")
}

///|
test "harness helpers and module fixture resolution are shadow-compatible" {
  let root = @path_utils.join_path(TEST_ROOT, "harness/test262")
  let harness_dir = @path_utils.join_path(root, "harness")
  write_text(@path_utils.join_path(harness_dir, "sta.js"), "// sta\n")
  write_text(@path_utils.join_path(harness_dir, "assert.js"), "// assert\n")
  write_text(
    @path_utils.join_path(harness_dir, "regExpUtils.js"),
    REGEXP_UTILS_BUILD_STRING,
  )

  let default_harness = load_harness(root, ["regExpUtils.js"], false)
  inspect(default_harness.contains("$262.codePointRange"), content="false")
  let modified_harness = load_harness(
    root,
    ["regExpUtils.js"],
    false,
    harness_options=HarnessOptions(helpers=[HELPER_CODE_POINT_RANGE]),
  )
  inspect(modified_harness.contains("function print"), content="true")
  inspect(modified_harness.contains("$262.codePointRange"), content="true")
  inspect(
    modified_harness.contains("result += $262.codePointRange(start, end);"),
    content="true",
  )

  let test_dir = @path_utils.join_path(root, "test/language/module")
  let main = @path_utils.join_path(test_dir, "main.js")
  let from_fixture = @path_utils.join_path(test_dir, "from_FIXTURE.js")
  let import_fixture = @path_utils.join_path(test_dir, "import_FIXTURE.js")
  let nested = @path_utils.join_path(test_dir, "nested_FIXTURE.js")
  write_text(
    main, "import {value} from './from_FIXTURE.js';\nimport './import_FIXTURE.js';\n",
  )
  write_text(from_fixture, "import './nested_FIXTURE.js';\n")
  write_text(import_fixture, "export const value = 1;\n")
  write_text(nested, "export const nested = 2;\n")
  json_inspect(resolve_fixtures(main, @fs.read_file_to_string(main)), content=[
    ("./nested_FIXTURE.js", "export const nested = 2;\n"),
    ("./from_FIXTURE.js", "import './nested_FIXTURE.js';\n"),
    ("./import_FIXTURE.js", "export const value = 1;\n"),
  ])
}

///|
async test "run_single_test preserves external subprocess status semantics" {
  let root = @path_utils.join_path(TEST_ROOT, "execute/test262")
  let harness_dir = @path_utils.join_path(root, "harness")
  write_text(@path_utils.join_path(harness_dir, "sta.js"), "")
  write_text(@path_utils.join_path(harness_dir, "assert.js"), "")
  let engine = @path_utils.join_path(TEST_ROOT, "execute/fake_engine.sh")
  write_text(
    engine,
    (
      #|last=""
      #|while [ "$#" -gt 0 ]; do
      #|  last="$1"
      #|  shift
      #|done
      #|case "$last" in
      #|  *BODY_ASYNC_COMPLETE*) echo 'Test262:AsyncTestComplete'; exit 0 ;;
      #|  *BODY_ASYNC_FAIL*) echo 'Test262:AsyncTestFailure:bad async'; exit 0 ;;
      #|  *BODY_CRLF_ERROR*) printf 'TypeError: boom\r\n' 1>&2; exit 1 ;;
      #|  *THROW_TYPE*) echo 'TypeError: boom'; exit 1 ;;
      #|  *FAIL_ENGINE*) echo 'Error: boom'; exit 1 ;;
      #|  *) exit 0 ;;
      #|esac
    ),
  )
  let test_dir = @path_utils.join_path(root, "test/language")
  let pass_test = @path_utils.join_path(test_dir, "pass.js")
  let fail_test = @path_utils.join_path(test_dir, "fail.js")
  let negative_test = @path_utils.join_path(test_dir, "negative.js")
  let async_pass_test = @path_utils.join_path(test_dir, "async-pass.js")
  let async_fail_test = @path_utils.join_path(test_dir, "async-fail.js")
  let crlf_error_test = @path_utils.join_path(test_dir, "crlf-error.js")
  let null_test = @path_utils.join_path(test_dir, "null-byte.js")
  write_test_file(pass_test, body="PASS_ENGINE")
  write_test_file(fail_test, body="FAIL_ENGINE")
  write_test_file(
    negative_test,
    frontmatter=(
      #|negative:
      #|  phase: runtime
      #|  type: TypeError
    ),
    body="THROW_TYPE",
  )
  write_test_file(
    async_pass_test,
    frontmatter="flags: [async]",
    body="BODY_ASYNC_COMPLETE",
  )
  write_test_file(
    async_fail_test,
    frontmatter="flags: [async]",
    body="BODY_ASYNC_FAIL",
  )
  write_test_file(crlf_error_test, body="BODY_CRLF_ERROR")
  let null_source = StringBuilder()
  null_source.write_string("const payload = \"")
  null_source.write_char(Int::unsafe_to_char(0))
  null_source.write_string("\";\n")
  write_text(null_test, null_source.to_string())
  let metadata = @metadata.load_skip_metadata(root=".")
  let engine_cmd = ["sh", engine]
  let pass_result = run_single_test(
    engine_cmd,
    root,
    pass_test,
    2,
    skip_metadata=metadata,
  )
  let fail_result = run_single_test(
    engine_cmd,
    root,
    fail_test,
    2,
    skip_metadata=metadata,
  )
  let negative_result = run_single_test(
    engine_cmd,
    root,
    negative_test,
    2,
    skip_metadata=metadata,
  )
  let async_pass_result = run_single_test(
    engine_cmd,
    root,
    async_pass_test,
    2,
    skip_metadata=metadata,
  )
  let async_fail_result = run_single_test(
    engine_cmd,
    root,
    async_fail_test,
    2,
    skip_metadata=metadata,
  )
  let crlf_error_result = run_single_test(
    engine_cmd,
    root,
    crlf_error_test,
    2,
    skip_metadata=metadata,
  )
  let null_result = run_single_test(
    engine_cmd,
    root,
    null_test,
    2,
    skip_metadata=metadata,
  )
  json_inspect(
    [
      pass_result.status,
      fail_result.status,
      negative_result.status,
      async_pass_result.status,
      async_fail_result.status,
      crlf_error_result.status,
      null_result.status,
    ],
    content=["pass", "fail", "pass", "pass", "fail", "fail", "error"],
  )
  inspect(async_fail_result.reason, content="bad async")
  inspect(crlf_error_result.reason, content="TypeError: boom")
  inspect(null_result.reason, content="embedded null byte")

  let progress_log = @path_utils.join_path(TEST_ROOT, "execute/progress.jsonl")
  let merged_log = @path_utils.join_path(TEST_ROOT, "execute/merged.jsonl")
  initialize_result_logs(progress_log, merged_log)
  write_result_logs(progress_log, merged_log, pass_result)
  write_result_logs(progress_log, merged_log, fail_result)
  let progress_text = @fs.read_file_to_string(progress_log)
  let merged_text = @fs.read_file_to_string(merged_log)
  inspect(progress_text.split("\n").count(), content="3")
  inspect(progress_text.contains("\"status\":\"pass\""), content="true")
  inspect(progress_text.contains("\"status\":\"fail\""), content="true")
  inspect(merged_text.contains("\"status\":\"pass\""), content="false")
  inspect(merged_text.contains("\"status\":\"fail\""), content="true")

  let empty_merged_log = @path_utils.join_path(
    TEST_ROOT,
    "execute/empty-merged.jsonl",
  )
  initialize_result_logs("", empty_merged_log)
  inspect(@fs.path_exists(empty_merged_log), content="true")
  inspect(@fs.read_file_to_string(empty_merged_log), content="")

  let bad_merged_log = @path_utils.join_path(
    TEST_ROOT,
    "execute/merged-log-dir",
  )
  ensure_dir(bad_merged_log)
  try {
    initialize_result_logs("", bad_merged_log)
    abort("expected merged log initialization failure")
  } catch {
    _ => ()
  }
}

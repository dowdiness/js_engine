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

  let test262_root = join_path(TEST_ROOT, "selection/test262")
  let test_dir = join_path(test262_root, "test/language")
  let normal = join_path(test_dir, "normal.js")
  let raw = join_path(test_dir, "raw.js")
  let module_test = join_path(test_dir, "module.js")
  let only_strict = join_path(test_dir, "only-strict.js")
  let no_strict = join_path(test_dir, "no-strict.js")
  let missing = join_path(test_dir, "missing.js")
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

  let tests_file = join_path(TEST_ROOT, "selection/tests.txt")
  write_text(
    tests_file, "# comment\nlanguage/normal.js\n test/language/raw.js # inline\n",
  )
  json_inspect(load_tests_file(tests_file, test262_root), content=[
    absolute_path(normal),
    absolute_path(raw),
  ])
}

///|
test "resume keys and artifact schema fields match the contract" {
  let root = join_path(TEST_ROOT, "resume/test262")
  let test_root = join_path(root, "test")
  let results_file = join_path(TEST_ROOT, "resume/results.json")
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
    (join_path(test_root, "language/add.js"), "strict"),
    (join_path(test_root, "language/add.js"), "non-strict"),
    (join_path(test_root, "language/if.js"), "strict"),
  ]
  json_inspect(filter_completed_tasks(tasks, completed, test262_dir=root), content=[
    (join_path(test_root, "language/if.js"), "strict"),
  ])

  let results = [
    TestResult(
      path=join_path(test_root, "language/expressions/pass.js"),
      status="pass",
      mode="strict",
    ),
    TestResult(
      path=join_path(test_root, "language/expressions/fail.js"),
      status="fail",
      reason="boom",
      mode="non-strict",
    ),
    TestResult(
      path=join_path(test_root, "language/expressions/skip.js"),
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
test "harness helpers and module fixture resolution are shadow-compatible" {
  let root = join_path(TEST_ROOT, "harness/test262")
  let harness_dir = join_path(root, "harness")
  write_text(join_path(harness_dir, "sta.js"), "// sta\n")
  write_text(join_path(harness_dir, "assert.js"), "// assert\n")
  write_text(
    join_path(harness_dir, "regExpUtils.js"),
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

  let test_dir = join_path(root, "test/language/module")
  let main = join_path(test_dir, "main.js")
  let dep = join_path(test_dir, "dep.js")
  let nested = join_path(test_dir, "nested.js")
  write_text(main, "import './dep.js';\nimport './main.js';\n")
  write_text(dep, "import './nested.js';\n")
  write_text(nested, "export const value = 1;\n")
  json_inspect(resolve_fixtures(main, @fs.read_file_to_string(main)), content=[
    ("./nested.js", "export const value = 1;\n"),
    ("./dep.js", "import './nested.js';\n"),
  ])
}

///|
async test "run_single_test preserves external subprocess status semantics" {
  let root = join_path(TEST_ROOT, "execute/test262")
  let harness_dir = join_path(root, "harness")
  write_text(join_path(harness_dir, "sta.js"), "")
  write_text(join_path(harness_dir, "assert.js"), "")
  let engine = join_path(TEST_ROOT, "execute/fake_engine.sh")
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
      #|  *THROW_TYPE*) echo 'TypeError: boom'; exit 1 ;;
      #|  *FAIL_ENGINE*) echo 'Error: boom'; exit 1 ;;
      #|  *) exit 0 ;;
      #|esac
    ),
  )
  let test_dir = join_path(root, "test/language")
  let pass_test = join_path(test_dir, "pass.js")
  let fail_test = join_path(test_dir, "fail.js")
  let negative_test = join_path(test_dir, "negative.js")
  let async_pass_test = join_path(test_dir, "async-pass.js")
  let async_fail_test = join_path(test_dir, "async-fail.js")
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
  json_inspect(
    [
      pass_result.status,
      fail_result.status,
      negative_result.status,
      async_pass_result.status,
      async_fail_result.status,
    ],
    content=["pass", "fail", "pass", "pass", "fail"],
  )
  inspect(async_fail_result.reason, content="bad async")

  let progress_log = join_path(TEST_ROOT, "execute/progress.jsonl")
  let merged_log = join_path(TEST_ROOT, "execute/merged.jsonl")
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
}

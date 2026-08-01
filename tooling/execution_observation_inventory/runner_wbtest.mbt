///|
#borrow(target, link)
extern "c" fn create_runner_test_symlink(target : Bytes, link : Bytes) -> Int = "moonbit_execution_observation_inventory_create_symlink"

///|
fn ensure_runner_test_dir(path : String) -> Unit raise {
  if !@fs.path_exists(path) {
    @fs.create_dir(path)
  }
}

///|
fn write_runner_test_file(
  root : String,
  relative_path : String,
  content : String,
) -> Unit raise {
  let path = @path_utils.join_path(root, relative_path)
  match relative_path.rev_find("/") {
    Some(index) => {
      let dir = @path_utils.join_path(root, relative_path[:index].to_owned())
      let parts = @path_utils.path_components(dir)
      let mut current = ""
      for part in parts {
        current = if current == "" {
          part
        } else {
          @path_utils.join_path(current, part)
        }
        ensure_runner_test_dir(current)
      }
    }
    None => ()
  }
  @fs.write_string_to_file(path, content)
}

///|
fn runner_test_manifest(reference : String) -> String {
  six_family_manifest(
    "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"statement\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"" +
    reference +
    "\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}",
  )
}

///|
test "runner rejects missing evidence path" {
  let root = "_build/execution-observation-inventory-missing-path-test"
  ensure_runner_test_dir("_build")
  ensure_runner_test_dir(root)
  write_runner_test_file(root, "fixture.mbt", "anchor")
  write_runner_test_file(
    root,
    "scripts/execution_observation_inventory.json",
    runner_test_manifest("missing.mbt#anchor"),
  )
  let (_stdout_lines, stderr_lines, code) = run(root~)
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line.contains("path does not exist")))
}

///|
test "runner rejects missing evidence anchor" {
  let root = "_build/execution-observation-inventory-missing-anchor-test"
  ensure_runner_test_dir("_build")
  ensure_runner_test_dir(root)
  write_runner_test_file(root, "fixture.mbt", "anchor")
  write_runner_test_file(
    root,
    "scripts/execution_observation_inventory.json",
    runner_test_manifest("fixture.mbt#missing"),
  )
  let (_stdout_lines, stderr_lines, code) = run(root~)
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line.contains("anchor not found")))
}

///|
test "runner rejects absolute evidence references before reading them" {
  let root = "_build/execution-observation-inventory-absolute-reference-test"
  ensure_runner_test_dir("_build")
  ensure_runner_test_dir(root)
  write_runner_test_file(root, "fixture.mbt", "anchor")
  let absolute_reference = @path_utils.absolute_path(
      @path_utils.join_path(root, "fixture.mbt"),
    ) +
    "#anchor"
  write_runner_test_file(
    root,
    "scripts/execution_observation_inventory.json",
    runner_test_manifest(absolute_reference),
  )
  let (_stdout_lines, stderr_lines, code) = run(root~)
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line.contains("repository-relative")))
}

///|
test "runner rejects parent traversal evidence references before reading them" {
  let root = "_build/execution-observation-inventory-parent-reference-test/root"
  ensure_runner_test_dir("_build")
  ensure_runner_test_dir(
    "_build/execution-observation-inventory-parent-reference-test",
  )
  ensure_runner_test_dir(root)
  let outside = @path_utils.join_path(root, "../outside.mbt")
  @fs.write_string_to_file(outside, "anchor")
  write_runner_test_file(
    root,
    "scripts/execution_observation_inventory.json",
    runner_test_manifest("../outside.mbt#anchor"),
  )
  let (_stdout_lines, stderr_lines, code) = run(root~)
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line.contains("repository-relative")))
}

///|
test "runner rejects symlink evidence that escapes repository root" {
  let root = "_build/execution-observation-inventory-symlink-escape-test/root"
  let parent = "_build/execution-observation-inventory-symlink-escape-test"
  let outside = @path_utils.join_path(parent, "outside.mbt")
  let link = @path_utils.join_path(root, "fixture.mbt")
  ensure_runner_test_dir("_build")
  ensure_runner_test_dir(parent)
  ensure_runner_test_dir(root)
  @fs.write_string_to_file(outside, "anchor")
  assert_eq(
    create_runner_test_symlink(
      @utf8.encode(@path_utils.absolute_path(outside)),
      @utf8.encode(@path_utils.absolute_path(link)),
    ),
    0,
  )
  write_runner_test_file(
    root,
    "scripts/execution_observation_inventory.json",
    runner_test_manifest("fixture.mbt#anchor"),
  )
  let (_stdout_lines, stderr_lines, code) = run(root~)
  assert_eq(code, 1)
  assert_true(
    stderr_lines.any(line => line.contains("escapes repository root")),
  )
}

///|
test "runner accepts in-root evidence file" {
  let root = "_build/execution-observation-inventory-in-root-evidence-test"
  ensure_runner_test_dir("_build")
  ensure_runner_test_dir(root)
  write_runner_test_file(root, "fixture.mbt", "anchor")
  write_runner_test_file(
    root,
    "scripts/execution_observation_inventory.json",
    runner_test_manifest("fixture.mbt#anchor"),
  )
  let (stdout_lines, stderr_lines, code) = run(root~)
  assert_eq(code, 0)
  assert_eq(stderr_lines, [])
  assert_eq(stdout_lines, ["ok: execution observation inventory is valid"])
}

///|
test "runner reports missing manifest as structured failure" {
  let root = "_build/execution-observation-inventory-missing-manifest-test"
  ensure_runner_test_dir("_build")
  ensure_runner_test_dir(root)
  let (_stdout_lines, stderr_lines, code) = run(root~)
  assert_eq(code, 1)
  assert_eq(stderr_lines[0:2], [
    "execution observation inventory failed:", "- inventory manifest could not be read",
  ])
}

///|
test "runner validates seeded root" {
  let (stdout_lines, stderr_lines, code) = run(root=".")
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_eq(stdout_lines, ["ok: execution observation inventory is valid"])
}

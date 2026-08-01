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
test "runner validates seeded root" {
  let (stdout_lines, stderr_lines, code) = run(root=".")
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_eq(stdout_lines, ["ok: execution observation inventory is valid"])
}

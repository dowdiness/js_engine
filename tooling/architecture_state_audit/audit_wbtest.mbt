///|
fn ensure_dir(path : String) -> Unit raise {
  if !@fs.path_exists(path) {
    @fs.create_dir(path)
  }
}

///|
fn write_mbt(root : String, rel_path : String, content : String) -> Unit raise {
  let path = join_path(root, rel_path)
  match rel_path.rev_find("/") {
    Some(index) => {
      let dir = join_path(root, rel_path[:index].to_owned())
      let parts = dir.split("/").map(part => part.to_owned()).to_array()
      let mut current = ""
      for part in parts {
        if part != "" {
          current = if current == "" { part } else { join_path(current, part) }
          ensure_dir(current)
        }
      }
    }
    None => ()
  }
  @fs.write_string_to_file(path, content)
}

///|
test "is_mutable_type recognizes wrapped mutable constructors" {
  assert_true(is_mutable_type("Ref[Int]"))
  assert_true(is_mutable_type("@ref.Ref[Int]"))
  assert_true(is_mutable_type("Ref[@runtime.Value]"))
  assert_true(is_mutable_type("Map[String, @ast.Expr]"))
  assert_true(is_mutable_type("@immut/hashmap.Map[String, Int]"))
  assert_true(is_mutable_type("@immut/hashmap.Map[String, @ast.Expr]"))
  assert_true(is_mutable_type("@array.Array[Int]"))
  assert_true(is_mutable_type("Option[Ref[Int]]"))
  assert_true(is_mutable_type("Result[Array[Int], String]"))
  assert_true(is_mutable_type("Option[@ref.Ref[Int]]"))
  assert_false(is_mutable_type("String"))
  assert_false(is_mutable_type("Arrayish[Int]"))
}

///|
test "discover_mutable_bindings matches Python guardrail cases" {
  let root = "_build/architecture-state-audit-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbt(
    root,
    "interpreter/runtime/qualified.mbt",
    [
      "let cache : @ref.Ref[Int] = { val: 0 }", "pub let table : @immut/hashmap.Map[String, Int] = {}",
      "pub(all) let public_cache : Ref[Int] = { val: 0 }", "let exprs : Map[String, @ast.Expr] = {}",
      "let current : Ref[@runtime.Value] = { val: @runtime.Undefined }", "let optional_ref : Option[Ref[Int]] = None",
      "let result_array : Result[Array[Int], String] = Ok([])", "let wrapped : Map[",
      "  String,", "  @runtime.Value,", "] = {}", "let fixed : Int = 1",
    ].join("\n"),
  )
  write_mbt(root, "interpreter/stdlib/unannotated.mbt", "let cache = [0]\n")

  let bindings = discover_mutable_bindings(root)
  let found : Map[String, MutableBinding] = {}
  for binding in bindings {
    found[binding.key] = binding
  }

  assert_eq(found.length(), 9)
  assert_true(found.contains("interpreter/runtime/qualified.mbt:cache"))
  assert_true(found.contains("interpreter/runtime/qualified.mbt:table"))
  assert_true(found.contains("interpreter/runtime/qualified.mbt:public_cache"))
  assert_true(found.contains("interpreter/runtime/qualified.mbt:exprs"))
  assert_true(found.contains("interpreter/runtime/qualified.mbt:current"))
  assert_true(found.contains("interpreter/runtime/qualified.mbt:optional_ref"))
  assert_true(found.contains("interpreter/runtime/qualified.mbt:result_array"))
  assert_true(found.contains("interpreter/runtime/qualified.mbt:wrapped"))
  assert_true(found.contains("interpreter/stdlib/unannotated.mbt:cache"))

  guard found.get("interpreter/runtime/qualified.mbt:cache") is Some(cache) else {
    fail("missing cache")
  }
  assert_eq(cache.type_name, "@ref.Ref[Int]")
  assert_false(cache.is_unannotated)

  guard found.get("interpreter/runtime/qualified.mbt:table") is Some(table) else {
    fail("missing table")
  }
  assert_true(table.is_public)

  guard found.get("interpreter/runtime/qualified.mbt:public_cache")
    is Some(public_cache) else {
    fail("missing public_cache")
  }
  assert_true(public_cache.is_public)

  guard found.get("interpreter/runtime/qualified.mbt:wrapped") is Some(wrapped) else {
    fail("missing wrapped")
  }
  assert_eq(wrapped.line, 8)
  assert_true(is_mutable_type(wrapped.type_name))

  guard found.get("interpreter/stdlib/unannotated.mbt:cache")
    is Some(unannotated) else {
    fail("missing unannotated cache")
  }
  assert_true(unannotated.is_unannotated)
}

///|
test "classified mutable state is read from shared JSON metadata" {
  let root = "_build/architecture-state-audit-classified-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbt(
    root, "interpreter/runtime/classified.mbt", "let retained : Ref[Int] = { val: 0 }\n",
  )
  write_mbt(
    root, "scripts/architecture_state_classified_mutable_state.json", "{\"interpreter/runtime/classified.mbt:retained\":\"retained for test\"}",
  )

  let (stdout_lines, stderr_lines, code) = run(root~, list=true)
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_eq(stdout_lines.length(), 2)
  assert_eq(
    stdout_lines[0],
    "interpreter/runtime/classified.mbt:1: retained: Ref[Int] -- retained for test",
  )
  assert_eq(
    stdout_lines[1],
    "ok: runtime/stdlib module-level mutable state matches the Stage 0 migration inventory (1 classified bindings)",
  )
}

///|
test "failure diagnostics are separated from list inventory" {
  let root = "_build/architecture-state-audit-failure-stream-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbt(
    root, "interpreter/runtime/unclassified.mbt", "let retained : Ref[Int] = { val: 0 }\n",
  )

  let (stdout_lines, stderr_lines, code) = run(root~, list=true)
  assert_eq(code, 1)
  assert_eq(stdout_lines.length(), 1)
  assert_eq(
    stdout_lines[0],
    "interpreter/runtime/unclassified.mbt:1: retained: Ref[Int] -- UNCLASSIFIED",
  )
  assert_true(stderr_lines.length() > 0)
  assert_eq(stderr_lines[0], "architecture state audit failed:")
}

///|
test "stale classified entries fail the audit" {
  let root = "_build/architecture-state-audit-stale-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbt(
    root, "scripts/architecture_state_classified_mutable_state.json", "{\"interpreter/runtime/missing.mbt:retained\":\"stale for test\"}",
  )

  let (_stdout_lines, stderr_lines, code) = run(root~, list=false)
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line == "stale classified entries:"))
  assert_true(
    stderr_lines.any(line => {
      line == "- interpreter/runtime/missing.mbt:retained"
    }),
  )
}

///|
fn base_representation_json(allowlisted : String) -> String {
  let prefix =
    #|{
    #|  "version": 1,
    #|  "scan_roots": ["compiler", "interpreter/stdlib"],
    #|  "ignore_globs": ["**/*_test.mbt", "**/*_wbtest.mbt", "**/pkg.generated.mbti"],
    #|  "representation_patterns": [
    #|    {
    #|      "id": "runtime-object-constructor",
    #|      "pattern": "Object(",
    #|      "kind": "constructor",
    #|      "reason": "object representation constructor"
    #|    },
    #|    {
    #|      "id": "representation-bag-field",
    #|      "pattern": ".bag",
    #|      "kind": "field",
    #|      "reason": "property bag field access"
    #|    }
    #|  ],
    #|  "allowlisted_access": [
  let suffix =
    #|
    #|  ]
    #|}
    #|
  prefix + allowlisted + suffix
}

///|
fn representation_debt_json(
  pattern_id : String,
  allowed_count : Int,
  fingerprint : String,
  reason : String,
) -> String {
  let prefix =
    #|    {
    #|      "path": "compiler/bytecode.mbt",
    #|      "pattern_id": "
  let middle =
    #|",
    #|      "allowed_count":
  let suffix =
    #|,
    #|      "fingerprint": "
  let after_fingerprint =
    #|",
    #|      "owner": "compiler runtime operation migration",
    #|      "retire_by_stage": "Stage 7-8",
    #|      "reason": "
  let end =
    #|"
    #|    }
  prefix +
  pattern_id +
  middle +
  allowed_count.to_string() +
  suffix +
  fingerprint +
  after_fingerprint +
  reason +
  end
}

///|
test "representation access debt is allowlisted and listable" {
  let root = "_build/architecture-representation-audit-pass-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn sample(v : Value) -> Unit {
    #|  match v {
    #|    Object(data) => data.bag.properties["x"] = Undefined
    #|    _ => ()
    #|  }
    #|}
    #|
  write_file(root, "compiler/bytecode.mbt", source)
  let object_debt = representation_debt_json(
    "runtime-object-constructor",
    1,
    representation_fingerprint([
      "Object(:Object(data) => data.bag.properties[\"x\"] = Undefined",
    ]),
    "test object debt",
  )
  let bag_debt = representation_debt_json(
    "representation-bag-field",
    1,
    representation_fingerprint([
      ".bag:Object(data) => data.bag.properties[\"x\"] = Undefined",
    ]),
    "test bag debt",
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(object_debt + ",\n" + bag_debt),
  )

  let (stdout_lines, stderr_lines, code) = run_representation_access(
    root~,
    list_representation=true,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_true(
    stdout_lines.any(line => {
      line.contains(
        "compiler/bytecode.mbt:3 [compiler] runtime-object-constructor: Object( -- DEBT Stage 7-8 (owner: compiler runtime operation migration): test object debt",
      )
    }),
  )
  assert_true(
    stdout_lines.any(line => {
      line.contains(
        "compiler/bytecode.mbt:3 [compiler] representation-bag-field: .bag -- DEBT Stage 7-8 (owner: compiler runtime operation migration): test bag debt",
      )
    }),
  )
  assert_eq(
    stdout_lines[stdout_lines.length() - 1],
    "ok: architecture representation access matches inventory (2 classified accesses)",
  )
}

///|
test "new compiler representation access fails" {
  let root = "_build/architecture-representation-audit-new-access-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn sample(v : Value) -> Unit {
    #|  match v {
    #|    Object(data) => ignore(data)
    #|    _ => ()
    #|  }
    #|}
    #|
  write_file(root, "compiler/bytecode.mbt", source)
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(""),
  )

  let (_stdout_lines, stderr_lines, code) = run_representation_access(
    root~,
    list_representation=false,
  )
  assert_eq(code, 1)
  assert_true(
    stderr_lines.any(line => line == "unclassified representation access:"),
  )
  assert_true(
    stderr_lines.any(line => {
      line ==
      "- compiler/bytecode.mbt:3 [compiler] runtime-object-constructor: Object("
    }),
  )
}

///|
test "allowlisted representation count does not hide new access" {
  let root = "_build/architecture-representation-audit-count-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn sample(a : Value, b : Value) -> Unit {
    #|  match a { Object(data) => ignore(data); _ => () }
    #|  match b { Object(data) => ignore(data); _ => () }
    #|}
    #|
  write_file(root, "compiler/bytecode.mbt", source)
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(
      representation_debt_json(
        "runtime-object-constructor",
        1,
        representation_fingerprint([
          "Object(:match a { Object(data) => ignore(data); _ => () }",
        ]),
        "one existing object access",
      ),
    ),
  )

  let (_stdout_lines, stderr_lines, code) = run_representation_access(
    root~,
    list_representation=false,
  )
  assert_eq(code, 1)
  assert_true(
    stderr_lines.any(line => line == "unclassified representation access:"),
  )
  assert_true(
    stderr_lines.any(line => {
      line ==
      "- compiler/bytecode.mbt:3 [compiler] runtime-object-constructor: Object("
    }),
  )
}

///|
test "changed representation access with same count fails" {
  let root = "_build/architecture-representation-audit-fingerprint-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn sample(v : Value) -> Unit {
    #|  match v {
    #|    Object(changed) => ignore(changed)
    #|    _ => ()
    #|  }
    #|}
    #|
  write_file(root, "compiler/bytecode.mbt", source)
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(
      representation_debt_json(
        "runtime-object-constructor",
        1,
        representation_fingerprint(["Object(:Object(data) => ignore(data)"]),
        "old object access",
      ),
    ),
  )

  let (_stdout_lines, stderr_lines, code) = run_representation_access(
    root~,
    list_representation=false,
  )
  assert_eq(code, 1)
  assert_true(
    stderr_lines.any(line => line == "unclassified representation access:"),
  )
  assert_true(stderr_lines.any(line => line == "stale allowlist entries:"))
  assert_true(
    stderr_lines.any(line => {
      line.contains(
        "- compiler/bytecode.mbt:runtime-object-constructor expected 1/",
      ) &&
      line.contains("found 1/")
    }),
  )
}

///|
test "stale representation allowlist fails" {
  let root = "_build/architecture-representation-audit-stale-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  write_file(root, "compiler/bytecode.mbt", "fn sample { () }\n")
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(
      representation_debt_json(
        "runtime-object-constructor",
        1,
        representation_fingerprint(["Object(:Object(data) => ignore(data)"]),
        "stale object access",
      ),
    ),
  )

  let (_stdout_lines, stderr_lines, code) = run_representation_access(
    root~,
    list_representation=false,
  )
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line == "stale allowlist entries:"))
  assert_true(
    stderr_lines.any(line => {
      line.contains(
        "- compiler/bytecode.mbt:runtime-object-constructor expected 1/",
      ) &&
      line.contains("found 0/none")
    }),
  )
}

///|
test "representation scanner ignores tests and string literals" {
  let root = "_build/architecture-representation-audit-ignore-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  write_file(root, "compiler/bytecode.mbt", "let text = \"Object(data).bag\"\n")
  write_file(root, "compiler/bytecode_test.mbt", "Object(data) => data.bag\n")
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(""),
  )

  let (stdout_lines, stderr_lines, code) = run_representation_access(
    root~,
    list_representation=true,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_eq(
    stdout_lines[stdout_lines.length() - 1],
    "ok: architecture representation access matches inventory (0 classified accesses)",
  )
}

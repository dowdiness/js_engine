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
    #|      "id": "runtime-map-constructor",
    #|      "pattern": "Map(",
    #|      "kind": "constructor",
    #|      "reason": "map representation constructor"
    #|    },
    #|    {
    #|      "id": "representation-bag-field",
    #|      "pattern": ".bag",
    #|      "kind": "field",
    #|      "reason": "property bag field access"
    #|    },
    #|    {
    #|      "id": "bytecode-vm-interpreter-edge",
    #|      "pattern": "interp.",
    #|      "paths": ["compiler/bytecode_vm.mbt"],
    #|      "kind": "guest-capable VM runtime edge",
    #|      "reason": "raw interpreter capability access in bytecode dispatch requires typed edge classification"
    #|    },
    #|    {
    #|      "id": "bytecode-vm-runtime-edge",
    #|      "pattern": "@runtime.",
    #|      "paths": ["compiler/bytecode_vm.mbt"],
    #|      "kind": "guest-capable VM runtime edge",
    #|      "reason": "raw runtime capability access in bytecode dispatch requires typed edge classification"
    #|    },
    #|    {
    #|      "id": "bytecode-vm-runtime-import",
    #|      "pattern": "using @runtime",
    #|      "paths": ["compiler/bytecode_vm.mbt"],
    #|      "kind": "guest-capable VM runtime import",
    #|      "reason": "unqualified runtime capability import in bytecode dispatch requires typed edge classification"
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
fn bytecode_vm_interpreter_edge_debt_json(
  allowed_count : Int,
  fingerprint : String,
) -> String {
  let prefix =
    #|    {
    #|      "path": "compiler/bytecode_vm.mbt",
    #|      "pattern_id": "bytecode-vm-interpreter-edge",
    #|      "allowed_count":
  let suffix =
    #|,
    #|      "fingerprint": "
  let after_fingerprint =
    #|",
    #|      "owner": "bytecode activation eligibility inventory",
    #|      "retire_by_stage": "Stage 7-12",
    #|      "reason": "raw VM interpreter edges remain evidence until each guest-capable path has an explicit managed seam or typed unsupported disposition"
    #|    }
    #|
  prefix + allowed_count.to_string() + suffix + fingerprint + after_fingerprint
}

///|
fn bytecode_vm_runtime_edge_debt_json(
  allowed_count : Int,
  fingerprint : String,
) -> String {
  let prefix =
    #|    {
    #|      "path": "compiler/bytecode_vm.mbt",
    #|      "pattern_id": "bytecode-vm-runtime-edge",
    #|      "allowed_count":
  let suffix =
    #|,
    #|      "fingerprint": "
  let after_fingerprint =
    #|",
    #|      "owner": "bytecode activation eligibility inventory",
    #|      "retire_by_stage": "Stage 7-12",
    #|      "reason": "raw VM runtime edges remain evidence until each guest-capable path has an explicit managed seam or typed unsupported disposition"
    #|    }
    #|
  prefix + allowed_count.to_string() + suffix + fingerprint + after_fingerprint
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
test "empty core map literal is not representation access" {
  let root = "_build/architecture-representation-audit-empty-map-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn sample(data : Value) -> Unit {
    #|  let values : Map[String, Int] = Map([])
    #|  let runtime_value = Map(data)
    #|  ignore((values, runtime_value))
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
    stderr_lines.any(line => {
      line ==
      "- compiler/bytecode.mbt:3 [compiler] runtime-map-constructor: Map("
    }),
  )
  assert_false(
    stderr_lines.any(line => line.contains("compiler/bytecode.mbt:2")),
  )
}

///|
test "inline block comment does not hide new representation access" {
  let root = "_build/architecture-representation-audit-inline-comment-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn sample(data : Value) -> Unit {
    #|  let v = /* TODO */ Object(data)
    #|  ignore(v)
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
      "- compiler/bytecode.mbt:2 [compiler] runtime-object-constructor: Object("
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

///|
test "bytecode VM interpreter edge fingerprint is accepted" {
  let root = "_build/architecture-representation-audit-bytecode-vm-pass-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  write_file(
    root, "compiler/other.mbt", "fn unrelated(interp : Interpreter) -> Unit { interp.unrelated() }\n",
  )
  let source =
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  interp.get_property()
    #|  interp.spread_iterable()
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
  let debt = bytecode_vm_interpreter_edge_debt_json(
    2,
    representation_fingerprint([
      "interp.:interp.get_property()", "interp.:interp.spread_iterable()",
    ]),
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(debt),
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
        "compiler/bytecode_vm.mbt:2 [compiler] bytecode-vm-interpreter-edge: interp. -- DEBT",
      )
    }),
  )
  assert_eq(
    stdout_lines[stdout_lines.length() - 1],
    "ok: architecture representation access matches inventory (2 classified accesses)",
  )
}

///|
test "new bytecode VM interpreter edge fails fingerprint audit" {
  let root = "_build/architecture-representation-audit-bytecode-vm-new-edge-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  interp.get_property()
    #|  interp.new_guest_helper()
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
  let debt = bytecode_vm_interpreter_edge_debt_json(
    2,
    representation_fingerprint([
      "interp.:interp.get_property()", "interp.:interp.spread_iterable()",
    ]),
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(debt),
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
      line.contains(
        "- compiler/bytecode_vm.mbt:3 [compiler] bytecode-vm-interpreter-edge: interp.",
      )
    }),
  )
  assert_true(stderr_lines.any(line => line == "stale allowlist entries:"))
}

///|
test "newline-separated bytecode VM interpreter edge fails audit" {
  let root = "_build/architecture-representation-audit-bytecode-vm-newline-edge-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  interp
    #|    .new_guest_helper()
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
  let debt = bytecode_vm_interpreter_edge_debt_json(
    1,
    representation_fingerprint(["interp.:interp.existing_guest_helper()"]),
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(debt),
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
      line.contains(
        "- compiler/bytecode_vm.mbt:2 [compiler] bytecode-vm-interpreter-edge: interp.",
      )
    }),
  )
}

///|
test "comment-separated bytecode VM interpreter edge fails audit" {
  let root = "_build/architecture-representation-audit-bytecode-vm-comment-edge-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  interp/* comment */.new_guest_helper()
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
  let debt = bytecode_vm_interpreter_edge_debt_json(
    1,
    representation_fingerprint(["interp.:interp.existing_guest_helper()"]),
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(debt),
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
      line.contains(
        "- compiler/bytecode_vm.mbt:2 [compiler] bytecode-vm-interpreter-edge: interp.",
      )
    }),
  )
}

///|
test "whitespace-separated bytecode VM interpreter edge fails audit" {
  let root = "_build/architecture-representation-audit-bytecode-vm-whitespace-edge-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  interp    .new_guest_helper()
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
  let debt = bytecode_vm_interpreter_edge_debt_json(
    1,
    representation_fingerprint(["interp.:interp.existing_guest_helper()"]),
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(debt),
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
      line.contains(
        "- compiler/bytecode_vm.mbt:2 [compiler] bytecode-vm-interpreter-edge: interp.",
      )
    }),
  )
}

///|
test "bytecode VM runtime edge fingerprint is accepted" {
  let root = "_build/architecture-representation-audit-bytecode-vm-runtime-pass-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  write_file(
    root, "compiler/other.mbt", "fn unrelated(interp : Interpreter) -> Unit { @runtime.unrelated(interp) }\n",
  )
  let source =
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  @runtime.get_property(interp)
    #|  @runtime.spread_iterable(interp)
    #|  let text = "@runtime.string_literal()"
    #|  // @runtime.comment_only(interp)
    #|  ignore(text)
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
  let debt = bytecode_vm_runtime_edge_debt_json(
    2,
    representation_fingerprint([
      "@runtime.:@runtime.get_property(interp)", "@runtime.:@runtime.spread_iterable(interp)",
    ]),
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(debt),
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
        "compiler/bytecode_vm.mbt:2 [compiler] bytecode-vm-runtime-edge: @runtime. -- DEBT",
      )
    }),
  )
  assert_eq(
    stdout_lines[stdout_lines.length() - 1],
    "ok: architecture representation access matches inventory (2 classified accesses)",
  )
}

///|
test "new bytecode VM runtime edge fails fingerprint audit" {
  let root = "_build/architecture-representation-audit-bytecode-vm-runtime-new-edge-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  @runtime.get_property(interp)
    #|  @runtime/* split comment */.new_guest_helper(interp)
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
  let debt = bytecode_vm_runtime_edge_debt_json(
    2,
    representation_fingerprint([
      "@runtime.:@runtime.get_property(interp)", "@runtime.:@runtime.spread_iterable(interp)",
    ]),
  )
  write_file(
    root,
    "scripts/architecture_representation_access.json",
    base_representation_json(debt),
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
      line.contains(
        "- compiler/bytecode_vm.mbt:3 [compiler] bytecode-vm-runtime-edge: @runtime.",
      )
    }),
  )
  assert_true(stderr_lines.any(line => line == "stale allowlist entries:"))
}

///|
test "bytecode VM runtime import baseline ignores unrelated sources" {
  let root = "_build/architecture-representation-audit-bytecode-vm-runtime-import-pass-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  write_file(
    root, "compiler/other.mbt", "using @runtime { type Value }\nfn unrelated(value : Value) -> Unit { ignore(value) }\n",
  )
  let source =
    #|fn dispatch() -> Unit {
    #|  let text = "using @runtime { type Hidden }"
    #|  // using @runtime { type CommentOnly }
    #|  ignore(text)
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
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

///|
test "new bytecode VM runtime import fails audit" {
  let root = "_build/architecture-representation-audit-bytecode-vm-runtime-import-new-edge-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|using @runtime { type Value }
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  eval_binary_op(interp)
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
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
      line.contains(
        "- compiler/bytecode_vm.mbt:1 [compiler] bytecode-vm-runtime-import: using @runtime",
      )
    }),
  )
}

///|
test "split bytecode VM runtime import fails audit" {
  let root = "_build/architecture-representation-audit-bytecode-vm-runtime-import-split-edge-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_file(root, "interpreter/stdlib/empty.mbt", "")
  let source =
    #|using
    #|  /* split declaration */
    #|  @runtime { type Value }
    #|fn dispatch(interp : Interpreter) -> Unit {
    #|  eval_binary_op(interp)
    #|}
    #|
  write_file(root, "compiler/bytecode_vm.mbt", source)
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
      line.contains(
        "- compiler/bytecode_vm.mbt:1 [compiler] bytecode-vm-runtime-import: using @runtime",
      )
    }),
  )
}

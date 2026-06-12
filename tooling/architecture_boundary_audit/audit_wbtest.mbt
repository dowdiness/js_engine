///|
fn ensure_dir(path : String) -> Unit raise {
  if !@fs.path_exists(path) {
    @fs.create_dir(path)
  }
}

///|
fn ensure_parent_dirs(root : String, rel_path : String) -> Unit raise {
  match rel_path.rev_find("/") {
    Some(index) => {
      let dir = rel_path[:index].to_owned()
      let parts = dir.split("/").map(part => part.to_owned()).to_array()
      let mut current = root
      for part in parts {
        if part != "" {
          current = join_path(current, part)
          ensure_dir(current)
        }
      }
    }
    None => ()
  }
}

///|
fn write_file(root : String, rel_path : String, content : String) -> Unit raise {
  ensure_parent_dirs(root, rel_path)
  @fs.write_string_to_file(join_path(root, rel_path), content)
}

///|
fn write_module_header(root : String) -> Unit raise {
  let content =
    #|name = "example/engine"
    #|
    #|version = "0.0.0"
    #|
  write_file(root, "moon.mod", content)
}

///|
fn base_rules_json(allowed : String, debt : String) -> String {
  let prefix =
    #|{
    #|  "version": 1,
    #|  "package_groups": [
    #|    { "name": "frontend-core", "packages": ["token", "parser"] },
    #|    { "name": "runtime", "packages": ["interpreter/runtime"] },
    #|    { "name": "compiler", "packages": ["compiler"] },
    #|    { "name": "external", "packages": ["moonbitlang/*"] }
    #|  ],
    #|  "allowed_imports": [
  let middle =
    #|
    #|  ],
    #|  "allowlisted_import_debt": [
  let suffix =
    #|
    #|  ]
    #|}
    #|
  prefix + allowed + middle + debt + suffix
}

///|
fn parser_token_allowed_json() -> String {
  let content =
    #|    {
    #|      "from": "parser",
    #|      "to": "token",
    #|      "scope": "prod",
    #|      "reason": "parser consumes token definitions"
    #|    }
  content
}

///|
fn runtime_parser_debt_json() -> String {
  let content =
    #|    {
    #|      "from": "interpreter/runtime",
    #|      "to": "parser",
    #|      "scope": "prod",
    #|      "owner": "static-semantics extraction",
    #|      "retire_by_stage": "Stage 4-6",
    #|      "reason": "runtime still parses source before preparation exists"
    #|    }
  content
}

///|
fn compiler_parser_test_allowed_json() -> String {
  let content =
    #|    {
    #|      "from": "compiler",
    #|      "to": "parser",
    #|      "scope": "test",
    #|      "reason": "compiler tests parse fixtures"
    #|    }
  content
}

///|
test "scope detection ignores trailing comments" {
  assert_eq(scope_from_import_close(" // \"test\""), "prod")
  assert_eq(scope_from_import_close(" /* \"wbtest\" */"), "prod")
  assert_eq(scope_from_import_close(" for \"test\" // \"wbtest\""), "test")
  assert_eq(scope_from_import_close(" for \"wbtest\" /* \"test\" */"), "wbtest")
}

///|
test "current import debt is allowlisted and listable" {
  let root = "_build/architecture-boundary-audit-pass-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  write_file(root, "token/moon.pkg", "")
  let parser_pkg =
    #|import {
    #|  "example/engine/token",
    #|}
    #|
  write_file(root, "parser/moon.pkg", parser_pkg)
  let runtime_pkg =
    #|import {
    #|  "example/engine/parser",
    #|}
    #|
  write_file(root, "interpreter/runtime/moon.pkg", runtime_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json(parser_token_allowed_json(), runtime_parser_debt_json()),
  )

  let (stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=true,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_true(
    stdout_lines.any(line => {
      line ==
      "parser -> token [prod] -- allowed: parser consumes token definitions"
    }),
  )
  assert_true(
    stdout_lines.any(line => {
      line ==
      "interpreter/runtime -> parser [prod] -- DEBT Stage 4-6: runtime still parses source before preparation exists"
    }),
  )
  assert_eq(
    stdout_lines[stdout_lines.length() - 1],
    "ok: architecture import boundaries match rules (2 imports, 1 allowlisted debts)",
  )
}

///|
test "forbidden production import fails" {
  let root = "_build/architecture-boundary-audit-forbidden-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  write_file(root, "interpreter/runtime/moon.pkg", "")
  let parser_pkg =
    #|import {
    #|  "example/engine/interpreter/runtime",
    #|}
    #|
  write_file(root, "parser/moon.pkg", parser_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", ""),
  )

  let (_stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=false,
  )
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line == "unclassified imports:"))
  assert_true(
    stderr_lines.any(line => {
      line == "- parser/moon.pkg: parser -> interpreter/runtime [prod]"
    }),
  )
}

///|
test "classified external imports are ignored" {
  let root = "_build/architecture-boundary-audit-external-pass-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  let parser_pkg =
    #|import {
    #|  "moonbitlang/core/string",
    #|}
    #|
  write_file(root, "parser/moon.pkg", parser_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", ""),
  )

  let (stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=true,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_true(
    stdout_lines.any(line => {
      line ==
      "parser -> moonbitlang/core/string [prod] -- ignored: external dependency"
    }),
  )
}

///|
test "unclassified external imports fail" {
  let root = "_build/architecture-boundary-audit-external-fail-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  let parser_pkg =
    #|import {
    #|  "someorg/internal",
    #|}
    #|
  write_file(root, "parser/moon.pkg", parser_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", ""),
  )

  let (_stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=false,
  )
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line == "unclassified imports:"))
  assert_true(
    stderr_lines.any(line => {
      line == "- parser/moon.pkg: parser -> someorg/internal [prod]"
    }),
  )
}

///|
test "runtime to stdlib production import fails" {
  let root = "_build/architecture-boundary-audit-runtime-stdlib-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  write_file(root, "interpreter/stdlib/moon.pkg", "")
  let runtime_pkg =
    #|import {
    #|  "example/engine/interpreter/stdlib",
    #|}
    #|
  write_file(root, "interpreter/runtime/moon.pkg", runtime_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", ""),
  )

  let (_stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=false,
  )
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line == "unclassified imports:"))
  assert_true(
    stderr_lines.any(line => {
      line ==
      "- interpreter/runtime/moon.pkg: interpreter/runtime -> interpreter/stdlib [prod]"
    }),
  )
}

///|
test "commented-out imports do not satisfy allowlisted debt" {
  let root = "_build/architecture-boundary-audit-commented-debt-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  let runtime_pkg =
    #|import {
    #|  // "example/engine/parser",
    #|}
    #|
  write_file(root, "interpreter/runtime/moon.pkg", runtime_pkg)
  write_file(root, "parser/moon.pkg", "")
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", runtime_parser_debt_json()),
  )

  let (_stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=false,
  )
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line == "stale allowlist entries:"))
  assert_true(
    stderr_lines.any(line => line == "- interpreter/runtime -> parser [prod]"),
  )
}

///|
test "commented-out forbidden imports are ignored" {
  let root = "_build/architecture-boundary-audit-commented-forbidden-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  let parser_pkg =
    #|import {
    #|  // "example/engine/interpreter/runtime",
    #|}
    #|
  write_file(root, "parser/moon.pkg", parser_pkg)
  write_file(root, "interpreter/runtime/moon.pkg", "")
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", ""),
  )

  let (_stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=false,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
}

///|
test "stale allowlisted import debt fails" {
  let root = "_build/architecture-boundary-audit-stale-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  write_file(root, "interpreter/runtime/moon.pkg", "")
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", runtime_parser_debt_json()),
  )

  let (_stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=false,
  )
  assert_eq(code, 1)
  assert_true(stderr_lines.any(line => line == "stale allowlist entries:"))
  assert_true(
    stderr_lines.any(line => line == "- interpreter/runtime -> parser [prod]"),
  )
}

///|
test "trailing comments do not reclassify production import scope" {
  let root = "_build/architecture-boundary-audit-scope-comment-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  write_file(root, "parser/moon.pkg", "")
  let compiler_pkg =
    #|import { "example/engine/parser" } // used only by "test"
    #|
  write_file(root, "compiler/moon.pkg", compiler_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json(compiler_parser_test_allowed_json(), ""),
  )

  let (stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=true,
  )
  assert_eq(code, 1)
  assert_true(
    stdout_lines.any(line => line == "compiler -> parser [prod] -- UNCLASSIFIED"),
  )
  assert_true(stderr_lines.any(line => line == "unclassified imports:"))
}

///|
test "nested generated directories are skipped" {
  let root = "_build/architecture-boundary-audit-nested-build-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  let generated_pkg =
    #|import {
    #|  "example/engine/interpreter/runtime",
    #|}
    #|
  write_file(root, "tooling/_build/generated/moon.pkg", generated_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json("", ""),
  )

  let (_stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=false,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
}

///|
test "test-only allow rule does not mask production import" {
  let root = "_build/architecture-boundary-audit-scope-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_module_header(root)
  write_file(root, "parser/moon.pkg", "")
  let compiler_pkg =
    #|import { "example/engine/parser" }
    #|
    #|import { "example/engine/parser" } for "test"
    #|
  write_file(root, "compiler/moon.pkg", compiler_pkg)
  write_file(
    root,
    "scripts/architecture_boundary_rules.json",
    base_rules_json(compiler_parser_test_allowed_json(), ""),
  )

  let (stdout_lines, stderr_lines, code) = run_import_boundary(
    root~,
    list_imports=true,
  )
  assert_eq(code, 1)
  assert_true(
    stdout_lines.any(line => {
      line ==
      "compiler -> parser [test] -- allowed: compiler tests parse fixtures"
    }),
  )
  assert_true(
    stdout_lines.any(line => line == "compiler -> parser [prod] -- UNCLASSIFIED"),
  )
  assert_true(stderr_lines.any(line => line == "unclassified imports:"))
}

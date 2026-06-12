///|
fn write_mbti(
  root : String,
  rel_dir : String,
  pkg_name : String,
  body : String,
) -> Unit raise {
  let content = "// Generated using `moon info`, DON'T EDIT IT\npackage \"\{pkg_name}\"\n\n// Values\n\{body}\n// Errors\n\n// Types and methods\n\n// Type aliases\n\n// Traits\n"
  let rel_path = if rel_dir == "." {
    "pkg.generated.mbti"
  } else {
    "\{rel_dir}/pkg.generated.mbti"
  }
  write_file(root, rel_path, content)
}

///|
fn base_taxonomy_json(defaults : String, overrides : String) -> String {
  let prefix =
    #|{
    #|  "version": 1,
    #|  "package_defaults": [
  let middle =
    #|
    #|  ],
    #|  "symbol_overrides": [
  let suffix =
    #|
    #|  ]
    #|}
    #|
  prefix + defaults + middle + overrides + suffix
}

///|
test "extract_mbti_symbol extracts fn names" {
  assert_true(extract_mbti_symbol("pub fn run(String) -> Unit") == Some("run"))
  assert_true(
    extract_mbti_symbol(
      "pub fn new_interpreter(annex_b? : Bool) -> @runtime.Interpreter",
    ) ==
    Some("new_interpreter"),
  )
  assert_true(
    extract_mbti_symbol(
      "pub fn BytecodeProgram::run(Self, @runtime.Interpreter) -> @runtime.Value raise",
    ) ==
    Some("BytecodeProgram::run"),
  )
}

///|
test "extract_mbti_symbol extracts generic fn names" {
  assert_true(
    extract_mbti_symbol("pub fn[T] Box::Box(value : T) -> Box[T]") ==
    Some("Box::Box"),
  )
}

///|
test "extract_mbti_symbol extracts type names" {
  assert_true(extract_mbti_symbol("pub(all) enum LexForm {") == Some("LexForm"))
  assert_true(extract_mbti_symbol("pub(all) struct Token {") == Some("Token"))
  assert_true(
    extract_mbti_symbol("pub struct BenchResult {") == Some("BenchResult"),
  )
  assert_true(
    extract_mbti_symbol("pub(all) suberror JsError {") == Some("JsError"),
  )
}

///|
test "extract_mbti_symbol extracts const names" {
  assert_true(
    extract_mbti_symbol("pub const FIBONACCI_SRC : String = \"...\"") ==
    Some("FIBONACCI_SRC"),
  )
}

///|
test "extract_mbti_symbol skips impl and using lines" {
  assert_true(extract_mbti_symbol("pub impl Show for LexForm") == None)
  assert_true(
    extract_mbti_symbol("pub using @runtime {type Environment}") == None,
  )
  assert_true(extract_mbti_symbol("pub(all) impl Show for Token") == None)
}

///|
test "extract_mbti_symbol skips non-pub lines" {
  assert_true(extract_mbti_symbol("// Values") == None)
  assert_true(extract_mbti_symbol("  kind : TokenKind") == None)
  assert_true(extract_mbti_symbol("") == None)
}

///|
test "parse_mbti extracts package name and symbols" {
  let source =
    #|// Generated using `moon info`, DON'T EDIT IT
    #|package "dowdiness/js_engine"
    #|
    #|// Values
    #|pub fn run(String, annex_b? : Bool) -> (Array[String], String) raise
    #|pub fn run_module(String, annex_b? : Bool) -> (Array[String], Map[String, @runtime.Value]) raise
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|
    #|// Type aliases
    #|
    #|// Traits
    #|
  let (pkg, symbols) = parse_mbti(source)
  assert_eq(pkg, "dowdiness/js_engine")
  assert_eq(symbols.length(), 2)
  assert_true(symbols.any(fn(s) { s == "run" }))
  assert_true(symbols.any(fn(s) { s == "run_module" }))
}

///|
test "taxonomy_pkg_matches supports wildcard suffix" {
  assert_true(
    taxonomy_pkg_matches(
      "dowdiness/js_engine/cmd/*", "dowdiness/js_engine/cmd/main",
    ),
  )
  assert_true(
    taxonomy_pkg_matches(
      "dowdiness/js_engine/cmd/*", "dowdiness/js_engine/cmd/test262_runner",
    ),
  )
  assert_false(
    taxonomy_pkg_matches(
      "dowdiness/js_engine/cmd/*", "dowdiness/js_engine/interpreter/runtime",
    ),
  )
  assert_true(
    taxonomy_pkg_matches(
      "dowdiness/js_engine/compiler", "dowdiness/js_engine/compiler",
    ),
  )
}

///|
test "classify_symbol uses override over default" {
  let rules : TaxonomyRules = {
    package_defaults: [
      { pkg: "example/pkg", category: "internal_api", reason: "default reason" },
    ],
    symbol_overrides: [
      {
        pkg: "example/pkg",
        symbol: "run",
        category: "stable_user_facade",
        reason: "override reason",
      },
    ],
  }
  assert_true(
    classify_symbol("example/pkg", "run", rules) ==
    ClassifiedOverride("stable_user_facade", "override reason"),
  )
  assert_true(
    classify_symbol("example/pkg", "other", rules) ==
    ClassifiedDefault("internal_api", "default reason"),
  )
}

///|
test "classify_symbol returns Unclassified with no default and no override" {
  let rules : TaxonomyRules = { package_defaults: [], symbol_overrides: [] }
  assert_true(classify_symbol("example/pkg", "run", rules) == Unclassified)
}

///|
test "current repo surface taxonomy passes" {
  let (stdout_lines, stderr_lines, code) = run_surface_taxonomy(
    root=".",
    list_surfaces=false,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_true(
    stdout_lines.any(fn(line) {
      line.has_prefix(
        "ok: architecture surface taxonomy covers generated interfaces",
      )
    }),
  )
}

///|
test "new root facade symbol fails until categorized" {
  let root = "_build/surface-taxonomy-unclassified-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbti(
    root, ".", "example/engine", "pub fn run(String) -> Unit\npub fn run_new_mode(String) -> Unit\n",
  )
  let overrides =
    #|    { "package": "example/engine", "symbol": "run", "category": "stable_user_facade", "reason": "entry point" }
  write_file(
    root,
    "scripts/architecture_surface_taxonomy.json",
    base_taxonomy_json("", overrides),
  )

  let (_stdout, stderr_lines, code) = run_surface_taxonomy(
    root~,
    list_surfaces=false,
  )
  assert_eq(code, 1)
  assert_true(
    stderr_lines.any(fn(line) { line == "unclassified public surfaces:" }),
  )
  assert_true(
    stderr_lines.any(fn(line) {
      line == "- package example/engine: run_new_mode"
    }),
  )
}

///|
test "stale symbol override fails" {
  let root = "_build/surface-taxonomy-stale-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbti(root, ".", "example/engine", "pub fn run(String) -> Unit\n")
  let overrides =
    #|    { "package": "example/engine", "symbol": "run", "category": "stable_user_facade", "reason": "entry point" },
    #|    { "package": "example/engine", "symbol": "removed_fn", "category": "stable_user_facade", "reason": "was an entry point" }
  write_file(
    root,
    "scripts/architecture_surface_taxonomy.json",
    base_taxonomy_json("", overrides),
  )

  let (_stdout, stderr_lines, code) = run_surface_taxonomy(
    root~,
    list_surfaces=false,
  )
  assert_eq(code, 1)
  assert_true(stderr_lines.any(fn(line) { line == "stale symbol overrides:" }))
  assert_true(
    stderr_lines.any(fn(line) { line == "- package example/engine: removed_fn" }),
  )
}

///|
test "package default covers symbols without requiring overrides" {
  let root = "_build/surface-taxonomy-default-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbti(
    root, "interpreter/runtime", "example/engine/interpreter/runtime", "pub fn new_interpreter() -> Interpreter\npub struct Interpreter { // private fields }\n",
  )
  let defaults =
    #|    { "package": "example/engine/interpreter/runtime", "category": "internal_api", "reason": "runtime internals" }
  write_file(
    root,
    "scripts/architecture_surface_taxonomy.json",
    base_taxonomy_json(defaults, ""),
  )

  let (stdout_lines, stderr_lines, code) = run_surface_taxonomy(
    root~,
    list_surfaces=false,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_true(
    stdout_lines.any(fn(line) {
      line.contains("1 packages") &&
      line.contains("2 symbols") &&
      line.contains("1 package-defaulted")
    }),
  )
}

///|
test "list surfaces shows all classifications" {
  let root = "_build/surface-taxonomy-list-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbti(root, ".", "example/engine", "pub fn run(String) -> Unit\n")
  write_mbti(
    root, "interpreter/runtime", "example/engine/interpreter/runtime", "pub fn new_interpreter() -> Interpreter\n",
  )
  let defaults =
    #|    { "package": "example/engine/interpreter/runtime", "category": "internal_api", "reason": "runtime internals" }
  let overrides =
    #|    { "package": "example/engine", "symbol": "run", "category": "stable_user_facade", "reason": "entry point" }
  write_file(
    root,
    "scripts/architecture_surface_taxonomy.json",
    base_taxonomy_json(defaults, overrides),
  )

  let (stdout_lines, _stderr_lines, code) = run_surface_taxonomy(
    root~,
    list_surfaces=true,
  )
  assert_eq(code, 0)
  assert_true(
    stdout_lines.any(fn(line) {
      line == "example/engine: run -- stable_user_facade (override)"
    }),
  )
  assert_true(
    stdout_lines.any(fn(line) {
      line ==
      "example/engine/interpreter/runtime: new_interpreter -- internal_api (package default)"
    }),
  )
}

///|
test "wildcard package default matches cmd packages" {
  let root = "_build/surface-taxonomy-wildcard-test-\{@env.now()}"
  ensure_dir("_build")
  ensure_dir(root)
  write_mbti(
    root, "cmd/runner", "example/engine/cmd/runner", "pub fn main() -> Unit\n",
  )
  let defaults =
    #|    { "package": "example/engine/cmd/*", "category": "benchmark_tooling_hook", "reason": "cmd packages" }
  write_file(
    root,
    "scripts/architecture_surface_taxonomy.json",
    base_taxonomy_json(defaults, ""),
  )

  let (stdout_lines, stderr_lines, code) = run_surface_taxonomy(
    root~,
    list_surfaces=false,
  )
  assert_eq(code, 0)
  assert_eq(stderr_lines.length(), 0)
  assert_true(
    stdout_lines.any(fn(line) {
      line.contains("1 packages") && line.contains("1 symbols")
    }),
  )
}

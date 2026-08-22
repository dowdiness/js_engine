///|
fn module_test_stmt(source : String) -> @ast.Stmt raise Error {
  @parser.parse(source).stmts[0]
}

///|
fn nest_module_stmt_lists(stmt : @ast.Stmt, depth : Int) -> @ast.Stmt {
  let loc = @token.Loc::default()
  let mut nested = stmt
  for _ in 0..<depth {
    nested = @ast.Stmt::StmtList([nested], loc)
  }
  nested
}

///|
fn module_test_record(stmts : Array[@ast.Stmt]) -> ModuleRunRecord {
  { specifier: "./main", stmts, exports: Map([]), env: Environment::new() }
}

///|
fn module_test_record_at(
  specifier : String,
  stmts : Array[@ast.Stmt],
) -> ModuleRunRecord {
  { specifier, stmts, exports: Map([]), env: Environment::new() }
}

///|
fn deep_exported_destructure(depth : Int) -> @ast.Stmt {
  let loc = @token.Loc::default()
  let mut pattern = @ast.Pattern::IdentPat("deep_name")
  for _ in 0..<depth {
    pattern = @ast.Pattern::DefaultPat(pattern, @ast.Expr::UndefinedLit(loc))
  }
  @ast.Stmt::ExportNamedDecl(
    Some(
      @ast.Stmt::DestructureDecl(
        LetKind,
        pattern,
        @ast.Expr::UndefinedLit(loc),
        loc,
      ),
    ),
    [],
    None,
    LexNormal,
    loc,
  )
}

///|
test "Task 6A: deep exported destructuring uses stack-safe BoundNames metadata" {
  let exported = deep_exported_destructure(4096)
  let decl = match exported {
    ExportNamedDecl(Some(decl), _, _, _, _) => decl
    _ => fail("export")
  }
  let interp = Interpreter::new()
  interp.extract_export_names(decl)
  json_inspect(interp.module_export_bindings, content=[
    ["deep_name", "deep_name"],
  ])
  interp.predeclare_decl_exports(decl, Environment::new())
  assert_true(interp.module_exports.contains("deep_name"))
  let names : Array[String] = []
  collect_module_direct_export_names_from_stmt(
    exported,
    names,
    Default::default(),
  )
  json_inspect(names, content=["deep_name"])
  assert_eq(
    module_direct_export_binding_name_from_stmt(
      module_test_record([exported]),
      exported,
      "deep_name",
    ),
    Some("deep_name"),
  )
}

///|
test "Task 6A: export wrapper is opaque but declaration payload carrier flattens" {
  let loc = @token.Loc::default()
  let payload = @ast.Stmt::StmtList(
    [module_test_stmt("let first = 1;"), module_test_stmt("let second = 2;")],
    loc,
  )
  let wrapper = @ast.Stmt::ExportNamedDecl(
    Some(payload),
    [],
    None,
    LexNormal,
    loc,
  )
  let flattened = flatten_module_stmt_carriers(wrapper)
  assert_eq(flattened.length(), 1)
  assert_true(flattened[0] is ExportNamedDecl(_))
  let names : Array[String] = []
  collect_module_direct_export_names_from_stmt(
    wrapper,
    names,
    Default::default(),
  )
  json_inspect(names, content=["first", "second"])
}

///|
test "Task 6A: synthetic statement carrier keeps direct indirect star precedence" {
  let interp = Interpreter::new()
  let direct = module_test_record(
    @parser.parse(
      "export const chosen = 1; export { chosen } from './indirect'; export * from './star';",
    ).stmts,
  )
  direct.exports["chosen"] = Number(1.0)
  let indirect = module_test_record(
    @parser.parse(
      "export { chosen } from './indirect'; export * from './star';",
    ).stmts,
  )
  let star_only = module_test_record(
    @parser.parse("export * from './star';").stmts,
  )
  let indirect_source = module_test_record_at(
    "./indirect",
    @parser.parse("export const chosen = 2;").stmts,
  )
  indirect_source.exports["chosen"] = Number(2.0)
  let star_source = module_test_record_at(
    "./star",
    @parser.parse("export const chosen = 3;").stmts,
  )
  star_source.exports["chosen"] = Number(3.0)
  let records : Map[String, ModuleRunRecord] = Map([])
  records["./indirect"] = indirect_source
  records["./star"] = star_source
  let resolved_direct = interp.resolve_module_export(
    direct,
    "chosen",
    records,
    Default::default(),
  )
  let resolved_indirect = interp.resolve_module_export(
    indirect,
    "chosen",
    records,
    Default::default(),
  )
  let resolved_star = interp.resolve_module_export(
    star_only,
    "chosen",
    records,
    Default::default(),
  )
  inspect(
    match resolved_direct {
      Resolved(result) => result.module_specifier
      _ => "missing"
    },
    content="./main",
  )
  inspect(
    match resolved_indirect {
      Resolved(result) => result.module_specifier
      _ => "missing"
    },
    content="./indirect",
  )
  inspect(
    match resolved_star {
      Resolved(result) => result.module_specifier
      _ => "missing"
    },
    content="./star",
  )
}

///|
test "Task 6A: deep module dependency carriers preserve source order and duplicates" {
  let nested = nest_module_stmt_lists(
    @ast.Stmt::StmtList(
      [
        module_test_stmt("import './first';"),
        module_test_stmt("export { x } from './named';"),
        module_test_stmt("export * from './star';"),
        module_test_stmt("import './first';"),
      ],
      @token.Loc::default(),
    ),
    4096,
  )
  json_inspect(module_test_record([nested]).dependency_edges(), content=[
    ["./first", true],
    ["./named", false],
    ["./star", false],
    ["./first", true],
  ])
}

///|
test "Task 6A: deep direct and star export collectors preserve duplicate policy" {
  let nested = nest_module_stmt_lists(
    @ast.Stmt::StmtList(
      [
        module_test_stmt("export const first = 1;"),
        module_test_stmt("export { first as alias, first as alias };"),
        module_test_stmt("export * from './star-a';"),
        module_test_stmt("export * from './star-a';"),
      ],
      @token.Loc::default(),
    ),
    4096,
  )
  let names : Array[String] = []
  collect_module_direct_export_names_from_stmt(
    nested,
    names,
    Default::default(),
  )
  json_inspect(names, content=["first", "alias"])
  json_inspect(module_test_record([nested]).star_sources(), content=[
    "./star-a", "./star-a",
  ])
}

///|
test "Task 6A: deep declaration carriers append all names in source order" {
  let interp = Interpreter::new()
  let first = module_test_stmt("let first = 1;")
  let duplicate = module_test_stmt("let first = 2;")
  let last = module_test_stmt("class Last {}")
  interp.extract_export_names(
    nest_module_stmt_lists(
      @ast.Stmt::StmtList([first, duplicate, last], @token.Loc::default()),
      4096,
    ),
  )
  json_inspect(interp.module_export_bindings, content=[
    ["first", "first"],
    ["first", "first"],
    ["Last", "Last"],
  ])
}

///|
fn module_dependency_chain(
  length : Int,
) -> Map[String, ModuleRunRecord] raise Error {
  let records : Map[String, ModuleRunRecord] = Map([])
  let import_stmt = module_test_stmt("import './next';")
  for i in 0..<length {
    let specifier = i.to_string()
    let stmts = if i + 1 < length {
      [
        match import_stmt {
          ImportDecl(a, b, c, _, d, e) =>
            @ast.Stmt::ImportDecl(a, b, c, (i + 1).to_string(), d, e)
          _ => fail("import")
        },
      ]
    } else {
      []
    }
    records[specifier] = module_test_record_at(specifier, stmts)
  }
  records
}

///|
test "Task 6B: dependency walker handles a 4096-record chain in exact postorder" {
  let length = 4096
  let records = module_dependency_chain(length)
  let order : Array[String] = []
  let state : Map[String, Int] = Map([])
  Interpreter::new().visit_module_dependencies_first(
    records["0"],
    records,
    state,
    (_, record) => order.push(record.specifier),
  )
  assert_eq(order.length(), length)
  for i in 0..<length {
    assert_eq(order[i], (length - i - 1).to_string())
    assert_eq(state[(length - i - 1).to_string()], 2)
  }
}

///|
test "Task 6B: dependency path search handles deep true false and shared seen cases" {
  let length = 4096
  let records = module_dependency_chain(length)
  assert_false(
    module_dependency_path_exists("0", "missing", records, Default::default()),
  )
  let seen : @set.Set[String] = Default::default()
  assert_true(module_dependency_path_exists("0", "4095", records, seen))
  assert_true(seen.contains("0"))
  assert_true(seen.contains("4094"))
  assert_false(module_dependency_path_exists("0", "missing", records, seen))
  assert_true(module_dependency_path_exists("same", "same", records, seen))
  assert_false(module_dependency_path_exists("absent", "target", records, seen))
  assert_true(seen.contains("absent"))
}

///|
test "Task 6B: weak re-export ring visits each record once in established order" {
  let records : Map[String, ModuleRunRecord] = Map([])
  records["a"] = module_test_record_at(
    "a",
    @parser.parse("export * from 'b';").stmts,
  )
  records["b"] = module_test_record_at(
    "b",
    @parser.parse("export * from 'c';").stmts,
  )
  records["c"] = module_test_record_at(
    "c",
    @parser.parse("export * from 'a';").stmts,
  )
  let order : Array[String] = []
  let state : Map[String, Int] = Map([])
  let interp = Interpreter::new()
  for specifier in ["a", "b", "c"] {
    interp.visit_module_dependencies_first(records[specifier], records, state, (
      _,
      record,
    ) => order.push(record.specifier))
  }
  json_inspect(order, content=["a", "b", "c"])
}

///|
test "Task 6B: missing dependencies are ignored and action errors leave visiting state" {
  let missing = module_test_record_at(
    "main",
    @parser.parse("import 'absent';").stmts,
  )
  let records : Map[String, ModuleRunRecord] = Map([("main", missing)])
  let state : Map[String, Int] = Map([])
  let result : Result[Unit, Error] = Ok(
    Interpreter::new().visit_module_dependencies_first(
      missing,
      records,
      state,
      (_, _) => raise @errors.TypeError(message="stop"),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
  assert_eq(state["main"], 1)
}

///|
test "Task 6A: deep import and direct export lookups keep first match" {
  let imports = nest_module_stmt_lists(
    @ast.Stmt::StmtList(
      [
        module_test_stmt("import { first as chosen } from './first';"),
        module_test_stmt("import { second as chosen } from './second';"),
      ],
      @token.Loc::default(),
    ),
    4096,
  )
  let import_result = match module_import_target_from_stmt(imports, "chosen") {
    Some(ImportedBinding(source, name)) => source + ":" + name
    Some(ImportedNamespace(source)) => source + ":*"
    None => "missing"
  }
  inspect(import_result, content="./first:first")
  let parsed_exports = @parser.parse(
      "let first = 1; export { first as chosen }; let second = 2; export { second as chosen };",
    ).stmts
  let exports = nest_module_stmt_lists(
    @ast.Stmt::StmtList(
      [parsed_exports[1], parsed_exports[3]],
      @token.Loc::default(),
    ),
    4096,
  )
  assert_eq(
    module_direct_export_binding_name_from_stmt(
      module_test_record(parsed_exports),
      exports,
      "chosen",
    ),
    Some("first"),
  )
}

///|
test "Task 6A: deep named re-export keeps original missing diagnostic location" {
  let interp = Interpreter::new()
  interp.register_module("./missing", Map([]))
  let reexport = module_test_stmt("\n\nexport { absent } from './missing';")
  let nested = nest_module_stmt_lists(reexport, 4096)
  let result : Result[Unit, Error] = Ok(
    interp.instantiate_indirect_exports_from_stmt(nested, Map([])),
  ) catch {
    error => Err(error)
  }
  debug_inspect(
    result,
    content="Err(SyntaxError(message=\"Module './missing' does not export 'absent' at line 3, col 24\"))",
  )
}

///|
fn module_resolution_chain(
  length : Int,
  kind : String,
) -> Map[String, ModuleRunRecord] raise Error {
  let records : Map[String, ModuleRunRecord] = Map([])
  let explicit = module_test_stmt("export { x } from 'next';")
  let imported = @parser.parse(
      "import { x as local } from 'next'; export { local as x };",
    ).stmts
  let star = module_test_stmt("export * from 'next';")
  for i in 0..<length {
    let specifier = i.to_string()
    if i + 1 == length {
      let record = module_test_record_at(
        specifier,
        @parser.parse("export const x = 1;").stmts,
      )
      record.exports["x"] = Number(1.0)
      records[specifier] = record
    } else {
      let next = (i + 1).to_string()
      let stmts = match kind {
        "explicit" =>
          match explicit {
            ExportNamedDecl(a, b, _, d, e) =>
              [@ast.Stmt::ExportNamedDecl(a, b, Some(next), d, e)]
            _ => fail("explicit")
          }
        "imported" => {
          let import_stmt = match imported[0] {
            ImportDecl(a, b, c, _, e, f) =>
              @ast.Stmt::ImportDecl(a, b, c, next, e, f)
            _ => fail("import")
          }
          [import_stmt, imported[1]]
        }
        _ =>
          match star {
            ExportAllDecl(a, _, c, d) =>
              [@ast.Stmt::ExportAllDecl(a, next, c, d)]
            _ => fail("star")
          }
      }
      records[specifier] = module_test_record_at(specifier, stmts)
    }
  }
  records
}

///|
fn assert_deep_module_resolution(
  result : ModuleExportResolution,
  leaf : String,
) -> Unit raise Error {
  match result {
    Resolved(resolved) => {
      assert_true(resolved.value is Number(1.0))
      assert_eq(resolved.module_specifier, leaf)
      assert_eq(resolved.binding_name, "x")
    }
    _ => fail("expected resolved export")
  }
}

///|
test "Task 6C: 4096-hop explicit-source resolution is stack safe" {
  let records = module_resolution_chain(4097, "explicit")
  let resolve_set : @set.Set[String] = Default::default()
  assert_deep_module_resolution(
    Interpreter::new().resolve_module_export(
      records["0"],
      "x",
      records,
      resolve_set,
    ),
    "4096",
  )
  assert_true(resolve_set.contains("0\u0000x"))
  assert_true(resolve_set.contains("4096\u0000x"))
}

///|
test "Task 6C: 4096-hop imported-local resolution is stack safe" {
  let records = module_resolution_chain(4097, "imported")
  let resolve_set : @set.Set[String] = Default::default()
  assert_deep_module_resolution(
    Interpreter::new().resolve_module_export(
      records["0"],
      "x",
      records,
      resolve_set,
    ),
    "4096",
  )
  assert_true(resolve_set.contains("0\u0000x"))
  assert_true(resolve_set.contains("4096\u0000x"))
}

///|
test "Task 6C: 4096-hop star resolution reaches direct leaf stack safely" {
  let records = module_resolution_chain(4097, "star")
  let resolve_set : @set.Set[String] = Default::default()
  assert_deep_module_resolution(
    Interpreter::new().resolve_module_export(
      records["0"],
      "x",
      records,
      resolve_set,
    ),
    "4096",
  )
  assert_true(resolve_set.contains("0\u0000x"))
  assert_true(resolve_set.contains("4096\u0000x"))
}

///|
fn assert_module_resolution_origin(
  result : ModuleExportResolution,
  value : Double,
  specifier : String,
  binding_name : String,
) -> Unit raise Error {
  match result {
    Resolved(resolved) => {
      assert_true(resolved.value is Number(n) && n == value)
      assert_eq(resolved.module_specifier, specifier)
      assert_eq(resolved.binding_name, binding_name)
    }
    _ => fail("expected resolved export")
  }
}

///|
test "Task 6C: explicit selection and direct/default precedence parity" {
  let interp = Interpreter::new()
  interp.register_module("missing", Map([]))
  let leaf = module_test_record_at(
    "leaf",
    @parser.parse("export const x = 1;").stmts,
  )
  leaf.exports["x"] = Number(1.0)
  let records : Map[String, ModuleRunRecord] = Map([("leaf", leaf)])
  let first_missing = module_test_record_at(
    "first",
    @parser.parse(
      "export { x } from 'missing'; export { x } from 'leaf'; export * from 'leaf';",
    ).stmts,
  )
  let first_set : @set.Set[String] = Default::default()
  assert_module_resolution_origin(
    interp.resolve_module_export(first_missing, "x", records, first_set),
    1.0,
    "leaf",
    "x",
  )
  assert_true(first_set.contains("first\u0000x"))
  assert_true(first_set.contains("leaf\u0000x"))
  let direct = module_test_record_at(
    "direct",
    @parser.parse(
      "export { x } from 'missing'; export const x = 2; export * from 'leaf';",
    ).stmts,
  )
  direct.exports["x"] = Number(2.0)
  let direct_set : @set.Set[String] = Default::default()
  assert_module_resolution_origin(
    interp.resolve_module_export(direct, "x", records, direct_set),
    2.0,
    "direct",
    "x",
  )
  assert_false(direct_set.contains("leaf\u0000x"))
  let default_only = module_test_record_at(
    "default",
    @parser.parse("export * from 'never-loaded';").stmts,
  )
  let default_set : @set.Set[String] = Default::default()
  assert_true(
    interp.resolve_module_export(default_only, "default", records, default_set)
    is NotFound,
  )
  assert_true(default_set.contains("default\u0000default"))
  assert_false(default_set.contains("never-loaded\u0000default"))
}

///|
test "Task 6C: star ambiguity identity and short-circuit parity" {
  let interp = Interpreter::new()
  let leaf = module_test_record_at(
    "leaf",
    @parser.parse("export const x = 1; export const y = 1;").stmts,
  )
  leaf.exports["x"] = Number(1.0)
  leaf.exports["y"] = Number(1.0)
  let alias_a = module_test_record_at(
    "alias-a",
    @parser.parse("export { x } from 'leaf';").stmts,
  )
  let alias_b = module_test_record_at(
    "alias-b",
    @parser.parse("export { x } from 'leaf';").stmts,
  )
  let different = module_test_record_at(
    "different",
    @parser.parse("export { y as x } from 'leaf';").stmts,
  )
  let records : Map[String, ModuleRunRecord] = Map([
    ("leaf", leaf),
    ("alias-a", alias_a),
    ("alias-b", alias_b),
    ("different", different),
  ])
  let same = module_test_record_at(
    "same",
    @parser.parse("export * from 'alias-a'; export * from 'alias-b';").stmts,
  )
  assert_module_resolution_origin(
    interp.resolve_module_export(same, "x", records, Default::default()),
    1.0,
    "leaf",
    "x",
  )
  let ambiguous = module_test_record_at(
    "ambiguous",
    @parser.parse(
      "export * from 'alias-a'; export * from 'different'; export * from 'must-not-load';",
    ).stmts,
  )
  let ambiguous_set : @set.Set[String] = Default::default()
  assert_true(
    interp.resolve_module_export(ambiguous, "x", records, ambiguous_set)
    is Ambiguous,
  )
  assert_false(ambiguous_set.contains("must-not-load\u0000x"))
}

///|
test "Task 6C: star ring later fallback and caller resolve-set reuse parity" {
  let interp = Interpreter::new()
  let records = module_resolution_chain(4097, "star")
  let leaf = module_test_record_at(
    "leaf",
    @parser.parse("export const x = 3;").stmts,
  )
  leaf.exports["x"] = Number(3.0)
  records["leaf"] = leaf
  records["4096"] = module_test_record_at(
    "4096",
    @parser.parse("export * from '0'; export * from 'leaf';").stmts,
  )
  let resolve_set : @set.Set[String] = Default::default()
  assert_module_resolution_origin(
    interp.resolve_module_export(records["0"], "x", records, resolve_set),
    3.0,
    "leaf",
    "x",
  )
  assert_true(resolve_set.contains("0\u0000x"))
  assert_true(resolve_set.contains("4096\u0000x"))
  assert_true(resolve_set.contains("leaf\u0000x"))
  assert_true(
    interp.resolve_module_export(records["0"], "x", records, resolve_set)
    is NotFound,
  )
}

///|
test "Task 6C: ImportedNamespace preserves identity cache and resolve set" {
  let interp = Interpreter::new()
  let exports : Map[String, Value] = Map([("x", Number(7.0))])
  interp.register_module("external", exports)
  let resolve_set : @set.Set[String] = Default::default()
  let first = interp.resolve_module_import_target(
    ImportedNamespace("external"),
    Map([]),
    resolve_set,
  )
  let second = interp.resolve_module_import_target(
    ImportedNamespace("external"),
    Map([]),
    resolve_set,
  )
  for result in [first, second] {
    match result {
      Resolved(resolved) => {
        assert_true(resolved.value is Object(_))
        assert_eq(resolved.module_specifier, "external")
        assert_eq(resolved.binding_name, MODULE_NAMESPACE_BINDING_NAME)
      }
      _ => fail("namespace")
    }
  }
  assert_true(module_export_resolution_same(first, second))
  assert_true(exports.contains(MODULE_NAMESPACE_OBJECT_KEY))
  assert_eq(resolve_set.length(), 0)
}

///|
fn module_exported_names_chain(
  length : Int,
) -> Map[String, ModuleRunRecord] raise Error {
  let records : Map[String, ModuleRunRecord] = Map([])
  let star = module_test_stmt("export * from 'next';")
  for i in 0..<length {
    let specifier = i.to_string()
    let stmts = if i + 1 < length {
      let next = (i + 1).to_string()
      match star {
        ExportAllDecl(namespace_name, _, attributes, loc) =>
          [@ast.Stmt::ExportAllDecl(namespace_name, next, attributes, loc)]
        _ => fail("star")
      }
    } else {
      @parser.parse("export const leaf = 1;").stmts
    }
    records[specifier] = module_test_record_at(specifier, stmts)
  }
  records
}

///|
test "Task 7: exported names handles a 4096-edge record chain" {
  let records = module_exported_names_chain(4097)
  let seen : @set.Set[String] = Default::default()
  let names = Interpreter::new().module_get_exported_names(
    records["0"],
    records,
    seen,
  )
  json_inspect(names, content=["leaf"])
  assert_eq(seen.length(), 4097)
  assert_true(seen.contains("0"))
  assert_true(seen.contains("4096"))
}

///|
test "Task 7: exported names cycle continues to later star source" {
  let records : Map[String, ModuleRunRecord] = Map([])
  records["a"] = module_test_record_at(
    "a",
    @parser.parse("export const a = 1; export * from 'b';").stmts,
  )
  records["b"] = module_test_record_at(
    "b",
    @parser.parse(
      "export const b = 1; export * from 'a'; export * from 'tail';",
    ).stmts,
  )
  records["tail"] = module_test_record_at(
    "tail",
    @parser.parse("export const tail = 1;").stmts,
  )
  let seen : @set.Set[String] = Default::default()
  json_inspect(
    Interpreter::new().module_get_exported_names(records["a"], records, seen),
    content=["a", "b", "tail"],
  )
  assert_true(seen.contains("a"))
  assert_true(seen.contains("b"))
  assert_true(seen.contains("tail"))
}

///|
test "Task 7: exported names filters default and dedupes at each level in order" {
  let records : Map[String, ModuleRunRecord] = Map([])
  records["left"] = module_test_record_at(
    "left",
    @parser.parse(
      "export const shared = 1; export default 2; export const left = 3;",
    ).stmts,
  )
  records["right"] = module_test_record_at(
    "right",
    @parser.parse("export const right = 1; export const shared = 2;").stmts,
  )
  let root = module_test_record_at(
    "root",
    @parser.parse(
      "export const own = 1; export * from 'left'; export * from 'right'; export { own as shared };",
    ).stmts,
  )
  json_inspect(
    Interpreter::new().module_get_exported_names(
      root,
      records,
      Default::default(),
    ),
    content=["own", "shared", "left", "right"],
  )
}

///|
test "Task 7: exported names reaches external sources in order and stops on error" {
  let loads : Array[String] = []
  let interp = Interpreter::new(
    module_loader=Some(
      ModuleLoader(source => {
        loads.push(source)
        match source {
          "first" =>
            Map([("first-name", Number(1.0)), ("default", Number(2.0))])
          "stop" => raise @errors.TypeError(message="stop")
          _ => Map([("late", Number(3.0))])
        }
      }),
    ),
  )
  let root = module_test_record_at(
    "root",
    @parser.parse(
      "export * from 'first'; export * from 'stop'; export * from 'late';",
    ).stmts,
  )
  let result : Result[Array[String], Error] = Ok(
    interp.module_get_exported_names(root, Map([]), Default::default()),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(TypeError(message=\"stop\"))")
  json_inspect(loads, content=["first", "stop"])
}

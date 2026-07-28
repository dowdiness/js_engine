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
    @set.Set::default(),
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
    @set.Set::default(),
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
    @set.Set::default(),
  )
  let resolved_indirect = interp.resolve_module_export(
    indirect,
    "chosen",
    records,
    @set.Set::default(),
  )
  let resolved_star = interp.resolve_module_export(
    star_only,
    "chosen",
    records,
    @set.Set::default(),
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
    @set.Set::default(),
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

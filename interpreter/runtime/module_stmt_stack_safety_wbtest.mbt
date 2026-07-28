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

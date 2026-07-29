///|
test "collect_var_declared_names: var declaration" {
  let prog = @parser.parse("var x;")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("x"), content="true")
  inspect(names.length(), content="1")
}

///|
test "collect_var_declared_names: let and const are not collected" {
  let prog = @parser.parse("let x; const y = 1;")
  inspect(collect_var_declared_names(prog.stmts).length(), content="0")
}

///|
test "collect_var_declared_names: function decl at top level" {
  let prog = @parser.parse("function f() {}")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("f"), content="true")
}

///|
test "collect_var_declared_names: function decl excluded when include_funcs=false" {
  let prog = @parser.parse("function f() {}")
  let names = collect_var_declared_names(prog.stmts, include_funcs=false)
  inspect(names.length(), content="0")
}

///|
test "collect_var_declared_names: var in for-of loop" {
  let prog = @parser.parse("for (var x of arr) {}")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("x"), content="true")
}

///|
test "collect_var_declared_names: var inside try-catch" {
  let prog = @parser.parse("try { var x; } catch (e) { var y; }")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("x"), content="true")
  inspect(names.contains("y"), content="true")
}

///|
test "collect_var_declared_names: function decl inside if is block-scoped (§B.3.4)" {
  let prog = @parser.parse("if (true) function f() {}")
  let names = collect_var_declared_names(prog.stmts)
  // §B.3.4: if (...) function f() {} treats f as a lexical binding of the
  // implicit block around the then-branch, not a var-declared name. The
  // IfStmt arm in collect_var_declared_names forces in_block=true, which
  // makes count_funcs false regardless of include_funcs.
  inspect(names.contains("f"), content="false")
  inspect(names.length(), content="0")
}

///|
test "collect_var_declared_names: deep statement containers preserve source order" {
  let seed = @parser.parse("var seed;")
  let (loc, init) = match seed.stmts[0] {
    @ast.Stmt::VarDecl(_, _, init, loc) => (loc, init)
    _ => abort("expected variable declaration")
  }
  let mut nested = @ast.Stmt::VarDecl(VarKind, "center", init, loc)
  let descending_half : Array[String] = []
  let ascending_half : Array[String] = []
  for depth in 0..<4096 {
    let before = "before_\{depth}"
    let after = "after_\{depth}"
    nested = @ast.Stmt::Block(
      [
        @ast.Stmt::VarDecl(VarKind, before, init, loc),
        nested,
        @ast.Stmt::VarDecl(VarKind, after, init, loc),
      ],
      loc,
    )
    descending_half.push(before)
    ascending_half.push(after)
  }
  let expected : Array[String] = []
  descending_half.rev_each(name => expected.push(name))
  expected.push("center")
  ascending_half.each(name => expected.push(name))
  assert_eq(collect_var_declared_names([nested]), expected)
}

///|
test "collect_var_declared_names: mixed statement shapes preserve order and boundaries" {
  let source =
    #|var top;
    #|{ var block_name; function block_fn() {} }
    #|if (cond) { var if_then; function if_fn() {} } else { var if_else; }
    #|for (var for_init; cond; step) { var for_body; function for_fn() {} }
    #|switch (value) {
    #|  case 0: var case_first; function case_fn() {} break;
    #|  default: var case_second;
    #|}
    #|try { var try_name; function try_fn() {} }
    #|catch (error) { var catch_name; }
    #|finally { var finally_name; }
    #|with (scope) { var with_name; function with_fn() {} }
    #|nested_label: { var label_name; function label_fn() {} }
    #|top_label: function labeled_fn() {}
    #|export var exported_name;
    #|var { left: destructured_left, right: [destructured_right] } = source;
    #|function boundary_fn() { var hidden_in_function; }
    #|class BoundaryClass { method() { var hidden_in_class; } }
  let parsed = @parser.parse(source)
  let loc = match parsed.stmts[0] {
    @ast.Stmt::VarDecl(_, _, _, loc) => loc
    _ => abort("expected leading variable declaration")
  }
  let direct_ast = @ast.Stmt::StmtList(parsed.stmts, loc)
  json_inspect(collect_var_declared_names([direct_ast]), content=[
    "top", "block_name", "if_then", "if_else", "for_init", "for_body", "case_first",
    "case_second", "try_name", "catch_name", "finally_name", "with_name", "label_name",
    "labeled_fn", "exported_name", "destructured_left", "destructured_right", "boundary_fn",
  ])
}

///|
test "bound names: deep patterns preserve source order and ignore expressions" {
  let seed = @parser.parse("var { first = ignored, second, ...rest } = source;")
  let (object, embedded_expr) = match seed.stmts[0] {
    @ast.Stmt::DestructureDecl(_, @ast.Pattern::ObjectPat(properties, _), _, _) as stmt =>
      match properties[0].default_val {
        Some(expr) =>
          match stmt {
            @ast.Stmt::DestructureDecl(_, pattern, _, _) => (pattern, expr)
            _ => abort("unreachable")
          }
        None => abort("expected default expression")
      }
    _ => abort("expected object destructuring declaration")
  }
  let mut deep = @ast.Pattern::IdentPat("x")
  for _ in 0..<512 {
    deep = @ast.Pattern::DefaultPat(deep, embedded_expr)
  }
  json_inspect(bound_names(deep), content=["x"])
  json_inspect(bound_names(@ast.Pattern::AssignTarget(embedded_expr)), content=[])
  json_inspect(bound_names(object), content=["first", "second", "rest"])
  let array = @ast.Pattern::ArrayPat(
    [
      Some(@ast.Pattern::IdentPat("element_first")),
      None,
      Some(
        @ast.Pattern::ArrayPat(
          [
            Some(@ast.Pattern::IdentPat("nested_first")),
            Some(@ast.Pattern::IdentPat("nested_second")),
          ],
          None,
        ),
      ),
    ],
    Some(@ast.Pattern::IdentPat("array_rest")),
  )
  json_inspect(bound_names(array), content=[
    "element_first", "nested_first", "nested_second", "array_rest",
  ])
}

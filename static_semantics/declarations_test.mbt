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

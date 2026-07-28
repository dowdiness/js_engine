///|
fn nest_groupings(expr : @ast.Expr, depth : Int) -> @ast.Expr {
  let loc = @token.Loc::default()
  let mut nested = expr
  for _ in 0..<depth {
    nested = @ast.Expr::Grouping(nested, loc)
  }
  nested
}

///|
test "grouping unwrap helpers handle 4096 nested nodes" {
  let loc = @token.Loc::default()
  let terminal = @ast.Expr::Ident("terminal", loc)
  let nested = nest_groupings(terminal, 4096)
  assert_eq(unwrap_grouping(nested), terminal)
  assert_eq(unwrap_groupings(nested), terminal)
}

///|
test "anonymous definition classification handles 4096 nested groupings" {
  let loc = @token.Loc::default()
  let terminals = [
    @ast.Expr::FuncExpr(None, [], [], loc, None),
    @ast.Expr::ClassExpr(None, None, [], loc, None),
    @ast.Expr::ArrowFunc([], [], loc, None),
  ]
  for terminal in terminals {
    assert_true(
      is_anonymous_function_definition(nest_groupings(terminal, 4096)),
    )
  }
  assert_false(
    is_anonymous_function_definition(
      nest_groupings(@ast.Expr::Ident("named", loc), 4096),
    ),
  )
}

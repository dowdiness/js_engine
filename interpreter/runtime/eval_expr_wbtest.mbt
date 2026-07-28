///|
test "expr_may_contain_yield handles 4096 nested expressions" {
  let loc = @token.Loc::default()
  let mut nested = @ast.Expr::YieldExpr(None, false, loc)
  for _ in 0..<4096 {
    nested = @ast.Expr::Comma(@ast.Expr::UndefinedLit(loc), nested, loc)
  }
  inspect(expr_may_contain_yield(nested), content="true")
}

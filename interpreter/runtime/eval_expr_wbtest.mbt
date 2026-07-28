///|
test "expr_may_contain_yield handles 4096 nested expressions" {
  let loc = @token.Loc::default()
  let mut nested = @ast.Expr::YieldExpr(None, false, loc)
  for _ in 0..<4096 {
    nested = @ast.Expr::Comma(@ast.Expr::UndefinedLit(loc), nested, loc)
  }
  inspect(expr_may_contain_yield(nested), content="true")
}

///|
test "PerformEval Contains handles a depth-4096 declaration pattern" {
  let loc = @token.Loc::default()
  let mut pattern = @ast.Pattern::DefaultPat(
    @ast.Pattern::IdentPat("value"),
    @ast.Expr::NewTargetExpr(loc),
  )
  for _ in 0..<4096 {
    pattern = @ast.Pattern::ArrayPat([Some(pattern)], None)
  }
  let scan = scan_eval_contains([
    @ast.Stmt::DestructureDecl(
      @ast.VarKind::LetKind,
      pattern,
      @ast.Expr::ArrayLit([], loc),
      loc,
    ),
  ])
  inspect(scan.new_target, content="true")
}

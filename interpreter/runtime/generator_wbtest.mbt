///|
test "params_contain_yield handles 4096 nested expressions" {
  let loc = @token.Loc::default()
  let mut nested = @ast.Expr::YieldExpr(None, false, loc)
  for _ in 0..<4096 {
    nested = @ast.Expr::Comma(@ast.Expr::UndefinedLit(loc), nested, loc)
  }
  let param : @ast.Param = {
    name: "value",
    default_val: Some(nested),
    pattern: None,
    is_rest_pattern: false,
  }
  inspect(params_contain_yield([param]), content="true")
}

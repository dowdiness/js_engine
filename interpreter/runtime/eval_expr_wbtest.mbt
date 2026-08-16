///|
test "eval_binary_op converts the right operand before Symbol failure" {
  let interp = Interpreter::new()
  let calls : Ref[Int] = { val: 0 }
  let hook = make_method_func(
    name="rightToPrimitive",
    realm_state=Some(interp.realm_state),
    fn(_this_value, _args) {
      calls.val += 1
      Number(2.0)
    },
  )
  let object = make_object(Map([]), Null, None, "Object", Map([]), true)
  match object {
    Object(data) =>
      data.bag.symbol_properties[interp.realm_state.well_known_symbols.to_primitive.id] = hook
    _ => fail("expected object fixture")
  }
  let raised = try {
    let _ = eval_binary_op(
      @ast.BinOp::Add,
      Symbol({ id: 9002, description: None }),
      object,
      @token.Loc::default(),
      interp=Some(interp),
    )
    false
  } catch {
    @errors.TypeError(_) => true
    _ => false
  }
  assert_true(raised)
  inspect(calls.val, content="1")
}

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

///|
test "PerformEval Contains handles a depth-4096 computed class key" {
  let loc = @token.Loc::default()
  let mut key = @ast.Expr::NewTargetExpr(loc)
  for _ in 0..<4096 {
    key = @ast.Expr::Comma(@ast.Expr::UndefinedLit(loc), key, loc)
  }
  let class_element = @ast.ClassMember::Field({
    key,
    initializer: Some(@ast.Expr::NewTargetExpr(loc)),
    computed: true,
    is_static: false,
    is_private: false,
  })
  let scan = scan_eval_contains([
    @ast.Stmt::ExprStmt(
      @ast.Expr::ClassExpr(None, None, [class_element], loc, None),
      loc,
    ),
  ])
  inspect(scan.new_target, content="true")
}

///|
test "issue 931 primitive Number update completes at runtime start boundary" {
  let interp = Interpreter::new()
  let env = Environment::new(parent=Some(interp.global))
  env.def("value", Number(1.0), VarBinding)
  let ctx : ExecContext = { strict: false, current_generator: None }
  match
    begin_executor_binding_update(
      interp,
      ctx,
      env,
      "value",
      @ast.Increment,
      true,
      @token.Loc::default(),
    ) {
    ExecutorBindingUpdateCompleted(value) => assert_eq(value.to_string(), "2")
    ExecutorBindingUpdateSuspended(_) =>
      fail("primitive Number update created a child activation")
  }
  assert_eq(env.get("value").to_string(), "2")
}

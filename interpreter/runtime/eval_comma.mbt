///|
/// Evaluate a direct comma chain without recursively entering its comma nodes.
/// The caller has already observed the root comma, so only nested comma nodes
/// popped from the worklist observe their entry here.
fn Interpreter::eval_direct_comma(
  self : Interpreter,
  ctx : ExecContext,
  left : @ast.Expr,
  right : @ast.Expr,
  env : Environment,
) -> Value raise Error {
  let work : Array[@ast.Expr] = []
  let mut result : Value = Undefined
  let skip_left = match ctx.current_generator {
    Some(gen) => gen.resuming && !expr_may_contain_yield(left)
    None => false
  }
  work.push(right)
  if !skip_left {
    work.push(left)
  }
  while work.pop() is Some(item) {
    match item {
      Comma(nested_left, nested_right, _) => {
        self.observe_execution_step()
        let skip_nested_left = match ctx.current_generator {
          Some(gen) => gen.resuming && !expr_may_contain_yield(nested_left)
          None => false
        }
        work.push(nested_right)
        if !skip_nested_left {
          work.push(nested_left)
        }
      }
      _ => result = self.eval_expr(ctx, item, env)
    }
  }
  result
}

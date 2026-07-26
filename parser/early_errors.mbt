///|
// Early-error helpers for formal-parameter validation.
//
// §15.5.1: generator formal parameters must not Contains(YieldExpression).
// §15.8.1: async formal parameters must not Contains(AwaitExpression).
//
// These walkers mirror the runtime versions in interpreter/runtime/generator.mbt
// so the parser can enforce early errors at parse time rather than at the
// dynamic GeneratorFunction/AsyncFunction constructor call site.

///|
fn params_contain_yield(params : Array[@ast.Param]) -> Bool {
  params
  .iter()
  .any(fn(p) {
    let dv = match p.default_val {
      Some(e) => expr_has_yield(e)
      None => false
    }
    let pt = match p.pattern {
      Some(pat) => pat_has_yield(pat)
      None => false
    }
    dv || pt
  })
}

///|
fn params_contain_await(params : Array[@ast.Param]) -> Bool {
  params
  .iter()
  .any(fn(p) {
    let dv = match p.default_val {
      Some(e) => expr_has_await(e)
      None => false
    }
    let pt = match p.pattern {
      Some(pat) => pat_has_await(pat)
      None => false
    }
    dv || pt
  })
}

///|
fn expr_has_yield(expr : @ast.Expr) -> Bool {
  match expr {
    YieldExpr(_, _, _) => true
    // Arrow param defaults are evaluated in the enclosing generator scope.
    ArrowFuncExt(params, _, _, _, _) | AsyncArrowFuncExt(params, _, _, _, _) =>
      params_contain_yield(params)
    // Class heritage and computed member keys are in the enclosing scope.
    ClassExpr(_, superclass, members, _, _) => {
      let h = match superclass {
        Some(e) => expr_has_yield(e)
        None => false
      }
      let m = members
        .iter()
        .any(fn(mbr) {
          match mbr {
            Method(cm) => cm.computed && expr_has_yield(cm.key)
            Field(cf) => cf.computed && expr_has_yield(cf.key)
            StaticBlock(_) => false
          }
        })
      h || m
    }
    // Full function boundaries — yield inside is not the outer generator's.
    ArrowFunc(_, _, _, _)
    | AsyncArrowFunc(_, _, _, _)
    | FuncExpr(_, _, _, _, _)
    | FuncExprExt(_, _, _, _, _, _)
    | GeneratorExpr(_, _, _, _, _)
    | GeneratorExprExt(_, _, _, _, _, _)
    | AsyncFuncExpr(_, _, _, _, _)
    | AsyncFuncExprExt(_, _, _, _, _, _)
    | AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _) => false
    DestructureAssign(pattern, _, _) =>
      pat_has_yield(pattern) ||
      @ast.expr_immediate_children_any(expr, expr_has_yield)
    _ => @ast.expr_immediate_children_any(expr, expr_has_yield)
  }
}

///|
fn pat_has_yield(pat : @ast.Pattern) -> Bool {
  @ast.pattern_immediate_children_any(pat, pat_has_yield, expr_has_yield)
}

///|
fn expr_has_await(expr : @ast.Expr) -> Bool {
  match expr {
    AwaitExpr(_, _) => true
    // Regular arrow param defaults are in the enclosing async scope.
    ArrowFuncExt(params, _, _, _, _) => params_contain_await(params)
    // Class heritage and computed member keys are in the enclosing scope.
    ClassExpr(_, superclass, members, _, _) => {
      let h = match superclass {
        Some(e) => expr_has_await(e)
        None => false
      }
      let m = members
        .iter()
        .any(fn(mbr) {
          match mbr {
            Method(cm) => cm.computed && expr_has_await(cm.key)
            Field(cf) => cf.computed && expr_has_await(cf.key)
            StaticBlock(_) => false
          }
        })
      h || m
    }
    // Full function/async boundaries — await inside is not the outer async's.
    ArrowFunc(_, _, _, _)
    | AsyncArrowFunc(_, _, _, _)
    | AsyncArrowFuncExt(_, _, _, _, _)
    | FuncExpr(_, _, _, _, _)
    | FuncExprExt(_, _, _, _, _, _)
    | GeneratorExpr(_, _, _, _, _)
    | GeneratorExprExt(_, _, _, _, _, _)
    | AsyncFuncExpr(_, _, _, _, _)
    | AsyncFuncExprExt(_, _, _, _, _, _)
    | AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _) => false
    DestructureAssign(pattern, _, _) =>
      pat_has_await(pattern) ||
      @ast.expr_immediate_children_any(expr, expr_has_await)
    _ => @ast.expr_immediate_children_any(expr, expr_has_await)
  }
}

///|
fn pat_has_await(pat : @ast.Pattern) -> Bool {
  @ast.pattern_immediate_children_any(pat, pat_has_await, expr_has_await)
}

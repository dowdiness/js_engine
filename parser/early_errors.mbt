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
    Binary(_, a, b, _) => expr_has_yield(a) || expr_has_yield(b)
    Unary(_, e, _)
    | UpdateExpr(_, e, _, _)
    | Grouping(e, _)
    | SpreadExpr(e, _) => expr_has_yield(e)
    Assign(_, e, _) => expr_has_yield(e)
    MemberAssign(obj, _, val, _) | PrivateMemberAssign(obj, _, val, _) =>
      expr_has_yield(obj) || expr_has_yield(val)
    ComputedAssign(obj, key, val, _) =>
      expr_has_yield(obj) || expr_has_yield(key) || expr_has_yield(val)
    CompoundAssign(_, a, b, _)
    | Comma(a, b, _)
    | WebCompatCallAssign(a, b, _) => expr_has_yield(a) || expr_has_yield(b)
    Member(obj, _, _)
    | OptionalMember(obj, _, _)
    | ChainMember(obj, _, _)
    | PrivateMember(obj, _, _) => expr_has_yield(obj)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) =>
      expr_has_yield(obj) || expr_has_yield(key)
    SuperComputedMember(e, _) => expr_has_yield(e)
    Ternary(cond, t, f, _) =>
      expr_has_yield(cond) || expr_has_yield(t) || expr_has_yield(f)
    Call(f, args, _) | NewExpr(f, args, _) | OptionalCall(f, args, _) =>
      expr_has_yield(f) || args.iter().any(fn(a) { expr_has_yield(a) })
    SuperCall(args, _) => args.iter().any(fn(a) { expr_has_yield(a) })
    ArrayLit(elems, _) => elems.iter().any(fn(e) { expr_has_yield(e) })
    ObjectLit(props, _) =>
      props
      .iter()
      .any(fn(p) { expr_has_yield(p.key) || expr_has_yield(p.value) })
    TemplateLit(_, exprs, _) => exprs.iter().any(fn(e) { expr_has_yield(e) })
    TaggedTemplate(tag, _, exprs, _) =>
      expr_has_yield(tag) || exprs.iter().any(fn(e) { expr_has_yield(e) })
    DestructureAssign(pat, rhs, _) => pat_has_yield(pat) || expr_has_yield(rhs)
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
    PrivateIdent(_, _) => false
    _ => false
  }
}

///|
fn pat_has_yield(pat : @ast.Pattern) -> Bool {
  match pat {
    IdentPat(_) => false
    DefaultPat(inner, default_expr) =>
      pat_has_yield(inner) || expr_has_yield(default_expr)
    AssignTarget(e) => expr_has_yield(e)
    ArrayPat(elements, rest) => {
      let ee = elements
        .iter()
        .any(fn(e) {
          match e {
            Some(p) => pat_has_yield(p)
            None => false
          }
        })
      let rr = match rest {
        Some(r) => pat_has_yield(r)
        None => false
      }
      ee || rr
    }
    ObjectPat(props, rest) => {
      let pp = props
        .iter()
        .any(fn(prop) {
          let ck = match prop.computed_key {
            Some(e) => expr_has_yield(e)
            None => false
          }
          let dv = match prop.default_val {
            Some(e) => expr_has_yield(e)
            None => false
          }
          ck || dv || pat_has_yield(prop.value)
        })
      let rr = match rest {
        Some(r) => pat_has_yield(r)
        None => false
      }
      pp || rr
    }
  }
}

///|
fn expr_has_await(expr : @ast.Expr) -> Bool {
  match expr {
    AwaitExpr(_, _) => true
    Binary(_, a, b, _) => expr_has_await(a) || expr_has_await(b)
    Unary(_, e, _)
    | UpdateExpr(_, e, _, _)
    | Grouping(e, _)
    | SpreadExpr(e, _) => expr_has_await(e)
    Assign(_, e, _) => expr_has_await(e)
    MemberAssign(obj, _, val, _) | PrivateMemberAssign(obj, _, val, _) =>
      expr_has_await(obj) || expr_has_await(val)
    ComputedAssign(obj, key, val, _) =>
      expr_has_await(obj) || expr_has_await(key) || expr_has_await(val)
    CompoundAssign(_, a, b, _)
    | Comma(a, b, _)
    | WebCompatCallAssign(a, b, _) => expr_has_await(a) || expr_has_await(b)
    Member(obj, _, _)
    | OptionalMember(obj, _, _)
    | ChainMember(obj, _, _)
    | PrivateMember(obj, _, _) => expr_has_await(obj)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) =>
      expr_has_await(obj) || expr_has_await(key)
    SuperComputedMember(e, _) => expr_has_await(e)
    Ternary(cond, t, f, _) =>
      expr_has_await(cond) || expr_has_await(t) || expr_has_await(f)
    Call(f, args, _) | NewExpr(f, args, _) | OptionalCall(f, args, _) =>
      expr_has_await(f) || args.iter().any(fn(a) { expr_has_await(a) })
    SuperCall(args, _) => args.iter().any(fn(a) { expr_has_await(a) })
    ArrayLit(elems, _) => elems.iter().any(fn(e) { expr_has_await(e) })
    ObjectLit(props, _) =>
      props
      .iter()
      .any(fn(p) { expr_has_await(p.key) || expr_has_await(p.value) })
    TemplateLit(_, exprs, _) => exprs.iter().any(fn(e) { expr_has_await(e) })
    TaggedTemplate(tag, _, exprs, _) =>
      expr_has_await(tag) || exprs.iter().any(fn(e) { expr_has_await(e) })
    DestructureAssign(pat, rhs, _) => pat_has_await(pat) || expr_has_await(rhs)
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
    PrivateIdent(_, _) => false
    _ => false
  }
}

///|
fn pat_has_await(pat : @ast.Pattern) -> Bool {
  match pat {
    IdentPat(_) => false
    DefaultPat(inner, default_expr) =>
      pat_has_await(inner) || expr_has_await(default_expr)
    AssignTarget(e) => expr_has_await(e)
    ArrayPat(elements, rest) => {
      let ee = elements
        .iter()
        .any(fn(e) {
          match e {
            Some(p) => pat_has_await(p)
            None => false
          }
        })
      let rr = match rest {
        Some(r) => pat_has_await(r)
        None => false
      }
      ee || rr
    }
    ObjectPat(props, rest) => {
      let pp = props
        .iter()
        .any(fn(prop) {
          let ck = match prop.computed_key {
            Some(e) => expr_has_await(e)
            None => false
          }
          let dv = match prop.default_val {
            Some(e) => expr_has_await(e)
            None => false
          }
          ck || dv || pat_has_await(prop.value)
        })
      let rr = match rest {
        Some(r) => pat_has_await(r)
        None => false
      }
      pp || rr
    }
  }
}

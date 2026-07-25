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
// Private tag distinguishing which expression kind the walk is searching for.
enum EarlyErrorKind {
  Yield
  Await
}

///|
fn params_contain_yield(params : Array[@ast.Param]) -> Bool {
  params_contain(params, Yield)
}

///|
fn params_contain_await(params : Array[@ast.Param]) -> Bool {
  params_contain(params, Await)
}

///|
fn params_contain(params : Array[@ast.Param], kind : EarlyErrorKind) -> Bool {
  params
  .iter()
  .any(fn(p) {
    let dv = match p.default_val {
      Some(e) => expr_contains(e, kind)
      None => false
    }
    let pt = match p.pattern {
      Some(pat) => pat_contains(pat, kind)
      None => false
    }
    dv || pt
  })
}

///|
fn expr_contains(expr : @ast.Expr, kind : EarlyErrorKind) -> Bool {
  match expr {
    YieldExpr(_, _, _) => kind is Yield
    AwaitExpr(_, _) => kind is Await
    Binary(_, a, b, _) => expr_contains(a, kind) || expr_contains(b, kind)
    Unary(_, e, _)
    | UpdateExpr(_, e, _, _)
    | Grouping(e, _)
    | SpreadExpr(e, _) => expr_contains(e, kind)
    Assign(_, e, _) => expr_contains(e, kind)
    MemberAssign(obj, _, val, _) | PrivateMemberAssign(obj, _, val, _) =>
      expr_contains(obj, kind) || expr_contains(val, kind)
    ComputedAssign(obj, key, val, _) =>
      expr_contains(obj, kind) ||
      expr_contains(key, kind) ||
      expr_contains(val, kind)
    CompoundAssign(_, a, b, _)
    | Comma(a, b, _)
    | WebCompatCallAssign(a, b, _) =>
      expr_contains(a, kind) || expr_contains(b, kind)
    Member(obj, _, _)
    | OptionalMember(obj, _, _)
    | ChainMember(obj, _, _)
    | PrivateMember(obj, _, _) => expr_contains(obj, kind)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) =>
      expr_contains(obj, kind) || expr_contains(key, kind)
    SuperComputedMember(e, _) => expr_contains(e, kind)
    Ternary(cond, t, f, _) =>
      expr_contains(cond, kind) ||
      expr_contains(t, kind) ||
      expr_contains(f, kind)
    Call(f, args, _) | NewExpr(f, args, _) | OptionalCall(f, args, _) =>
      expr_contains(f, kind) || args.iter().any(fn(a) { expr_contains(a, kind) })
    SuperCall(args, _) => args.iter().any(fn(a) { expr_contains(a, kind) })
    ArrayLit(elems, _) => elems.iter().any(fn(e) { expr_contains(e, kind) })
    ObjectLit(props, _) =>
      props
      .iter()
      .any(fn(p) {
        expr_contains(p.key, kind) || expr_contains(p.value, kind)
      })
    TemplateLit(_, exprs, _) =>
      exprs.iter().any(fn(e) { expr_contains(e, kind) })
    TaggedTemplate(tag, _, exprs, _) =>
      expr_contains(tag, kind) ||
      exprs.iter().any(fn(e) { expr_contains(e, kind) })
    DestructureAssign(pat, rhs, _) =>
      pat_contains(pat, kind) || expr_contains(rhs, kind)
    // Regular arrow param defaults are evaluated in the enclosing scope for
    // both yield and await.
    ArrowFuncExt(params, _, _, _, _) => params_contain(params, kind)
    // Async arrow param defaults are in the enclosing generator scope (yield
    // propagates), but an async arrow creates its own await scope (await stops).
    AsyncArrowFuncExt(params, _, _, _, _) =>
      (kind is Yield) && params_contain(params, kind)
    // Class heritage and computed member keys are in the enclosing scope.
    ClassExpr(_, superclass, members, _, _) => {
      let h = match superclass {
        Some(e) => expr_contains(e, kind)
        None => false
      }
      let m = members
        .iter()
        .any(fn(mbr) {
          match mbr {
            Method(cm) => cm.computed && expr_contains(cm.key, kind)
            Field(cf) => cf.computed && expr_contains(cf.key, kind)
            StaticBlock(_) => false
          }
        })
      h || m
    }
    // Full function boundaries — yield/await inside is not the outer scope's.
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
fn pat_contains(pat : @ast.Pattern, kind : EarlyErrorKind) -> Bool {
  match pat {
    IdentPat(_) => false
    DefaultPat(inner, default_expr) =>
      pat_contains(inner, kind) || expr_contains(default_expr, kind)
    AssignTarget(e) => expr_contains(e, kind)
    ArrayPat(elements, rest) => {
      let ee = elements
        .iter()
        .any(fn(e) {
          match e {
            Some(p) => pat_contains(p, kind)
            None => false
          }
        })
      let rr = match rest {
        Some(r) => pat_contains(r, kind)
        None => false
      }
      ee || rr
    }
    ObjectPat(props, rest) => {
      let pp = props
        .iter()
        .any(fn(prop) {
          let ck = match prop.computed_key {
            Some(e) => expr_contains(e, kind)
            None => false
          }
          let dv = match prop.default_val {
            Some(e) => expr_contains(e, kind)
            None => false
          }
          ck || dv || pat_contains(prop.value, kind)
        })
      let rr = match rest {
        Some(r) => pat_contains(r, kind)
        None => false
      }
      pp || rr
    }
  }
}

// ES262 §19.2.1.1 PerformEval steps 8–14 require, before evaluating the eval
// body, that we reject an eval source that contains forbidden constructs in
// the surrounding context:
//
//   • SuperCall              — outside a derived constructor
//   • SuperProperty          — outside a method
//   • NewTarget              — outside a function
//   • IdentifierReference    — "arguments" inside a class field initializer
//
// All four predicates are computed with the same Contains traversal:
// descend through ordinary expressions and arrow function bodies (arrows are
// transparent to super/this/arguments/new.target), but skip non-arrow
// function bodies, generator/async bodies, and class member bodies entirely
// (per ES262 §15.2.12 — Contains stops at function boundaries, including
// FormalParameters of a skipped function).
//
// We compute all four bits in one pass.

///|
priv struct EvalContainsScan {
  mut super_call : Bool
  mut super_property : Bool
  mut new_target : Bool
  mut arguments_ref : Bool
}

///|
priv enum EvalContainsWork {
  Stmt(@ast.Stmt)
  Expr(@ast.Expr)
  Pattern(@ast.Pattern)
}

///|
fn EvalContainsScan::new() -> EvalContainsScan {
  {
    super_call: false,
    super_property: false,
    new_target: false,
    arguments_ref: false,
  }
}

///|
/// Run the scan over a list of top-level statements (the parsed eval body).
/// Returns a struct with one bit per Contains predicate.
fn scan_eval_contains(stmts : Array[@ast.Stmt]) -> EvalContainsScan {
  let scan = EvalContainsScan::new()
  let work : Array[EvalContainsWork] = []
  for i in (stmts.length() - 1)>=..0 {
    work.push(Stmt(stmts[i]))
  }
  while work.pop() is Some(item) {
    let scheduled : Array[EvalContainsWork] = []
    match item {
      Stmt(stmt) => schedule_eval_contains_stmt(scheduled, stmt)
      Expr(expr) => schedule_eval_contains_expr(scan, scheduled, expr)
      Pattern(pattern) => schedule_eval_contains_pattern(scheduled, pattern)
    }
    for i in (scheduled.length() - 1)>=..0 {
      work.push(scheduled[i])
    }
  }
  scan
}

///|
fn schedule_eval_contains_stmt(
  scheduled : Array[EvalContainsWork],
  stmt : @ast.Stmt,
) -> Unit {
  match stmt {
    ExprStmt(e, _) => scheduled.push(Expr(e))
    VarDecl(_, _, init, _) =>
      match init {
        Some(e) => scheduled.push(Expr(e))
        None => ()
      }
    Block(stmts, _) | StmtList(stmts, _) =>
      for s in stmts {
        scheduled.push(Stmt(s))
      }
    IfStmt(cond, then_s, else_s, _) => {
      scheduled.push(Expr(cond))
      scheduled.push(Stmt(then_s))
      match else_s {
        Some(s) => scheduled.push(Stmt(s))
        None => ()
      }
    }
    WhileStmt(cond, body, _) => {
      scheduled.push(Expr(cond))
      scheduled.push(Stmt(body))
    }
    DoWhileStmt(body, cond, _) => {
      scheduled.push(Stmt(body))
      scheduled.push(Expr(cond))
    }
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(s) => scheduled.push(Stmt(s))
        None => ()
      }
      match cond {
        Some(e) => scheduled.push(Expr(e))
        None => ()
      }
      match update {
        Some(e) => scheduled.push(Expr(e))
        None => ()
      }
      scheduled.push(Stmt(body))
    }
    ForInStmt(_, _, src, body, _)
    | ForOfStmt(_, _, src, body, _)
    | AsyncForOfStmt(_, _, src, body, _) => {
      scheduled.push(Expr(src))
      scheduled.push(Stmt(body))
    }
    ForInStmtPat(_, _, src, body, _)
    | ForOfStmtPat(_, _, src, body, _)
    | AsyncForOfStmtPat(_, _, src, body, _) => {
      scheduled.push(Expr(src))
      scheduled.push(Stmt(body))
    }
    ForInExpr(target, src, body, _)
    | ForOfExpr(target, src, body, _)
    | AsyncForOfExpr(target, src, body, _) => {
      scheduled.push(Expr(target))
      scheduled.push(Expr(src))
      scheduled.push(Stmt(body))
    }
    ReturnStmt(e, _) =>
      match e {
        Some(e) => scheduled.push(Expr(e))
        None => ()
      }
    ThrowStmt(e, _) => scheduled.push(Expr(e))
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for s in try_body {
        scheduled.push(Stmt(s))
      }
      match catch_body {
        Some(stmts) =>
          for s in stmts {
            scheduled.push(Stmt(s))
          }
        None => ()
      }
      match finally_body {
        Some(stmts) =>
          for s in stmts {
            scheduled.push(Stmt(s))
          }
        None => ()
      }
    }
    SwitchStmt(disc, cases, _) => {
      scheduled.push(Expr(disc))
      for c in cases {
        match c.condition {
          Some(e) => scheduled.push(Expr(e))
          None => ()
        }
        for s in c.body {
          scheduled.push(Stmt(s))
        }
      }
    }
    DestructureDecl(_, _, init, _) => scheduled.push(Expr(init))
    LabeledStmt(_, body, _) => scheduled.push(Stmt(body))
    WithStmt(obj, body, _) => {
      scheduled.push(Expr(obj))
      scheduled.push(Stmt(body))
    }
    // Class declaration: visit heritage (extends clause is in surrounding
    // scope) but skip member bodies (each member has its own context).
    ClassDecl(_, superclass, _, _, _) =>
      match superclass {
        Some(e) => scheduled.push(Expr(e))
        None => ()
      }
    // Skip-entirely productions: each introduces its own function-scope
    // binding for new.target/arguments/super, so Contains stops here.
    FuncDecl(_, _, _, _, _)
    | FuncDeclExt(_, _, _, _, _, _)
    | GeneratorDecl(_, _, _, _, _)
    | GeneratorDeclExt(_, _, _, _, _, _)
    | AsyncFuncDecl(_, _, _, _, _)
    | AsyncFuncDeclExt(_, _, _, _, _, _)
    | AsyncGeneratorDecl(_, _, _, _, _)
    | AsyncGeneratorDeclExt(_, _, _, _, _, _) => ()
    // Module-level decls: import/export shouldn't appear in eval source, but
    // be defensive — they have nothing scan-relevant in their headers.
    _ => ()
  }
}

///|
/// Scan a destructuring pattern. Patterns themselves bind names (irrelevant
/// to Contains), but they may carry default expressions and computed keys,
/// both of which evaluate in the surrounding context and therefore count
/// for the four predicates.
fn schedule_eval_contains_pattern(
  scheduled : Array[EvalContainsWork],
  pat : @ast.Pattern,
) -> Unit {
  match pat {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for el in elements {
        match el {
          Some(p) => scheduled.push(Pattern(p))
          None => ()
        }
      }
      match rest {
        Some(p) => scheduled.push(Pattern(p))
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(e) => scheduled.push(Expr(e))
          None => ()
        }
        match prop.default_val {
          Some(e) => scheduled.push(Expr(e))
          None => ()
        }
        scheduled.push(Pattern(prop.value))
      }
      match rest {
        Some(p) => scheduled.push(Pattern(p))
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      scheduled.push(Pattern(inner))
      scheduled.push(Expr(expr))
    }
    AssignTarget(expr) => scheduled.push(Expr(expr))
  }
}

///|
fn schedule_eval_contains_expr(
  scan : EvalContainsScan,
  scheduled : Array[EvalContainsWork],
  expr : @ast.Expr,
) -> Unit {
  match expr {
    // Leaves
    SuperCall(args, _) => {
      scan.super_call = true
      for a in args {
        scheduled.push(Expr(a))
      }
    }
    SuperMember(_, _) => scan.super_property = true
    SuperComputedMember(key, _) => {
      scan.super_property = true
      scheduled.push(Expr(key))
    }
    SuperMemberAssign(_, rhs, _) => {
      scan.super_property = true
      scheduled.push(Expr(rhs))
    }
    SuperComputedAssign(key, rhs, _) => {
      scan.super_property = true
      scheduled.push(Expr(key))
      scheduled.push(Expr(rhs))
    }
    NewTargetExpr(_) => scan.new_target = true
    Ident("arguments", _) => scan.arguments_ref = true
    PrivateIdent(_, _) => ()
    // Skip-entirely: non-arrow function/generator/async bodies define their
    // own super/arguments/new.target context per ES262 §15.2.12.
    FuncExpr(_, _, _, _, _)
    | FuncExprExt(_, _, _, _, _, _)
    | GeneratorExpr(_, _, _, _, _)
    | GeneratorExprExt(_, _, _, _, _, _)
    | AsyncFuncExpr(_, _, _, _, _)
    | AsyncFuncExprExt(_, _, _, _, _, _)
    | AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _) => ()
    // ClassExpr: visit heritage only, skip member bodies.
    ClassExpr(_, superclass, _, _, _) =>
      match superclass {
        Some(e) => scheduled.push(Expr(e))
        None => ()
      }
    // Arrows: transparent for the four predicates per spec — and that
    // transparency extends to the parameter list. Non-arrow function
    // boundaries skip params (they're the function's own concern), but
    // arrow params/defaults run in the surrounding scope (Codex review on
    // PR #100 caught this gap, V8-confirmed). ArrowFunc has `Array[String]`
    // params — no expressions to scan. ArrowFuncExt carries Param values
    // with optional default_val and destructuring pattern, both of which
    // must be visited.
    ArrowFunc(_, body, _, _) | AsyncArrowFunc(_, body, _, _) =>
      for s in body {
        scheduled.push(Stmt(s))
      }
    ArrowFuncExt(params, _, body, _, _)
    | AsyncArrowFuncExt(params, _, body, _, _) => {
      for p in params {
        match p.default_val {
          Some(e) => scheduled.push(Expr(e))
          None => ()
        }
        match p.pattern {
          Some(pat) => scheduled.push(Pattern(pat))
          None => ()
        }
      }
      for s in body {
        scheduled.push(Stmt(s))
      }
    }
    // Recurse-into: every other expression descends through children.
    Binary(_, l, r, _) | Comma(l, r, _) => {
      scheduled.push(Expr(l))
      scheduled.push(Expr(r))
    }
    Unary(_, e, _)
    | Grouping(e, _)
    | SpreadExpr(e, _)
    | YieldExpr(Some(e), _, _)
    | AwaitExpr(e, _) => scheduled.push(Expr(e))
    YieldExpr(None, _, _) => ()
    Assign(_, e, _) => scheduled.push(Expr(e))
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      scheduled.push(Expr(callee))
      for a in args {
        scheduled.push(Expr(a))
      }
    }
    Member(obj, _, _)
    | OptionalMember(obj, _, _)
    | ChainMember(obj, _, _)
    | PrivateMember(obj, _, _) => scheduled.push(Expr(obj))
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) => {
      scheduled.push(Expr(obj))
      scheduled.push(Expr(key))
    }
    Ternary(c, t, f, _) => {
      scheduled.push(Expr(c))
      scheduled.push(Expr(t))
      scheduled.push(Expr(f))
    }
    MemberAssign(obj, _, rhs, _) => {
      scheduled.push(Expr(obj))
      scheduled.push(Expr(rhs))
    }
    PrivateMemberAssign(obj, _, rhs, _) => {
      scheduled.push(Expr(obj))
      scheduled.push(Expr(rhs))
    }
    ComputedAssign(obj, key, rhs, _) => {
      scheduled.push(Expr(obj))
      scheduled.push(Expr(key))
      scheduled.push(Expr(rhs))
    }
    UpdateExpr(_, target, _, _) => scheduled.push(Expr(target))
    CompoundAssign(_, lhs, rhs, _) => {
      scheduled.push(Expr(lhs))
      scheduled.push(Expr(rhs))
    }
    WebCompatCallAssign(call_expr, rhs, _) => {
      scheduled.push(Expr(call_expr))
      scheduled.push(Expr(rhs))
    }
    // Property keys: prop.key is StringLit for non-computed keys (per
    // ast/ast.mbt:83 comment), so descending into it is safe — a literal
    // `arguments` written as `{ arguments: 1 }` is a StringLit, not an
    // Ident, and won't trigger arguments_ref.
    ObjectLit(props, _) =>
      for prop in props {
        scheduled.push(Expr(prop.key))
        scheduled.push(Expr(prop.value))
      }
    ArrayLit(elements, _) =>
      for e in elements {
        scheduled.push(Expr(e))
      }
    TemplateLit(_, exprs, _) =>
      for e in exprs {
        scheduled.push(Expr(e))
      }
    TaggedTemplate(tag, _, exprs, _) => {
      scheduled.push(Expr(tag))
      for e in exprs {
        scheduled.push(Expr(e))
      }
    }
    DestructureAssign(_, rhs, _) => scheduled.push(Expr(rhs))
    // Leaves with nothing to scan. (Ident("arguments") is handled above.)
    NumberLit(_, _, _)
    | StringLit(_, _, _, _)
    | BoolLit(_, _)
    | NullLit(_)
    | UndefinedLit(_)
    | ArrayHole(_)
    | Ident(_, _)
    | ThisExpr(_)
    | RegexLit(_, _, _) => ()
  }
}

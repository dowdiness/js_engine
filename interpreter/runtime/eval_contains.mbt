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
  for s in stmts {
    scan_stmt(scan, s)
  }
  scan
}

///|
fn scan_stmt(scan : EvalContainsScan, stmt : @ast.Stmt) -> Unit {
  match stmt {
    ExprStmt(e, _) => scan_expr(scan, e)
    VarDecl(_, _, init, _) =>
      match init {
        Some(e) => scan_expr(scan, e)
        None => ()
      }
    Block(stmts, _) | StmtList(stmts, _) =>
      for s in stmts {
        scan_stmt(scan, s)
      }
    IfStmt(cond, then_s, else_s, _) => {
      scan_expr(scan, cond)
      scan_stmt(scan, then_s)
      match else_s {
        Some(s) => scan_stmt(scan, s)
        None => ()
      }
    }
    WhileStmt(cond, body, _) => {
      scan_expr(scan, cond)
      scan_stmt(scan, body)
    }
    DoWhileStmt(body, cond, _) => {
      scan_stmt(scan, body)
      scan_expr(scan, cond)
    }
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(s) => scan_stmt(scan, s)
        None => ()
      }
      match cond {
        Some(e) => scan_expr(scan, e)
        None => ()
      }
      match update {
        Some(e) => scan_expr(scan, e)
        None => ()
      }
      scan_stmt(scan, body)
    }
    ForInStmt(_, _, src, body, _) | ForOfStmt(_, _, src, body, _) => {
      scan_expr(scan, src)
      scan_stmt(scan, body)
    }
    ForInStmtPat(_, _, src, body, _) | ForOfStmtPat(_, _, src, body, _) => {
      scan_expr(scan, src)
      scan_stmt(scan, body)
    }
    ForInExpr(target, src, body, _) | ForOfExpr(target, src, body, _) => {
      scan_expr(scan, target)
      scan_expr(scan, src)
      scan_stmt(scan, body)
    }
    ReturnStmt(e, _) =>
      match e {
        Some(e) => scan_expr(scan, e)
        None => ()
      }
    ThrowStmt(e, _) => scan_expr(scan, e)
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for s in try_body {
        scan_stmt(scan, s)
      }
      match catch_body {
        Some(stmts) =>
          for s in stmts {
            scan_stmt(scan, s)
          }
        None => ()
      }
      match finally_body {
        Some(stmts) =>
          for s in stmts {
            scan_stmt(scan, s)
          }
        None => ()
      }
    }
    SwitchStmt(disc, cases, _) => {
      scan_expr(scan, disc)
      for c in cases {
        match c.condition {
          Some(e) => scan_expr(scan, e)
          None => ()
        }
        for s in c.body {
          scan_stmt(scan, s)
        }
      }
    }
    DestructureDecl(_, _, init, _) => scan_expr(scan, init)
    LabeledStmt(_, body, _) => scan_stmt(scan, body)
    WithStmt(obj, body, _) => {
      scan_expr(scan, obj)
      scan_stmt(scan, body)
    }
    // Class declaration: visit heritage (extends clause is in surrounding
    // scope) but skip member bodies (each member has its own context).
    ClassDecl(_, superclass, _, _, _) =>
      match superclass {
        Some(e) => scan_expr(scan, e)
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
fn scan_pattern(scan : EvalContainsScan, pat : @ast.Pattern) -> Unit {
  match pat {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for el in elements {
        match el {
          Some(p) => scan_pattern(scan, p)
          None => ()
        }
      }
      match rest {
        Some(p) => scan_pattern(scan, p)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(e) => scan_expr(scan, e)
          None => ()
        }
        match prop.default_val {
          Some(e) => scan_expr(scan, e)
          None => ()
        }
        scan_pattern(scan, prop.value)
      }
      match rest {
        Some(p) => scan_pattern(scan, p)
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      scan_pattern(scan, inner)
      scan_expr(scan, expr)
    }
    AssignTarget(expr) => scan_expr(scan, expr)
  }
}

///|
fn scan_expr(scan : EvalContainsScan, expr : @ast.Expr) -> Unit {
  match expr {
    // Leaves
    SuperCall(args, _) => {
      scan.super_call = true
      for a in args {
        scan_expr(scan, a)
      }
    }
    SuperMember(_, _) => scan.super_property = true
    SuperComputedMember(key, _) => {
      scan.super_property = true
      scan_expr(scan, key)
    }
    NewTargetExpr(_) => scan.new_target = true
    Ident("arguments", _) => scan.arguments_ref = true
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
        Some(e) => scan_expr(scan, e)
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
        scan_stmt(scan, s)
      }
    ArrowFuncExt(params, _, body, _, _)
    | AsyncArrowFuncExt(params, _, body, _, _) => {
      for p in params {
        match p.default_val {
          Some(e) => scan_expr(scan, e)
          None => ()
        }
        match p.pattern {
          Some(pat) => scan_pattern(scan, pat)
          None => ()
        }
      }
      for s in body {
        scan_stmt(scan, s)
      }
    }
    // Recurse-into: every other expression descends through children.
    Binary(_, l, r, _) | Comma(l, r, _) => {
      scan_expr(scan, l)
      scan_expr(scan, r)
    }
    Unary(_, e, _)
    | Grouping(e, _)
    | SpreadExpr(e, _)
    | YieldExpr(Some(e), _, _)
    | AwaitExpr(e, _) => scan_expr(scan, e)
    YieldExpr(None, _, _) => ()
    Assign(_, e, _) => scan_expr(scan, e)
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      scan_expr(scan, callee)
      for a in args {
        scan_expr(scan, a)
      }
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) | ChainMember(obj, _, _) =>
      scan_expr(scan, obj)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) => {
      scan_expr(scan, obj)
      scan_expr(scan, key)
    }
    Ternary(c, t, f, _) => {
      scan_expr(scan, c)
      scan_expr(scan, t)
      scan_expr(scan, f)
    }
    MemberAssign(obj, _, rhs, _) => {
      scan_expr(scan, obj)
      scan_expr(scan, rhs)
    }
    ComputedAssign(obj, key, rhs, _) => {
      scan_expr(scan, obj)
      scan_expr(scan, key)
      scan_expr(scan, rhs)
    }
    UpdateExpr(_, target, _, _) => scan_expr(scan, target)
    CompoundAssign(_, lhs, rhs, _) => {
      scan_expr(scan, lhs)
      scan_expr(scan, rhs)
    }
    WebCompatCallAssign(call_expr, rhs, _) => {
      scan_expr(scan, call_expr)
      scan_expr(scan, rhs)
    }
    // Property keys: prop.key is StringLit for non-computed keys (per
    // ast/ast.mbt:83 comment), so descending into it is safe — a literal
    // `arguments` written as `{ arguments: 1 }` is a StringLit, not an
    // Ident, and won't trigger arguments_ref.
    ObjectLit(props, _) =>
      for prop in props {
        scan_expr(scan, prop.key)
        scan_expr(scan, prop.value)
      }
    ArrayLit(elements, _) =>
      for e in elements {
        scan_expr(scan, e)
      }
    TemplateLit(_, exprs, _) =>
      for e in exprs {
        scan_expr(scan, e)
      }
    TaggedTemplate(tag, _, exprs, _) => {
      scan_expr(scan, tag)
      for e in exprs {
        scan_expr(scan, e)
      }
    }
    DestructureAssign(_, rhs, _) => scan_expr(scan, rhs)
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

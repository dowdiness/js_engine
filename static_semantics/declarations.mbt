///|
/// Push all binding identifiers from a destructuring pattern into `out`.
/// `AssignTarget` is intentionally ignored — its names resolve to member
/// expressions, not fresh bindings.
fn walk_pattern_binding_idents(
  pattern : @ast.Pattern,
  out : Array[String],
) -> Unit {
  let stack : Array[@ast.Pattern] = [pattern]
  while stack.length() > 0 {
    match stack.pop() {
      Some(IdentPat(name)) => out.push(name)
      Some(DefaultPat(inner_pat, _)) => stack.push(inner_pat)
      Some(AssignTarget(_)) => ()
      Some(ArrayPat(elements, rest)) => {
        match rest {
          Some(rest) => stack.push(rest)
          None => ()
        }
        elements.rev_each(elem => {
          match elem {
            Some(pattern) => stack.push(pattern)
            None => ()
          }
        })
      }
      Some(ObjectPat(props, rest)) => {
        match rest {
          Some(rest) => stack.push(rest)
          None => ()
        }
        props.rev_each(prop => stack.push(prop.value))
      }
      None => ()
    }
  }
}

///|
/// Return the bound names contributed by `pattern` in source order.
/// Assignment targets and embedded expressions do not introduce bindings.
pub fn bound_names(pattern : @ast.Pattern) -> Array[String] {
  let out : Array[String] = []
  walk_pattern_binding_idents(pattern, out)
  out
}

///|
/// Spec (§8.2.10 TopLevelVarDeclaredNames): FunctionDeclarations count as
/// var-declared names only at the top level of a ScriptBody or FunctionBody.
/// Once we descend into a Block, nested FunctionDeclarations are lexical
/// bindings of that block per §13.2.6. We honor `include_funcs` only while
/// `in_block` is false.
fn collect_var_declared_names_iterative(
  stmts : Array[@ast.Stmt],
  out : Array[String],
  include_funcs~ : Bool,
  in_block~ : Bool,
) -> Unit {
  let work : Array[(@ast.Stmt, Bool)] = []
  stmts.rev_each(stmt => work.push((stmt, in_block)))
  while work.length() > 0 {
    let (stmt, current_in_block) = work.pop().unwrap()
    let count_funcs = include_funcs && !current_in_block
    match stmt {
      VarDecl(VarKind, name, _, _) => out.push(name)
      FuncDecl(name, _, _, _, _)
      | FuncDeclExt(name, _, _, _, _, _)
      | GeneratorDecl(name, _, _, _, _)
      | GeneratorDeclExt(name, _, _, _, _, _)
      | AsyncFuncDecl(name, _, _, _, _)
      | AsyncFuncDeclExt(name, _, _, _, _, _)
      | AsyncGeneratorDecl(name, _, _, _, _)
      | AsyncGeneratorDeclExt(name, _, _, _, _, _) =>
        if count_funcs {
          out.push(name)
        }
      DestructureDecl(VarKind, pattern, _, _) =>
        for name in bound_names(pattern) {
          out.push(name)
        }
      Block(children, _) => children.rev_each(child => work.push((child, true)))
      StmtList(children, _) =>
        children.rev_each(child => work.push((child, current_in_block)))
      // ES262 §8.2.10 + §B.3.3: FunctionDeclarations nested under control flow
      // (if, while, for, switch, try/catch, with, labeled) are lexical bindings
      // of that nested scope per §B.3.4. Force in_block=true so FuncDecls don't
      // slip into the enclosing scope's var-declared names.
      IfStmt(_, then_branch, else_branch, _) => {
        match else_branch {
          Some(else_branch) => work.push((else_branch, true))
          None => ()
        }
        work.push((then_branch, true))
      }
      WhileStmt(_, body, _) | DoWhileStmt(body, _, _) => work.push((body, true))
      ForStmt(init, _, _, body, _) => {
        work.push((body, true))
        match init {
          Some(init_stmt) => work.push((init_stmt, true))
          None => ()
        }
      }
      ForInStmt(kind, name, _, body, _)
      | ForOfStmt(kind, name, _, body, _)
      | AsyncForOfStmt(kind, name, _, body, _) => {
        if kind == Some(VarKind) {
          out.push(name)
        }
        work.push((body, true))
      }
      ForInStmtPat(kind, pattern, _, body, _)
      | ForOfStmtPat(kind, pattern, _, body, _)
      | AsyncForOfStmtPat(kind, pattern, _, body, _) => {
        if kind == Some(VarKind) {
          for name in bound_names(pattern) {
            out.push(name)
          }
        }
        work.push((body, true))
      }
      ForInExpr(_, _, body, _)
      | ForOfExpr(_, _, body, _)
      | AsyncForOfExpr(_, _, body, _) => work.push((body, true))
      // §B.3.2 LabelledStatement: a top-level `label: function f(){}` is the
      // one §B.3.4 case where a labeled FunctionDeclaration still participates in
      // TopLevelVarDeclaredNames. Mirror caller's in_block so a top-level label
      // keeps its FuncDecl counted.
      LabeledStmt(_, inner, _) => work.push((inner, current_in_block))
      SwitchStmt(_, cases, _) =>
        cases.rev_each(case_ => {
          case_.body.rev_each(child => work.push((child, true)))
        })
      TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
        match finally_body {
          Some(body) => body.rev_each(child => work.push((child, true)))
          None => ()
        }
        match catch_body {
          Some(body) => body.rev_each(child => work.push((child, true)))
          None => ()
        }
        try_body.rev_each(child => work.push((child, true)))
      }
      WithStmt(_, body, _) => work.push((body, true))
      ExportNamedDecl(Some(decl), _, _, _, _) =>
        work.push((decl, current_in_block))
      // Do not recurse into function/class bodies — their var scopes are separate.
      _ => ()
    }
  }
}

///|
/// Return the var-declared names visible in `stmts`.
///
/// `include_funcs` controls whether FunctionDeclarations (and generator/async
/// variants) at the statement-list level are counted. Set `true` for a script
/// or function body (§8.2.10 TopLevelVarDeclaredNames), `false` for a block.
///
/// `in_block` tracks whether the current position is inside a block — callers
/// should leave this at the default `false` and let the traversal manage it.
pub fn collect_var_declared_names(
  stmts : Array[@ast.Stmt],
  include_funcs? : Bool = true,
  in_block? : Bool = false,
) -> Array[String] {
  let out : Array[String] = []
  collect_var_declared_names_iterative(stmts, out, include_funcs~, in_block~)
  out
}

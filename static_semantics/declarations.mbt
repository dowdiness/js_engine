///|
/// Push all binding identifiers from a destructuring pattern into `out`.
/// `AssignTarget` is intentionally ignored — its names resolve to member
/// expressions, not fresh bindings.
fn walk_pattern_binding_idents(
  pattern : @ast.Pattern,
  out : Array[String],
) -> Unit {
  match pattern {
    IdentPat(name) => out.push(name)
    DefaultPat(inner_pat, _) => walk_pattern_binding_idents(inner_pat, out)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => walk_pattern_binding_idents(p, out)
          None => ()
        }
      }
      match rest {
        Some(p) => walk_pattern_binding_idents(p, out)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        walk_pattern_binding_idents(prop.value, out)
      }
      match rest {
        Some(p) => walk_pattern_binding_idents(p, out)
        None => ()
      }
    }
  }
}

///|
fn collect_var_declared_names_from_stmts(
  stmts : Array[@ast.Stmt],
  out : Array[String],
  include_funcs~ : Bool,
  in_block~ : Bool,
) -> Unit {
  for stmt in stmts {
    collect_var_declared_names_from_stmt(stmt, out, include_funcs~, in_block~)
  }
}

///|
/// Spec (§8.2.10 TopLevelVarDeclaredNames): FunctionDeclarations count as
/// var-declared names only at the top level of a ScriptBody or FunctionBody.
/// Once we descend into a Block, nested FunctionDeclarations are lexical
/// bindings of that block per §13.2.6. We honor `include_funcs` only while
/// `in_block` is false.
fn collect_var_declared_names_from_stmt(
  stmt : @ast.Stmt,
  out : Array[String],
  include_funcs~ : Bool,
  in_block~ : Bool,
) -> Unit {
  let count_funcs = include_funcs && !in_block
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
      walk_pattern_binding_idents(pattern, out)
    Block(stmts, _) =>
      collect_var_declared_names_from_stmts(
        stmts,
        out,
        include_funcs~,
        in_block=true,
      )
    StmtList(stmts, _) =>
      collect_var_declared_names_from_stmts(
        stmts,
        out,
        include_funcs~,
        in_block~,
      )
    // ES262 §8.2.10 + §B.3.3: FunctionDeclarations nested under control flow
    // (if, while, for, switch, try/catch, with, labeled) are lexical bindings
    // of that nested scope per §B.3.4. Force in_block=true so FuncDecls don't
    // slip into the enclosing scope's var-declared names.
    IfStmt(_, then_branch, else_branch, _) => {
      collect_var_declared_names_from_stmt(
        then_branch,
        out,
        include_funcs~,
        in_block=true,
      )
      match else_branch {
        Some(eb) =>
          collect_var_declared_names_from_stmt(
            eb,
            out,
            include_funcs~,
            in_block=true,
          )
        None => ()
      }
    }
    WhileStmt(_, body, _) | DoWhileStmt(body, _, _) =>
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          collect_var_declared_names_from_stmt(
            init_stmt,
            out,
            include_funcs~,
            in_block=true,
          )
        None => ()
      }
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    }
    ForInStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        out.push(name)
      }
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    }
    ForOfStmt(kind, name, _, body, _) | AsyncForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        out.push(name)
      }
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        walk_pattern_binding_idents(pattern, out)
      }
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    }
    ForOfStmtPat(kind, pattern, _, body, _) | AsyncForOfStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        walk_pattern_binding_idents(pattern, out)
      }
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    }
    ForInExpr(_, _, body, _) | ForOfExpr(_, _, body, _) | AsyncForOfExpr(_, _, body, _) =>
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    // §B.3.2 LabelledStatement: a top-level `label: function f(){}` is the
    // one §B.3.4 case where a labeled FunctionDeclaration still participates in
    // TopLevelVarDeclaredNames. Mirror caller's in_block so a top-level label
    // keeps its FuncDecl counted.
    LabeledStmt(_, inner, _) =>
      collect_var_declared_names_from_stmt(
        inner,
        out,
        include_funcs~,
        in_block~,
      )
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        collect_var_declared_names_from_stmts(
          case_.body,
          out,
          include_funcs~,
          in_block=true,
        )
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      collect_var_declared_names_from_stmts(
        try_body,
        out,
        include_funcs~,
        in_block=true,
      )
      match catch_body {
        Some(cb) =>
          collect_var_declared_names_from_stmts(
            cb,
            out,
            include_funcs~,
            in_block=true,
          )
        None => ()
      }
      match finally_body {
        Some(fb) =>
          collect_var_declared_names_from_stmts(
            fb,
            out,
            include_funcs~,
            in_block=true,
          )
        None => ()
      }
    }
    WithStmt(_, body, _) =>
      collect_var_declared_names_from_stmt(
        body,
        out,
        include_funcs~,
        in_block=true,
      )
    ExportNamedDecl(Some(decl), _, _, _, _) =>
      collect_var_declared_names_from_stmt(decl, out, include_funcs~, in_block~)
    // Do not recurse into function/class bodies — their var scopes are separate.
    _ => ()
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
  collect_var_declared_names_from_stmts(stmts, out, include_funcs~, in_block~)
  out
}

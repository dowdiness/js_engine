///|
/// Generic destructuring-pattern walker: invoke `on_ident` once per
/// binding identifier in `pattern`. Shared traversal structure for every
/// pattern-name collector / hoister in this file — only the per-name
/// action differs. `AssignTarget` is intentionally ignored because its
/// names resolve to member expressions, not fresh bindings.
fn walk_pattern_idents(
  pattern : @ast.Pattern,
  on_ident : (String) -> Unit raise Error,
) -> Unit raise Error {
  match pattern {
    IdentPat(name) => on_ident(name)
    DefaultPat(inner_pat, _) => walk_pattern_idents(inner_pat, on_ident)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => walk_pattern_idents(p, on_ident)
          None => ()
        }
      }
      match rest {
        Some(p) => walk_pattern_idents(p, on_ident)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        walk_pattern_idents(prop.value, on_ident)
      }
      match rest {
        Some(p) => walk_pattern_idents(p, on_ident)
        None => ()
      }
    }
  }
}

///|
/// Collect names from a destructuring pattern (for eval var name collection).
fn collect_pattern_var_names(
  pattern : @ast.Pattern,
  names : Array[String],
) -> Unit raise Error {
  walk_pattern_idents(pattern, name => names.push(name))
}

///|
fn add_lexical_decl_name(
  lexical_names : Map[String, Bool],
  name : String,
) -> Unit raise Error {
  if lexical_names.contains(name) {
    raise @errors.SyntaxError(
      message="Identifier '\{name}' has already been declared",
    )
  }
  lexical_names[name] = true
}

///|
fn collect_pattern_decl_names(
  pattern : @ast.Pattern,
  names : Map[String, Bool],
  lexical? : Bool = false,
) -> Unit raise Error {
  walk_pattern_idents(pattern, name => {
    if lexical {
      add_lexical_decl_name(names, name)
    } else {
      names[name] = true
    }
  })
}

///|
fn collect_block_lexical_decl_names_from_stmt(
  stmt : @ast.Stmt,
  lexical_names : Map[String, Bool],
  block_function_kinds : Map[String, Int],
  include_block_functions? : Bool = false,
  allow_duplicate_block_functions? : Bool = false,
) -> Unit raise Error {
  match stmt {
    VarDecl(LetKind, name, _, _) => add_lexical_decl_name(lexical_names, name)
    VarDecl(ConstKind, name, _, _) => add_lexical_decl_name(lexical_names, name)
    DestructureDecl(LetKind, pattern, _, _) =>
      collect_pattern_decl_names(pattern, lexical_names, lexical=true)
    DestructureDecl(ConstKind, pattern, _, _) =>
      collect_pattern_decl_names(pattern, lexical_names, lexical=true)
    ClassDecl(name, _, _, _) => add_lexical_decl_name(lexical_names, name)
    // Function declarations are lexical only in block statement lists.
    FuncDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          if !(allow_duplicate_block_functions &&
            block_function_kinds.get(name) == Some(1)) {
            raise @errors.SyntaxError(
              message="Identifier '\{name}' has already been declared",
            )
          }
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 1
      }
    FuncDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          if !(allow_duplicate_block_functions &&
            block_function_kinds.get(name) == Some(1)) {
            raise @errors.SyntaxError(
              message="Identifier '\{name}' has already been declared",
            )
          }
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 1
      }
    GeneratorDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    GeneratorDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncFuncDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncFuncDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncGeneratorDecl(name, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names[name] = true
        }
        block_function_kinds[name] = 2
      }
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_block_lexical_decl_names_from_stmt(
          inner,
          lexical_names,
          block_function_kinds,
          include_block_functions~,
          allow_duplicate_block_functions~,
        )
      }
    ExportNamedDecl(Some(decl), _, _, _) =>
      collect_block_lexical_decl_names_from_stmt(
        decl,
        lexical_names,
        block_function_kinds,
        include_block_functions~,
        allow_duplicate_block_functions~,
      )
    _ => ()
  }
}

///|
fn collect_block_var_decl_names_from_stmt(
  stmt : @ast.Stmt,
  var_names : Map[String, Bool],
  include_function_decls? : Bool = false,
  in_block? : Bool = false,
) -> Unit raise Error {
  // Spec (§8.2.10 TopLevelVarDeclaredNames): FunctionDeclarations count as
  // var-declared names only at the top level of a ScriptBody or FunctionBody.
  // Once we descend into a Block, nested `function f` is a LEXICAL binding
  // of that block per §13.2.6; Annex B §B.3.3 handles promotion separately
  // with a skip check we cannot do here. So we honor `include_function_decls`
  // only while `in_block` is false.
  let count_funcs = include_function_decls && !in_block
  match stmt {
    VarDecl(VarKind, name, _, _) => var_names[name] = true
    FuncDecl(name, _, _, _) => if count_funcs { var_names[name] = true }
    FuncDeclExt(name, _, _, _, _) => if count_funcs { var_names[name] = true }
    GeneratorDecl(name, _, _, _) => if count_funcs { var_names[name] = true }
    GeneratorDeclExt(name, _, _, _, _) =>
      if count_funcs {
        var_names[name] = true
      }
    AsyncFuncDecl(name, _, _, _) => if count_funcs { var_names[name] = true }
    AsyncFuncDeclExt(name, _, _, _, _) =>
      if count_funcs {
        var_names[name] = true
      }
    AsyncGeneratorDecl(name, _, _, _) =>
      if count_funcs {
        var_names[name] = true
      }
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      if count_funcs {
        var_names[name] = true
      }
    DestructureDecl(VarKind, pattern, _, _) =>
      collect_pattern_decl_names(pattern, var_names)
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
          in_block=true,
        )
      }
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
          in_block~,
        )
      }
    IfStmt(_, then_branch, else_branch, _) => {
      collect_block_var_decl_names_from_stmt(
        then_branch,
        var_names,
        include_function_decls~,
        in_block~,
      )
      match else_branch {
        Some(eb) =>
          collect_block_var_decl_names_from_stmt(
            eb,
            var_names,
            include_function_decls~,
            in_block~,
          )
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    DoWhileStmt(body, _, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          collect_block_var_decl_names_from_stmt(
            init_stmt,
            var_names,
            include_function_decls~,
            in_block~,
          )
        None => ()
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    }
    ForInStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        var_names[name] = true
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    }
    ForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        var_names[name] = true
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_decl_names(pattern, var_names)
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    }
    ForOfStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_decl_names(pattern, var_names)
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    }
    ForInExpr(_, _, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    ForOfExpr(_, _, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    LabeledStmt(_, inner, _) =>
      collect_block_var_decl_names_from_stmt(
        inner,
        var_names,
        include_function_decls~,
        in_block~,
      )
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          collect_block_var_decl_names_from_stmt(
            inner,
            var_names,
            include_function_decls~,
            in_block~,
          )
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
          in_block~,
        )
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            collect_block_var_decl_names_from_stmt(
              inner,
              var_names,
              include_function_decls~,
              in_block~,
            )
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            collect_block_var_decl_names_from_stmt(
              inner,
              var_names,
              include_function_decls~,
              in_block~,
            )
          }
        None => ()
      }
    }
    WithStmt(_, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
        in_block~,
      )
    ExportNamedDecl(Some(decl), _, _, _) =>
      collect_block_var_decl_names_from_stmt(
        decl,
        var_names,
        include_function_decls~,
        in_block~,
      )
    // Do not recurse into function/class bodies when collecting VarDeclaredNames
    // for the surrounding block.
    _ => ()
  }
}

///|
fn validate_block_statement_list_early_errors(
  stmts : Array[@ast.Stmt],
  include_block_functions? : Bool = false,
  allow_duplicate_block_functions? : Bool = false,
  include_function_decls_in_var_names? : Bool = false,
) -> Unit raise Error {
  let lexical_names : Map[String, Bool] = {}
  let block_function_kinds : Map[String, Int] = {}
  for stmt in stmts {
    collect_block_lexical_decl_names_from_stmt(
      stmt,
      lexical_names,
      block_function_kinds,
      include_block_functions~,
      allow_duplicate_block_functions~,
    )
  }
  let var_names : Map[String, Bool] = {}
  for stmt in stmts {
    collect_block_var_decl_names_from_stmt(
      stmt,
      var_names,
      include_function_decls=include_function_decls_in_var_names,
    )
  }
  for name, _ in lexical_names {
    if var_names.contains(name) {
      raise @errors.SyntaxError(
        message="Identifier '\{name}' has already been declared",
      )
    }
  }
}

///|
fn validate_block_early_errors_expr(
  expr : @ast.Expr,
  strict_context : Bool,
) -> Unit raise Error {
  match expr {
    FuncExpr(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    FuncExprExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    ArrowFunc(_, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    ArrowFuncExt(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    GeneratorExpr(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    GeneratorExprExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    AsyncFuncExpr(_, _, body, _)
    | AsyncFuncExprExt(_, _, _, body, _)
    | AsyncArrowFunc(_, body, _)
    | AsyncArrowFuncExt(_, _, body, _)
    | AsyncGeneratorExpr(_, _, body, _)
    | AsyncGeneratorExprExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for stmt in body {
        validate_block_early_errors_stmt(stmt, child_strict)
      }
    }
    AwaitExpr(inner, _) =>
      validate_block_early_errors_expr(inner, strict_context)
    ClassExpr(_, _, members, _) =>
      for mbr in members {
        match mbr {
          @ast.ClassMember::Method(m) =>
            // Class bodies are always strict.
            validate_block_early_errors_expr(m.value, true)
          @ast.ClassMember::Field(f) => {
            if f.computed {
              validate_block_early_errors_expr(f.key, true)
            }
            match f.initializer {
              Some(expr) => validate_block_early_errors_expr(expr, true)
              None => ()
            }
          }
        }
      }
    Binary(_, l, r, _) => {
      validate_block_early_errors_expr(l, strict_context)
      validate_block_early_errors_expr(r, strict_context)
    }
    Unary(_, e, _) => validate_block_early_errors_expr(e, strict_context)
    Assign(_, e, _) => validate_block_early_errors_expr(e, strict_context)
    Call(callee, args, _) => {
      validate_block_early_errors_expr(callee, strict_context)
      for a in args {
        validate_block_early_errors_expr(a, strict_context)
      }
    }
    Member(obj, _, _) => validate_block_early_errors_expr(obj, strict_context)
    Ternary(c, t, f, _) => {
      validate_block_early_errors_expr(c, strict_context)
      validate_block_early_errors_expr(t, strict_context)
      validate_block_early_errors_expr(f, strict_context)
    }
    Grouping(inner, _) =>
      validate_block_early_errors_expr(inner, strict_context)
    ObjectLit(props, _) =>
      for prop in props {
        validate_block_early_errors_expr(prop.key, strict_context)
        validate_block_early_errors_expr(prop.value, strict_context)
      }
    ArrayLit(elements, _) =>
      for e in elements {
        validate_block_early_errors_expr(e, strict_context)
      }
    ComputedMember(obj, key, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(key, strict_context)
    }
    MemberAssign(obj, _, rhs, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(rhs, strict_context)
    }
    ComputedAssign(obj, key, rhs, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(key, strict_context)
      validate_block_early_errors_expr(rhs, strict_context)
    }
    NewExpr(callee, args, _) => {
      validate_block_early_errors_expr(callee, strict_context)
      for a in args {
        validate_block_early_errors_expr(a, strict_context)
      }
    }
    UpdateExpr(_, target, _, _) =>
      validate_block_early_errors_expr(target, strict_context)
    CompoundAssign(_, lhs, rhs, _) => {
      validate_block_early_errors_expr(lhs, strict_context)
      validate_block_early_errors_expr(rhs, strict_context)
    }
    Comma(l, r, _) => {
      validate_block_early_errors_expr(l, strict_context)
      validate_block_early_errors_expr(r, strict_context)
    }
    TemplateLit(_, exprs, _) =>
      for e in exprs {
        validate_block_early_errors_expr(e, strict_context)
      }
    SpreadExpr(e, _) => validate_block_early_errors_expr(e, strict_context)
    DestructureAssign(_, rhs, _) =>
      validate_block_early_errors_expr(rhs, strict_context)
    OptionalMember(obj, _, _) =>
      validate_block_early_errors_expr(obj, strict_context)
    OptionalComputedMember(obj, key, _) => {
      validate_block_early_errors_expr(obj, strict_context)
      validate_block_early_errors_expr(key, strict_context)
    }
    OptionalCall(callee, args, _) => {
      validate_block_early_errors_expr(callee, strict_context)
      for a in args {
        validate_block_early_errors_expr(a, strict_context)
      }
    }
    SuperComputedMember(e, _) =>
      validate_block_early_errors_expr(e, strict_context)
    TaggedTemplate(tag, _, exprs, _) => {
      validate_block_early_errors_expr(tag, strict_context)
      for e in exprs {
        validate_block_early_errors_expr(e, strict_context)
      }
    }
    _ => ()
  }
}

///|
fn validate_block_early_errors_stmt(
  stmt : @ast.Stmt,
  strict_context : Bool,
) -> Unit raise Error {
  match stmt {
    Block(stmts, _) => {
      validate_block_statement_list_early_errors(
        stmts,
        include_block_functions=true,
        allow_duplicate_block_functions=!strict_context,
      )
      for inner in stmts {
        validate_block_early_errors_stmt(inner, strict_context)
      }
    }
    StmtList(stmts, _) =>
      for inner in stmts {
        validate_block_early_errors_stmt(inner, strict_context)
      }
    ExprStmt(expr, _) => validate_block_early_errors_expr(expr, strict_context)
    IfStmt(_, then_branch, else_branch, _) => {
      validate_block_early_errors_stmt(then_branch, strict_context)
      match else_branch {
        Some(eb) => validate_block_early_errors_stmt(eb, strict_context)
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    DoWhileStmt(body, _, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          validate_block_early_errors_stmt(init_stmt, strict_context)
        None => ()
      }
      validate_block_early_errors_stmt(body, strict_context)
    }
    ForInStmt(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForOfStmt(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForInStmtPat(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForOfStmtPat(_, _, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForInExpr(_, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    ForOfExpr(_, _, body, _) =>
      validate_block_early_errors_stmt(body, strict_context)
    LabeledStmt(_, inner, _) =>
      validate_block_early_errors_stmt(inner, strict_context)
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          validate_block_early_errors_stmt(inner, strict_context)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        validate_block_early_errors_stmt(inner, strict_context)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            validate_block_early_errors_stmt(inner, strict_context)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            validate_block_early_errors_stmt(inner, strict_context)
          }
        None => ()
      }
    }
    FuncDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    FuncDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    GeneratorDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    GeneratorDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncFuncDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncFuncDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncGeneratorDecl(_, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    AsyncGeneratorDeclExt(_, _, _, body, _) => {
      validate_block_statement_list_early_errors(
        body,
        include_function_decls_in_var_names=true,
      )
      let child_strict = is_function_strict(strict_context, body)
      for inner in body {
        validate_block_early_errors_stmt(inner, child_strict)
      }
    }
    ClassDecl(_, _, members, _) =>
      for mbr in members {
        match mbr {
          @ast.ClassMember::Method(m) =>
            // Class bodies are always strict.
            validate_block_early_errors_expr(m.value, true)
          @ast.ClassMember::Field(f) => {
            if f.computed {
              validate_block_early_errors_expr(f.key, true)
            }
            match f.initializer {
              Some(expr) => validate_block_early_errors_expr(expr, true)
              None => ()
            }
          }
        }
      }
    WithStmt(_, body, _) => {
      if strict_context {
        raise @errors.SyntaxError(
          message="Strict mode code may not include a with statement",
        )
      }
      validate_block_early_errors_stmt(body, strict_context)
    }
    ExportNamedDecl(Some(decl), _, _, _) =>
      validate_block_early_errors_stmt(decl, strict_context)
    ExportDefaultDecl(expr, _) =>
      validate_block_early_errors_expr(expr, strict_context)
    _ => ()
  }
}

///|
fn Interpreter::validate_block_early_errors(
  _self : Interpreter,
  stmts : Array[@ast.Stmt],
  strict_context : Bool,
) -> Unit raise Error {
  // Validate lexical-vs-var conflicts for the current statement list itself.
  // This is required for script/function/eval bodies, not just nested Block nodes.
  validate_block_statement_list_early_errors(
    stmts,
    include_function_decls_in_var_names=true,
  )
  for stmt in stmts {
    validate_block_early_errors_stmt(stmt, strict_context)
  }
}

///|
/// Collect all var-scoped declaration names from eval code.
/// Used by EvalDeclarationInstantiation to check for var/lex conflicts.
fn collect_eval_var_names_from_stmt(
  stmt : @ast.Stmt,
  names : Array[String],
  in_block? : Bool = false,
) -> Unit raise Error {
  match stmt {
    VarDecl(VarKind, name, _, _) => names.push(name)
    FuncDecl(name, _, _, _) => if !in_block { names.push(name) }
    FuncDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    GeneratorDecl(name, _, _, _) => if !in_block { names.push(name) }
    GeneratorDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    AsyncFuncDecl(name, _, _, _) => if !in_block { names.push(name) }
    AsyncFuncDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    AsyncGeneratorDecl(name, _, _, _) => if !in_block { names.push(name) }
    AsyncGeneratorDeclExt(name, _, _, _, _) => if !in_block { names.push(name) }
    DestructureDecl(VarKind, pattern, _, _) =>
      collect_pattern_var_names(pattern, names)
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_eval_var_names_from_stmt(inner, names, in_block~)
      }
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_eval_var_names_from_stmt(inner, names, in_block=true)
      }
    IfStmt(_, then_branch, else_branch, _) => {
      // Statement-position function declarations in if branches should not be
      // treated as leaked var names for eval conflict checks.
      collect_eval_var_names_from_stmt(then_branch, names, in_block=true)
      match else_branch {
        Some(eb) => collect_eval_var_names_from_stmt(eb, names, in_block=true)
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    DoWhileStmt(body, _, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          collect_eval_var_names_from_stmt(init_stmt, names, in_block~)
        None => ()
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForInStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        names.push(name)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) {
        names.push(name)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_var_names(pattern, names)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForOfStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        collect_pattern_var_names(pattern, names)
      }
      collect_eval_var_names_from_stmt(body, names, in_block~)
    }
    ForInExpr(_, _, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    ForOfExpr(_, _, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    LabeledStmt(_, inner, _) =>
      collect_eval_var_names_from_stmt(inner, names, in_block=true)
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          collect_eval_var_names_from_stmt(inner, names, in_block~)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        collect_eval_var_names_from_stmt(inner, names, in_block~)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            collect_eval_var_names_from_stmt(inner, names, in_block~)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            collect_eval_var_names_from_stmt(inner, names, in_block~)
          }
        None => ()
      }
    }
    WithStmt(_, body, _) =>
      collect_eval_var_names_from_stmt(body, names, in_block~)
    ExportNamedDecl(Some(decl), _, _, _) =>
      collect_eval_var_names_from_stmt(decl, names, in_block~)
    _ => ()
  }
}

///|
fn collect_eval_var_names(
  stmts : Array[@ast.Stmt],
) -> Array[String] raise Error {
  let names : Array[String] = []
  for stmt in stmts {
    collect_eval_var_names_from_stmt(stmt, names)
  }
  names
}

///|
fn hoist_pattern(pattern : @ast.Pattern, env : Environment) -> Unit raise Error {
  walk_pattern_idents(pattern, name => {
    if !env.bindings.contains(name) {
      env.def(name, Undefined, VarBinding)
    }
  })
}

///|
fn hoist_var_declarations_from_stmt(
  stmt : @ast.Stmt,
  env : Environment,
) -> Unit raise Error {
  match stmt {
    VarDecl(VarKind, name, _, _) =>
      if !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
    DestructureDecl(VarKind, pattern, _, _) => hoist_pattern(pattern, env)
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        hoist_var_declarations_from_stmt(inner, env)
      }
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        hoist_var_declarations_from_stmt(inner, env)
      }
    IfStmt(_, then_branch, else_branch, _) => {
      hoist_var_declarations_from_stmt(then_branch, env)
      match else_branch {
        Some(eb) => hoist_var_declarations_from_stmt(eb, env)
        None => ()
      }
    }
    WhileStmt(_, body, _) => hoist_var_declarations_from_stmt(body, env)
    DoWhileStmt(body, _, _) => hoist_var_declarations_from_stmt(body, env)
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) => hoist_var_declarations_from_stmt(init_stmt, env)
        None => ()
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForInStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) && !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForOfStmt(kind, name, _, body, _) => {
      if kind == Some(VarKind) && !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        hoist_pattern(pattern, env)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForOfStmtPat(kind, pattern, _, body, _) => {
      if kind == Some(VarKind) {
        hoist_pattern(pattern, env)
      }
      hoist_var_declarations_from_stmt(body, env)
    }
    ForInExpr(_, _, body, _) => hoist_var_declarations_from_stmt(body, env)
    ForOfExpr(_, _, body, _) => hoist_var_declarations_from_stmt(body, env)
    LabeledStmt(_, inner, _) => hoist_var_declarations_from_stmt(inner, env)
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          hoist_var_declarations_from_stmt(inner, env)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        hoist_var_declarations_from_stmt(inner, env)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            hoist_var_declarations_from_stmt(inner, env)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            hoist_var_declarations_from_stmt(inner, env)
          }
        None => ()
      }
    }
    WithStmt(_, body, _) => hoist_var_declarations_from_stmt(body, env)
    // Export with declaration: hoist declarations from the inner declaration.
    ExportNamedDecl(Some(decl), _, _, _) =>
      hoist_var_declarations_from_stmt(decl, env)
    // Do not recurse into function/class declarations: their bodies create
    // separate var scopes.
    _ => ()
  }
}

///|
/// Annex B §B.3.3.3: record a block-level function as an eligible var binding
/// on `var_env`. Creates a new `VarBinding` initialized to Undefined if absent,
/// or simply tags an existing compatible binding (including a parameter stored
/// as `LetBinding`) so that the runtime block-entry reinit in `exec_stmt.mbt`
/// is allowed to update it.
fn tag_annex_b_hoisted(
  interp : Interpreter,
  var_env : Environment,
  name : String,
) -> Unit {
  match var_env.bindings.get(name) {
    // §B.3.4 skip check: the extension only applies if replacing the
    // FunctionDeclaration with `var name` would not be an Early Error. A
    // pre-existing let/const/class in the var env makes `var name` illegal,
    // so we must not tag — otherwise the later block-entry reinit would
    // overwrite an immutable lexical binding via direct `binding.value = ...`
    // (bypassing `Environment::assign` const enforcement). Parameters share
    // `BindingKind::LetBinding` with real `let` in the same environment
    // (when there are no param defaults), so `is_parameter` is the only
    // runtime-distinguishable signal.
    Some(existing) =>
      if existing.kind == VarBinding || existing.is_parameter {
        existing.annex_b_hoisted = true
      }
    None => {
      var_env.bindings[name] = {
        value: Undefined,
        kind: VarBinding,
        initialized: true,
        annex_b_hoisted: true,
        is_parameter: false,
      }
      // Mirror to globalThis when the var env IS the global env — matches
      // the normal hoist path in `hoist_declarations`.
      if physical_equal(var_env, interp.global) {
        interp.mirror_to_global(name, Undefined)
      }
    }
  }
}

///|
/// Add `let` / `const` / `class` names introduced by a single statement to
/// `names`. Non-recursive — blocks, function bodies, loop bodies, etc. are
/// NOT descended into; the caller controls scope granularity. The
/// `ExportNamedDecl` wrapper is unwrapped so `export let x = …` participates.
/// `StmtList` IS descended into: the parser emits it as a flat carrier for
/// comma-separated declarations (`let f=1, g=2` → `StmtList([VarDecl,
/// VarDecl])`), not a new scope, so its inner decls belong to the same lex
/// frame as the surrounding statements.
fn add_stmt_lex_names(
  stmt : @ast.Stmt,
  names : Map[String, Bool],
) -> Unit raise Error {
  match stmt {
    VarDecl(LetKind, name, _, _) | VarDecl(ConstKind, name, _, _) =>
      names[name] = true
    ClassDecl(name, _, _, _) => names[name] = true
    DestructureDecl(LetKind, pattern, _, _)
    | DestructureDecl(ConstKind, pattern, _, _) =>
      collect_pattern_lex_names(pattern, names)
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        add_stmt_lex_names(inner, names)
      }
    ExportNamedDecl(Some(decl), _, _, _) => add_stmt_lex_names(decl, names)
    _ => ()
  }
}

///|
/// Walk a pattern and record every `IdentPat` name into `names`. Used for
/// `let` / `const` destructuring declarations and for-loop heads.
fn collect_pattern_lex_names(
  pattern : @ast.Pattern,
  names : Map[String, Bool],
) -> Unit raise Error {
  walk_pattern_idents(pattern, name => names[name] = true)
}

///|
/// Collect lexically-declared names (§8.2.10 TopLevelLexicallyDeclaredNames)
/// from a statement list — `let` / `const` / `class` at the given scope, with
/// no recursion into Block, function body, switch case, loop body, catch
/// block, or `with` body. Suitable for both eval top level (§B.3.3.3 skip
/// check) and for per-block lex frames pushed onto the AST walk stack.
fn collect_stmts_lex_names(
  stmts : Array[@ast.Stmt],
) -> Map[String, Bool] raise Error {
  let names : Map[String, Bool] = {}
  for stmt in stmts {
    add_stmt_lex_names(stmt, names)
  }
  names
}

///|
/// Annex B §B.3.3.3 skip check: true iff replacing a `function F` nested in a
/// block/switch/loop-body with `var F` would produce an early error — i.e. `F`
/// is a lexically-declared name somewhere between the candidate site and the
/// eval var env.
///
/// Inputs:
///   - `name` — the candidate function name.
///   - `top_lex` — eval body's top-level lex names (let/const/class).
///   - `lex_stack` — stack of lex-name frames pushed as the AST walk enters
///     enclosing syntactic lex scopes (Block, for-head, switch case-block).
///     Each frame collects names introduced AT that scope (not inherited).
///
/// Per Codex review (§B.3.4), the catch binding is transparent for eval
/// conflict checks, so catch parameters are NOT pushed onto `lex_stack`.
/// Per §19.2.1.3 step 3.d, Object Environment Records (`with` bodies) are
/// ignored — `with` pushes nothing.
fn annex_b_candidate_conflicts(
  name : String,
  top_lex : Map[String, Bool],
  lex_stack : Array[Map[String, Bool]],
  excluded? : Map[String, Bool] = {},
) -> Bool {
  // §B.3.2.1 step ii parameter carve-out: when called from a function body,
  // `excluded` contains formal parameter names (plus "arguments" when the
  // arguments object exists). Per the spec, those are NOT candidates —
  // the extension is skipped so the param / arguments binding survives.
  // Eval (§B.3.2.3) passes `excluded` empty; SetMutableBinding in step
  // 10.d.iii permits overwrites, matching current behavior.
  if excluded.contains(name) {
    return true
  }
  if top_lex.contains(name) {
    return true
  }
  for frame in lex_stack {
    if frame.contains(name) {
      return true
    }
  } nobreak {
    false
  }
}

///|
/// Collect the lex names introduced at the top level of a single block's
/// statement list: let, const, class only.
///
/// Annex B §B.3.3.3: walk an eval body AST and hoist each eligible
/// block-level function declaration as a var binding on `var_env`.
///
/// The walk maintains a syntactic lex-scope stack. When entering a `Block`,
/// the block's own lex names are pushed; popped on exit. Loop-head lex
/// decls, switch-case scopes, finally bodies, and labeled/if branches follow
/// the same pattern. Function and class bodies are NOT traversed (they have
/// their own hoist pass when called).
///
/// For each candidate `function F` found at a block-nested position:
///   - If `F` conflicts per `annex_b_candidate_conflicts`, SKIP the extension.
///   - Otherwise tag `F` on `var_env` via `tag_annex_b_hoisted`.
fn hoist_eval_annex_b_candidates(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
  var_env : Environment,
  top_lex : Map[String, Bool],
  excluded? : Map[String, Bool] = {},
) -> Unit raise Error {
  let stack : Array[Map[String, Bool]] = []
  for stmt in stmts {
    walk_eval_annex_b_stmt(
      interp,
      stmt,
      var_env,
      top_lex,
      stack,
      in_block=false,
      excluded~,
    )
  }
}

///|
/// AST walk for B.3.3 candidates. `in_block` is true once we are below a
/// Block/for-head/switch-case/labeled-wrapped-Block/finally/etc. Candidate
/// function decls are only eligible when `in_block` is true.
fn walk_eval_annex_b_stmt(
  interp : Interpreter,
  stmt : @ast.Stmt,
  var_env : Environment,
  top_lex : Map[String, Bool],
  stack : Array[Map[String, Bool]],
  in_block~ : Bool,
  excluded~ : Map[String, Bool],
) -> Unit raise Error {
  match stmt {
    FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
      if in_block &&
        !annex_b_candidate_conflicts(name, top_lex, stack, excluded~) {
        tag_annex_b_hoisted(interp, var_env, name)
      }
    Block(inner_stmts, _) =>
      walk_stmt_list_in_own_frame(
        interp,
        inner_stmts,
        var_env,
        top_lex,
        stack,
        excluded~,
      )
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        walk_eval_annex_b_stmt(
          interp,
          inner,
          var_env,
          top_lex,
          stack,
          in_block~,
          excluded~,
        )
      }
    // §B.3.4: `if (expr) FunctionDeclaration` is treated as if the body
    // were `{ FunctionDeclaration }`. Each branch is a block context for
    // Annex B, so FuncDecls under IfStmt ARE candidates even at the eval
    // top level. If the branch is itself a Block, the Block arm pushes its
    // own frame — no double-pushing.
    IfStmt(_, then_branch, else_branch, _) => {
      walk_eval_annex_b_stmt(
        interp,
        then_branch,
        var_env,
        top_lex,
        stack,
        in_block=true,
        excluded~,
      )
      match else_branch {
        Some(eb) =>
          walk_eval_annex_b_stmt(
            interp,
            eb,
            var_env,
            top_lex,
            stack,
            in_block=true,
            excluded~,
          )
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      walk_eval_annex_b_stmt(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        in_block=true,
        excluded~,
      )
    DoWhileStmt(body, _, _) =>
      walk_eval_annex_b_stmt(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        in_block=true,
        excluded~,
      )
    // §14.7.4: `for (let/const …; ; ) body` makes the init's lex names visible
    // for the body's Annex-B candidate check.
    ForStmt(init, _, _, body, _) =>
      walk_enclosed_body(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        for_init_lex_names(init),
        excluded~,
      )
    ForInStmt(kind, name, _, body, _) => {
      let frame : Map[String, Bool] = {}
      if kind is (Some(LetKind) | Some(ConstKind)) {
        frame[name] = true
      }
      walk_enclosed_body(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        frame,
        excluded~,
      )
    }
    ForOfStmt(kind, name, _, body, _) => {
      let frame : Map[String, Bool] = {}
      if kind is (Some(LetKind) | Some(ConstKind)) {
        frame[name] = true
      }
      walk_enclosed_body(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        frame,
        excluded~,
      )
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      let frame : Map[String, Bool] = {}
      if kind is (Some(LetKind) | Some(ConstKind)) {
        collect_pattern_lex_names(pattern, frame)
      }
      walk_enclosed_body(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        frame,
        excluded~,
      )
    }
    ForOfStmtPat(kind, pattern, _, body, _) => {
      let frame : Map[String, Bool] = {}
      if kind is (Some(LetKind) | Some(ConstKind)) {
        collect_pattern_lex_names(pattern, frame)
      }
      walk_enclosed_body(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        frame,
        excluded~,
      )
    }
    ForInExpr(_, _, body, _) =>
      walk_eval_annex_b_stmt(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        in_block=true,
        excluded~,
      )
    ForOfExpr(_, _, body, _) =>
      walk_eval_annex_b_stmt(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        in_block=true,
        excluded~,
      )
    // §B.3.3 + §14.13: a `label:`-wrapped FuncDecl is an Annex B candidate
    // just like a plain block FuncDecl. Mirror the IfStmt treatment — the
    // inner is a block context, so pass `in_block=true`.
    LabeledStmt(_, inner, _) =>
      walk_eval_annex_b_stmt(
        interp,
        inner,
        var_env,
        top_lex,
        stack,
        in_block=true,
        excluded~,
      )
    // §14.12.3: all case clauses share one lex scope. Frame excludes
    // FuncDecls for the same reason `collect_stmts_lex_names` does — a
    // candidate `function F` in one case must not self-conflict. Duplicate
    // lex declarations across cases are caught by the early-error validator.
    SwitchStmt(_, cases, _) => {
      let frame : Map[String, Bool] = {}
      for case_ in cases {
        for inner in case_.body {
          add_stmt_lex_names(inner, frame)
        }
      }
      stack.push(frame)
      for case_ in cases {
        for inner in case_.body {
          walk_eval_annex_b_stmt(
            interp,
            inner,
            var_env,
            top_lex,
            stack,
            in_block=true,
            excluded~,
          )
        }
      }
      let _ = stack.pop()
    }
    // Per §B.3.4, the catch parameter is transparent for eval conflict
    // checks — so try / catch-body / finally are each just nested Blocks.
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      walk_stmt_list_in_own_frame(
        interp,
        try_body,
        var_env,
        top_lex,
        stack,
        excluded~,
      )
      match catch_body {
        Some(cb) =>
          walk_stmt_list_in_own_frame(
            interp,
            cb,
            var_env,
            top_lex,
            stack,
            excluded~,
          )
        None => ()
      }
      match finally_body {
        Some(fb) =>
          walk_stmt_list_in_own_frame(
            interp,
            fb,
            var_env,
            top_lex,
            stack,
            excluded~,
          )
        None => ()
      }
    }
    WithStmt(_, body, _) =>
      // Object env record — no lex frame pushed.
      walk_eval_annex_b_stmt(
        interp,
        body,
        var_env,
        top_lex,
        stack,
        in_block=true,
        excluded~,
      )
    ExportNamedDecl(Some(decl), _, _, _) =>
      walk_eval_annex_b_stmt(
        interp,
        decl,
        var_env,
        top_lex,
        stack,
        in_block~,
        excluded~,
      )
    // Function / class bodies: do NOT traverse. They have their own B.3.3
    // hoist on call (§B.3.2.1), operating in a fresh scope.
    _ => ()
  }
}

///|
/// Treat `stmts` as a block: collect its lex names as the pushed frame, walk
/// each statement with `in_block=true`, pop. Shared by the Block variant and
/// the three bodies of a try-catch-finally.
fn walk_stmt_list_in_own_frame(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
  var_env : Environment,
  top_lex : Map[String, Bool],
  stack : Array[Map[String, Bool]],
  excluded~ : Map[String, Bool],
) -> Unit raise Error {
  stack.push(collect_stmts_lex_names(stmts))
  for inner in stmts {
    walk_eval_annex_b_stmt(
      interp,
      inner,
      var_env,
      top_lex,
      stack,
      in_block=true,
      excluded~,
    )
  }
  let _ = stack.pop()
}

///|
/// Push `frame` onto `stack`, walk `body` with `in_block=true`, pop. Used by
/// every loop-body variant in `walk_eval_annex_b_stmt` to avoid repeating the
/// push/walk/pop boilerplate five times.
fn walk_enclosed_body(
  interp : Interpreter,
  body : @ast.Stmt,
  var_env : Environment,
  top_lex : Map[String, Bool],
  stack : Array[Map[String, Bool]],
  frame : Map[String, Bool],
  excluded~ : Map[String, Bool],
) -> Unit raise Error {
  stack.push(frame)
  walk_eval_annex_b_stmt(
    interp,
    body,
    var_env,
    top_lex,
    stack,
    in_block=true,
    excluded~,
  )
  let _ = stack.pop()
}

///|
/// Extract lex (let/const) names introduced by a for-loop init. An init of
/// `StmtList(inner, _)` is the comma-separated `for (let a=1, b=2; …)` shape
/// — unwrap it one level so each inner declaration contributes.
fn for_init_lex_names(init : @ast.Stmt?) -> Map[String, Bool] raise Error {
  let names : Map[String, Bool] = {}
  match init {
    Some(StmtList(inner, _)) =>
      for s in inner {
        add_stmt_lex_names(s, names)
      }
    Some(init_stmt) => add_stmt_lex_names(init_stmt, names)
    None => ()
  }
  names
}

///|
/// Hoist a body's var / function / let / const / class declarations into
/// `env`. When the caller has split §10.2.11 function scope into a distinct
/// `param_env` (holding formal params + `arguments`) and a `body_env`
/// (passed as `env` here), the caller supplies `param_source=Some(param_env)`
/// so the Annex B §B.3.2.1 skip check's exclusion set is populated from the
/// param env's `is_parameter` bindings rather than from `env` (which has
/// none in the split case). Scripts, modules, and non-Ext single-env call
/// paths omit `param_source` and keep scanning `env`.
fn Interpreter::hoist_declarations(
  _self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
  strict? : Bool = false,
  suppress_annex_b_candidates? : Bool = false,
  param_source? : Environment? = None,
) -> Unit raise Error {
  let is_global = physical_equal(env, _self.global)
  for stmt in stmts {
    match stmt {
      VarDecl(VarKind, name, _, _) =>
        if !env.bindings.contains(name) {
          env.def(name, Undefined, VarBinding)
          // Mirror var declaration to global object per ES spec
          if is_global {
            _self.mirror_to_global(name, Undefined)
          }
        }
      FuncDecl(name, params, body, _) => {
        validate_function_signature(strict, Some(name), params, body)
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(strict, body),
        }
        let func_val = make_func(func_data)
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
        // Mirror function declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, func_val)
        }
      }
      FuncDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_data : FuncDataExt = {
          name: Some(name),
          params,
          rest_param,
          body,
          closure: env,
          strict: is_function_strict(strict, body),
        }
        let func_val = make_func_ext(func_data)
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
        // Mirror function declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, func_val)
        }
      }
      GeneratorDecl(name, params, body, _) => {
        validate_function_signature(strict, Some(name), params, body)
        let gen_func = _self.make_generator_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
        // Mirror generator declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, gen_func)
        }
      }
      GeneratorDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let gen_func = _self.make_generator_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          is_function_strict(strict, body),
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
        // Mirror generator declaration to global object per ES spec
        if is_global {
          _self.mirror_to_global(name, gen_func)
        }
      }
      AsyncFuncDecl(name, params, body, _) => {
        validate_function_signature(strict, Some(name), params, body)
        let async_func = _self.make_async_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, async_func)
        } else {
          env.def(name, async_func, VarBinding)
        }
      }
      AsyncFuncDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let async_func = _self.make_async_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          is_function_strict(strict, body),
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, async_func)
        } else {
          env.def(name, async_func, VarBinding)
        }
      }
      AsyncGeneratorDecl(name, params, body, _) => {
        validate_function_signature(strict, Some(name), params, body)
        let gen_func = _self.make_async_generator_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
      }
      AsyncGeneratorDeclExt(name, params, rest_param, body, _) => {
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let gen_func = _self.make_async_generator_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          is_function_strict(strict, body),
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
      }
      DestructureDecl(VarKind, pattern, _, _) => hoist_pattern(pattern, env)
      StmtList(inner_stmts, _) =>
        // Recursively hoist declarations from StmtList (comma-separated decls)
        for inner in inner_stmts {
          match inner {
            VarDecl(VarKind, name, _, _) =>
              if !env.bindings.contains(name) {
                env.def(name, Undefined, VarBinding)
              }
            DestructureDecl(VarKind, pattern, _, _) =>
              hoist_pattern(pattern, env)
            _ => ()
          }
        }
      // Export with declaration: hoist the inner declaration
      ExportNamedDecl(Some(decl), _, _, _) => {
        let inner_stmts : Array[@ast.Stmt] = [decl]
        _self.hoist_declarations(inner_stmts, env, strict~)
      }
      // export default function name() {} - hoist the named function
      ExportDefaultDecl(FuncExpr(Some(name), params, body, _), _) => {
        validate_function_signature(strict, Some(name), params, body)
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(strict, body),
        }
        if env.bindings.contains(name) {
          env.assign(name, make_func(func_data))
        } else {
          env.def(name, make_func(func_data), VarBinding)
        }
      }
      ExportDefaultDecl(FuncExprExt(Some(name), params, rest_param, body, _), _) => {
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_data : FuncDataExt = {
          name: Some(name),
          params,
          rest_param,
          body,
          closure: env,
          strict: is_function_strict(strict, body),
        }
        if env.bindings.contains(name) {
          env.assign(name, make_func_ext(func_data))
        } else {
          env.def(name, make_func_ext(func_data), VarBinding)
        }
      }
      _ => ()
    }
    // Hoist var declarations recursively through nested statements
    // (e.g. var inside blocks still hoists to function/global var scope).
    hoist_var_declarations_from_stmt(stmt, env)
  }
  // Annex B §B.3.2.1: Hoist block-level FunctionDeclarations into the
  // containing function / script var env, with the syntactic skip check
  // from §B.3.4 — tag only when the candidate name does not conflict with
  // an enclosing lex-declared name. The same walker powers eval-scope
  // hoisting (§B.3.2.3); eval callers suppress this pass and run it
  // themselves in `perform_eval` so they can slot the call between var
  // hoisting and TDZ setup.
  if _self.annex_b && !strict && !suppress_annex_b_candidates {
    let top_lex = collect_stmts_lex_names(stmts)
    // §B.3.2.1 step ii parameter carve-out: skip the extension when the
    // candidate name is a formal parameter of the enclosing function, or
    // the distinguished name "arguments" (§10.2.11 step 22.f appends it to
    // parameterNames). Populate `excluded` by scanning `env`: formal params
    // are marked `is_parameter=true` by `Environment::def_parameter`, and
    // `arguments` is installed as a VarBinding during function-call setup.
    // Script / module top-level envs have no such bindings, so `excluded`
    // stays empty and no names are skipped.
    let excluded : Map[String, Bool] = {}
    // In the split (§10.2.11) case, param/"arguments" bindings live on
    // `param_source`, not `env` (= body_env). Fall back to `env` when no
    // split (scripts/modules/non-Ext single-env paths).
    let scan_env = match param_source {
      Some(p) => p
      None => env
    }
    for name, binding in scan_env.bindings {
      if binding.is_parameter {
        excluded[name] = true
      }
    }
    match scan_env.bindings.get("arguments") {
      Some(b) => if b.kind == VarBinding { excluded["arguments"] = true }
      None => ()
    }
    hoist_eval_annex_b_candidates(_self, stmts, env, top_lex, excluded~)
  }
}

///|
/// Hoist let/const declarations with TDZ markers at block scope
fn hoist_block_tdz(
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Unit raise Error {
  for stmt in stmts {
    match stmt {
      VarDecl(LetKind, name, _, _) =>
        if !env.bindings.contains(name) {
          env.def_tdz(name, LetBinding)
        }
      VarDecl(ConstKind, name, _, _) =>
        if !env.bindings.contains(name) {
          env.def_tdz(name, ConstBinding)
        }
      // DestructureDecl with let/const also needs TDZ
      DestructureDecl(LetKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, LetBinding)
      DestructureDecl(ConstKind, pattern, _, _) =>
        hoist_pattern_tdz(pattern, env, ConstBinding)
      // Class declarations have TDZ (similar to let)
      ClassDecl(name, _, _, _) =>
        if !env.bindings.contains(name) {
          env.def_tdz(name, LetBinding)
        }
      // Export with declaration: hoist let/const inner declarations with TDZ
      ExportNamedDecl(Some(decl), _, _, _) => {
        let inner_stmts : Array[@ast.Stmt] = [decl]
        hoist_block_tdz(inner_stmts, env)
      }
      _ => ()
    }
  }
}

///|
/// Hoist pattern bindings with TDZ markers
fn hoist_pattern_tdz(
  pattern : @ast.Pattern,
  env : Environment,
  kind : BindingKind,
) -> Unit raise Error {
  walk_pattern_idents(pattern, name => {
    if !env.bindings.contains(name) {
      env.def_tdz(name, kind)
    }
  })
}

///|
/// Collect names from a destructuring pattern (for eval var name collection).
fn collect_pattern_var_names(
  pattern : @ast.Pattern,
  names : Array[String],
) -> Unit {
  match pattern {
    IdentPat(name) => names.push(name)
    DefaultPat(inner_pat, _) => collect_pattern_var_names(inner_pat, names)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => collect_pattern_var_names(p, names)
          None => ()
        }
      }
      match rest {
        Some(p) => collect_pattern_var_names(p, names)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        collect_pattern_var_names(prop.value, names)
      }
      match rest {
        Some(p) => collect_pattern_var_names(p, names)
        None => ()
      }
    }
  }
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
  match pattern {
    IdentPat(name) =>
      if lexical {
        add_lexical_decl_name(names, name)
      } else {
        names[name] = true
      }
    DefaultPat(inner_pat, _) =>
      collect_pattern_decl_names(inner_pat, names, lexical~)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => collect_pattern_decl_names(p, names, lexical~)
          None => ()
        }
      }
      match rest {
        Some(p) => collect_pattern_decl_names(p, names, lexical~)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        collect_pattern_decl_names(prop.value, names, lexical~)
      }
      match rest {
        Some(p) => collect_pattern_decl_names(p, names, lexical~)
        None => ()
      }
    }
  }
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
) -> Unit raise Error {
  match stmt {
    VarDecl(VarKind, name, _, _) => var_names[name] = true
    FuncDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    FuncDeclExt(name, _, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    GeneratorDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    GeneratorDeclExt(name, _, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncFuncDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncFuncDeclExt(name, _, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncGeneratorDecl(name, _, _, _) =>
      if include_function_decls {
        var_names[name] = true
      }
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      if include_function_decls {
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
        )
      }
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
        )
      }
    IfStmt(_, then_branch, else_branch, _) => {
      collect_block_var_decl_names_from_stmt(
        then_branch,
        var_names,
        include_function_decls~,
      )
      match else_branch {
        Some(eb) =>
          collect_block_var_decl_names_from_stmt(
            eb,
            var_names,
            include_function_decls~,
          )
        None => ()
      }
    }
    WhileStmt(_, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    DoWhileStmt(body, _, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    ForStmt(init, _, _, body, _) => {
      match init {
        Some(init_stmt) =>
          collect_block_var_decl_names_from_stmt(
            init_stmt,
            var_names,
            include_function_decls~,
          )
        None => ()
      }
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
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
      )
    }
    ForInExpr(_, _, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    ForOfExpr(_, _, body, _) =>
      collect_block_var_decl_names_from_stmt(
        body,
        var_names,
        include_function_decls~,
      )
    LabeledStmt(_, inner, _) =>
      collect_block_var_decl_names_from_stmt(
        inner,
        var_names,
        include_function_decls~,
      )
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          collect_block_var_decl_names_from_stmt(
            inner,
            var_names,
            include_function_decls~,
          )
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        collect_block_var_decl_names_from_stmt(
          inner,
          var_names,
          include_function_decls~,
        )
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            collect_block_var_decl_names_from_stmt(
              inner,
              var_names,
              include_function_decls~,
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
      )
    ExportNamedDecl(Some(decl), _, _, _) =>
      collect_block_var_decl_names_from_stmt(
        decl,
        var_names,
        include_function_decls~,
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
    ClassExpr(_, _, methods, _) =>
      for m in methods {
        // Class bodies are always strict.
        validate_block_early_errors_expr(m.value, true)
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
    ClassDecl(_, _, methods, _) =>
      for m in methods {
        // Class bodies are always strict.
        validate_block_early_errors_expr(m.value, true)
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
) -> Unit {
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
fn collect_eval_var_names(stmts : Array[@ast.Stmt]) -> Array[String] {
  let names : Array[String] = []
  for stmt in stmts {
    collect_eval_var_names_from_stmt(stmt, names)
  }
  names
}

///|
fn hoist_pattern(pattern : @ast.Pattern, env : Environment) -> Unit raise Error {
  match pattern {
    IdentPat(name) =>
      if !env.bindings.contains(name) {
        env.def(name, Undefined, VarBinding)
      }
    DefaultPat(inner_pat, _) => hoist_pattern(inner_pat, env)
    AssignTarget(_) => () // member expressions don't need hoisting
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => hoist_pattern(p, env)
          None => ()
        }
      }
      match rest {
        Some(p) => hoist_pattern(p, env)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        hoist_pattern(prop.value, env)
      }
      match rest {
        Some(p) => hoist_pattern(p, env)
        None => ()
      }
    }
  }
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
/// Annex B.3.3: Scan nested blocks for function declarations and create
/// var bindings in the function scope (initialized to undefined).
/// Only used in sloppy mode with --annex-b.
fn hoist_block_func_declarations(
  stmt : @ast.Stmt,
  var_env : Environment,
) -> Unit raise Error {
  match stmt {
    Block(inner_stmts, _) =>
      for inner in inner_stmts {
        match inner {
          FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
            if !var_env.bindings.contains(name) {
              var_env.def(name, Undefined, VarBinding)
            }
          _ => ()
        }
        hoist_block_func_declarations(inner, var_env)
      }
    IfStmt(_, then_branch, else_branch, _) => {
      // Also handle bare function declarations in if/else branches
      match then_branch {
        FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
          if !var_env.bindings.contains(name) {
            var_env.def(name, Undefined, VarBinding)
          }
        _ => ()
      }
      hoist_block_func_declarations(then_branch, var_env)
      match else_branch {
        Some(eb) => {
          match eb {
            FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
              if !var_env.bindings.contains(name) {
                var_env.def(name, Undefined, VarBinding)
              }
            _ => ()
          }
          hoist_block_func_declarations(eb, var_env)
        }
        None => ()
      }
    }
    WhileStmt(_, body, _) => hoist_block_func_declarations(body, var_env)
    DoWhileStmt(body, _, _) => hoist_block_func_declarations(body, var_env)
    ForStmt(_, _, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForInStmt(_, _, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForOfStmt(_, _, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForInStmtPat(_, _, _, body, _) =>
      hoist_block_func_declarations(body, var_env)
    ForOfStmtPat(_, _, _, body, _) =>
      hoist_block_func_declarations(body, var_env)
    ForInExpr(_, _, body, _) => hoist_block_func_declarations(body, var_env)
    ForOfExpr(_, _, body, _) => hoist_block_func_declarations(body, var_env)
    LabeledStmt(_, inner, _) => hoist_block_func_declarations(inner, var_env)
    WithStmt(_, body, _) => {
      // Handle bare function declarations directly in with body (Annex B.3.3)
      match body {
        FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
          if !var_env.bindings.contains(name) {
            var_env.def(name, Undefined, VarBinding)
          }
        _ => ()
      }
      hoist_block_func_declarations(body, var_env)
    }
    SwitchStmt(_, cases, _) =>
      for case_ in cases {
        for inner in case_.body {
          match inner {
            FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
              if !var_env.bindings.contains(name) {
                var_env.def(name, Undefined, VarBinding)
              }
            _ => ()
          }
          hoist_block_func_declarations(inner, var_env)
        }
      }
    TryCatchStmt(try_body, _, catch_body, finally_body, _) => {
      for inner in try_body {
        match inner {
          FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
            if !var_env.bindings.contains(name) {
              var_env.def(name, Undefined, VarBinding)
            }
          _ => ()
        }
        hoist_block_func_declarations(inner, var_env)
      }
      match catch_body {
        Some(cb) =>
          for inner in cb {
            match inner {
              FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
                if !var_env.bindings.contains(name) {
                  var_env.def(name, Undefined, VarBinding)
                }
              _ => ()
            }
            hoist_block_func_declarations(inner, var_env)
          }
        None => ()
      }
      match finally_body {
        Some(fb) =>
          for inner in fb {
            match inner {
              FuncDecl(name, _, _, _) | FuncDeclExt(name, _, _, _, _) =>
                if !var_env.bindings.contains(name) {
                  var_env.def(name, Undefined, VarBinding)
                }
              _ => ()
            }
            hoist_block_func_declarations(inner, var_env)
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn Interpreter::hoist_declarations(
  _self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
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
        validate_function_signature(_self.strict, Some(name), params, body)
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(_self.strict, body),
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
          _self.strict,
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
          strict: is_function_strict(_self.strict, body),
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
        validate_function_signature(_self.strict, Some(name), params, body)
        let gen_func = _self.make_generator_function(
          Some(name),
          params,
          None,
          body,
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
          _self.strict,
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
        validate_function_signature(_self.strict, Some(name), params, body)
        let async_func = _self.make_async_function(
          Some(name),
          params,
          None,
          body,
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
          _self.strict,
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
          env,
        )
        if env.bindings.contains(name) {
          env.assign(name, async_func)
        } else {
          env.def(name, async_func, VarBinding)
        }
      }
      AsyncGeneratorDecl(name, params, body, _) => {
        validate_function_signature(_self.strict, Some(name), params, body)
        let gen_func = _self.make_async_generator_function(
          Some(name),
          params,
          None,
          body,
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
          _self.strict,
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
        _self.hoist_declarations(inner_stmts, env)
      }
      // export default function name() {} - hoist the named function
      ExportDefaultDecl(FuncExpr(Some(name), params, body, _), _) => {
        validate_function_signature(_self.strict, Some(name), params, body)
        let func_data : FuncData = {
          name: Some(name),
          params,
          body,
          closure: env,
          strict: is_function_strict(_self.strict, body),
        }
        if env.bindings.contains(name) {
          env.assign(name, make_func(func_data))
        } else {
          env.def(name, make_func(func_data), VarBinding)
        }
      }
      ExportDefaultDecl(FuncExprExt(Some(name), params, rest_param, body, _), _) => {
        validate_function_signature_ext(
          _self.strict,
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
          strict: is_function_strict(_self.strict, body),
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
    // Annex B.3.3: Hoist block-level function declarations as var bindings
    if _self.annex_b && !_self.strict {
      hoist_block_func_declarations(stmt, env)
    }
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
  match pattern {
    IdentPat(name) =>
      if !env.bindings.contains(name) {
        env.def_tdz(name, kind)
      }
    DefaultPat(inner_pat, _) => hoist_pattern_tdz(inner_pat, env, kind)
    AssignTarget(_) => () // member expressions don't need TDZ hoisting
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => hoist_pattern_tdz(p, env, kind)
          None => ()
        }
      }
      match rest {
        Some(p) => hoist_pattern_tdz(p, env, kind)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        hoist_pattern_tdz(prop.value, env, kind)
      }
      match rest {
        Some(p) => hoist_pattern_tdz(p, env, kind)
        None => ()
      }
    }
  }
}

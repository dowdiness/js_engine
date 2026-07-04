///|
fn bytecode_unsupported(kind : String) -> Unit raise Error {
  raise @errors.InternalError(message="bytecode prototype unsupported: " + kind)
}

///|
fn stmt_has_lexical_decl(stmt : @ast.Stmt) -> Bool {
  match stmt {
    VarDecl(LetKind, _, _, _)
    | VarDecl(ConstKind, _, _, _)
    | DestructureDecl(LetKind, _, _, _)
    | DestructureDecl(ConstKind, _, _, _) => true
    StmtList(stmts, _) | Block(stmts, _) => stmts_have_lexical_decl(stmts)
    ForInStmt(Some(LetKind), _, _, _, _)
    | ForInStmt(Some(ConstKind), _, _, _, _)
    | ForInStmtPat(Some(LetKind), _, _, _, _)
    | ForInStmtPat(Some(ConstKind), _, _, _, _) => true
    ForInStmt(_, _, _, body, _)
    | ForInStmtPat(_, _, _, body, _)
    | ForInExpr(_, _, body, _) => stmt_has_lexical_decl(body)
    SwitchStmt(_, cases, _) => switch_cases_have_lexical_decl(cases)
    LabeledStmt(_, body, _) => stmt_has_lexical_decl(body)
    _ => false
  }
}

///|
fn stmts_have_lexical_decl(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_lexical_decl(stmt) {
      return true
    }
  }
  false
}

///|
fn switch_cases_have_lexical_decl(cases : Array[@ast.SwitchCase]) -> Bool {
  for case in cases {
    if stmts_have_lexical_decl(case.body) {
      return true
    }
  }
  false
}

///|
fn bytecode_is_direct_eval_callee(expr : @ast.Expr) -> Bool {
  match expr {
    Ident("eval", _) => true
    Grouping(inner, _) => bytecode_is_direct_eval_callee(inner)
    _ => false
  }
}

///|
fn bytecode_is_anonymous_function_definition(expr : @ast.Expr) -> Bool {
  match expr {
    FuncExpr(None, _, _, _, _)
    | FuncExprExt(None, _, _, _, _, _)
    | ArrowFunc(_, _, _, _)
    | ArrowFuncExt(_, _, _, _, _) => true
    Grouping(inner, _) => bytecode_is_anonymous_function_definition(inner)
    _ => false
  }
}

///|
fn stmt_has_function_decl(stmt : @ast.Stmt) -> Bool {
  match stmt {
    FuncDecl(_, _, _, _, _) | FuncDeclExt(_, _, _, _, _, _) => true
    StmtList(stmts, _) | Block(stmts, _) => stmts_have_function_decl(stmts)
    IfStmt(_, then_branch, else_branch, _) => {
      let else_has = match else_branch {
        Some(stmt) => stmt_has_function_decl(stmt)
        None => false
      }
      stmt_has_function_decl(then_branch) || else_has
    }
    WhileStmt(_, body, _) | DoWhileStmt(body, _, _) =>
      stmt_has_function_decl(body)
    ForStmt(init, _, _, body, _) => {
      let init_has = match init {
        Some(stmt) => stmt_has_function_decl(stmt)
        None => false
      }
      init_has || stmt_has_function_decl(body)
    }
    ForInStmt(_, _, _, body, _)
    | ForInStmtPat(_, _, _, body, _)
    | ForInExpr(_, _, body, _) => stmt_has_function_decl(body)
    SwitchStmt(_, cases, _) => switch_cases_have_function_decl(cases)
    LabeledStmt(_, body, _) => stmt_has_function_decl(body)
    _ => false
  }
}

///|
fn stmts_have_function_decl(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_function_decl(stmt) {
      return true
    }
  }
  false
}

///|
fn switch_cases_have_function_decl(cases : Array[@ast.SwitchCase]) -> Bool {
  for case in cases {
    if stmts_have_function_decl(case.body) {
      return true
    }
  }
  false
}

///|
fn stmt_has_destructure_decl(stmt : @ast.Stmt) -> Bool {
  match stmt {
    DestructureDecl(_, _, _, _) => true
    StmtList(stmts, _) | Block(stmts, _) => stmts_have_destructure_decl(stmts)
    IfStmt(_, then_branch, else_branch, _) => {
      let else_has = match else_branch {
        Some(stmt) => stmt_has_destructure_decl(stmt)
        None => false
      }
      stmt_has_destructure_decl(then_branch) || else_has
    }
    WhileStmt(_, body, _) | DoWhileStmt(body, _, _) =>
      stmt_has_destructure_decl(body)
    ForStmt(init, _, _, body, _) => {
      let init_has = match init {
        Some(stmt) => stmt_has_destructure_decl(stmt)
        None => false
      }
      init_has || stmt_has_destructure_decl(body)
    }
    ForInStmt(_, _, _, body, _) | ForInExpr(_, _, body, _) =>
      stmt_has_destructure_decl(body)
    SwitchStmt(_, cases, _) => switch_cases_have_destructure_decl(cases)
    LabeledStmt(_, body, _) => stmt_has_destructure_decl(body)
    _ => false
  }
}

///|
fn stmts_have_destructure_decl(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_destructure_decl(stmt) {
      return true
    }
  }
  false
}

///|
fn switch_cases_have_destructure_decl(cases : Array[@ast.SwitchCase]) -> Bool {
  for case in cases {
    if stmts_have_destructure_decl(case.body) {
      return true
    }
  }
  false
}

///|
fn stmt_is_iteration_label_target(stmt : @ast.Stmt) -> Bool {
  match stmt {
    WhileStmt(_, _, _)
    | DoWhileStmt(_, _, _)
    | ForStmt(_, _, _, _, _)
    | ForInStmt(_, _, _, _, _)
    | ForOfStmt(_, _, _, _, _)
    | ForInStmtPat(_, _, _, _, _)
    | ForOfStmtPat(_, _, _, _, _)
    | ForInExpr(_, _, _, _)
    | ForOfExpr(_, _, _, _)
    | AsyncForOfStmt(_, _, _, _, _)
    | AsyncForOfStmtPat(_, _, _, _, _)
    | AsyncForOfExpr(_, _, _, _) => true
    LabeledStmt(_, body, _) => stmt_is_iteration_label_target(body)
    _ => false
  }
}

///|
fn add_local_candidate(
  names : Array[String],
  indices : Map[String, Int],
  captured : Map[String, Bool],
  name : String,
) -> Unit {
  if !captured.contains(name) && !indices.contains(name) {
    indices[name] = names.length()
    names.push(name)
  }
}

///|
fn add_env_slot_candidate(
  names : Array[String],
  indices : Map[String, Int],
  local_indices : Map[String, Int],
  name : String,
) -> Unit {
  if !local_indices.contains(name) && !indices.contains(name) {
    indices[name] = names.length()
    names.push(name)
  }
}

///|
fn collect_nested_function_refs_from_stmts(
  stmts : Array[@ast.Stmt],
  refs : Map[String, Bool],
) -> Unit {
  for stmt in stmts {
    collect_nested_function_refs_from_stmt(stmt, refs)
  }
}

///|
fn collect_nested_function_refs_from_stmt(
  stmt : @ast.Stmt,
  refs : Map[String, Bool],
) -> Unit {
  match stmt {
    FuncDecl(_, _, body, _, _) | FuncDeclExt(_, _, _, body, _, _) =>
      collect_name_refs_from_stmts(body, refs)
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) => collect_nested_function_refs_from_expr(expr, refs)
    DestructureDecl(_, pattern, init, _) => {
      collect_nested_function_refs_from_pattern(pattern, refs)
      collect_nested_function_refs_from_expr(init, refs)
    }
    StmtList(stmts, _) | Block(stmts, _) =>
      collect_nested_function_refs_from_stmts(stmts, refs)
    IfStmt(cond, then_branch, else_branch, _) => {
      collect_nested_function_refs_from_expr(cond, refs)
      collect_nested_function_refs_from_stmt(then_branch, refs)
      match else_branch {
        Some(stmt) => collect_nested_function_refs_from_stmt(stmt, refs)
        None => ()
      }
    }
    WhileStmt(cond, body, _) => {
      collect_nested_function_refs_from_expr(cond, refs)
      collect_nested_function_refs_from_stmt(body, refs)
    }
    DoWhileStmt(body, cond, _) => {
      collect_nested_function_refs_from_stmt(body, refs)
      collect_nested_function_refs_from_expr(cond, refs)
    }
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) => collect_nested_function_refs_from_stmt(stmt, refs)
        None => ()
      }
      match cond {
        Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
        None => ()
      }
      match update {
        Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
        None => ()
      }
      collect_nested_function_refs_from_stmt(body, refs)
    }
    ForInStmt(_, _, obj_expr, body, _) => {
      collect_nested_function_refs_from_expr(obj_expr, refs)
      collect_nested_function_refs_from_stmt(body, refs)
    }
    ForInStmtPat(_, pattern, obj_expr, body, _) => {
      collect_nested_function_refs_from_pattern(pattern, refs)
      collect_nested_function_refs_from_expr(obj_expr, refs)
      collect_nested_function_refs_from_stmt(body, refs)
    }
    ForInExpr(lhs_expr, obj_expr, body, _) => {
      collect_nested_function_refs_from_expr(lhs_expr, refs)
      collect_nested_function_refs_from_expr(obj_expr, refs)
      collect_nested_function_refs_from_stmt(body, refs)
    }
    SwitchStmt(discriminant, cases, _) => {
      collect_nested_function_refs_from_expr(discriminant, refs)
      for case in cases {
        match case.condition {
          Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
          None => ()
        }
        collect_nested_function_refs_from_stmts(case.body, refs)
      }
    }
    LabeledStmt(_, body, _) =>
      collect_nested_function_refs_from_stmt(body, refs)
    _ => ()
  }
}

///|
fn collect_nested_function_refs_from_expr(
  expr : @ast.Expr,
  refs : Map[String, Bool],
) -> Unit {
  match expr {
    FuncExpr(_, _, body, _, _)
    | FuncExprExt(_, _, _, body, _, _)
    | ArrowFunc(_, body, _, _)
    | ArrowFuncExt(_, _, body, _, _) => collect_name_refs_from_stmts(body, refs)
    Unary(_, operand, _) =>
      collect_nested_function_refs_from_expr(operand, refs)
    Binary(_, left, right, _) | Comma(left, right, _) => {
      collect_nested_function_refs_from_expr(left, refs)
      collect_nested_function_refs_from_expr(right, refs)
    }
    Ternary(cond, then_expr, else_expr, _) => {
      collect_nested_function_refs_from_expr(cond, refs)
      collect_nested_function_refs_from_expr(then_expr, refs)
      collect_nested_function_refs_from_expr(else_expr, refs)
    }
    Assign(_, value, _) => collect_nested_function_refs_from_expr(value, refs)
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      collect_nested_function_refs_from_expr(callee, refs)
      for arg in args {
        collect_nested_function_refs_from_expr(arg, refs)
      }
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) | ChainMember(obj, _, _) =>
      collect_nested_function_refs_from_expr(obj, refs)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) => {
      collect_nested_function_refs_from_expr(obj, refs)
      collect_nested_function_refs_from_expr(key, refs)
    }
    SuperComputedMember(key, _) =>
      collect_nested_function_refs_from_expr(key, refs)
    MemberAssign(obj, _, value, _) => {
      collect_nested_function_refs_from_expr(obj, refs)
      collect_nested_function_refs_from_expr(value, refs)
    }
    ComputedAssign(obj, key, value, _) => {
      collect_nested_function_refs_from_expr(obj, refs)
      collect_nested_function_refs_from_expr(key, refs)
      collect_nested_function_refs_from_expr(value, refs)
    }
    CompoundAssign(_, target, value, _) => {
      collect_nested_function_refs_from_expr(target, refs)
      collect_nested_function_refs_from_expr(value, refs)
    }
    DestructureAssign(pattern, value, _) => {
      collect_nested_function_refs_from_pattern(pattern, refs)
      collect_nested_function_refs_from_expr(value, refs)
    }
    UpdateExpr(_, operand, _, _) =>
      collect_nested_function_refs_from_expr(operand, refs)
    Grouping(inner, _) => collect_nested_function_refs_from_expr(inner, refs)
    ArrayLit(elements, _) =>
      for element in elements {
        collect_nested_function_refs_from_expr(element, refs)
      }
    ObjectLit(props, _) => collect_nested_function_refs_from_props(props, refs)
    TemplateLit(_, exprs, _) =>
      for expr in exprs {
        collect_nested_function_refs_from_expr(expr, refs)
      }
    TaggedTemplate(tag, _, exprs, _) => {
      collect_nested_function_refs_from_expr(tag, refs)
      for expr in exprs {
        collect_nested_function_refs_from_expr(expr, refs)
      }
    }
    SpreadExpr(inner, _) => collect_nested_function_refs_from_expr(inner, refs)
    _ => ()
  }
}

///|
fn collect_nested_function_refs_from_props(
  props : Array[@ast.Property],
  refs : Map[String, Bool],
) -> Unit {
  for prop in props {
    match prop.kind {
      Spread => collect_nested_function_refs_from_expr(prop.key, refs)
      _ => {
        if prop.computed {
          collect_nested_function_refs_from_expr(prop.key, refs)
        }
        collect_nested_function_refs_from_expr(prop.value, refs)
      }
    }
  }
}

///|
fn collect_nested_function_refs_from_pattern(
  pattern : @ast.Pattern,
  refs : Map[String, Bool],
) -> Unit {
  match pattern {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => collect_nested_function_refs_from_pattern(pat, refs)
          None => ()
        }
      }
      match rest {
        Some(pat) => collect_nested_function_refs_from_pattern(pat, refs)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
          None => ()
        }
        match prop.default_val {
          Some(expr) => collect_nested_function_refs_from_expr(expr, refs)
          None => ()
        }
        collect_nested_function_refs_from_pattern(prop.value, refs)
      }
      match rest {
        Some(pat) => collect_nested_function_refs_from_pattern(pat, refs)
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      collect_nested_function_refs_from_pattern(inner, refs)
      collect_nested_function_refs_from_expr(expr, refs)
    }
    AssignTarget(expr) => collect_nested_function_refs_from_expr(expr, refs)
  }
}

///|
fn collect_name_refs_from_stmts(
  stmts : Array[@ast.Stmt],
  refs : Map[String, Bool],
  nested_functions? : Bool = true,
) -> Unit {
  for stmt in stmts {
    collect_name_refs_from_stmt(stmt, refs, nested_functions~)
  }
}

///|
fn collect_current_function_name_refs_from_stmts(
  stmts : Array[@ast.Stmt],
  refs : Map[String, Bool],
) -> Unit {
  collect_name_refs_from_stmts(stmts, refs, nested_functions=false)
}

///|
fn collect_name_refs_from_stmt(
  stmt : @ast.Stmt,
  refs : Map[String, Bool],
  nested_functions? : Bool = true,
) -> Unit {
  match stmt {
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) =>
      collect_name_refs_from_expr(expr, refs, nested_functions~)
    DestructureDecl(_, pattern, init, _) => {
      collect_name_refs_from_binding_pattern_exprs(
        pattern,
        refs,
        nested_functions~,
      )
      collect_name_refs_from_expr(init, refs, nested_functions~)
    }
    FuncDecl(_, _, body, _, _) | FuncDeclExt(_, _, _, body, _, _) =>
      if nested_functions {
        collect_name_refs_from_stmts(body, refs, nested_functions~)
      }
    StmtList(body, _) | Block(body, _) =>
      collect_name_refs_from_stmts(body, refs, nested_functions~)
    IfStmt(cond, then_branch, else_branch, _) => {
      collect_name_refs_from_expr(cond, refs, nested_functions~)
      collect_name_refs_from_stmt(then_branch, refs, nested_functions~)
      match else_branch {
        Some(stmt) => collect_name_refs_from_stmt(stmt, refs, nested_functions~)
        None => ()
      }
    }
    WhileStmt(cond, body, _) => {
      collect_name_refs_from_expr(cond, refs, nested_functions~)
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    }
    DoWhileStmt(body, cond, _) => {
      collect_name_refs_from_stmt(body, refs, nested_functions~)
      collect_name_refs_from_expr(cond, refs, nested_functions~)
    }
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) => collect_name_refs_from_stmt(stmt, refs, nested_functions~)
        None => ()
      }
      match cond {
        Some(expr) => collect_name_refs_from_expr(expr, refs, nested_functions~)
        None => ()
      }
      match update {
        Some(expr) => collect_name_refs_from_expr(expr, refs, nested_functions~)
        None => ()
      }
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    }
    ForInStmt(None, name, obj_expr, body, _) => {
      refs[name] = true
      collect_name_refs_from_expr(obj_expr, refs, nested_functions~)
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    }
    ForInStmt(Some(_), _, obj_expr, body, _) => {
      collect_name_refs_from_expr(obj_expr, refs, nested_functions~)
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    }
    ForInStmtPat(None, pattern, obj_expr, body, _) => {
      collect_name_refs_from_pattern(pattern, refs, nested_functions~)
      collect_name_refs_from_expr(obj_expr, refs, nested_functions~)
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    }
    ForInStmtPat(Some(_), pattern, obj_expr, body, _) => {
      collect_name_refs_from_binding_pattern_exprs(
        pattern,
        refs,
        nested_functions~,
      )
      collect_name_refs_from_expr(obj_expr, refs, nested_functions~)
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    }
    ForInExpr(lhs_expr, obj_expr, body, _) => {
      collect_name_refs_from_expr(lhs_expr, refs, nested_functions~)
      collect_name_refs_from_expr(obj_expr, refs, nested_functions~)
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    }
    SwitchStmt(discriminant, cases, _) => {
      collect_name_refs_from_expr(discriminant, refs, nested_functions~)
      for case in cases {
        match case.condition {
          Some(expr) =>
            collect_name_refs_from_expr(expr, refs, nested_functions~)
          None => ()
        }
        collect_name_refs_from_stmts(case.body, refs, nested_functions~)
      }
    }
    LabeledStmt(_, body, _) =>
      collect_name_refs_from_stmt(body, refs, nested_functions~)
    _ => ()
  }
}

///|
fn collect_name_refs_from_expr(
  expr : @ast.Expr,
  refs : Map[String, Bool],
  nested_functions? : Bool = true,
) -> Unit {
  match expr {
    Ident(name, _) => refs[name] = true
    Assign(name, value, _) => {
      refs[name] = true
      collect_name_refs_from_expr(value, refs, nested_functions~)
    }
    Unary(_, operand, _) =>
      collect_name_refs_from_expr(operand, refs, nested_functions~)
    Binary(_, left, right, _) | Comma(left, right, _) => {
      collect_name_refs_from_expr(left, refs, nested_functions~)
      collect_name_refs_from_expr(right, refs, nested_functions~)
    }
    Ternary(cond, then_expr, else_expr, _) => {
      collect_name_refs_from_expr(cond, refs, nested_functions~)
      collect_name_refs_from_expr(then_expr, refs, nested_functions~)
      collect_name_refs_from_expr(else_expr, refs, nested_functions~)
    }
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      collect_name_refs_from_expr(callee, refs, nested_functions~)
      for arg in args {
        collect_name_refs_from_expr(arg, refs, nested_functions~)
      }
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) | ChainMember(obj, _, _) =>
      collect_name_refs_from_expr(obj, refs, nested_functions~)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) => {
      collect_name_refs_from_expr(obj, refs, nested_functions~)
      collect_name_refs_from_expr(key, refs, nested_functions~)
    }
    SuperComputedMember(key, _) =>
      collect_name_refs_from_expr(key, refs, nested_functions~)
    MemberAssign(obj, _, value, _) => {
      collect_name_refs_from_expr(obj, refs, nested_functions~)
      collect_name_refs_from_expr(value, refs, nested_functions~)
    }
    ComputedAssign(obj, key, value, _) => {
      collect_name_refs_from_expr(obj, refs, nested_functions~)
      collect_name_refs_from_expr(key, refs, nested_functions~)
      collect_name_refs_from_expr(value, refs, nested_functions~)
    }
    CompoundAssign(_, target, value, _) => {
      collect_name_refs_from_expr(target, refs, nested_functions~)
      collect_name_refs_from_expr(value, refs, nested_functions~)
    }
    DestructureAssign(pattern, value, _) => {
      collect_name_refs_from_pattern(pattern, refs, nested_functions~)
      collect_name_refs_from_expr(value, refs, nested_functions~)
    }
    UpdateExpr(_, operand, _, _) =>
      collect_name_refs_from_expr(operand, refs, nested_functions~)
    FuncExpr(_, _, body, _, _)
    | FuncExprExt(_, _, _, body, _, _)
    | ArrowFunc(_, body, _, _)
    | ArrowFuncExt(_, _, body, _, _) =>
      if nested_functions {
        collect_name_refs_from_stmts(body, refs, nested_functions~)
      }
    Grouping(inner, _) =>
      collect_name_refs_from_expr(inner, refs, nested_functions~)
    ArrayLit(elements, _) =>
      for element in elements {
        collect_name_refs_from_expr(element, refs, nested_functions~)
      }
    ObjectLit(props, _) =>
      collect_name_refs_from_props(props, refs, nested_functions~)
    TemplateLit(_, exprs, _) =>
      for expr in exprs {
        collect_name_refs_from_expr(expr, refs, nested_functions~)
      }
    TaggedTemplate(tag, _, exprs, _) => {
      collect_name_refs_from_expr(tag, refs, nested_functions~)
      for expr in exprs {
        collect_name_refs_from_expr(expr, refs, nested_functions~)
      }
    }
    SpreadExpr(inner, _) =>
      collect_name_refs_from_expr(inner, refs, nested_functions~)
    _ => ()
  }
}

///|
fn collect_name_refs_from_props(
  props : Array[@ast.Property],
  refs : Map[String, Bool],
  nested_functions? : Bool = true,
) -> Unit {
  for prop in props {
    match prop.kind {
      Spread => collect_name_refs_from_expr(prop.key, refs, nested_functions~)
      _ => {
        if prop.computed {
          collect_name_refs_from_expr(prop.key, refs, nested_functions~)
        }
        collect_name_refs_from_expr(prop.value, refs, nested_functions~)
      }
    }
  }
}

///|
fn collect_name_refs_from_pattern(
  pattern : @ast.Pattern,
  refs : Map[String, Bool],
  nested_functions? : Bool = true,
) -> Unit {
  match pattern {
    IdentPat(name) => refs[name] = true
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) =>
            collect_name_refs_from_pattern(pat, refs, nested_functions~)
          None => ()
        }
      }
      match rest {
        Some(pat) =>
          collect_name_refs_from_pattern(pat, refs, nested_functions~)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) =>
            collect_name_refs_from_expr(expr, refs, nested_functions~)
          None => ()
        }
        match prop.default_val {
          Some(expr) =>
            collect_name_refs_from_expr(expr, refs, nested_functions~)
          None => ()
        }
        collect_name_refs_from_pattern(prop.value, refs, nested_functions~)
      }
      match rest {
        Some(pat) =>
          collect_name_refs_from_pattern(pat, refs, nested_functions~)
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      collect_name_refs_from_pattern(inner, refs, nested_functions~)
      collect_name_refs_from_expr(expr, refs, nested_functions~)
    }
    AssignTarget(expr) =>
      collect_name_refs_from_expr(expr, refs, nested_functions~)
  }
}

///|
fn collect_name_refs_from_binding_pattern_exprs(
  pattern : @ast.Pattern,
  refs : Map[String, Bool],
  nested_functions? : Bool = true,
) -> Unit {
  match pattern {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) =>
            collect_name_refs_from_binding_pattern_exprs(
              pat,
              refs,
              nested_functions~,
            )
          None => ()
        }
      }
      match rest {
        Some(pat) =>
          collect_name_refs_from_binding_pattern_exprs(
            pat,
            refs,
            nested_functions~,
          )
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) =>
            collect_name_refs_from_expr(expr, refs, nested_functions~)
          None => ()
        }
        match prop.default_val {
          Some(expr) =>
            collect_name_refs_from_expr(expr, refs, nested_functions~)
          None => ()
        }
        collect_name_refs_from_binding_pattern_exprs(
          prop.value,
          refs,
          nested_functions~,
        )
      }
      match rest {
        Some(pat) =>
          collect_name_refs_from_binding_pattern_exprs(
            pat,
            refs,
            nested_functions~,
          )
        None => ()
      }
    }
    DefaultPat(inner, expr) => {
      collect_name_refs_from_binding_pattern_exprs(
        inner,
        refs,
        nested_functions~,
      )
      collect_name_refs_from_expr(expr, refs, nested_functions~)
    }
    AssignTarget(expr) =>
      collect_name_refs_from_expr(expr, refs, nested_functions~)
  }
}

///|
fn bytecode_body_references_outer_arguments(body : Array[@ast.Stmt]) -> Bool {
  for stmt in body {
    if bytecode_stmt_references_outer_arguments(stmt) {
      return true
    }
  }
  false
}

///|
fn bytecode_stmt_references_outer_arguments(stmt : @ast.Stmt) -> Bool {
  match stmt {
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) => bytecode_expr_references_outer_arguments(expr)
    DestructureDecl(_, pattern, init, _) =>
      bytecode_binding_pattern_exprs_reference_outer_arguments(pattern) ||
      bytecode_expr_references_outer_arguments(init)
    // Ordinary functions bind their own `arguments`; arrows inherit it.
    FuncDecl(_, _, _, _, _) | FuncDeclExt(_, _, _, _, _, _) => false
    StmtList(stmts, _) | Block(stmts, _) =>
      bytecode_body_references_outer_arguments(stmts)
    IfStmt(cond, then_branch, else_branch, _) => {
      if bytecode_expr_references_outer_arguments(cond) {
        return true
      }
      if bytecode_stmt_references_outer_arguments(then_branch) {
        return true
      }
      match else_branch {
        Some(stmt) => bytecode_stmt_references_outer_arguments(stmt)
        None => false
      }
    }
    WhileStmt(cond, body, _) =>
      bytecode_expr_references_outer_arguments(cond) ||
      bytecode_stmt_references_outer_arguments(body)
    DoWhileStmt(body, cond, _) =>
      bytecode_stmt_references_outer_arguments(body) ||
      bytecode_expr_references_outer_arguments(cond)
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) =>
          if bytecode_stmt_references_outer_arguments(stmt) {
            return true
          }
        None => ()
      }
      match cond {
        Some(expr) =>
          if bytecode_expr_references_outer_arguments(expr) {
            return true
          }
        None => ()
      }
      match update {
        Some(expr) =>
          if bytecode_expr_references_outer_arguments(expr) {
            return true
          }
        None => ()
      }
      bytecode_stmt_references_outer_arguments(body)
    }
    ForInStmt(None, name, obj_expr, body, _) =>
      name == "arguments" ||
      bytecode_expr_references_outer_arguments(obj_expr) ||
      bytecode_stmt_references_outer_arguments(body)
    ForInStmt(Some(_), _, obj_expr, body, _) =>
      bytecode_expr_references_outer_arguments(obj_expr) ||
      bytecode_stmt_references_outer_arguments(body)
    ForInStmtPat(None, pattern, obj_expr, body, _) =>
      bytecode_pattern_references_outer_arguments(pattern) ||
      bytecode_expr_references_outer_arguments(obj_expr) ||
      bytecode_stmt_references_outer_arguments(body)
    ForInStmtPat(Some(_), pattern, obj_expr, body, _) =>
      bytecode_binding_pattern_exprs_reference_outer_arguments(pattern) ||
      bytecode_expr_references_outer_arguments(obj_expr) ||
      bytecode_stmt_references_outer_arguments(body)
    ForInExpr(lhs_expr, obj_expr, body, _) =>
      bytecode_expr_references_outer_arguments(lhs_expr) ||
      bytecode_expr_references_outer_arguments(obj_expr) ||
      bytecode_stmt_references_outer_arguments(body)
    SwitchStmt(discriminant, cases, _) => {
      if bytecode_expr_references_outer_arguments(discriminant) {
        return true
      }
      for case in cases {
        match case.condition {
          Some(expr) =>
            if bytecode_expr_references_outer_arguments(expr) {
              return true
            }
          None => ()
        }
        if bytecode_body_references_outer_arguments(case.body) {
          return true
        }
      }
      false
    }
    LabeledStmt(_, body, _) => bytecode_stmt_references_outer_arguments(body)
    _ => false
  }
}

///|
fn bytecode_expr_references_outer_arguments(expr : @ast.Expr) -> Bool {
  match expr {
    Ident("arguments", _) => true
    Assign(name, value, _) =>
      name == "arguments" || bytecode_expr_references_outer_arguments(value)
    Unary(_, operand, _) | Grouping(operand, _) | SpreadExpr(operand, _) =>
      bytecode_expr_references_outer_arguments(operand)
    Binary(_, left, right, _) | Comma(left, right, _) =>
      bytecode_expr_references_outer_arguments(left) ||
      bytecode_expr_references_outer_arguments(right)
    Ternary(cond, then_expr, else_expr, _) =>
      bytecode_expr_references_outer_arguments(cond) ||
      bytecode_expr_references_outer_arguments(then_expr) ||
      bytecode_expr_references_outer_arguments(else_expr)
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      if bytecode_expr_references_outer_arguments(callee) {
        return true
      }
      for arg in args {
        if bytecode_expr_references_outer_arguments(arg) {
          return true
        }
      }
      false
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) | ChainMember(obj, _, _) =>
      bytecode_expr_references_outer_arguments(obj)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) =>
      bytecode_expr_references_outer_arguments(obj) ||
      bytecode_expr_references_outer_arguments(key)
    SuperComputedMember(key, _) => bytecode_expr_references_outer_arguments(key)
    MemberAssign(obj, _, value, _) =>
      bytecode_expr_references_outer_arguments(obj) ||
      bytecode_expr_references_outer_arguments(value)
    ComputedAssign(obj, key, value, _) =>
      bytecode_expr_references_outer_arguments(obj) ||
      bytecode_expr_references_outer_arguments(key) ||
      bytecode_expr_references_outer_arguments(value)
    CompoundAssign(_, target, value, _) =>
      bytecode_expr_references_outer_arguments(target) ||
      bytecode_expr_references_outer_arguments(value)
    DestructureAssign(pattern, value, _) =>
      bytecode_pattern_references_outer_arguments(pattern) ||
      bytecode_expr_references_outer_arguments(value)
    UpdateExpr(_, operand, _, _) =>
      bytecode_expr_references_outer_arguments(operand)
    FuncExpr(_, _, _, _, _) | FuncExprExt(_, _, _, _, _, _) => false
    ArrowFunc(_, body, _, _) | ArrowFuncExt(_, _, body, _, _) =>
      bytecode_body_references_outer_arguments(body)
    ArrayLit(elements, _) => {
      for element in elements {
        if bytecode_expr_references_outer_arguments(element) {
          return true
        }
      }
      false
    }
    ObjectLit(props, _) => bytecode_props_reference_outer_arguments(props)
    TemplateLit(_, exprs, _) => {
      for expr in exprs {
        if bytecode_expr_references_outer_arguments(expr) {
          return true
        }
      }
      false
    }
    TaggedTemplate(tag, _, exprs, _) => {
      if bytecode_expr_references_outer_arguments(tag) {
        return true
      }
      for expr in exprs {
        if bytecode_expr_references_outer_arguments(expr) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn bytecode_props_reference_outer_arguments(
  props : Array[@ast.Property],
) -> Bool {
  for prop in props {
    match prop.kind {
      Spread =>
        if bytecode_expr_references_outer_arguments(prop.key) {
          return true
        }
      _ => {
        if prop.computed && bytecode_expr_references_outer_arguments(prop.key) {
          return true
        }
        if bytecode_expr_references_outer_arguments(prop.value) {
          return true
        }
      }
    }
  }
  false
}

///|
fn bytecode_pattern_references_outer_arguments(pattern : @ast.Pattern) -> Bool {
  match pattern {
    IdentPat(name) => name == "arguments"
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) =>
            if bytecode_pattern_references_outer_arguments(pat) {
              return true
            }
          None => ()
        }
      }
      match rest {
        Some(pat) => bytecode_pattern_references_outer_arguments(pat)
        None => false
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) =>
            if bytecode_expr_references_outer_arguments(expr) {
              return true
            }
          None => ()
        }
        match prop.default_val {
          Some(expr) =>
            if bytecode_expr_references_outer_arguments(expr) {
              return true
            }
          None => ()
        }
        if bytecode_pattern_references_outer_arguments(prop.value) {
          return true
        }
      }
      match rest {
        Some(pat) => bytecode_pattern_references_outer_arguments(pat)
        None => false
      }
    }
    DefaultPat(inner, expr) =>
      bytecode_pattern_references_outer_arguments(inner) ||
      bytecode_expr_references_outer_arguments(expr)
    AssignTarget(expr) => bytecode_expr_references_outer_arguments(expr)
  }
}

///|
fn bytecode_binding_pattern_exprs_reference_outer_arguments(
  pattern : @ast.Pattern,
) -> Bool {
  match pattern {
    IdentPat(_) => false
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) =>
            if bytecode_binding_pattern_exprs_reference_outer_arguments(pat) {
              return true
            }
          None => ()
        }
      }
      match rest {
        Some(pat) =>
          bytecode_binding_pattern_exprs_reference_outer_arguments(pat)
        None => false
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) =>
            if bytecode_expr_references_outer_arguments(expr) {
              return true
            }
          None => ()
        }
        match prop.default_val {
          Some(expr) =>
            if bytecode_expr_references_outer_arguments(expr) {
              return true
            }
          None => ()
        }
        if bytecode_binding_pattern_exprs_reference_outer_arguments(prop.value) {
          return true
        }
      }
      match rest {
        Some(pat) =>
          bytecode_binding_pattern_exprs_reference_outer_arguments(pat)
        None => false
      }
    }
    DefaultPat(inner, expr) =>
      bytecode_binding_pattern_exprs_reference_outer_arguments(inner) ||
      bytecode_expr_references_outer_arguments(expr)
    AssignTarget(expr) => bytecode_expr_references_outer_arguments(expr)
  }
}

///|
fn bytecode_body_contains_destructure_assign(body : Array[@ast.Stmt]) -> Bool {
  for stmt in body {
    if bytecode_stmt_contains_destructure_assign(stmt) {
      return true
    }
  }
  false
}

///|
fn bytecode_stmt_contains_destructure_assign(stmt : @ast.Stmt) -> Bool {
  match stmt {
    DestructureDecl(_, _, _, _) => true
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) => bytecode_expr_contains_destructure_assign(expr)
    StmtList(stmts, _) | Block(stmts, _) =>
      bytecode_body_contains_destructure_assign(stmts)
    IfStmt(cond, then_branch, else_branch, _) => {
      if bytecode_expr_contains_destructure_assign(cond) {
        return true
      }
      if bytecode_stmt_contains_destructure_assign(then_branch) {
        return true
      }
      match else_branch {
        Some(stmt) => bytecode_stmt_contains_destructure_assign(stmt)
        None => false
      }
    }
    WhileStmt(cond, body, _) =>
      bytecode_expr_contains_destructure_assign(cond) ||
      bytecode_stmt_contains_destructure_assign(body)
    DoWhileStmt(body, cond, _) =>
      bytecode_stmt_contains_destructure_assign(body) ||
      bytecode_expr_contains_destructure_assign(cond)
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) =>
          if bytecode_stmt_contains_destructure_assign(stmt) {
            return true
          }
        None => ()
      }
      match cond {
        Some(expr) =>
          if bytecode_expr_contains_destructure_assign(expr) {
            return true
          }
        None => ()
      }
      match update {
        Some(expr) =>
          if bytecode_expr_contains_destructure_assign(expr) {
            return true
          }
        None => ()
      }
      bytecode_stmt_contains_destructure_assign(body)
    }
    ForInStmtPat(_, _, _, _, _) => true
    ForInStmt(_, _, obj_expr, body, _) =>
      bytecode_expr_contains_destructure_assign(obj_expr) ||
      bytecode_stmt_contains_destructure_assign(body)
    ForInExpr(lhs_expr, obj_expr, body, _) =>
      bytecode_expr_contains_destructure_assign(lhs_expr) ||
      bytecode_expr_contains_destructure_assign(obj_expr) ||
      bytecode_stmt_contains_destructure_assign(body)
    SwitchStmt(discriminant, cases, _) => {
      if bytecode_expr_contains_destructure_assign(discriminant) {
        return true
      }
      for case in cases {
        match case.condition {
          Some(expr) =>
            if bytecode_expr_contains_destructure_assign(expr) {
              return true
            }
          None => ()
        }
        if bytecode_body_contains_destructure_assign(case.body) {
          return true
        }
      }
      false
    }
    LabeledStmt(_, body, _) => bytecode_stmt_contains_destructure_assign(body)
    _ => false
  }
}

///|
fn bytecode_expr_contains_destructure_assign(expr : @ast.Expr) -> Bool {
  match expr {
    DestructureAssign(_, _, _) => true
    Unary(_, operand, _) | Grouping(operand, _) | SpreadExpr(operand, _) =>
      bytecode_expr_contains_destructure_assign(operand)
    Binary(_, left, right, _) | Comma(left, right, _) =>
      bytecode_expr_contains_destructure_assign(left) ||
      bytecode_expr_contains_destructure_assign(right)
    Ternary(cond, then_expr, else_expr, _) =>
      bytecode_expr_contains_destructure_assign(cond) ||
      bytecode_expr_contains_destructure_assign(then_expr) ||
      bytecode_expr_contains_destructure_assign(else_expr)
    Assign(_, value, _) => bytecode_expr_contains_destructure_assign(value)
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      if bytecode_expr_contains_destructure_assign(callee) {
        return true
      }
      for arg in args {
        if bytecode_expr_contains_destructure_assign(arg) {
          return true
        }
      }
      false
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) | ChainMember(obj, _, _) =>
      bytecode_expr_contains_destructure_assign(obj)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) =>
      bytecode_expr_contains_destructure_assign(obj) ||
      bytecode_expr_contains_destructure_assign(key)
    SuperComputedMember(key, _) =>
      bytecode_expr_contains_destructure_assign(key)
    MemberAssign(obj, _, value, _) =>
      bytecode_expr_contains_destructure_assign(obj) ||
      bytecode_expr_contains_destructure_assign(value)
    ComputedAssign(obj, key, value, _) =>
      bytecode_expr_contains_destructure_assign(obj) ||
      bytecode_expr_contains_destructure_assign(key) ||
      bytecode_expr_contains_destructure_assign(value)
    CompoundAssign(_, target, value, _) =>
      bytecode_expr_contains_destructure_assign(target) ||
      bytecode_expr_contains_destructure_assign(value)
    UpdateExpr(_, operand, _, _) =>
      bytecode_expr_contains_destructure_assign(operand)
    FuncExpr(_, _, body, _, _)
    | FuncExprExt(_, _, _, body, _, _)
    | ArrowFunc(_, body, _, _)
    | ArrowFuncExt(_, _, body, _, _) =>
      bytecode_body_contains_destructure_assign(body)
    ArrayLit(elements, _) => {
      for element in elements {
        if bytecode_expr_contains_destructure_assign(element) {
          return true
        }
      }
      false
    }
    ObjectLit(props, _) => bytecode_props_contain_destructure_assign(props)
    TemplateLit(_, exprs, _) => {
      for expr in exprs {
        if bytecode_expr_contains_destructure_assign(expr) {
          return true
        }
      }
      false
    }
    TaggedTemplate(tag, _, exprs, _) => {
      if bytecode_expr_contains_destructure_assign(tag) {
        return true
      }
      for expr in exprs {
        if bytecode_expr_contains_destructure_assign(expr) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn bytecode_props_contain_destructure_assign(
  props : Array[@ast.Property],
) -> Bool {
  for prop in props {
    match prop.kind {
      Spread =>
        if bytecode_expr_contains_destructure_assign(prop.key) {
          return true
        }
      _ => {
        if prop.computed && bytecode_expr_contains_destructure_assign(prop.key) {
          return true
        }
        if bytecode_expr_contains_destructure_assign(prop.value) {
          return true
        }
      }
    }
  }
  false
}

///|
// Direct eval can read or declare caller bindings by string, so any visible
// `eval` reference keeps this function and enclosing compiled functions on
// environment bindings instead of local slots.
fn bytecode_body_references_eval(body : Array[@ast.Stmt]) -> Bool {
  let refs : Map[String, Bool] = {}
  collect_name_refs_from_stmts(body, refs)
  refs.contains("eval")
}

///|
fn plan_bytecode_locals(
  params : Array[String],
  body : Array[@ast.Stmt],
  use_local_slots~ : Bool,
) -> BytecodeLocalPlan {
  let names : Array[String] = []
  let indices : Map[String, Int] = {}
  let env_names : Array[String] = []
  let env_indices : Map[String, Int] = {}
  let refs_arguments = bytecode_body_references_outer_arguments(body)
  if use_local_slots &&
    !bytecode_body_references_eval(body) &&
    !bytecode_body_contains_destructure_assign(body) {
    let captured : Map[String, Bool] = {}
    collect_nested_function_refs_from_stmts(body, captured)
    let current_refs : Map[String, Bool] = {}
    collect_current_function_name_refs_from_stmts(body, current_refs)
    let param_names : Map[String, Bool] = {}
    for param in params {
      param_names[param] = true
      if !captured.contains(param) && !refs_arguments {
        add_local_candidate(names, indices, captured, param)
      } else if captured.contains(param) &&
        current_refs.contains(param) &&
        !refs_arguments {
        add_env_slot_candidate(env_names, env_indices, indices, param)
      }
    }
    let vars = @static_semantics.collect_var_declared_names(body)
    for name in vars {
      if param_names.contains(name) {
        if !refs_arguments && !captured.contains(name) {
          add_local_candidate(names, indices, captured, name)
        }
      } else if (captured.contains(name) && current_refs.contains(name)) ||
        (refs_arguments && name == "arguments") {
        add_env_slot_candidate(env_names, env_indices, indices, name)
      } else {
        add_local_candidate(names, indices, captured, name)
      }
    }
  }
  { names, indices, env_names, env_indices }
}

///|
fn compile_bytecode_function(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
  rest_param : String?,
  use_local_slots? : Bool = true,
  call_self_name? : Bool = false,
  template_cache_key_prefix? : String = "main",
) -> BytecodeFunction raise Error {
  let plan = plan_bytecode_locals(
    params,
    body,
    use_local_slots=use_local_slots && rest_param is None,
  )
  let builder = BytecodeBuilder::BytecodeBuilder(
    plan, template_cache_key_prefix,
  )
  for stmt in body {
    builder.compile_stmt(stmt)
  }
  // Precompute the env-hoist name set once, now that builder.local_names is
  // final (compile_stmt above may have added locals). The VM used to derive
  // this on every call (issue #325); store it on the IR instead. It must
  // reproduce the old per-call result byte-for-byte: every var-declared name
  // that is NOT a local slot, in source order, with duplicates preserved.
  // Filter against the final builder.local_names (== func_def.local_names the
  // VM read), so the agreement holds for every branch — local, env slot,
  // arguments, eval, and rest-param.
  let env_var_hoist_names = @static_semantics.collect_var_declared_names(body).filter(name => {
      local_index_from_names(builder.local_names, name) is None
    },
  )
  let needs_arguments_obj = bytecode_body_references_outer_arguments(body) ||
    bytecode_body_references_eval(body)
  {
    name,
    params,
    rest_param,
    source_body: body,
    body_has_use_strict: @static_semantics.has_use_strict(body),
    call_self_name,
    needs_arguments_object: needs_arguments_obj,
    // When false, run_bytecode_function skips all hoist calls (each is a no-op per these conditions).
    needs_own_env: !(builder.env_slot_names.is_empty() &&
    env_var_hoist_names.is_empty() &&
    !needs_arguments_obj &&
    !call_self_name &&
    builder.children.is_empty() &&
    rest_param is None &&
    !builder.has_this &&
    !builder.has_new_target &&
    !stmts_have_lexical_decl(body) &&
    !bytecode_body_contains_destructure_assign(body)),
    local_names: builder.local_names,
    local_indices: builder.local_indices,
    env_slot_names: builder.env_slot_names,
    env_var_hoist_names,
    template_cache_key_prefix,
    code: builder.code,
    children: builder.children,
  }
}

///|
pub fn compile_script_to_bytecode(
  stmts : Array[@ast.Stmt],
) -> BytecodeProgram raise Error {
  {
    source_stmts: stmts,
    main: compile_bytecode_function(
      None,
      [],
      stmts,
      None,
      use_local_slots=false,
    ),
  }
}

///|
pub fn run_bytecode_script(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Value raise Error {
  compile_script_to_bytecode(stmts).run(interp)
}

///|
pub fn BytecodeProgram::run(
  self : BytecodeProgram,
  interp : Interpreter,
) -> Value raise Error {
  interp.run_compiled_script(self.source_stmts, fn(ctx, env) raise {
    match run_bytecode_function(interp, ctx, env, self.main) {
      BytecodeNormal(value) => value
      BytecodeReturn(_) =>
        raise @errors.SyntaxError(
          message="return statement outside of function",
        )
    }
  })
}

///|
fn BytecodeBuilder::add_function(
  self : BytecodeBuilder,
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
  rest_param : String?,
  call_self_name? : Bool = false,
) -> Int raise Error {
  let idx = self.children.length()
  let template_cache_key_prefix = self.template_cache_key_prefix +
    "/" +
    idx.to_string()
  self.children.push(
    compile_bytecode_function(
      name,
      params,
      body,
      rest_param,
      call_self_name~,
      template_cache_key_prefix~,
    ),
  )
  idx
}

///|
fn BytecodeBuilder::compile_switch(
  self : BytecodeBuilder,
  discriminant : @ast.Expr,
  cases : Array[@ast.SwitchCase],
) -> Unit raise Error {
  if switch_cases_have_lexical_decl(cases) {
    bytecode_unsupported(UNSUPPORTED_SWITCH_LEXICAL_DECLARATION)
  }
  if switch_cases_have_function_decl(cases) {
    bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
  }
  if switch_cases_have_destructure_decl(cases) {
    bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
  }
  self.emit_undefined_completion()
  self.compile_expr(discriminant)
  let case_jumps = Array::make(cases.length(), -1)
  let mut default_idx = -1
  for i, case in cases {
    match case.condition {
      Some(cond) => {
        let _ = self.emit(Dup)
        self.compile_expr(cond)
        let _ = self.emit(BinaryOp(EqEqEq, @token.Loc::default()))
        let no_match = self.emit(JumpIfFalse(-1))
        let _ = self.emit(Pop)
        case_jumps[i] = self.emit(Jump(-1))
        self.patch(no_match, JumpIfFalse(self.code.length()))
      }
      None => default_idx = i
    }
  }
  let _ = self.emit(Pop)
  let no_match_jump = self.emit(Jump(-1))
  self.push_switch_context()
  let case_starts = Array::make(cases.length(), 0)
  for i, case in cases {
    case_starts[i] = self.code.length()
    for child in case.body {
      self.compile_stmt(child)
    }
  }
  let switch_ctx = self.pop_switch_context()
  let exit_pos = self.code.length()
  for i, jump in case_jumps {
    if jump >= 0 {
      self.patch(jump, Jump(case_starts[i]))
    }
  }
  if default_idx >= 0 {
    self.patch(no_match_jump, Jump(case_starts[default_idx]))
  } else {
    self.patch(no_match_jump, Jump(exit_pos))
  }
  self.patch_loop_jumps(switch_ctx.break_jumps, exit_pos)
}

///|
fn BytecodeBuilder::compile_for_in_identifier(
  self : BytecodeBuilder,
  var_kind : @ast.VarKind?,
  name : String,
  obj_expr : @ast.Expr,
  body : @ast.Stmt,
) -> Unit raise Error {
  match var_kind {
    Some(VarKind) => bytecode_unsupported(UNSUPPORTED_FOR_IN_VAR_DECLARATION)
    Some(LetKind) | Some(ConstKind) =>
      bytecode_unsupported(UNSUPPORTED_FOR_IN_LEXICAL_DECLARATION)
    None => ()
  }
  if stmt_has_function_decl(body) {
    bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
  }
  if stmt_has_destructure_decl(body) {
    bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
  }
  self.emit_undefined_completion()
  self.compile_expr(obj_expr)
  let _ = self.emit(StartForIn)
  let loop_pos = self.code.length()
  let done_jump = self.emit(ForInNext(-1))
  self.compile_identifier_store(name)
  let _ = self.emit(Pop)
  let labels = self.take_pending_loop_labels()
  self.push_loop_context(labels, cleanup_for_in=true)
  self.compile_stmt(body)
  let loop_ctx = self.pop_loop_context()
  self.restore_pending_loop_labels(labels)
  let continue_pos = self.code.length()
  self.patch_loop_jumps(loop_ctx.continue_jumps, continue_pos)
  let _ = self.emit(Jump(loop_pos))
  let cleanup_pos = self.code.length()
  let _ = self.emit(EndForIn)
  let exit_pos = self.code.length()
  self.patch(done_jump, ForInNext(exit_pos))
  self.patch_loop_jumps(loop_ctx.break_jumps, cleanup_pos)
}

///|
fn BytecodeBuilder::compile_for_in_pattern(
  self : BytecodeBuilder,
  var_kind : @ast.VarKind?,
  pattern : @ast.Pattern,
  obj_expr : @ast.Expr,
  body : @ast.Stmt,
) -> Unit raise Error {
  match var_kind {
    Some(VarKind) => bytecode_unsupported(UNSUPPORTED_FOR_IN_VAR_DECLARATION)
    Some(LetKind) | Some(ConstKind) =>
      bytecode_unsupported(UNSUPPORTED_FOR_IN_LEXICAL_DECLARATION)
    None => ()
  }
  bytecode_validate_destructure_assignment_pattern(pattern)
  if stmt_has_function_decl(body) {
    bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
  }
  if stmt_has_destructure_decl(body) {
    bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
  }
  self.emit_undefined_completion()
  self.compile_expr(obj_expr)
  let _ = self.emit(StartForIn)
  let loop_pos = self.code.length()
  let done_jump = self.emit(ForInNext(-1))
  let _ = self.emit(AssignPattern(pattern))
  let _ = self.emit(Pop)
  let labels = self.take_pending_loop_labels()
  self.push_loop_context(labels, cleanup_for_in=true)
  self.compile_stmt(body)
  let loop_ctx = self.pop_loop_context()
  self.restore_pending_loop_labels(labels)
  let continue_pos = self.code.length()
  self.patch_loop_jumps(loop_ctx.continue_jumps, continue_pos)
  let _ = self.emit(Jump(loop_pos))
  let cleanup_pos = self.code.length()
  let _ = self.emit(EndForIn)
  let exit_pos = self.code.length()
  self.patch(done_jump, ForInNext(exit_pos))
  self.patch_loop_jumps(loop_ctx.break_jumps, cleanup_pos)
}

///|
fn BytecodeBuilder::compile_for_in_expr_target_store(
  self : BytecodeBuilder,
  target : @ast.Expr,
) -> Unit raise Error {
  match target {
    Member(obj, prop, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(SetForInProperty(prop, loc))
    }
    ComputedMember(obj, key, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(SetForInComputed(loc))
    }
    _ => bytecode_unsupported(UNSUPPORTED_FOR_IN_ASSIGNMENT_TARGET)
  }
}

///|
fn BytecodeBuilder::compile_for_in_expr(
  self : BytecodeBuilder,
  target : @ast.Expr,
  obj_expr : @ast.Expr,
  body : @ast.Stmt,
) -> Unit raise Error {
  if stmt_has_function_decl(body) {
    bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
  }
  if stmt_has_destructure_decl(body) {
    bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
  }
  self.emit_undefined_completion()
  self.compile_expr(obj_expr)
  let _ = self.emit(StartForIn)
  let loop_pos = self.code.length()
  let done_jump = self.emit(ForInNext(-1))
  self.compile_for_in_expr_target_store(target)
  let _ = self.emit(Pop)
  let labels = self.take_pending_loop_labels()
  self.push_loop_context(labels, cleanup_for_in=true)
  self.compile_stmt(body)
  let loop_ctx = self.pop_loop_context()
  self.restore_pending_loop_labels(labels)
  let continue_pos = self.code.length()
  self.patch_loop_jumps(loop_ctx.continue_jumps, continue_pos)
  let _ = self.emit(Jump(loop_pos))
  let cleanup_pos = self.code.length()
  let _ = self.emit(EndForIn)
  let exit_pos = self.code.length()
  self.patch(done_jump, ForInNext(exit_pos))
  self.patch_loop_jumps(loop_ctx.break_jumps, cleanup_pos)
}

///|
fn BytecodeBuilder::compile_stmt(
  self : BytecodeBuilder,
  stmt : @ast.Stmt,
  declaration_updates_completion? : Bool = true,
) -> Unit raise Error {
  match stmt {
    ExprStmt(expr, _) => self.compile_expr_for_completion(expr)
    VarDecl(kind, name, init, _) => {
      match init {
        Some(expr) => {
          self.compile_expr(expr)
          if bytecode_is_anonymous_function_definition(expr) {
            let _ = self.emit(SetFunctionName(name))
          }
        }
        None => {
          let _ = self.emit(LoadUndefined)
        }
      }
      match (kind, self.local_slot(name), self.env_slot(name)) {
        (VarKind, Some(slot), _) => {
          let _ = self.emit(DefineLocal(slot, init is Some(_)))
        }
        (VarKind, _, Some(slot)) => {
          let _ = self.emit(DefineEnvSlot(slot, init is Some(_)))
        }
        _ => {
          let _ = self.emit(DefineBinding(kind, name, init is Some(_)))
        }
      }
      if declaration_updates_completion {
        self.emit_undefined_completion()
      }
    }
    DestructureDecl(VarKind, pattern, init, _) => {
      bytecode_validate_destructure_assignment_pattern(pattern)
      self.compile_expr(init)
      let _ = self.emit(AssignPattern(pattern))
      let _ = self.emit(Pop)
      if declaration_updates_completion {
        self.emit_undefined_completion()
      }
    }
    DestructureDecl(_, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_KIND)
    StmtList(stmts, _) => {
      if stmts_have_destructure_decl(stmts) {
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
      }
      self.emit_undefined_completion()
      for child in stmts {
        self.compile_stmt(child, declaration_updates_completion=false)
      }
    }
    Block(stmts, _) => {
      if stmts_have_lexical_decl(stmts) {
        bytecode_unsupported(UNSUPPORTED_BLOCK_LEXICAL_DECLARATION)
      }
      if stmts_have_function_decl(stmts) {
        bytecode_unsupported(UNSUPPORTED_BLOCK_FUNCTION_DECLARATION)
      }
      if stmts_have_destructure_decl(stmts) {
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
      }
      self.emit_undefined_completion()
      for child in stmts {
        self.compile_stmt(child, declaration_updates_completion=false)
      }
    }
    IfStmt(cond, then_branch, else_branch, _) => {
      if stmt_has_function_decl(then_branch) {
        bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
      }
      match else_branch {
        Some(stmt) =>
          if stmt_has_function_decl(stmt) {
            bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
          }
        None => ()
      }
      if stmt_has_destructure_decl(then_branch) {
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
      }
      match else_branch {
        Some(stmt) =>
          if stmt_has_destructure_decl(stmt) {
            bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
          }
        None => ()
      }
      self.compile_expr(cond)
      let else_jump = self.emit(JumpIfFalse(-1))
      self.compile_stmt(then_branch)
      let end_jump = self.emit(Jump(-1))
      self.patch(else_jump, JumpIfFalse(self.code.length()))
      match else_branch {
        Some(stmt) => self.compile_stmt(stmt)
        None => self.emit_undefined_completion()
      }
      self.patch(end_jump, Jump(self.code.length()))
    }
    WhileStmt(cond, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
      }
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
      }
      self.emit_undefined_completion()
      let cond_pos = self.code.length()
      self.compile_expr(cond)
      let exit_jump = self.emit(JumpIfFalse(-1))
      let labels = self.take_pending_loop_labels()
      self.push_loop_context(labels)
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      self.restore_pending_loop_labels(labels)
      let _ = self.emit(Jump(cond_pos))
      let exit_pos = self.code.length()
      self.patch(exit_jump, JumpIfFalse(exit_pos))
      self.patch_loop_jumps(loop_ctx.break_jumps, exit_pos)
      self.patch_loop_jumps(loop_ctx.continue_jumps, cond_pos)
    }
    DoWhileStmt(body, cond, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
      }
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
      }
      self.emit_undefined_completion()
      let body_pos = self.code.length()
      let labels = self.take_pending_loop_labels()
      self.push_loop_context(labels)
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      self.restore_pending_loop_labels(labels)
      let cond_pos = self.code.length()
      self.patch_loop_jumps(loop_ctx.continue_jumps, cond_pos)
      self.compile_expr(cond)
      let exit_jump = self.emit(JumpIfFalse(-1))
      let _ = self.emit(Jump(body_pos))
      let exit_pos = self.code.length()
      self.patch(exit_jump, JumpIfFalse(exit_pos))
      self.patch_loop_jumps(loop_ctx.break_jumps, exit_pos)
    }
    ForStmt(init, cond, update, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
      }
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
      }
      match init {
        Some(stmt) => {
          if stmt_has_lexical_decl(stmt) {
            bytecode_unsupported(UNSUPPORTED_FOR_LEXICAL_INITIALIZER)
          }
          if stmt_has_destructure_decl(stmt) {
            bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
          }
          self.compile_for_init(stmt)
        }
        None => ()
      }
      self.emit_undefined_completion()
      let cond_pos = self.code.length()
      match cond {
        Some(expr) => self.compile_expr(expr)
        None => {
          let _ = self.emit(LoadConst(Value::Bool(true)))
        }
      }
      let exit_jump = self.emit(JumpIfFalse(-1))
      let labels = self.take_pending_loop_labels()
      self.push_loop_context(labels)
      self.compile_stmt(body)
      let loop_ctx = self.pop_loop_context()
      self.restore_pending_loop_labels(labels)
      let update_pos = self.code.length()
      self.patch_loop_jumps(loop_ctx.continue_jumps, update_pos)
      match update {
        Some(expr) => {
          self.compile_expr(expr)
          let _ = self.emit(Pop)
        }
        None => ()
      }
      let _ = self.emit(Jump(cond_pos))
      let exit_pos = self.code.length()
      self.patch(exit_jump, JumpIfFalse(exit_pos))
      self.patch_loop_jumps(loop_ctx.break_jumps, exit_pos)
    }
    ForOfStmt(_, _, _, _, _)
    | ForOfStmtPat(_, _, _, _, _)
    | ForOfExpr(_, _, _, _)
    | AsyncForOfStmt(_, _, _, _, _)
    | AsyncForOfStmtPat(_, _, _, _, _)
    | AsyncForOfExpr(_, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_FOR_OF_STATEMENT)
    ForInStmt(var_kind, name, obj_expr, body, _) =>
      self.compile_for_in_identifier(var_kind, name, obj_expr, body)
    ForInStmtPat(var_kind, pattern, obj_expr, body, _) =>
      self.compile_for_in_pattern(var_kind, pattern, obj_expr, body)
    ForInExpr(target, obj_expr, body, _) =>
      self.compile_for_in_expr(target, obj_expr, body)
    SwitchStmt(discriminant, cases, _) =>
      self.compile_switch(discriminant, cases)
    FuncDecl(name, params, body, _, _) => {
      let fn_idx = self.add_function(Some(name), params, body, None)
      let _ = self.emit(DeclareFunction(name, fn_idx))
      self.emit_undefined_completion()
    }
    FuncDeclExt(name, params, rest_param, body, _, _) => {
      let (simple_params, simple_rest) = simple_ext_param_names_with_rest(
        params, rest_param,
      )
      let fn_idx = self.add_function(
        Some(name),
        simple_params,
        body,
        simple_rest,
      )
      let _ = self.emit(DeclareFunction(name, fn_idx))
      self.emit_undefined_completion()
    }
    ReturnStmt(expr, _) => {
      match expr {
        Some(value) => self.compile_expr(value)
        None => {
          let _ = self.emit(LoadUndefined)
        }
      }
      let _ = self.emit(Return)
    }
    BreakStmt(label, _) => self.emit_loop_break(label)
    ContinueStmt(label, _) => self.emit_loop_continue(label)
    ThrowStmt(expr, _) => {
      self.compile_expr(expr)
      let _ = self.emit(Throw)
    }
    TryCatchStmt(_, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_TRY_CATCH_STATEMENT)
    LabeledStmt(label, body, _) => {
      if stmt_has_function_decl(body) {
        bytecode_unsupported(UNSUPPORTED_CONTROL_FLOW_FUNCTION_DECLARATION)
      }
      if stmt_has_destructure_decl(body) {
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_DECLARATION_CONTEXT)
      }
      if stmt_is_iteration_label_target(body) {
        self.pending_loop_labels.push(label)
        self.compile_stmt(body, declaration_updates_completion~)
        let _ = self.pending_loop_labels.pop()
      } else {
        self.label_contexts.push({
          label,
          break_jumps: [],
          loop_depth: self.loop_contexts.length(),
        })
        self.compile_stmt(body, declaration_updates_completion~)
        let label_ctx = match self.label_contexts.pop() {
          Some(ctx) => ctx
          None => {
            bytecode_unsupported(UNSUPPORTED_LABEL_CONTEXT)
            { label, break_jumps: [], loop_depth: self.loop_contexts.length() }
          }
        }
        self.patch_loop_jumps(label_ctx.break_jumps, self.code.length())
      }
    }
    GeneratorDecl(_, _, _, _, _) | GeneratorDeclExt(_, _, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_GENERATOR_DECLARATION)
    AsyncFuncDecl(_, _, _, _, _) | AsyncFuncDeclExt(_, _, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_ASYNC_FUNCTION_DECLARATION)
    AsyncGeneratorDecl(_, _, _, _, _)
    | AsyncGeneratorDeclExt(_, _, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_ASYNC_GENERATOR_DECLARATION)
    ClassDecl(_, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_CLASS_DECLARATION)
    WithStmt(_, _, _) => bytecode_unsupported(UNSUPPORTED_WITH_STATEMENT)
    ImportDecl(_, _, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_IMPORT_DECLARATION)
    ExportNamedDecl(_, _, _, _, _)
    | ExportDefaultDecl(_, _)
    | ExportAllDecl(_, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_EXPORT_DECLARATION)
  }
}

///|
fn BytecodeBuilder::compile_for_init(
  self : BytecodeBuilder,
  stmt : @ast.Stmt,
) -> Unit raise Error {
  match stmt {
    ExprStmt(expr, _) => {
      self.compile_expr(expr)
      let _ = self.emit(Pop)
    }
    VarDecl(_, _, _, _) | StmtList(_, _) => self.compile_stmt(stmt)
    _ => bytecode_unsupported(UNSUPPORTED_FOR_INITIALIZER)
  }
}

///|
fn bytecode_args_have_spread(args : Array[@ast.Expr]) -> Bool {
  for arg in args {
    match arg {
      SpreadExpr(_, _) => return true
      _ => ()
    }
  }
  false
}

///|
fn BytecodeBuilder::compile_fixed_args(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
) -> Unit raise Error {
  for arg in args {
    self.compile_expr(arg)
  }
}

///|
fn BytecodeBuilder::compile_dynamic_args(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
) -> Unit raise Error {
  let _ = self.emit(StartArgs)
  for arg in args {
    match arg {
      SpreadExpr(inner, loc) => {
        self.compile_expr(inner)
        let _ = self.emit(ArgPushSpread(loc))
      }
      _ => {
        self.compile_expr(arg)
        let _ = self.emit(ArgPushValue)
      }
    }
  }
}

///|
fn BytecodeBuilder::compile_call_args(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
) -> Bool raise Error {
  if bytecode_args_have_spread(args) {
    self.compile_dynamic_args(args)
    true
  } else {
    self.compile_fixed_args(args)
    false
  }
}

///|
fn BytecodeBuilder::emit_call(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  if self.compile_call_args(args) {
    let _ = self.emit(CallSpread(loc))
  } else {
    let _ = self.emit(Call(args.length(), loc))
  }
}

///|
fn BytecodeBuilder::emit_call_with_receiver(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  if self.compile_call_args(args) {
    let _ = self.emit(CallSpreadWithReceiver(loc))
  } else {
    let _ = self.emit(CallWithReceiver(args.length(), loc))
  }
}

///|
fn BytecodeBuilder::emit_construct(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  if self.compile_call_args(args) {
    let _ = self.emit(ConstructSpread(loc))
  } else {
    let _ = self.emit(Construct(args.length(), loc))
  }
}

///|
fn BytecodeBuilder::compile_logical_and(
  self : BytecodeBuilder,
  left : @ast.Expr,
  right : @ast.Expr,
) -> Unit raise Error {
  self.compile_expr(left)
  let keep_left = self.emit(JumpIfFalseKeep(-1))
  let _ = self.emit(Pop)
  self.compile_expr(right)
  self.patch(keep_left, JumpIfFalseKeep(self.code.length()))
}

///|
fn BytecodeBuilder::compile_logical_or(
  self : BytecodeBuilder,
  left : @ast.Expr,
  right : @ast.Expr,
) -> Unit raise Error {
  self.compile_expr(left)
  let keep_left = self.emit(JumpIfTrueKeep(-1))
  let _ = self.emit(Pop)
  self.compile_expr(right)
  self.patch(keep_left, JumpIfTrueKeep(self.code.length()))
}

///|
fn BytecodeBuilder::compile_nullish_coalesce(
  self : BytecodeBuilder,
  left : @ast.Expr,
  right : @ast.Expr,
) -> Unit raise Error {
  self.compile_expr(left)
  let keep_left = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  self.compile_expr(right)
  self.patch(keep_left, JumpIfNotNullishKeep(self.code.length()))
}

///|
/// Emit the nullish-guard preamble for an optional chain step that starts
/// with a `?.` (question-dot). If the value on the stack is null/undefined,
/// pop it, push Undefined, mark short-circuit, and route to the end label.
/// Repeat of the `JumpIfNotNullishKeep / Pop / LoadUndefined / MarkOptionalChainShortCircuit / Jump` pattern.
fn BytecodeBuilder::emit_optional_null_guard(
  self : BytecodeBuilder,
  end_jumps : Array[Int],
) -> Unit {
  let jump = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  let _ = self.emit(LoadUndefined)
  let _ = self.emit(MarkOptionalChainShortCircuit)
  end_jumps.push(self.emit(Jump(-1)))
  self.patch(jump, JumpIfNotNullishKeep(self.code.length()))
}

///|
/// Emit the chain short-circuit guard for a chain continuation.
/// If the optional chain already short-circuited (flag set), jump to the end.
/// Repeat of the `JumpIfNotOptionalChainShortCircuitKeep / Jump` pattern.
fn BytecodeBuilder::emit_chain_short_circuit_guard(
  self : BytecodeBuilder,
  end_jumps : Array[Int],
) -> Unit {
  let jump = self.emit(JumpIfNotOptionalChainShortCircuitKeep(-1))
  end_jumps.push(self.emit(Jump(-1)))
  self.patch(jump, JumpIfNotOptionalChainShortCircuitKeep(self.code.length()))
}

///|
fn BytecodeBuilder::compile_optional_chain_expr_body(
  self : BytecodeBuilder,
  expr : @ast.Expr,
  end_jumps : Array[Int],
) -> Unit raise Error {
  match expr {
    OptionalMember(obj, prop, loc) => {
      self.compile_expr(obj)
      self.emit_optional_null_guard(end_jumps)
      let _ = self.emit(GetProperty(prop, loc))
    }
    OptionalComputedMember(obj, key, loc) => {
      self.compile_expr(obj)
      self.emit_optional_null_guard(end_jumps)
      self.compile_expr(key)
      let _ = self.emit(GetComputed(loc))
    }
    ChainMember(obj, prop, loc) => {
      self.compile_optional_chain_expr_body(obj, end_jumps)
      self.emit_chain_short_circuit_guard(end_jumps)
      let _ = self.emit(GetProperty(prop, loc))
    }
    ChainComputedMember(obj, key, loc) => {
      self.compile_optional_chain_expr_body(obj, end_jumps)
      self.emit_chain_short_circuit_guard(end_jumps)
      self.compile_expr(key)
      let _ = self.emit(GetComputed(loc))
    }
    OptionalCall(callee, args, loc) => {
      // Peel grouping wrappers to recover member receivers for receiver binding,
      // matching the tree-walker's unwrap_grouping in eval_chain_expr.
      let unwrapped = match callee {
        Grouping(inner, _) => inner
        _ => callee
      }
      match unwrapped {
        OptionalMember(obj, prop, member_loc) => {
          self.compile_expr(obj)
          self.emit_optional_null_guard(end_jumps)
          let _ = self.emit(PreparePropertyCall(prop, member_loc))
          self.compile_optional_chain_call_with_receiver_tail(
            args,
            loc,
            end_jumps,
            optional_callee=true,
          )
        }
        ChainMember(obj, prop, member_loc) => {
          self.compile_optional_chain_expr_body(obj, end_jumps)
          self.emit_chain_short_circuit_guard(end_jumps)
          let _ = self.emit(PreparePropertyCall(prop, member_loc))
          self.compile_optional_chain_call_with_receiver_tail(
            args,
            loc,
            end_jumps,
            optional_callee=true,
          )
        }
        OptionalComputedMember(obj, key, member_loc) => {
          self.compile_expr(obj)
          self.emit_optional_null_guard(end_jumps)
          self.compile_expr(key)
          let _ = self.emit(PrepareComputedCall(member_loc))
          self.compile_optional_chain_call_with_receiver_tail(
            args,
            loc,
            end_jumps,
            optional_callee=true,
          )
        }
        ChainComputedMember(obj, key, member_loc) => {
          self.compile_optional_chain_expr_body(obj, end_jumps)
          self.emit_chain_short_circuit_guard(end_jumps)
          self.compile_expr(key)
          let _ = self.emit(PrepareComputedCall(member_loc))
          self.compile_optional_chain_call_with_receiver_tail(
            args,
            loc,
            end_jumps,
            optional_callee=true,
          )
        }
        Member(obj, prop, member_loc) => {
          // Grouping(Member(...)) recovered — compile with receiver preservation.
          self.compile_expr(obj)
          let _ = self.emit(PreparePropertyCall(prop, member_loc))
          self.compile_optional_chain_call_with_receiver_tail(
            args,
            loc,
            end_jumps,
            optional_callee=true,
          )
        }
        ComputedMember(obj, key, member_loc) => {
          self.compile_expr(obj)
          self.compile_expr(key)
          let _ = self.emit(PrepareComputedCall(member_loc))
          self.compile_optional_chain_call_with_receiver_tail(
            args,
            loc,
            end_jumps,
            optional_callee=true,
          )
        }
        _ => {
          self.compile_expr(callee)
          self.emit_optional_null_guard(end_jumps)
          self.emit_call(args, loc)
        }
      }
    }
    Call(OptionalMember(obj, prop, member_loc), args, loc) => {
      self.compile_expr(obj)
      self.emit_optional_null_guard(end_jumps)
      let _ = self.emit(PreparePropertyCall(prop, member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(ChainMember(obj, prop, member_loc), args, loc) => {
      self.compile_optional_chain_expr_body(obj, end_jumps)
      self.emit_chain_short_circuit_guard(end_jumps)
      let _ = self.emit(PreparePropertyCall(prop, member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(OptionalComputedMember(obj, key, member_loc), args, loc) => {
      self.compile_expr(obj)
      self.emit_optional_null_guard(end_jumps)
      self.compile_expr(key)
      let _ = self.emit(PrepareComputedCall(member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(ChainComputedMember(obj, key, member_loc), args, loc) => {
      self.compile_optional_chain_expr_body(obj, end_jumps)
      self.emit_chain_short_circuit_guard(end_jumps)
      self.compile_expr(key)
      let _ = self.emit(PrepareComputedCall(member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    // Call(OptionalCall(...), ...): continuation call after an optional call.
    // The inner OptionalCall handles its own nullish check and sets the
    // short-circuit flag if the callee was null. Here we check that flag:
    // if short-circuited, skip the continuation call; otherwise call the
    // inner call's result with the continuation arguments.
    Call(OptionalCall(callee, inner_args, inner_loc), continuation_args, loc) => {
      self.compile_optional_chain_expr_body(
        OptionalCall(callee, inner_args, inner_loc),
        end_jumps,
      )
      self.emit_chain_short_circuit_guard(end_jumps)
      self.emit_call(continuation_args, loc)
    }
    _ => self.compile_expr(expr)
  }
}

///|
fn BytecodeBuilder::compile_optional_chain_expr(
  self : BytecodeBuilder,
  expr : @ast.Expr,
) -> Unit raise Error {
  let end_jumps : Array[Int] = []
  let _ = self.emit(BeginOptionalChain)
  self.compile_optional_chain_expr_body(expr, end_jumps)
  for jump in end_jumps {
    self.patch(jump, Jump(self.code.length()))
  }
  let _ = self.emit(EndOptionalChain)
}

///|
fn BytecodeBuilder::compile_optional_member(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  prop : String,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_optional_chain_expr(OptionalMember(obj, prop, loc))
}

///|
fn BytecodeBuilder::compile_optional_computed_member(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  key : @ast.Expr,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_optional_chain_expr(OptionalComputedMember(obj, key, loc))
}

///|
fn BytecodeBuilder::compile_chain_member(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  prop : String,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_optional_chain_expr(ChainMember(obj, prop, loc))
}

///|
fn BytecodeBuilder::compile_chain_computed_member(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  key : @ast.Expr,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_optional_chain_expr(ChainComputedMember(obj, key, loc))
}

///|
fn BytecodeBuilder::compile_optional_plain_call(
  self : BytecodeBuilder,
  callee : @ast.Expr,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(callee)
  let call_jump = self.emit(JumpIfNotNullishKeep(-1))
  let _ = self.emit(Pop)
  let _ = self.emit(LoadUndefined)
  let end_jump = self.emit(Jump(-1))
  self.patch(call_jump, JumpIfNotNullishKeep(self.code.length()))
  self.emit_call(args, loc)
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_optional_call_with_receiver_tail(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
  end_jumps : Array[Int],
  optional_callee~ : Bool,
) -> Unit raise Error {
  if optional_callee {
    let call_jump = self.emit(JumpIfNotNullishKeep(-1))
    let _ = self.emit(Pop)
    let _ = self.emit(Pop)
    let _ = self.emit(LoadUndefined)
    end_jumps.push(self.emit(Jump(-1)))
    self.patch(call_jump, JumpIfNotNullishKeep(self.code.length()))
  }
  self.emit_call_with_receiver(args, loc)
  for jump in end_jumps {
    self.patch(jump, Jump(self.code.length()))
  }
}

///|
fn BytecodeBuilder::compile_optional_chain_call_with_receiver_tail(
  self : BytecodeBuilder,
  args : Array[@ast.Expr],
  loc : @token.Loc,
  end_jumps : Array[Int],
  optional_callee~ : Bool,
) -> Unit raise Error {
  if optional_callee {
    let call_jump = self.emit(JumpIfNotNullishKeep(-1))
    let _ = self.emit(Pop)
    let _ = self.emit(Pop)
    let _ = self.emit(LoadUndefined)
    let _ = self.emit(MarkOptionalChainShortCircuit)
    end_jumps.push(self.emit(Jump(-1)))
    self.patch(call_jump, JumpIfNotNullishKeep(self.code.length()))
  }
  self.emit_call_with_receiver(args, loc)
}

///|
fn BytecodeBuilder::compile_optional_property_call(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  prop : String,
  args : Array[@ast.Expr],
  member_loc : @token.Loc,
  loc : @token.Loc,
  optional_obj~ : Bool,
  optional_callee~ : Bool,
) -> Unit raise Error {
  let end_jumps : Array[Int] = []
  self.compile_expr(obj)
  if optional_obj {
    let member_jump = self.emit(JumpIfNotNullishKeep(-1))
    let _ = self.emit(Pop)
    let _ = self.emit(LoadUndefined)
    end_jumps.push(self.emit(Jump(-1)))
    self.patch(member_jump, JumpIfNotNullishKeep(self.code.length()))
  }
  let _ = self.emit(PreparePropertyCall(prop, member_loc))
  self.compile_optional_call_with_receiver_tail(
    args,
    loc,
    end_jumps,
    optional_callee~,
  )
}

///|
fn BytecodeBuilder::compile_optional_computed_call(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  key : @ast.Expr,
  args : Array[@ast.Expr],
  member_loc : @token.Loc,
  loc : @token.Loc,
  optional_obj~ : Bool,
  optional_callee~ : Bool,
) -> Unit raise Error {
  let end_jumps : Array[Int] = []
  self.compile_expr(obj)
  if optional_obj {
    let member_jump = self.emit(JumpIfNotNullishKeep(-1))
    let _ = self.emit(Pop)
    let _ = self.emit(LoadUndefined)
    end_jumps.push(self.emit(Jump(-1)))
    self.patch(member_jump, JumpIfNotNullishKeep(self.code.length()))
  }
  self.compile_expr(key)
  let _ = self.emit(PrepareComputedCall(member_loc))
  self.compile_optional_call_with_receiver_tail(
    args,
    loc,
    end_jumps,
    optional_callee~,
  )
}

///|
fn BytecodeBuilder::compile_chain_property_call(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  prop : String,
  args : Array[@ast.Expr],
  member_loc : @token.Loc,
  loc : @token.Loc,
  optional_callee~ : Bool,
) -> Unit raise Error {
  let end_jumps : Array[Int] = []
  let _ = self.emit(BeginOptionalChain)
  self.compile_optional_chain_expr_body(obj, end_jumps)
  let member_jump = self.emit(JumpIfNotOptionalChainShortCircuitKeep(-1))
  end_jumps.push(self.emit(Jump(-1)))
  self.patch(
    member_jump,
    JumpIfNotOptionalChainShortCircuitKeep(self.code.length()),
  )
  let _ = self.emit(PreparePropertyCall(prop, member_loc))
  self.compile_optional_call_with_receiver_tail(
    args,
    loc,
    end_jumps,
    optional_callee~,
  )
  let _ = self.emit(EndOptionalChain)
}

///|
fn BytecodeBuilder::compile_chain_computed_call(
  self : BytecodeBuilder,
  obj : @ast.Expr,
  key : @ast.Expr,
  args : Array[@ast.Expr],
  member_loc : @token.Loc,
  loc : @token.Loc,
  optional_callee~ : Bool,
) -> Unit raise Error {
  let end_jumps : Array[Int] = []
  let _ = self.emit(BeginOptionalChain)
  self.compile_optional_chain_expr_body(obj, end_jumps)
  let member_jump = self.emit(JumpIfNotOptionalChainShortCircuitKeep(-1))
  end_jumps.push(self.emit(Jump(-1)))
  self.patch(
    member_jump,
    JumpIfNotOptionalChainShortCircuitKeep(self.code.length()),
  )
  self.compile_expr(key)
  let _ = self.emit(PrepareComputedCall(member_loc))
  self.compile_optional_call_with_receiver_tail(
    args,
    loc,
    end_jumps,
    optional_callee~,
  )
  let _ = self.emit(EndOptionalChain)
}

///|
fn BytecodeBuilder::compile_identifier_load(
  self : BytecodeBuilder,
  name : String,
) -> Unit {
  match (self.local_slot(name), self.env_slot(name)) {
    (Some(slot), _) => {
      let _ = self.emit(LoadLocal(slot))
    }
    (_, Some(slot)) => {
      let _ = self.emit(LoadEnvSlot(slot))
    }
    _ => {
      let _ = self.emit(LoadName(name))
    }
  }
}

///|
fn BytecodeBuilder::compile_identifier_store(
  self : BytecodeBuilder,
  name : String,
) -> Unit {
  match (self.local_slot(name), self.env_slot(name)) {
    (Some(slot), _) => {
      let _ = self.emit(StoreLocal(slot))
    }
    (_, Some(slot)) => {
      let _ = self.emit(StoreEnvSlot(slot))
    }
    _ => {
      let _ = self.emit(StoreName(name))
    }
  }
}

///|
fn BytecodeBuilder::compile_identifier_compound_load(
  self : BytecodeBuilder,
  name : String,
) -> Unit {
  match (self.local_slot(name), self.env_slot(name)) {
    (Some(slot), _) => {
      let _ = self.emit(LoadLocal(slot))
    }
    (_, Some(slot)) => {
      let _ = self.emit(LoadEnvSlot(slot))
    }
    _ => {
      let _ = self.emit(LoadAssignmentName(name))
    }
  }
}

///|
fn BytecodeBuilder::compile_identifier_logical_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  name : String,
  value : @ast.Expr,
) -> Unit raise Error {
  self.compile_identifier_compound_load(name)
  let keep_current = match op {
    LogicalAndAssign => self.emit(JumpIfFalseKeep(-1))
    LogicalOrAssign => self.emit(JumpIfTrueKeep(-1))
    NullishAssign => self.emit(JumpIfNotNullishKeep(-1))
    _ => {
      bytecode_unsupported(UNSUPPORTED_LOGICAL_ASSIGNMENT_OPERATOR)
      -1
    }
  }
  let _ = self.emit(Pop)
  self.compile_expr(value)
  self.compile_identifier_store(name)
  match op {
    LogicalAndAssign =>
      self.patch(keep_current, JumpIfFalseKeep(self.code.length()))
    LogicalOrAssign =>
      self.patch(keep_current, JumpIfTrueKeep(self.code.length()))
    NullishAssign =>
      self.patch(keep_current, JumpIfNotNullishKeep(self.code.length()))
    _ => ()
  }
}

///|
fn BytecodeBuilder::compile_property_logical_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  prop : String,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(obj)
  let _ = self.emit(ReadPropertyForAssign(prop, member_loc))
  let keep_current = match op {
    LogicalAndAssign => self.emit(JumpIfFalseKeep(-1))
    LogicalOrAssign => self.emit(JumpIfTrueKeep(-1))
    NullishAssign => self.emit(JumpIfNotNullishKeep(-1))
    _ => {
      bytecode_unsupported(UNSUPPORTED_LOGICAL_ASSIGNMENT_OPERATOR)
      -1
    }
  }
  let _ = self.emit(Pop)
  self.compile_expr(value)
  let _ = self.emit(SetProperty(prop, loc))
  let end_jump = self.emit(Jump(-1))
  match op {
    LogicalAndAssign =>
      self.patch(keep_current, JumpIfFalseKeep(self.code.length()))
    LogicalOrAssign =>
      self.patch(keep_current, JumpIfTrueKeep(self.code.length()))
    NullishAssign =>
      self.patch(keep_current, JumpIfNotNullishKeep(self.code.length()))
    _ => ()
  }
  let _ = self.emit(DropPropertyAssignReference)
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_computed_logical_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  key : @ast.Expr,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  self.compile_expr(obj)
  self.compile_expr(key)
  let _ = self.emit(ReadComputedForAssign(member_loc))
  let keep_current = match op {
    LogicalAndAssign => self.emit(JumpIfFalseKeep(-1))
    LogicalOrAssign => self.emit(JumpIfTrueKeep(-1))
    NullishAssign => self.emit(JumpIfNotNullishKeep(-1))
    _ => {
      bytecode_unsupported(UNSUPPORTED_LOGICAL_ASSIGNMENT_OPERATOR)
      -1
    }
  }
  let _ = self.emit(Pop)
  self.compile_expr(value)
  let _ = self.emit(SetComputed(loc))
  let end_jump = self.emit(Jump(-1))
  match op {
    LogicalAndAssign =>
      self.patch(keep_current, JumpIfFalseKeep(self.code.length()))
    LogicalOrAssign =>
      self.patch(keep_current, JumpIfTrueKeep(self.code.length()))
    NullishAssign =>
      self.patch(keep_current, JumpIfNotNullishKeep(self.code.length()))
    _ => ()
  }
  let _ = self.emit(DropComputedAssignReference)
  self.patch(end_jump, Jump(self.code.length()))
}

///|
fn BytecodeBuilder::compile_identifier_compound_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  name : String,
  value : @ast.Expr,
  loc : @token.Loc,
) -> Unit raise Error {
  match op {
    LogicalAndAssign | LogicalOrAssign | NullishAssign =>
      self.compile_identifier_logical_assign(op, name, value)
    _ => {
      let bin_op = match @runtime.compound_assign_binary_op(op) {
        Some(bin_op) => bin_op
        None => {
          bytecode_unsupported(UNSUPPORTED_LOGICAL_ASSIGNMENT_OPERATOR)
          Add
        }
      }
      self.compile_identifier_compound_load(name)
      self.compile_expr(value)
      let _ = self.emit(BinaryOp(bin_op, loc))
      self.compile_identifier_store(name)
    }
  }
}

///|
fn BytecodeBuilder::compile_property_compound_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  prop : String,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  match op {
    LogicalAndAssign | LogicalOrAssign | NullishAssign =>
      return self.compile_property_logical_assign(
        op, obj, prop, value, member_loc, loc,
      )
    _ => ()
  }
  let bin_op = match @runtime.compound_assign_binary_op(op) {
    Some(bin_op) => bin_op
    None => {
      bytecode_unsupported(UNSUPPORTED_COMPOUND_ASSIGNMENT_TARGET)
      Add
    }
  }
  self.compile_expr(obj)
  let _ = self.emit(ReadPropertyForAssign(prop, member_loc))
  self.compile_expr(value)
  let _ = self.emit(BinaryOp(bin_op, loc))
  let _ = self.emit(SetProperty(prop, loc))
}

///|
fn BytecodeBuilder::compile_computed_compound_assign(
  self : BytecodeBuilder,
  op : @ast.CompoundOp,
  obj : @ast.Expr,
  key : @ast.Expr,
  value : @ast.Expr,
  member_loc : @token.Loc,
  loc : @token.Loc,
) -> Unit raise Error {
  match op {
    LogicalAndAssign | LogicalOrAssign | NullishAssign =>
      return self.compile_computed_logical_assign(
        op, obj, key, value, member_loc, loc,
      )
    _ => ()
  }
  let bin_op = match @runtime.compound_assign_binary_op(op) {
    Some(bin_op) => bin_op
    None => {
      bytecode_unsupported(UNSUPPORTED_COMPOUND_ASSIGNMENT_TARGET)
      Add
    }
  }
  self.compile_expr(obj)
  self.compile_expr(key)
  let _ = self.emit(ReadComputedForAssign(member_loc))
  self.compile_expr(value)
  let _ = self.emit(BinaryOp(bin_op, loc))
  let _ = self.emit(SetComputed(loc))
}

///|
fn bytecode_static_object_key(expr : @ast.Expr) -> String? {
  match expr {
    StringLit(s, _, _, _) => Some(s)
    Ident(name, _) => Some(name)
    NumberLit(n, _, _) => {
      let i = n.to_int()
      if i.to_double() == n {
        Some(i.to_string())
      } else {
        Some(n.to_string())
      }
    }
    _ => None
  }
}

///|
fn bytecode_object_lit_uses_incremental(props : Array[@ast.Property]) -> Bool {
  for prop in props {
    match prop.kind {
      Spread => return true
      Init =>
        if prop.is_method {
          return true
        } else if prop.computed {
          return true
        } else {
          match bytecode_static_object_key(prop.key) {
            Some(key) => if key == "__proto__" { return true }
            None => ()
          }
        }
      Get | Set => return true
    }
  }
  false
}

///|
fn bytecode_stmts_contain_super(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    if bytecode_stmt_contains_super(stmt) {
      return true
    }
  }
  false
}

///|
fn bytecode_stmt_contains_super(stmt : @ast.Stmt) -> Bool {
  match stmt {
    VarDecl(_, _, Some(expr), _)
    | ExprStmt(expr, _)
    | ReturnStmt(Some(expr), _)
    | ThrowStmt(expr, _) => bytecode_expr_contains_super(expr)
    DestructureDecl(_, pattern, init, _) =>
      bytecode_pattern_contains_super(pattern) ||
      bytecode_expr_contains_super(init)
    StmtList(stmts, _) | Block(stmts, _) => bytecode_stmts_contain_super(stmts)
    IfStmt(cond, then_branch, else_branch, _) => {
      if bytecode_expr_contains_super(cond) {
        return true
      }
      if bytecode_stmt_contains_super(then_branch) {
        return true
      }
      match else_branch {
        Some(stmt) => bytecode_stmt_contains_super(stmt)
        None => false
      }
    }
    WhileStmt(cond, body, _) =>
      bytecode_expr_contains_super(cond) || bytecode_stmt_contains_super(body)
    DoWhileStmt(body, cond, _) =>
      bytecode_stmt_contains_super(body) || bytecode_expr_contains_super(cond)
    ForStmt(init, cond, update, body, _) => {
      match init {
        Some(stmt) => if bytecode_stmt_contains_super(stmt) { return true }
        None => ()
      }
      match cond {
        Some(expr) => if bytecode_expr_contains_super(expr) { return true }
        None => ()
      }
      match update {
        Some(expr) => if bytecode_expr_contains_super(expr) { return true }
        None => ()
      }
      bytecode_stmt_contains_super(body)
    }
    ForInStmt(_, _, obj_expr, body, _) =>
      bytecode_expr_contains_super(obj_expr) ||
      bytecode_stmt_contains_super(body)
    ForInStmtPat(_, pattern, obj_expr, body, _) =>
      bytecode_pattern_contains_super(pattern) ||
      bytecode_expr_contains_super(obj_expr) ||
      bytecode_stmt_contains_super(body)
    ForInExpr(lhs_expr, obj_expr, body, _) =>
      bytecode_expr_contains_super(lhs_expr) ||
      bytecode_expr_contains_super(obj_expr) ||
      bytecode_stmt_contains_super(body)
    SwitchStmt(discriminant, cases, _) => {
      if bytecode_expr_contains_super(discriminant) {
        return true
      }
      for case in cases {
        match case.condition {
          Some(expr) => if bytecode_expr_contains_super(expr) { return true }
          None => ()
        }
        if bytecode_stmts_contain_super(case.body) {
          return true
        }
      }
      false
    }
    LabeledStmt(_, body, _) => bytecode_stmt_contains_super(body)
    FuncDecl(_, _, body, _, _)
    | FuncDeclExt(_, _, _, body, _, _)
    | GeneratorDecl(_, _, body, _, _)
    | GeneratorDeclExt(_, _, _, body, _, _)
    | AsyncFuncDecl(_, _, body, _, _)
    | AsyncFuncDeclExt(_, _, _, body, _, _)
    | AsyncGeneratorDecl(_, _, body, _, _)
    | AsyncGeneratorDeclExt(_, _, _, body, _, _) =>
      bytecode_stmts_contain_super(body)
    _ => false
  }
}

///|
fn bytecode_expr_contains_super(expr : @ast.Expr) -> Bool {
  match expr {
    SuperCall(_, _) | SuperMember(_, _) | SuperComputedMember(_, _) => true
    Unary(_, operand, _) | Grouping(operand, _) | SpreadExpr(operand, _) =>
      bytecode_expr_contains_super(operand)
    Binary(_, left, right, _) | Comma(left, right, _) =>
      bytecode_expr_contains_super(left) || bytecode_expr_contains_super(right)
    Ternary(cond, then_expr, else_expr, _) =>
      bytecode_expr_contains_super(cond) ||
      bytecode_expr_contains_super(then_expr) ||
      bytecode_expr_contains_super(else_expr)
    Assign(_, value, _) => bytecode_expr_contains_super(value)
    Call(callee, args, _)
    | OptionalCall(callee, args, _)
    | NewExpr(callee, args, _) => {
      if bytecode_expr_contains_super(callee) {
        return true
      }
      for arg in args {
        if bytecode_expr_contains_super(arg) {
          return true
        }
      }
      false
    }
    Member(obj, _, _) | OptionalMember(obj, _, _) | ChainMember(obj, _, _) =>
      bytecode_expr_contains_super(obj)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) =>
      bytecode_expr_contains_super(obj) || bytecode_expr_contains_super(key)
    MemberAssign(obj, _, value, _) =>
      bytecode_expr_contains_super(obj) || bytecode_expr_contains_super(value)
    ComputedAssign(obj, key, value, _) =>
      bytecode_expr_contains_super(obj) ||
      bytecode_expr_contains_super(key) ||
      bytecode_expr_contains_super(value)
    CompoundAssign(_, target, value, _) =>
      bytecode_expr_contains_super(target) ||
      bytecode_expr_contains_super(value)
    DestructureAssign(pattern, value, _) =>
      bytecode_pattern_contains_super(pattern) ||
      bytecode_expr_contains_super(value)
    UpdateExpr(_, operand, _, _) => bytecode_expr_contains_super(operand)
    FuncExpr(_, _, body, _, _)
    | FuncExprExt(_, _, _, body, _, _)
    | ArrowFunc(_, body, _, _)
    | ArrowFuncExt(_, _, body, _, _) => bytecode_stmts_contain_super(body)
    ArrayLit(elements, _) => {
      for element in elements {
        if bytecode_expr_contains_super(element) {
          return true
        }
      }
      false
    }
    ObjectLit(props, _) => bytecode_object_props_contain_data_super(props)
    TemplateLit(_, exprs, _) => {
      for expr in exprs {
        if bytecode_expr_contains_super(expr) {
          return true
        }
      }
      false
    }
    TaggedTemplate(tag, _, exprs, _) => {
      if bytecode_expr_contains_super(tag) {
        return true
      }
      for expr in exprs {
        if bytecode_expr_contains_super(expr) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn bytecode_object_props_contain_data_super(
  props : Array[@ast.Property],
) -> Bool {
  for prop in props {
    match prop.kind {
      Spread => if bytecode_expr_contains_super(prop.key) { return true }
      Init => {
        if prop.computed && bytecode_expr_contains_super(prop.key) {
          return true
        }
        if !prop.is_method && bytecode_expr_contains_super(prop.value) {
          return true
        }
      }
      Get | Set =>
        if prop.computed && bytecode_expr_contains_super(prop.key) {
          return true
        }
    }
  }
  false
}

///|
fn bytecode_pattern_contains_super(pattern : @ast.Pattern) -> Bool {
  match pattern {
    IdentPat(_) => false
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => if bytecode_pattern_contains_super(pat) { return true }
          None => ()
        }
      }
      match rest {
        Some(pat) => bytecode_pattern_contains_super(pat)
        None => false
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.computed_key {
          Some(expr) => if bytecode_expr_contains_super(expr) { return true }
          None => ()
        }
        match prop.default_val {
          Some(expr) => if bytecode_expr_contains_super(expr) { return true }
          None => ()
        }
        if bytecode_pattern_contains_super(prop.value) {
          return true
        }
      }
      match rest {
        Some(pat) => bytecode_pattern_contains_super(pat)
        None => false
      }
    }
    DefaultPat(inner, expr) =>
      bytecode_pattern_contains_super(inner) ||
      bytecode_expr_contains_super(expr)
    AssignTarget(expr) => bytecode_expr_contains_super(expr)
  }
}

///|
fn bytecode_reject_object_data_property_super(
  value : @ast.Expr,
) -> Unit raise Error {
  if bytecode_expr_contains_super(value) {
    bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_DATA_PROPERTY_SUPER)
  }
}

///|
fn BytecodeBuilder::compile_object_method(
  self : BytecodeBuilder,
  prop : @ast.Property,
  computed_key_on_stack? : Bool = false,
) -> Unit raise Error {
  let fn_idx = match prop.value {
    FuncExpr(Some(name), params, body, _, _) =>
      self.add_function(Some(name), params, body, None)
    FuncExpr(None, params, body, _, _) =>
      self.add_function(None, params, body, None)
    FuncExprExt(Some(name), params, rest_param, body, _, _) => {
      let (simple_params, simple_rest) = simple_ext_param_names_with_rest(
        params, rest_param,
      )
      self.add_function(Some(name), simple_params, body, simple_rest)
    }
    FuncExprExt(None, params, rest_param, body, _, _) => {
      let (simple_params, simple_rest) = simple_ext_param_names_with_rest(
        params, rest_param,
      )
      self.add_function(None, simple_params, body, simple_rest)
    }
    GeneratorExpr(_, _, _, _, _) | GeneratorExprExt(_, _, _, _, _, _) => {
      bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_GENERATOR_METHOD_PROPERTY)
      0
    }
    AsyncFuncExpr(_, _, _, _, _) | AsyncFuncExprExt(_, _, _, _, _, _) => {
      bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_ASYNC_METHOD_PROPERTY)
      0
    }
    AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _) => {
      bytecode_unsupported(
        UNSUPPORTED_OBJECT_LITERAL_ASYNC_GENERATOR_METHOD_PROPERTY,
      )
      0
    }
    _ => {
      bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_METHOD_PROPERTY)
      0
    }
  }
  if computed_key_on_stack {
    let _ = self.emit(MakeComputedMethodFunction(fn_idx))
  } else {
    let _ = self.emit(MakeMethodFunction(fn_idx))
  }
}

///|
fn BytecodeBuilder::compile_object_lit(
  self : BytecodeBuilder,
  props : Array[@ast.Property],
  loc : @token.Loc,
) -> Unit raise Error {
  if bytecode_object_lit_uses_incremental(props) {
    let _ = self.emit(StartObject)
    for prop in props {
      match prop.kind {
        Spread => {
          self.compile_expr(prop.key)
          let _ = self.emit(ObjectSpread(loc))
          continue
        }
        Init => ()
        Get | Set => {
          if prop.computed {
            self.compile_expr(prop.key)
            let _ = self.emit(ToObjectLiteralPropertyKey)
            self.compile_object_method(prop, computed_key_on_stack=true)
            match prop.kind {
              Get => {
                let _ = self.emit(ObjectSetComputedGetter)
              }
              Set => {
                let _ = self.emit(ObjectSetComputedSetter)
              }
              _ => ()
            }
            continue
          }
          let key = match bytecode_static_object_key(prop.key) {
            Some(key) => key
            None => {
              bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_PROPERTY_KEY)
              ""
            }
          }
          self.compile_object_method(prop)
          match prop.kind {
            Get => {
              let _ = self.emit(ObjectSetStaticGetter(key))
            }
            Set => {
              let _ = self.emit(ObjectSetStaticSetter(key))
            }
            _ => ()
          }
          continue
        }
      }
      if prop.is_method {
        if prop.computed {
          self.compile_expr(prop.key)
          let _ = self.emit(ToObjectLiteralPropertyKey)
          self.compile_object_method(prop, computed_key_on_stack=true)
          let _ = self.emit(ObjectSetComputed)
          continue
        }
        let key = match bytecode_static_object_key(prop.key) {
          Some(key) => key
          None => {
            bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_PROPERTY_KEY)
            ""
          }
        }
        if key == "__proto__" {
          bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_PROTO_METHOD_PROPERTY)
        }
        self.compile_object_method(prop)
        let _ = self.emit(ObjectSetStatic(key))
        continue
      }
      if prop.computed {
        self.compile_expr(prop.key)
        let _ = self.emit(ToObjectLiteralPropertyKey)
        bytecode_reject_object_data_property_super(prop.value)
        self.compile_expr(prop.value)
        let _ = self.emit(ObjectSetComputed)
        continue
      }
      let key = match bytecode_static_object_key(prop.key) {
        Some(key) => key
        None => {
          bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_PROPERTY_KEY)
          ""
        }
      }
      bytecode_reject_object_data_property_super(prop.value)
      self.compile_expr(prop.value)
      if key == "__proto__" {
        let _ = self.emit(ObjectSetProto)
      } else {
        let _ = self.emit(SetFunctionName(key))
        let _ = self.emit(ObjectSetStatic(key))
      }
    }
  } else {
    let keys : Array[String] = []
    for prop in props {
      match prop.kind {
        Get | Set =>
          bytecode_unsupported(
            UNSUPPORTED_OBJECT_LITERAL_COMPUTED_ACCESSOR_PROPERTY,
          )
        _ => ()
      }
      if prop.computed {
        bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_COMPUTED_PROPERTY)
      }
      if prop.is_method {
        bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_METHOD_PROPERTY)
      }
      let key = match bytecode_static_object_key(prop.key) {
        Some(key) => key
        None => {
          bytecode_unsupported(UNSUPPORTED_OBJECT_LITERAL_PROPERTY_KEY)
          ""
        }
      }
      bytecode_reject_object_data_property_super(prop.value)
      self.compile_expr(prop.value)
      let _ = self.emit(SetFunctionName(key))
      keys.push(key)
    }
    let _ = self.emit(MakeObject(keys))
  }
}

///|
fn bytecode_validate_destructure_assignment_pattern(
  pattern : @ast.Pattern,
) -> Unit raise Error {
  match pattern {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(pat) => bytecode_validate_destructure_assignment_pattern(pat)
          None => ()
        }
      }
      match rest {
        Some(pat) => bytecode_validate_destructure_assignment_pattern(pat)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        match prop.default_val {
          Some(_) =>
            bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_PATTERN_DEFAULT)
          None => ()
        }
        match prop.computed_key {
          Some(_) =>
            bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_PATTERN_COMPUTED_KEY)
          None => ()
        }
        bytecode_validate_destructure_assignment_pattern(prop.value)
      }
      match rest {
        Some(pat) => bytecode_validate_destructure_assignment_pattern(pat)
        None => ()
      }
    }
    DefaultPat(_, _) =>
      bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_PATTERN_DEFAULT)
    AssignTarget(_) =>
      bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_PATTERN_MEMBER_TARGET)
  }
}

///|
fn BytecodeBuilder::compile_expr_for_effect(
  self : BytecodeBuilder,
  expr : @ast.Expr,
) -> Unit raise Error {
  // Only elide expressions whose evaluation cannot throw or trigger user code.
  // Identifier references, calls, member expressions, and object/array/function
  // literals still use the value path and discard the result.
  match expr {
    NumberLit(_, _, _)
    | StringLit(_, _, _, _)
    | BoolLit(_, _)
    | NullLit(_)
    | UndefinedLit(_) => ()
    Grouping(inner, _) => self.compile_expr_for_effect(inner)
    Comma(left, right, _) => {
      self.compile_expr_for_effect(left)
      self.compile_expr_for_effect(right)
    }
    _ => {
      self.compile_expr(expr)
      let _ = self.emit(Pop)
    }
  }
}

///|
fn BytecodeBuilder::compile_expr_for_completion(
  self : BytecodeBuilder,
  expr : @ast.Expr,
) -> Unit raise Error {
  match expr {
    NumberLit(n, _, _) => self.emit_completion_value(Value::Number(n))
    StringLit(s, _, _, _) => self.emit_completion_value(Value::String_(s))
    BoolLit(b, _) => self.emit_completion_value(Value::Bool(b))
    NullLit(_) => self.emit_completion_value(Value::Null)
    UndefinedLit(_) => self.emit_completion_value(Value::Undefined)
    Grouping(inner, _) => self.compile_expr_for_completion(inner)
    Comma(left, right, _) => {
      self.compile_expr_for_effect(left)
      self.compile_expr_for_completion(right)
    }
    _ => {
      self.compile_expr(expr)
      let _ = self.emit(SetCompletion)
    }
  }
}

///|
fn BytecodeBuilder::compile_expr(
  self : BytecodeBuilder,
  expr : @ast.Expr,
) -> Unit raise Error {
  match expr {
    NumberLit(n, _, _) => {
      let _ = self.emit(LoadConst(Value::Number(n)))
    }
    StringLit(s, _, _, _) => {
      let _ = self.emit(LoadConst(Value::String_(s)))
    }
    BoolLit(b, _) => {
      let _ = self.emit(LoadConst(Value::Bool(b)))
    }
    NullLit(_) => {
      let _ = self.emit(LoadConst(Value::Null))
    }
    UndefinedLit(_) => {
      let _ = self.emit(LoadUndefined)
    }
    ArrayHole(_) => bytecode_unsupported(UNSUPPORTED_ARRAY_HOLE)
    ThisExpr(_) => {
      self.has_this = true
      let _ = self.emit(LoadThis)
    }
    NewTargetExpr(_) => {
      self.has_new_target = true
      let _ = self.emit(LoadNewTarget)
    }
    SuperCall(_, _) => bytecode_unsupported(UNSUPPORTED_SUPER_CALL)
    SuperMember(prop, loc) => {
      self.has_this = true
      let _ = self.emit(LoadSuperProperty(prop, loc))
    }
    SuperComputedMember(key, loc) => {
      self.has_this = true
      self.compile_expr(key)
      let _ = self.emit(LoadSuperComputed(loc))
    }
    Ident(name, _) => self.compile_identifier_load(name)
    Binary(And, left, right, _) => self.compile_logical_and(left, right)
    Binary(Or, left, right, _) => self.compile_logical_or(left, right)
    Binary(NullishCoalesce, left, right, _) =>
      self.compile_nullish_coalesce(left, right)
    Unary(Delete, Member(obj, prop, _), _) => {
      self.compile_expr(obj)
      let _ = self.emit(DeleteProperty(prop))
    }
    Unary(Delete, ComputedMember(obj, key, _), _) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(DeleteComputed)
    }
    Unary(Delete, Ident(name, _), _) =>
      match (self.local_slot(name), self.env_slot(name)) {
        (Some(_), _) | (_, Some(_)) => {
          let _ = self.emit(LoadConst(Value::Bool(false)))
        }
        _ => {
          let _ = self.emit(DeleteName(name))
        }
      }
    Unary(Delete, _, _) =>
      bytecode_unsupported(UNSUPPORTED_DELETE_NON_PROPERTY_OPERATOR)
    Unary(Typeof, Ident(name, _), loc) =>
      match (self.local_slot(name), self.env_slot(name)) {
        (Some(slot), _) => {
          let _ = self.emit(LoadLocal(slot))
          let _ = self.emit(UnaryValueOp(Typeof, loc))
        }
        (_, Some(slot)) => {
          let _ = self.emit(LoadEnvSlot(slot))
          let _ = self.emit(UnaryValueOp(Typeof, loc))
        }
        _ => {
          let _ = self.emit(TypeofName(name))
        }
      }
    Unary(Typeof, operand, loc) => {
      self.compile_expr(operand)
      let _ = self.emit(UnaryValueOp(Typeof, loc))
    }
    Unary(Void, operand, _) => {
      self.compile_expr(operand)
      let _ = self.emit(Pop)
      let _ = self.emit(LoadUndefined)
    }
    Unary(op, operand, loc) => {
      self.compile_expr(operand)
      let _ = self.emit(UnaryValueOp(op, loc))
    }
    Ternary(cond, then_expr, else_expr, _) => {
      self.compile_expr(cond)
      let else_jump = self.emit(JumpIfFalse(-1))
      self.compile_expr(then_expr)
      let end_jump = self.emit(Jump(-1))
      self.patch(else_jump, JumpIfFalse(self.code.length()))
      self.compile_expr(else_expr)
      self.patch(end_jump, Jump(self.code.length()))
    }
    Binary(op, left, right, loc) => {
      self.compile_expr(left)
      self.compile_expr(right)
      let _ = self.emit(BinaryOp(op, loc))
    }
    Comma(left, right, _) => {
      self.compile_expr_for_effect(left)
      self.compile_expr(right)
    }
    TemplateLit(quasis, exprs, _) => {
      let first_cooked = if quasis.length() > 0 {
        match quasis[0].1 {
          Some(s) => s
          None => ""
        }
      } else {
        ""
      }
      let _ = self.emit(LoadConst(Value::String_(first_cooked)))
      for i, expr in exprs {
        self.compile_expr(expr)
        let tail_cooked = if i + 1 < quasis.length() {
          match quasis[i + 1].1 {
            Some(s) => s
            None => ""
          }
        } else {
          ""
        }
        let _ = self.emit(AppendTemplate(tail_cooked))
      }
    }
    TaggedTemplate(Member(obj, prop, member_loc), quasis, exprs, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(PreparePropertyCall(prop, member_loc))
      let _ = self.emit(MakeTemplateObject(quasis))
      for expr in exprs {
        self.compile_expr(expr)
      }
      let _ = self.emit(CallWithReceiver(1 + exprs.length(), loc))
    }
    TaggedTemplate(ComputedMember(obj, key, member_loc), quasis, exprs, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(PrepareComputedCall(member_loc))
      let _ = self.emit(MakeTemplateObject(quasis))
      for expr in exprs {
        self.compile_expr(expr)
      }
      let _ = self.emit(CallWithReceiver(1 + exprs.length(), loc))
    }
    TaggedTemplate(tag, quasis, exprs, loc) => {
      self.compile_expr(tag)
      let _ = self.emit(MakeTemplateObject(quasis))
      for expr in exprs {
        self.compile_expr(expr)
      }
      let _ = self.emit(Call(1 + exprs.length(), loc))
    }
    RegexLit(pattern, flags, _) => {
      let _ = self.emit(MakeRegExp(pattern, flags))
    }
    DestructureAssign(pattern, value, _) => {
      bytecode_validate_destructure_assignment_pattern(pattern)
      self.compile_expr(value)
      let _ = self.emit(AssignPattern(pattern))
    }
    Assign(name, value, _) => {
      self.compile_expr(value)
      if bytecode_is_anonymous_function_definition(value) {
        let _ = self.emit(SetFunctionName(name))
      }
      self.compile_identifier_store(name)
    }
    UpdateExpr(op, Ident(name, _), prefix, loc) =>
      match (self.local_slot(name), self.env_slot(name)) {
        (Some(slot), _) => {
          let _ = self.emit(UpdateLocal(slot, op, prefix))
        }
        (_, Some(slot)) => {
          let _ = self.emit(UpdateEnvSlot(slot, op, prefix))
        }
        _ => {
          let _ = self.emit(UpdateName(name, op, prefix, loc))
        }
      }
    UpdateExpr(op, Member(obj, prop, member_loc), prefix, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(UpdateProperty(prop, op, prefix, member_loc, loc))
    }
    UpdateExpr(op, ComputedMember(obj, key, member_loc), prefix, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(UpdateComputed(op, prefix, member_loc, loc))
    }
    UpdateExpr(_, _, _, _) => bytecode_unsupported(UNSUPPORTED_UPDATE_TARGET)
    CompoundAssign(op, Ident(name, _), value, loc) =>
      self.compile_identifier_compound_assign(op, name, value, loc)
    CompoundAssign(op, Member(obj, prop, member_loc), value, loc) =>
      self.compile_property_compound_assign(
        op, obj, prop, value, member_loc, loc,
      )
    CompoundAssign(op, ComputedMember(obj, key, member_loc), value, loc) =>
      self.compile_computed_compound_assign(
        op, obj, key, value, member_loc, loc,
      )
    CompoundAssign(_, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_COMPOUND_ASSIGNMENT_TARGET)
    FuncExpr(Some(name), params, body, _, _) => {
      let fn_idx = self.add_function(Some(name), params, body, None)
      let _ = self.emit(MakeNamedFunction(fn_idx, name))
    }
    FuncExpr(None, params, body, _, _) => {
      let fn_idx = self.add_function(None, params, body, None)
      let _ = self.emit(MakeFunction(fn_idx))
    }
    FuncExprExt(Some(name), params, rest_param, body, _, _) => {
      let (simple_params, simple_rest) = simple_ext_param_names_with_rest(
        params, rest_param,
      )
      let fn_idx = self.add_function(
        Some(name),
        simple_params,
        body,
        simple_rest,
      )
      let _ = self.emit(MakeNamedFunction(fn_idx, name))
    }
    FuncExprExt(None, params, rest_param, body, _, _) => {
      let (simple_params, simple_rest) = simple_ext_param_names_with_rest(
        params, rest_param,
      )
      let fn_idx = self.add_function(None, simple_params, body, simple_rest)
      let _ = self.emit(MakeFunction(fn_idx))
    }
    ArrowFunc(params, body, _, _) => {
      let fn_idx = self.add_function(None, params, body, None)
      let _ = self.emit(MakeArrowFunction(fn_idx))
    }
    ArrowFuncExt(params, rest_param, body, _, _) => {
      let (simple_params, simple_rest) = simple_ext_param_names_with_rest(
        params, rest_param,
      )
      let fn_idx = self.add_function(None, simple_params, body, simple_rest)
      let _ = self.emit(MakeArrowFunction(fn_idx))
    }
    Grouping(inner, _) => self.compile_expr(inner)
    ObjectLit(props, loc) => self.compile_object_lit(props, loc)
    ArrayLit(elements, _) => {
      let mut has_spread = false
      for element in elements {
        match element {
          SpreadExpr(_, _) => has_spread = true
          _ => ()
        }
      }
      if has_spread {
        let _ = self.emit(StartArray)
        for element in elements {
          match element {
            ArrayHole(_) => {
              let _ = self.emit(ArrayPushHole)
            }
            SpreadExpr(inner, loc) => {
              self.compile_expr(inner)
              let _ = self.emit(ArrayPushSpread(loc))
            }
            _ => {
              self.compile_expr(element)
              let _ = self.emit(ArrayPushValue)
            }
          }
        }
      } else {
        let hole_idxs : Array[Int] = []
        for i, element in elements {
          match element {
            ArrayHole(_) => {
              hole_idxs.push(i)
              let _ = self.emit(LoadUndefined)
            }
            _ => self.compile_expr(element)
          }
        }
        if hole_idxs.length() > 0 {
          let _ = self.emit(MakeArrayWithHoles(elements.length(), hole_idxs))
        } else {
          let _ = self.emit(MakeArray(elements.length()))
        }
      }
    }
    Member(Ident("console", _), prop, _) => {
      let _ = self.emit(LoadConsoleMember(prop))
    }
    Member(obj, prop, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(GetProperty(prop, loc))
    }
    ComputedMember(obj, key, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(GetComputed(loc))
    }
    OptionalMember(obj, prop, loc) =>
      self.compile_optional_member(obj, prop, loc)
    OptionalComputedMember(obj, key, loc) =>
      self.compile_optional_computed_member(obj, key, loc)
    ChainMember(obj, prop, loc) => self.compile_chain_member(obj, prop, loc)
    ChainComputedMember(obj, key, loc) =>
      self.compile_chain_computed_member(obj, key, loc)
    MemberAssign(obj, prop, value, loc) => {
      self.compile_expr(obj)
      self.compile_expr(value)
      let _ = self.emit(SetProperty(prop, loc))
    }
    ComputedAssign(obj, key, value, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      self.compile_expr(value)
      let _ = self.emit(SetComputed(loc))
    }
    NewExpr(callee, args, loc) => {
      self.compile_expr(callee)
      self.emit_construct(args, loc)
    }
    OptionalCall(callee, args, loc) =>
      match callee {
        OptionalMember(obj, prop, member_loc) =>
          self.compile_optional_property_call(
            obj,
            prop,
            args,
            member_loc,
            loc,
            optional_obj=true,
            optional_callee=true,
          )
        OptionalComputedMember(obj, key, member_loc) =>
          self.compile_optional_computed_call(
            obj,
            key,
            args,
            member_loc,
            loc,
            optional_obj=true,
            optional_callee=true,
          )
        ChainMember(obj, prop, member_loc) =>
          self.compile_chain_property_call(
            obj,
            prop,
            args,
            member_loc,
            loc,
            optional_callee=true,
          )
        ChainComputedMember(obj, key, member_loc) =>
          self.compile_chain_computed_call(
            obj,
            key,
            args,
            member_loc,
            loc,
            optional_callee=true,
          )
        Member(obj, prop, member_loc) =>
          self.compile_optional_property_call(
            obj,
            prop,
            args,
            member_loc,
            loc,
            optional_obj=false,
            optional_callee=true,
          )
        ComputedMember(obj, key, member_loc) =>
          self.compile_optional_computed_call(
            obj,
            key,
            args,
            member_loc,
            loc,
            optional_obj=false,
            optional_callee=true,
          )
        _ => self.compile_optional_plain_call(callee, args, loc)
      }
    Call(Member(Ident("console", _), prop, _), args, loc) => {
      let _ = self.emit(LoadConsoleMember(prop))
      self.emit_call(args, loc)
    }
    Call(SuperMember(prop, member_loc), args, loc) => {
      self.has_this = true
      let _ = self.emit(PrepareSuperPropertyCall(prop, member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(SuperComputedMember(key, member_loc), args, loc) => {
      self.has_this = true
      self.compile_expr(key)
      let _ = self.emit(PrepareSuperComputedCall(member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(OptionalMember(obj, prop, member_loc), args, loc) =>
      self.compile_optional_property_call(
        obj,
        prop,
        args,
        member_loc,
        loc,
        optional_obj=true,
        optional_callee=false,
      )
    Call(OptionalComputedMember(obj, key, member_loc), args, loc) =>
      self.compile_optional_computed_call(
        obj,
        key,
        args,
        member_loc,
        loc,
        optional_obj=true,
        optional_callee=false,
      )
    // Parser emits OptionalCall, not plain Call, inside optional chains;
    // keep these arms for hand-built ASTs and future parser changes.
    Call(ChainMember(obj, prop, member_loc), args, loc) =>
      self.compile_chain_property_call(
        obj,
        prop,
        args,
        member_loc,
        loc,
        optional_callee=false,
      )
    Call(ChainComputedMember(obj, key, member_loc), args, loc) =>
      self.compile_chain_computed_call(
        obj,
        key,
        args,
        member_loc,
        loc,
        optional_callee=false,
      )
    Call(Member(obj, prop, member_loc), args, loc) => {
      self.compile_expr(obj)
      let _ = self.emit(PreparePropertyCall(prop, member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(ComputedMember(obj, key, member_loc), args, loc) => {
      self.compile_expr(obj)
      self.compile_expr(key)
      let _ = self.emit(PrepareComputedCall(member_loc))
      self.emit_call_with_receiver(args, loc)
    }
    Call(callee, args, loc) =>
      if bytecode_is_direct_eval_callee(callee) {
        let _ = self.emit(LoadDirectEvalCallee)
        self.compile_dynamic_args(args)
        let _ = self.emit(CallDirectEval(loc))
      } else {
        self.compile_expr(callee)
        self.emit_call(args, loc)
      }
    SpreadExpr(_, _) => bytecode_unsupported(UNSUPPORTED_SPREAD_EXPRESSION)
    GeneratorExpr(_, _, _, _, _) | GeneratorExprExt(_, _, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_GENERATOR_EXPRESSION)
    YieldExpr(_, _, _) => bytecode_unsupported(UNSUPPORTED_YIELD_EXPRESSION)
    AsyncFuncExpr(_, _, _, _, _) | AsyncFuncExprExt(_, _, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_ASYNC_FUNCTION_EXPRESSION)
    AsyncArrowFunc(_, _, _, _) | AsyncArrowFuncExt(_, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_ASYNC_ARROW_FUNCTION)
    AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_ASYNC_GENERATOR_EXPRESSION)
    AwaitExpr(_, _) => bytecode_unsupported(UNSUPPORTED_AWAIT_EXPRESSION)
    WebCompatCallAssign(_, _, _) =>
      bytecode_unsupported(UNSUPPORTED_WEB_COMPAT_CALL_ASSIGN)
    ClassExpr(_, _, _, _, _) =>
      bytecode_unsupported(UNSUPPORTED_CLASS_EXPRESSION)
  }
}

///|
fn simple_ext_param_names_with_rest(
  params : Array[@ast.Param],
  rest_param : String?,
) -> (Array[String], String?) raise Error {
  let names : Array[String] = []
  for param in params {
    match (param.default_val, param.pattern, param.is_rest_pattern) {
      (None, None, false) => names.push(param.name)
      (Some(_), _, _) => bytecode_unsupported(UNSUPPORTED_DEFAULT_PARAMETER)
      (_, Some(_), _) | (_, _, true) =>
        bytecode_unsupported(UNSUPPORTED_DESTRUCTURING_PARAMETER)
    }
  }
  (names, rest_param)
}

///|
fn add_lexical_decl_name(
  lexical_names : @set.Set[String],
  name : String,
) -> Unit raise Error {
  if lexical_names.contains(name) {
    raise @errors.SyntaxError(
      message="Identifier '\{name}' has already been declared",
    )
  }
  lexical_names.add(name)
}

///|
fn collect_pattern_decl_names(
  pattern : @ast.Pattern,
  names : @set.Set[String],
  lexical? : Bool = false,
) -> Unit raise Error {
  for name in @static_semantics.bound_names(pattern) {
    if lexical {
      add_lexical_decl_name(names, name)
    } else {
      names.add(name)
    }
  }
}

///|
fn collect_block_lexical_decl_names_from_stmt(
  stmt : @ast.Stmt,
  lexical_names : @set.Set[String],
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
    ClassDecl(name, _, _, _, _) => add_lexical_decl_name(lexical_names, name)
    // Function declarations are lexical only in block statement lists.
    FuncDecl(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          if !(allow_duplicate_block_functions &&
            block_function_kinds.get(name) == Some(1)) {
            raise @errors.SyntaxError(
              message="Identifier '\{name}' has already been declared",
            )
          }
        } else {
          lexical_names.add(name)
        }
        block_function_kinds[name] = 1
      }
    FuncDeclExt(name, _, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          if !(allow_duplicate_block_functions &&
            block_function_kinds.get(name) == Some(1)) {
            raise @errors.SyntaxError(
              message="Identifier '\{name}' has already been declared",
            )
          }
        } else {
          lexical_names.add(name)
        }
        block_function_kinds[name] = 1
      }
    GeneratorDecl(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names.add(name)
        }
        block_function_kinds[name] = 2
      }
    GeneratorDeclExt(name, _, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names.add(name)
        }
        block_function_kinds[name] = 2
      }
    AsyncFuncDecl(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names.add(name)
        }
        block_function_kinds[name] = 2
      }
    AsyncFuncDeclExt(name, _, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names.add(name)
        }
        block_function_kinds[name] = 2
      }
    AsyncGeneratorDecl(name, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names.add(name)
        }
        block_function_kinds[name] = 2
      }
    AsyncGeneratorDeclExt(name, _, _, _, _, _) =>
      if include_block_functions {
        if lexical_names.contains(name) {
          raise @errors.SyntaxError(
            message="Identifier '\{name}' has already been declared",
          )
        } else {
          lexical_names.add(name)
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
    ExportNamedDecl(Some(decl), _, _, _, _) =>
      collect_block_lexical_decl_names_from_stmt(
        decl,
        lexical_names,
        block_function_kinds,
        include_block_functions~,
        allow_duplicate_block_functions~,
      )
    ExportDefaultDecl(expr, _) =>
      match module_default_export_binding(expr) {
        LocalDefaultBinding(name) => add_lexical_decl_name(lexical_names, name)
        SyntheticDefaultBinding => ()
      }
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
  let lexical_names = @set.Set::default()
  let block_function_kinds : Map[String, Int] = Map([])
  for stmt in stmts {
    collect_block_lexical_decl_names_from_stmt(
      stmt,
      lexical_names,
      block_function_kinds,
      include_block_functions~,
      allow_duplicate_block_functions~,
    )
  }
  let var_name_set = @set.Set::default()
  for
    name in @static_semantics.collect_var_declared_names(
      stmts,
      include_funcs=include_function_decls_in_var_names,
    ) {
    var_name_set.add(name)
  }
  for name in lexical_names {
    if var_name_set.contains(name) {
      raise @errors.SyntaxError(
        message="Identifier '\{name}' has already been declared",
      )
    }
  }
}

///|
/// CaseBlock declarations share one lexical environment even though the AST
/// stores each case body separately.
fn flatten_case_block_statements(
  cases : Array[@ast.SwitchCase],
) -> Array[@ast.Stmt] {
  let stmts : Array[@ast.Stmt] = []
  for case in cases {
    for stmt in case.body {
      stmts.push(stmt)
    }
  }
  stmts
}

///|
fn validate_strict_lex_form(
  form : @token.LexForm,
  loc : @token.Loc,
  strict_context : Bool,
) -> Unit raise Error {
  if !strict_context {
    return
  }
  match form {
    LexNormal => ()
    StringLegacyOctalEscape =>
      raise @errors.SyntaxError(
        message="Octal escape sequences are not allowed in strict mode at line \{loc.line}, col \{loc.col}",
      )
    NumberLegacyOctalInt =>
      raise @errors.SyntaxError(
        message="Octal literals are not allowed in strict mode at line \{loc.line}, col \{loc.col}",
      )
    NumberNonOctalDecimalInt =>
      raise @errors.SyntaxError(
        message="Decimals with leading zeros are not allowed in strict mode at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
priv enum EarlyErrorTask {
  Expr(@ast.Expr, Bool)
  Stmt(@ast.Stmt, Bool)
  Pattern(@ast.Pattern, Bool, Bool)
  Param(@ast.Param, Bool)
  StmtListCheck(Array[@ast.Stmt], Bool, Bool, Bool)
  LexForm(@token.LexForm, @token.Loc, Bool)
  TemplateQuasis(Array[(String, String?)], @token.Loc)
}

///|
fn schedule_exprs_reverse(
  work : Array[EarlyErrorTask],
  exprs : Array[@ast.Expr],
  strict_context : Bool,
) -> Unit {
  for i = exprs.length() - 1; i >= 0; i = i - 1 {
    work.push(Expr(exprs[i], strict_context))
  }
}

///|
fn schedule_stmts_reverse(
  work : Array[EarlyErrorTask],
  stmts : Array[@ast.Stmt],
  strict_context : Bool,
) -> Unit {
  for i = stmts.length() - 1; i >= 0; i = i - 1 {
    work.push(Stmt(stmts[i], strict_context))
  }
}

///|
fn schedule_params_reverse(
  work : Array[EarlyErrorTask],
  params : Array[@ast.Param],
  strict_context : Bool,
) -> Unit {
  for i = params.length() - 1; i >= 0; i = i - 1 {
    work.push(Param(params[i], strict_context))
  }
}

///|
fn schedule_function_body(
  work : Array[EarlyErrorTask],
  params : Array[@ast.Param]?,
  body : Array[@ast.Stmt],
  parent_strict : Bool,
) -> Unit {
  let child_strict = is_function_strict(parent_strict, body)
  schedule_stmts_reverse(work, body, child_strict)
  match params {
    Some(ps) => schedule_params_reverse(work, ps, child_strict)
    None => ()
  }
  work.push(StmtListCheck(body, false, false, true))
}

///|
fn schedule_class_members_reverse(
  work : Array[EarlyErrorTask],
  members : Array[@ast.ClassMember],
) -> Unit {
  for i = members.length() - 1; i >= 0; i = i - 1 {
    match members[i] {
      @ast.ClassMember::Method(m) => {
        work.push(Expr(m.value, true))
        work.push(Expr(m.key, true))
      }
      @ast.ClassMember::Field(f) => {
        match f.initializer {
          Some(expr) => work.push(Expr(expr, true))
          None => ()
        }
        work.push(Expr(f.key, true))
      }
      @ast.ClassMember::StaticBlock(stmts, _) => {
        schedule_stmts_reverse(work, stmts, true)
        work.push(StmtListCheck(stmts, false, false, false))
      }
    }
  }
}

///|
pub fn validate_compiled_script_early_errors(
  stmts : Array[@ast.Stmt],
  strict_context : Bool,
) -> Unit raise Error {
  let work : Array[EarlyErrorTask] = []
  schedule_stmts_reverse(work, stmts, strict_context)
  work.push(StmtListCheck(stmts, false, false, true))
  while work.length() > 0 {
    let task = work.pop().unwrap()
    match task {
      StmtListCheck(
        stmts,
        include_funcs,
        allow_duplicates,
        include_funcs_in_var
      ) =>
        validate_block_statement_list_early_errors(
          stmts,
          include_block_functions=include_funcs,
          allow_duplicate_block_functions=allow_duplicates,
          include_function_decls_in_var_names=include_funcs_in_var,
        )
      LexForm(form, loc, strict) => validate_strict_lex_form(form, loc, strict)
      TemplateQuasis(quasis, loc) =>
        for q in quasis {
          if q.1 is None {
            raise @errors.SyntaxError(
              message="Invalid escape sequence in template literal at line \{loc.line}, col \{loc.col}",
            )
          }
        }
      Param(param, strict) => {
        match param.pattern {
          Some(pattern) => work.push(Pattern(pattern, strict, true))
          None => ()
        }
        match param.default_val {
          Some(expr) => work.push(Expr(expr, strict))
          None => ()
        }
      }
      Pattern(pattern, strict, binding) =>
        match pattern {
          IdentPat(name) =>
            if binding {
              if strict {
                @static_semantics.validate_strict_binding_name(name)
              }
            } else {
              @static_semantics.validate_strict_assignment_target_name(
                strict, name,
              )
            }
          DefaultPat(inner, default_expr) => {
            work.push(Expr(default_expr, strict))
            work.push(Pattern(inner, strict, binding))
          }
          AssignTarget(expr) =>
            match expr {
              Ident(name, _) =>
                @static_semantics.validate_strict_assignment_target_name(
                  strict, name,
                )
              _ => work.push(Expr(expr, strict))
            }
          ArrayPat(elements, rest) => {
            match rest {
              Some(pattern) => work.push(Pattern(pattern, strict, binding))
              None => ()
            }
            for i = elements.length() - 1; i >= 0; i = i - 1 {
              match elements[i] {
                Some(pattern) => work.push(Pattern(pattern, strict, binding))
                None => ()
              }
            }
          }
          ObjectPat(props, rest) => {
            match rest {
              Some(pattern) => work.push(Pattern(pattern, strict, binding))
              None => ()
            }
            for i = props.length() - 1; i >= 0; i = i - 1 {
              let prop = props[i]
              match prop.default_val {
                Some(expr) => work.push(Expr(expr, strict))
                None => ()
              }
              work.push(Pattern(prop.value, strict, binding))
              match prop.computed_key {
                Some(expr) => work.push(Expr(expr, strict))
                None => ()
              }
              work.push(LexForm(prop.key_lex_form, prop.key_loc, strict))
            }
          }
        }
      Expr(expr, strict) =>
        match expr {
          Ident(name, _) =>
            @static_semantics.validate_strict_identifier_reference(strict, name)
          StringLit(_, _, form, loc) | NumberLit(_, form, loc) =>
            validate_strict_lex_form(form, loc, strict)
          FuncExpr(_, _, body, _, _)
          | ArrowFunc(_, body, _, _)
          | GeneratorExpr(_, _, body, _, _)
          | AsyncFuncExpr(_, _, body, _, _)
          | AsyncArrowFunc(_, body, _, _)
          | AsyncGeneratorExpr(_, _, body, _, _) =>
            schedule_function_body(work, None, body, strict)
          FuncExprExt(_, params, _, body, _, _)
          | GeneratorExprExt(_, params, _, body, _, _)
          | AsyncFuncExprExt(_, params, _, body, _, _)
          | AsyncGeneratorExprExt(_, params, _, body, _, _) =>
            schedule_function_body(work, Some(params), body, strict)
          ArrowFuncExt(params, _, body, _, _)
          | AsyncArrowFuncExt(params, _, body, _, _) =>
            schedule_function_body(work, Some(params), body, strict)
          ClassExpr(_, superclass, members, _, _) => {
            schedule_class_members_reverse(work, members)
            match superclass {
              Some(expr) => work.push(Expr(expr, true))
              None => ()
            }
          }
          Assign(name, rhs, _) => {
            work.push(Expr(rhs, strict))
            @static_semantics.validate_strict_assignment_target_name(
              strict, name,
            )
          }
          UpdateExpr(_, target, _, _) =>
            match target {
              Ident(name, _) =>
                @static_semantics.validate_strict_assignment_target_name(
                  strict, name,
                )
              _ => work.push(Expr(target, strict))
            }
          CompoundAssign(_, lhs, rhs, _) => {
            work.push(Expr(rhs, strict))
            match lhs {
              Ident(name, _) =>
                @static_semantics.validate_strict_assignment_target_name(
                  strict, name,
                )
              _ => work.push(Expr(lhs, strict))
            }
          }
          Binary(_, left, right, _) | Comma(left, right, _) => {
            work.push(Expr(right, strict))
            work.push(Expr(left, strict))
          }
          ComputedMember(obj, key, _)
          | OptionalComputedMember(obj, key, _)
          | ChainComputedMember(obj, key, _) => {
            work.push(Expr(key, strict))
            work.push(Expr(obj, strict))
          }
          MemberAssign(obj, _, rhs, _) => {
            work.push(Expr(rhs, strict))
            work.push(Expr(obj, strict))
          }
          ComputedAssign(obj, key, rhs, _) => {
            work.push(Expr(rhs, strict))
            work.push(Expr(key, strict))
            work.push(Expr(obj, strict))
          }
          SuperComputedAssign(key, rhs, _) => {
            work.push(Expr(rhs, strict))
            work.push(Expr(key, strict))
          }
          Ternary(cond, yes, no, _) => {
            work.push(Expr(no, strict))
            work.push(Expr(yes, strict))
            work.push(Expr(cond, strict))
          }
          Call(callee, args, _)
          | NewExpr(callee, args, _)
          | OptionalCall(callee, args, _) => {
            schedule_exprs_reverse(work, args, strict)
            work.push(Expr(callee, strict))
          }
          ObjectLit(props, _) =>
            for i = props.length() - 1; i >= 0; i = i - 1 {
              work.push(Expr(props[i].value, strict))
              work.push(Expr(props[i].key, strict))
            }
          ArrayLit(elements, _) | SuperCall(elements, _) =>
            schedule_exprs_reverse(work, elements, strict)
          TemplateLit(quasis, exprs, loc) => {
            schedule_exprs_reverse(work, exprs, strict)
            work.push(TemplateQuasis(quasis, loc))
          }
          DestructureAssign(pattern, rhs, _) => {
            work.push(Expr(rhs, strict))
            work.push(Pattern(pattern, strict, false))
          }
          TaggedTemplate(tag, _, exprs, _) => {
            schedule_exprs_reverse(work, exprs, strict)
            work.push(Expr(tag, strict))
          }
          Unary(_, inner, _)
          | Grouping(inner, _)
          | SpreadExpr(inner, _)
          | AwaitExpr(inner, _)
          | Member(inner, _, _)
          | OptionalMember(inner, _, _)
          | ChainMember(inner, _, _)
          | SuperComputedMember(inner, _)
          | SuperMemberAssign(_, inner, _) => work.push(Expr(inner, strict))
          YieldExpr(arg, _, _) =>
            match arg {
              Some(inner) => work.push(Expr(inner, strict))
              None => ()
            }
          BoolLit(_, _)
          | NullLit(_)
          | UndefinedLit(_)
          | ArrayHole(_)
          | ThisExpr(_)
          | RegexLit(_, _, _)
          | SuperMember(_, _)
          | NewTargetExpr(_)
          | WebCompatCallAssign(_, _, _)
          | PrivateIdent(_, _)
          | PrivateMember(_, _, _)
          | PrivateMemberAssign(_, _, _, _) => ()
        }
      Stmt(stmt, strict) =>
        match stmt {
          Block(inner, _) => {
            schedule_stmts_reverse(work, inner, strict)
            work.push(StmtListCheck(inner, true, !strict, false))
          }
          StmtList(inner, _) => schedule_stmts_reverse(work, inner, strict)
          ExprStmt(expr, _) | ThrowStmt(expr, _) | ExportDefaultDecl(expr, _) =>
            work.push(Expr(expr, strict))
          VarDecl(_, name, init, _) => {
            match init {
              Some(expr) => work.push(Expr(expr, strict))
              None => ()
            }
            if strict {
              @static_semantics.validate_strict_binding_name(name)
            }
          }
          DestructureDecl(_, pattern, init, _) => {
            work.push(Expr(init, strict))
            work.push(Pattern(pattern, strict, true))
          }
          IfStmt(cond, yes, no, _) => {
            match no {
              Some(stmt) => work.push(Stmt(stmt, strict))
              None => ()
            }
            work.push(Stmt(yes, strict))
            work.push(Expr(cond, strict))
          }
          WhileStmt(cond, body, _) => {
            work.push(Stmt(body, strict))
            work.push(Expr(cond, strict))
          }
          DoWhileStmt(body, cond, _) => {
            work.push(Expr(cond, strict))
            work.push(Stmt(body, strict))
          }
          ForStmt(init, cond, update, body, _) => {
            work.push(Stmt(body, strict))
            match update {
              Some(e) => work.push(Expr(e, strict))
              None => ()
            }
            match cond {
              Some(e) => work.push(Expr(e, strict))
              None => ()
            }
            match init {
              Some(s) => work.push(Stmt(s, strict))
              None => ()
            }
          }
          ForInStmt(kind, name, expr, body, _)
          | ForOfStmt(kind, name, expr, body, _)
          | AsyncForOfStmt(kind, name, expr, body, _) => {
            work.push(Stmt(body, strict))
            work.push(Expr(expr, strict))
            if kind is Some(_) {
              if strict {
                @static_semantics.validate_strict_binding_name(name)
              }
            } else {
              @static_semantics.validate_strict_assignment_target_name(
                strict, name,
              )
            }
          }
          ForInStmtPat(kind, pattern, expr, body, _)
          | ForOfStmtPat(kind, pattern, expr, body, _)
          | AsyncForOfStmtPat(kind, pattern, expr, body, _) => {
            work.push(Stmt(body, strict))
            work.push(Expr(expr, strict))
            work.push(Pattern(pattern, strict, kind is Some(_)))
          }
          ForInExpr(lhs, expr, body, _)
          | ForOfExpr(lhs, expr, body, _)
          | AsyncForOfExpr(lhs, expr, body, _) => {
            work.push(Stmt(body, strict))
            work.push(Expr(expr, strict))
            match lhs {
              Ident(name, _) =>
                @static_semantics.validate_strict_assignment_target_name(
                  strict, name,
                )
              _ => work.push(Expr(lhs, strict))
            }
          }
          LabeledStmt(_, inner, _) => work.push(Stmt(inner, strict))
          ReturnStmt(expr, _) =>
            match expr {
              Some(e) => work.push(Expr(e, strict))
              None => ()
            }
          SwitchStmt(discriminant, cases, _) => {
            for i = cases.length() - 1; i >= 0; i = i - 1 {
              schedule_stmts_reverse(work, cases[i].body, strict)
              match cases[i].condition {
                Some(expr) => work.push(Expr(expr, strict))
                None => ()
              }
            }
            work.push(
              StmtListCheck(
                flatten_case_block_statements(cases),
                true,
                !strict,
                false,
              ),
            )
            work.push(Expr(discriminant, strict))
          }
          TryCatchStmt(try_body, catch_param, catch_body, finally_body, _) => {
            match finally_body {
              Some(xs) => schedule_stmts_reverse(work, xs, strict)
              None => ()
            }
            match catch_body {
              Some(xs) => schedule_stmts_reverse(work, xs, strict)
              None => ()
            }
            match catch_param {
              Some(p) => work.push(Pattern(p, strict, true))
              None => ()
            }
            schedule_stmts_reverse(work, try_body, strict)
          }
          FuncDecl(_, _, body, _, _)
          | GeneratorDecl(_, _, body, _, _)
          | AsyncFuncDecl(_, _, body, _, _)
          | AsyncGeneratorDecl(_, _, body, _, _) =>
            schedule_function_body(work, None, body, strict)
          FuncDeclExt(_, params, _, body, _, _)
          | GeneratorDeclExt(_, params, _, body, _, _)
          | AsyncFuncDeclExt(_, params, _, body, _, _)
          | AsyncGeneratorDeclExt(_, params, _, body, _, _) =>
            schedule_function_body(work, Some(params), body, strict)
          ClassDecl(_, superclass, members, _, _) => {
            schedule_class_members_reverse(work, members)
            match superclass {
              Some(expr) => work.push(Expr(expr, true))
              None => ()
            }
          }
          WithStmt(obj, body, _) => {
            if strict {
              raise @errors.SyntaxError(
                message="Strict mode code may not include a with statement",
              )
            }
            work.push(Stmt(body, strict))
            work.push(Expr(obj, strict))
          }
          ImportDecl(_, _, _, _, form, loc) | ExportAllDecl(_, _, form, loc) =>
            validate_strict_lex_form(form, loc, strict)
          ExportNamedDecl(decl, _, _, form, loc) => {
            match decl {
              Some(stmt) => work.push(Stmt(stmt, strict))
              None => ()
            }
            validate_strict_lex_form(form, loc, strict)
          }
          BreakStmt(_, _) | ContinueStmt(_, _) => ()
        }
    }
  }
}

///|
pub fn Interpreter::validate_block_early_errors(
  _self : Interpreter,
  stmts : Array[@ast.Stmt],
  strict_context : Bool,
) -> Unit raise Error {
  validate_compiled_script_early_errors(stmts, strict_context)
}

///|
fn collect_eval_var_names(stmts : Array[@ast.Stmt]) -> Array[String] {
  @static_semantics.collect_var_declared_names(stmts)
}

///|
fn hoist_pattern(pattern : @ast.Pattern, env : Environment) -> Unit raise Error {
  for name in @static_semantics.bound_names(pattern) {
    if !env.bindings.contains(name) {
      env.def(name, Undefined, VarBinding)
    }
  }
}

///|
/// Read-only mirror of hoist_var_declarations_from_stmt — walks the same
/// VarScopedDeclarations tree and invokes on_name for every var-scoped binding
/// without creating any bindings. Does not recurse into function/class/generator/
/// async-function bodies (separate var scopes per ES §8.2.4).
fn walk_var_scoped_names(
  stmt : @ast.Stmt,
  on_name : (String) -> Unit raise Error,
) -> Unit raise Error {
  for
    name in @static_semantics.collect_var_declared_names(
      [stmt],
      include_funcs=false,
    ) {
    on_name(name)
  }
}

///|
fn hoist_var_declarations_from_stmt(
  stmt : @ast.Stmt,
  env : Environment,
) -> Unit raise Error {
  walk_var_scoped_names(stmt, name => {
    if !env.bindings.contains(name) {
      env.def(name, Undefined, VarBinding)
    }
  })
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
  names : @set.Set[String],
) -> Unit raise Error {
  match stmt {
    VarDecl(LetKind, name, _, _) | VarDecl(ConstKind, name, _, _) =>
      names.add(name)
    ClassDecl(name, _, _, _, _) => names.add(name)
    DestructureDecl(LetKind, pattern, _, _)
    | DestructureDecl(ConstKind, pattern, _, _) =>
      collect_pattern_lex_names(pattern, names)
    StmtList(inner_stmts, _) =>
      for inner in inner_stmts {
        add_stmt_lex_names(inner, names)
      }
    ExportNamedDecl(Some(decl), _, _, _, _) => add_stmt_lex_names(decl, names)
    _ => ()
  }
}

///|
/// Walk a pattern and record every `IdentPat` name into `names`. Used for
/// `let` / `const` destructuring declarations and for-loop heads.
fn collect_pattern_lex_names(
  pattern : @ast.Pattern,
  names : @set.Set[String],
) -> Unit {
  for name in @static_semantics.bound_names(pattern) {
    names.add(name)
  }
}

///|
/// Collect lexically-declared names (§8.2.10 TopLevelLexicallyDeclaredNames)
/// from a statement list — `let` / `const` / `class` at the given scope, with
/// no recursion into Block, function body, switch case, loop body, catch
/// block, or `with` body. Suitable for both eval top level (§B.3.3.3 skip
/// check) and for per-block lex frames pushed onto the AST walk stack.
fn collect_stmts_lex_names(
  stmts : Array[@ast.Stmt],
) -> @set.Set[String] raise Error {
  let names = @set.Set::default()
  for stmt in stmts {
    add_stmt_lex_names(stmt, names)
  }
  names
}

///|
/// Apply the GlobalDeclarationInstantiation CanDeclareGlobalFunction checks.
/// Both the AST-backed interpreter path and the prepared bytecode path use
/// this operation so global-object property semantics have one runtime owner.
fn check_global_function_declarations(
  interp : Interpreter,
  names : Array[String],
) -> Unit raise Error {
  match interp.global_this {
    Value::Object(data) => {
      let declared : @set.Set[String] = @set.Set::default()
      for name in names {
        if !declared.contains(name) {
          let definable = match ordinary_get_own_string_desc(data.bag, name) {
            None => data.extensible
            Some(desc) =>
              desc.configurable ||
              (!desc.is_accessor && desc.writable && desc.enumerable)
          }
          if !definable {
            raise @errors.TypeError(
              message="Cannot declare global function '\{name}': property is non-configurable",
            )
          }
          declared.add(name) |> ignore
        }
      }
    }
    _ => ()
  }
}

///|
/// Apply the GlobalDeclarationInstantiation CanDeclareGlobalVar checks.
/// Function names are excluded because a function declaration's property has
/// already been checked by `check_global_function_declarations`.
fn check_global_var_declarations(
  interp : Interpreter,
  function_names : Array[String],
  var_names : Array[String],
) -> Unit raise Error {
  match interp.global_this {
    Value::Object(data) => {
      let function_set : @set.Set[String] = @set.Set::default()
      for name in function_names {
        function_set.add(name)
      }
      for name in var_names {
        if !function_set.contains(name) {
          let definable = ordinary_get_own_string_desc(data.bag, name)
            is Some(_) ||
            data.extensible
          if !definable {
            raise @errors.TypeError(
              message="Cannot declare global var '\{name}': global object is non-extensible",
            )
          }
        }
      }
    }
    _ => ()
  }
}

///|
/// Collect the direct function declarations used by global declaration
/// instantiation. This is the AST-side lowering of the same names retained by
/// `CompiledScriptPreparation` for the bytecode path.
fn collect_global_function_names(stmts : Array[@ast.Stmt]) -> Array[String] {
  let names = []
  for stmt in stmts {
    match stmt {
      FuncDecl(name, _, _, _, _) => names.push(name)
      FuncDeclExt(name, _, _, _, _, _) => names.push(name)
      GeneratorDecl(name, _, _, _, _) => names.push(name)
      GeneratorDeclExt(name, _, _, _, _, _) => names.push(name)
      AsyncFuncDecl(name, _, _, _, _) => names.push(name)
      AsyncFuncDeclExt(name, _, _, _, _, _) => names.push(name)
      AsyncGeneratorDecl(name, _, _, _, _) => names.push(name)
      AsyncGeneratorDeclExt(name, _, _, _, _, _) => names.push(name)
      _ => ()
    }
  }
  names
}

///|
/// Collect the var-scoped names with the same static-semantics traversal used
/// by the AST-backed hoist implementation.
fn collect_global_var_names(stmts : Array[@ast.Stmt]) -> Array[String] {
  @static_semantics.collect_var_declared_names(stmts, include_funcs=false)
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
  top_lex : @set.Set[String],
  lex_stack : Array[@set.Set[String]],
  excluded? : @set.Set[String] = @set.Set::default(),
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
  top_lex : @set.Set[String],
  excluded? : @set.Set[String] = @set.Set::default(),
) -> Unit raise Error {
  let lex_stack : Array[@set.Set[String]] = []
  let work : Array[AnnexBWalkTask] = []
  schedule_annex_b_stmts_reverse(work, stmts, in_block=false)
  while work.pop() is Some(task) {
    match task {
      VisitAnnexBStmt(stmt, in_block) =>
        visit_eval_annex_b_stmt(
          interp,
          stmt,
          var_env,
          top_lex,
          lex_stack,
          work,
          in_block~,
          excluded~,
        )
      EnterAnnexBStmtList(inner_stmts) => {
        lex_stack.push(collect_stmts_lex_names(inner_stmts))
        work.push(LeaveAnnexBLexicalFrame)
        schedule_annex_b_stmts_reverse(work, inner_stmts, in_block=true)
      }
      EnterAnnexBCatch(catch_param, catch_body) => {
        let catch_frame = @set.Set::default()
        match catch_param {
          Some(IdentPat(_)) => ()
          Some(pattern) =>
            for name in @static_semantics.bound_names(pattern) {
              catch_frame.add(name)
            }
          None => ()
        }
        lex_stack.push(catch_frame)
        work.push(LeaveAnnexBLexicalFrame)
        work.push(EnterAnnexBStmtList(catch_body))
      }
      LeaveAnnexBLexicalFrame => {
        guard lex_stack.pop() is Some(_) else {
          fail("unbalanced Annex B lexical-frame continuation")
        }
      }
    }
  }
}

///|
priv enum AnnexBWalkTask {
  VisitAnnexBStmt(@ast.Stmt, Bool)
  EnterAnnexBStmtList(Array[@ast.Stmt])
  EnterAnnexBCatch(@ast.Pattern?, Array[@ast.Stmt])
  LeaveAnnexBLexicalFrame
}

///|
fn schedule_annex_b_stmts_reverse(
  work : Array[AnnexBWalkTask],
  stmts : Array[@ast.Stmt],
  in_block~ : Bool,
) -> Unit {
  for i = stmts.length() - 1; i >= 0; i = i - 1 {
    work.push(VisitAnnexBStmt(stmts[i], in_block))
  }
}

///|
fn schedule_annex_b_enclosed_body(
  work : Array[AnnexBWalkTask],
  lex_stack : Array[@set.Set[String]],
  body : @ast.Stmt,
  frame : @set.Set[String],
) -> Unit {
  lex_stack.push(frame)
  work.push(LeaveAnnexBLexicalFrame)
  work.push(VisitAnnexBStmt(body, true))
}

///|
fn visit_eval_annex_b_stmt(
  interp : Interpreter,
  stmt : @ast.Stmt,
  var_env : Environment,
  top_lex : @set.Set[String],
  lex_stack : Array[@set.Set[String]],
  work : Array[AnnexBWalkTask],
  in_block~ : Bool,
  excluded~ : @set.Set[String],
) -> Unit raise Error {
  match stmt {
    FuncDecl(name, _, _, _, _) | FuncDeclExt(name, _, _, _, _, _) =>
      if in_block &&
        !annex_b_candidate_conflicts(name, top_lex, lex_stack, excluded~) {
        tag_annex_b_hoisted(interp, var_env, name)
      }
    Block(inner_stmts, _) => work.push(EnterAnnexBStmtList(inner_stmts))
    StmtList(inner_stmts, _) =>
      schedule_annex_b_stmts_reverse(work, inner_stmts, in_block~)
    // §B.3.4: `if (expr) FunctionDeclaration` is treated as if the body
    // were `{ FunctionDeclaration }`. Each branch is a block context for
    // Annex B, so FuncDecls under IfStmt ARE candidates even at the eval
    // top level. If the branch is itself a Block, the Block arm pushes its
    // own frame — no double-pushing.
    IfStmt(_, then_branch, else_branch, _) => {
      match else_branch {
        Some(else_stmt) => work.push(VisitAnnexBStmt(else_stmt, true))
        None => ()
      }
      work.push(VisitAnnexBStmt(then_branch, true))
    }
    WhileStmt(_, body, _) => work.push(VisitAnnexBStmt(body, true))
    DoWhileStmt(body, _, _) => work.push(VisitAnnexBStmt(body, true))
    // §14.7.4: `for (let/const …; ; ) body` makes the init's lex names visible
    // for the body's Annex-B candidate check.
    ForStmt(init, _, _, body, _) =>
      schedule_annex_b_enclosed_body(
        work,
        lex_stack,
        body,
        for_init_lex_names(init),
      )
    ForInStmt(kind, name, _, body, _) => {
      let frame = @set.Set::default()
      if kind is (Some(LetKind) | Some(ConstKind)) {
        frame.add(name)
      }
      schedule_annex_b_enclosed_body(work, lex_stack, body, frame)
    }
    ForOfStmt(kind, name, _, body, _)
    | AsyncForOfStmt(kind, name, _, body, _) => {
      let frame = @set.Set::default()
      if kind is (Some(LetKind) | Some(ConstKind)) {
        frame.add(name)
      }
      schedule_annex_b_enclosed_body(work, lex_stack, body, frame)
    }
    ForInStmtPat(kind, pattern, _, body, _) => {
      let frame = @set.Set::default()
      if kind is (Some(LetKind) | Some(ConstKind)) {
        collect_pattern_lex_names(pattern, frame)
      }
      schedule_annex_b_enclosed_body(work, lex_stack, body, frame)
    }
    ForOfStmtPat(kind, pattern, _, body, _)
    | AsyncForOfStmtPat(kind, pattern, _, body, _) => {
      let frame = @set.Set::default()
      if kind is (Some(LetKind) | Some(ConstKind)) {
        collect_pattern_lex_names(pattern, frame)
      }
      schedule_annex_b_enclosed_body(work, lex_stack, body, frame)
    }
    ForInExpr(_, _, body, _) => work.push(VisitAnnexBStmt(body, true))
    ForOfExpr(_, _, body, _) | AsyncForOfExpr(_, _, body, _) =>
      work.push(VisitAnnexBStmt(body, true))
    // §B.3.3 + §14.13: a `label:`-wrapped FuncDecl is an Annex B candidate
    // just like a plain block FuncDecl. Mirror the IfStmt treatment — the
    // inner is a block context, so pass `in_block=true`.
    LabeledStmt(_, inner, _) => work.push(VisitAnnexBStmt(inner, true))
    // §14.12.3: all case clauses share one lex scope. Frame excludes
    // FuncDecls for the same reason `collect_stmts_lex_names` does — a
    // candidate `function F` in one case must not self-conflict. Duplicate
    // lex declarations across cases are caught by the early-error validator.
    SwitchStmt(_, cases, _) => {
      let frame = @set.Set::default()
      for case_ in cases {
        for inner in case_.body {
          add_stmt_lex_names(inner, frame)
        }
      }
      lex_stack.push(frame)
      work.push(LeaveAnnexBLexicalFrame)
      for case_index = cases.length() - 1
          case_index >= 0
          case_index = case_index - 1 {
        schedule_annex_b_stmts_reverse(
          work,
          cases[case_index].body,
          in_block=true,
        )
      }
    }
    // §B.3.5 splits catch parameters in two: a simple BindingIdentifier
    // `catch (f) { var f; }` is exempt and lets `f` flow through to the
    // surrounding var scope, but a destructuring pattern like
    // `catch ({ f }) { ... }` does NOT get the exemption — replacing the
    // candidate `function f(){}` with `var f` would be a §B.3.5 SyntaxError,
    // so §B.3.3.3 step 2.c.i requires we skip the extension. Push the
    // catch's bound names as a lex frame around the catch body ONLY when
    // the parameter is destructuring; an IdentPat catch param stays
    // transparent. try-body and finally-body are always unaffected — only
    // catch-body inherits the parameter binding.
    TryCatchStmt(try_body, catch_param, catch_body, finally_body, _) => {
      match finally_body {
        Some(finally_stmts) => work.push(EnterAnnexBStmtList(finally_stmts))
        None => ()
      }
      match catch_body {
        Some(catch_stmts) =>
          work.push(EnterAnnexBCatch(catch_param, catch_stmts))
        None => ()
      }
      work.push(EnterAnnexBStmtList(try_body))
    }
    WithStmt(_, body, _) =>
      // Object env record — no lex frame pushed.
      work.push(VisitAnnexBStmt(body, true))
    ExportNamedDecl(Some(decl), _, _, _, _) =>
      work.push(VisitAnnexBStmt(decl, in_block))
    // Function / class bodies: do NOT traverse. They have their own B.3.3
    // hoist on call (§B.3.2.1), operating in a fresh scope.
    _ => ()
  }
}

///|
/// Extract lex (let/const) names introduced by a for-loop init. An init of
/// `StmtList(inner, _)` is the comma-separated `for (let a=1, b=2; …)` shape
/// — unwrap it one level so each inner declaration contributes.
fn for_init_lex_names(init : @ast.Stmt?) -> @set.Set[String] raise Error {
  let names = @set.Set::default()
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
  // §15.1.11 GlobalDeclarationInstantiation pre-check: verify all declarations
  // are definable before creating any bindings (spec steps 9-12). This ensures
  // TypeError is thrown atomically with no partial binding creation.
  if is_global {
    let function_names = collect_global_function_names(stmts)
    check_global_function_declarations(_self, function_names)
    check_global_var_declarations(
      _self,
      function_names,
      collect_global_var_names(stmts),
    )
  }
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
      FuncDecl(name, params, body, loc, source_text) => {
        validate_function_signature(strict, Some(name), params, body)
        let func_val = _self.materialize_function(
          FunctionMaterializationRequest(
            form=FunctionDeclaration,
            site=loc,
            name=Some(name),
            parameters=SimpleFunctionParameters(params),
            body~,
            closure=env,
            strict=is_function_strict(strict, body),
            source_text~,
          ),
        )
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
      FuncDeclExt(name, params, rest_param, body, loc, source_text) => {
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_val = _self.materialize_function(
          FunctionMaterializationRequest(
            form=FunctionDeclaration,
            site=loc,
            name=Some(name),
            parameters=ExtendedFunctionParameters(params, rest_param),
            body~,
            closure=env,
            strict=is_function_strict(strict, body),
            source_text~,
          ),
        )
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
      GeneratorDecl(name, params, body, _, source_text) => {
        validate_function_signature(strict, Some(name), params, body)
        let gen_func = _self.make_generator_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
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
      GeneratorDeclExt(name, params, rest_param, body, _, source_text) => {
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
          source_text~,
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
      AsyncFuncDecl(name, params, body, _, source_text) => {
        validate_function_signature(strict, Some(name), params, body)
        let async_func = _self.make_async_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        if env.bindings.contains(name) {
          env.assign(name, async_func)
        } else {
          env.def(name, async_func, VarBinding)
        }
      }
      AsyncFuncDeclExt(name, params, rest_param, body, _, source_text) => {
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
          source_text~,
        )
        if env.bindings.contains(name) {
          env.assign(name, async_func)
        } else {
          env.def(name, async_func, VarBinding)
        }
      }
      AsyncGeneratorDecl(name, params, body, _, source_text) => {
        validate_function_signature(strict, Some(name), params, body)
        let gen_func = _self.make_async_generator_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        if env.bindings.contains(name) {
          env.assign(name, gen_func)
        } else {
          env.def(name, gen_func, VarBinding)
        }
      }
      AsyncGeneratorDeclExt(name, params, rest_param, body, _, source_text) => {
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
          source_text~,
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
      ExportNamedDecl(Some(decl), _, _, _, _) => {
        let inner_stmts : Array[@ast.Stmt] = [decl]
        _self.hoist_declarations(inner_stmts, env, strict~)
      }
      // export default function name() {} - hoist the named function
      ExportDefaultDecl(FuncExpr(Some(name), params, body, loc, source_text), _) => {
        validate_function_signature(strict, Some(name), params, body)
        let func_val = _self.materialize_function(
          FunctionMaterializationRequest(
            form=FunctionDeclaration,
            site=loc,
            name=Some(name),
            parameters=SimpleFunctionParameters(params),
            body~,
            closure=env,
            strict=is_function_strict(strict, body),
            source_text~,
          ),
        )
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
        }
      }
      ExportDefaultDecl(
        FuncExprExt(Some(name), params, rest_param, body, loc, source_text),
        _
      ) => {
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_val = _self.materialize_function(
          FunctionMaterializationRequest(
            form=FunctionDeclaration,
            site=loc,
            name=Some(name),
            parameters=ExtendedFunctionParameters(params, rest_param),
            body~,
            closure=env,
            strict=is_function_strict(strict, body),
            source_text~,
          ),
        )
        if env.bindings.contains(name) {
          env.assign(name, func_val)
        } else {
          env.def(name, func_val, VarBinding)
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
    let excluded = @set.Set::default()
    // In the split (§10.2.11) case, param/"arguments" bindings live on
    // `param_source`, not `env` (= body_env). Fall back to `env` when no
    // split (scripts/modules/non-Ext single-env paths).
    let scan_env = match param_source {
      Some(p) => p
      None => env
    }
    for name, binding in scan_env.bindings {
      if binding.is_parameter {
        excluded.add(name)
      }
    }
    match scan_env.bindings.get("arguments") {
      Some(b) => if b.kind == VarBinding { excluded.add("arguments") }
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
  let work : Array[@ast.Stmt] = []
  stmts.rev_each(stmt => work.push(stmt))
  while work.length() > 0 {
    let stmt = work.pop().unwrap()
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
      StmtList(inner_stmts, _) =>
        inner_stmts.rev_each(inner => work.push(inner))
      // Class declarations have TDZ (similar to let)
      ClassDecl(name, _, _, _, _) =>
        if !env.bindings.contains(name) {
          env.def_tdz(name, LetBinding)
        }
      // Export with declaration: hoist let/const inner declarations with TDZ
      ExportNamedDecl(Some(decl), _, _, _, _) => work.push(decl)
      // A named default class contributes a module-local lexical binding.
      ExportDefaultDecl(expr, _) =>
        match (module_default_export_binding(expr), expr) {
          (LocalDefaultBinding(name), ClassExpr(_, _, _, _, _)) =>
            if !env.bindings.contains(name) {
              env.def_tdz(name, LetBinding)
            }
          _ => ()
        }
      _ => ()
    }
  }
}

///|
fn ensure_block_function_binding(
  env : Environment,
  name : String,
) -> Unit raise Error {
  if !env.bindings.contains(name) {
    env.def_tdz(name, LetBinding)
  }
}

///|
fn initialize_block_function_binding(
  env : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  match env.bindings.get(name) {
    Some(binding) =>
      if binding.initialized {
        env.assign(name, value)
      } else {
        env.initialize(name, value)
      }
    None => abort("unreachable: block function binding was not created")
  }
}

///|
/// Instantiate the lexical declarations owned by a Block or CaseBlock.
/// Function declarations are initialized before statement execution and close
/// over the block environment, per BlockDeclarationInstantiation.
fn Interpreter::instantiate_block_declarations(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
  strict : Bool,
) -> Unit raise Error {
  hoist_block_tdz(stmts, env)
  for stmt in stmts {
    match stmt {
      FuncDecl(name, params, body, loc, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature(strict, Some(name), params, body)
        let func_val = self.materialize_function(
          FunctionMaterializationRequest(
            form=FunctionDeclaration,
            site=loc,
            name=Some(name),
            parameters=SimpleFunctionParameters(params),
            body~,
            closure=env,
            strict=is_function_strict(strict, body),
            source_text~,
          ),
        )
        initialize_block_function_binding(env, name, func_val)
      }
      FuncDeclExt(name, params, rest_param, body, loc, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_val = self.materialize_function(
          FunctionMaterializationRequest(
            form=FunctionDeclaration,
            site=loc,
            name=Some(name),
            parameters=ExtendedFunctionParameters(params, rest_param),
            body~,
            closure=env,
            strict=is_function_strict(strict, body),
            source_text~,
          ),
        )
        initialize_block_function_binding(env, name, func_val)
      }
      GeneratorDecl(name, params, body, _, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature(strict, Some(name), params, body)
        let func_val = self.make_generator_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        initialize_block_function_binding(env, name, func_val)
      }
      GeneratorDeclExt(name, params, rest_param, body, _, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_val = self.make_generator_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        initialize_block_function_binding(env, name, func_val)
      }
      AsyncFuncDecl(name, params, body, _, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature(strict, Some(name), params, body)
        let func_val = self.make_async_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        initialize_block_function_binding(env, name, func_val)
      }
      AsyncFuncDeclExt(name, params, rest_param, body, _, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_val = self.make_async_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        initialize_block_function_binding(env, name, func_val)
      }
      AsyncGeneratorDecl(name, params, body, _, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature(strict, Some(name), params, body)
        let func_val = self.make_async_generator_function(
          Some(name),
          params,
          None,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        initialize_block_function_binding(env, name, func_val)
      }
      AsyncGeneratorDeclExt(name, params, rest_param, body, _, source_text) => {
        ensure_block_function_binding(env, name)
        validate_function_signature_ext(
          strict,
          Some(name),
          params,
          rest_param,
          body,
        )
        let func_val = self.make_async_generator_function_ext(
          Some(name),
          params,
          rest_param,
          body,
          is_function_strict(strict, body),
          env,
          source_text~,
        )
        initialize_block_function_binding(env, name, func_val)
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
  for name in @static_semantics.bound_names(pattern) {
    if !env.bindings.contains(name) {
      env.def_tdz(name, kind)
    }
  }
}

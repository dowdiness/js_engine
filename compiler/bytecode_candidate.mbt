///|
// Candidate preparation is a compiler-only, pure envelope.  It records the
// source tree and the independently classified bytecode child without
// retaining any runtime callable or execution state.
priv enum CandidateFunctionLowering {
  CandidateLowered
  CandidateLoweringUnsupported(BytecodeUnsupported)
}

///|
priv enum CandidateTreeWalkerReason {
  CandidateLoweringUnsupported(BytecodeUnsupported)
  CandidateActivationUnsupported(BytecodeActivationUnsupported)
}

///|
priv enum CandidateSelection {
  UseBytecode(BytecodeActivationDisposition)
  UseTreeWalker(CandidateTreeWalkerReason)
}

///|
priv enum CandidateFunctionSignature {
  CandidateSimpleSignature(Array[String])
  CandidateExtendedSignature(Array[@ast.Param], String?)
}

///|
priv struct CandidateIdentityPlan {
  source_point_owner : SourcePointOwnerId
  children : Array[CandidateIdentityPlan]
}

///|
priv struct CandidateFunctionPlan {
  name : String?
  signature : CandidateFunctionSignature
  params : Array[String]
  rest_param : String?
  body : Array[@ast.Stmt]
  source_text : String?
  is_method : Bool
  consumer_form : BytecodeFunctionConsumerForm?
  enclosing_strict : Bool
  activation_kind : BytecodeActivationKind
  lowering : CandidateFunctionLowering
  children : Array[CandidateFunctionPlan]
  identity_plan : CandidateIdentityPlan?
}

///|
priv struct CandidateFunction {
  name : String?
  signature : CandidateFunctionSignature
  body : Array[@ast.Stmt]
  source_text : String?
  is_method : Bool
  consumer_form : BytecodeFunctionConsumerForm?
  source_identity : BytecodeSourceIdentity
  selection : CandidateSelection
  bytecode : VerifiedBytecodeFunction?
  children : Array[CandidateFunction]
}

///|
priv struct CandidateProgram {
  program_identity : Ref[Unit]
  root : CandidateFunction
}

///|
fn candidate_function_strict(
  enclosing_strict : Bool,
  body : Array[@ast.Stmt],
) -> Bool {
  enclosing_strict || @static_semantics.has_use_strict(body)
}

///|
fn candidate_unsupported(
  reason : BytecodeUnsupportedReason,
  loc : @token.Loc,
) -> CandidateFunctionLowering {
  CandidateLoweringUnsupported(BytecodeUnsupported(reason, loc))
}

///|
fn candidate_lower_function(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
  rest_param : String?,
  source_text : String?,
  enclosing_strict : Bool,
  is_method : Bool,
  activation_kind : BytecodeActivationKind,
) -> CandidateFunctionLowering raise Error {
  let allocator = new_source_point_owner_allocator()
  try {
    let _ = compile_bytecode_function(
      name,
      params,
      body,
      rest_param,
      allocator,
      source_text~,
      use_local_slots=true,
      source_unit=SourceUnitHandle(0),
      enclosing_strict~,
      is_method~,
      activation_kind~,
      candidate_mode=true,
    )
    CandidateLowered
  } catch {
    BytecodeUnsupportedSignal(unsupported) =>
      CandidateLoweringUnsupported(unsupported)
    error => raise error
  }
}

///|
fn candidate_normalize_ext_params(
  params : Array[@ast.Param],
  rest_param : String?,
  loc : @token.Loc,
) -> Result[(Array[String], String?), BytecodeUnsupported] raise Error {
  try {
    Ok(simple_ext_param_names_with_rest(params, rest_param, loc))
  } catch {
    BytecodeUnsupportedSignal(unsupported) => Err(unsupported)
    error => raise error
  }
}

///|
fn candidate_prepare_plan(
  name : String?,
  signature : CandidateFunctionSignature,
  params : Result[(Array[String], String?), BytecodeUnsupported],
  body : Array[@ast.Stmt],
  source_text : String?,
  is_method : Bool,
  consumer_form : BytecodeFunctionConsumerForm?,
  enclosing_strict : Bool,
  activation_kind : BytecodeActivationKind,
  children : Array[CandidateFunctionPlan],
  unsupported_kind : CandidateFunctionLowering?,
) -> CandidateFunctionPlan raise Error {
  let strict = candidate_function_strict(enclosing_strict, body)
  let lowering = match unsupported_kind {
    Some(outcome) => outcome
    None => match params {
      Ok((simple_params, simple_rest)) => candidate_lower_function(
        name,
        simple_params,
        body,
        simple_rest,
        source_text,
        strict,
        is_method,
        activation_kind,
      )
      Err(unsupported) => CandidateLoweringUnsupported(unsupported)
    }
  }
  let (simple_params, simple_rest) = match params {
    Ok((simple_params, simple_rest)) => (simple_params, simple_rest)
    Err(_) => ([], None)
  }
  {
    name,
    signature,
    params: simple_params,
    rest_param: simple_rest,
    body: body.copy(),
    source_text,
    is_method,
    consumer_form,
    enclosing_strict: strict,
    activation_kind,
    lowering,
    children,
    identity_plan: None,
  }
}

///|
fn candidate_prepare_simple_plan(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
  source_text : String?,
  is_method : Bool,
  consumer_form : BytecodeFunctionConsumerForm?,
  enclosing_strict : Bool,
  children : Array[CandidateFunctionPlan],
) -> CandidateFunctionPlan raise Error {
  candidate_prepare_plan(
    name,
    CandidateSimpleSignature(params.copy()),
    Ok((params.copy(), None)),
    body,
    source_text,
    is_method,
    consumer_form,
    enclosing_strict,
    FunctionActivation,
    children,
    None,
  )
}

///|
fn candidate_prepare_ext_plan(
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  loc : @token.Loc,
  source_text : String?,
  is_method : Bool,
  consumer_form : BytecodeFunctionConsumerForm?,
  enclosing_strict : Bool,
  children : Array[CandidateFunctionPlan],
) -> CandidateFunctionPlan raise Error {
  let normalized = candidate_normalize_ext_params(params, rest_param, loc)
  candidate_prepare_plan(
    name,
    CandidateExtendedSignature(params.copy(), rest_param),
    normalized,
    body,
    source_text,
    is_method,
    consumer_form,
    enclosing_strict,
    FunctionActivation,
    children,
    None,
  )
}

///|
fn candidate_prepare_unsupported_plan(
  name : String?,
  signature : CandidateFunctionSignature,
  body : Array[@ast.Stmt],
  source_text : String?,
  loc : @token.Loc,
  reason : BytecodeUnsupportedReason,
  consumer_form : BytecodeFunctionConsumerForm?,
  enclosing_strict : Bool,
  children : Array[CandidateFunctionPlan],
) -> CandidateFunctionPlan raise Error {
  candidate_prepare_plan(
    name,
    signature,
    Ok(([], None)),
    body,
    source_text,
    false,
    consumer_form,
    enclosing_strict,
    FunctionActivation,
    children,
    Some(candidate_unsupported(reason, loc)),
  )
}

///|
fn candidate_append_plans(
  target : Array[CandidateFunctionPlan],
  source : Array[CandidateFunctionPlan],
) -> Unit {
  for plan in source { target.push(plan) }
}

///|
fn candidate_collect_pattern(
  pattern : @ast.Pattern,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  match pattern {
    IdentPat(_) => ()
    ArrayPat(elements, rest) => {
      for element in elements {
        match element {
          Some(element) => candidate_collect_pattern(element, enclosing_strict, plans)
          None => ()
        }
      }
      match rest {
        Some(rest) => candidate_collect_pattern(rest, enclosing_strict, plans)
        None => ()
      }
    }
    ObjectPat(properties, rest) => {
      for property in properties {
        match property.computed_key {
          Some(key) => candidate_collect_expr(key, enclosing_strict, plans)
          None => ()
        }
        candidate_collect_pattern(property.value, enclosing_strict, plans)
        match property.default_val {
          Some(default_val) => candidate_collect_expr(default_val, enclosing_strict, plans)
          None => ()
        }
      }
      match rest {
        Some(rest) => candidate_collect_pattern(rest, enclosing_strict, plans)
        None => ()
      }
    }
    DefaultPat(inner, default_val) => {
      candidate_collect_pattern(inner, enclosing_strict, plans)
      candidate_collect_expr(default_val, enclosing_strict, plans)
    }
    AssignTarget(expr) => candidate_collect_expr(expr, enclosing_strict, plans)
  }
}

///|
fn candidate_collect_params(
  params : Array[@ast.Param],
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  for param in params {
    match param.default_val {
      Some(default_val) => candidate_collect_expr(default_val, enclosing_strict, plans)
      None => ()
    }
    match param.pattern {
      Some(pattern) => candidate_collect_pattern(pattern, enclosing_strict, plans)
      None => ()
    }
  }
}

///|
fn candidate_collect_function_body(
  body : Array[@ast.Stmt],
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  candidate_collect_stmts(body, enclosing_strict, plans)
}

///|
fn candidate_collect_function_expr(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
  loc : @token.Loc,
  source_text : String?,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_function_body(body, enclosing_strict, children)
  plans.push(candidate_prepare_simple_plan(
    name,
    params,
    body,
    source_text,
    false,
    Some(consumer_form),
    enclosing_strict,
    children,
  ))
}

///|
fn candidate_collect_function_expr_ext(
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  loc : @token.Loc,
  source_text : String?,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_params(params, enclosing_strict, children)
  candidate_collect_function_body(body, enclosing_strict, children)
  plans.push(candidate_prepare_ext_plan(
    name,
    params,
    rest_param,
    body,
    loc,
    source_text,
    false,
    Some(consumer_form),
    enclosing_strict,
    children,
  ))
}

///|
fn candidate_collect_method_expr(
  expr : @ast.Expr,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  match expr {
    FuncExpr(name, params, body, loc, source_text) =>
      candidate_collect_function_expr(
        name,
        params,
        body,
        loc,
        source_text,
        consumer_form,
        enclosing_strict,
        plans,
      )
    FuncExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_expr_ext(
        name,
        params,
        rest_param,
        body,
        loc,
        source_text,
        consumer_form,
        enclosing_strict,
        plans,
      )
    GeneratorExpr(name, params, body, loc, source_text) =>
      candidate_collect_unsupported_function(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        GeneratorExpression,
        consumer_form,
        enclosing_strict,
        plans,
      )
    GeneratorExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_unsupported_function_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        GeneratorExpression,
        consumer_form,
        enclosing_strict,
        plans,
      )
    AsyncFuncExpr(name, params, body, loc, source_text) =>
      candidate_collect_unsupported_function(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncFunctionExpression,
        consumer_form,
        enclosing_strict,
        plans,
      )
    AsyncFuncExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_unsupported_function_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        AsyncFunctionExpression,
        consumer_form,
        enclosing_strict,
        plans,
      )
    _ => candidate_collect_expr(expr, enclosing_strict, plans)
  }
}

///|
fn candidate_collect_unsupported_function(
  name : String?,
  signature : CandidateFunctionSignature,
  body : Array[@ast.Stmt],
  source_text : String?,
  loc : @token.Loc,
  reason : BytecodeUnsupportedReason,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_function_body(body, enclosing_strict, children)
  match signature {
    CandidateSimpleSignature(_) => ()
    CandidateExtendedSignature(params, _) =>
      candidate_collect_params(params, enclosing_strict, children)
  }
  plans.push(candidate_prepare_unsupported_plan(
    name,
    signature,
    body,
    source_text,
    loc,
    reason,
    Some(consumer_form),
    enclosing_strict,
    children,
  ))
}

///|
fn candidate_collect_unsupported_function_ext(
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  source_text : String?,
  loc : @token.Loc,
  reason : BytecodeUnsupportedReason,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  candidate_collect_unsupported_function(
    name,
    CandidateExtendedSignature(params.copy(), rest_param),
    body,
    source_text,
    loc,
    reason,
    consumer_form,
    enclosing_strict,
    plans,
  )
}

///|
fn candidate_collect_class_member(
  member : @ast.ClassMember,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  match member {
    Method(method) => {
      candidate_collect_expr(method.key, enclosing_strict, plans)
      let consumer_form = if method.computed {
        ComputedMethodFunctionConsumer
      } else {
        MethodFunctionConsumer
      }
      candidate_collect_method_expr(
        method.value,
        consumer_form,
        enclosing_strict,
        plans,
      )
    }
    Field(field) => {
      candidate_collect_expr(field.key, enclosing_strict, plans)
      match field.initializer {
        Some(initializer) => candidate_collect_expr(initializer, enclosing_strict, plans)
        None => ()
      }
    }
    StaticBlock(stmts, _) => candidate_collect_stmts(stmts, enclosing_strict, plans)
  }
}

///|
fn candidate_collect_property(
  property : @ast.Property,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  candidate_collect_expr(property.key, enclosing_strict, plans)
  if property.is_method {
    let consumer_form = if property.computed {
      ComputedMethodFunctionConsumer
    } else {
      MethodFunctionConsumer
    }
    candidate_collect_method_expr(
      property.value,
      consumer_form,
      enclosing_strict,
      plans,
    )
  } else {
    candidate_collect_expr(property.value, enclosing_strict, plans)
  }
}

///|
fn candidate_collect_expr(
  expr : @ast.Expr,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  match expr {
    FuncExpr(name, params, body, loc, source_text) =>
      candidate_collect_function_expr(
        name,
        params,
        body,
        loc,
        source_text,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    FuncExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_expr_ext(
        name,
        params,
        rest_param,
        body,
        loc,
        source_text,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    ArrowFunc(params, body, loc, source_text) =>
      candidate_collect_function_expr(
        None,
        params,
        body,
        loc,
        source_text,
        ArrowFunctionConsumer,
        enclosing_strict,
        plans,
      )
    ArrowFuncExt(params, rest_param, body, loc, source_text) =>
      candidate_collect_function_expr_ext(
        None,
        params,
        rest_param,
        body,
        loc,
        source_text,
        ArrowFunctionConsumer,
        enclosing_strict,
        plans,
      )
    GeneratorExpr(name, params, body, loc, source_text) =>
      candidate_collect_unsupported_function(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        GeneratorExpression,
        FunctionConsumer,
        enclosing_strict,
        plans,
      )
    GeneratorExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_unsupported_function_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        GeneratorExpression,
        FunctionConsumer,
        enclosing_strict,
        plans,
      )
    AsyncFuncExpr(name, params, body, loc, source_text) =>
      candidate_collect_unsupported_function(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncFunctionExpression,
        FunctionConsumer,
        enclosing_strict,
        plans,
      )
    AsyncFuncExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_unsupported_function_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        AsyncFunctionExpression,
        FunctionConsumer,
        enclosing_strict,
        plans,
      )
    AsyncArrowFunc(params, body, loc, source_text) =>
      candidate_collect_unsupported_function(
        None,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncArrowFunction,
        ArrowFunctionConsumer,
        enclosing_strict,
        plans,
      )
    AsyncArrowFuncExt(params, rest_param, body, loc, source_text) =>
      candidate_collect_unsupported_function_ext(
        None,
        params,
        rest_param,
        body,
        source_text,
        loc,
        AsyncArrowFunction,
        ArrowFunctionConsumer,
        enclosing_strict,
        plans,
      )
    AsyncGeneratorExpr(name, params, body, loc, source_text) =>
      candidate_collect_unsupported_function(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncGeneratorExpression,
        FunctionConsumer,
        enclosing_strict,
        plans,
      )
    AsyncGeneratorExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_unsupported_function_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        AsyncGeneratorExpression,
        FunctionConsumer,
        enclosing_strict,
        plans,
      )
    ObjectLit(properties, _) => {
      for property in properties {
        candidate_collect_property(property, enclosing_strict, plans)
      }
    }
    ClassExpr(_, superclass, members, _, _) => {
      match superclass {
        Some(superclass) => candidate_collect_expr(superclass, enclosing_strict, plans)
        None => ()
      }
      for member in members {
        candidate_collect_class_member(member, enclosing_strict, plans)
      }
    }
    DestructureAssign(pattern, value, _) => {
      candidate_collect_pattern(pattern, enclosing_strict, plans)
      candidate_collect_expr(value, enclosing_strict, plans)
    }
    _ => {
      let mut failure : Error? = None
      let _ = @ast.expr_immediate_children_any(expr, child => {
        match failure {
          Some(_) => ()
          None => try {
            candidate_collect_expr(child, enclosing_strict, plans)
          } catch {
            error => failure = Some(error)
          }
        }
        false
      })
      match failure {
        Some(error) => raise error
        None => ()
      }
    }
  }
}

///|
fn candidate_collect_switch_cases(
  cases : Array[@ast.SwitchCase],
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  for case in cases {
    match case.condition {
      Some(condition) => candidate_collect_expr(condition, enclosing_strict, plans)
      None => ()
    }
    candidate_collect_stmts(case.body, enclosing_strict, plans)
  }
}

///|
fn candidate_collect_stmt(
  stmt : @ast.Stmt,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  match stmt {
    ExprStmt(expr, _) => candidate_collect_expr(expr, enclosing_strict, plans)
    VarDecl(_, _, init, _) => match init {
      Some(init) => candidate_collect_expr(init, enclosing_strict, plans)
      None => ()
    }
    Block(stmts, _) | StmtList(stmts, _) =>
      candidate_collect_stmts(stmts, enclosing_strict, plans)
    IfStmt(condition, then_branch, else_branch, _) => {
      candidate_collect_expr(condition, enclosing_strict, plans)
      candidate_collect_stmt(then_branch, enclosing_strict, plans)
      match else_branch {
        Some(else_branch) => candidate_collect_stmt(else_branch, enclosing_strict, plans)
        None => ()
      }
    }
    WhileStmt(condition, body, _) => {
      candidate_collect_expr(condition, enclosing_strict, plans)
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    ForStmt(init, condition, update, body, _) => {
      match init {
        Some(init) => candidate_collect_stmt(init, enclosing_strict, plans)
        None => ()
      }
      match condition {
        Some(condition) => candidate_collect_expr(condition, enclosing_strict, plans)
        None => ()
      }
      match update {
        Some(update) => candidate_collect_expr(update, enclosing_strict, plans)
        None => ()
      }
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    FuncDecl(name, params, body, _, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_simple_plan(
        Some(name),
        params,
        body,
        source_text,
        false,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    FuncDeclExt(name, params, rest_param, body, loc, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, enclosing_strict, children)
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_ext_plan(
        Some(name),
        params,
        rest_param,
        body,
        loc,
        source_text,
        false,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    ReturnStmt(expr, _) => match expr {
      Some(expr) => candidate_collect_expr(expr, enclosing_strict, plans)
      None => ()
    }
    ThrowStmt(expr, _) => candidate_collect_expr(expr, enclosing_strict, plans)
    BreakStmt(_, _) | ContinueStmt(_, _) => ()
    TryCatchStmt(try_body, param, catch_body, finally_body, _) => {
      candidate_collect_stmts(try_body, enclosing_strict, plans)
      match param {
        Some(param) => candidate_collect_pattern(param, enclosing_strict, plans)
        None => ()
      }
      match catch_body {
        Some(catch_body) => candidate_collect_stmts(catch_body, enclosing_strict, plans)
        None => ()
      }
      match finally_body {
        Some(finally_body) => candidate_collect_stmts(finally_body, enclosing_strict, plans)
        None => ()
      }
    }
    SwitchStmt(discriminant, cases, _) => {
      candidate_collect_expr(discriminant, enclosing_strict, plans)
      candidate_collect_switch_cases(cases, enclosing_strict, plans)
    }
    DoWhileStmt(body, condition, _) => {
      candidate_collect_stmt(body, enclosing_strict, plans)
      candidate_collect_expr(condition, enclosing_strict, plans)
    }
    ForInStmt(_, _, obj_expr, body, _)
    | ForOfStmt(_, _, obj_expr, body, _)
    | AsyncForOfStmt(_, _, obj_expr, body, _) => {
      candidate_collect_expr(obj_expr, enclosing_strict, plans)
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    ForInStmtPat(_, pattern, obj_expr, body, _)
    | ForOfStmtPat(_, pattern, obj_expr, body, _)
    | AsyncForOfStmtPat(_, pattern, obj_expr, body, _) => {
      candidate_collect_pattern(pattern, enclosing_strict, plans)
      candidate_collect_expr(obj_expr, enclosing_strict, plans)
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    ForInExpr(target, obj_expr, body, _)
    | ForOfExpr(target, obj_expr, body, _)
    | AsyncForOfExpr(target, obj_expr, body, _) => {
      candidate_collect_expr(target, enclosing_strict, plans)
      candidate_collect_expr(obj_expr, enclosing_strict, plans)
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    DestructureDecl(_, pattern, value, _) => {
      candidate_collect_pattern(pattern, enclosing_strict, plans)
      candidate_collect_expr(value, enclosing_strict, plans)
    }
    LabeledStmt(_, body, _) =>
      candidate_collect_stmt(body, enclosing_strict, plans)
    GeneratorDecl(name, params, body, loc, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_unsupported_plan(
        Some(name),
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        GeneratorDeclaration,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    GeneratorDeclExt(name, params, rest_param, body, loc, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, enclosing_strict, children)
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_unsupported_plan(
        Some(name),
        CandidateExtendedSignature(params.copy(), rest_param),
        body,
        source_text,
        loc,
        GeneratorDeclaration,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    AsyncFuncDecl(name, params, body, loc, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_unsupported_plan(
        Some(name),
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncFunctionDeclaration,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    AsyncFuncDeclExt(name, params, rest_param, body, loc, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, enclosing_strict, children)
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_unsupported_plan(
        Some(name),
        CandidateExtendedSignature(params.copy(), rest_param),
        body,
        source_text,
        loc,
        AsyncFunctionDeclaration,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    AsyncGeneratorDecl(name, params, body, loc, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_unsupported_plan(
        Some(name),
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncGeneratorDeclaration,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    AsyncGeneratorDeclExt(name, params, rest_param, body, loc, source_text) => {
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, enclosing_strict, children)
      candidate_collect_function_body(body, enclosing_strict, children)
      plans.push(candidate_prepare_unsupported_plan(
        Some(name),
        CandidateExtendedSignature(params.copy(), rest_param),
        body,
        source_text,
        loc,
        AsyncGeneratorDeclaration,
        Some(DeclareFunctionConsumer(name)),
        enclosing_strict,
        children,
      ))
    }
    ClassDecl(_, superclass, members, _, _) => {
      match superclass {
        Some(superclass) => candidate_collect_expr(superclass, enclosing_strict, plans)
        None => ()
      }
      for member in members {
        candidate_collect_class_member(member, enclosing_strict, plans)
      }
    }
    WithStmt(expr, body, _) => {
      candidate_collect_expr(expr, enclosing_strict, plans)
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    ImportDecl(_, _, _, _, _, _) | ExportAllDecl(_, _, _, _) => ()
    ExportNamedDecl(declaration, _, _, _, _) => match declaration {
      Some(declaration) => candidate_collect_stmt(declaration, enclosing_strict, plans)
      None => ()
    }
    ExportDefaultDecl(expr, _) => candidate_collect_expr(expr, enclosing_strict, plans)
  }
}

///|
fn candidate_collect_stmts(
  stmts : Array[@ast.Stmt],
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  for stmt in stmts {
    candidate_collect_stmt(stmt, enclosing_strict, plans)
  }
}

///|
fn candidate_assign_identity_plan(
  plan : CandidateFunctionPlan,
  allocator : Ref[SourcePointOwnerAllocator],
) -> CandidateFunctionPlan raise Error {
  let owner = allocate_source_point_owner(allocator)
  let children : Array[CandidateFunctionPlan] = []
  for child in plan.children {
    children.push(candidate_assign_identity_plan(child, allocator))
  }
  { ..plan, children, identity_plan: Some({ source_point_owner: owner, children: children.map(c => c.identity_plan.unwrap()) }) }
}

///|
fn candidate_bytecode_identity_plan(
  plan : CandidateFunctionPlan,
) -> CandidateIdentityPlan {
  let identity_plan = plan.identity_plan.unwrap()
  let children : Array[CandidateIdentityPlan] = []
  for i, child in plan.children {
    let child_identity = identity_plan.children[i]
    match child.lowering {
      CandidateLoweringUnsupported(_) =>
        children.push({
          source_point_owner: child_identity.source_point_owner,
          children: [],
        })
      CandidateLowered => children.push(candidate_bytecode_identity_plan(child))
    }
  }
  { source_point_owner: identity_plan.source_point_owner, children }
}

///|
fn candidate_owner_number(owner : SourcePointOwnerId) -> Int {
  let SourcePointOwnerId(number) = owner
  number
}

///|
fn candidate_verify_function(
  function : BytecodeFunction,
) -> Unit raise Error {
  let _ = verify_bytecode_function_source_metadata(
    function,
    SourceUnitHandle(0),
    [],
    candidate_owner_number(function.source_point_owner),
  )
  verify_bytecode_preparation(function, [])
  verify_bytecode_function_control_flow(function, [])
  verify_bytecode_function_observation_coverage(function, [])
  verify_bytecode_function_indexed_operands(function, [])
  verify_bytecode_function_shape_operands(function, [])
  verify_bytecode_function_frame_shapes(function, [])
}

///|
fn candidate_compile_function(
  plan : CandidateFunctionPlan,
  allocator : Ref[SourcePointOwnerAllocator],
  identity_plan : CandidateIdentityPlan,
  header_provenance : BytecodeHeaderProvenance?,
) -> VerifiedBytecodeFunction raise Error {
  let function = compile_bytecode_function(
    plan.name,
    plan.params,
    plan.body,
    plan.rest_param,
    allocator,
    source_text=plan.source_text,
    use_local_slots=true,
    source_unit=SourceUnitHandle(0),
    enclosing_strict=plan.enclosing_strict,
    is_method=plan.is_method,
    header_provenance~,
    activation_kind=plan.activation_kind,
    candidate_identity_plan=Some(identity_plan),
    candidate_mode=true,
  )
  candidate_verify_function(function)
  make_verified_bytecode_function(function)
}

///|
fn candidate_source_identity(
  identity_plan : CandidateIdentityPlan,
  allocator : Ref[SourcePointOwnerAllocator],
  parent : (SourcePointOwnerId, Int, BytecodeFunctionConsumerForm)?,
) -> BytecodeSourceIdentity {
  match parent {
    Some((parent_owner, child_index, consumer_form)) => BytecodeSourceIdentity::child(
      allocator.val.program_identity,
      SourceUnitHandle(0),
      identity_plan.source_point_owner,
      parent_owner,
      child_index,
      consumer_form,
    )
    None => BytecodeSourceIdentity::root(
      SourceUnitHandle(0),
      identity_plan.source_point_owner,
      program_identity=Some(allocator.val.program_identity),
    )
  }
}

///|
fn candidate_materialize_function(
  plan : CandidateFunctionPlan,
  allocator : Ref[SourcePointOwnerAllocator],
  parent : (SourcePointOwnerId, Int, BytecodeFunctionConsumerForm)?,
) -> CandidateFunction raise Error {
  let identity_plan = plan.identity_plan.unwrap()
  let source_identity = candidate_source_identity(identity_plan, allocator, parent)
  let bytecode : VerifiedBytecodeFunction? = match plan.lowering {
    CandidateLoweringUnsupported(_) => None
    CandidateLowered => {
      let bytecode_identity_plan = candidate_bytecode_identity_plan(plan)
      let header_provenance = match parent {
        Some((parent_owner, child_index, consumer_form)) => Some(
          BytecodeHeaderProvenance(
            allocator.val.program_identity,
            plan.name,
            plan.params.copy(),
            plan.rest_param,
            plan.enclosing_strict,
            parent_owner,
            child_index,
            consumer_form,
            plan.source_text,
          ),
        )
        None => None
      }
      Some(candidate_compile_function(
        plan,
        allocator,
        bytecode_identity_plan,
        header_provenance,
      ))
    }
  }
  let selection = match plan.lowering {
    CandidateLoweringUnsupported(unsupported) =>
      UseTreeWalker(CandidateLoweringUnsupported(unsupported))
    CandidateLowered => match bytecode {
      Some(bytecode) => match select_bytecode_function_activation(
        bytecode,
        [],
      ) {
        Ok(disposition) => UseBytecode(disposition)
        Err(unsupported) => UseTreeWalker(CandidateActivationUnsupported(unsupported))
      }
      None => raise @errors.InternalError(
        message="candidate lowering succeeded without verified bytecode",
      )
    }
  }
  let children : Array[CandidateFunction] = []
  for child_index, child_plan in plan.children {
    let child_consumer = match child_plan.consumer_form {
      Some(consumer_form) => consumer_form
      None => raise @errors.InternalError(
        message="candidate child is missing consumer form",
      )
    }
    children.push(candidate_materialize_function(
      child_plan,
      allocator,
      Some((identity_plan.source_point_owner, child_index, child_consumer)),
    ))
  }
  {
    name: plan.name,
    signature: plan.signature,
    body: plan.body.copy(),
    source_text: plan.source_text,
    is_method: plan.is_method,
    consumer_form: plan.consumer_form,
    source_identity,
    selection,
    bytecode,
    children,
  }
}

///|
fn verify_candidate_function(
  function : CandidateFunction,
  program_identity : Ref[Unit],
  parent : BytecodeSourceIdentity?,
) -> Unit raise Error {
  guard physical_equal(function.source_identity.program_identity, program_identity) else {
    raise @errors.InternalError(message="candidate source identity has stale program token")
  }
  match parent {
    Some(parent) => {
      guard function.source_identity.parent_source_point_owner ==
        Some(parent.source_point_owner) else {
        raise @errors.InternalError(message="candidate child has stale parent identity")
      }
    }
    None => {
      if function.source_identity.parent_source_point_owner is Some(_) {
        raise @errors.InternalError(message="candidate root has child identity")
      }
    }
  }
  match function.bytecode {
    Some(bytecode) => {
      guard bytecode_source_identity_equal(
        bytecode.function.source_identity,
        function.source_identity,
      ) else {
        raise @errors.InternalError(message="candidate bytecode/tree identity mismatch")
      }
    }
    None => ()
  }
  for child in function.children {
    verify_candidate_function(child, program_identity, Some(function.source_identity))
  }
}

///|
fn prepare_candidate_program(
  stmts : Array[@ast.Stmt],
) -> CandidateProgram raise Error {
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_stmts(stmts, false, children)
  let root_lowering = candidate_lower_function(
    None,
    [],
    stmts,
    None,
    None,
    @static_semantics.has_use_strict(stmts),
    false,
    ScriptRootActivation,
  )
  let root_plan : CandidateFunctionPlan = {
    name: None,
    signature: CandidateSimpleSignature([]),
    params: [],
    rest_param: None,
    body: stmts.copy(),
    source_text: None,
    is_method: false,
    consumer_form: None,
    enclosing_strict: @static_semantics.has_use_strict(stmts),
    activation_kind: ScriptRootActivation,
    lowering: root_lowering,
    children,
    identity_plan: None,
  }
  let allocator = new_source_point_owner_allocator()
  let root_plan = candidate_assign_identity_plan(root_plan, allocator)
  let root = candidate_materialize_function(root_plan, allocator, None)
  verify_candidate_function(root, allocator.val.program_identity, None)
  { program_identity: allocator.val.program_identity, root }
}

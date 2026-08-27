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
priv enum CandidateBytecodeChildSlot {
  CandidateBytecodeChild(CandidateVerifiedBytecodeFunction)
  CandidateTreeChild(CandidateTreeWalkerReason)
}

///|
// This candidate-local carrier is verified by the function-local verifier
// below.  It is deliberately not `VerifiedBytecodeFunction`, so it cannot be
// passed to ordinary finalization or `BytecodeExecutorCode` activation.
priv struct CandidateVerifiedBytecodeFunction {
  function : BytecodeFunction
  child_slots : Array[CandidateBytecodeChildSlot]
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
  lowering_supported : Bool
}

///|
priv struct CandidateFunctionPlan {
  name : String?
  materialization_site : @token.Loc?
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
  materialization_site : @token.Loc?
  signature : CandidateFunctionSignature
  body : Array[@ast.Stmt]
  strict : Bool
  source_text : String?
  is_method : Bool
  consumer_form : BytecodeFunctionConsumerForm?
  source_identity : BytecodeSourceIdentity
  selection : CandidateSelection
  bytecode : CandidateVerifiedBytecodeFunction?
  children : Array[CandidateFunction]
}

///|
priv struct CandidateIdentityAuthority {
  program_identity : Ref[Unit]
  root : CandidateIdentityNode
}

///|
priv struct CandidateIdentityNode {
  source_identity : BytecodeSourceIdentity
  children : Array[CandidateIdentityNode]
}

///|
priv struct CandidateProgram {
  program_identity : Ref[Unit]
  identity_authority : CandidateIdentityAuthority
  root : CandidateFunction
  script_preparation : @runtime.CompiledScriptPreparation?
}

///|
fn candidate_function_strict(
  enclosing_strict : Bool,
  body : Array[@ast.Stmt],
) -> Bool {
  enclosing_strict || @static_semantics.has_use_strict(body)
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
  function_form? : BytecodeFunctionForm = OrdinaryFunction,
  function_form_loc? : @token.Loc? = None,
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
      function_form~,
      function_form_loc~,
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
  Ok(simple_ext_param_names_with_rest(params, rest_param, loc)) catch {
    BytecodeUnsupportedSignal(unsupported) => Err(unsupported)
    error => raise error
  }
}

///|
fn candidate_first_unsupported_child(
  children : Array[CandidateFunctionPlan],
) -> BytecodeUnsupported? {
  for child in children {
    match child.lowering {
      CandidateLoweringUnsupported(unsupported) => return Some(unsupported)
      CandidateLowered => ()
    }
  }
  None
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
  materialization_site : @token.Loc?,
  function_form? : BytecodeFunctionForm = OrdinaryFunction,
  function_form_loc? : @token.Loc? = None,
) -> CandidateFunctionPlan raise Error {
  let strict = candidate_function_strict(enclosing_strict, body)
  let named_function_unsupported = match
    (function_form, consumer_form, materialization_site) {
    (OrdinaryFunction, Some(NamedFunctionConsumer(_)), Some(loc)) =>
      Some(BytecodeUnsupported(NamedFunctionExpression, loc))
    _ => None
  }
  let lowering : CandidateFunctionLowering = match named_function_unsupported {
    Some(unsupported) => CandidateLoweringUnsupported(unsupported)
    None =>
      match candidate_first_unsupported_child(children) {
        Some(unsupported) => CandidateLoweringUnsupported(unsupported)
        None =>
          match params {
            Ok((simple_params, simple_rest)) =>
              candidate_lower_function(
                name,
                simple_params,
                body,
                simple_rest,
                source_text,
                strict,
                is_method,
                activation_kind,
                function_form~,
                function_form_loc~,
              )
            Err(unsupported) => CandidateLoweringUnsupported(unsupported)
          }
      }
  }
  let (simple_params, simple_rest) = match params {
    Ok((simple_params, simple_rest)) => (simple_params, simple_rest)
    Err(_) => ([], None)
  }
  {
    name,
    materialization_site,
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
  materialization_site : @token.Loc?,
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
    materialization_site,
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
  materialization_site : @token.Loc?,
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
    materialization_site,
  )
}

///|
fn candidate_prepare_function_form_plan(
  name : String?,
  signature : CandidateFunctionSignature,
  body : Array[@ast.Stmt],
  source_text : String?,
  loc : @token.Loc,
  function_form : BytecodeFunctionForm,
  consumer_form : BytecodeFunctionConsumerForm?,
  is_method : Bool,
  enclosing_strict : Bool,
  children : Array[CandidateFunctionPlan],
) -> CandidateFunctionPlan raise Error {
  candidate_prepare_plan(
    name,
    signature,
    Ok(([], None)),
    body,
    source_text,
    is_method,
    consumer_form,
    enclosing_strict,
    FunctionActivation,
    children,
    Some(loc),
    function_form~,
    function_form_loc=Some(loc),
  )
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
          Some(element) =>
            candidate_collect_pattern(element, enclosing_strict, plans)
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
          Some(default_val) =>
            candidate_collect_expr(default_val, enclosing_strict, plans)
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
      Some(default_val) =>
        candidate_collect_expr(default_val, enclosing_strict, plans)
      None => ()
    }
    match param.pattern {
      Some(pattern) =>
        candidate_collect_pattern(pattern, enclosing_strict, plans)
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
  let strict = candidate_function_strict(enclosing_strict, body)
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_function_body(body, strict, children)
  plans.push(
    candidate_prepare_simple_plan(
      name,
      params,
      body,
      source_text,
      false,
      Some(consumer_form),
      strict,
      children,
      Some(loc),
    ),
  )
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
  let strict = candidate_function_strict(enclosing_strict, body)
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_params(params, strict, children)
  candidate_collect_function_body(body, strict, children)
  plans.push(
    candidate_prepare_ext_plan(
      name,
      params,
      rest_param,
      body,
      loc,
      source_text,
      false,
      Some(consumer_form),
      strict,
      children,
      Some(loc),
    ),
  )
}

///|
fn candidate_collect_method_expr(
  expr : @ast.Expr,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
  class_constructor? : Bool = false,
) -> Unit raise Error {
  match expr {
    FuncExpr(name, params, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, strict, children)
      let plan = candidate_prepare_plan(
        name,
        CandidateSimpleSignature(params.copy()),
        Ok((params.copy(), None)),
        body,
        source_text,
        true,
        Some(consumer_form),
        strict,
        FunctionActivation,
        children,
        Some(loc),
      )
      plans.push(
        if class_constructor {
          {
            ..plan,
            lowering: CandidateLoweringUnsupported(
              BytecodeUnsupported(ClassConstructor, loc),
            ),
          }
        } else {
          plan
        },
      )
    }
    FuncExprExt(name, params, rest_param, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, strict, children)
      candidate_collect_function_body(body, strict, children)
      let plan = candidate_prepare_plan(
        name,
        CandidateExtendedSignature(params.copy(), rest_param),
        candidate_normalize_ext_params(params, rest_param, loc),
        body,
        source_text,
        true,
        Some(consumer_form),
        strict,
        FunctionActivation,
        children,
        Some(loc),
      )
      plans.push(
        if class_constructor {
          {
            ..plan,
            lowering: CandidateLoweringUnsupported(
              BytecodeUnsupported(ClassConstructor, loc),
            ),
          }
        } else {
          plan
        },
      )
    }
    GeneratorExpr(name, params, body, loc, source_text) =>
      candidate_collect_function_form(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        match consumer_form {
          MethodFunctionConsumer | ComputedMethodFunctionConsumer =>
            ObjectLiteralGeneratorMethodFunction
          _ => GeneratorExpressionFunction
        },
        consumer_form,
        enclosing_strict,
        plans,
      )
    GeneratorExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_form_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        match consumer_form {
          MethodFunctionConsumer | ComputedMethodFunctionConsumer =>
            ObjectLiteralGeneratorMethodFunction
          _ => GeneratorExpressionFunction
        },
        consumer_form,
        enclosing_strict,
        plans,
      )
    AsyncFuncExpr(name, params, body, loc, source_text) =>
      candidate_collect_function_form(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        match consumer_form {
          MethodFunctionConsumer | ComputedMethodFunctionConsumer =>
            ObjectLiteralAsyncMethodFunction
          _ => AsyncFunctionExpressionFunction
        },
        consumer_form,
        enclosing_strict,
        plans,
      )
    AsyncFuncExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_form_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        match consumer_form {
          MethodFunctionConsumer | ComputedMethodFunctionConsumer =>
            ObjectLiteralAsyncMethodFunction
          _ => AsyncFunctionExpressionFunction
        },
        consumer_form,
        enclosing_strict,
        plans,
      )
    AsyncGeneratorExpr(name, params, body, loc, source_text) =>
      candidate_collect_function_form(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        match consumer_form {
          MethodFunctionConsumer | ComputedMethodFunctionConsumer =>
            ObjectLiteralAsyncGeneratorMethodFunction
          _ => AsyncGeneratorExpressionFunction
        },
        consumer_form,
        enclosing_strict,
        plans,
      )
    AsyncGeneratorExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_form_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        match consumer_form {
          MethodFunctionConsumer | ComputedMethodFunctionConsumer =>
            ObjectLiteralAsyncGeneratorMethodFunction
          _ => AsyncGeneratorExpressionFunction
        },
        consumer_form,
        enclosing_strict,
        plans,
      )
    _ => candidate_collect_expr(expr, enclosing_strict, plans)
  }
}

///|
fn candidate_collect_function_form(
  name : String?,
  signature : CandidateFunctionSignature,
  body : Array[@ast.Stmt],
  source_text : String?,
  loc : @token.Loc,
  function_form : BytecodeFunctionForm,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  let strict = candidate_function_strict(enclosing_strict, body)
  let is_method = match consumer_form {
    MethodFunctionConsumer | ComputedMethodFunctionConsumer => true
    _ => false
  }
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_function_body(body, strict, children)
  match signature {
    CandidateSimpleSignature(_) => ()
    CandidateExtendedSignature(params, _) =>
      candidate_collect_params(params, strict, children)
  }
  plans.push(
    candidate_prepare_function_form_plan(
      name,
      signature,
      body,
      source_text,
      loc,
      function_form,
      Some(consumer_form),
      is_method,
      strict,
      children,
    ),
  )
}

///|
fn candidate_collect_function_form_ext(
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  source_text : String?,
  loc : @token.Loc,
  function_form : BytecodeFunctionForm,
  consumer_form : BytecodeFunctionConsumerForm,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  candidate_collect_function_form(
    name,
    CandidateExtendedSignature(params.copy(), rest_param),
    body,
    source_text,
    loc,
    function_form,
    consumer_form,
    enclosing_strict,
    plans,
  )
}

///|
fn candidate_collect_class_member(
  class_member : @ast.ClassMember,
  enclosing_strict : Bool,
  plans : Array[CandidateFunctionPlan],
) -> Unit raise Error {
  match class_member {
    Method(method_def) => {
      candidate_collect_expr(method_def.key, enclosing_strict, plans)
      let class_constructor = !method_def.computed &&
        !method_def.is_static &&
        !method_def.is_private &&
        method_def.kind is @ast.PropKind::Init &&
        method_def.key is @ast.Expr::StringLit("constructor", _, _, _)
      let consumer_form = if method_def.computed {
        ComputedMethodFunctionConsumer
      } else {
        MethodFunctionConsumer
      }
      candidate_collect_method_expr(
        method_def.value,
        consumer_form,
        enclosing_strict,
        plans,
        class_constructor~,
      )
    }
    Field(field) => {
      candidate_collect_expr(field.key, enclosing_strict, plans)
      match field.initializer {
        Some(initializer) =>
          candidate_collect_expr(initializer, enclosing_strict, plans)
        None => ()
      }
    }
    StaticBlock(stmts, _) =>
      candidate_collect_stmts(stmts, enclosing_strict, plans)
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
      candidate_collect_function_form(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        GeneratorExpressionFunction,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    GeneratorExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_form_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        GeneratorExpressionFunction,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    AsyncFuncExpr(name, params, body, loc, source_text) =>
      candidate_collect_function_form(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncFunctionExpressionFunction,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    AsyncFuncExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_form_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        AsyncFunctionExpressionFunction,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    AsyncArrowFunc(params, body, loc, source_text) =>
      candidate_collect_function_form(
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
      candidate_collect_function_form_ext(
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
      candidate_collect_function_form(
        name,
        CandidateSimpleSignature(params),
        body,
        source_text,
        loc,
        AsyncGeneratorExpressionFunction,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    AsyncGeneratorExprExt(name, params, rest_param, body, loc, source_text) =>
      candidate_collect_function_form_ext(
        name,
        params,
        rest_param,
        body,
        source_text,
        loc,
        AsyncGeneratorExpressionFunction,
        match name {
          Some(name) => NamedFunctionConsumer(name)
          None => FunctionConsumer
        },
        enclosing_strict,
        plans,
      )
    ObjectLit(properties, _) =>
      for property in properties {
        candidate_collect_property(property, enclosing_strict, plans)
      }
    ClassExpr(_, superclass, members, _, _) => {
      match superclass {
        Some(superclass) =>
          candidate_collect_expr(superclass, enclosing_strict, plans)
        None => ()
      }
      for class_member in members {
        candidate_collect_class_member(class_member, enclosing_strict, plans)
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
          None =>
            candidate_collect_expr(child, enclosing_strict, plans) catch {
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
      Some(condition) =>
        candidate_collect_expr(condition, enclosing_strict, plans)
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
    VarDecl(_, _, init, _) =>
      match init {
        Some(init) => candidate_collect_expr(init, enclosing_strict, plans)
        None => ()
      }
    Block(stmts, _) | StmtList(stmts, _) =>
      candidate_collect_stmts(stmts, enclosing_strict, plans)
    IfStmt(condition, then_branch, else_branch, _) => {
      candidate_collect_expr(condition, enclosing_strict, plans)
      candidate_collect_stmt(then_branch, enclosing_strict, plans)
      match else_branch {
        Some(else_branch) =>
          candidate_collect_stmt(else_branch, enclosing_strict, plans)
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
        Some(condition) =>
          candidate_collect_expr(condition, enclosing_strict, plans)
        None => ()
      }
      match update {
        Some(update) => candidate_collect_expr(update, enclosing_strict, plans)
        None => ()
      }
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    FuncDecl(name, params, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_simple_plan(
          Some(name),
          params,
          body,
          source_text,
          false,
          Some(DeclareFunctionConsumer(name)),
          strict,
          children,
          Some(loc),
        ),
      )
    }
    FuncDeclExt(name, params, rest_param, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, strict, children)
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_ext_plan(
          Some(name),
          params,
          rest_param,
          body,
          loc,
          source_text,
          false,
          Some(DeclareFunctionConsumer(name)),
          strict,
          children,
          Some(loc),
        ),
      )
    }
    ReturnStmt(expr, _) =>
      match expr {
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
        Some(catch_body) =>
          candidate_collect_stmts(catch_body, enclosing_strict, plans)
        None => ()
      }
      match finally_body {
        Some(finally_body) =>
          candidate_collect_stmts(finally_body, enclosing_strict, plans)
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
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_function_form_plan(
          Some(name),
          CandidateSimpleSignature(params),
          body,
          source_text,
          loc,
          GeneratorDeclarationFunction,
          Some(DeclareFunctionConsumer(name)),
          false,
          strict,
          children,
        ),
      )
    }
    GeneratorDeclExt(name, params, rest_param, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, strict, children)
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_function_form_plan(
          Some(name),
          CandidateExtendedSignature(params.copy(), rest_param),
          body,
          source_text,
          loc,
          GeneratorDeclarationFunction,
          Some(DeclareFunctionConsumer(name)),
          false,
          strict,
          children,
        ),
      )
    }
    AsyncFuncDecl(name, params, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_function_form_plan(
          Some(name),
          CandidateSimpleSignature(params),
          body,
          source_text,
          loc,
          AsyncFunctionDeclarationFunction,
          Some(DeclareFunctionConsumer(name)),
          false,
          strict,
          children,
        ),
      )
    }
    AsyncFuncDeclExt(name, params, rest_param, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, strict, children)
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_function_form_plan(
          Some(name),
          CandidateExtendedSignature(params.copy(), rest_param),
          body,
          source_text,
          loc,
          AsyncFunctionDeclarationFunction,
          Some(DeclareFunctionConsumer(name)),
          false,
          strict,
          children,
        ),
      )
    }
    AsyncGeneratorDecl(name, params, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_function_form_plan(
          Some(name),
          CandidateSimpleSignature(params),
          body,
          source_text,
          loc,
          AsyncGeneratorDeclarationFunction,
          Some(DeclareFunctionConsumer(name)),
          false,
          strict,
          children,
        ),
      )
    }
    AsyncGeneratorDeclExt(name, params, rest_param, body, loc, source_text) => {
      let strict = candidate_function_strict(enclosing_strict, body)
      let children : Array[CandidateFunctionPlan] = []
      candidate_collect_params(params, strict, children)
      candidate_collect_function_body(body, strict, children)
      plans.push(
        candidate_prepare_function_form_plan(
          Some(name),
          CandidateExtendedSignature(params.copy(), rest_param),
          body,
          source_text,
          loc,
          AsyncGeneratorDeclarationFunction,
          Some(DeclareFunctionConsumer(name)),
          false,
          strict,
          children,
        ),
      )
    }
    ClassDecl(_, superclass, members, _, _) => {
      match superclass {
        Some(superclass) =>
          candidate_collect_expr(superclass, enclosing_strict, plans)
        None => ()
      }
      for class_member in members {
        candidate_collect_class_member(class_member, enclosing_strict, plans)
      }
    }
    WithStmt(expr, body, _) => {
      candidate_collect_expr(expr, enclosing_strict, plans)
      candidate_collect_stmt(body, enclosing_strict, plans)
    }
    ImportDecl(_, _, _, _, _, _) | ExportAllDecl(_, _, _, _) => ()
    ExportNamedDecl(declaration, _, _, _, _) =>
      match declaration {
        Some(declaration) =>
          candidate_collect_stmt(declaration, enclosing_strict, plans)
        None => ()
      }
    ExportDefaultDecl(expr, _) =>
      candidate_collect_expr(expr, enclosing_strict, plans)
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
  {
    ..plan,
    children,
    identity_plan: Some({
      source_point_owner: owner,
      children: children.map(c => c.identity_plan.unwrap()),
      lowering_supported: plan.lowering is CandidateLowered,
    }),
  }
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
          lowering_supported: false,
        })
      CandidateLowered => children.push(candidate_bytecode_identity_plan(child))
    }
  }
  {
    source_point_owner: identity_plan.source_point_owner,
    children,
    lowering_supported: identity_plan.lowering_supported,
  }
}

///|
fn candidate_owner_number(owner : SourcePointOwnerId) -> Int {
  let SourcePointOwnerId(number) = owner
  number
}

///|
fn candidate_compile_function(
  plan : CandidateFunctionPlan,
  allocator : Ref[SourcePointOwnerAllocator],
  identity_plan : CandidateIdentityPlan,
  header_provenance : BytecodeHeaderProvenance?,
  enclosing_strict : Bool,
) -> BytecodeFunction raise Error {
  let function = compile_bytecode_function(
    plan.name,
    plan.params,
    plan.body,
    plan.rest_param,
    allocator,
    source_text=plan.source_text,
    use_local_slots=plan.activation_kind != ScriptRootActivation,
    source_unit=SourceUnitHandle(0),
    enclosing_strict~,
    is_method=plan.is_method,
    header_provenance~,
    activation_kind=plan.activation_kind,
    candidate_identity_plan=Some(identity_plan),
    candidate_mode=true,
  )
  function
}

///|
fn candidate_source_identity(
  identity_plan : CandidateIdentityPlan,
  allocator : Ref[SourcePointOwnerAllocator],
  parent : (SourcePointOwnerId, Int, BytecodeFunctionConsumerForm, Bool)?,
) -> BytecodeSourceIdentity {
  match parent {
    Some((parent_owner, child_index, consumer_form, _)) =>
      BytecodeSourceIdentity::child(
        allocator.val.program_identity,
        SourceUnitHandle(0),
        identity_plan.source_point_owner,
        parent_owner,
        child_index,
        consumer_form,
      )
    None =>
      BytecodeSourceIdentity::root(
        SourceUnitHandle(0),
        identity_plan.source_point_owner,
        program_identity=Some(allocator.val.program_identity),
      )
  }
}

///|
fn candidate_tree_walker_reason(
  selection : CandidateSelection,
) -> CandidateTreeWalkerReason raise Error {
  match selection {
    UseTreeWalker(reason) => reason
    UseBytecode(_) =>
      raise @errors.InternalError(
        message="candidate bytecode slot has no tree-walker reason",
      )
  }
}

///|
fn candidate_build_identity_node(
  plan : CandidateFunctionPlan,
  allocator : Ref[SourcePointOwnerAllocator],
  parent : (SourcePointOwnerId, Int, BytecodeFunctionConsumerForm, Bool)?,
) -> CandidateIdentityNode raise Error {
  let identity_plan = plan.identity_plan.unwrap()
  let source_identity = candidate_source_identity(
    identity_plan, allocator, parent,
  )
  let children : Array[CandidateIdentityNode] = []
  for child_index, child_plan in plan.children {
    let child_consumer = match child_plan.consumer_form {
      Some(consumer_form) => consumer_form
      None =>
        raise @errors.InternalError(
          message="candidate identity authority is missing a consumer form",
        )
    }
    children.push(
      candidate_build_identity_node(
        child_plan,
        allocator,
        Some(
          (
            identity_plan.source_point_owner,
            child_index,
            child_consumer,
            plan.enclosing_strict,
          ),
        ),
      ),
    )
  }
  { source_identity, children }
}

///|
fn candidate_build_identity_authority(
  plan : CandidateFunctionPlan,
  allocator : Ref[SourcePointOwnerAllocator],
) -> CandidateIdentityAuthority raise Error {
  {
    program_identity: allocator.val.program_identity,
    root: candidate_build_identity_node(plan, allocator, None),
  }
}

///|
fn candidate_materialize_function(
  plan : CandidateFunctionPlan,
  allocator : Ref[SourcePointOwnerAllocator],
  parent : (SourcePointOwnerId, Int, BytecodeFunctionConsumerForm, Bool)?,
  function_path : Array[Int],
) -> CandidateFunction raise Error {
  let identity_plan = plan.identity_plan.unwrap()
  let source_identity = candidate_source_identity(
    identity_plan, allocator, parent,
  )
  let raw_bytecode : BytecodeFunction? = match plan.lowering {
    CandidateLoweringUnsupported(_) => None
    CandidateLowered => {
      let bytecode_identity_plan = candidate_bytecode_identity_plan(plan)
      let header_provenance = match parent {
        Some((parent_owner, child_index, consumer_form, parent_strict)) =>
          Some(
            BytecodeHeaderProvenance(
              allocator.val.program_identity,
              plan.name,
              plan.params.copy(),
              plan.rest_param,
              parent_strict,
              parent_owner,
              child_index,
              consumer_form,
              plan.source_text,
            ),
          )
        None => None
      }
      Some(
        candidate_compile_function(
          plan,
          allocator,
          bytecode_identity_plan,
          header_provenance,
          match parent {
            Some((_, _, _, parent_strict)) => parent_strict
            None => false
          },
        ),
      )
    }
  }
  let children : Array[CandidateFunction] = []
  for child_index, child_plan in plan.children {
    let child_consumer = match child_plan.consumer_form {
      Some(consumer_form) => consumer_form
      None =>
        raise @errors.InternalError(
          message="candidate child is missing consumer form",
        )
    }
    let child_path = function_path.copy()
    child_path.push(child_index)
    children.push(
      candidate_materialize_function(
        child_plan,
        allocator,
        Some(
          (
            identity_plan.source_point_owner,
            child_index,
            child_consumer,
            plan.enclosing_strict,
          ),
        ),
        child_path,
      ),
    )
  }
  let bytecode : CandidateVerifiedBytecodeFunction? = match raw_bytecode {
    None => None
    Some(function) => {
      // Establish the candidate-local verification boundary before retaining
      // the carrier.  This verifier accepts the logical child-slot count while
      // deliberately skipping sparse raw-child recursion.
      candidate_verify_local_function(
        function,
        children.length(),
        function_path,
      )
      let child_slots : Array[CandidateBytecodeChildSlot] = []
      for child in children {
        match child.bytecode {
          Some(child_bytecode) =>
            child_slots.push(CandidateBytecodeChild(child_bytecode))
          None =>
            child_slots.push(
              CandidateTreeChild(candidate_tree_walker_reason(child.selection)),
            )
        }
      }
      Some({ function, child_slots })
    }
  }
  let selection = match plan.lowering {
    CandidateLoweringUnsupported(unsupported) =>
      UseTreeWalker(CandidateLoweringUnsupported(unsupported))
    CandidateLowered =>
      match bytecode {
        Some(bytecode) =>
          match
            select_bytecode_code_activation(
              bytecode.function.code,
              function_path,
            ) {
            Ok(disposition) => UseBytecode(disposition)
            Err(unsupported) =>
              UseTreeWalker(CandidateActivationUnsupported(unsupported))
          }
        None =>
          raise @errors.InternalError(
            message="candidate lowering succeeded without candidate bytecode",
          )
      }
  }
  {
    name: plan.name,
    materialization_site: plan.materialization_site,
    signature: plan.signature,
    body: plan.body.copy(),
    strict: plan.enclosing_strict,
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
fn candidate_verify_selection(selection : CandidateSelection) -> Unit {
  match selection {
    UseBytecode(disposition) =>
      match disposition {
        SynchronousLeaf | ManagedSuspension => ()
        UnsupportedBeforeActivation(reason) => ignore(reason)
      }
    UseTreeWalker(reason) =>
      match reason {
        CandidateLoweringUnsupported(unsupported) => ignore(unsupported)
        CandidateActivationUnsupported(unsupported) => ignore(unsupported)
      }
  }
}

///|
fn candidate_verify_metadata(function : CandidateFunction) -> Unit raise Error {
  ignore(function.name)
  ignore(function.body)
  ignore(function.source_text)
  ignore(function.is_method)
  match function.signature {
    CandidateSimpleSignature(params) => ignore(params)
    CandidateExtendedSignature(params, rest_param) => {
      ignore(params)
      ignore(rest_param)
    }
  }
  candidate_verify_selection(function.selection)
  guard function.source_identity.consumer_form == function.consumer_form else {
    raise @errors.InternalError(message="candidate consumer metadata mismatch")
  }
  match (function.consumer_form, function.materialization_site) {
    (None, None) | (Some(_), Some(_)) => ()
    _ =>
      raise @errors.InternalError(
        message="candidate materialization site metadata mismatch",
      )
  }
}

///|
// A verified parent may not contain two children at one syntax coordinate.
// Rejecting this during preparation prevents runtime lookup from becoming
// ambiguous, while repeated evaluation of one site still returns the same
// immutable child.
fn candidate_verify_materialization_sites(
  function : CandidateFunction,
) -> Unit raise Error {
  let seen : Array[@token.Loc] = []
  for child in function.children {
    let site = match child.materialization_site {
      Some(site) => site
      None =>
        raise @errors.InternalError(
          message="candidate child has no materialization site",
        )
    }
    if seen.contains(site) {
      raise @errors.InternalError(
        message="candidate materialization site is duplicated",
      )
    }
    seen.push(site)
  }
}

///|
fn candidate_verify_function_declarations(
  function : BytecodeFunction,
  children : Array[CandidateFunction],
  function_path : Array[Int],
) -> Unit raise Error {
  let consumer_scan = scan_bytecode_function_consumers_for_verification(
    function.code,
    children.length(),
  )
  let actual = function.preparation.function_declarations
  if actual.length() != consumer_scan.declarations.length() {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "DeclareFunction source count",
      -1,
      consumer_scan.declarations.length().to_string(),
      actual.length().to_string(),
    )
  }
  for index in 0..<actual.length() {
    let actual_declaration = actual[index]
    let (consumer_name, consumer_child_index) = consumer_scan.declarations[index]
    guard actual_declaration.name == consumer_name &&
      actual_declaration.child_index == consumer_child_index else {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration provenance",
        index,
        consumer_name + ":" + consumer_child_index.to_string(),
        actual_declaration.name +
        ":" +
        actual_declaration.child_index.to_string(),
      )
    }
    guard consumer_child_index >= 0 && consumer_child_index < children.length() else {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration child index bounds",
        index,
        "0..<" + children.length().to_string(),
        consumer_child_index.to_string(),
      )
    }
    let child = children[consumer_child_index]
    guard bytecode_source_identity_equal(
      actual_declaration.source_identity,
      child.source_identity,
    ) else {
      bytecode_preparation_mismatch_for_verification(
        function_path, "function declaration source identity", index, "candidate child source identity",
        "mismatch",
      )
    }
    guard child.name == Some(consumer_name) else {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration child name",
        index,
        consumer_name,
        match child.name {
          Some(name) => name
          None => "<anonymous>"
        },
      )
    }
  }
}

///|
fn candidate_raw_child_for_slot(
  function : BytecodeFunction,
  child_index : Int,
) -> BytecodeFunction? {
  for child in function.children {
    if child.source_identity.child_index == Some(child_index) {
      return Some(child)
    }
  }
  None
}

///|
fn candidate_verify_bytecode_function(
  bytecode : CandidateVerifiedBytecodeFunction,
  candidate : CandidateFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let function = bytecode.function
  candidate_verify_local_function(
    function,
    candidate.children.length(),
    function_path,
  )
  candidate_verify_function_declarations(
    function,
    candidate.children,
    function_path,
  )
  guard bytecode.child_slots.length() == candidate.children.length() else {
    raise @errors.InternalError(
      message="candidate bytecode child slots do not match candidate tree",
    )
  }
  for child_index, child in candidate.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    let raw_child = candidate_raw_child_for_slot(function, child_index)
    match (child.bytecode, bytecode.child_slots[child_index]) {
      (Some(child_bytecode), CandidateBytecodeChild(slot_bytecode)) => {
        guard bytecode_source_identity_equal(
            child_bytecode.function.source_identity,
            child.source_identity,
          ) &&
          bytecode_source_identity_equal(
            slot_bytecode.function.source_identity,
            child.source_identity,
          ) else {
          raise @errors.InternalError(
            message="candidate bytecode/tree child identity mismatch",
          )
        }
        let raw_child = match raw_child {
          Some(raw_child) => raw_child
          None =>
            raise @errors.InternalError(
              message="candidate bytecode slot has no lowered child",
            )
        }
        let consumer_form = match child.consumer_form {
          Some(consumer_form) => consumer_form
          None =>
            raise @errors.InternalError(
              message="candidate bytecode child has no consumer form",
            )
        }
        verify_bytecode_child_provenance(
          function,
          raw_child,
          child_index,
          child_path,
          Some(consumer_form),
        )
        candidate_verify_bytecode_function(slot_bytecode, child, child_path)
      }
      (None, CandidateTreeChild(slot_reason)) => {
        match (child.selection, slot_reason) {
          (
            UseTreeWalker(CandidateLoweringUnsupported(_)),
            CandidateLoweringUnsupported(_),
          )
          | (
            UseTreeWalker(CandidateActivationUnsupported(_)),
            CandidateActivationUnsupported(_),
          ) => ()
          _ =>
            raise @errors.InternalError(
              message="tree-only candidate slot has the wrong fallback reason",
            )
        }
        guard raw_child is None else {
          raise @errors.InternalError(
            message="tree-only candidate child retained lowered bytecode",
          )
        }
      }
      (Some(_), CandidateTreeChild(_)) | (None, CandidateBytecodeChild(_)) =>
        raise @errors.InternalError(
          message="candidate bytecode child slot disagrees with tree candidate",
        )
    }
  }
}

///|
fn candidate_verify_local_function(
  function : BytecodeFunction,
  child_count : Int,
  function_path : Array[Int],
) -> Unit raise Error {
  let _ = verify_bytecode_function_source_metadata(
    function,
    SourceUnitHandle(0),
    function_path,
    candidate_owner_number(function.source_point_owner),
    recurse=false,
  )
  verify_bytecode_preparation(
    function,
    function_path,
    child_count=Some(child_count),
    recurse=false,
  )
  verify_bytecode_function_control_flow(function, function_path, recurse=false)
  verify_bytecode_function_observation_coverage(
    function,
    function_path,
    recurse=false,
  )
  verify_bytecode_function_indexed_operands(
    function,
    function_path,
    child_count=Some(child_count),
    recurse=false,
  )
  verify_bytecode_function_shape_operands(
    function,
    function_path,
    recurse=false,
  )
  verify_bytecode_function_frame_shapes(function, function_path, recurse=false)
}

///|
fn verify_candidate_function(
  function : CandidateFunction,
  authority : CandidateIdentityNode,
) -> Unit raise Error {
  candidate_verify_metadata(function)
  candidate_verify_materialization_sites(function)
  guard bytecode_source_identity_equal(
    function.source_identity,
    authority.source_identity,
  ) else {
    raise @errors.InternalError(
      message="candidate source identity disagrees with canonical authority",
    )
  }
  guard function.children.length() == authority.children.length() else {
    raise @errors.InternalError(
      message="candidate child tree disagrees with canonical authority",
    )
  }
  match (function.selection, function.bytecode) {
    (UseBytecode(_), Some(bytecode)) =>
      candidate_verify_bytecode_function(bytecode, function, [])
    (UseTreeWalker(CandidateLoweringUnsupported(_)), None) => ()
    (UseTreeWalker(CandidateActivationUnsupported(_)), Some(bytecode)) =>
      candidate_verify_bytecode_function(bytecode, function, [])
    _ =>
      raise @errors.InternalError(
        message="candidate selection and bytecode carrier disagree",
      )
  }
  for child_index, child in function.children {
    verify_candidate_function(child, authority.children[child_index])
  }
}

///|
fn verify_candidate_program(program : CandidateProgram) -> Unit raise Error {
  guard physical_equal(
    program.program_identity,
    program.identity_authority.program_identity,
  ) else {
    raise @errors.InternalError(
      message="candidate program identity disagrees with canonical authority",
    )
  }
  verify_candidate_function(program.root, program.identity_authority.root)
}

///|
#warnings("-unused_value")
fn prepare_candidate_program(
  stmts : Array[@ast.Stmt],
) -> CandidateProgram raise Error {
  let root_strict = @static_semantics.has_use_strict(stmts)
  let children : Array[CandidateFunctionPlan] = []
  candidate_collect_stmts(stmts, root_strict, children)
  let root_lowering : CandidateFunctionLowering = match
    candidate_first_unsupported_child(children) {
    Some(unsupported) => CandidateLoweringUnsupported(unsupported)
    None =>
      candidate_lower_function(
        None,
        [],
        stmts,
        None,
        None,
        root_strict,
        false,
        ScriptRootActivation,
      )
  }
  let root_plan : CandidateFunctionPlan = {
    name: None,
    materialization_site: None,
    signature: CandidateSimpleSignature([]),
    params: [],
    rest_param: None,
    body: stmts.copy(),
    source_text: None,
    is_method: false,
    consumer_form: None,
    enclosing_strict: root_strict,
    activation_kind: ScriptRootActivation,
    lowering: root_lowering,
    children,
    identity_plan: None,
  }
  let allocator = new_source_point_owner_allocator()
  let root_plan = candidate_assign_identity_plan(root_plan, allocator)
  let identity_authority = candidate_build_identity_authority(
    root_plan, allocator,
  )
  let root = candidate_materialize_function(root_plan, allocator, None, [])
  let script_preparation = match root.bytecode {
    Some(bytecode) => {
      let lexical_bindings = bytecode.function.preparation.lexical_bindings.map(binding => {
          let kind = match binding.kind {
            BytecodeLet => @runtime.LetBinding
            BytecodeConst => @runtime.ConstBinding
          }
          @runtime.CompiledScriptLexicalBinding(kind~, name=binding.name)
        },
      )
      let function_names = bytecode.function.preparation.function_declarations.map(declaration => {
          declaration.name
        },
      )
      let settlement = @runtime.prepare_compiled_script_early_error(
        stmts,
        root_strict,
        provenance_token=Some(allocator.val.program_identity),
      )
      Some(
        @runtime.CompiledScriptPreparation::with_early_error_settlement(
          strict=root_strict,
          var_names=bytecode.function.env_var_hoist_names,
          function_names~,
          lexical_bindings~,
          settlement~,
        ),
      )
    }
    None => None
  }
  let program = {
    program_identity: allocator.val.program_identity,
    identity_authority,
    root,
    script_preparation,
  }
  verify_candidate_program(program)
  program
}

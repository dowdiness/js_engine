///|
using @runtime {
  type Callable,
  type Environment,
  type ExecContext,
  type FuncData,
  type FuncDataExt,
  type Interpreter,
  type PropDescriptor,
  type ProxyData,
  type Value,
}

///|
priv enum CompiledArg {
  Plain((Interpreter, ExecContext, Environment) -> Value raise Error)
  Spread(
    (Interpreter, ExecContext, Environment) -> Value raise Error,
    @token.Loc
  )
}

///|
/// Compile a supported expression into a MoonBit closure that evaluates that
/// expression against an interpreter, execution context, and lexical
/// environment.
///
/// The current tree-walking interpreter matches on `@ast.Expr` every time an
/// expression runs. This prototype performs that match once at compile time and
/// stores the chosen behavior in a closure, so hot execution paths invoke
/// already-selected code directly. The `ExecContext` is retained as an explicit
/// input so direct eval and strict function validation can preserve the caller's
/// strictness. Function expressions still capture the `Environment` passed to
/// the returned closure, matching `FuncData.closure` in the normal interpreter
/// path.
///
/// Limitations: this is an expression-only prototype. It supports literals,
/// identifiers, grouping, binary operators, functions, arrows, and bare calls.
/// It intentionally does not compile statements, member-call receivers,
/// assignment, object/array literals, `this`, classes, generators, or async
/// functions yet.
pub fn compile_expr_to_closure(
  expr : @ast.Expr,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  match expr {
    NumberLit(n, _, _) => fn(_, _, _) { Value::Number(n) }
    StringLit(s, _, _, _) => fn(_, _, _) { Value::String_(s) }
    BoolLit(b, _) => fn(_, _, _) { Value::Bool(b) }
    NullLit(_) => fn(_, _, _) { Value::Null }
    UndefinedLit(_) => fn(_, _, _) { Value::Undefined }
    Ident(name, _) => compile_ident(name)
    Grouping(inner, _) => compile_expr_to_closure(inner)
    Binary(op, left, right, loc) => {
      let left_fn = compile_expr_to_closure(left)
      let right_fn = compile_expr_to_closure(right)
      fn(interp, ctx, env) raise {
        eval_compiled_binary(interp, ctx, env, op, left_fn, right_fn, loc)
      }
    }
    FuncExpr(name, params, body, _) => compile_func_expr(name, params, body)
    FuncExprExt(name, params, rest_param, body, _) =>
      compile_func_expr_ext(name, params, rest_param, body)
    ArrowFunc(params, body, _) => compile_arrow_func(params, body)
    ArrowFuncExt(params, rest_param, body, _) =>
      compile_arrow_func_ext(params, rest_param, body)
    Call(callee, args, loc) => {
      let compiled_args = compile_args(args)
      if is_direct_eval_callee(callee) {
        fn(interp, ctx, env) raise {
          eval_compiled_direct_eval(interp, ctx, env, compiled_args, loc)
        }
      } else {
        let callee_fn = compile_expr_to_closure(callee)
        fn(interp, ctx, env) raise {
          let callee_value = callee_fn(interp, ctx, env)
          let values = eval_compiled_args(interp, ctx, env, compiled_args)
          interp.call_value(callee_value, Value::Undefined, values, loc)
        }
      }
    }
    _ => unsupported_expr("expression kind")
  }
}

///|
fn compile_ident(
  name : String,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(interp, _ctx, env) raise {
    env.get(name) catch {
      @errors.ReferenceError(_) =>
        match interp.global_this {
          Value::Object(data) =>
            match data.bag.properties.get(name) {
              Some(v) => v
              None =>
                raise @errors.ReferenceError(message="\{name} is not defined")
            }
          _ => raise @errors.ReferenceError(message="\{name} is not defined")
        }
      other => raise other
    }
  }
}

///|
fn compile_func_expr(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature(ctx.strict, name, params, body)
    let func_data : FuncData = {
      name,
      params,
      body,
      closure: env,
      strict: ctx.strict || @runtime.has_use_strict(body),
      has_name_binding: name is Some(_),
      is_method: false,
    }
    @runtime.make_func(func_data)
  }
}

///|
fn compile_func_expr_ext(
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature_ext(
      ctx.strict,
      name,
      params,
      rest_param,
      body,
    )
    let func_data : FuncDataExt = {
      name,
      params,
      rest_param,
      body,
      closure: env,
      strict: ctx.strict || @runtime.has_use_strict(body),
      has_name_binding: name is Some(_),
      is_method: false,
    }
    @runtime.make_func_ext(func_data)
  }
}

///|
fn compile_arrow_func(
  params : Array[String],
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature(ctx.strict, None, params, body)
    let func_data : FuncData = {
      name: None,
      params,
      body,
      closure: env,
      strict: ctx.strict || @runtime.has_use_strict(body),
      has_name_binding: false,
      is_method: false,
    }
    make_arrow_func(func_data, params.length())
  }
}

///|
fn compile_arrow_func_ext(
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature_ext(
      ctx.strict,
      None,
      params,
      rest_param,
      body,
    )
    let func_data : FuncDataExt = {
      name: None,
      params,
      rest_param,
      body,
      closure: env,
      strict: ctx.strict || @runtime.has_use_strict(body),
      has_name_binding: false,
      is_method: false,
    }
    make_arrow_func_ext(func_data, arrow_ext_length(params))
  }
}

///|
fn compile_args(args : Array[@ast.Expr]) -> Array[CompiledArg] {
  let compiled : Array[CompiledArg] = []
  for arg in args {
    match arg {
      SpreadExpr(inner, loc) =>
        compiled.push(Spread(compile_expr_to_closure(inner), loc))
      _ => compiled.push(Plain(compile_expr_to_closure(arg)))
    }
  }
  compiled
}

///|
fn eval_compiled_args(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  args : Array[CompiledArg],
) -> Array[Value] raise Error {
  let values : Array[Value] = []
  for arg in args {
    match arg {
      Plain(run) => values.push(run(interp, ctx, env))
      Spread(run, loc) => {
        let spread_values = interp.spread_iterable(run(interp, ctx, env), loc)
        for value in spread_values {
          values.push(value)
        }
      }
    }
  }
  values
}

///|
fn is_direct_eval_callee(expr : @ast.Expr) -> Bool {
  match expr {
    Ident("eval", _) => true
    Grouping(inner, _) => is_direct_eval_callee(inner)
    _ => false
  }
}

///|
fn eval_compiled_direct_eval(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  args : Array[CompiledArg],
  loc : @token.Loc,
) -> Value raise Error {
  let callee = env.get("eval") catch {
    _ => raise @errors.ReferenceError(message="eval is not defined")
  }
  let values = eval_compiled_args(interp, ctx, env, args)
  if is_global_eval_function(callee) {
    if values.length() == 0 {
      return Value::Undefined
    }
    match values[0] {
      Value::String_(code) =>
        interp.perform_eval(code, env, true, caller_strict=ctx.strict)
      other => other
    }
  } else {
    interp.call_value(callee, Value::Undefined, values, loc)
  }
}

///|
fn is_global_eval_function(value : Value) -> Bool {
  match value {
    Value::Object(data) =>
      match data.callable {
        Some(Callable::NonConstructableCallable("eval", _)) => true
        _ => false
      }
    _ => false
  }
}

///|
fn eval_compiled_binary(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  op : @ast.BinOp,
  left_fn : (Interpreter, ExecContext, Environment) -> Value raise Error,
  right_fn : (Interpreter, ExecContext, Environment) -> Value raise Error,
  loc : @token.Loc,
) -> Value raise Error {
  match op {
    And => {
      let left = left_fn(interp, ctx, env)
      if !@runtime.is_truthy(left) {
        left
      } else {
        right_fn(interp, ctx, env)
      }
    }
    Or => {
      let left = left_fn(interp, ctx, env)
      if @runtime.is_truthy(left) {
        left
      } else {
        right_fn(interp, ctx, env)
      }
    }
    NullishCoalesce => {
      let left = left_fn(interp, ctx, env)
      match left {
        Value::Null | Value::Undefined => right_fn(interp, ctx, env)
        _ => left
      }
    }
    In => {
      let left = left_fn(interp, ctx, env)
      let right = right_fn(interp, ctx, env)
      if @runtime.is_object_value(right) {
        Value::Bool(
          interp.has_property_key(
            right,
            @runtime.to_property_key(left, interp=Some(interp)),
          ),
        )
      } else {
        raise @errors.TypeError(
          message="Cannot use 'in' operator to search for '\{left.to_string()}' in \{@runtime.type_of(right)}",
        )
      }
    }
    Instanceof => {
      let left = left_fn(interp, ctx, env)
      let right = right_fn(interp, ctx, env)
      eval_compiled_instanceof(interp, left, right, loc)
    }
    _ => {
      let left = left_fn(interp, ctx, env)
      let right = right_fn(interp, ctx, env)
      @runtime.eval_binary_op(op, left, right, loc)
    }
  }
}

///|
fn eval_compiled_instanceof(
  interp : Interpreter,
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match right {
    Value::Object(_) => {
      let has_instance = interp.get_computed_property(
        right,
        Value::Symbol(@runtime.get_hasinstance_symbol()),
        loc,
      )
      match has_instance {
        Value::Null | Value::Undefined =>
          ordinary_compiled_instanceof(interp, left, right, loc)
        _ => {
          if !@runtime.is_callable(has_instance) {
            raise @errors.TypeError(
              message="Symbol.hasInstance is not a function",
            )
          }
          Value::Bool(
            @runtime.is_truthy(
              interp.call_value(has_instance, right, [left], loc),
            ),
          )
        }
      }
    }
    Value::Proxy(proxy_data) =>
      eval_compiled_proxy_instanceof(interp, left, right, proxy_data, loc)
    _ =>
      raise @errors.TypeError(
        message="Right-hand side of 'instanceof' is not an object",
      )
  }
}

///|
fn eval_compiled_proxy_instanceof(
  interp : Interpreter,
  left : Value,
  right : Value,
  proxy_data : ProxyData,
  loc : @token.Loc,
) -> Value raise Error {
  let target = @runtime.get_proxy_target(proxy_data)
  let proto = interp.get_property(right, "prototype", loc)
  match proto {
    Value::Object(_) => @runtime.instanceof_prototype_chain(left, proto, interp)
    _ =>
      match target {
        Value::Object(target_data) =>
          match target_data.callable {
            Some(_) => Value::Bool(false)
            None =>
              raise @errors.TypeError(
                message="Right-hand side of 'instanceof' is not callable",
              )
          }
        _ => Value::Bool(false)
      }
  }
}

///|
fn ordinary_compiled_instanceof(
  interp : Interpreter,
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> Value raise Error {
  if !@runtime.is_callable(right) {
    raise @errors.TypeError(
      message="Right-hand side of 'instanceof' is not callable",
    )
  }
  if !@runtime.is_object_value(left) {
    return Value::Bool(false)
  }
  match interp.get_property(right, "prototype", loc) {
    Value::Object(_) as proto =>
      @runtime.instanceof_prototype_chain(left, proto, interp)
    _ =>
      raise @errors.TypeError(
        message="Function has non-object prototype in instanceof check",
      )
  }
}

///|
fn make_arrow_func(data : FuncData, length : Int) -> Value {
  let nf_desc = non_writable_function_descriptor()
  Value::Object({
    bag: {
      properties: {
        "name": Value::String_(""),
        "length": Value::Number(length.to_double()),
      },
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: @runtime.get_func_proto(),
    callable: Some(Callable::ArrowFunc(data)),
    class_name: "Function",
    extensible: true,
  })
}

///|
fn make_arrow_func_ext(data : FuncDataExt, length : Int) -> Value {
  let nf_desc = non_writable_function_descriptor()
  Value::Object({
    bag: {
      properties: {
        "name": Value::String_(""),
        "length": Value::Number(length.to_double()),
      },
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: @runtime.get_func_proto(),
    callable: Some(Callable::ArrowFuncExt(data)),
    class_name: "Function",
    extensible: true,
  })
}

///|
fn non_writable_function_descriptor() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn arrow_ext_length(params : Array[@ast.Param]) -> Int {
  let mut length = 0
  for param in params {
    if param.default_val is Some(_) {
      break
    }
    length += 1
  }
  length
}

///|
fn unsupported_expr(
  kind : String,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, _, _) raise {
    raise @errors.InternalError(
      message="closure conversion prototype does not support \{kind}",
    )
  }
}

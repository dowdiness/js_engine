///|
using @runtime {
  type BindingKind,
  type Callable,
  type Environment,
  type ExecContext,
  type FuncDataExt,
  type Interpreter,
  type PropDescriptor,
  type ProxyData,
  type Signal,
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
priv struct CompiledBody(
  (Interpreter, ExecContext, Environment) -> Signal raise Error
)

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
/// Limitations: this is a prototype for benchmark exploration. It supports the
/// statement and expression subset needed by the closure-factory workloads, but
/// it intentionally does not compile classes, generators, async functions,
/// destructuring, object literals, `this`, or the full ECMAScript hoisting
/// surface yet.
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
    ArrayLit(elements, _) => compile_array_lit(elements)
    Assign(name, value_expr, _) => compile_assign(name, value_expr)
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
    Call(callee, args, loc) => compile_call(callee, args, loc)
    Member(obj, prop, loc) => {
      let obj_fn = compile_expr_to_closure(obj)
      fn(interp, ctx, env) raise {
        interp.get_property(obj_fn(interp, ctx, env), prop, loc)
      }
    }
    ComputedMember(obj, key, loc) => {
      let obj_fn = compile_expr_to_closure(obj)
      let key_fn = compile_expr_to_closure(key)
      fn(interp, ctx, env) raise {
        interp.get_computed_property(
          obj_fn(interp, ctx, env),
          key_fn(interp, ctx, env),
          loc,
        )
      }
    }
    UpdateExpr(op, operand, prefix, _) => compile_update(op, operand, prefix)
    _ => unsupported_expr("expression kind")
  }
}

///|
/// Compile a statement list into a reusable program closure.
///
/// This is intentionally opt-in for benchmarks. It does not replace
/// `Interpreter::run`; callers choose a prepared `Interpreter`, `ExecContext`,
/// and `Environment` so benchmark code can isolate parse, compile, and execute
/// costs explicitly.
pub fn compile_program_to_closure(
  stmts : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let body = compile_body(stmts)
  fn(interp, ctx, env) raise {
    reduce_program_signal((body.0)(interp, ctx, env))
  }
}

///|
/// Compile a script into a closure that runs with the same outer execution
/// envelope as `Interpreter::run`.
///
/// This wrapper keeps declaration hoisting, directive-prologue strictness,
/// static early-error checks, current-interpreter setup, and JS error wrapping
/// in the runtime package. The compiled body still avoids repeated AST matches
/// for the supported statement/expression subset during execution.
pub fn compile_script_to_closure(
  stmts : Array[@ast.Stmt],
) -> (Interpreter) -> Value raise Error {
  let program = compile_program_to_closure(stmts)
  fn(interp) raise {
    interp.run_compiled_script(stmts, fn(ctx, env) raise {
      program(interp, ctx, env)
    })
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
fn compile_array_lit(
  elements : Array[@ast.Expr],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled : Array[
    (Interpreter, ExecContext, Environment) -> Value raise Error,
  ] = []
  for element in elements {
    match element {
      ArrayHole(_) => compiled.push(fn(_, _, _) { Value::Undefined })
      SpreadExpr(_, _) => return unsupported_expr("array spread")
      _ => compiled.push(compile_expr_to_closure(element))
    }
  }
  fn(interp, ctx, env) raise {
    let values : Array[Value] = []
    for run in compiled {
      values.push(run(interp, ctx, env))
    }
    @runtime.make_array(values)
  }
}

///|
fn compile_assign(
  name : String,
  value_expr : @ast.Expr,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let value_fn = compile_expr_to_closure(value_expr)
  fn(interp, ctx, env) raise {
    let value = value_fn(interp, ctx, env)
    env.assign(name, value) catch {
      @errors.ReferenceError(_) =>
        if ctx.strict {
          raise @errors.ReferenceError(message="\{name} is not defined")
        } else {
          interp.global.def(name, value, BindingKind::VarBinding)
        }
      other => raise other
    }
    value
  }
}

///|
fn compile_update(
  op : @ast.UpdateOp,
  operand : @ast.Expr,
  prefix : Bool,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  match operand {
    Ident(name, _) =>
      fn(_, _, env) raise {
        let old = env.get(name)
        let old_num = @runtime.to_number(old)
        let new_value = match op {
          Increment => Value::Number(old_num + 1.0)
          Decrement => Value::Number(old_num - 1.0)
        }
        env.assign(name, new_value)
        if prefix {
          new_value
        } else {
          old
        }
      }
    _ => unsupported_expr("update target")
  }
}

///|
fn compile_call(
  callee : @ast.Expr,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled_args = compile_args(args)
  match callee {
    Member(obj_expr, prop, member_loc) => {
      let obj_fn = compile_expr_to_closure(obj_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let callee_value = interp.get_property(obj, prop, member_loc)
        let values = eval_compiled_args(interp, ctx, env, compiled_args)
        interp.call_value(callee_value, obj, values, loc)
      }
    }
    ComputedMember(obj_expr, key_expr, member_loc) => {
      let obj_fn = compile_expr_to_closure(obj_expr)
      let key_fn = compile_expr_to_closure(key_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let key = key_fn(interp, ctx, env)
        let callee_value = interp.get_computed_property(obj, key, member_loc)
        let values = eval_compiled_args(interp, ctx, env, compiled_args)
        interp.call_value(callee_value, obj, values, loc)
      }
    }
    _ =>
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
}

///|
fn compile_func_expr(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled_body = compile_body(body)
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature(ctx.strict, name, params, body)
    make_compiled_func(
      name,
      params,
      env,
      ctx.strict || @runtime.has_use_strict(body),
      compiled_body,
    )
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
  let compiled_body = compile_body(body)
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature(ctx.strict, None, params, body)
    make_compiled_arrow_func(
      params,
      env,
      ctx.strict || @runtime.has_use_strict(body),
      compiled_body,
    )
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
fn compile_body(stmts : Array[@ast.Stmt]) -> CompiledBody {
  let compiled : Array[
    (Interpreter, ExecContext, Environment) -> Signal raise Error,
  ] = []
  for stmt in stmts {
    compiled.push(compile_stmt(stmt))
  }
  CompiledBody(fn(interp, ctx, env) raise {
    let mut last = Value::Undefined
    for run in compiled {
      match run(interp, ctx, env) {
        Signal::Normal(value) => last = value
        sig => return sig
      }
    }
    Signal::Normal(last)
  })
}

///|
fn compile_stmt(
  stmt : @ast.Stmt,
) -> (Interpreter, ExecContext, Environment) -> Signal raise Error {
  match stmt {
    ExprStmt(expr, _) => {
      let expr_fn = compile_expr_to_closure(expr)
      fn(interp, ctx, env) raise { Signal::Normal(expr_fn(interp, ctx, env)) }
    }
    ReturnStmt(expr, _) => {
      let value_fn = match expr {
        Some(e) => compile_expr_to_closure(e)
        None => fn(_, _, _) { Value::Undefined }
      }
      fn(interp, ctx, env) raise {
        Signal::ReturnSignal(value_fn(interp, ctx, env))
      }
    }
    VarDecl(kind, name, init, _) => {
      let init_fn = match init {
        Some(expr) => compile_expr_to_closure(expr)
        None => fn(_, _, _) { Value::Undefined }
      }
      fn(interp, ctx, env) raise {
        let binding_kind = match kind {
          LetKind => BindingKind::LetBinding
          ConstKind => BindingKind::ConstBinding
          VarKind => BindingKind::VarBinding
        }
        let value = init_fn(interp, ctx, env)
        if binding_kind == BindingKind::VarBinding &&
          (env.bindings.contains(name) || env.has_var(name)) {
          if init is Some(_) {
            env.assign_var(name, value)
          }
        } else if (
            binding_kind == BindingKind::LetBinding ||
            binding_kind == BindingKind::ConstBinding
          ) &&
          env.bindings.contains(name) {
          env.initialize(name, value)
        } else {
          env.def(name, value, binding_kind)
        }
        Signal::Normal(Value::Undefined)
      }
    }
    IfStmt(cond, then_branch, else_branch, _) => {
      let cond_fn = compile_expr_to_closure(cond)
      let then_fn = compile_stmt(then_branch)
      let else_fn = match else_branch {
        Some(stmt) => Some(compile_stmt(stmt))
        None => None
      }
      fn(interp, ctx, env) raise {
        if @runtime.is_truthy(cond_fn(interp, ctx, env)) {
          then_fn(interp, ctx, env)
        } else {
          match else_fn {
            Some(run) => run(interp, ctx, env)
            None => Signal::Normal(Value::Undefined)
          }
        }
      }
    }
    Block(stmts, _) => {
      let body = compile_body(stmts)
      fn(interp, ctx, env) raise {
        let block_env = Environment::new(parent=Some(env))
        (body.0)(interp, ctx, block_env)
      }
    }
    StmtList(stmts, _) => {
      let body = compile_body(stmts)
      fn(interp, ctx, env) raise { (body.0)(interp, ctx, env) }
    }
    FuncDecl(name, params, body, _) => {
      let compiled_body = compile_body(body)
      fn(_interp, ctx, env) raise {
        @runtime.validate_function_signature(
          ctx.strict,
          Some(name),
          params,
          body,
        )
        let func = make_compiled_func(
          Some(name),
          params,
          env,
          ctx.strict || @runtime.has_use_strict(body),
          compiled_body,
        )
        if env.bindings.contains(name) || env.has_var(name) {
          env.assign_var(name, func)
        } else {
          env.def(name, func, BindingKind::VarBinding)
        }
        Signal::Normal(Value::Undefined)
      }
    }
    ForStmt(init, cond, update, body, _) => {
      let init_fn = match init {
        Some(stmt) => Some(compile_stmt(stmt))
        None => None
      }
      let cond_fn = match cond {
        Some(expr) => Some(compile_expr_to_closure(expr))
        None => None
      }
      let update_fn = match update {
        Some(expr) => Some(compile_expr_to_closure(expr))
        None => None
      }
      let body_fn = compile_stmt(body)
      fn(interp, ctx, env) raise {
        match init_fn {
          Some(run) =>
            match run(interp, ctx, env) {
              Signal::Normal(_) => ()
              sig => return sig
            }
          None => ()
        }
        let mut completion = Value::Undefined
        while true {
          match cond_fn {
            Some(run) => if !@runtime.is_truthy(run(interp, ctx, env)) { break }
            None => ()
          }
          match body_fn(interp, ctx, env) {
            Signal::Normal(value) => completion = value
            Signal::ReturnSignal(_) as sig => return sig
            Signal::BreakSignal(value, None) => {
              completion = value.unwrap_or(completion)
              break
            }
            Signal::ContinueSignal(value, None) =>
              completion = value.unwrap_or(completion)
            sig => return sig
          }
          match update_fn {
            Some(run) => {
              let _ = run(interp, ctx, env)
            }
            None => ()
          }
        }
        Signal::Normal(completion)
      }
    }
    _ => unsupported_stmt("statement kind")
  }
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
fn make_compiled_func(
  name : String?,
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body : CompiledBody,
) -> Value {
  let func_name = match name {
    Some(n) => n
    None => ""
  }
  @runtime.make_interp_method_func(name=func_name, length=params.length(), fn(
    interp,
    this_val,
    args,
  ) raise {
    call_compiled_func(interp, this_val, args, params, closure, strict, body)
  })
}

///|
fn make_compiled_arrow_func(
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body : CompiledBody,
) -> Value {
  @runtime.make_interp_method_func(name="", length=params.length(), fn(
    interp,
    _this_val,
    args,
  ) raise {
    call_compiled_arrow_func(interp, args, params, closure, strict, body)
  })
}

///|
fn call_compiled_func(
  interp : Interpreter,
  this_val : Value,
  args : Array[Value],
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body : CompiledBody,
) -> Value raise Error {
  let saved_in_default = interp.in_nonarrow_param_default_eval
  interp.in_nonarrow_param_default_eval = false
  let result : Value = try {
    let func_env = Environment::new(parent=Some(closure))
    func_env.is_var_scope = true
    let func_ctx : ExecContext = { strict, current_generator: None }
    let effective_this = if strict {
      this_val
    } else {
      match this_val {
        Value::Undefined | Value::Null => interp.global_this
        _ => this_val
      }
    }
    func_env.def("this", effective_this, BindingKind::LetBinding)
    func_env.def("<new.target>", Value::Undefined, BindingKind::LetBinding)
    bind_simple_params(func_env, params, args)
    reduce_body_signal((body.0)(interp, func_ctx, func_env))
  } catch {
    err => {
      interp.in_nonarrow_param_default_eval = saved_in_default
      raise err
    }
  }
  interp.in_nonarrow_param_default_eval = saved_in_default
  result
}

///|
fn call_compiled_arrow_func(
  interp : Interpreter,
  args : Array[Value],
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body : CompiledBody,
) -> Value raise Error {
  let saved_in_default = interp.in_nonarrow_param_default_eval
  interp.in_nonarrow_param_default_eval = false
  let result : Value = try {
    let func_env = Environment::new(parent=Some(closure))
    func_env.is_var_scope = true
    let func_ctx : ExecContext = { strict, current_generator: None }
    bind_simple_params(func_env, params, args)
    reduce_body_signal((body.0)(interp, func_ctx, func_env))
  } catch {
    err => {
      interp.in_nonarrow_param_default_eval = saved_in_default
      raise err
    }
  }
  interp.in_nonarrow_param_default_eval = saved_in_default
  result
}

///|
fn bind_simple_params(
  env : Environment,
  params : Array[String],
  args : Array[Value],
) -> Unit raise Error {
  for i = 0; i < params.length(); i = i + 1 {
    let value = if i < args.length() { args[i] } else { Value::Undefined }
    if env.bindings.contains(params[i]) {
      env.assign(params[i], value)
    } else {
      env.def_parameter(params[i], value)
    }
  }
}

///|
fn reduce_body_signal(signal : Signal) -> Value raise Error {
  match signal {
    Signal::Normal(_) => Value::Undefined
    Signal::ReturnSignal(value) => value
    Signal::BreakSignal(_, _) =>
      raise @errors.SyntaxError(message="break statement outside of loop")
    Signal::ContinueSignal(_, _) =>
      raise @errors.SyntaxError(message="continue statement outside of loop")
  }
}

///|
fn reduce_program_signal(signal : Signal) -> Value raise Error {
  match signal {
    Signal::Normal(value) => value
    Signal::ReturnSignal(_) =>
      raise @errors.SyntaxError(message="return statement outside of function")
    Signal::BreakSignal(_, _) =>
      raise @errors.SyntaxError(message="break statement outside of loop")
    Signal::ContinueSignal(_, _) =>
      raise @errors.SyntaxError(message="continue statement outside of loop")
  }
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

///|
fn unsupported_stmt(
  kind : String,
) -> (Interpreter, ExecContext, Environment) -> Signal raise Error {
  fn(_, _, _) raise {
    raise @errors.InternalError(
      message="closure conversion prototype does not support \{kind}",
    )
  }
}

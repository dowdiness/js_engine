// Executor-neutral function activation seam. Runtime owns observable function
// setup and completion normalization; executor packages supply only opaque code
// and private resumable frames. A frame step may advance guest execution, but
// it cannot return a host-language continuation or expose executor state.

///|
pub enum ExecutorActivationStep {
  ExecutorActivationContinue
  ExecutorActivationNormal(Value)
  ExecutorActivationReturn(Value)
}

///|
pub fn executor_activation_continue() -> ExecutorActivationStep {
  ExecutorActivationContinue
}

///|
pub fn executor_activation_normal(value : Value) -> ExecutorActivationStep {
  ExecutorActivationNormal(value)
}

///|
pub fn executor_activation_return(value : Value) -> ExecutorActivationStep {
  ExecutorActivationReturn(value)
}

///|
pub struct PreparedExecutorActivation {
  ctx : ExecContext
  env : Environment
  args : Array[Value]
}

///|
fn PreparedExecutorActivation::PreparedExecutorActivation(
  ctx~ : ExecContext,
  env~ : Environment,
  args~ : Array[Value],
) -> PreparedExecutorActivation {
  { ctx, env, args: args.copy() }
}

///|
pub fn PreparedExecutorActivation::context(
  self : PreparedExecutorActivation,
) -> ExecContext {
  self.ctx
}

///|
pub fn PreparedExecutorActivation::environment(
  self : PreparedExecutorActivation,
) -> Environment {
  self.env
}

///|
pub fn PreparedExecutorActivation::arguments(
  self : PreparedExecutorActivation,
) -> Array[Value] {
  self.args.copy()
}

///|
pub(open) trait ExecutorActivationFrame {
  fn step(Self, Interpreter) -> ExecutorActivationStep raise Error
}

///|
pub(open) trait ExecutorCode {
  fn start(Self, Interpreter, PreparedExecutorActivation) -> &ExecutorActivationFrame raise Error
}

///|
fn Interpreter::drive_executor_activation(
  self : Interpreter,
  code : &ExecutorCode,
  prepared : PreparedExecutorActivation,
) -> ExecutorActivationStep raise Error {
  let frame = code.start(self, prepared)
  while true {
    match frame.step(self) {
      ExecutorActivationContinue => ()
      ExecutorActivationNormal(value) => return ExecutorActivationNormal(value)
      ExecutorActivationReturn(value) => return ExecutorActivationReturn(value)
    }
  }
  ExecutorActivationNormal(Undefined)
}

///|
fn bind_executor_parameters(
  env : Environment,
  params : Array[String],
  args : Array[Value],
) -> Unit raise Error {
  for i, param in params {
    let value = if i < args.length() { args[i] } else { Undefined }
    if env.bindings.contains(param) {
      env.assign(param, value)
    } else {
      env.def_parameter(param, value)
    }
  }
}

///|
fn bind_executor_rest_parameter(
  env : Environment,
  positional_count : Int,
  rest_param : String?,
  args : Array[Value],
) -> Unit raise Error {
  match rest_param {
    Some(name) => {
      let rest : Array[Value] = []
      for i = positional_count; i < args.length(); i = i + 1 {
        rest.push(args[i])
      }
      env.def_parameter(name, make_array(rest))
    }
    None => ()
  }
}

///|
fn Interpreter::prepare_executor_activation(
  self : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  params : Array[String],
  rest_param : String?,
  closure : Environment,
  strict : Bool,
  new_target : Value?,
  is_method : Bool,
  self_name : String?,
  define_arguments_object : Bool,
) -> PreparedExecutorActivation raise Error {
  let ctx : ExecContext = { strict, current_generator: None }
  let env = Environment::new(parent=Some(closure))
  env.is_var_scope = true
  env.def_builtin("[[EvalMethodContext]]", Bool(is_method))
  let effective_this = if strict {
    this_value
  } else {
    self.normalize_sloppy_this(this_value)
  }
  env.def("this", effective_this, LetBinding)
  env.def("<new.target>", new_target.unwrap_or(Undefined), LetBinding)
  bind_executor_parameters(env, params, args)
  bind_executor_rest_parameter(env, params.length(), rest_param, args)
  if define_arguments_object && !params_include_arguments(params, rest_param) {
    match rest_param {
      Some(_) =>
        self.define_unmapped_arguments_object(env, args, callee, strict)
      None =>
        self.define_simple_arguments_object(env, args, callee, strict, params)
    }
  }
  match self_name {
    Some(name) if !env.bindings.contains(name) =>
      env.def(name, callee, FunctionNameBinding)
    _ => ()
  }
  PreparedExecutorActivation(ctx~, env~, args~)
}

///|
fn executor_call_completion(step : ExecutorActivationStep) -> Value {
  match step {
    ExecutorActivationContinue => Undefined
    ExecutorActivationNormal(_) => Undefined
    ExecutorActivationReturn(value) => value
  }
}

///|
fn executor_construct_completion(
  step : ExecutorActivationStep,
  instance : Value,
) -> Value {
  match step {
    ExecutorActivationReturn(value) if is_object_like_for_constructor_return(
        value,
      ) => value
    ExecutorActivationContinue
    | ExecutorActivationNormal(_)
    | ExecutorActivationReturn(_) => instance
  }
}

///|
fn Interpreter::run_executor_function(
  self : Interpreter,
  code : &ExecutorCode,
  callee : Value,
  context : CallContext,
  this_value : Value,
  args : Array[Value],
  params : Array[String],
  rest_param : String?,
  closure : Environment,
  strict : Bool,
  is_method : Bool,
  self_name : String?,
  define_arguments_object : Bool,
) -> Value raise Error {
  let saved_in_default = self.in_nonarrow_param_default_eval
  self.in_nonarrow_param_default_eval = false
  let result : Value = try {
    if context.is_constructing() {
      let new_target = context.new_target().unwrap_or(callee)
      let proto = self.get_prototype_from_constructor(
        new_target,
        @token.Loc::default(),
      )
      let instance = make_constructor_instance(proto, "Object")
      let prepared = self.prepare_executor_activation(
        callee,
        instance,
        args,
        params,
        rest_param,
        closure,
        strict,
        Some(new_target),
        is_method,
        self_name,
        define_arguments_object,
      )
      executor_construct_completion(
        self.drive_executor_activation(code, prepared),
        instance,
      )
    } else {
      let prepared = self.prepare_executor_activation(
        callee,
        this_value,
        args,
        params,
        rest_param,
        closure,
        strict,
        None,
        is_method,
        self_name,
        define_arguments_object,
      )
      executor_call_completion(self.drive_executor_activation(code, prepared))
    }
  } catch {
    error => {
      self.in_nonarrow_param_default_eval = saved_in_default
      raise error
    }
  }
  self.in_nonarrow_param_default_eval = saved_in_default
  result
}

///|
pub fn[T : ExecutorCode] make_executor_function(
  name : String?,
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : T,
  rest_param? : String? = None,
  constructable? : Bool = true,
  call_self_name? : Bool = false,
  define_arguments_object? : Bool = true,
) -> Value {
  let realm_state = match closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => closure.realm_state
  }
  let function_name = name.unwrap_or("")
  let self_name = if call_self_name { name } else { None }
  let executable = code as &ExecutorCode
  let function_ref : Ref[Value?] = { val: None }
  let function = build_func_object(
    function_name,
    params.length(),
    InterpreterCallableWithContext(function_name, fn(
      interp,
      context,
      this_value,
      args,
    ) raise {
      interp.run_executor_function(
        executable,
        function_ref.val.unwrap_or(Undefined),
        context,
        this_value,
        args,
        params,
        rest_param,
        closure,
        strict,
        !constructable,
        self_name,
        define_arguments_object,
      )
    }),
    realm_state~,
  )
  function_ref.val = Some(function)
  if constructable {
    let prototype = make_constructor_instance(
      get_obj_proto(realm_state~),
      "Object",
    )
    match function {
      Object(function_data) => {
        function_data.bag.properties["prototype"] = prototype
        function_data.bag.descriptors["prototype"] = {
          writable: true,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        }
      }
      _ => ()
    }
    match prototype {
      Object(prototype_data) => {
        prototype_data.bag.properties["constructor"] = function
        prototype_data.bag.descriptors["constructor"] = {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        }
      }
      _ => ()
    }
  }
  function
}

// Executor-neutral function activation seam. Runtime owns observable function
// setup and completion normalization; executor packages supply only opaque code
// and private resumable frames. The neutral step surface returns neither a
// host-language continuation nor executor state. Until #631 migrates nested
// guest entry, individual executor steps may still cross the documented
// synchronous compatibility boundary; no stack-safety claim covers those
// operations.

///|
pub enum ExecutorActivationStep {
  ExecutorActivationContinue
  ExecutorActivationNormal(Value)
  ExecutorActivationReturn(Value)
  ExecutorActivationCall(ExecutorCallRequest)
}

///|
// A closed ordinary-call request. Runtime owns the request fields and the
// coordinator is the only code that may inspect them; executors only create a
// request and later consume its one-shot result through their frame.
pub struct ExecutorCallRequest {
  priv callee : Value
  priv this_value : Value
  priv args : Array[Value]
  priv loc : @token.Loc
}

///|
fn ExecutorCallRequest::ExecutorCallRequest(
  callee~ : Value,
  this_value~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorCallRequest {
  { callee, this_value, args: args.copy(), loc }
}

///|
pub fn executor_activation_call(
  callee : Value,
  this_value : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationCall(ExecutorCallRequest(callee~, this_value~, args~, loc~))
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
) -> ArrayView[Value] {
  self.args.view()
}

///|
pub(open) trait ExecutorActivationFrame {
  fn step(Self, Interpreter) -> ExecutorActivationStep raise Error
  fn deliver_call_result(Self, Value) -> Unit raise Error
}

///|
pub(open) trait ExecutorCode {
  fn start(Self, Interpreter, PreparedExecutorActivation) -> &ExecutorActivationFrame raise Error
}

///|
priv enum ExecutorCallableKind {
  OrdinaryExecutorCallable
  ArrowExecutorCallable
}

///|
// Runtime-owned metadata for a callable executor body. The code capability is
// mode-neutral and remains recoverable before entry so a managed dispatcher can
// start the private executor frame without invoking a final-value callback.
pub struct ExecutorCallableData {
  priv name : String
  priv params : Array[String]
  priv closure : Environment
  priv strict : Bool
  priv code : &ExecutorCode
  priv rest_param : String?
  priv constructable : Bool
  priv self_name : String?
  priv define_arguments_object : Bool
  priv kind : ExecutorCallableKind
}

///|
pub fn ExecutorCallableData::name(self : ExecutorCallableData) -> String {
  self.name
}

///|
pub fn ExecutorCallableData::length(self : ExecutorCallableData) -> Int {
  self.params.length()
}

///|
pub fn ExecutorCallableData::is_constructable(
  self : ExecutorCallableData,
) -> Bool {
  self.constructable
}

///|
pub fn ExecutorCallableData::start_frame(
  self : ExecutorCallableData,
  interp : Interpreter,
  prepared : PreparedExecutorActivation,
) -> &ExecutorActivationFrame raise Error {
  self.code.start(interp, prepared)
}

///|
priv struct ExecutorActivationCleanup {
  observation : ActivationObservationToken
  cleared_realm : ClearedActiveCalleeRealmScope
  active_realm : ActiveCalleeRealmValueScope
  saved_in_default : Bool
  saved_param_default_conflicts : @set.Set[String]?
}

///|
priv struct ExecutorActivationStackEntry {
  frame : &ExecutorActivationFrame
  kind : ExecutorCallableKind?
  cleanup : ExecutorActivationCleanup?
}

///|
fn Interpreter::restore_executor_activation_resources(
  self : Interpreter,
  cleared_realm : ClearedActiveCalleeRealmScope,
  active_realm : ActiveCalleeRealmValueScope,
  saved_in_default : Bool,
  saved_param_default_conflicts : @set.Set[String]?,
  failure : Error?,
) -> Unit {
  self.in_nonarrow_param_default_eval = saved_in_default
  self.param_default_eval_var_conflicts = saved_param_default_conflicts
  finish_active_callee_realm_value(self.realm_state, active_realm, failure~)
  finish_cleared_active_callee_realm(self.realm_state, cleared_realm)
}

///|
fn Interpreter::finish_executor_activation(
  self : Interpreter,
  cleanup : ExecutorActivationCleanup,
  failure : Error?,
) -> Unit raise Error {
  self.restore_executor_activation_resources(
    cleanup.cleared_realm,
    cleanup.active_realm,
    cleanup.saved_in_default,
    cleanup.saved_param_default_conflicts,
    failure,
  )
  cleanup.observation.release() catch {
    InvalidActivationObservationTransition(message) =>
      raise @errors.InternalError(
        message="executor activation release is invalid: " + message,
      )
  }
}

///|
fn reject_executor_activation_observation(
  attempt : ActivationEntryAttempt,
) -> Unit raise Error {
  attempt.reject() catch {
    InvalidActivationObservationTransition(message) =>
      raise @errors.InternalError(
        message="executor activation rejection is invalid: " + message,
      )
  }
}

///|
fn release_rejected_executor_activation_observation(
  attempt : ActivationEntryAttempt,
) -> Unit raise Error {
  attempt.release_after_rejection() catch {
    InvalidActivationObservationTransition(message) =>
      raise @errors.InternalError(
        message="executor rejected activation release is invalid: " + message,
      )
  }
}

///|
fn observe_executor_activation_entry(
  interp : Interpreter,
) -> ActivationEntryAttempt raise Error {
  observe_activation_entry(
    interp.execution_control_activation_observation_port(),
  )
}

///|
fn Interpreter::start_executor_activation(
  self : Interpreter,
  executable : ExecutorCallableData,
  request : ExecutorCallRequest,
) -> ExecutorActivationStackEntry raise Error {
  let observation = observe_executor_activation_entry(self)
  let cleared_realm = begin_cleared_active_callee_realm(self.realm_state)
  let active_realm = begin_active_callee_realm_value(
    self.realm_state,
    request.callee,
  )
  let saved_in_default = self.in_nonarrow_param_default_eval
  let saved_param_default_conflicts = self.param_default_eval_var_conflicts
  self.in_nonarrow_param_default_eval = false
  self.param_default_eval_var_conflicts = None
  let setup : Result[&ExecutorActivationFrame, Error] = Ok(
    {
      let prepared = self.prepare_executor_callable_call(
        executable,
        request.callee,
        request.this_value,
        request.args,
      )
      executable.start_frame(self, prepared)
    },
  ) catch {
    error => Err(error)
  }
  match setup {
    Err(error) => {
      reject_executor_activation_observation(observation)
      self.restore_executor_activation_resources(
        cleared_realm,
        active_realm,
        saved_in_default,
        saved_param_default_conflicts,
        Some(error),
      )
      release_rejected_executor_activation_observation(observation)
      raise error
    }
    Ok(frame) => {
      let accepted = observation.accept()
      {
        frame,
        kind: Some(executable.kind),
        cleanup: Some({
          observation: accepted,
          cleared_realm,
          active_realm,
          saved_in_default,
          saved_param_default_conflicts,
        }),
      }
    }
  }
}

///|
fn Interpreter::complete_executor_child(
  self : Interpreter,
  stack : Array[ExecutorActivationStackEntry],
  step : ExecutorActivationStep,
) -> Unit raise Error {
  let entry = stack.pop().unwrap()
  let completion = match entry.kind {
    Some(kind) => executor_call_completion(kind, step)
    None => Undefined
  }
  match entry.cleanup {
    Some(cleanup) => self.finish_executor_activation(cleanup, None)
    None => ()
  }
  let parent = stack[stack.length() - 1].frame
  parent.deliver_call_result(completion)
}

///|
// Drive one root executor frame and every exact executor-backed ordinary call
// it requests. The root is top-level script state and therefore has no
// activation observation or cleanup record of its own.
pub fn Interpreter::run_executor_activation_coordinator(
  self : Interpreter,
  root : &ExecutorActivationFrame,
) -> ExecutorActivationStep raise Error {
  let stack : Array[ExecutorActivationStackEntry] = [
    { frame: root, kind: None, cleanup: None },
  ]
  try {
    while true {
      guard !stack.is_empty() else {
        return ExecutorActivationNormal(Undefined)
      }
      let index = stack.length() - 1
      let frame = stack[index].frame
      match frame.step(self) {
        ExecutorActivationContinue => ()
        ExecutorActivationNormal(value) =>
          if index == 0 {
            return ExecutorActivationNormal(value)
          } else {
            self.complete_executor_child(stack, ExecutorActivationNormal(value))
          }
        ExecutorActivationReturn(value) =>
          if index == 0 {
            return ExecutorActivationReturn(value)
          } else {
            self.complete_executor_child(stack, ExecutorActivationReturn(value))
          }
        ExecutorActivationCall(request) =>
          match request.callee {
            Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
              stack.push(self.start_executor_activation(executable, request))
            _ => {
              let value = self.call_value(
                request.callee,
                request.this_value,
                request.args,
                request.loc,
              )
              frame.deliver_call_result(value)
            }
          }
      }
    }
  } catch {
    error => {
      while stack.length() > 1 {
        let entry = stack.pop().unwrap()
        match entry.cleanup {
          Some(cleanup) => self.finish_executor_activation(cleanup, Some(error))
          None => ()
        }
      }
      raise error
    }
  }
  ExecutorActivationNormal(Undefined)
}

///|
// Prepare an ordinary call without entering executor code. This is the
// hand-off used by a managed dispatcher: runtime owns observable activation
// semantics, while the caller may push the private frame returned by
// `start_frame` instead of invoking the synchronous compatibility adapter.
pub fn Interpreter::prepare_executor_callable_call(
  self : Interpreter,
  executable : ExecutorCallableData,
  callee : Value,
  this_value : Value,
  args : Array[Value],
) -> PreparedExecutorActivation raise Error {
  match executable.kind {
    OrdinaryExecutorCallable =>
      self.prepare_executor_activation(
        callee,
        this_value,
        args,
        executable.params,
        executable.rest_param,
        executable.closure,
        executable.strict,
        None,
        !executable.constructable,
        executable.self_name,
        executable.define_arguments_object,
      )
    ArrowExecutorCallable => prepare_executor_arrow_activation(executable, args)
  }
}

///|
fn Interpreter::drive_executor_activation(
  self : Interpreter,
  code : &ExecutorCode,
  prepared : PreparedExecutorActivation,
) -> ExecutorActivationStep raise Error {
  let frame = code.start(self, prepared)
  self.run_executor_activation_coordinator(frame)
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
fn prepare_executor_arrow_activation(
  executable : ExecutorCallableData,
  args : Array[Value],
) -> PreparedExecutorActivation raise Error {
  let ctx : ExecContext = { strict: executable.strict, current_generator: None }
  let env = Environment::new(parent=Some(executable.closure))
  env.is_var_scope = true
  bind_executor_parameters(env, executable.params, args)
  bind_executor_rest_parameter(
    env,
    executable.params.length(),
    executable.rest_param,
    args,
  )
  PreparedExecutorActivation(ctx~, env~, args~)
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
fn executor_call_completion(
  kind : ExecutorCallableKind,
  step : ExecutorActivationStep,
) -> Value {
  match kind {
    OrdinaryExecutorCallable =>
      match step {
        ExecutorActivationContinue => Undefined
        ExecutorActivationNormal(_) => Undefined
        ExecutorActivationReturn(value) => value
        ExecutorActivationCall(_) => Undefined
      }
    ArrowExecutorCallable =>
      match step {
        ExecutorActivationContinue => Undefined
        ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
          value
        ExecutorActivationCall(_) => Undefined
      }
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
    | ExecutorActivationReturn(_)
    | ExecutorActivationCall(_) => instance
  }
}

///|
fn Interpreter::run_executor_function(
  self : Interpreter,
  executable : ExecutorCallableData,
  callee : Value,
  context : CallContext,
  this_value : Value,
  args : Array[Value],
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
        executable.params,
        executable.rest_param,
        executable.closure,
        executable.strict,
        Some(new_target),
        !executable.constructable,
        executable.self_name,
        executable.define_arguments_object,
      )
      executor_construct_completion(
        self.drive_executor_activation(executable.code, prepared),
        instance,
      )
    } else {
      let prepared = self.prepare_executor_callable_call(
        executable, callee, this_value, args,
      )
      executor_call_completion(
        executable.kind,
        self.drive_executor_activation(executable.code, prepared),
      )
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
  let executable : ExecutorCallableData = {
    name: function_name,
    params: params.copy(),
    closure,
    strict,
    code: code as &ExecutorCode,
    rest_param,
    constructable,
    self_name,
    define_arguments_object,
    kind: OrdinaryExecutorCallable,
  }
  let function = build_func_object(
    function_name,
    params.length(),
    ExecutorCallable(executable),
    realm_state~,
  )
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

///|
pub fn[T : ExecutorCode] make_executor_arrow_function(
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : T,
  rest_param? : String? = None,
) -> Value {
  let realm_state = match closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => closure.realm_state
  }
  let executable : ExecutorCallableData = {
    name: "",
    params: params.copy(),
    closure,
    strict,
    code: code as &ExecutorCode,
    rest_param,
    constructable: false,
    self_name: None,
    define_arguments_object: false,
    kind: ArrowExecutorCallable,
  }
  build_func_object(
    "",
    params.length(),
    ExecutorCallable(executable),
    realm_state~,
  )
}

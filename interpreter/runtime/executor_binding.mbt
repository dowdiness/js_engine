///|
// Runtime-owned name resolution for bytecode instructions whose environment
// chain may contain a live `with` object. Ordinary lexical and global paths
// stay on their existing synchronous helpers; this request is created only
// when a dynamic environment is present.
priv enum ExecutorBindingOperation {
  ExecutorBindingLoad
  ExecutorBindingAssignmentLoad
  ExecutorBindingStore(Value)
  ExecutorBindingTypeof
  ExecutorBindingDirectEvalCallee
}

///|
pub struct ExecutorBindingRequest {
  priv ctx : ExecContext
  priv env : Environment
  priv name : String
  priv operation : ExecutorBindingOperation
  priv loc : @token.Loc
}

///|
fn ExecutorBindingRequest::ExecutorBindingRequest(
  ctx~ : ExecContext,
  env~ : Environment,
  name~ : String,
  operation~ : ExecutorBindingOperation,
  loc~ : @token.Loc,
) -> ExecutorBindingRequest {
  { ctx, env, name, operation, loc }
}

///|
pub enum ExecutorBindingStart {
  ExecutorBindingCompleted(Value)
  ExecutorBindingSuspended(ExecutorBindingRequest)
}

///|
fn environment_requires_managed_binding(
  env : Environment,
  name : String,
) -> Bool {
  match env.with_object {
    Some(_) => true
    None =>
      match env.bindings.get(name) {
        Some(_) => false
        None =>
          match env.parent {
            Some(parent) => environment_requires_managed_binding(parent, name)
            None => false
          }
      }
  }
}

///|
fn executor_binding_global_value(
  interp : Interpreter,
  name : String,
) -> Value raise Error {
  match interp.global_this {
    Object(data) =>
      match data.bag.properties.get(name) {
        Some(value) => value
        None => raise @errors.ReferenceError(message="{name} is not defined")
      }
    _ => raise @errors.ReferenceError(message="{name} is not defined")
  }
}

///|
fn executor_binding_unresolved(
  interp : Interpreter,
  request : ExecutorBindingRequest,
) -> Value raise Error {
  match request.operation {
    ExecutorBindingLoad => executor_binding_global_value(interp, request.name)
    ExecutorBindingAssignmentLoad | ExecutorBindingDirectEvalCallee =>
      raise @errors.ReferenceError(message="{request.name} is not defined")
    ExecutorBindingTypeof =>
      match interp.global_this {
        Object(data) =>
          match data.bag.properties.get(request.name) {
            Some(value) => String_(type_of(value))
            None => String_("undefined")
          }
        _ => String_("undefined")
      }
    ExecutorBindingStore(value) => {
      if request.ctx.strict {
        raise @errors.ReferenceError(message="{request.name} is not defined")
      }
      interp.global.def(request.name, value, VarBinding)
      interp.mirror_to_global(request.name, value, configurable=true)
      value
    }
  }
}

///|
fn executor_binding_synchronous(
  interp : Interpreter,
  request : ExecutorBindingRequest,
) -> Value raise Error {
  match request.operation {
    ExecutorBindingLoad => interp.get_compiled_name(request.env, request.name)
    ExecutorBindingAssignmentLoad =>
      get_assignment_name_value(request.ctx, request.env, request.name)
    ExecutorBindingStore(value) =>
      interp.assign_compiled_name(request.ctx, request.env, request.name, value)
    ExecutorBindingTypeof =>
      interp.typeof_compiled_name(request.ctx, request.env, request.name)
    ExecutorBindingDirectEvalCallee => load_direct_eval_callee(request.env)
  }
}

///|
fn begin_executor_binding_operation(
  interp : Interpreter,
  request : ExecutorBindingRequest,
) -> ExecutorBindingStart raise Error {
  match request.operation {
    ExecutorBindingStore(value) => {
      @static_semantics.validate_strict_assignment_target_name(
        request.ctx.strict,
        request.name,
      )
      if interp.is_immutable_global(request.name) {
        if request.ctx.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '{request.name}' of object '[object global]'",
          )
        }
        return ExecutorBindingCompleted(value)
      }
    }
    ExecutorBindingAssignmentLoad =>
      @static_semantics.validate_strict_assignment_target_name(
        request.ctx.strict,
        request.name,
      )
    ExecutorBindingTypeof =>
      @static_semantics.validate_strict_identifier_reference(
        request.ctx.strict,
        request.name,
      )
    _ => ()
  }
  if !environment_requires_managed_binding(request.env, request.name) {
    return ExecutorBindingCompleted(
      executor_binding_synchronous(interp, request),
    )
  }
  ExecutorBindingSuspended(request)
}

///|
pub fn begin_executor_binding_load(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  loc : @token.Loc,
) -> ExecutorBindingStart raise Error {
  begin_executor_binding_operation(
    interp,
    ExecutorBindingRequest(
      ctx~,
      env~,
      name~,
      operation=ExecutorBindingLoad,
      loc~,
    ),
  )
}

///|
pub fn begin_executor_binding_assignment_load(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  loc : @token.Loc,
) -> ExecutorBindingStart raise Error {
  begin_executor_binding_operation(
    interp,
    ExecutorBindingRequest(
      ctx~,
      env~,
      name~,
      operation=ExecutorBindingAssignmentLoad,
      loc~,
    ),
  )
}

///|
pub fn begin_executor_binding_store(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  value : Value,
  loc : @token.Loc,
) -> ExecutorBindingStart raise Error {
  begin_executor_binding_operation(
    interp,
    ExecutorBindingRequest(
      ctx~,
      env~,
      name~,
      operation=ExecutorBindingStore(value),
      loc~,
    ),
  )
}

///|
pub fn begin_executor_binding_typeof(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  loc : @token.Loc,
) -> ExecutorBindingStart raise Error {
  begin_executor_binding_operation(
    interp,
    ExecutorBindingRequest(
      ctx~,
      env~,
      name~,
      operation=ExecutorBindingTypeof,
      loc~,
    ),
  )
}

///|
pub fn begin_executor_binding_direct_eval(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  loc : @token.Loc,
) -> ExecutorBindingStart raise Error {
  begin_executor_binding_operation(
    interp,
    ExecutorBindingRequest(
      ctx~,
      env~,
      name="eval",
      operation=ExecutorBindingDirectEvalCallee,
      loc~,
    ),
  )
}

///|
priv enum ExecutorBindingPhase {
  ExecutorBindingNeedEnvironment(Environment)
  ExecutorBindingAwaitHas(
    Environment,
    Value,
    Bool,
    ExecutorDeleteHasPropertyOperation
  )
  ExecutorBindingAwaitUnscopables(Environment, Value, Bool)
  ExecutorBindingHaveUnscopables(Environment, Value, Bool, Value)
  ExecutorBindingAwaitUnscopablesName(Environment, Value, Bool)
  ExecutorBindingHaveUnscopablesName(Environment, Value, Bool, Value)
  ExecutorBindingAwaitGet
  ExecutorBindingHaveGet(Value)
  ExecutorBindingAwaitSet
  ExecutorBindingComplete(Value)
  ExecutorBindingDone
}

///|
priv struct ExecutorBindingFrame {
  request : ExecutorBindingRequest
  mut phase : ExecutorBindingPhase
}

///|
fn ExecutorBindingFrame::ExecutorBindingFrame(
  request : ExecutorBindingRequest,
) -> ExecutorBindingFrame {
  { request, phase: ExecutorBindingNeedEnvironment(request.env) }
}

///|
fn ExecutorBindingFrame::parent_or_unresolved(
  self : ExecutorBindingFrame,
  env : Environment,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match env.parent {
    Some(parent) => {
      self.phase = ExecutorBindingNeedEnvironment(parent)
      ExecutorActivationContinue
    }
    None => {
      let value = executor_binding_unresolved(interp, self.request)
      self.phase = ExecutorBindingComplete(value)
      ExecutorActivationNormal(value)
    }
  }
}

///|
fn ExecutorBindingFrame::finish_with_object(
  self : ExecutorBindingFrame,
  obj : Value,
  had_own : Bool,
) -> ExecutorActivationStep raise Error {
  match self.request.operation {
    ExecutorBindingStore(value) => {
      if self.request.ctx.strict &&
        had_own &&
        !with_object_has_own_direct(obj, self.request.name) {
        raise @errors.ReferenceError(
          message="{self.request.name} is not defined",
        )
      }
      self.phase = ExecutorBindingAwaitSet
      executor_activation_managed_property_set(
        obj,
        self.request.name,
        value,
        self.request.loc,
        self.request.ctx.strict,
      )
    }
    _ => {
      self.phase = ExecutorBindingAwaitGet
      executor_activation_managed_property_get(
        obj,
        self.request.name,
        self.request.loc,
      )
    }
  }
}

///|
fn ExecutorBindingFrame::after_has(
  self : ExecutorBindingFrame,
  env : Environment,
  obj : Value,
  had_own : Bool,
  has_property : Bool,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if !has_property {
    return self.parent_or_unresolved(env, interp)
  }
  self.phase = ExecutorBindingAwaitUnscopables(env, obj, had_own)
  executor_activation_symbol_property_get(
    obj,
    interp.realm_state.well_known_symbols.unscopables,
    self.request.loc,
  )
}

///|
fn ExecutorBindingFrame::after_unscopables(
  self : ExecutorBindingFrame,
  env : Environment,
  obj : Value,
  had_own : Bool,
  unscopables : Value,
) -> ExecutorActivationStep raise Error {
  if is_object_value(unscopables) {
    self.phase = ExecutorBindingAwaitUnscopablesName(env, obj, had_own)
    return executor_activation_managed_property_get(
      unscopables,
      self.request.name,
      self.request.loc,
    )
  }
  self.finish_with_object(obj, had_own)
}

///|
fn ExecutorBindingFrame::after_unscopables_name(
  self : ExecutorBindingFrame,
  env : Environment,
  obj : Value,
  had_own : Bool,
  unscopables_value : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if is_truthy(unscopables_value) {
    self.parent_or_unresolved(env, interp)
  } else {
    self.finish_with_object(obj, had_own)
  }
}

///|
fn ExecutorBindingFrame::step_environment(
  self : ExecutorBindingFrame,
  env : Environment,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match env.with_object {
    Some(obj) => {
      let had_own = match self.request.operation {
        ExecutorBindingStore(_) =>
          with_object_has_own_direct(obj, self.request.name)
        _ => false
      }
      let operation = ExecutorDeleteHasPropertyOperation(
        target=obj,
        key=String_(self.request.name),
        loc=self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(env, obj, had_own, has_property, interp)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingAwaitHas(env, obj, had_own, operation)
          step
        }
      }
    }
    None =>
      match env.bindings.get(self.request.name) {
        Some(_) => {
          let value = executor_binding_synchronous(interp, {
            ..self.request,
            env,
          })
          self.phase = ExecutorBindingComplete(value)
          ExecutorActivationNormal(value)
        }
        None => self.parent_or_unresolved(env, interp)
      }
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingFrame with fn step(self, interp) {
  match self.phase {
    ExecutorBindingNeedEnvironment(env) => self.step_environment(env, interp)
    ExecutorBindingAwaitHas(env, obj, had_own, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(env, obj, had_own, has_property, interp)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingAwaitHas(env, obj, had_own, operation)
          step
        }
      }
    ExecutorBindingAwaitUnscopables(_, _, _) =>
      raise @errors.InternalError(
        message="binding frame stepped while awaiting unscopables",
      )
    ExecutorBindingHaveUnscopables(env, obj, had_own, value) =>
      self.after_unscopables(env, obj, had_own, value)
    ExecutorBindingAwaitUnscopablesName(_, _, _) =>
      raise @errors.InternalError(
        message="binding frame stepped while awaiting unscopables name",
      )
    ExecutorBindingHaveUnscopablesName(env, obj, had_own, value) =>
      self.after_unscopables_name(env, obj, had_own, value, interp)
    ExecutorBindingAwaitGet =>
      raise @errors.InternalError(
        message="binding frame stepped while awaiting get",
      )
    ExecutorBindingHaveGet(value) => {
      let result = match self.request.operation {
        ExecutorBindingTypeof => String_(type_of(value))
        _ => value
      }
      self.phase = ExecutorBindingComplete(result)
      ExecutorActivationNormal(result)
    }
    ExecutorBindingAwaitSet =>
      raise @errors.InternalError(
        message="binding frame stepped while awaiting set",
      )
    ExecutorBindingComplete(value) => {
      self.phase = ExecutorBindingDone
      ExecutorActivationNormal(value)
    }
    ExecutorBindingDone =>
      raise @errors.InternalError(
        message="binding frame stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorBindingAwaitHas(_, _, _, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingAwaitUnscopables(env, obj, had_own) =>
          self.phase = ExecutorBindingHaveUnscopables(env, obj, had_own, value)
        ExecutorBindingAwaitUnscopablesName(env, obj, had_own) =>
          self.phase = ExecutorBindingHaveUnscopablesName(
            env, obj, had_own, value,
          )
        ExecutorBindingAwaitGet => self.phase = ExecutorBindingHaveGet(value)
        ExecutorBindingAwaitSet => {
          let result = match self.request.operation {
            ExecutorBindingStore(value) => value
            _ =>
              raise @errors.InternalError(
                message="binding set completion had a non-store operation",
              )
          }
          self.phase = ExecutorBindingComplete(result)
        }
        ExecutorBindingNeedEnvironment(_)
        | ExecutorBindingHaveUnscopables(_, _, _, _)
        | ExecutorBindingHaveUnscopablesName(_, _, _, _)
        | ExecutorBindingHaveGet(_)
        | ExecutorBindingComplete(_)
        | ExecutorBindingDone =>
          raise @errors.InternalError(
            message="binding received an unexpected child completion",
          )
      }
  }
}

///|
pub fn executor_activation_binding_request(
  request : ExecutorBindingRequest,
) -> ExecutorActivationStep {
  ExecutorActivationBinding(request)
}

///|
fn executor_binding_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    _ =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="binding frame completed with a pending activation step",
        ),
      )
  }
}

///|
priv enum ExecutorProxyPropertySetPhase {
  ExecutorProxyPropertySetNeedTrap
  ExecutorProxyPropertySetAwaitTrapLookup
  ExecutorProxyPropertySetHaveTrap(Value)
  ExecutorProxyPropertySetAwaitTrapCall
  ExecutorProxyPropertySetHaveTrapResult(Value)
  ExecutorProxyPropertySetAwaitForward
  ExecutorProxyPropertySetComplete(Value)
  ExecutorProxyPropertySetDone
}

///|
priv struct ExecutorProxyPropertySetFrame {
  target : Value
  handler : Value
  property_name : String
  value : Value
  receiver : Value
  strict : Bool
  loc : @token.Loc
  mut phase : ExecutorProxyPropertySetPhase
}

///|
fn ExecutorProxyPropertySetFrame::ExecutorProxyPropertySetFrame(
  target~ : Value,
  handler~ : Value,
  property_name~ : String,
  value~ : Value,
  receiver~ : Value,
  strict~ : Bool,
  loc~ : @token.Loc,
) -> ExecutorProxyPropertySetFrame {
  {
    target,
    handler,
    property_name,
    value,
    receiver,
    strict,
    loc,
    phase: ExecutorProxyPropertySetNeedTrap,
  }
}

///|
fn ExecutorProxyPropertySetFrame::step_frame(
  self : ExecutorProxyPropertySetFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorProxyPropertySetNeedTrap => {
      self.phase = ExecutorProxyPropertySetAwaitTrapLookup
      executor_activation_managed_property_get(self.handler, "set", self.loc)
    }
    ExecutorProxyPropertySetAwaitTrapLookup
    | ExecutorProxyPropertySetAwaitTrapCall
    | ExecutorProxyPropertySetAwaitForward =>
      raise @errors.InternalError(
        message="proxy set frame stepped while awaiting a child activation",
      )
    ExecutorProxyPropertySetHaveTrap(trap) =>
      match trap {
        Undefined | Null => {
          self.phase = ExecutorProxyPropertySetAwaitForward
          executor_activation_managed_property_set_with_receiver(
            self.target,
            self.property_name,
            self.value,
            self.receiver,
            self.loc,
            self.strict,
          )
        }
        _ if !is_callable(trap) =>
          raise @errors.TypeError(
            message="'set' on proxy: trap is not a function",
          )
        _ => {
          self.phase = ExecutorProxyPropertySetAwaitTrapCall
          executor_activation_call(
            trap,
            self.handler,
            [
              self.target,
              String_(self.property_name),
              self.value,
              self.receiver,
            ],
            self.loc,
          )
        }
      }
    ExecutorProxyPropertySetHaveTrapResult(result) =>
      if !is_truthy(result) {
        if self.strict {
          raise @errors.TypeError(
            message="'set' on proxy: trap returned falsish for property '{self.property_name}'",
          )
        }
        self.phase = ExecutorProxyPropertySetComplete(self.value)
        ExecutorActivationContinue
      } else {
        check_proxy_set_trap_invariants_with_interp(
          Some(interp),
          self.target,
          String_(self.property_name),
          self.value,
        )
        self.phase = ExecutorProxyPropertySetComplete(self.value)
        ExecutorActivationContinue
      }
    ExecutorProxyPropertySetComplete(value) => {
      self.phase = ExecutorProxyPropertySetDone
      ExecutorActivationNormal(value)
    }
    ExecutorProxyPropertySetDone =>
      raise @errors.InternalError(
        message="proxy set frame stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorProxyPropertySetFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorProxyPropertySetFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorProxyPropertySetAwaitTrapLookup =>
          self.phase = ExecutorProxyPropertySetHaveTrap(value)
        ExecutorProxyPropertySetAwaitTrapCall =>
          self.phase = ExecutorProxyPropertySetHaveTrapResult(value)
        ExecutorProxyPropertySetAwaitForward =>
          self.phase = ExecutorProxyPropertySetComplete(self.value)
        _ =>
          raise @errors.InternalError(
            message="proxy set frame received an unexpected child completion",
          )
      }
  }
}

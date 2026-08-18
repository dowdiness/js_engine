///|
// A resolved identifier reference is runtime state, not a JavaScript value.
// Its closed representation retains the selected binding cell or object base
// and keeps source-sensitive PutValue policy with that selection.
priv enum ResolvedBindingReferenceKind {
  ResolvedBindingLexical(EnvironmentSlot)
  ResolvedBindingWithObject(Value, Bool)
  ResolvedBindingGlobal
  ResolvedBindingUnresolvable
}

///|
pub struct ResolvedBindingReference {
  priv kind : ResolvedBindingReferenceKind
  priv name : String
  priv strict : Bool
  priv loc : @token.Loc
}

///|
pub struct ExecutorBindingReferenceRequest {
  priv ctx : ExecContext
  priv env : Environment
  priv name : String
  priv loc : @token.Loc
}

///|
fn ExecutorBindingReferenceRequest::ExecutorBindingReferenceRequest(
  ctx~ : ExecContext,
  env~ : Environment,
  name~ : String,
  loc~ : @token.Loc,
) -> ExecutorBindingReferenceRequest {
  { ctx, env, name, loc }
}

///|
#warnings("-unused_constructor")
priv enum ExecutorBindingReferenceStart {
  ExecutorBindingReferenceCompleted(ResolvedBindingReference)
  ExecutorBindingReferenceSuspended(ExecutorBindingReferenceRequest)
}

///|
#warnings("-unused_constructor")
priv enum ExecutorBindingReferenceGetStart {
  ExecutorBindingReferenceGetCompleted(Value)
  ExecutorBindingReferenceGetSuspended(ExecutorActivationStep)
}

///|
#warnings("-unused_constructor")
priv enum ExecutorBindingReferencePutStart {
  ExecutorBindingReferencePutCompleted(Value)
  ExecutorBindingReferencePutSuspended(ExecutorActivationStep)
}

///|
fn resolved_binding_reference(
  kind : ResolvedBindingReferenceKind,
  name : String,
  ctx : ExecContext,
  loc : @token.Loc,
) -> ResolvedBindingReference {
  { kind, name, strict: ctx.strict, loc }
}

///|
fn executor_binding_reference_global_or_unresolvable(
  interp : Interpreter,
  request : ExecutorBindingReferenceRequest,
) -> ResolvedBindingReference {
  let kind = match interp.global_this {
    Object(data) if data.bag.properties.contains(request.name) =>
      ResolvedBindingGlobal
    _ => ResolvedBindingUnresolvable
  }
  resolved_binding_reference(kind, request.name, request.ctx, request.loc)
}

///|
fn executor_binding_reference_plain(
  interp : Interpreter,
  request : ExecutorBindingReferenceRequest,
) -> ResolvedBindingReference {
  let mut current : Environment? = Some(request.env)
  while true {
    match current {
      Some(env) =>
        match env.bindings.get(request.name) {
          Some(_) => {
            let slot = env.resolve_slot(request.name).unwrap()
            return resolved_binding_reference(
              ResolvedBindingLexical(slot),
              request.name,
              request.ctx,
              request.loc,
            )
          }
          None => current = env.parent
        }
      None =>
        return executor_binding_reference_global_or_unresolvable(
          interp, request,
        )
    }
  }
  executor_binding_reference_global_or_unresolvable(interp, request)
}

///|
#warnings("-unused_value")
fn begin_executor_binding_reference(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  loc : @token.Loc,
) -> ExecutorBindingReferenceStart raise Error {
  @static_semantics.validate_strict_identifier_reference(ctx.strict, name)
  let request = ExecutorBindingReferenceRequest(ctx~, env~, name~, loc~)
  if !environment_requires_managed_binding(env, name) {
    return ExecutorBindingReferenceCompleted(
      executor_binding_reference_plain(interp, request),
    )
  }
  ExecutorBindingReferenceSuspended(request)
}

///|
#warnings("-unused_value")
fn begin_executor_binding_reference_get(
  interp : Interpreter,
  reference : ResolvedBindingReference,
) -> ExecutorBindingReferenceGetStart raise Error {
  match reference.kind {
    ResolvedBindingLexical(slot) =>
      ExecutorBindingReferenceGetCompleted(slot.read())
    ResolvedBindingWithObject(obj, missing) =>
      if missing {
        ExecutorBindingReferenceGetCompleted(Undefined)
      } else {
        ExecutorBindingReferenceGetSuspended(
          executor_activation_managed_property_get(
            obj,
            reference.name,
            reference.loc,
          ),
        )
      }
    ResolvedBindingGlobal =>
      ExecutorBindingReferenceGetCompleted(
        executor_binding_global_value(interp, reference.name),
      )
    ResolvedBindingUnresolvable =>
      raise @errors.ReferenceError(message="{reference.name} is not defined")
  }
}

///|
fn executor_binding_reference_put_unresolved(
  interp : Interpreter,
  reference : ResolvedBindingReference,
  value : Value,
) -> Value raise Error {
  if interp.is_immutable_global(reference.name) {
    if reference.strict {
      raise @errors.TypeError(
        message="Cannot assign to read only property '{reference.name}' of object '[object global]'",
      )
    }
    return value
  }
  if reference.strict {
    raise @errors.ReferenceError(message="{reference.name} is not defined")
  }
  interp.global.def(reference.name, value, VarBinding)
  interp.mirror_to_global(reference.name, value, configurable=true)
  value
}

///|
#warnings("-unused_value")
fn begin_executor_binding_reference_put(
  interp : Interpreter,
  reference : ResolvedBindingReference,
  value : Value,
) -> ExecutorBindingReferencePutStart raise Error {
  @static_semantics.validate_strict_assignment_target_name(
    reference.strict,
    reference.name,
  )
  match reference.kind {
    ResolvedBindingLexical(slot) => {
      slot.assign(value, strict=reference.strict)
      ExecutorBindingReferencePutCompleted(value)
    }
    ResolvedBindingWithObject(obj, _) =>
      ExecutorBindingReferencePutSuspended(
        executor_activation_managed_property_set(
          obj,
          reference.name,
          value,
          reference.loc,
          reference.strict,
        ),
      )
    ResolvedBindingGlobal | ResolvedBindingUnresolvable =>
      ExecutorBindingReferencePutCompleted(
        executor_binding_reference_put_unresolved(interp, reference, value),
      )
  }
}

///|
priv enum ExecutorBindingReferencePhase {
  ExecutorBindingReferenceNeedEnvironment(Environment)
  ExecutorBindingReferenceAwaitHas(
    Environment,
    Value,
    ExecutorDeleteHasPropertyOperation
  )
  ExecutorBindingReferenceAwaitRecheck(
    Environment,
    Value,
    ExecutorDeleteHasPropertyOperation
  )
  ExecutorBindingReferenceAwaitUnscopables(Environment, Value)
  ExecutorBindingReferenceHaveUnscopables(Environment, Value, Value)
  ExecutorBindingReferenceAwaitUnscopablesName(Environment, Value)
  ExecutorBindingReferenceHaveUnscopablesName(Environment, Value, Value)
  ExecutorBindingReferenceComplete(ResolvedBindingReference)
  ExecutorBindingReferenceDone
}

///|
priv struct ExecutorBindingReferenceFrame {
  request : ExecutorBindingReferenceRequest
  mut phase : ExecutorBindingReferencePhase
}

///|
fn ExecutorBindingReferenceFrame::ExecutorBindingReferenceFrame(
  request : ExecutorBindingReferenceRequest,
) -> ExecutorBindingReferenceFrame {
  { request, phase: ExecutorBindingReferenceNeedEnvironment(request.env) }
}

///|
fn ExecutorBindingReferenceFrame::parent_or_global(
  self : ExecutorBindingReferenceFrame,
  env : Environment,
  interp : Interpreter,
) -> ExecutorActivationStep {
  match env.parent {
    Some(parent) => {
      self.phase = ExecutorBindingReferenceNeedEnvironment(parent)
      ExecutorActivationContinue
    }
    None => {
      let reference = executor_binding_reference_global_or_unresolvable(
        interp,
        self.request,
      )
      self.phase = ExecutorBindingReferenceComplete(reference)
      ExecutorActivationReference(reference)
    }
  }
}

///|
fn ExecutorBindingReferenceFrame::complete_lexical(
  self : ExecutorBindingReferenceFrame,
  env : Environment,
) -> ExecutorActivationStep {
  let slot = env.resolve_slot(self.request.name).unwrap()
  let reference = resolved_binding_reference(
    ResolvedBindingLexical(slot),
    self.request.name,
    self.request.ctx,
    self.request.loc,
  )
  self.phase = ExecutorBindingReferenceComplete(reference)
  ExecutorActivationReference(reference)
}

///|
fn ExecutorBindingReferenceFrame::complete_with_object(
  self : ExecutorBindingReferenceFrame,
  obj : Value,
  missing : Bool,
) -> ExecutorActivationStep {
  let reference = resolved_binding_reference(
    ResolvedBindingWithObject(obj, missing),
    self.request.name,
    self.request.ctx,
    self.request.loc,
  )
  self.phase = ExecutorBindingReferenceComplete(reference)
  ExecutorActivationReference(reference)
}

///|
fn ExecutorBindingReferenceFrame::after_has(
  self : ExecutorBindingReferenceFrame,
  env : Environment,
  obj : Value,
  has_property : Bool,
  interp : Interpreter,
) -> ExecutorActivationStep {
  if !has_property {
    return self.parent_or_global(env, interp)
  }
  self.phase = ExecutorBindingReferenceAwaitUnscopables(env, obj)
  executor_activation_symbol_property_get(
    obj,
    interp.realm_state.well_known_symbols.unscopables,
    self.request.loc,
  )
}

///|
fn ExecutorBindingReferenceFrame::after_unscopables(
  self : ExecutorBindingReferenceFrame,
  env : Environment,
  obj : Value,
  unscopables : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if is_object_value(unscopables) {
    self.phase = ExecutorBindingReferenceAwaitUnscopablesName(env, obj)
    return executor_activation_managed_property_get(
      unscopables,
      self.request.name,
      self.request.loc,
    )
  }
  self.begin_recheck(env, obj, interp)
}

///|
fn ExecutorBindingReferenceFrame::after_unscopables_name(
  self : ExecutorBindingReferenceFrame,
  env : Environment,
  obj : Value,
  unscopables_value : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if is_truthy(unscopables_value) {
    self.parent_or_global(env, interp)
  } else {
    self.begin_recheck(env, obj, interp)
  }
}

///|
fn ExecutorBindingReferenceFrame::begin_recheck(
  self : ExecutorBindingReferenceFrame,
  env : Environment,
  obj : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let operation = ExecutorDeleteHasPropertyOperation(
    target=obj,
    key=String_(self.request.name),
    loc=self.request.loc,
  )
  match operation.step(interp) {
    ExecutorActivationNormal(Bool(has_property)) =>
      self.after_recheck(obj, has_property)
    ExecutorActivationNormal(_) =>
      raise @errors.InternalError(
        message="binding reference HasProperty recheck returned a non-boolean",
      )
    step => {
      self.phase = ExecutorBindingReferenceAwaitRecheck(env, obj, operation)
      step
    }
  }
}

///|
fn ExecutorBindingReferenceFrame::after_recheck(
  self : ExecutorBindingReferenceFrame,
  obj : Value,
  has_property : Bool,
) -> ExecutorActivationStep raise Error {
  if has_property {
    self.complete_with_object(obj, false)
  } else if self.request.ctx.strict {
    raise @errors.ReferenceError(message="{self.request.name} is not defined")
  } else {
    self.complete_with_object(obj, true)
  }
}

///|
fn ExecutorBindingReferenceFrame::step_environment(
  self : ExecutorBindingReferenceFrame,
  env : Environment,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match env.with_object {
    Some(obj) => {
      let operation = ExecutorDeleteHasPropertyOperation(
        target=obj,
        key=String_(self.request.name),
        loc=self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(env, obj, has_property, interp)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding reference HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferenceAwaitHas(env, obj, operation)
          step
        }
      }
    }
    None =>
      match env.bindings.get(self.request.name) {
        Some(_) => self.complete_lexical(env)
        None => self.parent_or_global(env, interp)
      }
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferenceFrame with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorBindingReferenceNeedEnvironment(env) =>
      self.step_environment(env, interp)
    ExecutorBindingReferenceAwaitHas(env, obj, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(env, obj, has_property, interp)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding reference HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferenceAwaitHas(env, obj, operation)
          step
        }
      }
    ExecutorBindingReferenceAwaitRecheck(env, obj, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_recheck(obj, has_property)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding reference HasProperty recheck returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferenceAwaitRecheck(env, obj, operation)
          step
        }
      }
    ExecutorBindingReferenceAwaitUnscopables(_, _) =>
      raise @errors.InternalError(
        message="binding reference frame stepped while awaiting unscopables",
      )
    ExecutorBindingReferenceHaveUnscopables(env, obj, value) =>
      self.after_unscopables(env, obj, value, interp)
    ExecutorBindingReferenceAwaitUnscopablesName(_, _) =>
      raise @errors.InternalError(
        message="binding reference frame stepped while awaiting unscopables name",
      )
    ExecutorBindingReferenceHaveUnscopablesName(env, obj, value) =>
      self.after_unscopables_name(env, obj, value, interp)
    ExecutorBindingReferenceComplete(reference) => {
      self.phase = ExecutorBindingReferenceDone
      ExecutorActivationReference(reference)
    }
    ExecutorBindingReferenceDone =>
      raise @errors.InternalError(
        message="binding reference frame stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferenceFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="binding reference frame received a nested reference",
      )
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorBindingReferenceAwaitHas(_, _, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingReferenceAwaitRecheck(_, _, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingReferenceAwaitUnscopables(env, obj) =>
          self.phase = ExecutorBindingReferenceHaveUnscopables(env, obj, value)
        ExecutorBindingReferenceAwaitUnscopablesName(env, obj) =>
          self.phase = ExecutorBindingReferenceHaveUnscopablesName(
            env, obj, value,
          )
        ExecutorBindingReferenceNeedEnvironment(_)
        | ExecutorBindingReferenceHaveUnscopables(_, _, _)
        | ExecutorBindingReferenceHaveUnscopablesName(_, _, _)
        | ExecutorBindingReferenceComplete(_)
        | ExecutorBindingReferenceDone =>
          raise @errors.InternalError(
            message="binding reference received an unexpected child completion",
          )
      }
  }
}

///|
#warnings("-unused_value")
fn executor_activation_binding_reference_request(
  request : ExecutorBindingReferenceRequest,
) -> ExecutorActivationStep {
  ExecutorActivationBindingReference(request)
}

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
  ExecutorBindingReferenceGetSuspended(ExecutorBindingReferenceGetOperation)
}

///|
priv enum ExecutorBindingReferenceGetPhase {
  ExecutorBindingReferenceGetNeedHas(Value)
  ExecutorBindingReferenceGetAwaitHas(Value, ExecutorDeleteHasPropertyOperation)
  ExecutorBindingReferenceGetNeedGet(Value)
  ExecutorBindingReferenceGetAwaitGet
  ExecutorBindingReferenceGetComplete(Value)
  ExecutorBindingReferenceGetDone
}

///|
priv struct ExecutorBindingReferenceGetOperation {
  reference : ResolvedBindingReference
  mut phase : ExecutorBindingReferenceGetPhase
}

///|
fn ExecutorBindingReferenceGetOperation::ExecutorBindingReferenceGetOperation(
  reference : ResolvedBindingReference,
  obj : Value,
  recheck : Bool,
) -> ExecutorBindingReferenceGetOperation {
  {
    reference,
    phase: if recheck {
      ExecutorBindingReferenceGetNeedHas(obj)
    } else {
      ExecutorBindingReferenceGetNeedGet(obj)
    },
  }
}

///|
fn ExecutorBindingReferenceGetOperation::after_has(
  self : ExecutorBindingReferenceGetOperation,
  obj : Value,
  has_property : Bool,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if !has_property {
    if self.reference.strict {
      raise @errors.ReferenceError(
        message="\{self.reference.name} is not defined",
      )
    }
    self.phase = ExecutorBindingReferenceGetComplete(Undefined)
    return ExecutorActivationNormal(Undefined)
  }
  self.phase = ExecutorBindingReferenceGetNeedGet(obj)
  self.step(interp)
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferenceGetOperation with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorBindingReferenceGetNeedHas(obj) => {
      let operation = ExecutorDeleteHasPropertyOperation(
        target=obj,
        key=String_(self.reference.name),
        loc=self.reference.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(obj, has_property, interp)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding reference GetValue HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferenceGetAwaitHas(obj, operation)
          step
        }
      }
    }
    ExecutorBindingReferenceGetAwaitHas(obj, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(obj, has_property, interp)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding reference GetValue HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferenceGetAwaitHas(obj, operation)
          step
        }
      }
    ExecutorBindingReferenceGetNeedGet(obj) => {
      self.phase = ExecutorBindingReferenceGetAwaitGet
      executor_activation_managed_property_get(
        obj,
        self.reference.name,
        self.reference.loc,
      )
    }
    ExecutorBindingReferenceGetAwaitGet =>
      raise @errors.InternalError(
        message="binding reference GetValue stepped while awaiting Get",
      )
    ExecutorBindingReferenceGetComplete(value) => {
      self.phase = ExecutorBindingReferenceGetDone
      ExecutorActivationNormal(value)
    }
    ExecutorBindingReferenceGetDone =>
      raise @errors.InternalError(
        message="binding reference GetValue stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferenceGetOperation with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="binding reference GetValue received a nested reference",
      )
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorBindingReferenceGetAwaitHas(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingReferenceGetAwaitGet =>
          self.phase = ExecutorBindingReferenceGetComplete(value)
        ExecutorBindingReferenceGetNeedHas(_)
        | ExecutorBindingReferenceGetNeedGet(_)
        | ExecutorBindingReferenceGetComplete(_)
        | ExecutorBindingReferenceGetDone =>
          raise @errors.InternalError(
            message="binding reference GetValue received an unexpected child completion",
          )
      }
  }
}

///|
extend ExecutorBindingReferenceGetOperation with ExecutorActivationFrame::{
  step,
  deliver_activation_completion,
}

///|
#warnings("-unused_constructor")
priv enum ExecutorBindingReferencePutStart {
  ExecutorBindingReferencePutCompleted(Value)
  ExecutorBindingReferencePutSuspended(ExecutorBindingReferencePutOperation)
}

///|
priv enum ExecutorBindingReferencePutPhase {
  ExecutorBindingReferencePutNeedHas(Value)
  ExecutorBindingReferencePutAwaitHas(Value, ExecutorDeleteHasPropertyOperation)
  ExecutorBindingReferencePutAwaitSet
  ExecutorBindingReferencePutComplete
  ExecutorBindingReferencePutDone
}

///|
priv struct ExecutorBindingReferencePutOperation {
  reference : ResolvedBindingReference
  value : Value
  mut phase : ExecutorBindingReferencePutPhase
}

///|
fn ExecutorBindingReferencePutOperation::ExecutorBindingReferencePutOperation(
  reference : ResolvedBindingReference,
  value : Value,
  obj : Value,
) -> ExecutorBindingReferencePutOperation {
  { reference, value, phase: ExecutorBindingReferencePutNeedHas(obj) }
}

///|
fn ExecutorBindingReferencePutOperation::after_has(
  self : ExecutorBindingReferencePutOperation,
  obj : Value,
  has_property : Bool,
) -> ExecutorActivationStep raise Error {
  if !has_property && self.reference.strict {
    raise @errors.ReferenceError(
      message="\{self.reference.name} is not defined",
    )
  }
  self.phase = ExecutorBindingReferencePutAwaitSet
  executor_activation_managed_property_set(
    obj,
    self.reference.name,
    self.value,
    self.reference.loc,
    self.reference.strict,
  )
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferencePutOperation with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorBindingReferencePutNeedHas(obj) => {
      let operation = ExecutorDeleteHasPropertyOperation(
        target=obj,
        key=String_(self.reference.name),
        loc=self.reference.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(obj, has_property)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding reference PutValue HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferencePutAwaitHas(obj, operation)
          step
        }
      }
    }
    ExecutorBindingReferencePutAwaitHas(obj, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.after_has(obj, has_property)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="binding reference PutValue HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferencePutAwaitHas(obj, operation)
          step
        }
      }
    ExecutorBindingReferencePutAwaitSet =>
      raise @errors.InternalError(
        message="binding reference PutValue stepped while awaiting Set",
      )
    ExecutorBindingReferencePutComplete => {
      self.phase = ExecutorBindingReferencePutDone
      ExecutorActivationNormal(self.value)
    }
    ExecutorBindingReferencePutDone =>
      raise @errors.InternalError(
        message="binding reference PutValue stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferencePutOperation with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="binding reference PutValue received a nested reference",
      )
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorBindingReferencePutAwaitHas(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingReferencePutAwaitSet =>
          self.phase = ExecutorBindingReferencePutComplete
        ExecutorBindingReferencePutNeedHas(_)
        | ExecutorBindingReferencePutComplete
        | ExecutorBindingReferencePutDone =>
          raise @errors.InternalError(
            message="binding reference PutValue received an unexpected child completion",
          )
      }
  }
}

///|
extend ExecutorBindingReferencePutOperation with ExecutorActivationFrame::{
  step,
  deliver_activation_completion,
}

///|
priv enum ExecutorBindingReferenceAccessKind {
  ExecutorBindingReferenceAccessGet
  ExecutorBindingReferenceAccessPut(Value)
}

///|
pub struct ExecutorBindingReferenceAccessRequest {
  priv reference : ResolvedBindingReference
  priv kind : ExecutorBindingReferenceAccessKind
}

///|
priv enum ExecutorBindingReferenceAccessPhase {
  ExecutorBindingReferenceAccessNeedOperation
  ExecutorBindingReferenceAccessAwaitGet(ExecutorBindingReferenceGetOperation)
  ExecutorBindingReferenceAccessAwaitPut(ExecutorBindingReferencePutOperation)
  ExecutorBindingReferenceAccessComplete(Value)
  ExecutorBindingReferenceAccessDone
}

///|
priv struct ExecutorBindingReferenceAccessFrame {
  request : ExecutorBindingReferenceAccessRequest
  mut phase : ExecutorBindingReferenceAccessPhase
}

///|
fn ExecutorBindingReferenceAccessFrame::ExecutorBindingReferenceAccessFrame(
  request : ExecutorBindingReferenceAccessRequest,
) -> ExecutorBindingReferenceAccessFrame {
  { request, phase: ExecutorBindingReferenceAccessNeedOperation }
}

///|
fn ExecutorBindingReferenceAccessFrame::advance_get(
  self : ExecutorBindingReferenceAccessFrame,
  operation : ExecutorBindingReferenceGetOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match operation.step(interp) {
    ExecutorActivationNormal(value) => {
      self.phase = ExecutorBindingReferenceAccessComplete(value)
      ExecutorActivationNormal(value)
    }
    step => {
      self.phase = ExecutorBindingReferenceAccessAwaitGet(operation)
      step
    }
  }
}

///|
fn ExecutorBindingReferenceAccessFrame::advance_put(
  self : ExecutorBindingReferenceAccessFrame,
  operation : ExecutorBindingReferencePutOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match operation.step(interp) {
    ExecutorActivationNormal(value) => {
      self.phase = ExecutorBindingReferenceAccessComplete(value)
      ExecutorActivationNormal(value)
    }
    step => {
      self.phase = ExecutorBindingReferenceAccessAwaitPut(operation)
      step
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferenceAccessFrame with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorBindingReferenceAccessNeedOperation =>
      match self.request.kind {
        ExecutorBindingReferenceAccessGet =>
          match
            begin_executor_binding_reference_get(interp, self.request.reference) {
            ExecutorBindingReferenceGetCompleted(value) => {
              self.phase = ExecutorBindingReferenceAccessComplete(value)
              ExecutorActivationNormal(value)
            }
            ExecutorBindingReferenceGetSuspended(operation) =>
              self.advance_get(operation, interp)
          }
        ExecutorBindingReferenceAccessPut(value) =>
          match
            begin_executor_binding_reference_put(
              interp,
              self.request.reference,
              value,
            ) {
            ExecutorBindingReferencePutCompleted(result) => {
              self.phase = ExecutorBindingReferenceAccessComplete(result)
              ExecutorActivationNormal(result)
            }
            ExecutorBindingReferencePutSuspended(operation) =>
              self.advance_put(operation, interp)
          }
      }
    ExecutorBindingReferenceAccessAwaitGet(operation) =>
      self.advance_get(operation, interp)
    ExecutorBindingReferenceAccessAwaitPut(operation) =>
      self.advance_put(operation, interp)
    ExecutorBindingReferenceAccessComplete(value) => {
      self.phase = ExecutorBindingReferenceAccessDone
      ExecutorActivationNormal(value)
    }
    ExecutorBindingReferenceAccessDone =>
      raise @errors.InternalError(
        message="binding reference access stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingReferenceAccessFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match self.phase {
    ExecutorBindingReferenceAccessAwaitGet(operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorBindingReferenceAccessAwaitPut(operation) =>
      operation.deliver_activation_completion(completion)
    ExecutorBindingReferenceAccessNeedOperation
    | ExecutorBindingReferenceAccessComplete(_)
    | ExecutorBindingReferenceAccessDone =>
      raise @errors.InternalError(
        message="binding reference access received an unexpected child completion",
      )
  }
}

///|
#warnings("-unused_value")
extend ExecutorBindingReferenceAccessFrame with ExecutorActivationFrame::{
  step,
  deliver_activation_completion,
}

///|
pub fn executor_activation_binding_reference_resolution(
  ctx : ExecContext,
  env : Environment,
  name : String,
  loc : @token.Loc,
) -> ExecutorActivationStep raise Error {
  @static_semantics.validate_strict_identifier_reference(ctx.strict, name)
  ExecutorActivationBindingReference(
    ExecutorBindingReferenceRequest(ctx~, env~, name~, loc~),
  )
}

///|
pub fn executor_activation_binding_reference_get(
  reference : ResolvedBindingReference,
) -> ExecutorActivationStep {
  ExecutorActivationBindingReferenceAccess({
    reference,
    kind: ExecutorBindingReferenceAccessGet,
  })
}

///|
pub fn executor_activation_binding_reference_put(
  reference : ResolvedBindingReference,
  value : Value,
) -> ExecutorActivationStep {
  ExecutorActivationBindingReferenceAccess({
    reference,
    kind: ExecutorBindingReferenceAccessPut(value),
  })
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
fn try_executor_binding_reference_plain(
  interp : Interpreter,
  request : ExecutorBindingReferenceRequest,
) -> ResolvedBindingReference? {
  let mut current : Environment? = Some(request.env)
  while true {
    match current {
      Some(env) =>
        match env.with_object {
          Some(_) => return None
          None =>
            match env.resolve_slot(request.name) {
              Some(slot) => {
                let kind = if env.bindings.get(request.name)
                  is Some({ kind: VarBinding, .. }) &&
                  env.parent is None &&
                  interp.is_immutable_global(request.name) {
                  ResolvedBindingGlobal
                } else {
                  ResolvedBindingLexical(slot)
                }
                return Some(
                  resolved_binding_reference(
                    kind,
                    request.name,
                    request.ctx,
                    request.loc,
                  ),
                )
              }
              None => current = env.parent
            }
        }
      None => return None
    }
  }
  None
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
  match try_executor_binding_reference_plain(interp, request) {
    Some(reference) => ExecutorBindingReferenceCompleted(reference)
    None => ExecutorBindingReferenceSuspended(request)
  }
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
    ResolvedBindingWithObject(obj, _) =>
      ExecutorBindingReferenceGetSuspended(
        ExecutorBindingReferenceGetOperation(reference, obj, true),
      )
    ResolvedBindingGlobal =>
      ExecutorBindingReferenceGetSuspended(
        ExecutorBindingReferenceGetOperation(
          reference,
          interp.global_this,
          true,
        ),
      )
    ResolvedBindingUnresolvable =>
      raise @errors.ReferenceError(message="\{reference.name} is not defined")
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
        message="Cannot assign to read only property '\{reference.name}' of object '[object global]'",
      )
    }
    return value
  }
  if reference.strict {
    raise @errors.ReferenceError(message="\{reference.name} is not defined")
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
        ExecutorBindingReferencePutOperation(reference, value, obj),
      )
    ResolvedBindingGlobal =>
      ExecutorBindingReferencePutSuspended(
        ExecutorBindingReferencePutOperation(
          reference,
          value,
          interp.global_this,
        ),
      )
    ResolvedBindingUnresolvable =>
      ExecutorBindingReferencePutCompleted(
        executor_binding_reference_put_unresolved(interp, reference, value),
      )
  }
}

///|
priv enum ExecutorBindingReferencePhase {
  ExecutorBindingReferenceNeedEnvironment(Environment)
  ExecutorBindingReferenceAwaitGlobalHas(
    Value,
    ExecutorDeleteHasPropertyOperation
  )
  ExecutorBindingReferenceAwaitHas(
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
) -> ExecutorActivationStep raise Error {
  match env.parent {
    Some(parent) => {
      self.phase = ExecutorBindingReferenceNeedEnvironment(parent)
      ExecutorActivationContinue
    }
    None => self.begin_global_has(interp)
  }
}

///|
fn ExecutorBindingReferenceFrame::begin_global_has(
  self : ExecutorBindingReferenceFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let obj = interp.global_this
  let operation = ExecutorDeleteHasPropertyOperation(
    target=obj,
    key=String_(self.request.name),
    loc=self.request.loc,
  )
  match operation.step(interp) {
    ExecutorActivationNormal(Bool(has_property)) =>
      self.complete_global(has_property)
    ExecutorActivationNormal(_) =>
      raise @errors.InternalError(
        message="global binding reference HasProperty returned a non-boolean",
      )
    step => {
      self.phase = ExecutorBindingReferenceAwaitGlobalHas(obj, operation)
      step
    }
  }
}

///|
fn ExecutorBindingReferenceFrame::complete_global(
  self : ExecutorBindingReferenceFrame,
  has_property : Bool,
) -> ExecutorActivationStep {
  let kind = if has_property {
    ResolvedBindingGlobal
  } else {
    ResolvedBindingUnresolvable
  }
  let reference = resolved_binding_reference(
    kind,
    self.request.name,
    self.request.ctx,
    self.request.loc,
  )
  self.phase = ExecutorBindingReferenceComplete(reference)
  ExecutorActivationReference(reference)
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
) -> ExecutorActivationStep raise Error {
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
) -> ExecutorActivationStep {
  if is_object_value(unscopables) {
    self.phase = ExecutorBindingReferenceAwaitUnscopablesName(env, obj)
    return executor_activation_managed_property_get(
      unscopables,
      self.request.name,
      self.request.loc,
    )
  }
  self.complete_with_object(obj, false)
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
    self.complete_with_object(obj, false)
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
        Some({ kind: VarBinding, .. }) if env.parent is None &&
          interp.is_immutable_global(self.request.name) =>
          self.complete_global(true)
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
    ExecutorBindingReferenceAwaitGlobalHas(obj, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(has_property)) =>
          self.complete_global(has_property)
        ExecutorActivationNormal(_) =>
          raise @errors.InternalError(
            message="global binding reference HasProperty returned a non-boolean",
          )
        step => {
          self.phase = ExecutorBindingReferenceAwaitGlobalHas(obj, operation)
          step
        }
      }
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
    ExecutorBindingReferenceAwaitUnscopables(_, _) =>
      raise @errors.InternalError(
        message="binding reference frame stepped while awaiting unscopables",
      )
    ExecutorBindingReferenceHaveUnscopables(env, obj, value) =>
      self.after_unscopables(env, obj, value)
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
        ExecutorBindingReferenceAwaitGlobalHas(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingReferenceAwaitHas(_, _, operation) =>
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

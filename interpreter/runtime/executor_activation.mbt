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
  ExecutorActivationConstruct(ExecutorConstructRequest)
  ExecutorActivationPropertyGet(ExecutorPropertyGetRequest)
  ExecutorActivationPropertySet(ExecutorPropertySetRequest)
  ExecutorActivationPropertyUpdate(ExecutorPropertyUpdateRequest)
  ExecutorActivationCoercingAddition(ExecutorCoercingAdditionRequest)
  ExecutorActivationCoercingRelational(ExecutorCoercingRelationalRequest)
  ExecutorActivationCoercingSubtraction(ExecutorCoercingSubtractionRequest)
  ExecutorActivationPropertyDelete(ExecutorPropertyDeleteRequest)
  ExecutorActivationIterableSpread(ExecutorIterableSpreadRequest)
  ExecutorActivationCopyDataProperties(ExecutorCopyDataPropertiesRequest)
  ExecutorActivationBinding(ExecutorBindingRequest)
  ExecutorActivationBindingReference(ExecutorBindingReferenceRequest)
  ExecutorActivationBindingUpdate(ExecutorBindingUpdateRequest)
  ExecutorActivationReference(ResolvedBindingReference)
}

///|
// A closed child completion. Runtime owns the completion boundary so executor
// frames can choose whether an abrupt child result is recoverable without
// translating or copying the original error.
pub enum ExecutorActivationCompletion {
  ExecutorActivationCompletionNormal(Value)
  ExecutorActivationCompletionAbrupt(Error)
  ExecutorActivationCompletionReference(ResolvedBindingReference)
}

///|
priv enum ExecutorActivationRequestOutcome {
  ExecutorActivationRequestChild
  ExecutorActivationRequestValue(Value)
}

///|
pub fn executor_activation_completion_normal(
  value : Value,
) -> ExecutorActivationCompletion {
  ExecutorActivationCompletionNormal(value)
}

///|
pub fn executor_activation_completion_abrupt(
  error : Error,
) -> ExecutorActivationCompletion {
  ExecutorActivationCompletionAbrupt(error)
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
// A closed iterable-spread request. Runtime owns iterator acquisition, every
// protocol step, validation, and abrupt completion. The executor supplies only
// the already-evaluated iterable and source location; the eventual batch is
// delivered through the neutral activation completion seam.
pub struct ExecutorIterableSpreadRequest {
  priv iterable : Value
  priv loc : @token.Loc
}

///|
fn ExecutorIterableSpreadRequest::ExecutorIterableSpreadRequest(
  iterable~ : Value,
  loc~ : @token.Loc,
) -> ExecutorIterableSpreadRequest {
  { iterable, loc }
}

///|
#warnings("-unused_constructor")
pub enum ExecutorIterableSpreadStart {
  ExecutorIterableSpreadCompleted(Array[Value])
  ExecutorIterableSpreadSuspended(ExecutorIterableSpreadRequest)
}

///|
// Acquisition always crosses the executor-neutral seam. Runtime decides
// whether a particular iterator lookup or protocol step completes locally;
// this keeps built-in Array/String handling in one canonical owner without a
// VM-side fast path.
pub fn begin_executor_iterable_spread(
  iterable : Value,
  loc : @token.Loc,
) -> ExecutorIterableSpreadStart {
  ExecutorIterableSpreadSuspended(
    ExecutorIterableSpreadRequest(iterable~, loc~),
  )
}

///|
pub fn executor_activation_iterable_spread_request(
  request : ExecutorIterableSpreadRequest,
) -> ExecutorActivationStep {
  ExecutorActivationIterableSpread(request)
}

///|
// A closed CopyDataProperties request. Runtime owns key snapshotting,
// descriptor/enumerability checks, source reads, and incremental target
// definitions. The compiler/VM supplies only the evaluated target/source and
// an immutable exclusion snapshot.
pub struct ExecutorCopyDataPropertiesRequest {
  priv target : Value
  priv source : Value
  priv excluded_keys : Array[Value]
  priv loc : @token.Loc
}

///|
fn ExecutorCopyDataPropertiesRequest::ExecutorCopyDataPropertiesRequest(
  target~ : Value,
  source~ : Value,
  excluded_keys~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorCopyDataPropertiesRequest {
  { target, source, excluded_keys: excluded_keys.copy(), loc }
}

///|
#warnings("-unused_constructor")
pub enum ExecutorCopyDataPropertiesStart {
  ExecutorCopyDataPropertiesCompleted
  ExecutorCopyDataPropertiesSuspended(ExecutorCopyDataPropertiesRequest)
}

///|
pub fn begin_executor_copy_data_properties(
  _interp : Interpreter,
  target : Value,
  source : Value,
  excluded_keys : Array[Value],
  loc : @token.Loc,
) -> ExecutorCopyDataPropertiesStart {
  match source {
    Null | Undefined => ExecutorCopyDataPropertiesCompleted
    _ =>
      ExecutorCopyDataPropertiesSuspended(
        ExecutorCopyDataPropertiesRequest(
          target~,
          source~,
          excluded_keys~,
          loc~,
        ),
      )
  }
}

///|
pub fn executor_activation_copy_data_properties_request(
  request : ExecutorCopyDataPropertiesRequest,
) -> ExecutorActivationStep {
  ExecutorActivationCopyDataProperties(request)
}

///|
// A closed property-get request. Runtime owns property lookup and accessor
// admission; executors only provide an already-evaluated target and a sealed
// string or symbol key.
pub struct ExecutorPropertyGetRequest {
  priv target : Value
  priv key : ExecutorPropertyGetKey
  priv receiver : Value
  priv loc : @token.Loc
  priv manage_proxy : Bool
  priv admission : ExecutorPropertyGetAdmission?
}

///|
priv enum ExecutorPropertyGetKey {
  ExecutorStringPropertyGetKey(String)
  ExecutorSymbolPropertyGetKey(SymbolData)
}

///|
fn ExecutorPropertyGetRequest::ExecutorPropertyGetRequest(
  target~ : Value,
  key~ : ExecutorPropertyGetKey,
  receiver~ : Value,
  loc~ : @token.Loc,
  manage_proxy~ : Bool,
  admission? : ExecutorPropertyGetAdmission? = None,
) -> ExecutorPropertyGetRequest {
  { target, key, receiver, loc, manage_proxy, admission }
}

///|
pub fn executor_activation_property_get(
  target : Value,
  property_name : String,
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationPropertyGet(
    ExecutorPropertyGetRequest(
      target~,
      key=ExecutorStringPropertyGetKey(property_name),
      receiver=target,
      loc~,
      manage_proxy=false,
    ),
  )
}

///|
fn executor_activation_symbol_property_get(
  target : Value,
  symbol : SymbolData,
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationPropertyGet(
    ExecutorPropertyGetRequest(
      target~,
      key=ExecutorSymbolPropertyGetKey(symbol),
      receiver=target,
      loc~,
      manage_proxy=true,
    ),
  )
}

///|
fn executor_activation_property_get_with_receiver(
  target : Value,
  key : ExecutorPropertyGetKey,
  receiver : Value,
  loc : @token.Loc,
  manage_proxy : Bool,
) -> ExecutorActivationStep {
  ExecutorActivationPropertyGet(
    ExecutorPropertyGetRequest(target~, key~, receiver~, loc~, manage_proxy~),
  )
}

///|
fn executor_activation_managed_property_get(
  target : Value,
  property_name : String,
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationPropertyGet(
    ExecutorPropertyGetRequest(
      target~,
      key=ExecutorStringPropertyGetKey(property_name),
      receiver=target,
      loc~,
      manage_proxy=true,
    ),
  )
}

///|
fn executor_property_get_key_value(key : ExecutorPropertyGetKey) -> Value {
  match key {
    ExecutorStringPropertyGetKey(property_name) => String_(property_name)
    ExecutorSymbolPropertyGetKey(symbol) => Symbol(symbol)
  }
}

///|
// A closed static property-set request. Runtime owns property mutation,
// setter admission, fallback, and assignment-result normalization; executors
// only provide the already-evaluated target, property name, and RHS.
pub struct ExecutorPropertySetRequest {
  priv target : Value
  priv property_name : String
  priv value : Value
  priv receiver : Value
  priv loc : @token.Loc
  priv strict : Bool
  priv manage_proxy : Bool
}

///|
fn ExecutorPropertySetRequest::ExecutorPropertySetRequest(
  target~ : Value,
  property_name~ : String,
  value~ : Value,
  receiver~ : Value,
  loc~ : @token.Loc,
  strict~ : Bool,
  manage_proxy? : Bool = false,
) -> ExecutorPropertySetRequest {
  { target, property_name, value, receiver, loc, strict, manage_proxy }
}

///|
pub fn executor_activation_property_set(
  target : Value,
  property_name : String,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> ExecutorActivationStep {
  ExecutorActivationPropertySet(
    ExecutorPropertySetRequest(
      target~,
      property_name~,
      value~,
      receiver=target,
      loc~,
      strict~,
    ),
  )
}

///|
fn executor_activation_managed_property_set(
  target : Value,
  property_name : String,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> ExecutorActivationStep {
  executor_activation_managed_property_set_with_receiver(
    target, property_name, value, target, loc, strict,
  )
}

///|
fn executor_activation_managed_property_set_with_receiver(
  target : Value,
  property_name : String,
  value : Value,
  receiver : Value,
  loc : @token.Loc,
  strict : Bool,
) -> ExecutorActivationStep {
  ExecutorActivationPropertySet(
    ExecutorPropertySetRequest(
      target~,
      property_name~,
      value~,
      receiver~,
      loc~,
      strict~,
      manage_proxy=true,
    ),
  )
}

///|
// A closed addition request. Runtime owns ToPrimitive ordering, conversion
// hooks, final string-or-numeric addition, and abrupt completion; executors
// supply only the already-evaluated operands and source location.
pub struct ExecutorCoercingAdditionRequest {
  priv left : Value
  priv right : Value
  priv loc : @token.Loc
}

///|
fn ExecutorCoercingAdditionRequest::ExecutorCoercingAdditionRequest(
  left~ : Value,
  right~ : Value,
  loc~ : @token.Loc,
) -> ExecutorCoercingAdditionRequest {
  { left, right, loc }
}

///|
pub fn executor_activation_coercing_addition(
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingAddition(
    ExecutorCoercingAdditionRequest(left~, right~, loc~),
  )
}

///|
pub fn executor_activation_coercing_addition_request(
  request : ExecutorCoercingAdditionRequest,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingAddition(request)
}

///|
// A closed subtraction request. Runtime owns ToPrimitive(number) ordering,
// Number conversion, and abrupt completion; executors supply only the already-
// evaluated operands and source location.
pub struct ExecutorCoercingSubtractionRequest {
  priv left : Value
  priv right : Value
  priv loc : @token.Loc
}

///|
fn ExecutorCoercingSubtractionRequest::ExecutorCoercingSubtractionRequest(
  left~ : Value,
  right~ : Value,
  loc~ : @token.Loc,
) -> ExecutorCoercingSubtractionRequest {
  { left, right, loc }
}

///|
pub fn executor_activation_coercing_subtraction(
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingSubtraction(
    ExecutorCoercingSubtractionRequest(left~, right~, loc~),
  )
}

///|
pub fn executor_activation_coercing_subtraction_request(
  request : ExecutorCoercingSubtractionRequest,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingSubtraction(request)
}

///|
pub fn executor_activation_coercing_less_than_or_equal(
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingRelational(
    ExecutorCoercingRelationalRequest(
      left~,
      right~,
      operator=ExecutorRelationalLessThanOrEqual,
      loc~,
    ),
  )
}

///|
pub fn executor_activation_coercing_less_than_or_equal_request(
  request : ExecutorCoercingLessThanOrEqualRequest,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingRelational(
    executor_coercing_relational_request_from_less_than_or_equal(request),
  )
}

///|
pub fn executor_activation_coercing_relational(
  left : Value,
  right : Value,
  loc : @token.Loc,
  operator : ExecutorRelationalOperator,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingRelational(
    ExecutorCoercingRelationalRequest(left~, right~, operator~, loc~),
  )
}

///|
pub fn executor_activation_coercing_relational_request(
  request : ExecutorCoercingRelationalRequest,
) -> ExecutorActivationStep {
  ExecutorActivationCoercingRelational(request)
}

///|
// A closed property-delete request. Runtime owns ToPropertyKey, Proxy trap
// lookup/call, forwarding, invariants, and strict-result normalization. The
// compiler supplies only an already-evaluated target and either a static key
// or the raw computed key value.
pub struct ExecutorPropertyDeleteRequest {
  priv target : Value
  priv key : ExecutorPropertyDeleteKey
  priv strict : Bool
  priv loc : @token.Loc
}

///|
priv enum ExecutorPropertyDeleteKey {
  ExecutorStaticPropertyDeleteKey(String)
  ExecutorComputedPropertyDeleteKey(Value)
}

///|
fn ExecutorPropertyDeleteRequest::ExecutorPropertyDeleteRequest(
  target~ : Value,
  key~ : ExecutorPropertyDeleteKey,
  strict~ : Bool,
  loc~ : @token.Loc,
) -> ExecutorPropertyDeleteRequest {
  { target, key, strict, loc }
}

///|
pub enum ExecutorPropertyDeleteStart {
  ExecutorPropertyDeleteCompleted(Value)
  ExecutorPropertyDeleteSuspended(ExecutorPropertyDeleteRequest)
}

///|
fn begin_executor_property_delete(
  interp : Interpreter,
  target : Value,
  key : ExecutorPropertyDeleteKey,
  strict : Bool,
  loc : @token.Loc,
) -> ExecutorPropertyDeleteStart raise Error {
  let request = ExecutorPropertyDeleteRequest(target~, key~, strict~, loc~)
  match key {
    ExecutorStaticPropertyDeleteKey(_) if target is Proxy(_) =>
      ExecutorPropertyDeleteSuspended(request)
    ExecutorStaticPropertyDeleteKey(property_name) =>
      ExecutorPropertyDeleteCompleted(
        Bool(
          interp.delete_property_key(target, String_(property_name), strict~),
        ),
      )
    ExecutorComputedPropertyDeleteKey(raw_key) if target is Proxy(_) ||
      is_js_object(raw_key) => ExecutorPropertyDeleteSuspended(request)
    ExecutorComputedPropertyDeleteKey(raw_key) =>
      ExecutorPropertyDeleteCompleted(
        Bool(interp.delete_property_key(target, raw_key, strict~)),
      )
  }
}

///|
pub fn begin_executor_property_delete_static(
  interp : Interpreter,
  target : Value,
  property_name : String,
  strict : Bool,
  loc : @token.Loc,
) -> ExecutorPropertyDeleteStart raise Error {
  begin_executor_property_delete(
    interp,
    target,
    ExecutorStaticPropertyDeleteKey(property_name),
    strict,
    loc,
  )
}

///|
pub fn begin_executor_property_delete_computed(
  interp : Interpreter,
  target : Value,
  raw_key : Value,
  strict : Bool,
  loc : @token.Loc,
) -> ExecutorPropertyDeleteStart raise Error {
  begin_executor_property_delete(
    interp,
    target,
    ExecutorComputedPropertyDeleteKey(raw_key),
    strict,
    loc,
  )
}

///|
pub fn executor_activation_property_delete_request(
  request : ExecutorPropertyDeleteRequest,
) -> ExecutorActivationStep {
  ExecutorActivationPropertyDelete(request)
}

///|
// A closed identifier-update request. Runtime retains the resolved binding
// reference across read, Number-hint conversion, and write; the compiler and
// VM provide only the source update operator and result destination.
pub struct ExecutorBindingUpdateRequest {
  priv ctx : ExecContext
  priv env : Environment
  priv name : String
  priv operator : ExecutorBindingUpdateOperator
  priv prefix : Bool
  priv loc : @token.Loc
  priv mut phase : ExecutorBindingUpdatePhase
}

///|
priv enum ExecutorBindingUpdateOperator {
  ExecutorBindingIncrement
  ExecutorBindingDecrement
}

///|
priv enum ExecutorBindingUpdatePhase {
  ExecutorBindingUpdateNeedReference(ExecutorBindingReferenceRequest)
  ExecutorBindingUpdateAwaitReference
  ExecutorBindingUpdateNeedGet(ResolvedBindingReference)
  ExecutorBindingUpdateAwaitGet(ResolvedBindingReference)
  ExecutorBindingUpdateHaveCurrent(ResolvedBindingReference, Value)
  ExecutorBindingUpdateAwaitToPrimitive(
    ResolvedBindingReference,
    Value,
    ExecutorToPrimitiveOperation
  )
  ExecutorBindingUpdateAwaitPut(ExecutorBindingReferencePutOperation, Value)
  ExecutorBindingUpdateComplete(Value)
}

///|
fn ExecutorBindingUpdateRequest::ExecutorBindingUpdateRequest(
  ctx~ : ExecContext,
  env~ : Environment,
  name~ : String,
  operator~ : ExecutorBindingUpdateOperator,
  prefix~ : Bool,
  loc~ : @token.Loc,
  phase~ : ExecutorBindingUpdatePhase,
) -> ExecutorBindingUpdateRequest {
  { ctx, env, name, operator, prefix, loc, phase }
}

///|
pub enum ExecutorBindingUpdateStart {
  ExecutorBindingUpdateCompleted(Value)
  ExecutorBindingUpdateSuspended(ExecutorBindingUpdateRequest)
}

///|
fn executor_binding_update_operator(
  op : @ast.UpdateOp,
) -> ExecutorBindingUpdateOperator {
  match op {
    Increment => ExecutorBindingIncrement
    Decrement => ExecutorBindingDecrement
  }
}

///|
pub fn begin_executor_binding_update(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  op : @ast.UpdateOp,
  prefix : Bool,
  loc : @token.Loc,
) -> ExecutorBindingUpdateStart raise Error {
  let reference_request = ExecutorBindingReferenceRequest(
    ctx~,
    env~,
    name~,
    loc~,
  )
  let request = ExecutorBindingUpdateRequest(
    ctx~,
    env~,
    name~,
    operator=executor_binding_update_operator(op),
    prefix~,
    loc~,
    phase=ExecutorBindingUpdateNeedReference(reference_request),
  )
  match begin_executor_binding_reference(interp, ctx, env, name, loc) {
    ExecutorBindingReferenceSuspended(reference_request) => {
      request.phase = ExecutorBindingUpdateNeedReference(reference_request)
      ExecutorBindingUpdateSuspended(request)
    }
    ExecutorBindingReferenceCompleted(reference) =>
      match begin_executor_binding_reference_get(interp, reference) {
        ExecutorBindingReferenceGetSuspended(_) => {
          request.phase = ExecutorBindingUpdateNeedGet(reference)
          ExecutorBindingUpdateSuspended(request)
        }
        ExecutorBindingReferenceGetCompleted(current) if is_js_object(current) => {
          request.phase = ExecutorBindingUpdateHaveCurrent(reference, current)
          ExecutorBindingUpdateSuspended(request)
        }
        ExecutorBindingReferenceGetCompleted(current) =>
          match reference.kind {
            ResolvedBindingWithObject(_, _) => {
              request.phase = ExecutorBindingUpdateHaveCurrent(
                reference, current,
              )
              ExecutorBindingUpdateSuspended(request)
            }
            _ => {
              let old_number = to_number(current, interp=Some(interp))
              let next_value : Value = match request.operator {
                ExecutorBindingIncrement => Number(old_number + 1.0)
                ExecutorBindingDecrement => Number(old_number - 1.0)
              }
              let result = if request.prefix {
                next_value
              } else {
                Number(old_number)
              }
              match
                begin_executor_binding_reference_put(
                  interp, reference, next_value,
                ) {
                ExecutorBindingReferencePutCompleted(value) => {
                  ignore(value)
                  ExecutorBindingUpdateCompleted(result)
                }
                ExecutorBindingReferencePutSuspended(_) => {
                  request.phase = ExecutorBindingUpdateHaveCurrent(
                    reference, current,
                  )
                  ExecutorBindingUpdateSuspended(request)
                }
              }
            }
          }
      }
  }
}

///|
// Complete a binding update for synchronous runtime owners. Dynamic binding
// resolution and object conversion use the same coordinator as bytecode, so
// a suspended request keeps its one resolved reference through every child.
fn Interpreter::run_binding_update_to_completion(
  self : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  op : @ast.UpdateOp,
  prefix : Bool,
  loc : @token.Loc,
) -> Value raise Error {
  match begin_executor_binding_update(self, ctx, env, name, op, prefix, loc) {
    ExecutorBindingUpdateCompleted(value) => value
    ExecutorBindingUpdateSuspended(request) => {
      let frame = ExecutorBindingUpdateFrame(request)
      match
        self.run_executor_activation_coordinator(
          frame as &ExecutorActivationFrame,
        ) {
        ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
          value
        _ =>
          raise @errors.InternalError(
            message="binding update coordinator returned a pending activation",
          )
      }
    }
  }
}

///|
pub fn executor_activation_binding_update_request(
  request : ExecutorBindingUpdateRequest,
) -> ExecutorActivationStep {
  ExecutorActivationBindingUpdate(request)
}

///|
priv struct ExecutorBindingUpdateFrame {
  request : ExecutorBindingUpdateRequest
}

///|
fn ExecutorBindingUpdateFrame::ExecutorBindingUpdateFrame(
  request : ExecutorBindingUpdateRequest,
) -> ExecutorBindingUpdateFrame {
  { request, }
}

///|
fn ExecutorBindingUpdateFrame::begin_put(
  self : ExecutorBindingUpdateFrame,
  interp : Interpreter,
  reference : ResolvedBindingReference,
  old_number : Double,
) -> ExecutorActivationStep raise Error {
  let next_value : Value = match self.request.operator {
    ExecutorBindingIncrement => Number(old_number + 1.0)
    ExecutorBindingDecrement => Number(old_number - 1.0)
  }
  let result = if self.request.prefix { next_value } else { Number(old_number) }
  match begin_executor_binding_reference_put(interp, reference, next_value) {
    ExecutorBindingReferencePutCompleted(value) => {
      ignore(value)
      self.request.phase = ExecutorBindingUpdateComplete(result)
      ExecutorActivationNormal(result)
    }
    ExecutorBindingReferencePutSuspended(operation) => {
      self.request.phase = ExecutorBindingUpdateAwaitPut(operation, result)
      operation.step(interp)
    }
  }
}

///|
fn ExecutorBindingUpdateFrame::begin_to_primitive(
  self : ExecutorBindingUpdateFrame,
  interp : Interpreter,
  reference : ResolvedBindingReference,
  current : Value,
) -> ExecutorActivationStep raise Error {
  let operation = ExecutorToPrimitiveOperation(
    current,
    ExecutorToPrimitiveNumber,
    self.request.loc,
  )
  match operation.step(interp) {
    ExecutorActivationNormal(value) =>
      self.begin_put(interp, reference, to_number(value, interp=Some(interp)))
    step => {
      self.request.phase = ExecutorBindingUpdateAwaitToPrimitive(
        reference, current, operation,
      )
      step
    }
  }
}

///|
fn ExecutorBindingUpdateFrame::step_frame(
  self : ExecutorBindingUpdateFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.request.phase {
    ExecutorBindingUpdateNeedReference(reference_request) => {
      self.request.phase = ExecutorBindingUpdateAwaitReference
      ExecutorActivationBindingReference(reference_request)
    }
    ExecutorBindingUpdateNeedGet(reference) =>
      match begin_executor_binding_reference_get(interp, reference) {
        ExecutorBindingReferenceGetCompleted(value) => {
          self.request.phase = ExecutorBindingUpdateHaveCurrent(
            reference, value,
          )
          self.step_frame(interp)
        }
        ExecutorBindingReferenceGetSuspended(step) => {
          self.request.phase = ExecutorBindingUpdateAwaitGet(reference)
          step
        }
      }
    ExecutorBindingUpdateHaveCurrent(reference, current) =>
      if is_js_object(current) {
        self.begin_to_primitive(interp, reference, current)
      } else {
        self.begin_put(
          interp,
          reference,
          to_number(current, interp=Some(interp)),
        )
      }
    ExecutorBindingUpdateAwaitToPrimitive(reference, current, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.begin_put(
            interp,
            reference,
            to_number(value, interp=Some(interp)),
          )
        step => {
          self.request.phase = ExecutorBindingUpdateAwaitToPrimitive(
            reference, current, operation,
          )
          step
        }
      }
    ExecutorBindingUpdateAwaitPut(operation, result) =>
      match operation.step(interp) {
        ExecutorActivationNormal(_) => {
          self.request.phase = ExecutorBindingUpdateComplete(result)
          ExecutorActivationNormal(result)
        }
        step => {
          self.request.phase = ExecutorBindingUpdateAwaitPut(operation, result)
          step
        }
      }
    ExecutorBindingUpdateComplete(result) => ExecutorActivationNormal(result)
    ExecutorBindingUpdateAwaitReference | ExecutorBindingUpdateAwaitGet(_) =>
      raise @errors.InternalError(
        message="binding update stepped while awaiting a child completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorBindingUpdateFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorBindingUpdateFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionReference(reference) =>
      match self.request.phase {
        ExecutorBindingUpdateAwaitReference =>
          self.request.phase = ExecutorBindingUpdateNeedGet(reference)
        _ =>
          raise @errors.InternalError(
            message="binding update received an unexpected binding reference",
          )
      }
    ExecutorActivationCompletionNormal(value) =>
      match self.request.phase {
        ExecutorBindingUpdateAwaitGet(reference) =>
          self.request.phase = ExecutorBindingUpdateHaveCurrent(
            reference, value,
          )
        ExecutorBindingUpdateAwaitToPrimitive(_, _, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingUpdateAwaitPut(operation, _) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorBindingUpdateNeedReference(_)
        | ExecutorBindingUpdateAwaitReference
        | ExecutorBindingUpdateNeedGet(_)
        | ExecutorBindingUpdateHaveCurrent(_, _)
        | ExecutorBindingUpdateComplete(_) =>
          raise @errors.InternalError(
            message="binding update received an unexpected child completion",
          )
      }
  }
}

///|
// A closed static property-update request. Runtime owns the resumable
// get/convert/set pipeline and prefix/postfix result selection; executors only
// provide the already-evaluated target and update syntax.
pub struct ExecutorPropertyUpdateRequest {
  priv target : Value
  priv property_name : String
  priv operator : ExecutorPropertyUpdateOperator
  priv prefix : Bool
  priv member_loc : @token.Loc
  priv loc : @token.Loc
  priv strict : Bool
}

///|
priv enum ExecutorPropertyUpdateOperator {
  ExecutorPropertyIncrement
  ExecutorPropertyDecrement
}

///|
fn ExecutorPropertyUpdateRequest::ExecutorPropertyUpdateRequest(
  target~ : Value,
  property_name~ : String,
  operator~ : ExecutorPropertyUpdateOperator,
  prefix~ : Bool,
  member_loc~ : @token.Loc,
  loc~ : @token.Loc,
  strict~ : Bool,
) -> ExecutorPropertyUpdateRequest {
  { target, property_name, operator, prefix, member_loc, loc, strict }
}

///|
fn executor_activation_property_update(
  target : Value,
  property_name : String,
  operator : ExecutorPropertyUpdateOperator,
  prefix : Bool,
  member_loc : @token.Loc,
  loc : @token.Loc,
  strict : Bool,
) -> ExecutorActivationStep {
  ExecutorActivationPropertyUpdate(
    ExecutorPropertyUpdateRequest(
      target~,
      property_name~,
      operator~,
      prefix~,
      member_loc~,
      loc~,
      strict~,
    ),
  )
}

///|
pub fn executor_activation_property_increment(
  target : Value,
  property_name : String,
  prefix : Bool,
  member_loc : @token.Loc,
  loc : @token.Loc,
  strict : Bool,
) -> ExecutorActivationStep {
  executor_activation_property_update(
    target,
    property_name,
    ExecutorPropertyIncrement,
    prefix,
    member_loc,
    loc,
    strict,
  )
}

///|
pub fn executor_activation_property_decrement(
  target : Value,
  property_name : String,
  prefix : Bool,
  member_loc : @token.Loc,
  loc : @token.Loc,
  strict : Bool,
) -> ExecutorActivationStep {
  executor_activation_property_update(
    target,
    property_name,
    ExecutorPropertyDecrement,
    prefix,
    member_loc,
    loc,
    strict,
  )
}

///|
// Admit an already-evaluated computed property only when its key is an exact
// primitive string and the existing callback-free ordinary-own accessor
// classifier can seal the getter and executable. The compiler receives only
// the resulting activation request; object-shape rules stay runtime-owned.
pub fn executor_activation_computed_property_get_if_admitted(
  target : Value,
  key : Value,
  loc : @token.Loc,
) -> ExecutorActivationStep? {
  match key {
    String_(property_name) =>
      match direct_executor_property_getter(target, property_name) {
        Some((getter, executable)) =>
          Some(
            ExecutorActivationPropertyGet(
              ExecutorPropertyGetRequest(
                target~,
                key=ExecutorStringPropertyGetKey(property_name),
                receiver=target,
                loc~,
                manage_proxy=false,
                admission=Some(
                  ExecutorPropertyGetAdmission(getter~, executable~),
                ),
              ),
            ),
          )
        None => None
      }
    _ => None
  }
}

///|
priv struct ExecutorPropertyGetAdmission {
  getter : Value
  executable : ExecutorCallableData
}

///|
fn ExecutorPropertyGetAdmission::ExecutorPropertyGetAdmission(
  getter~ : Value,
  executable~ : ExecutorCallableData,
) -> ExecutorPropertyGetAdmission {
  { getter, executable }
}

///|
// A closed direct-construction request. Runtime retains ownership of
// constructability, prototype selection, instance allocation, new.target, and
// constructor completion; executors only provide already-evaluated operands.
pub struct ExecutorConstructRequest {
  priv ctor : Value
  priv args : Array[Value]
  priv loc : @token.Loc
}

///|
fn ExecutorConstructRequest::ExecutorConstructRequest(
  ctor~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorConstructRequest {
  { ctor, args: args.copy(), loc }
}

///|
pub fn executor_activation_construct(
  ctor : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> ExecutorActivationStep {
  ExecutorActivationConstruct(ExecutorConstructRequest(ctor~, args~, loc~))
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
  fn deliver_activation_completion(Self, ExecutorActivationCompletion) -> Unit raise Error
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
  priv activation_capability_summary : ExecutorActivationCapabilitySummary?
  // Exact parser text for prepared bytecode functions. This is source
  // metadata only and never participates in execution or capability checks.
  priv source_text : String?
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
pub fn ExecutorCallableData::source_text(
  self : ExecutorCallableData,
) -> String? {
  self.source_text
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
  property_scope : ClearedActiveCalleeRealmScope?
  saved_in_default : Bool
  saved_param_default_conflicts : @set.Set[String]?
}

///|
priv enum ExecutorChildCompletion {
  ExecutorChildCall(ExecutorCallableKind)
  ExecutorChildArrayForEach
  ExecutorChildConstruct(Value)
  ExecutorChildPropertyGet
  ExecutorChildPropertySet(Value)
  ExecutorChildPropertyUpdate
  ExecutorChildCoercingAddition
  ExecutorChildCoercingRelational
  ExecutorChildCoercingSubtraction
  ExecutorChildPropertyDelete
  ExecutorChildIterableSpread
  ExecutorChildCopyDataProperties
  ExecutorChildBinding
  ExecutorChildBindingReference
  ExecutorChildBindingUpdate
}

///|
priv enum ExecutorProxyPropertyGetPhase {
  ExecutorProxyPropertyGetNeedTrap
  ExecutorProxyPropertyGetAwaitTrapLookup
  ExecutorProxyPropertyGetHaveTrap(Value)
  ExecutorProxyPropertyGetAwaitTrapCall
  ExecutorProxyPropertyGetHaveTrapResult(Value)
  ExecutorProxyPropertyGetAwaitForward
  ExecutorProxyPropertyGetComplete(Value)
}

///|
priv struct ExecutorProxyPropertyGetFrame {
  target : Value
  handler : Value
  key : ExecutorPropertyGetKey
  receiver : Value
  loc : @token.Loc
  mut phase : ExecutorProxyPropertyGetPhase
}

///|
fn ExecutorProxyPropertyGetFrame::ExecutorProxyPropertyGetFrame(
  target~ : Value,
  handler~ : Value,
  key~ : ExecutorPropertyGetKey,
  receiver~ : Value,
  loc~ : @token.Loc,
) -> ExecutorProxyPropertyGetFrame {
  {
    target,
    handler,
    key,
    receiver,
    loc,
    phase: ExecutorProxyPropertyGetNeedTrap,
  }
}

///|
fn reduce_executor_proxy_property_get_completion(
  phase : ExecutorProxyPropertyGetPhase,
  completion : ExecutorActivationCompletion,
) -> ExecutorProxyPropertyGetPhase raise Error {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="proxy property get received a binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) =>
      match phase {
        ExecutorProxyPropertyGetAwaitTrapLookup =>
          ExecutorProxyPropertyGetHaveTrap(value)
        ExecutorProxyPropertyGetAwaitTrapCall =>
          ExecutorProxyPropertyGetHaveTrapResult(value)
        ExecutorProxyPropertyGetAwaitForward =>
          ExecutorProxyPropertyGetComplete(value)
        ExecutorProxyPropertyGetNeedTrap
        | ExecutorProxyPropertyGetHaveTrap(_)
        | ExecutorProxyPropertyGetHaveTrapResult(_)
        | ExecutorProxyPropertyGetComplete(_) =>
          raise @errors.InternalError(
            message="Proxy property get received an unexpected child completion",
          )
      }
  }
}

///|
impl ExecutorActivationFrame for ExecutorProxyPropertyGetFrame with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorProxyPropertyGetNeedTrap => {
      self.phase = ExecutorProxyPropertyGetAwaitTrapLookup
      executor_activation_managed_property_get(self.handler, "get", self.loc)
    }
    ExecutorProxyPropertyGetHaveTrap(trap) =>
      match trap {
        Undefined | Null => {
          self.phase = ExecutorProxyPropertyGetAwaitForward
          executor_activation_property_get_with_receiver(
            self.target,
            self.key,
            self.receiver,
            self.loc,
            true,
          )
        }
        _ if is_callable(trap) => {
          self.phase = ExecutorProxyPropertyGetAwaitTrapCall
          ExecutorActivationCall(
            ExecutorCallRequest(
              callee=trap,
              this_value=self.handler,
              args=[
                self.target,
                executor_property_get_key_value(self.key),
                self.receiver,
              ],
              loc=self.loc,
            ),
          )
        }
        _ =>
          raise @errors.TypeError(
            message="'get' on proxy: trap is not a function",
          )
      }
    ExecutorProxyPropertyGetHaveTrapResult(result) => {
      validate_proxy_get_trap_result(
        interp,
        self.target,
        executor_property_get_key_value(self.key),
        result,
      )
      self.phase = ExecutorProxyPropertyGetComplete(result)
      ExecutorActivationNormal(result)
    }
    ExecutorProxyPropertyGetComplete(result) => ExecutorActivationNormal(result)
    ExecutorProxyPropertyGetAwaitTrapLookup
    | ExecutorProxyPropertyGetAwaitTrapCall
    | ExecutorProxyPropertyGetAwaitForward =>
      raise @errors.InternalError(
        message="Proxy property get stepped while awaiting a child completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorProxyPropertyGetFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  self.phase = reduce_executor_proxy_property_get_completion(
    self.phase,
    completion,
  )
}

///|
priv enum ExecutorPropertyUpdatePhase {
  ExecutorPropertyUpdateNeedGet
  ExecutorPropertyUpdateAwaitGet
  ExecutorPropertyUpdateHaveCurrent(Value)
  ExecutorPropertyUpdateAwaitToPrimitive(ExecutorToPrimitiveOperation)
  ExecutorPropertyUpdateAwaitSet(Value)
  ExecutorPropertyUpdateComplete(Value)
}

///|
priv struct ExecutorPropertyUpdateFrame {
  request : ExecutorPropertyUpdateRequest
  mut phase : ExecutorPropertyUpdatePhase
}

///|
fn ExecutorPropertyUpdateFrame::ExecutorPropertyUpdateFrame(
  request : ExecutorPropertyUpdateRequest,
) -> ExecutorPropertyUpdateFrame {
  { request, phase: ExecutorPropertyUpdateNeedGet }
}

///|
fn plan_executor_property_update_set(
  request : ExecutorPropertyUpdateRequest,
  old_number : Double,
) -> (ExecutorPropertyUpdatePhase, ExecutorActivationStep) {
  let next_value : Value = match request.operator {
    ExecutorPropertyIncrement => Number(old_number + 1.0)
    ExecutorPropertyDecrement => Number(old_number - 1.0)
  }
  let result = if request.prefix { next_value } else { Number(old_number) }
  (
    ExecutorPropertyUpdateAwaitSet(result),
    executor_activation_property_set(
      request.target,
      request.property_name,
      next_value,
      request.loc,
      request.strict,
    ),
  )
}

///|
fn reduce_executor_property_update_completion(
  phase : ExecutorPropertyUpdatePhase,
  completion : ExecutorActivationCompletion,
) -> ExecutorPropertyUpdatePhase raise Error {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="property update received a binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) =>
      match phase {
        ExecutorPropertyUpdateAwaitGet =>
          ExecutorPropertyUpdateHaveCurrent(value)
        ExecutorPropertyUpdateAwaitToPrimitive(operation) => {
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
          ExecutorPropertyUpdateAwaitToPrimitive(operation)
        }
        ExecutorPropertyUpdateAwaitSet(result) =>
          ExecutorPropertyUpdateComplete(result)
        ExecutorPropertyUpdateNeedGet
        | ExecutorPropertyUpdateHaveCurrent(_)
        | ExecutorPropertyUpdateComplete(_) =>
          raise @errors.InternalError(
            message="property update received an unexpected child completion",
          )
      }
  }
}

///|
fn ExecutorPropertyUpdateFrame::begin_to_primitive(
  self : ExecutorPropertyUpdateFrame,
  current : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let operation = ExecutorToPrimitiveOperation(
    current,
    ExecutorToPrimitiveNumber,
    self.request.loc,
  )
  match operation.step(interp) {
    ExecutorActivationNormal(value) =>
      self.begin_set(to_number(value, interp=Some(interp)))
    step => {
      self.phase = ExecutorPropertyUpdateAwaitToPrimitive(operation)
      step
    }
  }
}

///|
fn ExecutorPropertyUpdateFrame::begin_set(
  self : ExecutorPropertyUpdateFrame,
  old_number : Double,
) -> ExecutorActivationStep {
  let (next_phase, step) = plan_executor_property_update_set(
    self.request,
    old_number,
  )
  self.phase = next_phase
  step
}

///|
impl ExecutorActivationFrame for ExecutorPropertyUpdateFrame with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorPropertyUpdateNeedGet => {
      self.phase = ExecutorPropertyUpdateAwaitGet
      executor_activation_property_get(
        self.request.target,
        self.request.property_name,
        self.request.member_loc,
      )
    }
    ExecutorPropertyUpdateHaveCurrent(current) =>
      if is_js_object(current) {
        self.begin_to_primitive(current, interp)
      } else {
        self.begin_set(to_number(current, interp=Some(interp)))
      }
    ExecutorPropertyUpdateAwaitToPrimitive(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          self.begin_set(to_number(value, interp=Some(interp)))
        step => {
          self.phase = ExecutorPropertyUpdateAwaitToPrimitive(operation)
          step
        }
      }
    ExecutorPropertyUpdateComplete(result) => ExecutorActivationNormal(result)
    ExecutorPropertyUpdateAwaitGet =>
      raise @errors.InternalError(
        message="property update stepped while awaiting a child completion",
      )
    ExecutorPropertyUpdateAwaitSet(_) =>
      raise @errors.InternalError(
        message="property update stepped while awaiting a child completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorPropertyUpdateFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  self.phase = reduce_executor_property_update_completion(
    self.phase,
    completion,
  )
}

///|
priv enum ExecutorActivationStart {
  ExecutorStartCall(ExecutorCallRequest)
  ExecutorStartConstruct(ExecutorConstructRequest)
  ExecutorStartPropertySet(ExecutorCallRequest, Value)
}

///|
priv struct ExecutorActivationStackEntry {
  frame : &ExecutorActivationFrame
  completion : ExecutorChildCompletion?
  cleanup : ExecutorActivationCleanup?
  graph_cursor : TreeExecutorGraphCursor?
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
  let release_error : Error? = try {
    cleanup.observation.release()
    None
  } catch {
    InvalidActivationObservationTransition(message) =>
      Some(
        @errors.InternalError(
          message="executor activation release is invalid: " + message,
        ),
      )
  }
  match cleanup.property_scope {
    Some(scope) => finish_cleared_active_callee_realm(self.realm_state, scope)
    None => ()
  }
  match release_error {
    Some(error) => raise error
    None => ()
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
  start : ExecutorActivationStart,
  property_scope : ClearedActiveCalleeRealmScope?,
  graph_cursor? : TreeExecutorGraphCursor? = None,
) -> ExecutorActivationStackEntry raise Error {
  let callee = match start {
    ExecutorStartCall(request) => request.callee
    ExecutorStartConstruct(request) => request.ctor
    ExecutorStartPropertySet(request, _) => request.callee
  }
  let observation = observe_executor_activation_entry(self) catch {
    error => {
      match property_scope {
        Some(scope) =>
          finish_cleared_active_callee_realm(self.realm_state, scope)
        None => ()
      }
      raise error
    }
  }
  let cleared_realm = begin_cleared_active_callee_realm(self.realm_state)
  let active_realm = begin_active_callee_realm_value(self.realm_state, callee)
  let saved_in_default = self.in_nonarrow_param_default_eval
  let saved_param_default_conflicts = self.param_default_eval_var_conflicts
  self.in_nonarrow_param_default_eval = false
  self.param_default_eval_var_conflicts = None
  let setup : Result[(&ExecutorActivationFrame, ExecutorChildCompletion), Error] = Ok(
    match start {
      ExecutorStartCall(request) => {
        let prepared = self.prepare_executor_callable_call(
          executable,
          request.callee,
          request.this_value,
          request.args,
        )
        (
          executable.start_frame(self, prepared),
          ExecutorChildCall(executable.kind),
        )
      }
      ExecutorStartPropertySet(request, value) => {
        let prepared = self.prepare_executor_callable_call(
          executable,
          request.callee,
          request.this_value,
          request.args,
        )
        (
          executable.start_frame(self, prepared),
          ExecutorChildPropertySet(value),
        )
      }
      ExecutorStartConstruct(request) => {
        let proto = self.get_prototype_from_constructor(
          request.ctor,
          request.loc,
        )
        let instance = make_constructor_instance(proto, "Object")
        let prepared = self.prepare_executor_activation(
          request.ctor,
          instance,
          request.args,
          executable.params,
          executable.rest_param,
          executable.closure,
          executable.strict,
          Some(request.ctor),
          !executable.constructable,
          executable.self_name,
          executable.define_arguments_object,
        )
        (
          executable.start_frame(self, prepared),
          ExecutorChildConstruct(instance),
        )
      }
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
      let release_error : Error? = try {
        release_rejected_executor_activation_observation(observation)
        None
      } catch {
        error => Some(error)
      }
      match property_scope {
        Some(scope) =>
          finish_cleared_active_callee_realm(self.realm_state, scope)
        None => ()
      }
      match release_error {
        Some(cleanup_error) => raise cleanup_error
        None => raise error
      }
    }
    Ok((frame, completion)) => {
      let accepted = observation.accept()
      {
        frame,
        completion: Some(completion),
        cleanup: Some({
          observation: accepted,
          cleared_realm,
          active_realm,
          property_scope,
          saved_in_default,
          saved_param_default_conflicts,
        }),
        graph_cursor,
      }
    }
  }
}

///|
fn Interpreter::complete_executor_child(
  self : Interpreter,
  stack : Array[ExecutorActivationStackEntry],
  completion : ExecutorActivationCompletion,
) -> Unit raise Error {
  let entry = stack.pop().unwrap()
  let failure = match completion {
    ExecutorActivationCompletionAbrupt(error) => Some(error)
    ExecutorActivationCompletionNormal(_) => None
    ExecutorActivationCompletionReference(_) => None
  }
  match entry.cleanup {
    Some(cleanup) => self.finish_executor_activation(cleanup, failure)
    None => ()
  }
  let parent = stack[stack.length() - 1].frame
  parent.deliver_activation_completion(completion)
}

///|
fn Interpreter::complete_executor_step(
  self : Interpreter,
  stack : Array[ExecutorActivationStackEntry],
  step : ExecutorActivationStep,
) -> Unit raise Error {
  let completion = match stack[stack.length() - 1].completion {
    Some(ExecutorChildCall(kind)) =>
      ExecutorActivationCompletionNormal(executor_call_completion(kind, step))
    Some(ExecutorChildArrayForEach) => executor_array_for_each_completion(step)
    Some(ExecutorChildConstruct(instance)) =>
      ExecutorActivationCompletionNormal(
        executor_construct_completion(step, instance),
      )
    Some(ExecutorChildPropertyGet) => executor_property_get_completion(step)
    Some(ExecutorChildPropertySet(value)) =>
      executor_property_set_completion(value)
    Some(ExecutorChildPropertyUpdate) =>
      executor_property_update_completion(step)
    Some(ExecutorChildCoercingAddition) =>
      executor_coercing_addition_completion(step)
    Some(ExecutorChildCoercingRelational) =>
      executor_coercing_relational_completion(step)
    Some(ExecutorChildCoercingSubtraction) =>
      executor_coercing_subtraction_completion(step)
    Some(ExecutorChildPropertyDelete) =>
      executor_property_delete_completion(step)
    Some(ExecutorChildIterableSpread) =>
      executor_iterable_spread_completion(step)
    Some(ExecutorChildCopyDataProperties) =>
      executor_copy_data_properties_completion(step)
    Some(ExecutorChildBinding) => executor_binding_completion(step)
    Some(ExecutorChildBindingReference) =>
      executor_binding_reference_completion(step)
    Some(ExecutorChildBindingUpdate) => executor_binding_update_completion(step)
    None => ExecutorActivationCompletionNormal(Undefined)
  }
  self.complete_executor_child(stack, completion)
}

///|
fn executor_array_for_each_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(_) | ExecutorActivationReturn(_) =>
      ExecutorActivationCompletionNormal(Undefined)
    _ =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(message="forEach frame completed without a value"),
      )
  }
}

///|
fn executor_binding_reference_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationReference(reference) =>
      ExecutorActivationCompletionReference(reference)
    _ =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="binding reference frame completed without a reference",
        ),
      )
  }
}

///|
fn executor_binding_update_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    _ =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="binding update completed with a pending activation",
        ),
      )
  }
}

///|
fn executor_iterable_spread_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    _ =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="iterable spread frame completed without a value",
        ),
      )
  }
}

///|
fn executor_copy_data_properties_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(_) | ExecutorActivationReturn(_) =>
      ExecutorActivationCompletionNormal(Undefined)
    _ =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="CopyDataProperties frame completed with a pending step",
        ),
      )
  }
}

///|
fn Interpreter::deliver_executor_activation_error(
  self : Interpreter,
  stack : Array[ExecutorActivationStackEntry],
  index : Int,
  error : Error,
) -> Unit raise Error {
  if index == 0 {
    raise error
  } else {
    self.complete_executor_child(
      stack,
      ExecutorActivationCompletionAbrupt(error),
    ) catch {
      nested_error =>
        self.deliver_executor_activation_error(
          stack,
          stack.length() - 1,
          nested_error,
        )
    }
  }
}

///|
fn deliver_executor_activation_request_error(
  frame : &ExecutorActivationFrame,
  error : Error,
) -> Unit raise Error {
  frame.deliver_activation_completion(ExecutorActivationCompletionAbrupt(error))
}

///|
fn deliver_executor_activation_request(
  frame : &ExecutorActivationFrame,
  requested : Result[ExecutorActivationRequestOutcome, Error],
) -> Unit raise Error {
  match requested {
    Ok(ExecutorActivationRequestChild) => ()
    Ok(ExecutorActivationRequestValue(value)) =>
      frame.deliver_activation_completion(
        ExecutorActivationCompletionNormal(value),
      )
    Err(error) => deliver_executor_activation_request_error(frame, error)
  }
}

///|
fn direct_executor_constructor_with_data_prototype(
  ctor : Value,
) -> ExecutorCallableData? {
  match ctor {
    Object(object_data) =>
      match object_data.callable {
        Some(ExecutorCallable(executable)) if executable.constructable =>
          match object_data.bag.descriptors.get("prototype") {
            Some(descriptor) if !descriptor.is_accessor &&
              object_data.bag.properties.contains("prototype") =>
              Some(executable)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
// Callback-free admission for an exact own accessor. Computed-property
// admission deliberately retains this narrower boundary.
fn direct_executor_property_getter(
  target : Value,
  property_name : String,
) -> (Value, ExecutorCallableData)? {
  match target {
    Object(data) if data.class_name == "Object" &&
      data.callable is None &&
      data.arraybuffer_state is None &&
      data.bag.internal_slots.is_empty() &&
      data.bag.host_slots.is_empty() =>
      match data.bag.descriptors.get(property_name) {
        Some(descriptor) if descriptor.is_accessor =>
          match descriptor.getter {
            Some(getter) =>
              match getter {
                Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
                  Some((getter, executable))
                _ => None
              }
            None => None
          }
        _ => None
      }
    _ => None
  }
}

///|
// Callback-free lookup for the iterative static-property slice. A plain
// ordinary prototype chain is inspected directly so no guest code runs before
// the property scope and executor activation are installed. The original
// target remains the receiver when an inherited getter is selected.
fn direct_executor_property_getter_in_plain_chain(
  target : Value,
  property_name : String,
) -> (Value, ExecutorCallableData)? {
  for current = target {
    match current {
      Object(data) if data.class_name == "Object" &&
        data.callable is None &&
        data.arraybuffer_state is None &&
        data.bag.internal_slots.is_empty() &&
        data.bag.host_slots.is_empty() =>
        match data.bag.descriptors.get(property_name) {
          Some(descriptor) if descriptor.is_accessor =>
            match descriptor.getter {
              Some(getter) =>
                match getter {
                  Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
                    break Some((getter, executable))
                  _ => break None
                }
              None => break None
            }
          Some(_) => break None
          None =>
            if data.bag.properties.contains(property_name) {
              break None
            } else {
              continue data.prototype
            }
        }
      _ => break None
    }
  }
}

///|
// Callback-free admission for the one iterative static-property mutation
// slice. This mirrors the getter classifier but admits only an exact own
// accessor setter carrying sealed executor data.
fn direct_executor_property_setter(
  target : Value,
  property_name : String,
) -> (Value, ExecutorCallableData)? {
  for current = target {
    match current {
      Object(data) if data.class_name == "Object" &&
        data.callable is None &&
        data.arraybuffer_state is None &&
        data.bag.internal_slots.is_empty() &&
        data.bag.host_slots.is_empty() =>
        match data.bag.descriptors.get(property_name) {
          Some(descriptor) if descriptor.is_accessor =>
            match descriptor.setter {
              Some(setter) =>
                match setter {
                  Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
                    break Some((setter, executable))
                  _ => break None
                }
              None => break None
            }
          Some(_) => break None
          None =>
            if data.bag.properties.contains(property_name) {
              break None
            } else {
              continue data.prototype
            }
        }
      _ => break None
    }
  }
}

///|
// Callback-free lookup for an executor-backed symbol accessor on a plain
// ordinary prototype chain. The original target remains the receiver.
fn direct_executor_symbol_property_getter_in_plain_chain(
  target : Value,
  symbol_id : Int,
) -> (Value, ExecutorCallableData)? {
  for current = target {
    match current {
      Object(data) if data.class_name == "Object" &&
        data.callable is None &&
        data.arraybuffer_state is None &&
        data.bag.internal_slots.is_empty() &&
        data.bag.host_slots.is_empty() =>
        match data.bag.symbol_descriptors.get(symbol_id) {
          Some(descriptor) if descriptor.is_accessor =>
            match descriptor.getter {
              Some(getter) =>
                match getter {
                  Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
                    break Some((getter, executable))
                  _ => break None
                }
              None => break None
            }
          Some(_) => break None
          None =>
            if data.bag.symbol_properties.contains(symbol_id) {
              break None
            } else {
              continue data.prototype
            }
        }
      _ => break None
    }
  }
}

///|
// Find the first Proxy reached by an ordinary [[Get]] prototype walk before
// the requested key is found. This inspection is callback-free; the caller
// keeps the original receiver when it resumes lookup at the Proxy boundary.
fn direct_executor_proxy_boundary_in_plain_chain(
  target : Value,
  key : ExecutorPropertyGetKey,
) -> Value? {
  for current = target {
    match current {
      Proxy(_) => break Some(current)
      Object(data) if data.class_name == "Object" &&
        data.callable is None &&
        data.arraybuffer_state is None &&
        data.bag.internal_slots.is_empty() &&
        data.bag.host_slots.is_empty() => {
        let has_own = match key {
          ExecutorStringPropertyGetKey(property_name) =>
            data.bag.descriptors.contains(property_name) ||
            data.bag.properties.contains(property_name)
          ExecutorSymbolPropertyGetKey(symbol) =>
            data.bag.symbol_descriptors.contains(symbol.id) ||
            data.bag.symbol_properties.contains(symbol.id)
        }
        if has_own {
          break None
        } else {
          continue data.prototype
        }
      }
      _ => break None
    }
  }
}

///|
fn Interpreter::executor_activation_fallback_call(
  self : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> ExecutorActivationRequestOutcome raise Error {
  ExecutorActivationRequestValue(self.call_value(callee, this_value, args, loc))
}

///|
fn Interpreter::handle_executor_activation_step(
  self : Interpreter,
  stack : Array[ExecutorActivationStackEntry],
  index : Int,
  step : ExecutorActivationStep,
) -> ExecutorActivationStep? raise Error {
  let frame = stack[index].frame
  match step {
    ExecutorActivationContinue => None
    ExecutorActivationNormal(value) =>
      if index == 0 {
        Some(ExecutorActivationNormal(value))
      } else {
        self.complete_executor_step(stack, ExecutorActivationNormal(value))
        None
      }
    ExecutorActivationReturn(value) =>
      if index == 0 {
        Some(ExecutorActivationReturn(value))
      } else {
        self.complete_executor_step(stack, ExecutorActivationReturn(value))
        None
      }
    ExecutorActivationReference(reference) =>
      if index == 0 {
        Some(ExecutorActivationReference(reference))
      } else {
        self.complete_executor_step(
          stack,
          ExecutorActivationReference(reference),
        )
        None
      }
    ExecutorActivationCopyDataProperties(request) => {
      let copy_frame = ExecutorCopyDataPropertiesFrame(request)
      stack.push({
        frame: copy_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildCopyDataProperties),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationBinding(request) => {
      let binding_frame = ExecutorBindingFrame(request)
      stack.push({
        frame: binding_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildBinding),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationBindingReference(request) => {
      let binding_frame = ExecutorBindingReferenceFrame(request)
      stack.push({
        frame: binding_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildBindingReference),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationBindingUpdate(request) => {
      let binding_update_frame = ExecutorBindingUpdateFrame(request)
      stack.push({
        frame: binding_update_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildBindingUpdate),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationCall(request) => {
      let requested : Result[ExecutorActivationRequestOutcome, Error] = Ok(
        {
          let (forwarded_callee, forwarded_this_value, forwarded_args) = self.resolve_call_forwarding(
            request.callee,
            request.this_value,
            request.args,
          )
          match
            executor_array_for_each_request(
              self,
              forwarded_callee,
              forwarded_this_value,
              forwarded_args,
              request.loc,
            ) {
            Some(array_request) => {
              let array_frame = ExecutorArrayForEachFrame(array_request)
              stack.push({
                frame: array_frame as &ExecutorActivationFrame,
                completion: Some(ExecutorChildArrayForEach),
                cleanup: None,
                graph_cursor: None,
              })
              ExecutorActivationRequestChild
            }
            None =>
              match stack[index].graph_cursor {
                Some(graph_cursor) => {
                  let edge = match
                    tree_executor_graph_select_edge(
                      graph_cursor,
                      forwarded_callee,
                      forwarded_args.length(),
                    ) {
                    Some(edge) => edge
                    None =>
                      raise @errors.InternalError(
                        message="executor activation graph proof was violated by an unmatched call",
                      )
                  }
                  let admission = match
                    tree_executor_graph_target(graph_cursor, edge) {
                    Some(admission) => admission
                    None =>
                      raise @errors.InternalError(
                        message="executor activation graph target was invalid",
                      )
                  }
                  let forwarded_request = ExecutorCallRequest(
                    callee=forwarded_callee,
                    this_value=forwarded_this_value,
                    args=forwarded_args,
                    loc=request.loc,
                  )
                  stack.push(
                    self.start_executor_activation(
                      admission.executable,
                      ExecutorStartCall(forwarded_request),
                      None,
                      graph_cursor=Some(admission.cursor),
                    ),
                  )
                  ExecutorActivationRequestChild
                }
                None =>
                  match forwarded_callee {
                    Object({ callable: Some(ExecutorCallable(executable)), .. }) => {
                      let forwarded_request = ExecutorCallRequest(
                        callee=forwarded_callee,
                        this_value=forwarded_this_value,
                        args=forwarded_args,
                        loc=request.loc,
                      )
                      stack.push(
                        self.start_executor_activation(
                          executable,
                          ExecutorStartCall(forwarded_request),
                          None,
                        ),
                      )
                      ExecutorActivationRequestChild
                    }
                    Object({ callable: Some(UserFunc(data)), .. }) =>
                      match
                        tree_executor_callable_admission(
                          forwarded_callee, data, forwarded_args,
                        ) {
                        Some(admission) => {
                          let forwarded_request = ExecutorCallRequest(
                            callee=forwarded_callee,
                            this_value=forwarded_this_value,
                            args=forwarded_args,
                            loc=request.loc,
                          )
                          stack.push(
                            self.start_executor_activation(
                              admission.executable,
                              ExecutorStartCall(forwarded_request),
                              None,
                              graph_cursor=Some(admission.cursor),
                            ),
                          )
                          ExecutorActivationRequestChild
                        }
                        None =>
                          self.executor_activation_fallback_call(
                            forwarded_callee,
                            forwarded_this_value,
                            forwarded_args,
                            request.loc,
                          )
                      }
                    _ =>
                      self.executor_activation_fallback_call(
                        forwarded_callee,
                        forwarded_this_value,
                        forwarded_args,
                        request.loc,
                      )
                  }
              }
          }
        },
      ) catch {
        error => Err(error)
      }
      deliver_executor_activation_request(frame, requested)
      None
    }
    ExecutorActivationConstruct(request) => {
      let requested : Result[ExecutorActivationRequestOutcome, Error] = Ok(
        match direct_executor_constructor_with_data_prototype(request.ctor) {
          Some(executable) => {
            stack.push(
              self.start_executor_activation(
                executable,
                ExecutorStartConstruct(request),
                None,
              ),
            )
            ExecutorActivationRequestChild
          }
          None =>
            ExecutorActivationRequestValue(
              self.construct_value(request.ctor, request.args, request.loc),
            )
        },
      ) catch {
        error => Err(error)
      }
      deliver_executor_activation_request(frame, requested)
      None
    }
    ExecutorActivationPropertyGet(request) => {
      let requested : Result[ExecutorActivationRequestOutcome, Error] = Ok(
        {
          let proxy_boundary = if request.manage_proxy {
            direct_executor_proxy_boundary_in_plain_chain(
              request.target,
              request.key,
            )
          } else {
            None
          }
          match proxy_boundary {
            Some(Proxy(proxy_data)) => {
              let handler = match proxy_data.handler {
                Some(handler) => handler
                None =>
                  raise @errors.TypeError(
                    message="Cannot perform 'get' on a proxy that has been revoked",
                  )
              }
              let target = match proxy_data.target {
                Some(target) => target
                None =>
                  raise @errors.TypeError(
                    message="Cannot perform 'get' on a proxy that has been revoked",
                  )
              }
              let proxy_frame = ExecutorProxyPropertyGetFrame(
                target~,
                handler~,
                key=request.key,
                receiver=request.receiver,
                loc=request.loc,
              )
              stack.push({
                frame: proxy_frame as &ExecutorActivationFrame,
                completion: Some(ExecutorChildPropertyGet),
                cleanup: None,
                graph_cursor: None,
              })
              return None
            }
            _ => ()
          }
          let admitted = match request.admission {
            Some(admission) => Some((admission.getter, admission.executable))
            None =>
              match request.key {
                ExecutorStringPropertyGetKey(property_name) =>
                  direct_executor_property_getter_in_plain_chain(
                    request.target,
                    property_name,
                  )
                ExecutorSymbolPropertyGetKey(symbol) =>
                  direct_executor_symbol_property_getter_in_plain_chain(
                    request.target,
                    symbol.id,
                  )
              }
          }
          match admitted {
            Some((getter, executable)) => {
              let property_scope = begin_cleared_active_callee_realm(
                self.realm_state,
              )
              let call_request = ExecutorCallRequest(
                callee=getter,
                this_value=request.receiver,
                args=[],
                loc=request.loc,
              )
              stack.push(
                self.start_executor_activation(
                  executable,
                  ExecutorStartCall(call_request),
                  Some(property_scope),
                ),
              )
              ExecutorActivationRequestChild
            }
            None =>
              ExecutorActivationRequestValue(
                match request.key {
                  ExecutorStringPropertyGetKey(property_name) =>
                    if request.manage_proxy {
                      self.get_property_key_with_receiver(
                        request.target,
                        String_(property_name),
                        request.receiver,
                        request.loc,
                      )
                    } else {
                      self.get_property(
                        request.target,
                        property_name,
                        request.loc,
                      )
                    }
                  ExecutorSymbolPropertyGetKey(symbol) =>
                    if request.manage_proxy {
                      self.get_property_key_with_receiver(
                        request.target,
                        Symbol(symbol),
                        request.receiver,
                        request.loc,
                      )
                    } else {
                      self.get_computed_property(
                        request.target,
                        Symbol(symbol),
                        request.loc,
                      )
                    }
                },
              )
          }
        },
      ) catch {
        error => Err(error)
      }
      deliver_executor_activation_request(frame, requested)
      None
    }
    ExecutorActivationPropertySet(request) => {
      if request.manage_proxy {
        let proxy_boundary = direct_executor_proxy_boundary_in_plain_chain(
          request.target,
          ExecutorStringPropertyGetKey(request.property_name),
        )
        match proxy_boundary {
          Some(Proxy(proxy_data)) => {
            let handler = match proxy_data.handler {
              Some(handler) => handler
              None =>
                raise @errors.TypeError(
                  message="Cannot perform 'set' on a proxy that has been revoked",
                )
            }
            let target = match proxy_data.target {
              Some(target) => target
              None =>
                raise @errors.TypeError(
                  message="Cannot perform 'set' on a proxy that has been revoked",
                )
            }
            let proxy_frame = ExecutorProxyPropertySetFrame(
              target~,
              handler~,
              property_name=request.property_name,
              value=request.value,
              receiver=request.target,
              strict=request.strict,
              loc=request.loc,
            )
            stack.push({
              frame: proxy_frame as &ExecutorActivationFrame,
              completion: Some(ExecutorChildPropertySet(request.value)),
              cleanup: None,
              graph_cursor: None,
            })
            return None
          }
          _ => ()
        }
      }
      let requested : Result[ExecutorActivationRequestOutcome, Error] = Ok(
        match
          direct_executor_property_setter(request.target, request.property_name) {
          Some((setter, executable)) => {
            let property_scope = begin_cleared_active_callee_realm(
              self.realm_state,
            )
            let call_request = ExecutorCallRequest(
              callee=setter,
              this_value=request.receiver,
              args=[request.value],
              loc=request.loc,
            )
            stack.push(
              self.start_executor_activation(
                executable,
                ExecutorStartPropertySet(call_request, request.value),
                Some(property_scope),
              ),
            )
            ExecutorActivationRequestChild
          }
          None =>
            ExecutorActivationRequestValue(
              self.set_property(
                request.target,
                request.property_name,
                request.value,
                request.loc,
                strict=request.strict,
                receiver=request.receiver,
              ),
            )
        },
      ) catch {
        error => Err(error)
      }
      deliver_executor_activation_request(frame, requested)
      None
    }
    ExecutorActivationPropertyUpdate(request) => {
      let update_frame = ExecutorPropertyUpdateFrame(request)
      stack.push({
        frame: update_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildPropertyUpdate),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationCoercingAddition(request) => {
      let addition_frame = ExecutorCoercingAdditionFrame(request)
      stack.push({
        frame: addition_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildCoercingAddition),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationCoercingRelational(request) => {
      let relational_frame = ExecutorCoercingRelationalFrame(request)
      stack.push({
        frame: relational_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildCoercingRelational),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationCoercingSubtraction(request) => {
      let subtraction_frame = ExecutorCoercingSubtractionFrame(request)
      stack.push({
        frame: subtraction_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildCoercingSubtraction),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationPropertyDelete(request) => {
      let delete_frame = ExecutorPropertyDeleteFrame(request)
      stack.push({
        frame: delete_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildPropertyDelete),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
    ExecutorActivationIterableSpread(request) => {
      let spread_frame = ExecutorIterableSpreadFrame(request)
      stack.push({
        frame: spread_frame as &ExecutorActivationFrame,
        completion: Some(ExecutorChildIterableSpread),
        cleanup: None,
        graph_cursor: None,
      })
      None
    }
  }
}

///|
// Drive one root entry and every exact executor-backed ordinary call or static
// property getter/setter it requests. Root ownership is carried by the entry:
// public top-level frames have none, while admitted ordinary-call roots own
// cleanup.
fn Interpreter::drive_executor_activation_stack(
  self : Interpreter,
  stack : Array[ExecutorActivationStackEntry],
) -> ExecutorActivationStep raise Error {
  try {
    while true {
      guard !stack.is_empty() else {
        return ExecutorActivationNormal(Undefined)
      }
      let index = stack.length() - 1
      let frame = stack[index].frame
      let stepped : Result[ExecutorActivationStep, Error] = Ok(frame.step(self)) catch {
        error => Err(error)
      }
      match stepped {
        Err(error) =>
          self.deliver_executor_activation_error(stack, index, error)
        Ok(step) => {
          let handled : ExecutorActivationStep? = self.handle_executor_activation_step(
            stack, index, step,
          ) catch {
            error => {
              if index < stack.length() {
                self.deliver_executor_activation_error(stack, index, error)
              }
              raise error
            }
          }
          match handled {
            Some(result) => {
              let root = stack.pop().unwrap()
              match root.cleanup {
                Some(cleanup) => self.finish_executor_activation(cleanup, None)
                None => ()
              }
              return result
            }
            None => ()
          }
        }
      }
    }
  } catch {
    error => {
      let mut first_cleanup_error : Error? = None
      while !stack.is_empty() {
        let entry = stack.pop().unwrap()
        match entry.cleanup {
          Some(cleanup) => {
            let cleanup_error : Error? = try {
              self.finish_executor_activation(cleanup, Some(error))
              None
            } catch {
              cleanup_error => Some(cleanup_error)
            }
            match (first_cleanup_error, cleanup_error) {
              (None, Some(cleanup_error)) =>
                first_cleanup_error = Some(cleanup_error)
              _ => ()
            }
          }
          None => ()
        }
      }
      match first_cleanup_error {
        Some(cleanup_error) => raise cleanup_error
        None => raise error
      }
    }
  }
  ExecutorActivationNormal(Undefined)
}

///|
// Drive a top-level executor frame that does not represent an acquired guest
// activation. Managed ordinary-call roots use the owned entry point below.
pub fn Interpreter::run_executor_activation_coordinator(
  self : Interpreter,
  root : &ExecutorActivationFrame,
) -> ExecutorActivationStep raise Error {
  self.drive_executor_activation_stack([
    { frame: root, completion: None, cleanup: None, graph_cursor: None },
  ])
}

///|
// Enter one already-admitted ordinary call as an owned coordinator root. The
// same entry owns depth observation, realm state, the sealed graph cursor, and
// exactly-once cleanup on both normal and abrupt completion.
fn Interpreter::run_admitted_executor_call_root(
  self : Interpreter,
  executable : ExecutorCallableData,
  request : ExecutorCallRequest,
  graph_cursor : TreeExecutorGraphCursor,
) -> ExecutorActivationStep raise Error {
  let root = self.start_executor_activation(
    executable,
    ExecutorStartCall(request),
    None,
    graph_cursor=Some(graph_cursor),
  )
  self.drive_executor_activation_stack([root])
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
) -> Value raise Error {
  match kind {
    OrdinaryExecutorCallable =>
      match step {
        ExecutorActivationContinue => Undefined
        ExecutorActivationNormal(_) => Undefined
        ExecutorActivationReturn(value) => value
        ExecutorActivationCall(_)
        | ExecutorActivationConstruct(_)
        | ExecutorActivationPropertyGet(_)
        | ExecutorActivationPropertySet(_)
        | ExecutorActivationPropertyUpdate(_)
        | ExecutorActivationBindingUpdate(_)
        | ExecutorActivationCoercingAddition(_)
        | ExecutorActivationCoercingRelational(_)
        | ExecutorActivationCoercingSubtraction(_)
        | ExecutorActivationPropertyDelete(_)
        | ExecutorActivationIterableSpread(_)
        | ExecutorActivationCopyDataProperties(_)
        | ExecutorActivationBinding(_) => Undefined
        ExecutorActivationBindingReference(_)
        | ExecutorActivationReference(_) =>
          raise @errors.InternalError(
            message="executor call completed with a binding reference",
          )
      }
    ArrowExecutorCallable =>
      match step {
        ExecutorActivationContinue => Undefined
        ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
          value
        ExecutorActivationCall(_)
        | ExecutorActivationConstruct(_)
        | ExecutorActivationPropertyGet(_)
        | ExecutorActivationPropertySet(_)
        | ExecutorActivationPropertyUpdate(_)
        | ExecutorActivationBindingUpdate(_)
        | ExecutorActivationCoercingAddition(_)
        | ExecutorActivationCoercingRelational(_)
        | ExecutorActivationCoercingSubtraction(_)
        | ExecutorActivationPropertyDelete(_)
        | ExecutorActivationIterableSpread(_)
        | ExecutorActivationCopyDataProperties(_)
        | ExecutorActivationBinding(_) => Undefined
        ExecutorActivationBindingReference(_)
        | ExecutorActivationReference(_) =>
          raise @errors.InternalError(
            message="executor arrow call completed with a binding reference",
          )
      }
  }
}

///|
fn executor_construct_completion(
  step : ExecutorActivationStep,
  instance : Value,
) -> Value raise Error {
  match step {
    ExecutorActivationReturn(value) if is_object_like_for_constructor_return(
        value,
      ) => value
    ExecutorActivationContinue
    | ExecutorActivationNormal(_)
    | ExecutorActivationReturn(_)
    | ExecutorActivationCall(_)
    | ExecutorActivationConstruct(_)
    | ExecutorActivationPropertyGet(_)
    | ExecutorActivationPropertySet(_)
    | ExecutorActivationPropertyUpdate(_)
    | ExecutorActivationBindingUpdate(_)
    | ExecutorActivationCoercingAddition(_)
    | ExecutorActivationCoercingRelational(_)
    | ExecutorActivationCoercingSubtraction(_)
    | ExecutorActivationPropertyDelete(_)
    | ExecutorActivationIterableSpread(_)
    | ExecutorActivationCopyDataProperties(_)
    | ExecutorActivationBinding(_) => instance
    ExecutorActivationBindingReference(_) | ExecutorActivationReference(_) =>
      raise @errors.InternalError(
        message="executor construct completed with a binding reference",
      )
  }
}

///|
fn executor_property_set_completion(
  rhs : Value,
) -> ExecutorActivationCompletion {
  ExecutorActivationCompletionNormal(rhs)
}

///|
fn executor_property_get_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    ExecutorActivationContinue
    | ExecutorActivationCall(_)
    | ExecutorActivationConstruct(_)
    | ExecutorActivationPropertyGet(_)
    | ExecutorActivationPropertySet(_)
    | ExecutorActivationPropertyUpdate(_)
    | ExecutorActivationBindingUpdate(_)
    | ExecutorActivationCoercingAddition(_)
    | ExecutorActivationCoercingRelational(_)
    | ExecutorActivationCoercingSubtraction(_)
    | ExecutorActivationPropertyDelete(_)
    | ExecutorActivationIterableSpread(_)
    | ExecutorActivationCopyDataProperties(_)
    | ExecutorActivationBinding(_)
    | ExecutorActivationBindingReference(_)
    | ExecutorActivationReference(_) =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="property get completed with a pending activation step",
        ),
      )
  }
}

///|
fn executor_property_update_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    ExecutorActivationContinue
    | ExecutorActivationCall(_)
    | ExecutorActivationConstruct(_)
    | ExecutorActivationPropertyGet(_)
    | ExecutorActivationPropertySet(_)
    | ExecutorActivationPropertyUpdate(_)
    | ExecutorActivationBindingUpdate(_)
    | ExecutorActivationCoercingAddition(_)
    | ExecutorActivationCoercingRelational(_)
    | ExecutorActivationCoercingSubtraction(_)
    | ExecutorActivationPropertyDelete(_)
    | ExecutorActivationIterableSpread(_)
    | ExecutorActivationCopyDataProperties(_)
    | ExecutorActivationBinding(_)
    | ExecutorActivationBindingReference(_)
    | ExecutorActivationReference(_) =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="property update completed with a pending activation step",
        ),
      )
  }
}

///|
fn executor_coercing_addition_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    ExecutorActivationContinue
    | ExecutorActivationCall(_)
    | ExecutorActivationConstruct(_)
    | ExecutorActivationPropertyGet(_)
    | ExecutorActivationPropertySet(_)
    | ExecutorActivationPropertyUpdate(_)
    | ExecutorActivationBindingUpdate(_)
    | ExecutorActivationCoercingAddition(_)
    | ExecutorActivationCoercingRelational(_)
    | ExecutorActivationCoercingSubtraction(_)
    | ExecutorActivationPropertyDelete(_)
    | ExecutorActivationIterableSpread(_)
    | ExecutorActivationCopyDataProperties(_)
    | ExecutorActivationBinding(_)
    | ExecutorActivationBindingReference(_)
    | ExecutorActivationReference(_) =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="coercing addition completed with a pending activation step",
        ),
      )
  }
}

///|
fn executor_coercing_relational_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    ExecutorActivationContinue
    | ExecutorActivationCall(_)
    | ExecutorActivationConstruct(_)
    | ExecutorActivationPropertyGet(_)
    | ExecutorActivationPropertySet(_)
    | ExecutorActivationPropertyUpdate(_)
    | ExecutorActivationBindingUpdate(_)
    | ExecutorActivationCoercingAddition(_)
    | ExecutorActivationCoercingRelational(_)
    | ExecutorActivationCoercingSubtraction(_)
    | ExecutorActivationPropertyDelete(_)
    | ExecutorActivationIterableSpread(_)
    | ExecutorActivationCopyDataProperties(_)
    | ExecutorActivationBinding(_)
    | ExecutorActivationBindingReference(_)
    | ExecutorActivationReference(_) =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="coercing relational completed with a pending activation step",
        ),
      )
  }
}

///|
fn executor_coercing_subtraction_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    ExecutorActivationContinue
    | ExecutorActivationCall(_)
    | ExecutorActivationConstruct(_)
    | ExecutorActivationPropertyGet(_)
    | ExecutorActivationPropertySet(_)
    | ExecutorActivationPropertyUpdate(_)
    | ExecutorActivationBindingUpdate(_)
    | ExecutorActivationCoercingAddition(_)
    | ExecutorActivationCoercingRelational(_)
    | ExecutorActivationCoercingSubtraction(_)
    | ExecutorActivationPropertyDelete(_)
    | ExecutorActivationIterableSpread(_)
    | ExecutorActivationCopyDataProperties(_)
    | ExecutorActivationBinding(_)
    | ExecutorActivationBindingReference(_)
    | ExecutorActivationReference(_) =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="coercing subtraction completed with a pending activation step",
        ),
      )
  }
}

///|
fn executor_property_delete_completion(
  step : ExecutorActivationStep,
) -> ExecutorActivationCompletion {
  match step {
    ExecutorActivationNormal(value) | ExecutorActivationReturn(value) =>
      ExecutorActivationCompletionNormal(value)
    ExecutorActivationContinue
    | ExecutorActivationCall(_)
    | ExecutorActivationConstruct(_)
    | ExecutorActivationPropertyGet(_)
    | ExecutorActivationPropertySet(_)
    | ExecutorActivationPropertyUpdate(_)
    | ExecutorActivationBindingUpdate(_)
    | ExecutorActivationCoercingAddition(_)
    | ExecutorActivationCoercingRelational(_)
    | ExecutorActivationCoercingSubtraction(_)
    | ExecutorActivationPropertyDelete(_)
    | ExecutorActivationIterableSpread(_)
    | ExecutorActivationCopyDataProperties(_)
    | ExecutorActivationBinding(_)
    | ExecutorActivationBindingReference(_)
    | ExecutorActivationReference(_) =>
      ExecutorActivationCompletionAbrupt(
        @errors.InternalError(
          message="property delete completed with a pending activation step",
        ),
      )
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
fn make_executor_callable_with_capability(
  function_name : String,
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : &ExecutorCode,
  rest_param : String?,
  constructable : Bool,
  self_name : String?,
  define_arguments_object : Bool,
  kind : ExecutorCallableKind,
  activation_capability_summary : ExecutorActivationCapabilitySummary?,
  source_text : String?,
) -> Value {
  let realm_state = match closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => closure.realm_state
  }
  let executable : ExecutorCallableData = {
    name: function_name,
    params: params.copy(),
    closure,
    strict,
    code,
    rest_param,
    constructable,
    self_name,
    define_arguments_object,
    kind,
    activation_capability_summary,
    source_text,
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
  let function_name = name.unwrap_or("")
  let self_name = if call_self_name { name } else { None }
  make_executor_callable_with_capability(
    function_name,
    params,
    closure,
    strict,
    code as &ExecutorCode,
    rest_param,
    constructable,
    self_name,
    define_arguments_object,
    OrdinaryExecutorCallable,
    None,
    None,
  )
}

///|
/// ExecutorCode providers are trusted to supply code corresponding to
/// `source_body`; runtime admission cannot prove otherwise.
pub fn[T : ExecutorCode] make_classified_executor_function(
  name : String?,
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : T,
  source_body : Array[@ast.Stmt],
  rest_param? : String? = None,
  constructable? : Bool = true,
  call_self_name? : Bool = false,
  define_arguments_object? : Bool = true,
) -> Value {
  let function_name = name.unwrap_or("")
  let self_name = if call_self_name { name } else { None }
  make_executor_callable_with_capability(
    function_name,
    params,
    closure,
    strict,
    code as &ExecutorCode,
    rest_param,
    constructable,
    self_name,
    define_arguments_object,
    OrdinaryExecutorCallable,
    executor_activation_capability_summary(params, source_body),
    None,
  )
}

///|
// Prepared executor providers supply an immutable capability proof. Unlike
// make_classified_executor_function, this boundary never accepts executable
// source AST; compiler-produced bytecode can therefore not regain a source
// traversal during function creation.
pub fn[T : ExecutorCode] make_prepared_executor_function(
  name : String?,
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : T,
  activation_capability_summary : ExecutorActivationCapabilitySummary?,
  source_text? : String? = None,
  rest_param? : String? = None,
  constructable? : Bool = true,
  call_self_name? : Bool = false,
  define_arguments_object? : Bool = true,
) -> Value {
  let function_name = name.unwrap_or("")
  let self_name = if call_self_name { name } else { None }
  make_executor_callable_with_capability(
    function_name,
    params,
    closure,
    strict,
    code as &ExecutorCode,
    rest_param,
    constructable,
    self_name,
    define_arguments_object,
    OrdinaryExecutorCallable,
    activation_capability_summary,
    source_text,
  )
}

///|
pub fn[T : ExecutorCode] make_executor_arrow_function(
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : T,
  rest_param? : String? = None,
) -> Value {
  make_executor_callable_with_capability(
    "",
    params,
    closure,
    strict,
    code as &ExecutorCode,
    rest_param,
    false,
    None,
    false,
    ArrowExecutorCallable,
    None,
    None,
  )
}

///|
/// ExecutorCode providers are trusted to supply code corresponding to
/// `source_body`; runtime admission cannot prove otherwise.
pub fn[T : ExecutorCode] make_classified_executor_arrow_function(
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : T,
  source_body : Array[@ast.Stmt],
  rest_param? : String? = None,
) -> Value {
  make_executor_callable_with_capability(
    "",
    params,
    closure,
    strict,
    code as &ExecutorCode,
    rest_param,
    false,
    None,
    false,
    ArrowExecutorCallable,
    executor_activation_capability_summary(params, source_body),
    None,
  )
}

///|
// Prepared arrow providers carry the immutable capability proof produced
// before execution and never accept executable source AST.
pub fn[T : ExecutorCode] make_prepared_executor_arrow_function(
  params : Array[String],
  closure : Environment,
  strict : Bool,
  code : T,
  activation_capability_summary : ExecutorActivationCapabilitySummary?,
  source_text? : String? = None,
  rest_param? : String? = None,
) -> Value {
  make_executor_callable_with_capability(
    "",
    params,
    closure,
    strict,
    code as &ExecutorCode,
    rest_param,
    false,
    None,
    false,
    ArrowExecutorCallable,
    activation_capability_summary,
    source_text,
  )
}

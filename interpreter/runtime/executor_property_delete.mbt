///|
priv struct ExecutorDeleteDescriptorInfo {
  descriptor : PropDescriptor
  value : Value
}

///|
priv struct ExecutorDeleteGetOwnProxyContext {
  target : Value
  mut trap_missing : Bool
  mut trap_result : Value?
  mut underlying : ExecutorDeleteDescriptorInfo?
  mut target_extensible : Bool?
}

///|
priv enum ExecutorDeleteGetOwnPhase {
  ExecutorDeleteGetOwnNeedCurrent(Value)
  ExecutorDeleteGetOwnAwaitTrapLookup(Value, Value, Value)
  ExecutorDeleteGetOwnHaveTrap(Value, Value, Value, Value)
  ExecutorDeleteGetOwnAwaitTrapCall
  ExecutorDeleteGetOwnHaveTrapResult(Value)
  ExecutorDeleteGetOwnAwaitDescriptor(ExecutorDeleteDescriptorParseOperation)
  ExecutorDeleteGetOwnAwaitTargetExtensible(ExecutorDeleteIsExtensibleOperation)
  ExecutorDeleteGetOwnComplete(ExecutorDeleteDescriptorInfo?)
}

///|
priv struct ExecutorDeleteGetOwnOperation {
  key : Value
  loc : @token.Loc
  contexts : Array[ExecutorDeleteGetOwnProxyContext]
  mut phase : ExecutorDeleteGetOwnPhase
}

///|
fn ExecutorDeleteGetOwnOperation::ExecutorDeleteGetOwnOperation(
  target~ : Value,
  key~ : Value,
  loc~ : @token.Loc,
) -> ExecutorDeleteGetOwnOperation {
  { key, loc, contexts: [], phase: ExecutorDeleteGetOwnNeedCurrent(target) }
}

///|
fn executor_delete_descriptor_info(
  entry : (PropDescriptor, Value)?,
) -> ExecutorDeleteDescriptorInfo? {
  match entry {
    Some((descriptor, value)) => Some({ descriptor, value })
    None => None
  }
}

///|
priv enum ExecutorDeleteHasPropertyPhase {
  ExecutorDeleteHasPropertyNeedCurrent(Value)
  ExecutorDeleteHasPropertyAwaitTrapLookup(Value, Value)
  ExecutorDeleteHasPropertyHaveTrap(Value, Value, Value)
  ExecutorDeleteHasPropertyAwaitTrapCall(Value)
  ExecutorDeleteHasPropertyHaveTrapResult(Value, Bool)
  ExecutorDeleteHasPropertyAwaitTargetDescriptor(
    Value,
    ExecutorDeleteGetOwnOperation
  )
  ExecutorDeleteHasPropertyAwaitTargetExtensible(
    Value,
    ExecutorDeleteIsExtensibleOperation
  )
  ExecutorDeleteHasPropertyComplete
}

///|
priv struct ExecutorDeleteHasPropertyOperation {
  key : Value
  loc : @token.Loc
  mut phase : ExecutorDeleteHasPropertyPhase
}

///|
fn ExecutorDeleteHasPropertyOperation::ExecutorDeleteHasPropertyOperation(
  target~ : Value,
  key~ : Value,
  loc~ : @token.Loc,
) -> ExecutorDeleteHasPropertyOperation {
  { key, loc, phase: ExecutorDeleteHasPropertyNeedCurrent(target) }
}

///|
fn executor_delete_descriptor_prototype(
  value : Value,
  interp : Interpreter,
) -> Value? {
  match value {
    Object(data) => Some(data.prototype)
    Array(data) => Some(get_array_prototype(interp.realm_state, data))
    Map(data) =>
      Some(
        data.prototype.unwrap_or_else(fn() {
          interp.realm_state.get_map_proto()
        }),
      )
    Set(data) =>
      Some(
        data.prototype.unwrap_or_else(fn() {
          interp.realm_state.get_set_proto()
        }),
      )
    Promise(data) =>
      Some(
        data.prototype.unwrap_or_else(fn() {
          interp.realm_state.get_promise_proto()
        }),
      )
    _ => None
  }
}

///|
fn executor_delete_descriptor_has_own_property(
  value : Value,
  key : Value,
) -> Bool raise Error {
  ordinary_get_own_property(value, key) is Some(_)
}

///|
fn ExecutorDeleteHasPropertyOperation::complete_result(
  self : ExecutorDeleteHasPropertyOperation,
  result : Bool,
) -> ExecutorActivationStep {
  self.phase = ExecutorDeleteHasPropertyComplete
  ExecutorActivationNormal(Bool(result))
}

///|
fn ExecutorDeleteHasPropertyOperation::finish_target_extensible(
  self : ExecutorDeleteHasPropertyOperation,
  extensible : Bool,
) -> ExecutorActivationStep raise Error {
  guard extensible else {
    raise @errors.TypeError(
      message="'has' on proxy: trap returned false for a property on a non-extensible proxy target",
    )
  }
  self.complete_result(false)
}

///|
fn ExecutorDeleteHasPropertyOperation::consume_target_descriptor(
  self : ExecutorDeleteHasPropertyOperation,
  target : Value,
  descriptor : ExecutorDeleteDescriptorInfo?,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match descriptor {
    None => self.complete_result(false)
    Some(info) => {
      guard info.descriptor.configurable else {
        raise @errors.TypeError(
          message="'has' on proxy: trap returned false for a non-configurable property on the proxy target",
        )
      }
      let operation = ExecutorDeleteIsExtensibleOperation(target~, loc=self.loc)
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          match value {
            Bool(extensible) => self.finish_target_extensible(extensible)
            _ =>
              raise @errors.InternalError(
                message="descriptor HasProperty extensibility returned a non-boolean",
              )
          }
        step => {
          self.phase = ExecutorDeleteHasPropertyAwaitTargetExtensible(
            target, operation,
          )
          step
        }
      }
    }
  }
}

///|
fn ExecutorDeleteHasPropertyOperation::begin_target_descriptor(
  self : ExecutorDeleteHasPropertyOperation,
  target : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let operation = ExecutorDeleteGetOwnOperation(
    target~,
    key=self.key,
    loc=self.loc,
  )
  match operation.step(interp) {
    ExecutorActivationNormal(_) =>
      self.consume_target_descriptor(target, operation.result(), interp)
    step => {
      self.phase = ExecutorDeleteHasPropertyAwaitTargetDescriptor(
        target, operation,
      )
      step
    }
  }
}

///|
fn ExecutorDeleteHasPropertyOperation::resume_target_descriptor(
  self : ExecutorDeleteHasPropertyOperation,
  target : Value,
  operation : ExecutorDeleteGetOwnOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match operation.phase {
    ExecutorDeleteGetOwnComplete(_) =>
      self.consume_target_descriptor(target, operation.result(), interp)
    _ =>
      match operation.step(interp) {
        ExecutorActivationNormal(_) =>
          self.consume_target_descriptor(target, operation.result(), interp)
        step => {
          self.phase = ExecutorDeleteHasPropertyAwaitTargetDescriptor(
            target, operation,
          )
          step
        }
      }
  }
}

///|
fn ExecutorDeleteHasPropertyOperation::resume_target_extensible(
  self : ExecutorDeleteHasPropertyOperation,
  target : Value,
  operation : ExecutorDeleteIsExtensibleOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match operation.phase {
    ExecutorDeleteIsExtensibleComplete(extensible) =>
      self.finish_target_extensible(extensible)
    _ =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          match value {
            Bool(extensible) => self.finish_target_extensible(extensible)
            _ =>
              raise @errors.InternalError(
                message="descriptor HasProperty extensibility returned a non-boolean",
              )
          }
        step => {
          self.phase = ExecutorDeleteHasPropertyAwaitTargetExtensible(
            target, operation,
          )
          step
        }
      }
  }
}

///|
impl ExecutorActivationFrame for ExecutorDeleteHasPropertyOperation with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorDeleteHasPropertyNeedCurrent(current) =>
      match current {
        Proxy(proxy_data) => {
          let handler = get_proxy_handler(proxy_data)
          let target = get_proxy_target(proxy_data)
          self.phase = ExecutorDeleteHasPropertyAwaitTrapLookup(target, handler)
          executor_activation_managed_property_get(handler, "has", self.loc)
        }
        _ =>
          if executor_delete_descriptor_has_own_property(current, self.key) {
            self.phase = ExecutorDeleteHasPropertyComplete
            ExecutorActivationNormal(Bool(true))
          } else {
            match executor_delete_descriptor_prototype(current, interp) {
              Some(proto) => {
                self.phase = ExecutorDeleteHasPropertyNeedCurrent(proto)
                ExecutorActivationContinue
              }
              None => {
                self.phase = ExecutorDeleteHasPropertyComplete
                ExecutorActivationNormal(Bool(false))
              }
            }
          }
      }
    ExecutorDeleteHasPropertyHaveTrap(target, handler, trap) =>
      match trap {
        Undefined | Null => {
          self.phase = ExecutorDeleteHasPropertyNeedCurrent(target)
          ExecutorActivationContinue
        }
        _ if is_callable(trap) => {
          self.phase = ExecutorDeleteHasPropertyAwaitTrapCall(target)
          ExecutorActivationCall(
            ExecutorCallRequest(
              callee=trap,
              this_value=handler,
              args=[target, self.key],
              loc=self.loc,
            ),
          )
        }
        _ =>
          raise @errors.TypeError(
            message="'has' on proxy: trap is not a function",
          )
      }
    ExecutorDeleteHasPropertyHaveTrapResult(target, result) =>
      if result {
        self.complete_result(true)
      } else {
        self.begin_target_descriptor(target, interp)
      }
    ExecutorDeleteHasPropertyAwaitTrapLookup(_, _)
    | ExecutorDeleteHasPropertyAwaitTrapCall(_) =>
      raise @errors.InternalError(
        message="descriptor HasProperty stepped while awaiting a child completion",
      )
    ExecutorDeleteHasPropertyAwaitTargetDescriptor(target, operation) =>
      self.resume_target_descriptor(target, operation, interp)
    ExecutorDeleteHasPropertyAwaitTargetExtensible(target, operation) =>
      self.resume_target_extensible(target, operation, interp)
    ExecutorDeleteHasPropertyComplete =>
      raise @errors.InternalError(
        message="descriptor HasProperty operation stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorDeleteHasPropertyOperation with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorDeleteHasPropertyAwaitTrapLookup(target, handler) =>
          self.phase = ExecutorDeleteHasPropertyHaveTrap(target, handler, value)
        ExecutorDeleteHasPropertyAwaitTrapCall(target) =>
          self.phase = ExecutorDeleteHasPropertyHaveTrapResult(
            target,
            is_truthy(value),
          )
        ExecutorDeleteHasPropertyAwaitTargetDescriptor(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorDeleteHasPropertyAwaitTargetExtensible(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorDeleteHasPropertyNeedCurrent(_)
        | ExecutorDeleteHasPropertyHaveTrap(_, _, _)
        | ExecutorDeleteHasPropertyHaveTrapResult(_, _)
        | ExecutorDeleteHasPropertyComplete =>
          raise @errors.InternalError(
            message="descriptor HasProperty received an unexpected child completion",
          )
      }
  }
}

///|
extend ExecutorDeleteHasPropertyOperation with ExecutorActivationFrame::{
  step,
  deliver_activation_completion,
}

///|
priv enum ExecutorDeleteDescriptorField {
  ExecutorDeleteDescriptorEnumerable
  ExecutorDeleteDescriptorConfigurable
  ExecutorDeleteDescriptorValue
  ExecutorDeleteDescriptorWritable
  ExecutorDeleteDescriptorGetter
  ExecutorDeleteDescriptorSetter
}

///|
fn executor_delete_descriptor_field_name(
  field : ExecutorDeleteDescriptorField,
) -> String {
  match field {
    ExecutorDeleteDescriptorEnumerable => "enumerable"
    ExecutorDeleteDescriptorConfigurable => "configurable"
    ExecutorDeleteDescriptorValue => "value"
    ExecutorDeleteDescriptorWritable => "writable"
    ExecutorDeleteDescriptorGetter => "get"
    ExecutorDeleteDescriptorSetter => "set"
  }
}

///|
fn executor_delete_descriptor_next_field(
  field : ExecutorDeleteDescriptorField,
) -> ExecutorDeleteDescriptorField? {
  match field {
    ExecutorDeleteDescriptorEnumerable =>
      Some(ExecutorDeleteDescriptorConfigurable)
    ExecutorDeleteDescriptorConfigurable => Some(ExecutorDeleteDescriptorValue)
    ExecutorDeleteDescriptorValue => Some(ExecutorDeleteDescriptorWritable)
    ExecutorDeleteDescriptorWritable => Some(ExecutorDeleteDescriptorGetter)
    ExecutorDeleteDescriptorGetter => Some(ExecutorDeleteDescriptorSetter)
    ExecutorDeleteDescriptorSetter => None
  }
}

///|
priv enum ExecutorDeleteDescriptorParsePhase {
  ExecutorDeleteDescriptorNeedField(ExecutorDeleteDescriptorField)
  ExecutorDeleteDescriptorAwaitHasProperty(
    ExecutorDeleteDescriptorField,
    ExecutorDeleteHasPropertyOperation
  )
  ExecutorDeleteDescriptorAwaitValue(ExecutorDeleteDescriptorField)
  ExecutorDeleteDescriptorComplete(ExecutorDeleteDescriptorInfo)
}

///|
priv struct ExecutorDeleteDescriptorParseOperation {
  attrs : Value
  loc : @token.Loc
  mut enumerable : Bool?
  mut configurable : Bool?
  mut value : Value?
  mut writable : Bool?
  mut getter : Value?
  mut setter : Value?
  mut has_getter : Bool
  mut has_setter : Bool
  mut phase : ExecutorDeleteDescriptorParsePhase
}

///|
fn ExecutorDeleteDescriptorParseOperation::ExecutorDeleteDescriptorParseOperation(
  attrs~ : Value,
  loc~ : @token.Loc,
) -> ExecutorDeleteDescriptorParseOperation {
  {
    attrs,
    loc,
    enumerable: None,
    configurable: None,
    value: None,
    writable: None,
    getter: None,
    setter: None,
    has_getter: false,
    has_setter: false,
    phase: ExecutorDeleteDescriptorNeedField(ExecutorDeleteDescriptorEnumerable),
  }
}

///|
fn ExecutorDeleteDescriptorParseOperation::finish_descriptor(
  self : ExecutorDeleteDescriptorParseOperation,
) -> ExecutorActivationStep raise Error {
  let is_accessor = self.has_getter || self.has_setter
  let is_data = self.value is Some(_) || self.writable is Some(_)
  guard !(is_accessor && is_data) else {
    raise @errors.TypeError(
      message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute",
    )
  }
  let descriptor : PropDescriptor = {
    writable: self.writable.unwrap_or(false),
    enumerable: self.enumerable.unwrap_or(false),
    configurable: self.configurable.unwrap_or(false),
    getter: if self.has_getter {
      self.getter
    } else {
      None
    },
    setter: if self.has_setter {
      self.setter
    } else {
      None
    },
    is_accessor,
  }
  let info = {
    descriptor,
    value: if is_accessor {
      Undefined
    } else {
      self.value.unwrap_or(Undefined)
    },
  }
  self.phase = ExecutorDeleteDescriptorComplete(info)
  ExecutorActivationNormal(Undefined)
}

///|
fn ExecutorDeleteDescriptorParseOperation::advance(
  self : ExecutorDeleteDescriptorParseOperation,
  field : ExecutorDeleteDescriptorField,
) -> ExecutorActivationStep raise Error {
  match executor_delete_descriptor_next_field(field) {
    Some(next) => {
      self.phase = ExecutorDeleteDescriptorNeedField(next)
      ExecutorActivationContinue
    }
    None => self.finish_descriptor()
  }
}

///|
fn ExecutorDeleteDescriptorParseOperation::after_has_property(
  self : ExecutorDeleteDescriptorParseOperation,
  field : ExecutorDeleteDescriptorField,
  present : Bool,
) -> ExecutorActivationStep raise Error {
  if present {
    self.phase = ExecutorDeleteDescriptorAwaitValue(field)
    executor_activation_managed_property_get(
      self.attrs,
      executor_delete_descriptor_field_name(field),
      self.loc,
    )
  } else {
    self.advance(field)
  }
}

///|
fn ExecutorDeleteDescriptorParseOperation::record_value(
  self : ExecutorDeleteDescriptorParseOperation,
  field : ExecutorDeleteDescriptorField,
  value : Value,
) -> ExecutorActivationStep raise Error {
  match field {
    ExecutorDeleteDescriptorEnumerable =>
      self.enumerable = Some(is_truthy(value))
    ExecutorDeleteDescriptorConfigurable =>
      self.configurable = Some(is_truthy(value))
    ExecutorDeleteDescriptorValue => self.value = Some(value)
    ExecutorDeleteDescriptorWritable => self.writable = Some(is_truthy(value))
    ExecutorDeleteDescriptorGetter => {
      self.has_getter = true
      match value {
        Undefined => self.getter = None
        _ => {
          guard is_callable(value) else {
            raise @errors.TypeError(message="Getter must be a function")
          }
          self.getter = Some(value)
        }
      }
    }
    ExecutorDeleteDescriptorSetter => {
      self.has_setter = true
      match value {
        Undefined => self.setter = None
        _ => {
          guard is_callable(value) else {
            raise @errors.TypeError(message="Setter must be a function")
          }
          self.setter = Some(value)
        }
      }
    }
  }
  self.advance(field)
}

///|
impl ExecutorActivationFrame for ExecutorDeleteDescriptorParseOperation with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorDeleteDescriptorNeedField(field) => {
      let operation = ExecutorDeleteHasPropertyOperation(
        target=self.attrs,
        key=String_(executor_delete_descriptor_field_name(field)),
        loc=self.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          match value {
            Bool(present) => self.after_has_property(field, present)
            _ =>
              raise @errors.InternalError(
                message="descriptor HasProperty returned a non-boolean",
              )
          }
        step => {
          self.phase = ExecutorDeleteDescriptorAwaitHasProperty(
            field, operation,
          )
          step
        }
      }
    }
    ExecutorDeleteDescriptorAwaitHasProperty(field, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          match value {
            Bool(present) => self.after_has_property(field, present)
            _ =>
              raise @errors.InternalError(
                message="descriptor HasProperty returned a non-boolean",
              )
          }
        step => {
          self.phase = ExecutorDeleteDescriptorAwaitHasProperty(
            field, operation,
          )
          step
        }
      }
    ExecutorDeleteDescriptorAwaitValue(_) =>
      raise @errors.InternalError(
        message="descriptor parser stepped while awaiting a child completion",
      )
    ExecutorDeleteDescriptorComplete(_) =>
      raise @errors.InternalError(
        message="descriptor parser stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorDeleteDescriptorParseOperation with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorDeleteDescriptorAwaitHasProperty(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorDeleteDescriptorAwaitValue(field) =>
          ignore(self.record_value(field, value))
        ExecutorDeleteDescriptorNeedField(_)
        | ExecutorDeleteDescriptorComplete(_) =>
          raise @errors.InternalError(
            message="descriptor parser received an unexpected child completion",
          )
      }
  }
}

///|
extend ExecutorDeleteDescriptorParseOperation with ExecutorActivationFrame::{
  step,
  deliver_activation_completion,
}

///|
fn ExecutorDeleteDescriptorParseOperation::result(
  self : ExecutorDeleteDescriptorParseOperation,
) -> ExecutorDeleteDescriptorInfo raise Error {
  match self.phase {
    ExecutorDeleteDescriptorComplete(info) => info
    _ =>
      raise @errors.InternalError(
        message="descriptor parser result requested before completion",
      )
  }
}

///|
fn executor_delete_validate_descriptor(
  existing : ExecutorDeleteDescriptorInfo,
  reported : ExecutorDeleteDescriptorInfo,
) -> Unit raise Error {
  let existing_desc = existing.descriptor
  let reported_desc = reported.descriptor
  guard existing_desc.configurable == reported_desc.configurable else {
    raise @errors.TypeError(
      message="'getOwnPropertyDescriptor' on proxy: trap reported a different configurable value for a property on the proxy target",
    )
  }
  guard existing_desc.configurable ||
    existing_desc.enumerable == reported_desc.enumerable else {
    raise @errors.TypeError(
      message="'getOwnPropertyDescriptor' on proxy: trap reported different enumerable for non-configurable property on proxy target",
    )
  }
  let existing_is_data = !existing_desc.is_accessor
  let reported_is_data = !reported_desc.is_accessor
  if !existing_desc.configurable && existing_is_data != reported_is_data {
    raise @errors.TypeError(
      message="'getOwnPropertyDescriptor' on proxy: trap reported descriptor kind (data/accessor) mismatch for non-configurable property on proxy target",
    )
  }
  if !existing_desc.configurable && existing_is_data && reported_is_data {
    if reported_desc.writable == false && existing_desc.writable {
      raise @errors.TypeError(
        message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and non-writable for property which is writable on the proxy target",
      )
    }
    if !existing_desc.writable && !same_value(reported.value, existing.value) {
      raise @errors.TypeError(
        message="'getOwnPropertyDescriptor' on proxy: trap reported different value for non-configurable non-writable data property on proxy target",
      )
    }
  }
  if !existing_desc.configurable && !existing_is_data && !reported_is_data {
    let getter_ok = match (existing_desc.getter, reported_desc.getter) {
      (None, None) => true
      (Some(a), Some(b)) => strict_equal(a, b)
      _ => false
    }
    guard getter_ok else {
      raise @errors.TypeError(
        message="'getOwnPropertyDescriptor' on proxy: trap reported mismatched getter for non-configurable accessor on proxy target",
      )
    }
    let setter_ok = match (existing_desc.setter, reported_desc.setter) {
      (None, None) => true
      (Some(a), Some(b)) => strict_equal(a, b)
      _ => false
    }
    guard setter_ok else {
      raise @errors.TypeError(
        message="'getOwnPropertyDescriptor' on proxy: trap reported mismatched setter for non-configurable accessor on proxy target",
      )
    }
  }
}

///|
fn ExecutorDeleteGetOwnOperation::begin_target_extensible(
  self : ExecutorDeleteGetOwnOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let target = self.contexts[self.contexts.length() - 1].target
  let operation = ExecutorDeleteIsExtensibleOperation(target~, loc=self.loc)
  match operation.step(interp) {
    ExecutorActivationNormal(value) =>
      match value {
        Bool(extensible) => self.consume_target_extensible(extensible, interp)
        _ =>
          raise @errors.InternalError(
            message="delete invariant extensibility returned a non-boolean",
          )
      }
    step => {
      self.phase = ExecutorDeleteGetOwnAwaitTargetExtensible(operation)
      step
    }
  }
}

///|
fn ExecutorDeleteGetOwnOperation::consume_target_extensible(
  self : ExecutorDeleteGetOwnOperation,
  extensible : Bool,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let index = self.contexts.length() - 1
  let context = self.contexts[index]
  guard !context.trap_missing else {
    raise @errors.InternalError(
      message="delete invariant extensibility was requested for a forwarding getOwn trap",
    )
  }
  let trap_result = match context.trap_result {
    Some(result) => result
    None =>
      raise @errors.InternalError(
        message="delete invariant extensibility lost its trap result",
      )
  }
  context.target_extensible = Some(extensible)
  match trap_result {
    Undefined =>
      match context.underlying {
        Some(_) => {
          guard extensible else {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap returned an undefined descriptor for a property on a non-extensible proxy target",
            )
          }
          ignore(self.contexts.pop())
          self.consume_descriptor(None, interp)
        }
        None =>
          raise @errors.InternalError(
            message="delete invariant extensibility was requested for an absent undefined descriptor",
          )
      }
    _ if is_js_object(trap_result) =>
      self.begin_descriptor_parse(trap_result, interp)
    _ =>
      raise @errors.InternalError(
        message="delete invariant extensibility had an invalid trap result",
      )
  }
}

///|
fn ExecutorDeleteGetOwnOperation::consume_descriptor(
  self : ExecutorDeleteGetOwnOperation,
  descriptor : ExecutorDeleteDescriptorInfo?,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let current = descriptor
  while true {
    guard !self.contexts.is_empty() else {
      self.phase = ExecutorDeleteGetOwnComplete(current)
      return ExecutorActivationNormal(Undefined)
    }
    let index = self.contexts.length() - 1
    let context = self.contexts[index]
    if context.trap_missing {
      ignore(self.contexts.pop())
      continue
    }
    self.contexts[index].underlying = current
    let trap_result = match context.trap_result {
      Some(result) => result
      None =>
        raise @errors.InternalError(
          message="delete [[GetOwnProperty]] lost its trap result",
        )
    }
    match trap_result {
      Undefined =>
        match current {
          None =>
            // An absent undefined trap result for an absent target property
            // is valid forwarding. No extensibility check is required here.
            ignore(self.contexts.pop())
          Some(existing) => {
            guard existing.descriptor.configurable else {
              raise @errors.TypeError(
                message="'getOwnPropertyDescriptor' on proxy: trap returned an undefined descriptor for a non-configurable property on the proxy target",
              )
            }
            return self.begin_target_extensible(interp)
          }
        }
      _ if is_js_object(trap_result) =>
        return self.begin_target_extensible(interp)
      _ =>
        raise @errors.InternalError(
          message="delete [[GetOwnProperty]] had an invalid trap result",
        )
    }
  } nobreak {
    raise @errors.InternalError(
      message="delete [[GetOwnProperty]] descriptor unwind did not converge",
    )
  }
}

///|
fn ExecutorDeleteGetOwnOperation::finish_reported_descriptor(
  self : ExecutorDeleteGetOwnOperation,
  reported : ExecutorDeleteDescriptorInfo,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let index = self.contexts.length() - 1
  let context = self.contexts[index]
  match context.trap_result {
    Some(result) if is_js_object(result) => ()
    _ =>
      raise @errors.InternalError(
        message="descriptor parser completed without an object trap result",
      )
  }
  match context.underlying {
    None => {
      guard context.target_extensible is Some(true) else {
        raise @errors.TypeError(
          message="'getOwnPropertyDescriptor' on proxy: trap reported a property on a non-extensible target",
        )
      }
      guard reported.descriptor.configurable else {
        raise @errors.TypeError(
          message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable for a key that does not exist on the proxy target",
        )
      }
    }
    Some(existing) => executor_delete_validate_descriptor(existing, reported)
  }
  ignore(self.contexts.pop())
  self.consume_descriptor(Some(reported), interp)
}

///|
fn ExecutorDeleteGetOwnOperation::begin_descriptor_parse(
  self : ExecutorDeleteGetOwnOperation,
  result : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let operation = ExecutorDeleteDescriptorParseOperation(
    attrs=result,
    loc=self.loc,
  )
  match operation.step(interp) {
    ExecutorActivationNormal(_) =>
      self.finish_reported_descriptor(operation.result(), interp)
    step => {
      self.phase = ExecutorDeleteGetOwnAwaitDescriptor(operation)
      step
    }
  }
}

///|
fn ExecutorDeleteGetOwnOperation::resume_descriptor_parse(
  self : ExecutorDeleteGetOwnOperation,
  operation : ExecutorDeleteDescriptorParseOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match operation.phase {
    ExecutorDeleteDescriptorComplete(_) =>
      self.finish_reported_descriptor(operation.result(), interp)
    _ =>
      match operation.step(interp) {
        ExecutorActivationNormal(_) =>
          self.finish_reported_descriptor(operation.result(), interp)
        step => {
          self.phase = ExecutorDeleteGetOwnAwaitDescriptor(operation)
          step
        }
      }
  }
}

///|
fn ExecutorDeleteGetOwnOperation::resume_target_extensible(
  self : ExecutorDeleteGetOwnOperation,
  operation : ExecutorDeleteIsExtensibleOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match operation.step(interp) {
    ExecutorActivationNormal(value) =>
      match value {
        Bool(extensible) => self.consume_target_extensible(extensible, interp)
        _ =>
          raise @errors.InternalError(
            message="delete invariant extensibility returned a non-boolean",
          )
      }
    step => {
      self.phase = ExecutorDeleteGetOwnAwaitTargetExtensible(operation)
      step
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorDeleteGetOwnOperation with fn step(
  self,
  interp,
) {
  match self.phase {
    ExecutorDeleteGetOwnNeedCurrent(current) =>
      match current {
        Proxy(proxy_data) => {
          let handler = get_proxy_handler(proxy_data)
          let target = get_proxy_target(proxy_data)
          self.contexts.push({
            target,
            trap_missing: false,
            trap_result: None,
            underlying: None,
            target_extensible: None,
          })
          self.phase = ExecutorDeleteGetOwnAwaitTrapLookup(
            target,
            handler,
            self.key,
          )
          executor_activation_managed_property_get(
            handler,
            "getOwnPropertyDescriptor",
            self.loc,
          )
        }
        _ => {
          let entry = interp.get_own_property(current, self.key)
          self.consume_descriptor(
            executor_delete_descriptor_info(entry),
            interp,
          )
        }
      }
    ExecutorDeleteGetOwnHaveTrap(target, handler, key, trap) =>
      match trap {
        Undefined | Null => {
          let index = self.contexts.length() - 1
          self.contexts[index].trap_missing = true
          self.phase = ExecutorDeleteGetOwnNeedCurrent(target)
          ExecutorActivationContinue
        }
        _ if is_callable(trap) => {
          self.phase = ExecutorDeleteGetOwnAwaitTrapCall
          ExecutorActivationCall(
            ExecutorCallRequest(
              callee=trap,
              this_value=handler,
              args=[target, key],
              loc=self.loc,
            ),
          )
        }
        _ =>
          raise @errors.TypeError(
            message="'getOwnPropertyDescriptor' on proxy: trap is not a function",
          )
      }
    ExecutorDeleteGetOwnHaveTrapResult(result) =>
      if result is Undefined {
        let index = self.contexts.length() - 1
        self.contexts[index].trap_result = Some(result)
        self.phase = ExecutorDeleteGetOwnNeedCurrent(
          self.contexts[self.contexts.length() - 1].target,
        )
        ExecutorActivationContinue
      } else if is_js_object(result) {
        let index = self.contexts.length() - 1
        self.contexts[index].trap_result = Some(result)
        self.phase = ExecutorDeleteGetOwnNeedCurrent(
          self.contexts[self.contexts.length() - 1].target,
        )
        ExecutorActivationContinue
      } else {
        raise @errors.TypeError(
          message="'getOwnPropertyDescriptor' on proxy: trap returned neither object nor undefined",
        )
      }
    ExecutorDeleteGetOwnAwaitDescriptor(operation) =>
      self.resume_descriptor_parse(operation, interp)
    ExecutorDeleteGetOwnAwaitTargetExtensible(operation) =>
      self.resume_target_extensible(operation, interp)
    ExecutorDeleteGetOwnAwaitTrapLookup(_, _, _)
    | ExecutorDeleteGetOwnAwaitTrapCall =>
      raise @errors.InternalError(
        message="delete [[GetOwnProperty]] stepped while awaiting a child completion",
      )
    ExecutorDeleteGetOwnComplete(_) =>
      raise @errors.InternalError(
        message="delete [[GetOwnProperty]] operation stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorDeleteGetOwnOperation with fn deliver_activation_completion(
  self : ExecutorDeleteGetOwnOperation,
  completion : ExecutorActivationCompletion,
) -> Unit raise Error {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorDeleteGetOwnAwaitTrapLookup(target, handler, key) =>
          self.phase = ExecutorDeleteGetOwnHaveTrap(target, handler, key, value)
        ExecutorDeleteGetOwnAwaitTrapCall =>
          self.phase = ExecutorDeleteGetOwnHaveTrapResult(value)
        ExecutorDeleteGetOwnAwaitDescriptor(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorDeleteGetOwnAwaitTargetExtensible(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorDeleteGetOwnNeedCurrent(_)
        | ExecutorDeleteGetOwnHaveTrap(_, _, _, _)
        | ExecutorDeleteGetOwnHaveTrapResult(_)
        | ExecutorDeleteGetOwnComplete(_) =>
          raise @errors.InternalError(
            message="delete [[GetOwnProperty]] received an unexpected child completion",
          )
      }
  }
}

///|
extend ExecutorDeleteGetOwnOperation with ExecutorActivationFrame::{
  step,
  deliver_activation_completion,
}

///|
fn ExecutorDeleteGetOwnOperation::result(
  self : ExecutorDeleteGetOwnOperation,
) -> ExecutorDeleteDescriptorInfo? raise Error {
  match self.phase {
    ExecutorDeleteGetOwnComplete(value) => value
    _ =>
      raise @errors.InternalError(
        message="delete [[GetOwnProperty]] result requested before completion",
      )
  }
}

///|
priv struct ExecutorDeleteIsExtensibleProxyContext {
  target : Value
  mut trap_result : Bool?
}

///|
priv enum ExecutorDeleteIsExtensiblePhase {
  ExecutorDeleteIsExtensibleNeedCurrent(Value)
  ExecutorDeleteIsExtensibleAwaitTrapLookup(Value, Value)
  ExecutorDeleteIsExtensibleHaveTrap(Value, Value, Value)
  ExecutorDeleteIsExtensibleAwaitTrapCall
  ExecutorDeleteIsExtensibleHaveTrapResult(Bool)
  ExecutorDeleteIsExtensibleComplete(Bool)
}

///|
priv struct ExecutorDeleteIsExtensibleOperation {
  loc : @token.Loc
  contexts : Array[ExecutorDeleteIsExtensibleProxyContext]
  mut phase : ExecutorDeleteIsExtensiblePhase
}

///|
fn ExecutorDeleteIsExtensibleOperation::ExecutorDeleteIsExtensibleOperation(
  target~ : Value,
  loc~ : @token.Loc,
) -> ExecutorDeleteIsExtensibleOperation {
  { loc, contexts: [], phase: ExecutorDeleteIsExtensibleNeedCurrent(target) }
}

///|
fn ExecutorDeleteIsExtensibleOperation::consume_result(
  self : ExecutorDeleteIsExtensibleOperation,
  result : Bool,
) -> ExecutorActivationStep raise Error {
  let mut current = result
  while true {
    guard !self.contexts.is_empty() else {
      self.phase = ExecutorDeleteIsExtensibleComplete(current)
      return ExecutorActivationNormal(Bool(current))
    }
    let index = self.contexts.length() - 1
    let context = self.contexts[index]
    let trap_result = match context.trap_result {
      Some(value) => value
      None =>
        raise @errors.InternalError(
          message="delete [[IsExtensible]] lost its trap result",
        )
    }
    if trap_result != current {
      raise @errors.TypeError(
        message="'isExtensible' on proxy: trap result does not reflect extensibility of proxy target (which is '{current}')",
      )
    }
    ignore(self.contexts.pop())
    current = trap_result
  } nobreak {
    raise @errors.InternalError(
      message="delete [[IsExtensible]] invariant unwind did not converge",
    )
  }
}

///|
fn ExecutorDeleteIsExtensibleOperation::step(
  self : ExecutorDeleteIsExtensibleOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorDeleteIsExtensibleNeedCurrent(current) =>
      match current {
        Proxy(proxy_data) => {
          let handler = get_proxy_handler(proxy_data)
          let target = get_proxy_target(proxy_data)
          self.contexts.push({ target, trap_result: None })
          self.phase = ExecutorDeleteIsExtensibleAwaitTrapLookup(
            target, handler,
          )
          executor_activation_managed_property_get(
            handler,
            "isExtensible",
            self.loc,
          )
        }
        _ => self.consume_result(interp.is_extensible_internal(current))
      }
    ExecutorDeleteIsExtensibleHaveTrap(target, handler, trap) =>
      match trap {
        Undefined | Null => {
          ignore(self.contexts.pop())
          self.phase = ExecutorDeleteIsExtensibleNeedCurrent(target)
          ExecutorActivationContinue
        }
        _ if is_callable(trap) => {
          self.phase = ExecutorDeleteIsExtensibleAwaitTrapCall
          ExecutorActivationCall(
            ExecutorCallRequest(
              callee=trap,
              this_value=handler,
              args=[target],
              loc=self.loc,
            ),
          )
        }
        _ =>
          raise @errors.TypeError(
            message="'isExtensible' on proxy: trap is not a function",
          )
      }
    ExecutorDeleteIsExtensibleHaveTrapResult(result) => {
      self.contexts[self.contexts.length() - 1].trap_result = Some(result)
      self.phase = ExecutorDeleteIsExtensibleNeedCurrent(
        self.contexts[self.contexts.length() - 1].target,
      )
      ExecutorActivationContinue
    }
    ExecutorDeleteIsExtensibleAwaitTrapLookup(_, _)
    | ExecutorDeleteIsExtensibleAwaitTrapCall =>
      raise @errors.InternalError(
        message="delete [[IsExtensible]] stepped while awaiting a child completion",
      )
    ExecutorDeleteIsExtensibleComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="delete [[IsExtensible]] operation stepped after completion",
      )
    }
  }
}

///|
fn ExecutorDeleteIsExtensibleOperation::deliver_activation_completion(
  self : ExecutorDeleteIsExtensibleOperation,
  completion : ExecutorActivationCompletion,
) -> Unit raise Error {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorDeleteIsExtensibleAwaitTrapLookup(target, handler) =>
          self.phase = ExecutorDeleteIsExtensibleHaveTrap(
            target, handler, value,
          )
        ExecutorDeleteIsExtensibleAwaitTrapCall =>
          self.phase = ExecutorDeleteIsExtensibleHaveTrapResult(
            is_truthy(value),
          )
        ExecutorDeleteIsExtensibleNeedCurrent(_)
        | ExecutorDeleteIsExtensibleHaveTrap(_, _, _)
        | ExecutorDeleteIsExtensibleHaveTrapResult(_)
        | ExecutorDeleteIsExtensibleComplete(_) =>
          raise @errors.InternalError(
            message="delete [[IsExtensible]] received an unexpected child completion",
          )
      }
  }
}

///|
fn ExecutorDeleteIsExtensibleOperation::result(
  self : ExecutorDeleteIsExtensibleOperation,
) -> Bool raise Error {
  match self.phase {
    ExecutorDeleteIsExtensibleComplete(value) => value
    _ =>
      raise @errors.InternalError(
        message="delete [[IsExtensible]] result requested before completion",
      )
  }
}

///|
priv enum ExecutorPropertyDeletePhase {
  ExecutorPropertyDeleteNeedKey
  ExecutorPropertyDeleteAwaitKey(ExecutorToPropertyKeyOperation)
  ExecutorPropertyDeleteNeedTarget(Value, Value)
  ExecutorPropertyDeleteAwaitTrapLookup(Value, Value, Value)
  ExecutorPropertyDeleteHaveTrap(Value, Value, Value, Value)
  ExecutorPropertyDeleteAwaitTrapCall(Value, Value)
  ExecutorPropertyDeleteHaveTrapResult(Value, Value, Value)
  ExecutorPropertyDeleteAwaitTargetDescriptor(
    Value,
    ExecutorDeleteGetOwnOperation
  )
  ExecutorPropertyDeleteAwaitTargetExtensible(
    ExecutorDeleteIsExtensibleOperation
  )
  ExecutorPropertyDeleteComplete(Value)
}

///|
priv struct ExecutorPropertyDeleteFrame {
  request : ExecutorPropertyDeleteRequest
  mut phase : ExecutorPropertyDeletePhase
}

///|
fn ExecutorPropertyDeleteFrame::ExecutorPropertyDeleteFrame(
  request : ExecutorPropertyDeleteRequest,
) -> ExecutorPropertyDeleteFrame {
  { request, phase: ExecutorPropertyDeleteNeedKey }
}

///|
fn ExecutorPropertyDeleteFrame::complete_result(
  self : ExecutorPropertyDeleteFrame,
  result : Bool,
) -> ExecutorActivationStep raise Error {
  if !result && self.request.strict {
    raise @errors.TypeError(message="Cannot delete property")
  }
  let value = Bool(result)
  self.phase = ExecutorPropertyDeleteComplete(value)
  ExecutorActivationNormal(value)
}

///|
fn ExecutorPropertyDeleteFrame::finish_target_descriptor(
  self : ExecutorPropertyDeleteFrame,
  target : Value,
  descriptor : ExecutorDeleteDescriptorInfo?,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match descriptor {
    None => self.complete_result(true)
    Some(info) => {
      guard info.descriptor.configurable else {
        raise @errors.TypeError(
          message="'deleteProperty' on proxy: trap returned true for a non-configurable property on the proxy target",
        )
      }
      let operation = ExecutorDeleteIsExtensibleOperation(
        target~,
        loc=self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          match value {
            Bool(extensible) => self.finish_target_extensible(extensible)
            _ =>
              raise @errors.InternalError(
                message="delete invariant extensibility returned a non-boolean",
              )
          }
        step => {
          self.phase = ExecutorPropertyDeleteAwaitTargetExtensible(operation)
          step
        }
      }
    }
  }
}

///|
fn ExecutorPropertyDeleteFrame::finish_target_extensible(
  self : ExecutorPropertyDeleteFrame,
  extensible : Bool,
) -> ExecutorActivationStep raise Error {
  guard extensible else {
    raise @errors.TypeError(
      message="'deleteProperty' on proxy: trap returned true for a configurable property on a non-extensible proxy target",
    )
  }
  self.complete_result(true)
}

///|
fn ExecutorPropertyDeleteFrame::step_frame(
  self : ExecutorPropertyDeleteFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorPropertyDeleteNeedKey =>
      match self.request.key {
        ExecutorStaticPropertyDeleteKey(property_name) => {
          self.phase = ExecutorPropertyDeleteNeedTarget(
            self.request.target,
            String_(property_name),
          )
          ExecutorActivationContinue
        }
        ExecutorComputedPropertyDeleteKey(raw_key) => {
          let operation = ExecutorToPropertyKeyOperation(
            raw_key,
            self.request.loc,
          )
          match operation.step(interp) {
            ExecutorActivationNormal(key) => {
              self.phase = ExecutorPropertyDeleteNeedTarget(
                self.request.target,
                key,
              )
              ExecutorActivationContinue
            }
            step => {
              self.phase = ExecutorPropertyDeleteAwaitKey(operation)
              step
            }
          }
        }
      }
    ExecutorPropertyDeleteAwaitKey(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(key) => {
          self.phase = ExecutorPropertyDeleteNeedTarget(
            self.request.target,
            key,
          )
          ExecutorActivationContinue
        }
        step => {
          self.phase = ExecutorPropertyDeleteAwaitKey(operation)
          step
        }
      }
    ExecutorPropertyDeleteNeedTarget(current_target, key) =>
      match current_target {
        Proxy(proxy_data) => {
          let handler = get_proxy_handler(proxy_data)
          let target = get_proxy_target(proxy_data)
          self.phase = ExecutorPropertyDeleteAwaitTrapLookup(
            target, handler, key,
          )
          executor_activation_managed_property_get(
            handler,
            "deleteProperty",
            self.request.loc,
          )
        }
        _ => {
          let result = interp.delete_property_key(
            current_target,
            key,
            strict=self.request.strict,
          )
          self.phase = ExecutorPropertyDeleteComplete(Bool(result))
          ExecutorActivationNormal(Bool(result))
        }
      }
    ExecutorPropertyDeleteHaveTrap(target, handler, key, trap) =>
      match trap {
        Undefined | Null => {
          self.phase = ExecutorPropertyDeleteNeedTarget(target, key)
          ExecutorActivationContinue
        }
        _ if is_callable(trap) => {
          self.phase = ExecutorPropertyDeleteAwaitTrapCall(target, key)
          ExecutorActivationCall(
            ExecutorCallRequest(
              callee=trap,
              this_value=handler,
              args=[target, key],
              loc=self.request.loc,
            ),
          )
        }
        _ =>
          raise @errors.TypeError(
            message="'deleteProperty' on proxy: trap is not a function",
          )
      }
    ExecutorPropertyDeleteHaveTrapResult(target, key, result) => {
      let trap_result = is_truthy(result)
      if !trap_result {
        return self.complete_result(false)
      }
      let operation = ExecutorDeleteGetOwnOperation(
        target~,
        key~,
        loc=self.request.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(_) =>
          self.finish_target_descriptor(target, operation.result(), interp)
        step => {
          self.phase = ExecutorPropertyDeleteAwaitTargetDescriptor(
            target, operation,
          )
          step
        }
      }
    }
    ExecutorPropertyDeleteAwaitTrapLookup(_, _, _)
    | ExecutorPropertyDeleteAwaitTrapCall(_, _) =>
      raise @errors.InternalError(
        message="property delete stepped while awaiting a child completion",
      )
    ExecutorPropertyDeleteAwaitTargetDescriptor(target, operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(_) =>
          self.finish_target_descriptor(target, operation.result(), interp)
        step => {
          self.phase = ExecutorPropertyDeleteAwaitTargetDescriptor(
            target, operation,
          )
          step
        }
      }
    ExecutorPropertyDeleteAwaitTargetExtensible(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(_) =>
          self.finish_target_extensible(operation.result())
        step => {
          self.phase = ExecutorPropertyDeleteAwaitTargetExtensible(operation)
          step
        }
      }
    ExecutorPropertyDeleteComplete(value) => ExecutorActivationNormal(value)
  }
}

///|
impl ExecutorActivationFrame for ExecutorPropertyDeleteFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorPropertyDeleteFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorPropertyDeleteAwaitKey(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorPropertyDeleteAwaitTrapLookup(target, handler, key) =>
          self.phase = ExecutorPropertyDeleteHaveTrap(
            target, handler, key, value,
          )
        ExecutorPropertyDeleteAwaitTrapCall(target, key) =>
          self.phase = ExecutorPropertyDeleteHaveTrapResult(target, key, value)
        ExecutorPropertyDeleteAwaitTargetDescriptor(_, operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorPropertyDeleteAwaitTargetExtensible(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorPropertyDeleteNeedKey
        | ExecutorPropertyDeleteNeedTarget(_, _)
        | ExecutorPropertyDeleteHaveTrap(_, _, _, _)
        | ExecutorPropertyDeleteHaveTrapResult(_, _, _)
        | ExecutorPropertyDeleteComplete(_) =>
          raise @errors.InternalError(
            message="property delete received an unexpected child completion",
          )
      }
  }
}

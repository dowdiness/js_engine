///|
priv struct ExecutorDeleteDescriptorInfo {
  configurable : Bool
}

///|
priv enum ExecutorDeleteGetOwnProxyStage {
  ExecutorDeleteGetOwnAwaitUnderlyingDescriptor
}

///|
priv struct ExecutorDeleteGetOwnProxyContext {
  target : Value
  mut stage : ExecutorDeleteGetOwnProxyStage
  mut trap_undefined : Bool
  mut reported_configurable : Bool?
  mut underlying : ExecutorDeleteDescriptorInfo?
}

///|
priv enum ExecutorDeleteGetOwnPhase {
  ExecutorDeleteGetOwnNeedCurrent(Value)
  ExecutorDeleteGetOwnAwaitTrapLookup(Value, Value, Value)
  ExecutorDeleteGetOwnHaveTrap(Value, Value, Value, Value)
  ExecutorDeleteGetOwnAwaitTrapCall
  ExecutorDeleteGetOwnHaveTrapResult(Value)
  ExecutorDeleteGetOwnAwaitConfigurableLookup
  ExecutorDeleteGetOwnHaveConfigurable(Bool)
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
    Some((desc, _)) => Some({ configurable: desc.configurable })
    None => None
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
  guard !context.trap_undefined else {
    raise @errors.InternalError(
      message="delete invariant extensibility was requested for a forwarding getOwn trap",
    )
  }
  match context.reported_configurable {
    None => {
      guard extensible else {
        raise @errors.TypeError(
          message="'getOwnPropertyDescriptor' on proxy: trap returned an undefined descriptor for a missing property on a non-extensible target",
        )
      }
      ignore(self.contexts.pop())
      self.consume_descriptor(None, interp)
    }
    Some(reported) => {
      guard context.underlying is None else {
        raise @errors.InternalError(
          message="delete invariant descriptor unexpectedly had an underlying property",
        )
      }
      if !extensible || !reported {
        raise @errors.TypeError(
          message="'getOwnPropertyDescriptor' on proxy: trap reported an invalid descriptor for a missing property",
        )
      }
      ignore(self.contexts.pop())
      self.consume_descriptor(Some({ configurable: reported }), interp)
    }
  }
}

///|
fn ExecutorDeleteGetOwnOperation::consume_descriptor(
  self : ExecutorDeleteGetOwnOperation,
  descriptor : ExecutorDeleteDescriptorInfo?,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let mut current = descriptor
  while true {
    guard !self.contexts.is_empty() else {
      self.phase = ExecutorDeleteGetOwnComplete(current)
      return ExecutorActivationNormal(Undefined)
    }
    let index = self.contexts.length() - 1
    let context = self.contexts[index]
    match context.stage {
      ExecutorDeleteGetOwnAwaitUnderlyingDescriptor => {
        self.contexts[index].underlying = current
        if context.trap_undefined {
          ignore(self.contexts.pop())
        } else {
          match current {
            None => return self.begin_target_extensible(interp)
            Some(info) =>
              match context.reported_configurable {
                None => {
                  guard info.configurable else {
                    raise @errors.TypeError(
                      message="'getOwnPropertyDescriptor' on proxy: trap returned undefined for a non-configurable property on the proxy target",
                    )
                  }
                  ignore(self.contexts.pop())
                  current = None
                }
                Some(reported) => {
                  if reported && !info.configurable {
                    raise @errors.TypeError(
                      message="'getOwnPropertyDescriptor' on proxy: trap reported configurable for a non-configurable property on the proxy target",
                    )
                  }
                  if !reported && info.configurable {
                    raise @errors.TypeError(
                      message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable for property which is configurable on the proxy target",
                    )
                  }
                  ignore(self.contexts.pop())
                  current = Some({ configurable: reported })
                }
              }
          }
        }
      }
    }
  } nobreak {
    raise @errors.InternalError(
      message="delete [[GetOwnProperty]] descriptor unwind did not converge",
    )
  }
}

///|
fn ExecutorDeleteGetOwnOperation::step(
  self : ExecutorDeleteGetOwnOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorDeleteGetOwnNeedCurrent(current) =>
      match current {
        Proxy(proxy_data) => {
          let handler = get_proxy_handler(proxy_data)
          let target = get_proxy_target(proxy_data)
          self.contexts.push({
            target,
            stage: ExecutorDeleteGetOwnAwaitUnderlyingDescriptor,
            trap_undefined: false,
            reported_configurable: None,
            underlying: None,
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
          self.contexts[index].trap_undefined = true
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
        self.contexts[index].trap_undefined = false
        self.phase = ExecutorDeleteGetOwnNeedCurrent(
          self.contexts[index].target,
        )
        ExecutorActivationContinue
      } else if is_js_object(result) {
        let index = self.contexts.length() - 1
        self.contexts[index].trap_undefined = false
        self.contexts[index].stage = ExecutorDeleteGetOwnAwaitUnderlyingDescriptor
        self.phase = ExecutorDeleteGetOwnAwaitConfigurableLookup
        executor_activation_managed_property_get(
          result,
          "configurable",
          self.loc,
        )
      } else {
        raise @errors.TypeError(
          message="'getOwnPropertyDescriptor' on proxy: trap returned neither object nor undefined",
        )
      }
    ExecutorDeleteGetOwnHaveConfigurable(configurable) => {
      let index = self.contexts.length() - 1
      self.contexts[index].reported_configurable = Some(configurable)
      self.phase = ExecutorDeleteGetOwnNeedCurrent(self.contexts[index].target)
      ExecutorActivationContinue
    }
    ExecutorDeleteGetOwnAwaitTrapLookup(_, _, _)
    | ExecutorDeleteGetOwnAwaitTrapCall
    | ExecutorDeleteGetOwnAwaitConfigurableLookup =>
      raise @errors.InternalError(
        message="delete [[GetOwnProperty]] stepped while awaiting a child completion",
      )
    ExecutorDeleteGetOwnAwaitTargetExtensible(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) =>
          match value {
            Bool(extensible) =>
              self.consume_target_extensible(extensible, interp)
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
    ExecutorDeleteGetOwnComplete(value) => {
      ignore(value)
      raise @errors.InternalError(
        message="delete [[GetOwnProperty]] operation stepped after completion",
      )
    }
  }
}

///|
fn ExecutorDeleteGetOwnOperation::deliver_activation_completion(
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
        ExecutorDeleteGetOwnAwaitConfigurableLookup =>
          self.phase = ExecutorDeleteGetOwnHaveConfigurable(is_truthy(value))
        ExecutorDeleteGetOwnAwaitTargetExtensible(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorDeleteGetOwnNeedCurrent(_)
        | ExecutorDeleteGetOwnHaveTrap(_, _, _, _)
        | ExecutorDeleteGetOwnHaveTrapResult(_)
        | ExecutorDeleteGetOwnHaveConfigurable(_)
        | ExecutorDeleteGetOwnComplete(_) =>
          raise @errors.InternalError(
            message="delete [[GetOwnProperty]] received an unexpected child completion",
          )
      }
  }
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
    Some(info) => {
      guard info.configurable else {
        raise @errors.TypeError(
          message="'deleteProperty' on proxy: trap returned true for a non-configurable property on the proxy target",
        )
      }
      self.complete_result(true)
    }
    None => {
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
      message="'deleteProperty' on proxy: trap returned true for a missing property on a non-extensible proxy target",
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

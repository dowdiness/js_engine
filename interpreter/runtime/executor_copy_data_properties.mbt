///|
// The managed own-keys operation is the runtime-owned version of
// [[OwnPropertyKeys]]. It deliberately returns its list only to the parent
// CopyDataProperties frame; the VM never receives a property batch.
priv enum ExecutorOwnPropertyKeysPhase {
  ExecutorOwnPropertyKeysNeedCurrent(Value)
  ExecutorOwnPropertyKeysAwaitTrapLookup(Value, Value)
  ExecutorOwnPropertyKeysHaveTrap(Value, Value, Value)
  ExecutorOwnPropertyKeysAwaitTrapCall
  ExecutorOwnPropertyKeysHaveTrapResult(Value)
  ExecutorOwnPropertyKeysAwaitLengthGet
  ExecutorOwnPropertyKeysHaveLengthValue(Value)
  ExecutorOwnPropertyKeysAwaitLengthPrimitive(ExecutorToPrimitiveOperation)
  ExecutorOwnPropertyKeysHaveLength(Int64)
  ExecutorOwnPropertyKeysAwaitIndex
  ExecutorOwnPropertyKeysHaveIndex(Value)
  ExecutorOwnPropertyKeysNeedTargetExtensible
  ExecutorOwnPropertyKeysAwaitTargetExtensible(ExecutorDeleteIsExtensibleOperation)
  ExecutorOwnPropertyKeysNeedTargetKeys
  ExecutorOwnPropertyKeysAwaitTargetKeys(ExecutorOwnPropertyKeysOperation)
  ExecutorOwnPropertyKeysNeedTargetDescriptor
  ExecutorOwnPropertyKeysAwaitTargetDescriptor(ExecutorDeleteGetOwnOperation)
  ExecutorOwnPropertyKeysAwaitForward(ExecutorOwnPropertyKeysOperation)
  ExecutorOwnPropertyKeysComplete(Array[Value])
}

///|
priv struct ExecutorOwnPropertyKeysOperation {
  mut target : Value
  loc : @token.Loc
  mut phase : ExecutorOwnPropertyKeysPhase
  mut trap_keys : Array[Value]
  mut target_keys : Array[Value]
  mut target_nonconfigurable_keys : Array[Value]
  mut target_configurable_keys : Array[Value]
  mut index : Int
  mut target_extensible : Bool
  mut current_key : Value?
  mut trap_result : Value?
  mut trap_length : Int64
}

///|
fn ExecutorOwnPropertyKeysOperation::ExecutorOwnPropertyKeysOperation(
  target~ : Value,
  loc~ : @token.Loc,
) -> ExecutorOwnPropertyKeysOperation {
  {
    target,
    loc,
    phase: ExecutorOwnPropertyKeysNeedCurrent(target),
    trap_keys: [],
    target_keys: [],
    target_nonconfigurable_keys: [],
    target_configurable_keys: [],
    index: 0,
    target_extensible: true,
    current_key: None,
    trap_result: None,
    trap_length: 0L,
  }
}

///|
fn executor_copy_key_get(
  target : Value,
  key : Value,
  loc : @token.Loc,
) -> ExecutorActivationStep {
  let property_key = match key {
    String_(name) => ExecutorStringPropertyGetKey(name)
    Symbol(symbol) => ExecutorSymbolPropertyGetKey(symbol)
    _ => ExecutorStringPropertyGetKey("")
  }
  ExecutorActivationPropertyGet(
    ExecutorPropertyGetRequest(
      target~,
      key=property_key,
      receiver=target,
      loc~,
      manage_proxy=true,
    ),
  )
}

///|
fn executor_own_keys_array(value : Value) -> Array[Value] raise Error {
  match value {
    Array(data) => data.elements.copy()
    _ =>
      raise @errors.InternalError(
        message="managed ownKeys operation did not return an Array",
      )
  }
}

///|
fn executor_own_keys_length(
  value : Value,
  interp : Interpreter,
) -> Int64 raise Error {
  to_length_from_value(Some(value), interp=Some(interp))
}

///|
fn ExecutorOwnPropertyKeysOperation::finish_length_value(
  self : ExecutorOwnPropertyKeysOperation,
  value : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  if is_js_object(value) {
    let operation = ExecutorToPrimitiveOperation(
      value,
      ExecutorToPrimitiveNumber,
      self.loc,
    )
    match operation.step(interp) {
      ExecutorActivationNormal(primitive) => {
        self.phase = ExecutorOwnPropertyKeysHaveLength(
          executor_own_keys_length(primitive, interp),
        )
        self.step_frame(interp)
      }
      step => {
        self.phase = ExecutorOwnPropertyKeysAwaitLengthPrimitive(operation)
        step
      }
    }
  } else {
    self.phase = ExecutorOwnPropertyKeysHaveLength(
      executor_own_keys_length(value, interp),
    )
    self.step_frame(interp)
  }
}

///|
fn ExecutorOwnPropertyKeysOperation::consume_trap_result(
  self : ExecutorOwnPropertyKeysOperation,
  value : Value,
) -> ExecutorActivationStep raise Error {
  guard is_object_type(value) else {
    raise @errors.TypeError(
      message="'ownKeys' on proxy: trap returned non-object",
    )
  }
  self.trap_keys = []
  self.index = 0
  self.trap_result = Some(value)
  self.phase = ExecutorOwnPropertyKeysAwaitLengthGet
  executor_copy_key_get(value, String_("length"), self.loc)
}

///|
fn ExecutorOwnPropertyKeysOperation::start_invariants(
  self : ExecutorOwnPropertyKeysOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  self.index = 0
  self.target_nonconfigurable_keys = []
  self.target_configurable_keys = []
  self.phase = ExecutorOwnPropertyKeysNeedTargetExtensible
  self.step_frame(interp)
}

///|
fn ExecutorOwnPropertyKeysOperation::consume_target_extensible(
  self : ExecutorOwnPropertyKeysOperation,
  extensible : Bool,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  self.target_extensible = extensible
  self.phase = ExecutorOwnPropertyKeysNeedTargetKeys
  self.step_frame(interp)
}

///|
fn ExecutorOwnPropertyKeysOperation::consume_target_keys(
  self : ExecutorOwnPropertyKeysOperation,
  value : Value,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  self.target_keys = executor_own_keys_array(value)
  self.index = 0
  self.phase = ExecutorOwnPropertyKeysNeedTargetDescriptor
  self.step_frame(interp)
}

///|
fn ExecutorOwnPropertyKeysOperation::consume_target_descriptor(
  self : ExecutorOwnPropertyKeysOperation,
  descriptor : ExecutorDeleteDescriptorInfo?,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let key = match self.current_key {
    Some(key) => key
    None =>
      raise @errors.InternalError(
        message="managed ownKeys descriptor had no current key",
      )
  }
  match descriptor {
    Some(info) if !info.descriptor.configurable =>
      self.target_nonconfigurable_keys.push(key)
    _ => self.target_configurable_keys.push(key)
  }
  self.index += 1
  self.phase = ExecutorOwnPropertyKeysNeedTargetDescriptor
  self.step_frame(interp)
}

///|
fn executor_own_keys_decrement_string(
  counts : Map[String, Int],
  key : String,
) -> Unit raise Error {
  match counts.get(key) {
    Some(n) if n > 0 => counts[key] = n - 1
    _ =>
      raise @errors.TypeError(
        message="'ownKeys' on proxy: trap result did not include '\{key}'",
      )
  }
}

///|
fn ExecutorOwnPropertyKeysOperation::validate_trap_keys(
  self : ExecutorOwnPropertyKeysOperation,
) -> Unit raise Error {
  let seen_strings : Map[String, Bool] = Map([])
  let seen_symbols : Map[Int, Bool] = Map([])
  for key in self.trap_keys {
    match key {
      String_(name) => {
        guard !seen_strings.contains(name) else {
          raise @errors.TypeError(
            message="'ownKeys' on proxy: trap returned duplicate key '\{name}'",
          )
        }
        seen_strings[name] = true
      }
      Symbol(symbol) => {
        guard !seen_symbols.contains(symbol.id) else {
          raise @errors.TypeError(
            message="'ownKeys' on proxy: trap returned duplicate Symbol key",
          )
        }
        seen_symbols[symbol.id] = true
      }
      _ =>
        raise @errors.InternalError(
          message="managed ownKeys retained an invalid trap key",
        )
    }
  }
}

///|
fn ExecutorOwnPropertyKeysOperation::finish_invariants(
  self : ExecutorOwnPropertyKeysOperation,
) -> ExecutorActivationStep raise Error {
  let trap_keys = self.trap_keys
  if self.target_extensible && self.target_nonconfigurable_keys.is_empty() {
    self.phase = ExecutorOwnPropertyKeysComplete(trap_keys)
    return ExecutorActivationNormal(make_array(trap_keys.copy()))
  }
  let unchecked : Map[String, Int] = Map([])
  let unchecked_symbols : Map[Int, Int] = Map([])
  for key in trap_keys {
    match key {
      String_(name) =>
        unchecked[name] = unchecked.get(name).unwrap_or(0) + 1
      Symbol(symbol) =>
        unchecked_symbols[symbol.id] = unchecked_symbols.get(symbol.id).unwrap_or(0) + 1
      _ => ()
    }
  }
  for key in self.target_nonconfigurable_keys {
    match key {
      String_(name) => executor_own_keys_decrement_string(unchecked, name)
      Symbol(symbol) =>
        match unchecked_symbols.get(symbol.id) {
          Some(n) if n > 0 => unchecked_symbols[symbol.id] = n - 1
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result did not include a required Symbol key",
            )
        }
      _ => ()
    }
  }
  if self.target_extensible {
    self.phase = ExecutorOwnPropertyKeysComplete(trap_keys)
    return ExecutorActivationNormal(make_array(trap_keys.copy()))
  }
  for key in self.target_configurable_keys {
    match key {
      String_(name) => executor_own_keys_decrement_string(unchecked, name)
      Symbol(symbol) =>
        match unchecked_symbols.get(symbol.id) {
          Some(n) if n > 0 => unchecked_symbols[symbol.id] = n - 1
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result did not include a required Symbol key",
            )
        }
      _ => ()
    }
  }
  let mut remaining = 0
  unchecked.each(fn(_key, count) { remaining += count })
  unchecked_symbols.each(fn(_key, count) { remaining += count })
  guard remaining == 0 else {
    raise @errors.TypeError(
      message="'ownKeys' on proxy: trap returned extra keys for a non-extensible target",
    )
  }
  self.phase = ExecutorOwnPropertyKeysComplete(trap_keys)
  ExecutorActivationNormal(make_array(trap_keys.copy()))
}

///|
fn ExecutorOwnPropertyKeysOperation::step_frame(
  self : ExecutorOwnPropertyKeysOperation,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorOwnPropertyKeysNeedCurrent(current) =>
      match current {
        Proxy(proxy_data) => {
          let handler = get_proxy_handler(proxy_data)
          let target = get_proxy_target(proxy_data)
          self.phase = ExecutorOwnPropertyKeysAwaitTrapLookup(target, handler)
          executor_copy_key_get(handler, String_("ownKeys"), self.loc)
        }
        _ => {
          let keys = interp.own_property_keys(current)
          self.phase = ExecutorOwnPropertyKeysComplete(keys)
          ExecutorActivationNormal(make_array(keys.copy()))
        }
      }
    ExecutorOwnPropertyKeysHaveTrap(target, handler, trap) =>
      match trap {
        Undefined | Null => {
          self.target = target
          let operation = ExecutorOwnPropertyKeysOperation(target~, loc=self.loc)
          match operation.step_frame(interp) {
            ExecutorActivationNormal(value) => {
              self.phase = ExecutorOwnPropertyKeysComplete(
                executor_own_keys_array(value),
              )
              ExecutorActivationNormal(value)
            }
            step => {
              self.phase = ExecutorOwnPropertyKeysAwaitForward(operation)
              step
            }
          }
        }
        _ if is_callable(trap) => {
          self.target = target
          self.phase = ExecutorOwnPropertyKeysAwaitTrapCall
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
            message="'ownKeys' on proxy: trap is not a function",
          )
      }
    ExecutorOwnPropertyKeysHaveTrapResult(value) =>
      self.consume_trap_result(value)
    ExecutorOwnPropertyKeysAwaitLengthGet(_) =>
      raise @errors.InternalError(
        message="managed ownKeys stepped while awaiting length",
      )
    ExecutorOwnPropertyKeysHaveLengthValue(value) =>
      self.finish_length_value(value, interp)
    ExecutorOwnPropertyKeysAwaitLengthPrimitive(operation) =>
      match operation.phase {
        ExecutorToPrimitiveComplete(value) =>
          self.finish_length_value(value, interp)
        _ =>
          match operation.step(interp) {
            ExecutorActivationNormal(value) =>
              self.finish_length_value(value, interp)
            step => {
              self.phase = ExecutorOwnPropertyKeysAwaitLengthPrimitive(operation)
              step
            }
          }
      }
    ExecutorOwnPropertyKeysHaveLength(length) => {
      self.trap_length = length
      if self.index.to_int64() >= length {
        self.validate_trap_keys()
        self.start_invariants(interp)
      } else {
        let trap_result = match self.trap_result {
          Some(value) => value
          None =>
            raise @errors.InternalError(
              message="managed ownKeys lost its trap result",
            )
        }
        self.phase = ExecutorOwnPropertyKeysAwaitIndex
        executor_copy_key_get(
          trap_result,
          String_(self.index.to_string()),
          self.loc,
        )
      }
    }
    ExecutorOwnPropertyKeysHaveIndex(value) => {
      match value {
        String_(_) | Symbol(_) => {
          self.trap_keys.push(value)
          self.index += 1
          self.phase = ExecutorOwnPropertyKeysHaveLength(self.trap_length)
          self.step_frame(interp)
        }
        _ =>
          raise @errors.TypeError(
            message="'ownKeys' on proxy: trap result must contain only Strings and Symbols",
          )
      }
    }
    ExecutorOwnPropertyKeysNeedTargetExtensible => {
      let operation = ExecutorDeleteIsExtensibleOperation(
        target=self.target,
        loc=self.loc,
      )
      match operation.step(interp) {
        ExecutorActivationNormal(Bool(value)) =>
          self.consume_target_extensible(value, interp)
        step => {
          self.phase = ExecutorOwnPropertyKeysAwaitTargetExtensible(operation)
          step
        }
      }
    }
    ExecutorOwnPropertyKeysAwaitTargetExtensible(operation) =>
      match operation.phase {
        ExecutorDeleteIsExtensibleComplete(value) =>
          self.consume_target_extensible(value, interp)
        _ =>
          match operation.step(interp) {
            ExecutorActivationNormal(Bool(value)) =>
              self.consume_target_extensible(value, interp)
            step => {
              self.phase = ExecutorOwnPropertyKeysAwaitTargetExtensible(operation)
              step
            }
          }
      }
    ExecutorOwnPropertyKeysNeedTargetKeys => {
      let operation = ExecutorOwnPropertyKeysOperation(
        target=self.target,
        loc=self.loc,
      )
      match operation.step_frame(interp) {
        ExecutorActivationNormal(value) =>
          self.consume_target_keys(value, interp)
        step => {
          self.phase = ExecutorOwnPropertyKeysAwaitTargetKeys(operation)
          step
        }
      }
    }
    ExecutorOwnPropertyKeysAwaitTargetKeys(operation) =>
      match operation.phase {
        ExecutorOwnPropertyKeysComplete(_) => {
          let value = make_array(operation.result())
          self.consume_target_keys(value, interp)
        }
        _ =>
          match operation.step_frame(interp) {
            ExecutorActivationNormal(value) =>
              self.consume_target_keys(value, interp)
            step => {
              self.phase = ExecutorOwnPropertyKeysAwaitTargetKeys(operation)
              step
            }
          }
      }
    ExecutorOwnPropertyKeysNeedTargetDescriptor =>
      if self.index >= self.target_keys.length() {
        self.finish_invariants()
      } else {
        let key = self.target_keys[self.index]
        self.current_key = Some(key)
        let operation = ExecutorDeleteGetOwnOperation(
          target=self.target,
          key~,
          loc=self.loc,
        )
        match operation.step(interp) {
          ExecutorActivationNormal(_) =>
            self.consume_target_descriptor(operation.result(), interp)
          step => {
            self.phase = ExecutorOwnPropertyKeysAwaitTargetDescriptor(operation)
            step
          }
        }
      }
    ExecutorOwnPropertyKeysAwaitTargetDescriptor(operation) =>
      match operation.phase {
        ExecutorDeleteGetOwnComplete(_) =>
          self.consume_target_descriptor(operation.result(), interp)
        _ =>
          match operation.step(interp) {
            ExecutorActivationNormal(_) =>
              self.consume_target_descriptor(operation.result(), interp)
            step => {
              self.phase = ExecutorOwnPropertyKeysAwaitTargetDescriptor(operation)
              step
            }
          }
      }
    ExecutorOwnPropertyKeysAwaitForward(operation) =>
      match operation.phase {
        ExecutorOwnPropertyKeysComplete(_) => {
          let value = make_array(operation.result())
          self.phase = ExecutorOwnPropertyKeysComplete(
            executor_own_keys_array(value),
          )
          ExecutorActivationNormal(value)
        }
        _ =>
          match operation.step_frame(interp) {
            ExecutorActivationNormal(value) => {
              self.phase = ExecutorOwnPropertyKeysComplete(
                executor_own_keys_array(value),
              )
              ExecutorActivationNormal(value)
            }
            step => {
              self.phase = ExecutorOwnPropertyKeysAwaitForward(operation)
              step
            }
          }
      }
    ExecutorOwnPropertyKeysAwaitTrapLookup(_, _)
    | ExecutorOwnPropertyKeysAwaitTrapCall
    | ExecutorOwnPropertyKeysAwaitIndex
    | ExecutorOwnPropertyKeysComplete(_) =>
      raise @errors.InternalError(
        message="managed ownKeys stepped while awaiting or after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorOwnPropertyKeysOperation with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorOwnPropertyKeysOperation with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorOwnPropertyKeysAwaitTrapLookup(target, handler) =>
          self.phase = ExecutorOwnPropertyKeysHaveTrap(target, handler, value)
        ExecutorOwnPropertyKeysAwaitTrapCall =>
          self.phase = ExecutorOwnPropertyKeysHaveTrapResult(value)
        ExecutorOwnPropertyKeysAwaitLengthGet =>
          self.phase = ExecutorOwnPropertyKeysHaveLengthValue(value)
        ExecutorOwnPropertyKeysAwaitIndex =>
          self.phase = ExecutorOwnPropertyKeysHaveIndex(value)
        ExecutorOwnPropertyKeysAwaitLengthPrimitive(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorOwnPropertyKeysAwaitTargetExtensible(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorOwnPropertyKeysAwaitTargetKeys(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorOwnPropertyKeysAwaitTargetDescriptor(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorOwnPropertyKeysAwaitForward(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorOwnPropertyKeysNeedCurrent(_)
        | ExecutorOwnPropertyKeysHaveTrap(_, _, _)
        | ExecutorOwnPropertyKeysHaveTrapResult(_)
        | ExecutorOwnPropertyKeysHaveLengthValue(_)
        | ExecutorOwnPropertyKeysHaveLength(_)
        | ExecutorOwnPropertyKeysHaveIndex(_)
        | ExecutorOwnPropertyKeysNeedTargetExtensible
        | ExecutorOwnPropertyKeysNeedTargetKeys
        | ExecutorOwnPropertyKeysNeedTargetDescriptor
        | ExecutorOwnPropertyKeysComplete(_) =>
          raise @errors.InternalError(
            message="managed ownKeys received an unexpected child completion",
          )
      }
  }
}

///|
extend ExecutorOwnPropertyKeysOperation with ExecutorActivationFrame::{
  deliver_activation_completion,
}

///|
fn ExecutorOwnPropertyKeysOperation::result(
  self : ExecutorOwnPropertyKeysOperation,
) -> Array[Value] raise Error {
  match self.phase {
    ExecutorOwnPropertyKeysComplete(keys) => keys
    _ =>
      raise @errors.InternalError(
        message="managed ownKeys result requested before completion",
      )
  }
}

///|
priv enum ExecutorCopyDataPropertiesPhase {
  ExecutorCopyDataPropertiesNeedSource
  ExecutorCopyDataPropertiesAwaitOwnKeys(ExecutorOwnPropertyKeysOperation)
  ExecutorCopyDataPropertiesNeedKey
  ExecutorCopyDataPropertiesAwaitGetOwn(ExecutorDeleteGetOwnOperation)
  ExecutorCopyDataPropertiesAwaitGet
  ExecutorCopyDataPropertiesHaveGet(Value)
  ExecutorCopyDataPropertiesComplete
}

///|
priv struct ExecutorCopyDataPropertiesFrame {
  request : ExecutorCopyDataPropertiesRequest
  mut keys : Array[Value]
  mut index : Int
  mut current_key : Value?
  mut phase : ExecutorCopyDataPropertiesPhase
}

///|
fn ExecutorCopyDataPropertiesFrame::ExecutorCopyDataPropertiesFrame(
  request : ExecutorCopyDataPropertiesRequest,
) -> ExecutorCopyDataPropertiesFrame {
  {
    request,
    keys: [],
    index: 0,
    current_key: None,
    phase: ExecutorCopyDataPropertiesNeedSource,
  }
}

///|
fn ExecutorCopyDataPropertiesFrame::consume_own_keys(
  self : ExecutorCopyDataPropertiesFrame,
  value : Value,
) -> Unit raise Error {
  self.keys = executor_own_keys_array(value)
  self.index = 0
  self.phase = ExecutorCopyDataPropertiesNeedKey
}

///|
fn executor_copy_data_properties_is_excluded(
  excluded_keys : Array[Value],
  key : Value,
) -> Bool {
  for excluded in excluded_keys {
    if strict_equal(excluded, key) {
      return true
    }
  }
  false
}

///|
fn ExecutorCopyDataPropertiesFrame::consume_get_own(
  self : ExecutorCopyDataPropertiesFrame,
  descriptor : ExecutorDeleteDescriptorInfo?,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  self.current_key = Some(self.keys[self.index])
  match descriptor {
    Some(info) if info.descriptor.enumerable => {
      self.phase = ExecutorCopyDataPropertiesAwaitGet
      executor_copy_key_get(
        self.request.source,
        self.current_key.unwrap(),
        self.request.loc,
      )
    }
    _ => {
      self.index += 1
      self.current_key = None
      self.phase = ExecutorCopyDataPropertiesNeedKey
      self.step_frame(interp)
    }
  }
}

///|
fn ExecutorCopyDataPropertiesFrame::step_frame(
  self : ExecutorCopyDataPropertiesFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    ExecutorCopyDataPropertiesNeedSource => {
      match self.request.target {
        Object(_) => ()
        _ =>
          raise @errors.InternalError(
            message="object spread target was not an object",
          )
      }
      match self.request.source {
        Null | Undefined => {
          self.phase = ExecutorCopyDataPropertiesComplete
          ExecutorActivationNormal(Undefined)
        }
        source => {
          let operation = ExecutorOwnPropertyKeysOperation(
            target=source,
            loc=self.request.loc,
          )
          match operation.step_frame(interp) {
            ExecutorActivationNormal(value) => {
              self.consume_own_keys(value)
              self.step_frame(interp)
            }
            step => {
              self.phase = ExecutorCopyDataPropertiesAwaitOwnKeys(operation)
              step
            }
          }
        }
      }
    }
    ExecutorCopyDataPropertiesAwaitOwnKeys(operation) =>
      match operation.phase {
        ExecutorOwnPropertyKeysComplete(_) => {
          let value = make_array(operation.result())
          self.consume_own_keys(value)
          self.step_frame(interp)
        }
        _ =>
          match operation.step_frame(interp) {
            ExecutorActivationNormal(value) => {
              self.consume_own_keys(value)
              self.step_frame(interp)
            }
            step => {
              self.phase = ExecutorCopyDataPropertiesAwaitOwnKeys(operation)
              step
            }
          }
      }
    ExecutorCopyDataPropertiesNeedKey =>
      if self.index >= self.keys.length() {
        self.phase = ExecutorCopyDataPropertiesComplete
        ExecutorActivationNormal(Undefined)
      } else {
        let key = self.keys[self.index]
        if executor_copy_data_properties_is_excluded(
          self.request.excluded_keys,
          key,
        ) {
          self.index += 1
          self.current_key = None
          self.step_frame(interp)
        } else {
          self.current_key = Some(key)
          let operation = ExecutorDeleteGetOwnOperation(
            target=self.request.source,
            key~,
            loc=self.request.loc,
          )
          match operation.step(interp) {
            ExecutorActivationNormal(_) =>
              self.consume_get_own(operation.result(), interp)
            step => {
              self.phase = ExecutorCopyDataPropertiesAwaitGetOwn(operation)
              step
            }
          }
        }
      }
    ExecutorCopyDataPropertiesAwaitGetOwn(operation) =>
      match operation.phase {
        ExecutorDeleteGetOwnComplete(_) =>
          self.consume_get_own(operation.result(), interp)
        _ =>
          match operation.step(interp) {
            ExecutorActivationNormal(_) =>
              self.consume_get_own(operation.result(), interp)
            step => {
              self.phase = ExecutorCopyDataPropertiesAwaitGetOwn(operation)
              step
            }
          }
      }
    ExecutorCopyDataPropertiesAwaitGet =>
      raise @errors.InternalError(
        message="CopyDataProperties stepped while awaiting source Get",
      )
    ExecutorCopyDataPropertiesHaveGet(value) => {
      let key = match self.current_key {
        Some(key) => key
        None =>
          raise @errors.InternalError(
            message="CopyDataProperties Get completed without a key",
          )
      }
      let succeeded = interp.define_own_property(
        self.request.target,
        key,
        PartialDescriptor::data_default(value),
        self.request.loc,
      )
      guard succeeded else {
        raise @errors.TypeError(
          message=format_loc_context(
            "Cannot create data property",
            self.request.loc,
          ),
        )
      }
      self.index += 1
      self.current_key = None
      self.phase = ExecutorCopyDataPropertiesNeedKey
      self.step_frame(interp)
    }
    ExecutorCopyDataPropertiesComplete =>
      raise @errors.InternalError(
        message="CopyDataProperties frame stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorCopyDataPropertiesFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorCopyDataPropertiesFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorCopyDataPropertiesAwaitOwnKeys(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorCopyDataPropertiesAwaitGetOwn(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        ExecutorCopyDataPropertiesAwaitGet =>
          self.phase = ExecutorCopyDataPropertiesHaveGet(value)
        ExecutorCopyDataPropertiesNeedSource
        | ExecutorCopyDataPropertiesNeedKey
        | ExecutorCopyDataPropertiesHaveGet(_)
        | ExecutorCopyDataPropertiesComplete =>
          raise @errors.InternalError(
            message="CopyDataProperties received an unexpected child completion",
          )
      }
  }
}

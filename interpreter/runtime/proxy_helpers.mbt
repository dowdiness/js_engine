///|
/// Get a trap function from the proxy handler, or None if the trap is not defined.
/// Throws TypeError if the proxy has been revoked.
/// Uses the engine's ordinary Get path (interp.get_property) so accessor traps
/// and proxy-handler proxies are resolved with full language semantics.
pub fn get_proxy_trap(
  proxy_data : ProxyData,
  trap_name : String,
  interp : Interpreter,
) -> Value? raise Error {
  let handler = match proxy_data.handler {
    Some(h) => h
    None =>
      raise @errors.TypeError(
        message="Cannot perform '\{trap_name}' on a proxy that has been revoked",
      )
  }
  let _ = match proxy_data.target {
    Some(_) => ()
    None =>
      raise @errors.TypeError(
        message="Cannot perform '\{trap_name}' on a proxy that has been revoked",
      )
  }
  // Use engine-level Get (GetMethod semantics per ES §10.5): this traverses
  // the prototype chain, invokes accessor getters, and handles proxy handlers
  // that are themselves proxies.
  let trap = interp.get_property(handler, trap_name, @token.Loc::default())
  match trap {
    Undefined | Null => None
    _ =>
      if is_callable(trap) {
        Some(trap)
      } else {
        raise @errors.TypeError(
          message="'\{trap_name}' on proxy: trap is not a function",
        )
      }
  }
}

///|
/// Get the target of a proxy, throwing TypeError if revoked.
pub fn get_proxy_target(proxy_data : ProxyData) -> Value raise Error {
  match proxy_data.target {
    Some(t) => t
    None =>
      raise @errors.TypeError(
        message="Cannot perform operation on a proxy that has been revoked",
      )
  }
}

///|
/// Get the handler of a proxy, throwing TypeError if revoked.
pub fn get_proxy_handler(proxy_data : ProxyData) -> Value raise Error {
  match proxy_data.handler {
    Some(h) => h
    None =>
      raise @errors.TypeError(
        message="Cannot perform operation on a proxy that has been revoked",
      )
  }
}

///|
/// Collect own property keys from a non-proxy target value as Array[Value].
/// Returns string keys and symbol keys (symbol keys require SymbolState).
pub fn collect_target_own_keys(
  target : Value,
  sym_state : SymbolState
) -> Array[Value] {
  let keys : Array[Value] = []
  match target {
    Object(data) => {
      // Indexed (integer) string keys first, in ascending order
      let sorted = sort_property_keys(data.properties)
      for k in sorted {
        keys.push(Value::String_(k))
      }
      // Also include keys from descriptors not in properties
      data.descriptors.each(fn(k, _v) {
        if !data.properties.contains(k) {
          keys.push(Value::String_(k))
        }
      })
      // Symbol keys
      data.symbol_properties.each(fn(id, _v) {
        match sym_state.get_symbol_by_id(id) {
          Some(sym) => keys.push(Value::Symbol(sym))
          None => ()
        }
      })
    }
    Value::Array(data) => {
      for i = 0; i < data.elements.length(); i = i + 1 {
        keys.push(Value::String_(i.to_string()))
      }
      keys.push(Value::String_("length"))
    }
    _ => ()
  }
  keys
}

///|
/// Check if target object is extensible (handles Object, Array, etc.)
fn target_is_extensible(target : Value) -> Bool {
  match target {
    Object(data) => data.extensible
    _ => true // Arrays, etc. are always extensible in our implementation
  }
}

///|
/// Implement the Proxy [[IsExtensible]] internal method per ES §10.5.3.
pub fn proxy_is_extensible(
  interp : Interpreter,
  proxy_data : ProxyData
) -> Bool raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "isExtensible", interp)
  match trap {
    None =>
      // No trap — delegate to target
      match target {
        Object(data) => data.extensible
        Value::Proxy(inner) => proxy_is_extensible(interp, inner)
        _ => true
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target], loc)
      let trap_result = is_truthy(result)
      let target_extensible = target_is_extensible(target)
      if trap_result != target_extensible {
        raise @errors.TypeError(
          message="'isExtensible' on proxy: trap result does not reflect extensibility of proxy target (which is '\{target_extensible}')",
        )
      }
      trap_result
    }
  }
}

///|
/// Check if target has a non-configurable own property with the given string key.
fn target_has_non_configurable_key(target : Value, key : String) -> Bool {
  match target {
    Object(data) =>
      match data.descriptors.get(key) {
        Some(desc) => !desc.configurable
        None => false
      }
    _ => false
  }
}

///|
/// Implement the Proxy [[OwnPropertyKeys]] internal method per ES §10.5.11.
/// Calls the ownKeys trap, validates the result against the target's invariants,
/// and returns the validated list of keys as an Array value.
pub fn proxy_own_property_keys(
  interp : Interpreter,
  proxy_data : ProxyData
) -> Value raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "ownKeys", interp)
  // Step 6: If trap is undefined, return target.[[OwnPropertyKeys]]()
  match trap {
    None =>
      // If target is itself a Proxy, recursively invoke its [[OwnPropertyKeys]]
      match target {
        Value::Proxy(inner_proxy) =>
          return proxy_own_property_keys(interp, inner_proxy)
        _ =>
          return Value::Array({
            elements: collect_target_own_keys(target, interp.symbols),
          })
      }
    _ => ()
  }
  let trap_fn = trap.unwrap()
  let handler = get_proxy_handler(proxy_data)
  let loc = @token.Loc::default()
  // Step 7: Call trap(handler, target)
  let trap_result = interp.call_value(trap_fn, handler, [target], loc)
  // Step 8: CreateListFromArrayLike(trapResult, « String, Symbol »)
  let trap_keys : Array[Value] = []
  match trap_result {
    Value::Array(arr) =>
      for elem in arr.elements {
        match elem {
          Value::String_(_) | Value::Symbol(_) => trap_keys.push(elem)
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result must contain only Strings and Symbols",
            )
        }
      }
    Object(data) => {
      // Array-like object: read "length" and indexed properties
      let len = match data.properties.get("length") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      for i = 0; i < len; i = i + 1 {
        let elem = match data.properties.get(i.to_string()) {
          Some(v) => v
          None => Undefined
        }
        match elem {
          Value::String_(_) | Value::Symbol(_) => trap_keys.push(elem)
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result must contain only Strings and Symbols",
            )
        }
      }
    }
    _ =>
      raise @errors.TypeError(
        message="'ownKeys' on proxy: trap returned non-object",
      )
  }
  // Step 9: If trapResult contains any duplicate entries, throw TypeError
  let seen_strings : Map[String, Bool] = {}
  let seen_symbols : Map[Int, Bool] = {}
  for key in trap_keys {
    match key {
      Value::String_(s) => {
        if seen_strings.contains(s) {
          raise @errors.TypeError(
            message="'ownKeys' on proxy: trap returned duplicate key '\{s}'",
          )
        }
        seen_strings[s] = true
      }
      Value::Symbol(sym) => {
        if seen_symbols.contains(sym.id) {
          raise @errors.TypeError(
            message="'ownKeys' on proxy: trap returned duplicate Symbol key",
          )
        }
        seen_symbols[sym.id] = true
      }
      _ => ()
    }
  }
  // Step 10: Get extensibleTarget
  let extensible_target = target_is_extensible(target)
  // Step 11-12: Get target keys, split into non-configurable and configurable
  let target_keys = collect_target_own_keys(target, interp.symbols)
  let target_nonconfigurable_keys : Array[Value] = []
  let target_configurable_keys : Array[Value] = []
  for key in target_keys {
    match key {
      Value::String_(s) =>
        if target_has_non_configurable_key(target, s) {
          target_nonconfigurable_keys.push(key)
        } else {
          target_configurable_keys.push(key)
        }
      _ => target_configurable_keys.push(key) // Symbol keys: assume configurable
    }
  }
  // Step 15: If extensibleTarget is true and targetNonconfigurableKeys is empty, return
  if extensible_target && target_nonconfigurable_keys.is_empty() {
    return Value::Array({ elements: trap_keys })
  }
  // Step 16: Let uncheckedResultKeys be a copy of trapResult
  let unchecked : Map[String, Int] = {} // string key -> count
  let unchecked_sym : Map[Int, Int] = {} // symbol id -> count
  for key in trap_keys {
    match key {
      Value::String_(s) =>
        unchecked[s] = match unchecked.get(s) {
          Some(n) => n + 1
          None => 1
        }
      Value::Symbol(sym) =>
        unchecked_sym[sym.id] = match unchecked_sym.get(sym.id) {
          Some(n) => n + 1
          None => 1
        }
      _ => ()
    }
  }
  // Step 17: For each key in targetNonconfigurableKeys, must be in trapResult
  for key in target_nonconfigurable_keys {
    match key {
      Value::String_(s) =>
        match unchecked.get(s) {
          Some(n) if n > 0 => unchecked[s] = n - 1
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result did not include '\{s}'",
            )
        }
      Value::Symbol(sym) =>
        match unchecked_sym.get(sym.id) {
          Some(n) if n > 0 => unchecked_sym[sym.id] = n - 1
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result did not include a required Symbol key",
            )
        }
      _ => ()
    }
  }
  // Step 18: If extensibleTarget is true, return trapResult
  if extensible_target {
    return Value::Array({ elements: trap_keys })
  }
  // Step 19: For each key in targetConfigurableKeys, must be in unchecked
  for key in target_configurable_keys {
    match key {
      Value::String_(s) =>
        match unchecked.get(s) {
          Some(n) if n > 0 => unchecked[s] = n - 1
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result did not include '\{s}'",
            )
        }
      Value::Symbol(sym) =>
        match unchecked_sym.get(sym.id) {
          Some(n) if n > 0 => unchecked_sym[sym.id] = n - 1
          _ =>
            raise @errors.TypeError(
              message="'ownKeys' on proxy: trap result did not include a required Symbol key",
            )
        }
      _ => ()
    }
  }
  // Step 20: If uncheckedResultKeys is not empty, throw TypeError
  let mut remaining = 0
  unchecked.each(fn(_k, v) { remaining = remaining + v })
  unchecked_sym.each(fn(_k, v) { remaining = remaining + v })
  if remaining > 0 {
    raise @errors.TypeError(
      message="'ownKeys' on proxy: trap returned extra keys for a non-extensible target",
    )
  }
  Value::Array({ elements: trap_keys })
}

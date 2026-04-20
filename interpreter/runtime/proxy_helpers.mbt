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
  sym_state : SymbolState,
) -> Array[Value] {
  let keys : Array[Value] = []
  match target {
    Object(data) => {
      // Indexed (integer) string keys first, in ascending order
      let sorted = sort_property_keys(data.bag.properties)
      for k in sorted {
        keys.push(Value::String_(k))
      }
      // Also include keys from descriptors not in properties
      data.bag.descriptors.each(fn(k, _v) {
        if !data.bag.properties.contains(k) {
          keys.push(Value::String_(k))
        }
      })
      // Symbol keys
      data.bag.symbol_properties.each(fn(id, _v) {
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
  proxy_data : ProxyData,
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
      match data.bag.descriptors.get(key) {
        Some(desc) => !desc.configurable
        None => false
      }
    _ => false
  }
}

///|
/// Get the descriptor for a string-keyed property on the target.
fn target_get_own_descriptor(target : Value, key : String) -> PropDescriptor? {
  match target {
    Object(data) => data.bag.descriptors.get(key)
    _ => None
  }
}

///|
/// Check if the target has a specific own string property (in properties or descriptors).
fn target_has_own_property(target : Value, key : String) -> Bool {
  match target {
    Object(data) =>
      data.bag.properties.contains(key) || data.bag.descriptors.contains(key)
    _ => false
  }
}

///|
/// Implement the Proxy [[PreventExtensions]] internal method per ES §10.5.4.
pub fn proxy_prevent_extensions(
  interp : Interpreter,
  proxy_data : ProxyData,
) -> Bool raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "preventExtensions", interp)
  match trap {
    None =>
      match target {
        Object(data) => {
          data.extensible = false
          true
        }
        Value::Proxy(inner) => proxy_prevent_extensions(interp, inner)
        _ => true
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target], loc)
      let trap_result = is_truthy(result)
      // ES §10.5.4 step 8: If trap returns true, target must not be extensible
      if trap_result {
        let target_extensible = target_is_extensible(target)
        if target_extensible {
          raise @errors.TypeError(
            message="'preventExtensions' on proxy: trap returned truish but the proxy target is extensible",
          )
        }
      }
      trap_result
    }
  }
}

///|
/// Implement the Proxy [[GetPrototypeOf]] internal method per ES §10.5.1.
pub fn proxy_get_prototype_of(
  interp : Interpreter,
  proxy_data : ProxyData,
) -> Value raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "getPrototypeOf", interp)
  match trap {
    None =>
      match target {
        Object(data) => data.prototype
        Value::Proxy(inner) => proxy_get_prototype_of(interp, inner)
        _ => Null
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target], loc)
      // Step 7: Result must be Object or Null
      match result {
        Object(_) | Null => ()
        _ =>
          raise @errors.TypeError(
            message="'getPrototypeOf' on proxy: trap returned neither object nor null",
          )
      }
      // Step 9-10: If target is non-extensible, result must match target's prototype
      let extensible = target_is_extensible(target)
      if !extensible {
        let target_proto = match target {
          Object(data) => data.prototype
          _ => Null
        }
        if !strict_equal(result, target_proto) {
          raise @errors.TypeError(
            message="'getPrototypeOf' on proxy: proxy target is non-extensible but the trap did not return its actual prototype",
          )
        }
      }
      result
    }
  }
}

///|
/// Implement the Proxy [[SetPrototypeOf]] internal method per ES §10.5.2.
pub fn proxy_set_prototype_of(
  interp : Interpreter,
  proxy_data : ProxyData,
  proto : Value,
) -> Bool raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "setPrototypeOf", interp)
  match trap {
    None =>
      match target {
        Object(data) => {
          if !data.extensible && !strict_equal(proto, data.prototype) {
            return false
          }
          data.prototype = proto
          true
        }
        Value::Proxy(inner) => proxy_set_prototype_of(interp, inner, proto)
        _ => true
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target, proto], loc)
      let trap_result = is_truthy(result)
      // Step 10-11: If target non-extensible, proto must match target's prototype
      if trap_result {
        let extensible = target_is_extensible(target)
        if !extensible {
          let target_proto = match target {
            Object(data) => data.prototype
            _ => Null
          }
          if !strict_equal(proto, target_proto) {
            raise @errors.TypeError(
              message="'setPrototypeOf' on proxy: trap returned truish for setting a new prototype on a non-extensible proxy target",
            )
          }
        }
      }
      trap_result
    }
  }
}

///|
/// Implement the Proxy [[HasProperty]] invariant checks per ES §10.5.7.
/// Called after the has trap returns a result.
pub fn proxy_has_property(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : String,
) -> Bool raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "has", interp)
  match trap {
    None =>
      match target {
        Value::Proxy(inner) => proxy_has_property(interp, inner, key)
        _ => interp.has_property(target, key)
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(
        trap_fn,
        handler,
        [target, String_(key)],
        loc,
      )
      let trap_result = is_truthy(result)
      // ES §10.5.7 step 9-10: If trap returns false, check invariants
      if !trap_result {
        // Cannot report a non-configurable own property as non-existent
        if target_has_non_configurable_key(target, key) {
          raise @errors.TypeError(
            message="'has' on proxy: trap returned falsish for property '\{key}' which exists in the proxy target as non-configurable",
          )
        }
        // Cannot report an own property as non-existent on non-extensible target
        if !target_is_extensible(target) && target_has_own_property(target, key) {
          raise @errors.TypeError(
            message="'has' on proxy: trap returned falsish for property '\{key}' but the proxy target is not extensible",
          )
        }
      }
      trap_result
    }
  }
}

///|
/// Implement the Proxy [[Delete]] invariant checks per ES §10.5.10.
pub fn proxy_delete_property(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : String,
) -> Bool raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "deleteProperty", interp)
  match trap {
    None =>
      match target {
        Object(data) => {
          match data.bag.descriptors.get(key) {
            Some(desc) => if !desc.configurable { return false }
            None => ()
          }
          let _ = data.bag.properties.remove(key)
          let _ = data.bag.descriptors.remove(key)
          true
        }
        Value::Proxy(inner) => proxy_delete_property(interp, inner, key)
        _ => true
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(
        trap_fn,
        handler,
        [target, String_(key)],
        loc,
      )
      let trap_result = is_truthy(result)
      // ES §10.5.10 step 10-11: Cannot delete non-configurable property
      if trap_result {
        if target_has_non_configurable_key(target, key) {
          raise @errors.TypeError(
            message="'deleteProperty' on proxy: trap returned truish for property '\{key}' which is non-configurable in the proxy target",
          )
        }
        // Step 12: Cannot delete own property of non-extensible target
        if !target_is_extensible(target) && target_has_own_property(target, key) {
          raise @errors.TypeError(
            message="'deleteProperty' on proxy: trap returned truish for property '\{key}' on a non-extensible proxy target",
          )
        }
      }
      trap_result
    }
  }
}

///|
/// Implement the Proxy [[Get]] invariant checks per ES §10.5.8.
pub fn proxy_get(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : String,
  receiver : Value,
) -> Value raise Error {
  // get_proxy_trap checks revocation and includes trap name in error message
  let trap = get_proxy_trap(proxy_data, "get", interp)
  let target = get_proxy_target(proxy_data)
  match trap {
    None =>
      match target {
        Value::Proxy(_) =>
          interp.get_property(target, key, @token.Loc::default())
        _ => interp.get_property(target, key, @token.Loc::default())
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(
        trap_fn,
        handler,
        [target, String_(key), receiver],
        loc,
      )
      // ES §10.5.8 step 10-11: Invariant checks
      match target_get_own_descriptor(target, key) {
        Some(desc) =>
          if !desc.configurable {
            // Non-configurable data property: trap result must match target value
            if desc.getter is None && !desc.writable {
              let target_value = match target {
                Object(data) =>
                  match data.bag.properties.get(key) {
                    Some(v) => v
                    None => Undefined
                  }
                _ => Undefined
              }
              if !strict_equal(result, target_value) {
                raise @errors.TypeError(
                  message="'get' on proxy: property '\{key}' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value",
                )
              }
            }
            // Non-configurable accessor with undefined getter: must return undefined
            if desc.getter is None && desc.setter is Some(_) {
              // accessor with no getter
              if !strict_equal(result, Undefined) {
                raise @errors.TypeError(
                  message="'get' on proxy: property '\{key}' is a non-configurable accessor property on the proxy target and does not have a getter function, but the trap did not return 'undefined'",
                )
              }
            }
          }
        None => ()
      }
      result
    }
  }
}

///|
/// ES §10.5.9 step 11-12 invariant checks shared by the string-keyed
/// `proxy_set` and the computed (String or Symbol) path in
/// `set_computed_property`. Raises TypeError if the target's own descriptor
/// for `key` is non-configurable and the trap's truish return is a lie.
pub fn check_proxy_set_trap_invariants(
  target : Value,
  key : Value,
  value : Value,
) -> Unit raise Error {
  let (desc_opt, target_value, key_display) = match key {
    String_(k) =>
      (
        target_get_own_descriptor(target, k),
        match target {
          Object(data) =>
            match data.bag.properties.get(k) {
              Some(v) => v
              None => Undefined
            }
          _ => Undefined
        },
        k,
      )
    Symbol(sym) =>
      (
        match target {
          Object(data) => data.bag.symbol_descriptors.get(sym.id)
          _ => None
        },
        match target {
          Object(data) =>
            match data.bag.symbol_properties.get(sym.id) {
              Some(v) => v
              None => Undefined
            }
          _ => Undefined
        },
        "Symbol(\{sym.description.or_default()})",
      )
    _ => (None, Undefined, "")
  }
  match desc_opt {
    Some(desc) =>
      if !desc.configurable {
        if desc.getter is None && !desc.writable {
          if !strict_equal(value, target_value) {
            raise @errors.TypeError(
              message="'set' on proxy: trap returned truish for property '\{key_display}' which exists in the proxy target as a non-configurable and non-writable data property with a different value",
            )
          }
        }
        if desc.getter is Some(_) && desc.setter is None {
          raise @errors.TypeError(
            message="'set' on proxy: trap returned truish for property '\{key_display}' which exists in the proxy target as a non-configurable and non-writable accessor property without a setter",
          )
        }
      }
    None => ()
  }
}

///|
/// Implement the Proxy [[Set]] invariant checks per ES §10.5.9.
pub fn proxy_set(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : String,
  value : Value,
  receiver : Value,
  strict : Bool,
) -> Value raise Error {
  let trap = get_proxy_trap(proxy_data, "set", interp)
  let target = get_proxy_target(proxy_data)
  match trap {
    None =>
      // ES §10.5.9 step 5: target.[[Set]](P, V, Receiver) — preserve receiver
      interp.set_property(
        target,
        key,
        value,
        @token.Loc::default(),
        strict~,
        receiver~,
      )
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(
        trap_fn,
        handler,
        [target, String_(key), value, receiver],
        loc,
      )
      let trap_result = is_truthy(result)
      if !trap_result {
        if strict {
          raise @errors.TypeError(
            message="'set' on proxy: trap returned falsish for property '\{key}'",
          )
        }
        return value
      }
      check_proxy_set_trap_invariants(target, String_(key), value)
      value
    }
  }
}

///|
/// Implement the Proxy [[OwnPropertyKeys]] internal method per ES §10.5.11.
/// Calls the ownKeys trap, validates the result against the target's invariants,
/// and returns the validated list of keys as an Array value.
pub fn proxy_own_property_keys(
  interp : Interpreter,
  proxy_data : ProxyData,
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
        _ => return make_array(collect_target_own_keys(target, interp.symbols))
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
      let len = match data.bag.properties.get("length") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      for i = 0; i < len; i = i + 1 {
        let elem = match data.bag.properties.get(i.to_string()) {
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
    return make_array(trap_keys)
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
    return make_array(trap_keys)
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
  make_array(trap_keys)
}

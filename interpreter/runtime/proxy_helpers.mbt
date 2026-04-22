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
/// Check if target object is extensible. Arrays, Maps, Sets, Promises have
/// no `extensible` field in their data structs today (tracked as a known
/// gap from Stage B.1 — `isExtensible` 2/22 Array failures); they behave
/// as always-extensible.
fn target_is_extensible(target : Value) -> Bool {
  match target {
    Object(data) => data.extensible
    Array(_) | Map(_) | Set(_) | Promise(_) => true
    _ => true
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
/// Descriptors live in `bag` for Object/Map/Set/Promise. Arrays synthesize:
/// `length` is non-configurable; indexed elements default to configurable
/// (no per-index descriptor storage pre-Stage-C).
fn target_has_non_configurable_key(target : Value, key : String) -> Bool {
  match target {
    Object(data) =>
      match data.bag.descriptors.get(key) {
        Some(desc) => !desc.configurable
        None => false
      }
    Map(data) =>
      match data.bag.descriptors.get(key) {
        Some(desc) => !desc.configurable
        None => false
      }
    Set(data) =>
      match data.bag.descriptors.get(key) {
        Some(desc) => !desc.configurable
        None => false
      }
    Promise(data) =>
      match data.bag.descriptors.get(key) {
        Some(desc) => !desc.configurable
        None => false
      }
    Array(_) =>
      // "length" is non-configurable per §10.4.2. Indexed elements and
      // named props have no per-element configurable tracking today.
      key == "length"
    _ => false
  }
}

///|
/// Get the descriptor for a string-keyed own property on the target.
/// Arrays synthesize `length` and indexed element descriptors; other own
/// named props live on `bag` for Object/Map/Set/Promise.
fn target_get_own_descriptor(target : Value, key : String) -> PropDescriptor? {
  match target {
    Object(data) => data.bag.descriptors.get(key)
    Map(data) => data.bag.descriptors.get(key)
    Set(data) => data.bag.descriptors.get(key)
    Promise(data) => data.bag.descriptors.get(key)
    Array(arr) => {
      if key == "length" {
        return Some({
          writable: arr.length_writable,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
        })
      }
      // Indexed element?
      let idx = @string.parse_int(key) catch { _ => -1 }
      if idx >= 0 && idx.to_string() == key && idx < arr.elements.length() {
        return Some({
          writable: true,
          enumerable: true,
          configurable: true,
          getter: None,
          setter: None,
        })
      }
      // Array named props (via side-table) surface through bag descriptors
      // when explicitly registered; otherwise None.
      arr.bag.descriptors.get(key)
    }
    _ => None
  }
}

///|
/// Read the own string-keyed value from the target, or Undefined if absent.
/// Mirrors the variant coverage of `target_get_own_descriptor`. Used by
/// proxy invariant checks that compare trap results to target values for
/// non-configurable non-writable data descriptors.
fn target_get_own_value(target : Value, key : String) -> Value {
  match target {
    Object(data) =>
      match data.bag.properties.get(key) {
        Some(v) => v
        None => Undefined
      }
    Map(data) =>
      match data.bag.properties.get(key) {
        Some(v) => v
        None => Undefined
      }
    Set(data) =>
      match data.bag.properties.get(key) {
        Some(v) => v
        None => Undefined
      }
    Promise(data) =>
      match data.bag.properties.get(key) {
        Some(v) => v
        None => Undefined
      }
    Array(arr) => {
      if key == "length" {
        return Value::Number(arr.elements.length().to_double())
      }
      let idx = @string.parse_int(key) catch { _ => -1 }
      if idx >= 0 && idx.to_string() == key && idx < arr.elements.length() {
        return arr.elements[idx]
      }
      match arr.bag.properties.get(key) {
        Some(v) => v
        None => Undefined
      }
    }
    _ => Undefined
  }
}

///|
/// Check if the target has a specific own string property.
/// Sources: `bag.properties` + `bag.descriptors` for Object/Map/Set/Promise;
/// Array length + indexed elements + bag descriptors for Array.
fn target_has_own_property(target : Value, key : String) -> Bool {
  match target {
    Object(data) =>
      data.bag.properties.contains(key) || data.bag.descriptors.contains(key)
    Map(data) =>
      data.bag.properties.contains(key) || data.bag.descriptors.contains(key)
    Set(data) =>
      data.bag.properties.contains(key) || data.bag.descriptors.contains(key)
    Promise(data) =>
      data.bag.properties.contains(key) || data.bag.descriptors.contains(key)
    Array(arr) => {
      if key == "length" {
        return true
      }
      let idx = @string.parse_int(key) catch { _ => -1 }
      if idx >= 0 && idx.to_string() == key && idx < arr.elements.length() {
        return true
      }
      arr.bag.properties.contains(key) || arr.bag.descriptors.contains(key)
    }
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
              let target_value = target_get_own_value(target, key)
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
      (target_get_own_descriptor(target, k), target_get_own_value(target, k), k)
    Symbol(sym) =>
      (
        match target {
          Object(data) => data.bag.symbol_descriptors.get(sym.id)
          Map(data) => data.bag.symbol_descriptors.get(sym.id)
          Set(data) => data.bag.symbol_descriptors.get(sym.id)
          Promise(data) => data.bag.symbol_descriptors.get(sym.id)
          Array(arr) => arr.bag.symbol_descriptors.get(sym.id)
          _ => None
        },
        match target {
          Object(data) =>
            match data.bag.symbol_properties.get(sym.id) {
              Some(v) => v
              None => Undefined
            }
          Map(data) =>
            match data.bag.symbol_properties.get(sym.id) {
              Some(v) => v
              None => Undefined
            }
          Set(data) =>
            match data.bag.symbol_properties.get(sym.id) {
              Some(v) => v
              None => Undefined
            }
          Promise(data) =>
            match data.bag.symbol_properties.get(sym.id) {
              Some(v) => v
              None => Undefined
            }
          Array(arr) =>
            match arr.bag.symbol_properties.get(sym.id) {
              Some(v) => v
              None => Undefined
            }
          _ => Undefined
        },
        "Symbol(\{sym.description.unwrap_or_default()})",
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

// ---------------------------------------------------------------------------
// Stage B.2: [[GetOwnProperty]] + [[DefineOwnProperty]] traps
// ---------------------------------------------------------------------------

///|
/// Convert a PartialDescriptor into a plain JS descriptor object so it can
/// be passed to a Proxy defineProperty trap as the `Descriptor` argument.
/// Per ES §6.2.5.4 FromPropertyDescriptor, only present fields are emitted
/// (absent fields don't appear on the object).
fn partial_desc_to_value(partial : PartialDescriptor) -> Value {
  let props : Map[String, Value] = {}
  match partial.value {
    Some(v) => props["value"] = v
    None => ()
  }
  match partial.writable {
    Some(w) => props["writable"] = Value::Bool(w)
    None => ()
  }
  match partial.enumerable {
    Some(e) => props["enumerable"] = Value::Bool(e)
    None => ()
  }
  match partial.configurable {
    Some(c) => props["configurable"] = Value::Bool(c)
    None => ()
  }
  if partial.has_getter {
    props["get"] = partial.getter.unwrap_or(Undefined)
  }
  if partial.has_setter {
    props["set"] = partial.setter.unwrap_or(Undefined)
  }
  Value::Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: Null,
    extensible: true,
    callable: None,
    class_name: "Object",
  })
}

///|
/// Parse a Proxy getOwnPropertyDescriptor trap's result Value into a
/// PropDescriptor. Approximates §6.2.5.5 CompletePropertyDescriptor:
/// fill absent writable/enumerable/configurable with false. Trap is
/// expected to return an object (caller validates non-object rejection).
fn trap_result_to_descriptor(
  trap_result : Value,
  interp : Interpreter,
) -> PropDescriptor raise Error {
  let loc = @token.Loc::default()
  let writable = if has_property(trap_result, "writable", interp=Some(interp)) {
    is_truthy(interp.get_property(trap_result, "writable", loc))
  } else {
    false
  }
  let enumerable = if has_property(
      trap_result,
      "enumerable",
      interp=Some(interp),
    ) {
    is_truthy(interp.get_property(trap_result, "enumerable", loc))
  } else {
    false
  }
  let configurable = if has_property(
      trap_result,
      "configurable",
      interp=Some(interp),
    ) {
    is_truthy(interp.get_property(trap_result, "configurable", loc))
  } else {
    false
  }
  let getter = if has_property(trap_result, "get", interp=Some(interp)) {
    let g = interp.get_property(trap_result, "get", loc)
    match g {
      Undefined => None
      _ => Some(g)
    }
  } else {
    None
  }
  let setter = if has_property(trap_result, "set", interp=Some(interp)) {
    let s = interp.get_property(trap_result, "set", loc)
    match s {
      Undefined => None
      _ => Some(s)
    }
  } else {
    None
  }
  { writable, enumerable, configurable, getter, setter }
}

///|
/// Extract the value field from a trap result, if present.
fn trap_result_value(
  trap_result : Value,
  interp : Interpreter,
) -> Value? raise Error {
  if has_property(trap_result, "value", interp=Some(interp)) {
    Some(interp.get_property(trap_result, "value", @token.Loc::default()))
  } else {
    None
  }
}

///|
/// Is this value a plain object (can hold a descriptor)? Proxy, Map, Set,
/// Promise, Array qualify per §7.2.5 IsObject (but for GOPD trap result
/// we want an Object-ish shape with readable properties).
fn is_object_type(val : Value) -> Bool {
  match val {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    _ => false
  }
}

///|
/// ES §10.5.5 `[[GetOwnProperty]]` (Proxy). Invokes the
/// `getOwnPropertyDescriptor` trap with the canonical invariant set:
/// - trap returns non-object non-undefined -> TypeError
/// - target's own desc is non-configurable AND trap returns undefined -> TypeError
/// - target is non-extensible + no own desc + trap returns object -> TypeError
/// - trap reports non-configurable + non-writable; target is NOT both -> TypeError
/// - target non-configurable accessor: getter/setter identity must match (SameValue)
/// Returns the completed descriptor or None.
pub fn proxy_get_own_property(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : Value,
) -> (PropDescriptor, Value)? raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "getOwnPropertyDescriptor", interp)
  match trap {
    None =>
      // Delegate to the target's own [[GetOwnProperty]]. For Proxy-of-Proxy
      // this recurses; otherwise reads from the ordinary/Array path.
      match target {
        Value::Proxy(inner) => proxy_get_own_property(interp, inner, key)
        _ =>
          match ordinary_get_own_property(target, key) {
            None => None
            Some(desc) =>
              Some((desc, ordinary_get_own_value_for_descriptor(target, key)))
          }
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let key_val = match key {
        Symbol(_) => key
        _ => Value::String_(key.to_string())
      }
      let trap_result = interp.call_value(
        trap_fn,
        handler,
        [target, key_val],
        loc,
      )
      // §10.5.5 step 8: trap result must be object or undefined.
      match trap_result {
        Undefined => ()
        _ =>
          if !is_object_type(trap_result) {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap returned neither object nor undefined",
            )
          }
      }
      let target_desc : PropDescriptor? = match key {
        Symbol(sym) =>
          match target {
            Object(data) => data.bag.symbol_descriptors.get(sym.id)
            Map(data) => data.bag.symbol_descriptors.get(sym.id)
            Set(data) => data.bag.symbol_descriptors.get(sym.id)
            Promise(data) => data.bag.symbol_descriptors.get(sym.id)
            Array(arr) => arr.bag.symbol_descriptors.get(sym.id)
            _ => None
          }
        _ => target_get_own_descriptor(target, key.to_string())
      }
      // §10.5.5 step 10: trap returns undefined.
      if trap_result is Undefined {
        match target_desc {
          None => return None
          Some(desc) => {
            // Step 10.b: target desc must be configurable.
            if !desc.configurable {
              raise @errors.TypeError(
                message="'getOwnPropertyDescriptor' on proxy: trap returned undefined for property which exists as non-configurable on the proxy target",
              )
            }
            // Step 10.c: target must be extensible.
            if !target_is_extensible(target) {
              raise @errors.TypeError(
                message="'getOwnPropertyDescriptor' on proxy: trap returned undefined for property which exists on a non-extensible proxy target",
              )
            }
            return None
          }
        }
      }
      // §10.5.5 step 11+: parse trap descriptor; run invariants.
      let trap_desc = trap_result_to_descriptor(trap_result, interp)
      let trap_value_opt = if !(trap_desc.getter is Some(_) ||
        trap_desc.setter is Some(_)) {
        trap_result_value(trap_result, interp)
      } else {
        None
      }
      let target_extensible = target_is_extensible(target)
      match target_desc {
        None =>
          // Step 17 (reorg): target has no own desc; target must be extensible.
          if !target_extensible {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported non-existent property on a non-extensible target",
            )
          }
        Some(existing) => {
          // Step 17.a: cannot report non-configurable when target is configurable.
          if !trap_desc.configurable && existing.configurable {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable for property which is configurable on the proxy target",
            )
          }
          // Step 17.b: cannot report non-configurable + non-writable unless target matches.
          let trap_is_data = trap_desc.getter is None &&
            trap_desc.setter is None
          let existing_is_data = existing.getter is None &&
            existing.setter is None
          if trap_is_data &&
            existing_is_data &&
            !trap_desc.configurable &&
            !trap_desc.writable &&
            existing.writable {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and non-writable for property which is writable on the proxy target",
            )
          }
          // Accessor identity for existing non-configurable accessor.
          if !existing.configurable && !existing_is_data && !trap_is_data {
            let g_ok = match (existing.getter, trap_desc.getter) {
              (None, None) => true
              (Some(a), Some(b)) => strict_equal(a, b)
              _ => false
            }
            let s_ok = match (existing.setter, trap_desc.setter) {
              (None, None) => true
              (Some(a), Some(b)) => strict_equal(a, b)
              _ => false
            }
            if !g_ok || !s_ok {
              raise @errors.TypeError(
                message="'getOwnPropertyDescriptor' on proxy: trap reported mismatched accessor for non-configurable accessor on proxy target",
              )
            }
          }
        }
      }
      let trap_value = match trap_value_opt {
        Some(v) => v
        None => Undefined
      }
      Some((trap_desc, trap_value))
    }
  }
}

///|
/// ES §10.5.6 `[[DefineOwnProperty]]` (Proxy). Invokes the `defineProperty`
/// trap and validates:
/// - trap returns falsy -> return false
/// - trap returns true + target has no own desc + target non-extensible -> TypeError
/// - trap returns true + incoming descriptor is non-configurable + target
///   descriptor doesn't exist / is configurable -> TypeError
/// - trap returns true + existing target desc non-configurable incompatible
///   with incoming -> TypeError
pub fn proxy_define_property(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : Value,
  partial : PartialDescriptor,
) -> Bool raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "defineProperty", interp)
  match trap {
    None =>
      // Delegate: Proxy-of-Proxy recurses; otherwise route through dispatcher.
      match target {
        Value::Proxy(inner) =>
          proxy_define_property(interp, inner, key, partial)
        _ =>
          interp.ordinary_define_own_property(
            target,
            key,
            partial,
            @token.Loc::default(),
          )
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let key_val = match key {
        Symbol(_) => key
        _ => Value::String_(key.to_string())
      }
      let desc_val = partial_desc_to_value(partial)
      let result = interp.call_value(
        trap_fn,
        handler,
        [target, key_val, desc_val],
        loc,
      )
      let trap_result = is_truthy(result)
      if !trap_result {
        return false
      }
      // Invariant checks: §10.5.6 step 14+.
      let target_desc : PropDescriptor? = match key {
        Symbol(sym) =>
          match target {
            Object(data) => data.bag.symbol_descriptors.get(sym.id)
            Map(data) => data.bag.symbol_descriptors.get(sym.id)
            Set(data) => data.bag.symbol_descriptors.get(sym.id)
            Promise(data) => data.bag.symbol_descriptors.get(sym.id)
            Array(arr) => arr.bag.symbol_descriptors.get(sym.id)
            _ => None
          }
        _ => target_get_own_descriptor(target, key.to_string())
      }
      let target_extensible = target_is_extensible(target)
      let is_new = target_desc is None
      // Step 16.b: cannot add a new non-configurable property to non-extensible target.
      if is_new {
        if !target_extensible {
          raise @errors.TypeError(
            message="'defineProperty' on proxy: trap returned truish for adding property to non-extensible target",
          )
        }
        if partial.configurable is Some(false) {
          raise @errors.TypeError(
            message="'defineProperty' on proxy: trap returned truish for defining non-configurable property which does not exist on proxy target",
          )
        }
      } else {
        let current = target_desc.unwrap()
        // Step 18.b: if incoming is non-configurable, existing must also be.
        if partial.configurable is Some(false) && current.configurable {
          raise @errors.TypeError(
            message="'defineProperty' on proxy: trap returned truish for defining non-configurable property on proxy target where property is configurable",
          )
        }
        // §10.5.6 step 18.c: non-configurable existing + incoming data
        // reporting writable:false over existing writable:true -> TypeError.
        // (Spec requires target's writable to remain true if the trap succeeds
        //  but didn't report non-writable; conversely, a lying non-writable
        //  over a non-configurable writable target is invariant-busting.)
        let current_is_data = current.getter is None && current.setter is None
        if !current.configurable && current_is_data && current.writable {
          if partial.writable is Some(false) {
            raise @errors.TypeError(
              message="'defineProperty' on proxy: trap returned truish for non-writable redefinition of a non-configurable writable data property on proxy target",
            )
          }
        }
        // Step 18.c full compatibility when existing is non-configurable.
        if !current.configurable {
          // Key-aware current-value lookup — Symbol keys must not coerce
          // through key.to_string() (would read a different slot).
          let cur_val = match key {
            Symbol(sym) =>
              match target {
                Object(data) =>
                  match data.bag.symbol_properties.get(sym.id) {
                    Some(v) => v
                    None => Undefined
                  }
                Map(data) =>
                  match data.bag.symbol_properties.get(sym.id) {
                    Some(v) => v
                    None => Undefined
                  }
                Set(data) =>
                  match data.bag.symbol_properties.get(sym.id) {
                    Some(v) => v
                    None => Undefined
                  }
                Promise(data) =>
                  match data.bag.symbol_properties.get(sym.id) {
                    Some(v) => v
                    None => Undefined
                  }
                Array(arr) =>
                  // Array Symbol values live in the side table, not arr.bag.
                  // (Pre-Stage-C inconsistency; Stage C unifies onto bag.)
                  match get_array_symbol_prop(arr, sym.id) {
                    Some(v) => v
                    None => Undefined
                  }
                _ => Undefined
              }
            _ => target_get_own_value(target, key.to_string())
          }
          if !is_compatible_with_non_configurable(current, partial, cur_val) {
            raise @errors.TypeError(
              message="'defineProperty' on proxy: trap returned truish for incompatible redefinition of non-configurable property on proxy target",
            )
          }
        }
      }
      true
    }
  }
}

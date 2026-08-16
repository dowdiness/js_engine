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
/// Revoke a proxy by nullifying its target and handler slots. The cached
/// The cached call/construct classifications are intentionally left untouched:
/// revocation clears the target and handler slots, not the Proxy's internal
/// [[Call]] and [[Construct]] methods.
pub fn revoke_proxy(proxy_data : ProxyData) -> Unit {
  proxy_data.target = None
  proxy_data.handler = None
}

///|
fn typedarray_declared_length(data : ObjectData) -> Int {
  guard is_typedarray_class(data.class_name) else { return 0 }
  match data.bag.internal_slots.get(ArrayLength) {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
}

///|
fn is_typedarray_own_index_key(key : String, length : Int) -> Bool {
  guard length > 0 else { return false }
  let idx = @string.parse_int(key) catch { _ => -1 }
  idx >= 0 && idx < length && idx.to_string() == key
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
    None => interp.is_extensible_internal(target)
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target], loc)
      let trap_result = is_truthy(result)
      let target_extensible = interp.is_extensible_internal(target)
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
/// Get the descriptor for a string-keyed own property on the target.
/// Arrays synthesize `length` and indexed element descriptors; other own
/// named props live on `bag`.
fn target_get_own_descriptor(
  interp : Interpreter?,
  target : Value,
  key : String,
) -> PropDescriptor? raise Error {
  // Properties created via ordinary assignment (`o.x = 1`) live in
  // bag.properties without always receiving a bag.descriptors entry.
  // For §10.5.5 / §10.5.6 invariants we must report such keys as
  // existing with the default data-descriptor shape (w/e/c all true)
  // per §10.1.5.1 OrdinaryGetOwnProperty.
  let default_data : PropDescriptor = {
    writable: true,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  match target {
    Object(data) =>
      if data.class_name == "Module" {
        match interp {
          Some(ip) =>
            match
              ip.module_namespace_get_own_property_pair(data, String_(key)) {
              Some((desc, _)) => Some(desc)
              None => None
            }
          None =>
            if data.bag.properties.contains(key) {
              Some(module_namespace_export_descriptor())
            } else {
              None
            }
        }
      } else {
        match data.bag.descriptors.get(key) {
          Some(d) => Some(d)
          None =>
            if data.bag.properties.contains(key) {
              Some(default_data)
            } else {
              None
            }
        }
      }
    Map(data) =>
      match data.bag.descriptors.get(key) {
        Some(d) => Some(d)
        None =>
          if data.bag.properties.contains(key) {
            Some(default_data)
          } else {
            None
          }
      }
    Set(data) =>
      match data.bag.descriptors.get(key) {
        Some(d) => Some(d)
        None =>
          if data.bag.properties.contains(key) {
            Some(default_data)
          } else {
            None
          }
      }
    Promise(data) =>
      match data.bag.descriptors.get(key) {
        Some(d) => Some(d)
        None =>
          if data.bag.properties.contains(key) {
            Some(default_data)
          } else {
            None
          }
      }
    Array(arr) => {
      if key == "length" {
        return Some({
          writable: arr.length_writable,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        })
      }
      // Indexed element?
      let idx = @string.parse_int(key) catch { _ => -1 }
      if idx >= 0 && idx.to_string() == key && idx < arr.elements.length() {
        return match arr.bag.descriptors.get(key) {
          Some(d) => Some(d)
          None => Some(default_data)
        }
      }
      // Array named props surface through bag descriptors when explicitly
      // registered; assignment-created props synthesize the default shape.
      match arr.bag.descriptors.get(key) {
        Some(d) => Some(d)
        None =>
          if arr.bag.properties.contains(key) {
            Some(default_data)
          } else {
            None
          }
      }
    }
    _ => None
  }
}

///|
/// Read the own string-keyed value from the target, or Undefined if absent.
/// Mirrors the variant coverage of `target_get_own_descriptor`. Used by
/// proxy invariant checks that compare trap results to target values for
/// non-configurable non-writable data descriptors.
fn target_get_own_value(
  interp : Interpreter?,
  target : Value,
  key : String,
) -> Value raise Error {
  match target {
    Object(data) =>
      if data.class_name == "Module" {
        match interp {
          Some(ip) =>
            match
              ip.module_namespace_get_own_property_pair(data, String_(key)) {
              Some((_, value)) => value
              None => Undefined
            }
          None =>
            match data.bag.descriptors.get(key) {
              Some({ getter: Some(getter), .. }) =>
                call_callable_direct(getter, Object(data), [])
              _ => Undefined
            }
        }
      } else {
        match data.bag.properties.get(key) {
          Some(v) => v
          None => Undefined
        }
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
/// Resolve the target's canonical [[GetOwnProperty]] descriptor/value pair
/// when an interpreter is available. The interpreter-free fallback exists for
/// the legacy public invariant helper and cannot observe Proxy internals.
fn target_get_own_property_pair_for_invariant(
  interp : Interpreter?,
  target : Value,
  key : Value,
) -> (PropDescriptor, Value)? raise Error {
  match interp {
    Some(ip) => ip.get_own_property(target, key)
    None =>
      match key {
        String_(name) =>
          match target_get_own_descriptor(None, target, name) {
            Some(desc) => Some((desc, target_get_own_value(None, target, name)))
            None => None
          }
        Symbol(_) =>
          match ordinary_get_own_property(target, key) {
            Some(desc) =>
              Some((desc, ordinary_get_own_value_for_descriptor(target, key)))
            None => None
          }
        _ => None
      }
  }
}

///|
/// Apply ES §10.5.8 steps 10-11 to a completed Proxy `get` trap. Both the
/// legacy call path and admitted activation dispatch use this single boundary
/// so the post-trap descriptor rules remain identical.
fn validate_proxy_get_trap_result(
  interp : Interpreter,
  target : Value,
  property_key : Value,
  result : Value,
) -> Unit raise Error {
  match
    target_get_own_property_pair_for_invariant(
      Some(interp),
      target,
      property_key,
    ) {
    Some((desc, target_value)) =>
      if !desc.configurable {
        if !desc.is_accessor &&
          !desc.writable &&
          !same_value(result, target_value) {
          raise @errors.TypeError(
            message="'get' on proxy: trap did not return the actual value of a read-only non-configurable target property",
          )
        }
        if desc.is_accessor &&
          desc.getter is None &&
          !same_value(result, Undefined) {
          raise @errors.TypeError(
            message="'get' on proxy: trap returned a value for a non-configurable target accessor without a getter",
          )
        }
      }
    None => ()
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
    None => interp.prevent_extensions_internal(target)
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target], loc)
      let trap_result = is_truthy(result)
      // ES §10.5.4 step 8: If trap returns true, target must not be extensible
      if trap_result {
        let target_extensible = interp.is_extensible_internal(target)
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
    None => object_get_prototype_of(interp, target)
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
      let extensible = interp.is_extensible_internal(target)
      if !extensible {
        let target_proto = object_get_prototype_of(interp, target)
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
      match object_set_prototype_of(interp, target, proto) {
        Bool(result) => result
        _ => false
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target, proto], loc)
      let trap_result = is_truthy(result)
      // Step 10-11: If target non-extensible, proto must match target's prototype
      if trap_result {
        let extensible = interp.is_extensible_internal(target)
        if !extensible {
          let target_proto = object_get_prototype_of(interp, target)
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
  proxy_has_property_key(interp, proxy_data, String_(key))
}

///|
pub fn proxy_has_property_key(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : Value,
) -> Bool raise Error {
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "has", interp)
  let key_display = match key {
    Symbol(sym) => "Symbol(\{sym.description.unwrap_or_default()})"
    _ => to_js_string(key)
  }
  match trap {
    None =>
      match target {
        Value::Proxy(inner) => proxy_has_property_key(interp, inner, key)
        _ => interp.has_property_key(target, key)
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target, key], loc)
      let trap_result = is_truthy(result)
      // ES §10.5.7 step 9-10: If trap returns false, check invariants
      if !trap_result {
        let target_desc = interp.get_own_property(target, key)
        // Cannot report a non-configurable own property as non-existent
        match target_desc {
          Some((desc, _)) =>
            if !desc.configurable {
              raise @errors.TypeError(
                message="'has' on proxy: trap returned falsish for property '\{key_display}' which exists in the proxy target as non-configurable",
              )
            }
          None => ()
        }
        // Cannot report an own property as non-existent on non-extensible target
        if !interp.is_extensible_internal(target) && target_desc is Some(_) {
          raise @errors.TypeError(
            message="'has' on proxy: trap returned falsish for property '\{key_display}' but the proxy target is not extensible",
          )
        }
      }
      trap_result
    }
  }
}

///|
fn proxy_delete_key_display(key : Value) -> String {
  match key {
    Symbol(sym) => "Symbol(\{sym.description.unwrap_or_default()})"
    String_(s) => s
    _ => to_js_string(key) catch { _ => "<property key>" }
  }
}

///|
/// Implement the Proxy [[Delete]] invariant checks per ES §10.5.10.
pub fn proxy_delete_property(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : String,
) -> Bool raise Error {
  proxy_delete_property_key(interp, proxy_data, String_(key))
}

///|
fn proxy_delete_property_key(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : Value,
) -> Bool raise Error {
  let prop_key = match key {
    Symbol(_) | String_(_) => key
    _ => String_(to_js_string(key, interp=Some(interp)))
  }
  let key_display = proxy_delete_key_display(prop_key)
  let target = get_proxy_target(proxy_data)
  let trap = get_proxy_trap(proxy_data, "deleteProperty", interp)
  match trap {
    None =>
      match target {
        Value::Proxy(inner) =>
          proxy_delete_property_key(interp, inner, prop_key)
        _ => interp.delete_property_key(target, prop_key)
      }
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(trap_fn, handler, [target, prop_key], loc)
      let trap_result = is_truthy(result)
      // ES §10.5.10 step 10-11: Cannot delete non-configurable property
      if trap_result {
        let target_desc = interp.get_own_property(target, prop_key)
        match target_desc {
          Some((desc, _)) =>
            if !desc.configurable {
              raise @errors.TypeError(
                message="'deleteProperty' on proxy: trap returned truish for property '\{key_display}' which is non-configurable in the proxy target",
              )
            }
          None => ()
        }
        // Step 12: Cannot delete own property of non-extensible target
        if !interp.is_extensible_internal(target) && target_desc is Some(_) {
          raise @errors.TypeError(
            message="'deleteProperty' on proxy: trap returned truish for property '\{key_display}' on a non-extensible proxy target",
          )
        }
      }
      trap_result
    }
  }
}

///|
/// Implement Proxy [[Get]] for either kind of PropertyKey. Trap-less proxies
/// delegate to the target's receiver-aware [[Get]] rather than restarting a
/// normal property access with the target as Receiver.
fn proxy_get_key(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : Value,
  receiver : Value,
) -> Value raise Error {
  let prop_key = to_property_key(key, interp=Some(interp))
  // get_proxy_trap checks revocation and includes trap name in error message
  let trap = get_proxy_trap(proxy_data, "get", interp)
  let target = get_proxy_target(proxy_data)
  match trap {
    None =>
      interp.get_property_key_with_receiver(
        target,
        prop_key,
        receiver,
        @token.Loc::default(),
      )
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      let result = interp.call_value(
        trap_fn,
        handler,
        [target, prop_key, receiver],
        loc,
      )
      validate_proxy_get_trap_result(interp, target, prop_key, result)
      result
    }
  }
}

///|
/// String-key compatibility wrapper for existing [[Get]] call sites.
pub fn proxy_get(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : String,
  receiver : Value,
) -> Value raise Error {
  proxy_get_key(interp, proxy_data, String_(key), receiver)
}

///|
/// ES §10.5.9 step 11-12 invariant checks shared by the string-keyed
/// `proxy_set` and the computed (String or Symbol) path in
/// `set_computed_property`. Raises TypeError if the target's own descriptor
/// for `key` is non-configurable and the trap's truish return is a lie.
fn check_proxy_set_trap_invariants_with_interp(
  interp : Interpreter?,
  target : Value,
  key : Value,
  value : Value,
) -> Unit raise Error {
  let key_display = match key {
    String_(name) => name
    Symbol(sym) => "Symbol(\{sym.description.unwrap_or_default()})"
    _ => ""
  }
  let target_entry = target_get_own_property_pair_for_invariant(
    interp, target, key,
  )
  let (desc_opt, target_value) = match target_entry {
    Some((desc, current_value)) => (Some(desc), current_value)
    None => (None, Undefined)
  }
  match desc_opt {
    Some(desc) =>
      if !desc.configurable {
        if !desc.is_accessor && !desc.writable {
          if !same_value(value, target_value) {
            raise @errors.TypeError(
              message="'set' on proxy: trap returned truish for property '\{key_display}' which exists in the proxy target as a non-configurable and non-writable data property with a different value",
            )
          }
        }
        if desc.is_accessor && desc.setter is None {
          raise @errors.TypeError(
            message="'set' on proxy: trap returned truish for property '\{key_display}' which exists in the proxy target as a non-configurable accessor property without a setter",
          )
        }
      }
    None => ()
  }
}

///|
pub fn check_proxy_set_trap_invariants(
  target : Value,
  key : Value,
  value : Value,
) -> Unit raise Error {
  check_proxy_set_trap_invariants_with_interp(None, target, key, value)
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
      check_proxy_set_trap_invariants_with_interp(
        Some(interp),
        target,
        String_(key),
        value,
      )
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
    None => return make_array(interp.own_property_keys(target))
    _ => ()
  }
  let trap_fn = trap.unwrap()
  let handler = get_proxy_handler(proxy_data)
  let loc = @token.Loc::default()
  // Step 7: Call trap(handler, target)
  let trap_result = interp.call_value(trap_fn, handler, [target], loc)
  // Step 8: CreateListFromArrayLike(trapResult, « String, Symbol »)
  guard is_object_type(trap_result) else {
    raise @errors.TypeError(
      message="'ownKeys' on proxy: trap returned non-object",
    )
  }
  let trap_keys : Array[Value] = []
  let trap_result_len = to_array_like_length_interp(trap_result, interp)
  for i = 0L; i < trap_result_len; i = i + 1L {
    let elem = get_array_like_element_interp(interp, trap_result, i)
    match elem {
      Value::String_(_) | Value::Symbol(_) => trap_keys.push(elem)
      _ =>
        raise @errors.TypeError(
          message="'ownKeys' on proxy: trap result must contain only Strings and Symbols",
        )
    }
  }
  // Step 9: If trapResult contains any duplicate entries, throw TypeError
  let seen_strings = @set.Set::default()
  let seen_symbols : Map[Int, Bool] = Map([])
  for key in trap_keys {
    match key {
      Value::String_(s) => {
        if seen_strings.contains(s) {
          raise @errors.TypeError(
            message="'ownKeys' on proxy: trap returned duplicate key '\{s}'",
          )
        }
        seen_strings.add(s)
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
  let extensible_target = interp.is_extensible_internal(target)
  // Step 11-12: Get target keys, split into non-configurable and configurable
  let target_keys = interp.own_property_keys(target)
  let target_nonconfigurable_keys : Array[Value] = []
  let target_configurable_keys : Array[Value] = []
  for key in target_keys {
    let non_configurable = match interp.get_own_property(target, key) {
      Some((desc, _)) => !desc.configurable
      None => false
    }
    if non_configurable {
      target_nonconfigurable_keys.push(key)
    } else {
      target_configurable_keys.push(key)
    }
  }
  // Step 15: If extensibleTarget is true and targetNonconfigurableKeys is empty, return
  if extensible_target && target_nonconfigurable_keys.is_empty() {
    return make_array(trap_keys)
  }
  // Step 16: Let uncheckedResultKeys be a copy of trapResult
  let unchecked : Map[String, Int] = Map([]) // string key -> count
  let unchecked_sym : Map[Int, Int] = Map([]) // symbol id -> count
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
fn partial_desc_to_value(
  partial : PartialDescriptor,
  realm_state : RealmState,
) -> Value {
  let props : Map[String, Value] = Map([])
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
      symbol_properties: Map([]),
      descriptors: Map([]),
      symbol_descriptors: Map([]),
      internal_slots: Map([]),
      host_slots: Map([]),
    },
    prototype: realm_state.get_obj_proto(),
    extensible: true,
    arraybuffer_state: None,
    callable: None,
    class_name: "Object",
  })
}

///|
/// Parse a Proxy getOwnPropertyDescriptor trap's result Value into a
/// completed descriptor and its completed data value. ToPropertyDescriptor
/// observes each field in specification order, with one HasProperty and one
/// Get for every present field; CompletePropertyDescriptor supplies defaults.
fn trap_result_to_descriptor(
  trap_result : Value,
  interp : Interpreter,
) -> (PropDescriptor, Value) raise Error {
  let loc = @token.Loc::default()
  let has_enumerable = interp.has_property(trap_result, "enumerable")
  let enumerable = if has_enumerable {
    Some(is_truthy(interp.get_property(trap_result, "enumerable", loc)))
  } else {
    None
  }
  let has_configurable = interp.has_property(trap_result, "configurable")
  let configurable = if has_configurable {
    Some(is_truthy(interp.get_property(trap_result, "configurable", loc)))
  } else {
    None
  }
  let has_value = interp.has_property(trap_result, "value")
  let value = if has_value {
    Some(interp.get_property(trap_result, "value", loc))
  } else {
    None
  }
  let has_writable = interp.has_property(trap_result, "writable")
  let writable = if has_writable {
    Some(is_truthy(interp.get_property(trap_result, "writable", loc)))
  } else {
    None
  }
  let has_get = interp.has_property(trap_result, "get")
  let getter = if has_get {
    let g = interp.get_property(trap_result, "get", loc)
    match g {
      Undefined => None
      _ => {
        guard is_callable(g) else {
          raise @errors.TypeError(
            message="Getter must be a function: \{g.to_string()}",
          )
        }
        Some(g)
      }
    }
  } else {
    None
  }
  let has_set = interp.has_property(trap_result, "set")
  let setter = if has_set {
    let s = interp.get_property(trap_result, "set", loc)
    match s {
      Undefined => None
      _ => {
        guard is_callable(s) else {
          raise @errors.TypeError(
            message="Setter must be a function: \{s.to_string()}",
          )
        }
        Some(s)
      }
    }
  } else {
    None
  }
  let is_accessor = has_get || has_set
  let is_data = has_value || has_writable
  guard !(is_accessor && is_data) else {
    raise @errors.TypeError(
      message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute",
    )
  }
  let descriptor : PropDescriptor = {
    writable: writable.unwrap_or(false),
    enumerable: enumerable.unwrap_or(false),
    configurable: configurable.unwrap_or(false),
    getter,
    setter,
    is_accessor,
  }
  let completed_value = if is_accessor {
    Undefined
  } else {
    value.unwrap_or(Undefined)
  }
  (descriptor, completed_value)
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
    None => interp.get_own_property(target, key)
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      // §7.1.19 ToPropertyKey — use to_js_string so object-typed keys
      // with Symbol.toPrimitive/toString hooks coerce per spec, matching
      // the key the validation path will subsequently look up.
      let key_val = match key {
        Symbol(_) => key
        _ => Value::String_(to_js_string(key))
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
      let target_entry = interp.get_own_property(target, key_val)
      let target_desc = match target_entry {
        Some((desc, _)) => Some(desc)
        None => None
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
            if !interp.is_extensible_internal(target) {
              raise @errors.TypeError(
                message="'getOwnPropertyDescriptor' on proxy: trap returned undefined for property which exists on a non-extensible proxy target",
              )
            }
            return None
          }
        }
      }
      // §10.5.5 step 11: an object trap result always observes target
      // extensibility before ToPropertyDescriptor can run guest getters.
      let target_extensible = interp.is_extensible_internal(target)
      // §10.5.5 step 12+: parse trap descriptor; run invariants.
      let (trap_desc, trap_value) = trap_result_to_descriptor(
        trap_result, interp,
      )
      match target_desc {
        None => {
          // §10.5.5 step 17.c: target has no own desc; target must be
          // extensible AND the trap must not report non-configurable
          // (can't invent a non-configurable key that doesn't exist).
          if !target_extensible {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported non-existent property on a non-extensible target",
            )
          }
          if !trap_desc.configurable {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable for a key that does not exist on the proxy target",
            )
          }
        }
        Some(existing) => {
          // Step 17.a: cannot report non-configurable when target is configurable.
          if trap_desc.configurable != existing.configurable {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported a different configurable value for a property on the proxy target",
            )
          }
          // §10.5.5 step 17.a (bis): enumerable must match when target is
          // non-configurable. Missing from the prior invariant set.
          if !existing.configurable &&
            trap_desc.enumerable != existing.enumerable {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported different enumerable for non-configurable property on proxy target",
            )
          }
          // Step 17.b: cannot report non-configurable + non-writable unless target matches.
          let trap_is_data = !trap_desc.is_accessor
          let existing_is_data = !existing.is_accessor
          if trap_is_data &&
            existing_is_data &&
            !trap_desc.configurable &&
            trap_desc.writable &&
            !existing.writable {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and writable for property which is non-writable on the proxy target",
            )
          }
          if trap_is_data &&
            existing_is_data &&
            !trap_desc.configurable &&
            !trap_desc.writable &&
            existing.writable {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and non-writable for property which is writable on the proxy target",
            )
          }
          // §10.5.5 step 17.b SameValue extension: when target is frozen
          // (nc+nw data) the trap's reported value must equal target's.
          // Compare only when both sides are data and target is nc+nw.
          if trap_is_data &&
            existing_is_data &&
            !existing.configurable &&
            !existing.writable {
            let cur_val = match target_entry {
              Some((_, value)) => value
              None => Undefined
            }
            if !same_value(trap_value, cur_val) {
              raise @errors.TypeError(
                message="'getOwnPropertyDescriptor' on proxy: trap reported different value for non-configurable non-writable data property on proxy target",
              )
            }
          }
          // §10.5.5 step 17.a (descriptor-kind invariance for non-configurable):
          // a non-configurable property's descriptor kind (data vs accessor)
          // must not change. Reject data→accessor AND accessor→data
          // reports on a non-configurable target.
          if !existing.configurable && existing_is_data != trap_is_data {
            raise @errors.TypeError(
              message="'getOwnPropertyDescriptor' on proxy: trap reported descriptor kind (data/accessor) mismatch for non-configurable property on proxy target",
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
      interp.define_own_property(target, key, partial, @token.Loc::default())
    Some(trap_fn) => {
      let handler = get_proxy_handler(proxy_data)
      let loc = @token.Loc::default()
      // §7.1.19 ToPropertyKey — use to_js_string so object-typed keys
      // with Symbol.toPrimitive/toString hooks coerce per spec, matching
      // the key the validation path will subsequently look up.
      let key_val = match key {
        Symbol(_) => key
        _ => Value::String_(to_js_string(key))
      }
      let desc_val = partial_desc_to_value(partial, interp.realm_state)
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
      let target_entry = interp.get_own_property(target, key_val)
      let target_desc = match target_entry {
        Some((desc, _)) => Some(desc)
        None => None
      }
      let target_extensible = interp.is_extensible_internal(target)
      // is_new: key is absent as an own property. Use the target's real
      // [[GetOwnProperty]] dispatcher so synthetic TypedArray integer-index
      // descriptors count as existing.
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
        // Bag-only props (ordinary assignment, no explicit descriptor entry)
        // default to {writable: true, enumerable: true, configurable: true}
        // per §10.1.5.1 OrdinaryGetOwnProperty step 3.
        let current : PropDescriptor = match target_desc {
          Some(d) => d
          None =>
            {
              writable: true,
              enumerable: true,
              configurable: true,
              getter: None,
              setter: None,
              is_accessor: false,
            }
        }
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
          let cur_val = match target_entry {
            Some((_, value)) => value
            None => Undefined
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

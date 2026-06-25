///|
fn array_index64_from_string(prop : String) -> Int64? {
  let idx = @string.parse_int(prop) catch { _ => -1 }
  if idx >= 0 && idx.to_string() == prop {
    return Some(idx.to_int64())
  }
  try {
    let n = @string.parse_double(prop)
    let i64 = n.to_int64()
    if n >= 2147483648.0 &&
      n == i64.to_double() &&
      i64 <= 4294967294L &&
      i64.to_string() == prop {
      Some(i64)
    } else {
      None
    }
  } catch {
    _ => None
  }
}

///|
fn Interpreter::set_array_sparse_index64(
  self : Interpreter,
  data : ArrayData,
  receiver : Value,
  prop : String,
  idx64 : Int64,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value raise Error {
  let logical_len64 = match get_array_length_override(data) {
    Some(n64) => n64
    None => data.elements.length().to_int64()
  }
  match data.bag.descriptors.get(prop) {
    Some(desc) =>
      match desc.setter {
        Some(setter) => {
          let _ = self.call_value(setter, receiver, [value], loc)
          return value
        }
        None =>
          if !desc.writable {
            if strict {
              raise @errors.TypeError(
                message="Cannot assign to read only property '\{prop}'",
              )
            }
            return value
          }
      }
    None => ()
  }
  let is_own = data.bag.properties.contains(prop) ||
    data.bag.descriptors.contains(prop)
  if !is_own {
    match
      self.set_missing_array_index_via_proto_chain(
        get_array_prototype(self.realm_state, data),
        receiver,
        prop,
        value,
        loc,
        strict,
      ) {
      Some(result) => return result
      None => ()
    }
  }
  // §10.4.2.1 step 3.b: extend requires length_writable.
  if idx64 >= logical_len64 && !data.length_writable {
    if strict {
      raise @errors.TypeError(
        message="Cannot add property \{idx64}, array's length is non-writable",
      )
    }
    return value
  }
  if !is_own && !data.extensible {
    if strict {
      raise @errors.TypeError(
        message="Cannot add property \{idx64}, object is not extensible",
      )
    }
    return value
  }
  set_array_named_prop(data, prop, value)
  let new_len = idx64 + 1L
  if new_len > logical_len64 {
    set_array_length_override(data, new_len)
  }
  value
}

///|
/// Stage B.1 [[Set]] dispatcher.
///
/// `receiver` threads through the prototype chain and proxy fallbacks per
/// ES §10.1.9 (OrdinarySet) and §10.5.9 (ProxyExoticObject.[[Set]]).
///
/// - Inherited setters are invoked with `receiver` as `this`.
/// - Trap-less Proxy forwards to `target.[[Set]](P, V, Receiver)`.
/// - When no own/inherited blocker exists and `receiver !== obj`, the write
///   lands on `receiver` via `define_value_on_receiver` (approximating
///   `CreateDataProperty(Receiver, P, V)` — a direct `[[DefineOwnProperty]]`
///   that bypasses `[[Set]]`, preventing the recursion loop that a naive
///   self-call would produce for nested trap-less proxies).
pub fn Interpreter::set_property(
  self : Interpreter,
  obj : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
  strict? : Bool = false,
  receiver? : Value = obj,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) =>
      proxy_set(self, proxy_data, prop, value, receiver, strict)
    Object(data) => {
      let receiver_is_self = strict_equal(obj, receiver)
      // Ordinary object-literal own-data writes can skip the TypedArray string
      // classifier and descriptor hash when the receiver is the object itself.
      if data.class_name == "Object" &&
        receiver_is_self &&
        (
          data.bag.descriptors.is_empty() ||
          !data.bag.descriptors.contains(prop)
        ) {
        match data.bag.properties.get(prop) {
          Some(_) => {
            data.bag.properties[prop] = value
            return value
          }
          None => ()
        }
      }
      // TypedArray indexed write via dot notation (numeric string prop).
      // Receiver-sensitive per §10.4.5.5 step 1.b:
      // - canonical-invalid AND O === Receiver → ToNumber(value), then no-op
      // - canonical-invalid AND O !== Receiver → no-op without coercion
      // - canonical valid AND O === Receiver → write to buffer
      // - canonical valid AND O !== Receiver → land on Receiver (OrdinarySet)
      // The classifier raises nothing; to_number does — keep the raising
      // call outside any try/catch so Symbol → TypeError propagates per
      // §10.4.5.16 (PR #75 wide-catch fix).
      if is_typedarray_class(data.class_name) {
        match classify_typedarray_string_key(prop) {
          Some(idx) =>
            return self.typedarray_set_dispatch(
              data,
              obj,
              receiver,
              String_(prop),
              idx,
              value,
              loc,
              strict,
            )
          None => () // not a canonical numeric string — fall through
        }
      }
      if receiver_is_self &&
        (
          data.bag.descriptors.is_empty() ||
          !data.bag.descriptors.contains(prop)
        ) {
        match data.bag.properties.get(prop) {
          Some(_) => {
            data.bag.properties[prop] = value
            return value
          }
          None => ()
        }
      }
      // Check for accessor descriptor (setter)
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, receiver, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if !desc.writable {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None => {
          // Walk prototype chain for inherited setters. Per ES §10.1.9.2:
          // - Accessor getter-only / non-writable data → blocked.
          // - Inherited writable data (explicit descriptor OR implicit via
          //   bag.properties): TERMINATES the walk (step 2 data-descriptor
          //   branch lands on Receiver without consulting higher protos).
          //   Missing this short-circuit lets a higher Proxy prototype's
          //   set trap fire with unexpected side effects.
          // - Proxy on chain: delegate to its [[Set]] (§10.1.9.2 step 1.b).
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                if is_typedarray_class(proto_data.class_name) {
                  match classify_typedarray_string_key(prop) {
                    Some(idx) =>
                      return self.typedarray_set_dispatch(
                        proto_data,
                        current,
                        receiver,
                        String_(prop),
                        idx,
                        value,
                        loc,
                        strict,
                      )
                    None => ()
                  }
                }
                let mut stop_at_writable_data = false
                match proto_data.bag.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.setter {
                      Some(setter) => {
                        let _ = self.call_value(setter, receiver, [value], loc)
                        return value
                      }
                      None =>
                        if desc.getter is Some(_) {
                          if strict {
                            raise @errors.TypeError(
                              message="Cannot set property \{prop} which has only a getter",
                            )
                          }
                          return value
                        } else if !desc.writable {
                          if strict {
                            raise @errors.TypeError(
                              message="Cannot assign to read only property '\{prop}'",
                            )
                          }
                          return value
                        } else {
                          // Writable data descriptor → stop walking.
                          stop_at_writable_data = true
                        }
                    }
                  None =>
                    // No explicit descriptor — plain assignments go to
                    // bag.properties and carry an implicit writable data
                    // descriptor per spec.
                    if proto_data.bag.properties.contains(prop) {
                      stop_at_writable_data = true
                    }
                }
                if stop_at_writable_data {
                  break
                }
                current = proto_data.prototype
              }
              Proxy(_) =>
                return self.set_property(
                  current,
                  prop,
                  value,
                  loc,
                  strict~,
                  receiver~,
                )
              _ => break
            }
          }
        }
      }
      // No own / inherited blocker — land the write on `receiver` per
      // ES §10.1.9.2 step 3. When `receiver !== obj` this goes through
      // `define_value_on_receiver` (approximates `CreateDataProperty`).
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
      // Common path: receiver === obj, write locally (byte-identical to pre-B.1).
      if !data.bag.properties.contains(prop) && !data.extensible {
        if strict {
          raise @errors.TypeError(
            message="Cannot add property \{prop}, object is not extensible",
          )
        }
        return value
      }
      data.bag.properties[prop] = value
      value
    }
    Array(data) => {
      // Arrays use ordinary [[Set]] (only [[DefineOwnProperty]] is exotic per
      // §10.4.2). When `receiver !== obj` (Array), land on the receiver via
      // the helper — matches `Reflect.set(arr, "0", 1, otherObj)` semantics.
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
      if prop == "length" {
        // Ordinary [[Set]] rejects non-writable Array length even when the
        // numeric value is unchanged (push()/pop() with no length change).
        if !data.length_writable {
          if strict {
            raise @errors.TypeError(
              message="Cannot assign to read only property 'length' of array",
            )
          }
          return value
        }
        let ok = self.array_set_length(
          data,
          PartialDescriptor::value_only(value),
        )
        if !ok && strict {
          raise @errors.TypeError(message="Cannot delete property")
        }
      } else {
        // Parse numeric index OUTSIDE any try/catch so strict-mode TypeError
        // raises propagate (Codex blocker 1 fix — the previous `catch { _ =>
        // () }` was swallowing §10.4.2.1 step 3.b TypeErrors and falling
        // through to set_array_named_prop).
        // Only canonical numeric index strings (e.g. "0", "1", "42") are
        // treated as array indices. Non-canonical forms like "01", "1.0",
        // "+1" go to named properties per §10.4.2.1 / §7.1.21
        // CanonicalNumericIndexString.
        let i = @string.parse_int(prop) catch { _ => -1 }
        if i >= 0 && i.to_string() == prop {
          // Compare against logical length (override when set), not physical.
          let logical_len64 = match get_array_length_override(data) {
            Some(n64) => n64
            None => data.elements.length().to_int64()
          }
          match data.bag.descriptors.get(prop) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, receiver, [value], loc)
                  return value
                }
                None =>
                  if !desc.writable {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property '\{prop}'",
                      )
                    }
                    return value
                  }
              }
            None => ()
          }
          let is_sparse_own = data.bag.properties.contains(prop) ||
            data.bag.descriptors.contains(prop)
          let is_own = (i < data.elements.length() && !data.holes.contains(i)) ||
            is_sparse_own
          if !is_own {
            match
              self.set_missing_array_index_via_proto_chain(
                get_array_prototype(self.realm_state, data),
                receiver,
                prop,
                value,
                loc,
                strict,
              ) {
              Some(result) => return result
              None => ()
            }
          }
          // §10.4.2.1 step 3.b: extend requires length_writable.
          if i.to_int64() >= logical_len64 && !data.length_writable {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property \{i}, array's length is non-writable",
              )
            }
            return value
          }
          if !is_own && !data.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property \{i}, object is not extensible",
              )
            }
            return value
          }
          let gap = i.to_int64() - data.elements.length().to_int64()
          if gap <= 100000L {
            let prev_len = data.elements.length()
            while data.elements.length() <= i {
              data.elements.push(Undefined)
            }
            for j in prev_len..<i {
              data.holes.set(j, ())
            }
            data.holes.remove(i)
            data.elements[i] = value
            let _ = data.bag.properties.remove(prop)
          } else {
            set_array_named_prop(data, prop, value)
          }
          let new_len = i.to_int64() + 1L
          if new_len > logical_len64 &&
            new_len > data.elements.length().to_int64() {
            set_array_length_override(data, new_len)
          }
        } else {
          match array_index64_from_string(prop) {
            Some(idx64) =>
              return self.set_array_sparse_index64(
                data, receiver, prop, idx64, value, loc, strict,
              )
            None => ()
          }
          match data.bag.descriptors.get(prop) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, receiver, [value], loc)
                  return value
                }
                None =>
                  if !desc.writable {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property '\{prop}'",
                      )
                    }
                    return value
                  } else {
                    data.bag.properties[prop] = value
                    return value
                  }
              }
            None => {
              // Walk Array's prototype chain for an inherited setter/blocker.
              let proto_start = match get_array_prototype_override(data) {
                Some(p) => p
                None => {
                  let ctor = self.global.get("Array") catch { _ => Null }
                  match ctor {
                    Object(ctor_data) =>
                      match ctor_data.bag.properties.get("prototype") {
                        Some(p) => p
                        None => Null
                      }
                    _ => Null
                  }
                }
              }
              let mut current = proto_start
              let mut blocked = false
              while true {
                match current {
                  Object(proto_data) =>
                    match proto_data.bag.descriptors.get(prop) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(
                              setter,
                              receiver,
                              [value],
                              loc,
                            )
                            return value
                          }
                          None =>
                            if desc.getter is Some(_) {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot set property \{prop} which has only a getter",
                                )
                              }
                              blocked = true
                              break
                            } else if !desc.writable {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property '\{prop}'",
                                )
                              }
                              blocked = true
                              break
                            } else {
                              break // writable data: land on receiver
                            }
                        }
                      None =>
                        match proto_data.bag.properties.get(prop) {
                          Some(_) => break // writable data: land on receiver
                          None => current = proto_data.prototype
                        }
                    }
                  _ => break
                }
              }
              if !blocked {
                if !data.extensible {
                  if strict {
                    raise @errors.TypeError(
                      message="Cannot add property \{prop}, array is not extensible",
                    )
                  }
                  return value
                }
                set_array_named_prop(data, prop, value)
              }
            }
          }
        }
      }
      value
    }
    Promise(data) => {
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, receiver, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if !desc.writable {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None => ()
      }
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
      data.bag.properties[prop] = value
      value
    }
    Map(data) => {
      let mut should_walk_proto = false
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, receiver, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if !desc.writable {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None =>
          if !data.bag.properties.contains(prop) {
            should_walk_proto = true
          }
      }
      if should_walk_proto {
        match
          self.set_string_via_map_set_prototype_chain(
            data.prototype,
            receiver,
            prop,
            value,
            loc,
            strict,
          ) {
          Some(result) => return result
          None => ()
        }
      }
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
      data.bag.properties[prop] = value
      value
    }
    Set(data) => {
      let mut should_walk_proto = false
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, receiver, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if !desc.writable {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None =>
          if !data.bag.properties.contains(prop) {
            should_walk_proto = true
          }
      }
      if should_walk_proto {
        match
          self.set_string_via_map_set_prototype_chain(
            data.prototype,
            receiver,
            prop,
            value,
            loc,
            strict,
          ) {
          Some(result) => return result
          None => ()
        }
      }
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
      data.bag.properties[prop] = value
      value
    }
    Null =>
      raise @errors.TypeError(
        message="Cannot set properties of null (setting '\{prop}')",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot set properties of undefined (setting '\{prop}')",
      )
    _ =>
      // In non-strict mode, setting a property on a primitive is silently ignored
      // (the temporary wrapper object is discarded). In strict mode, throw TypeError.
      if strict {
        raise @errors.TypeError(
          message="Cannot set property '\{prop}' of \{type_of(obj)}",
        )
      } else {
        value
      }
  }
}

///|
/// Map/Set carry their own prototype slot, so string-key [[Set]] must honor
/// inherited setters and inherited blocker descriptors before creating an
/// expando property on the receiver.
fn Interpreter::set_string_via_map_set_prototype_chain(
  self : Interpreter,
  proto : Value,
  receiver : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value? raise Error {
  let mut current = proto
  while true {
    match current {
      Object(proto_data) =>
        match
          self.check_inherited_string_property_value(
            current,
            proto_data.prototype,
            receiver,
            prop,
            value,
            loc,
            strict,
          ) {
          Handled(result) => return Some(result)
          Continue(next) => current = next
          Stop => break
        }
      Array(proto_data) => {
        let next_proto = get_array_prototype_override(proto_data).unwrap_or(
          self.realm_state.get_array_proto(),
        )
        match
          self.check_inherited_string_property_value(
            current, next_proto, receiver, prop, value, loc, strict,
          ) {
          Handled(result) => return Some(result)
          Continue(next) => current = next
          Stop => break
        }
      }
      Map(proto_data) =>
        match
          self.check_inherited_string_property_value(
            current,
            proto_data.prototype,
            receiver,
            prop,
            value,
            loc,
            strict,
          ) {
          Handled(result) => return Some(result)
          Continue(next) => current = next
          Stop => break
        }
      Set(proto_data) =>
        match
          self.check_inherited_string_property_value(
            current,
            proto_data.prototype,
            receiver,
            prop,
            value,
            loc,
            strict,
          ) {
          Handled(result) => return Some(result)
          Continue(next) => current = next
          Stop => break
        }
      Promise(proto_data) =>
        match
          self.check_inherited_string_property_value(
            current,
            proto_data.prototype,
            receiver,
            prop,
            value,
            loc,
            strict,
          ) {
          Handled(result) => return Some(result)
          Continue(next) => current = next
          Stop => break
        }
      Proxy(_) =>
        return Some(
          self.set_property(current, prop, value, loc, strict~, receiver~),
        )
      _ => break
    }
  }
  None
}

///|
priv enum InheritedStringSetResult {
  Handled(Value)
  Continue(Value)
  Stop
}

///|
fn Interpreter::check_inherited_string_property_value(
  self : Interpreter,
  owner : Value,
  next_proto : Value,
  receiver : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> InheritedStringSetResult raise Error {
  match self.get_own_property(owner, String_(prop)) {
    Some((desc, _)) =>
      match desc.setter {
        Some(setter) => {
          let _ = self.call_value(setter, receiver, [value], loc)
          Handled(value)
        }
        None =>
          if desc.getter is Some(_) {
            if strict {
              raise @errors.TypeError(
                message="Cannot set property \{prop} which has only a getter",
              )
            }
            Handled(value)
          } else if !desc.writable {
            if strict {
              raise @errors.TypeError(
                message="Cannot assign to read only property '\{prop}'",
              )
            }
            Handled(value)
          } else {
            Stop
          }
      }
    None => Continue(next_proto)
  }
}

///|
fn Interpreter::set_string_on_map_set_expando(
  self : Interpreter,
  obj : Value,
  receiver : Value,
  bag : PropertyBag,
  proto : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value raise Error {
  let mut should_walk_proto = false
  match bag.descriptors.get(prop) {
    Some(desc) =>
      match desc.setter {
        Some(setter) => {
          let _ = self.call_value(setter, receiver, [value], loc)
          return value
        }
        None =>
          if desc.getter is Some(_) {
            if strict {
              raise @errors.TypeError(
                message="Cannot set property \{prop} which has only a getter",
              )
            }
            return value
          } else if !desc.writable {
            if strict {
              raise @errors.TypeError(
                message="Cannot assign to read only property '\{prop}'",
              )
            }
            return value
          }
      }
    None => if !bag.properties.contains(prop) { should_walk_proto = true }
  }
  if should_walk_proto {
    match
      self.set_string_via_map_set_prototype_chain(
        proto, receiver, prop, value, loc, strict,
      ) {
      Some(result) => return result
      None => ()
    }
  }
  if !strict_equal(obj, receiver) {
    return self.define_value_on_receiver(
      receiver,
      String_(prop),
      value,
      loc,
      strict,
    )
  }
  bag.properties[prop] = value
  value
}

///|
/// Helper predicate for §10.1.9.2 step 3.e: an existing receiver-side
/// descriptor blocks the landing write if it is an accessor descriptor
/// (getter or setter present) or a non-writable data descriptor. Writable
/// data descriptors do NOT block (the write lands as { [[Value]]: V }).
fn existing_receiver_desc_blocks(desc : PropDescriptor) -> Bool {
  desc.getter is Some(_) ||
  desc.setter is Some(_) ||
  (desc.getter is None && desc.setter is None && !desc.writable)
}

///|
/// ES §10.1.9.2 step 3 landing via [[DefineOwnProperty]]. Looks up the
/// existing own descriptor on receiver (honoring Proxy `getOwnPropertyDescriptor`
/// trap), then dispatches:
/// - existing is accessor / non-writable data -> blocker (strict throws,
///   sloppy returns `value` silently).
/// - existing is writable data -> call [[DefineOwnProperty]] with value-only
///   (§10.1.9.2 step 3.e). Preserves existing enumerable/configurable.
/// - no existing -> call [[DefineOwnProperty]] with CreateDataProperty shape
///   (§10.1.9.2 step 3.f).
/// If [[DefineOwnProperty]] returns false: strict throws, sloppy returns value.
fn Interpreter::landing_via_define_own_property(
  self : Interpreter,
  receiver : Value,
  key : Value,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value raise Error {
  // Look up existing own descriptor on receiver.
  let existing = self.get_own_property(receiver, key)
  match existing {
    Some((desc, _)) if existing_receiver_desc_blocks(desc) => {
      if strict {
        let key_display = match key {
          Symbol(sym) => "Symbol(\{sym.description.unwrap_or_default()})"
          _ => to_js_string(key, interp=Some(self))
        }
        raise @errors.TypeError(
          message="Cannot redefine non-writable or accessor property '\{key_display}' on receiver",
        )
      }
      return value
    }
    _ => ()
  }
  // Choose partial shape per step 3.e vs 3.f.
  let partial = match existing {
    Some(_) => PartialDescriptor::value_only(value) // step 3.e
    None => PartialDescriptor::data_default(value) // step 3.f
  }
  let ok = self.define_own_property(receiver, key, partial, loc)
  if !ok {
    if strict {
      let key_display = match key {
        Symbol(sym) => "Symbol(\{sym.description.unwrap_or_default()})"
        _ => to_js_string(key, interp=Some(self))
      }
      raise @errors.TypeError(
        message="Cannot assign to property '\{key_display}' on receiver",
      )
    }
  }
  value
}

///|
/// §10.4.5.5 step 1.b TypedArray `[[Set]]` dispatch for a canonical-numeric
/// index whose classifier already returned `Some(idx)` (`idx == -1` means a
/// canonical numeric string that is not a valid integer-index form).
/// Called from the three TypedArray intercept sites (`set_property` string
/// path, `set_computed_property` `Number` and `String_` paths) to centralize
/// the same-receiver, invalid-index, and cross-receiver landing cases.
///
/// - `O === Receiver` → `TypedArraySetElement`: coerce `value`, then write to
///   the buffer only when `idx` is a valid in-range integer index.
/// - `O !== Receiver` AND `!IsValidIntegerIndex` → no-op per step 1.b.ii,
///   without coercing `value`.
/// - `O !== Receiver` AND in-range → `OrdinarySet` on `Receiver` (lands via
///   `Receiver.[[DefineOwnProperty]]`; the TypedArray's backing buffer is untouched).
///
/// The `to_number(value)` raise must remain outside the classifier's
/// try/catch: Symbol → TypeError must propagate per §10.4.5.16 (the PR #75
/// wide-catch fix).
fn Interpreter::typedarray_set_dispatch(
  self : Interpreter,
  data : ObjectData,
  obj : Value,
  receiver : Value,
  key : Value,
  idx : Int,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value raise Error {
  if strict_equal(obj, receiver) {
    let num = self.to_number(value)
    if idx >= 0 {
      (self.stdlib_hooks.typedarray_set_index)(data, idx, num, self.realm_state)
    }
    value
  } else if idx < 0 ||
    !(self.stdlib_hooks.typedarray_is_valid_index)(data, idx, self.realm_state) {
    value
  } else {
    let landing_key = match key {
      String_(_) => key
      _ => String_(to_js_string(key, interp=Some(self)))
    }
    self.define_value_on_receiver(receiver, landing_key, value, loc, strict)
  }
}

///|
/// Array uses ordinary [[Set]], so a missing array index delegates through the
/// full prototype chain before Array [[DefineOwnProperty]] can extend length.
/// This keeps TypedArray integer-index semantics observable even behind
/// intermediate ordinary prototypes, while preserving ordinary prototype
/// blockers (setters, getter-only accessors, and non-writable data props).
fn Interpreter::set_missing_array_index_via_proto_chain(
  self : Interpreter,
  proto : Value,
  receiver : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value? raise Error {
  let mut current = proto
  while true {
    match current {
      Object(proto_data) => {
        if is_typedarray_class(proto_data.class_name) {
          match classify_typedarray_string_key(prop) {
            Some(idx) =>
              return Some(
                self.typedarray_set_dispatch(
                  proto_data,
                  current,
                  receiver,
                  String_(prop),
                  idx,
                  value,
                  loc,
                  strict,
                ),
              )
            None => ()
          }
        }
        match proto_data.bag.descriptors.get(prop) {
          Some(desc) =>
            match desc.setter {
              Some(setter) => {
                let _ = self.call_value(setter, receiver, [value], loc)
                return Some(value)
              }
              None =>
                if desc.getter is Some(_) {
                  if strict {
                    raise @errors.TypeError(
                      message="Cannot set property \{prop} which has only a getter",
                    )
                  }
                  return Some(value)
                } else if !desc.writable {
                  if strict {
                    raise @errors.TypeError(
                      message="Cannot assign to read only property '\{prop}'",
                    )
                  }
                  return Some(value)
                } else {
                  return Some(
                    self.define_value_on_receiver(
                      receiver,
                      String_(prop),
                      value,
                      loc,
                      strict,
                    ),
                  )
                }
            }
          None =>
            if proto_data.bag.properties.contains(prop) {
              return Some(
                self.define_value_on_receiver(
                  receiver,
                  String_(prop),
                  value,
                  loc,
                  strict,
                ),
              )
            }
        }
        current = proto_data.prototype
      }
      Proxy(_) =>
        return Some(
          self.set_property(current, prop, value, loc, strict~, receiver~),
        )
      _ => return None
    }
  }
  None
}

///|
/// Approximates ES `CreateDataProperty(Receiver, P, V)` / `Receiver.[[Define\
/// OwnProperty]]` for the [[Set]] landing rule. This is NOT `[[Set]]` — it
/// must not invoke setters on `receiver`'s prototype chain, otherwise a
/// trap-less proxy chain would infinite-loop (per Codex's design review).
///
/// Implements §10.1.9.2 step 3.e as of the receiver-blocker fix: if receiver
/// has an existing own descriptor at `key`, accessor or non-writable data
/// blocks the landing (sloppy returns `value`, strict raises TypeError).
///
/// The Object and Array branches now route through
/// `landing_via_define_own_property` (the Stage B.2 [[DefineOwnProperty]]
/// dispatcher). Other receivers (Map/Set/Promise/Null/primitives) still have
/// inline approximations here. A full dispatcher migration for all receiver
/// kinds is a Stage B.3+ follow-up.
fn Interpreter::define_value_on_receiver(
  self : Interpreter,
  receiver : Value,
  key : Value,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value raise Error {
  match receiver {
    // §10.1.9.2 step 3: look up receiver's own descriptor; dispatch per
    // 3.e (existing writable-data) or 3.f (absent → CreateDataProperty).
    // Proxy receivers route through proxy_get_own_property +
    // proxy_define_property so the getOwnPropertyDescriptor and
    // defineProperty traps fire.
    Proxy(_) =>
      self.landing_via_define_own_property(receiver, key, value, loc, strict)
    Object(rdata) => {
      if is_typedarray_class(rdata.class_name) {
        return self.landing_via_define_own_property(
          receiver, key, value, loc, strict,
        )
      }
      match key {
        Symbol(sym) => {
          // §10.1.9.2 step 3.e: existing own descriptor blocker check.
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          if !rdata.bag.symbol_properties.contains(sym.id) && !rdata.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property, object is not extensible",
              )
            }
            return value
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key, interp=Some(self))
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          if !rdata.bag.properties.contains(prop) && !rdata.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property \{prop}, object is not extensible",
              )
            }
            return value
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    }
    Promise(rdata) =>
      match key {
        Symbol(sym) => {
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key, interp=Some(self))
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    // Map / Set receivers carry an expando bag for instance fields from
    // subclasses (e.g. `class D extends Map { constructor() { super(); this.x = 1 } }`)
    // — the landing helper must write there rather than hitting the primitive
    // fall-through. Descriptor-blocker check mirrors the Object arm.
    Map(rdata) =>
      match key {
        Symbol(sym) => {
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key, interp=Some(self))
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    Set(rdata) =>
      match key {
        Symbol(sym) => {
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key, interp=Some(self))
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    // §10.1.9.2 step 3 via [[DefineOwnProperty]] (§10.4.2.1 / §10.4.2.4 for
    // Array): existing writable `length` → `ArraySetLength` with just {Value};
    // absent index → `CreateDataProperty` with full defaults;
    // `length_writable: false` rejection honored. Routes through the Stage B.2
    // `landing_via_define_own_property` dispatcher rather than re-firing
    // Array's `[[Set]]` exotic path (which would be the wrong operation per
    // §10.5.9 step 5.b — landing must be `[[DefineOwnProperty]]`, not `[[Set]]`).
    Array(_) =>
      self.landing_via_define_own_property(receiver, key, value, loc, strict)
    // Null/Undefined/primitive receiver: per spec returns false. In strict
    // mode our dispatcher surface raises TypeError; in sloppy mode return
    // `value` to match existing set_property primitive handling.
    Null =>
      if strict {
        raise @errors.TypeError(message="Cannot set property on null receiver")
      } else {
        value
      }
    Undefined =>
      if strict {
        raise @errors.TypeError(
          message="Cannot set property on undefined receiver",
        )
      } else {
        value
      }
    _ =>
      if strict {
        raise @errors.TypeError(
          message="Cannot set property on primitive receiver",
        )
      } else {
        value
      }
  }
}

///|
pub fn Interpreter::set_computed_property(
  self : Interpreter,
  obj : Value,
  key : Value,
  value : Value,
  loc : @token.Loc,
  strict? : Bool = false,
  receiver? : Value = obj,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) => {
      let trap = get_proxy_trap(proxy_data, "set", self)
      match trap {
        Some(trap_fn) => {
          let target = get_proxy_target(proxy_data)
          let handler = get_proxy_handler(proxy_data)
          let prop_key = match key {
            Symbol(_) => key
            _ => String_(to_js_string(key, interp=Some(self)))
          }
          let result = self.call_value(
            trap_fn,
            handler,
            [target, prop_key, value, receiver],
            loc,
          )
          if !is_truthy(result) {
            if strict {
              raise @errors.TypeError(
                message="'set' on proxy: trap returned falsish",
              )
            }
            return value
          }
          // ES §10.5.9 step 11-12 invariants. Same checks proxy_set runs for
          // the string-key path; must run here so `p[k] = v` and the proto-
          // chain delegation (Proxy(_) arm of the walk) match spec.
          check_proxy_set_trap_invariants_with_interp(
            Some(self),
            target,
            prop_key,
            value,
          )
          return value
        }
        None => {
          // Trap-less fallback: target.[[Set]](P, V, Receiver) — thread
          // receiver through per ES §10.5.9 step 5.
          let target = get_proxy_target(proxy_data)
          return self.set_computed_property(
            target,
            key,
            value,
            loc,
            strict~,
            receiver~,
          )
        }
      }
    }
    Object(data) =>
      match key {
        Symbol(sym) => {
          // Check symbol property accessor descriptor (setter)
          match data.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, receiver, [value], loc)
                  return value
                }
                None =>
                  if desc.getter is Some(_) {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot set property which has only a getter",
                      )
                    }
                    return value
                  } else if !desc.writable {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property",
                      )
                    }
                    return value
                  }
              }
            None => {
              // Walk prototype chain for inherited symbol setters. Writable
              // data on a proto (explicit or implicit via symbol_properties)
              // terminates the walk per §10.1.9.2; see string-key branch for
              // full rationale.
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    let mut stop_at_writable_data = false
                    match proto_data.bag.symbol_descriptors.get(sym.id) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(
                              setter,
                              receiver,
                              [value],
                              loc,
                            )
                            return value
                          }
                          None =>
                            if desc.getter is Some(_) {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot set property which has only a getter",
                                )
                              }
                              return value
                            } else if !desc.writable {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property",
                                )
                              }
                              return value
                            } else {
                              stop_at_writable_data = true
                            }
                        }
                      None =>
                        if proto_data.bag.symbol_properties.contains(sym.id) {
                          stop_at_writable_data = true
                        }
                    }
                    if stop_at_writable_data {
                      break
                    }
                    current = proto_data.prototype
                  }
                  Proxy(_) =>
                    return self.set_computed_property(
                      current,
                      key,
                      value,
                      loc,
                      strict~,
                      receiver~,
                    )
                  _ => break
                }
              }
            }
          }
          // Landing rule: if receiver differs, write lands on receiver.
          if !strict_equal(obj, receiver) {
            return self.define_value_on_receiver(
              receiver, key, value, loc, strict,
            )
          }
          if !data.bag.symbol_properties.contains(sym.id) && !data.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property, object is not extensible",
              )
            }
            return value
          }
          data.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          // TypedArray indexed write: intercept numeric keys per
          // §10.4.5.5 [[Set]] (receiver-sensitive) + §10.4.5.16
          // IntegerIndexedElementSet.
          //
          // Per §10.4.5.5 step 1.b:
          // - If P is canonical numeric AND SameValue(O, Receiver):
          //   IntegerIndexedElementSet — write to buffer (or no-op if
          //   IsValidIntegerIndex is false).
          // - If P is canonical numeric AND O !== Receiver AND not a
          //   valid index: return true (no-op, do NOT land on receiver).
          // - If P is canonical numeric AND O !== Receiver AND valid
          //   index: fall through to OrdinarySet on Receiver (lands as
          //   ordinary data property on the receiver, NOT in O's buffer).
          if is_typedarray_class(data.class_name) {
            match key {
              Number(n) => {
                let idx = n.to_int()
                if !(idx.to_double() == n && idx >= 0) {
                  // Canonical numeric (Number always is) but not a valid
                  // integer-index form. Same-receiver writes still perform
                  // ToNumber(value); cross-receiver writes are no-ops.
                  return self.typedarray_set_dispatch(
                    data, obj, receiver, key, -1, value, loc, strict,
                  )
                }
                return self.typedarray_set_dispatch(
                  data, obj, receiver, key, idx, value, loc, strict,
                )
              }
              String_(s) =>
                match classify_typedarray_string_key(s) {
                  Some(idx) =>
                    return self.typedarray_set_dispatch(
                      data, obj, receiver, key, idx, value, loc, strict,
                    )
                  None => () // not canonical numeric → fall through
                }
              _ => ()
            }
          }
          let prop = to_js_string(key, interp=Some(self))
          // Check for accessor descriptor (setter) on string key
          match data.bag.descriptors.get(prop) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, receiver, [value], loc)
                  return value
                }
                None =>
                  if desc.getter is Some(_) {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot set property \{prop} which has only a getter",
                      )
                    }
                    return value
                  } else if !desc.writable {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property '\{prop}'",
                      )
                    }
                    return value
                  }
              }
            None => {
              // Walk prototype chain for inherited setters. Writable data on
              // a proto (explicit or implicit via bag.properties) terminates
              // the walk per §10.1.9.2; see set_property for full rationale.
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    if is_typedarray_class(proto_data.class_name) {
                      match classify_typedarray_string_key(prop) {
                        Some(idx) =>
                          return self.typedarray_set_dispatch(
                            proto_data,
                            current,
                            receiver,
                            String_(prop),
                            idx,
                            value,
                            loc,
                            strict,
                          )
                        None => ()
                      }
                    }
                    let mut stop_at_writable_data = false
                    match proto_data.bag.descriptors.get(prop) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(
                              setter,
                              receiver,
                              [value],
                              loc,
                            )
                            return value
                          }
                          None =>
                            if desc.getter is Some(_) {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot set property \{prop} which has only a getter",
                                )
                              }
                              return value
                            } else if !desc.writable {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property '\{prop}'",
                                )
                              }
                              return value
                            } else {
                              stop_at_writable_data = true
                            }
                        }
                      None =>
                        if proto_data.bag.properties.contains(prop) {
                          stop_at_writable_data = true
                        }
                    }
                    if stop_at_writable_data {
                      break
                    }
                    current = proto_data.prototype
                  }
                  Proxy(_) =>
                    return self.set_computed_property(
                      current,
                      key,
                      value,
                      loc,
                      strict~,
                      receiver~,
                    )
                  _ => break
                }
              }
            }
          }
          // Landing rule: if receiver differs, write lands on receiver.
          if !strict_equal(obj, receiver) {
            return self.define_value_on_receiver(
              receiver,
              String_(prop),
              value,
              loc,
              strict,
            )
          }
          if !data.bag.properties.contains(prop) && !data.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property \{prop}, object is not extensible",
              )
            }
            return value
          }
          data.bag.properties[prop] = value
          value
        }
      }
    Map(data) =>
      match key {
        Symbol(sym) => {
          if !strict_equal(obj, receiver) {
            return self.define_value_on_receiver(
              receiver, key, value, loc, strict,
            )
          }
          data.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key, interp=Some(self))
          self.set_string_on_map_set_expando(
            obj,
            receiver,
            data.bag,
            data.prototype,
            prop,
            value,
            loc,
            strict,
          )
        }
      }
    Set(data) =>
      match key {
        Symbol(sym) => {
          if !strict_equal(obj, receiver) {
            return self.define_value_on_receiver(
              receiver, key, value, loc, strict,
            )
          }
          data.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key, interp=Some(self))
          self.set_string_on_map_set_expando(
            obj,
            receiver,
            data.bag,
            data.prototype,
            prop,
            value,
            loc,
            strict,
          )
        }
      }
    Array(data) => {
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(receiver, key, value, loc, strict)
      }
      match key {
        Symbol(sym) => {
          set_array_symbol_prop(data, sym.id, value)
          value
        }
        Number(n) => {
          let prop64 = n.to_string()
          match array_index64_from_string(prop64) {
            Some(idx64) if idx64 > 0x7FFFFFFFL =>
              return self.set_array_sparse_index64(
                data, receiver, prop64, idx64, value, loc, strict,
              )
            _ => ()
          }
          let i = n.to_int()
          // Only treat as array index if n is an exact, non-negative integer.
          // Non-integer keys like 1.1 must be stored as named properties.
          if i >= 0 && i.to_double() == n {
            let prop = i.to_string()
            let logical_len64 = match get_array_length_override(data) {
              Some(n64) => n64
              None => data.elements.length().to_int64()
            }
            match data.bag.descriptors.get(prop) {
              Some(desc) =>
                match desc.setter {
                  Some(setter) => {
                    let _ = self.call_value(setter, receiver, [value], loc)
                    return value
                  }
                  None =>
                    if !desc.writable {
                      if strict {
                        raise @errors.TypeError(
                          message="Cannot assign to read only property '\{prop}'",
                        )
                      }
                      return value
                    }
                }
              None => ()
            }
            let is_sparse_own = data.bag.properties.contains(prop) ||
              data.bag.descriptors.contains(prop)
            let is_own = (i < data.elements.length() && !data.holes.contains(i)) ||
              is_sparse_own
            if !is_own {
              match
                self.set_missing_array_index_via_proto_chain(
                  get_array_prototype(self.realm_state, data),
                  receiver,
                  prop,
                  value,
                  loc,
                  strict,
                ) {
                Some(result) => return result
                None => ()
              }
            }
            // §10.4.2.1 step 3.b: extending beyond length requires length to be writable.
            if i.to_int64() >= logical_len64 && !data.length_writable {
              if strict {
                raise @errors.TypeError(
                  message="Cannot add property \{i}, array's length is non-writable",
                )
              }
              return value
            }
            if !is_own && !data.extensible {
              if strict {
                raise @errors.TypeError(
                  message="Cannot add property \{i}, object is not extensible",
                )
              }
              return value
            }
            let gap = i.to_int64() - data.elements.length().to_int64()
            if gap <= 100000L {
              let prev_len = data.elements.length()
              while data.elements.length() <= i {
                data.elements.push(Undefined)
              }
              for j in prev_len..<i {
                data.holes.set(j, ())
              }
              data.holes.remove(i)
              data.elements[i] = value
              let _ = data.bag.properties.remove(prop)
            } else {
              set_array_named_prop(data, prop, value)
            }
            let new_len = i.to_int64() + 1L
            if new_len > logical_len64 &&
              new_len > data.elements.length().to_int64() {
              set_array_length_override(data, new_len)
            }
          } else {
            // Non-integer numeric key (e.g., 1.1, -0.5): delegate to set_property
            // to enforce descriptor, extensibility, and prototype-chain checks.
            return self.set_property(obj, prop64, value, loc, strict~)
          }
          value
        }
        _ => {
          let prop = to_js_string(key, interp=Some(self))
          if prop == "length" {
            // Ordinary [[Set]] rejects non-writable Array length even when the
            // numeric value is unchanged (push()/pop() with no length change).
            if !data.length_writable {
              if strict {
                raise @errors.TypeError(
                  message="Cannot assign to read only property 'length' of array",
                )
              }
              return value
            }
            let ok = self.array_set_length(
              data,
              PartialDescriptor::value_only(value),
            )
            if !ok && strict {
              raise @errors.TypeError(message="Cannot delete property")
            }
          } else {
            // Canonical numeric index string check: parseDouble(s).toString() === s
            // Parse OUTSIDE try/catch so strict TypeErrors propagate.
            let maybe_n : Double? = Some(@string.parse_double(prop)) catch {
              _ => None
            }
            let mut handled = false
            match array_index64_from_string(prop) {
              Some(idx64) if idx64 > 0x7FFFFFFFL =>
                return self.set_array_sparse_index64(
                  data, receiver, prop, idx64, value, loc, strict,
                )
              _ => ()
            }
            match maybe_n {
              Some(n) =>
                if n.to_string() == prop {
                  let idx = n.to_int()
                  if idx.to_double() == n && idx >= 0 {
                    let logical_len64 = match get_array_length_override(data) {
                      Some(n64) => n64
                      None => data.elements.length().to_int64()
                    }
                    match data.bag.descriptors.get(prop) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(
                              setter,
                              receiver,
                              [value],
                              loc,
                            )
                            return value
                          }
                          None =>
                            if !desc.writable {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property '\{prop}'",
                                )
                              }
                              return value
                            }
                        }
                      None => ()
                    }
                    let is_sparse_own = data.bag.properties.contains(prop) ||
                      data.bag.descriptors.contains(prop)
                    let is_own = (
                        idx < data.elements.length() &&
                        !data.holes.contains(idx)
                      ) ||
                      is_sparse_own
                    if !is_own {
                      match
                        self.set_missing_array_index_via_proto_chain(
                          get_array_prototype(self.realm_state, data),
                          receiver,
                          prop,
                          value,
                          loc,
                          strict,
                        ) {
                        Some(result) => return result
                        None => ()
                      }
                    }
                    // §10.4.2.1 step 3.b: extend requires writable length.
                    if idx.to_int64() >= logical_len64 && !data.length_writable {
                      if strict {
                        raise @errors.TypeError(
                          message="Cannot add property \{idx}, array's length is non-writable",
                        )
                      }
                      return value
                    }
                    if !is_own && !data.extensible {
                      if strict {
                        raise @errors.TypeError(
                          message="Cannot add property \{idx}, object is not extensible",
                        )
                      }
                      return value
                    }
                    let gap = idx.to_int64() - data.elements.length().to_int64()
                    if gap <= 100000L {
                      let prev_len = data.elements.length()
                      while data.elements.length() <= idx {
                        data.elements.push(Undefined)
                      }
                      for j in prev_len..<idx {
                        data.holes.set(j, ())
                      }
                      data.holes.remove(idx)
                      data.elements[idx] = value
                      let _ = data.bag.properties.remove(prop)
                    } else {
                      set_array_named_prop(data, prop, value)
                    }
                    let new_len = idx.to_int64() + 1L
                    if new_len > logical_len64 &&
                      new_len > data.elements.length().to_int64() {
                      set_array_length_override(data, new_len)
                    }
                    handled = true
                  }
                }
              None => ()
            }
            if !handled {
              match data.bag.descriptors.get(prop) {
                Some(desc) =>
                  match desc.setter {
                    Some(setter) => {
                      let _ = self.call_value(setter, receiver, [value], loc)
                      return value
                    }
                    None =>
                      if !desc.writable {
                        if strict {
                          raise @errors.TypeError(
                            message="Cannot assign to read only property '\{prop}'",
                          )
                        }
                        return value
                      }
                  }
                None => ()
              }
              if !data.extensible {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot add property '\{prop}' on a non-extensible object",
                  )
                }
                return value
              }
              set_array_named_prop(data, prop, value)
            }
          }
          value
        }
      }
    }
    Promise(data) => {
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(receiver, key, value, loc, strict)
      }
      match key {
        Symbol(sym) => {
          data.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.bag.properties[to_js_string(key, interp=Some(self))] = value
          value
        }
      }
    }
    Null => {
      let key_str = match key {
        Symbol(sym) =>
          match sym.description {
            Some(d) => "Symbol(\{d})"
            None => "Symbol()"
          }
        String_(s) => s
        Number(n) => n.to_string()
        Bool(b) => b.to_string()
        _ => ""
      }
      raise @errors.TypeError(
        message="Cannot set properties of null (setting '\{key_str}')",
      )
    }
    Undefined => {
      let key_str = match key {
        Symbol(sym) =>
          match sym.description {
            Some(d) => "Symbol(\{d})"
            None => "Symbol()"
          }
        String_(s) => s
        Number(n) => n.to_string()
        Bool(b) => b.to_string()
        _ => ""
      }
      raise @errors.TypeError(
        message="Cannot set properties of undefined (setting '\{key_str}')",
      )
    }
    _ =>
      if strict {
        raise @errors.TypeError(
          message="Cannot set property of \{type_of(obj)}",
        )
      } else {
        value
      }
  }
}

///|
pub fn Interpreter::get_console_member(
  self : Interpreter,
  prop : String,
) -> Value raise Error {
  if prop == "log" {
    let output = self.host.output
    make_native_func(name="log", realm_state=Some(self.realm_state), fn(args) {
      let parts : Array[String] = args.map(fn(a) { a.to_string() })
      output.push(parts.join(" "))
      Undefined
    })
  } else {
    raise @errors.TypeError(message="console.\{prop} is not supported")
  }
}

///|
fn Interpreter::eval_member(
  self : Interpreter,
  ctx : ExecContext,
  obj_expr : @ast.Expr,
  prop : String,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Special case: console.log
  match obj_expr {
    Ident("console", _) => self.get_console_member(prop)
    _ => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      self.get_property(obj, prop, loc)
    }
  }
}

///|
pub fn get_bound_func_name(target : Value) -> String {
  match target {
    Object(td) => {
      // First check properties["name"] (set by Object.defineProperty or bind)
      let prop_name = match td.bag.properties.get("name") {
        Some(String_(s)) => s
        _ => ""
      }
      if prop_name != "" {
        return "bound " + prop_name
      }
      match td.callable {
        Some(UserFunc(fd)) => "bound " + fd.name.unwrap_or("")
        Some(UserFuncExt(fd)) => "bound " + fd.name.unwrap_or("")
        Some(NativeCallable(n, _)) | Some(NativeCallableWithContext(n, _)) =>
          "bound " + n
        Some(NonConstructableCallable(n, _)) => "bound " + n
        Some(BoundFunc(inner, _, _)) => "bound " + get_bound_func_name(inner)
        Some(ArrowFunc(fd)) => "bound " + fd.name.unwrap_or("")
        Some(ArrowFuncExt(fd)) => "bound " + fd.name.unwrap_or("")
        Some(ClassConstructor({ name: n, .. })) => "bound " + n
        Some(MethodCallable(n, _)) => "bound " + n
        Some(InterpreterCallable(n, _))
        | Some(InterpreterCallableWithContext(n, _)) => "bound " + n
        Some(NonConstructableInterpreterCallable(n, _)) => "bound " + n
        Some(_) => "bound "
        None => "bound "
      }
    }
    _ => "bound "
  }
}

///|
pub fn get_func_length(callable : Callable) -> Int {
  match callable {
    UserFunc(func_data) => func_data.params.length()
    UserFuncExt(func_data) => {
      let mut len = 0
      for p in func_data.params {
        if p.default_val is Some(_) {
          break
        }
        len += 1
      }
      len
    }
    ArrowFunc(func_data) => func_data.params.length()
    ArrowFuncExt(func_data) => {
      let mut len = 0
      for p in func_data.params {
        if p.default_val is Some(_) {
          break
        }
        len += 1
      }
      len
    }
    BoundFunc(target, _, bound_args) => {
      let target_len = get_function_length(target)
      let diff = target_len - bound_args.length()
      if diff < 0 {
        0
      } else {
        diff
      }
    }
    NativeCallable(_, _) => 0
    NativeCallableWithContext(_, _) => 0
    NonConstructableCallable(_, _) => 0
    FuncCallMethod(_) => 1
    FuncApplyMethod(_) => 2
    MethodCallable(_, _) => 0
    InterpreterCallable(_, _) => 0
    InterpreterCallableWithContext(_, _) => 0
    NonConstructableInterpreterCallable(_, _) => 0
    ConstructorOnlyCallable(_, _) => 0
    ClassConstructor({ ctor_fn, .. }) =>
      match ctor_fn {
        Some((params, _, _)) => params.length()
        None => 0
      }
  }
}

///|
/// Return the observable function length used by Function.prototype.bind.
/// Prefer an own numeric `length` property, falling back to callable metadata
/// for older function objects that synthesize length from their Callable tag.
pub fn get_function_length(target : Value) -> Int {
  match target {
    Object(data) =>
      match data.bag.properties.get("length") {
        Some(Number(n)) => if n <= 0.0 { 0 } else { n.to_int() }
        _ =>
          match data.callable {
            Some(callable) => get_func_length(callable)
            None => 0
          }
      }
    _ => 0
  }
}

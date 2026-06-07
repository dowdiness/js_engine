///|
/// Factory functions for Object integrity and utility static methods.
///
/// Each function returns a Value (a JS function object) for use as a static
/// method on the Object constructor.  None of these closures capture variables
/// from the outer setup_object_builtins scope — they operate entirely on their
/// lambda parameters and package-level helpers.

///|
fn frozen_descriptor(existing : PropDescriptor?) -> PropDescriptor {
  {
    writable: false,
    enumerable: match existing {
      Some(d) => d.enumerable
      None => true
    },
    configurable: false,
    getter: match existing {
      Some(d) => d.getter
      None => None
    },
    setter: match existing {
      Some(d) => d.setter
      None => None
    },
    is_accessor: match existing {
      Some(d) => d.is_accessor
      None => false
    },
  }
}

///|
fn freeze_string_properties(bag : @runtime.PropertyBag) -> Unit {
  let keys : Array[String] = []
  bag.properties.each(fn(k, _v) { keys.push(k) })
  bag.descriptors.each(fn(k, _desc) {
    if !bag.properties.contains(k) {
      keys.push(k)
    }
  })
  for key in keys {
    bag.descriptors[key] = frozen_descriptor(bag.descriptors.get(key))
  }
}

///|
fn freeze_symbol_properties(bag : @runtime.PropertyBag) -> Unit {
  let sym_ids : Array[Int] = []
  bag.symbol_properties.each(fn(id, _v) { sym_ids.push(id) })
  for id in sym_ids {
    bag.symbol_descriptors[id] = frozen_descriptor(
      bag.symbol_descriptors.get(id),
    )
  }
}

///|
fn freeze_array_index_properties(data : ArrayData) -> Unit {
  for i in 0..<data.elements.length() {
    if !data.holes.contains(i) {
      let key = i.to_string()
      data.bag.descriptors[key] = frozen_descriptor(
        data.bag.descriptors.get(key),
      )
    }
  }
}

///|
fn make_freeze_func() -> Value {
  @runtime.make_native_func(name="freeze", length=1, fn(args) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        if data.class_name == "Module" {
          let mut has_string_export = false
          data.bag.properties.each(fn(_, _) { has_string_export = true })
          if has_string_export {
            raise @errors.TypeError(
              message="Cannot freeze module namespace object",
            )
          }
        }
        data.extensible = false
        freeze_string_properties(data.bag)
        freeze_symbol_properties(data.bag)
        obj
      }
      Array(data) => {
        data.extensible = false
        data.length_writable = false
        freeze_array_index_properties(data)
        freeze_string_properties(data.bag)
        freeze_symbol_properties(data.bag)
        obj
      }
      _ => obj
    }
  })
}

///|
fn make_seal_func() -> Value {
  @runtime.make_native_func(name="seal", length=1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        data.extensible = false
        // Seal string properties
        let keys : Array[String] = []
        data.bag.properties.each(fn(k, _v) { keys.push(k) })
        for key in keys {
          let existing = data.bag.descriptors.get(key)
          data.bag.descriptors[key] = {
            writable: match existing {
              Some(d) => d.writable
              None => true
            },
            enumerable: match existing {
              Some(d) => d.enumerable
              None => true
            },
            configurable: false,
            getter: match existing {
              Some(d) => d.getter
              None => None
            },
            setter: match existing {
              Some(d) => d.setter
              None => None
            },
            is_accessor: match existing {
              Some(d) => d.is_accessor
              None => false
            },
          }
        }
        // Seal symbol properties
        let sym_ids : Array[Int] = []
        data.bag.symbol_properties.each(fn(id, _v) { sym_ids.push(id) })
        for id in sym_ids {
          let existing = data.bag.symbol_descriptors.get(id)
          data.bag.symbol_descriptors[id] = {
            writable: match existing {
              Some(d) => d.writable
              None => true
            },
            enumerable: match existing {
              Some(d) => d.enumerable
              None => true
            },
            configurable: false,
            getter: match existing {
              Some(d) => d.getter
              None => None
            },
            setter: match existing {
              Some(d) => d.setter
              None => None
            },
            is_accessor: match existing {
              Some(d) => d.is_accessor
              None => false
            },
          }
        }
        obj
      }
      _ => obj
    }
  })
}

///|
fn make_prevent_extensions_func() -> Value {
  @runtime.make_interp_static_func(name="preventExtensions", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Value::Proxy(proxy_data) => {
        let _ = @runtime.proxy_prevent_extensions(interp, proxy_data)
        obj
      }
      Object(data) => {
        data.extensible = false
        obj
      }
      Array(data) => {
        data.extensible = false
        obj
      }
      _ => obj
    }
  })
}

///|
fn make_is_frozen_func() -> Value {
  @runtime.make_native_func(name="isFrozen", length=1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        if data.extensible {
          return Value::Bool(false)
        }
        if data.class_name == "Module" {
          let mut has_string_export = false
          data.bag.properties.each(fn(_, _) { has_string_export = true })
          if has_string_export {
            return Value::Bool(false)
          }
        }
        let mut frozen = true
        data.bag.properties.each(fn(k, _v) {
          match data.bag.descriptors.get(k) {
            Some(d) => if d.writable || d.configurable { frozen = false }
            None => frozen = false // No descriptor = writable+configurable
          }
        })
        Bool(frozen)
      }
      _ => Value::Bool(true) // Non-objects are vacuously frozen
    }
  })
}

///|
fn make_is_sealed_func() -> Value {
  @runtime.make_native_func(name="isSealed", length=1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        if data.extensible {
          return Value::Bool(false)
        }
        let mut is_sealed = true
        data.bag.properties.each(fn(k, _v) {
          match data.bag.descriptors.get(k) {
            Some(d) => if d.configurable { is_sealed = false }
            None => is_sealed = false
          }
        })
        Bool(is_sealed)
      }
      _ => Value::Bool(true)
    }
  })
}

///|
fn make_is_extensible_func() -> Value {
  @runtime.make_interp_static_func(name="isExtensible", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => Bool(data.extensible)
      Array(data) => Bool(data.extensible)
      Value::Proxy(proxy_data) =>
        Bool(@runtime.proxy_is_extensible(interp, proxy_data))
      _ => Value::Bool(false)
    }
  })
}

///|
fn make_is_func() -> Value {
  @runtime.make_native_func(name="is", length=2, fn(args) {
    // Object.is() - SameValue algorithm
    let x = if args.length() > 0 { args[0] } else { Undefined }
    let y = if args.length() > 1 { args[1] } else { Undefined }
    Bool(same_value(x, y))
  })
}

///|
fn make_from_entries_func(realm_state : @runtime.RealmState) -> Value {
  let object_proto = realm_state.get_obj_proto()
  @runtime.make_native_func(
    name="fromEntries",
    length=1,
    realm_state=Some(realm_state),
    fn(args) raise {
      // Object.fromEntries() - create object from iterable of key-value pairs
      let iterable = if args.length() > 0 { args[0] } else { Undefined }
      let properties : Map[String, Value] = {}
      match iterable {
        Value::Array(data) =>
          for entry in data.elements {
            match entry {
              Array(pair) =>
                if pair.elements.length() >= 2 {
                  let key = pair.elements[0].to_string()
                  let value = pair.elements[1]
                  properties[key] = value
                } else {
                  raise @errors.TypeError(
                    message="Iterator value is not an entry object",
                  )
                }
              Object(obj) => {
                // Object with numeric indices 0 and 1
                let key = match obj.bag.properties.get("0") {
                  Some(v) => v.to_string()
                  None =>
                    raise @errors.TypeError(
                      message="Iterator value is not an entry object",
                    )
                }
                let value = match obj.bag.properties.get("1") {
                  Some(v) => v
                  None =>
                    raise @errors.TypeError(
                      message="Iterator value is not an entry object",
                    )
                }
                properties[key] = value
              }
              _ =>
                raise @errors.TypeError(
                  message="Iterator value is not an entry object",
                )
            }
          }
        _ =>
          raise @errors.TypeError(
            message="Object.fromEntries requires an iterable argument",
          )
      }
      Value::Object({
        bag: {
          properties,
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
        },
        prototype: object_proto,
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
      })
    },
  )
}

///|
fn make_group_by_func() -> Value {
  @runtime.make_interp_static_func(name="groupBy", length=2, fn(
    interp,
    args,
  ) raise {
    // Object.groupBy(items, callbackFn)
    let items = if args.length() > 0 { args[0] } else { Undefined }
    let callback = if args.length() > 1 { args[1] } else { Undefined }
    if !@runtime.is_callable(callback) {
      raise @errors.TypeError(
        message=@runtime.to_js_string(callback) + " is not a function",
      )
    }
    let loc = @token.Loc::default()
    let o = to_object(items, interp)
    let len = @runtime.to_array_like_length_interp(o, interp)
    let group_arrays : Map[String, Array[Value]] = {}
    for k = 0; k < len; k = k + 1 {
      let kvalue = @runtime.get_array_like_element_interp(interp, o, k)
      let key = interp.call_value(
        callback,
        Undefined,
        [kvalue, Value::Number(k.to_double())],
        loc,
      )
      let property_key = @runtime.to_js_string(key)
      match group_arrays.get(property_key) {
        Some(arr) => arr.push(kvalue)
        None => {
          let arr : Array[Value] = [kvalue]
          group_arrays[property_key] = arr
        }
      }
    }
    // Build result object with null prototype
    let result_props : Map[String, Value] = {}
    group_arrays.each(fn(key, arr) {
      result_props[key] = @runtime.make_array(arr)
    })
    Value::Object({
      bag: {
        properties: result_props,
        symbol_properties: {},
        descriptors: {},
        symbol_descriptors: {},
      },
      prototype: Null,
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    })
  })
}

///|
fn make_has_own_func() -> Value {
  @runtime.make_interp_static_func(name="hasOwn", length=2, fn(
    interp,
    args,
  ) raise {
    // Object.hasOwn() - ES spec 20.1.2.14: Let obj be ? ToObject(O)
    let raw = if args.length() > 0 { args[0] } else { Undefined }
    let key_val = if args.length() > 1 { args[1] } else { Undefined }
    let obj = to_object(raw, interp)
    let prop_key = @runtime.to_property_key(key_val, interp=Some(interp))
    Bool(interp.get_own_property(obj, prop_key) is Some(_))
  })
}

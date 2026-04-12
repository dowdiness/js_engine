///|
/// Factory functions for Object integrity and utility static methods.
///
/// Each function returns a Value (a JS function object) for use as a static
/// method on the Object constructor.  None of these closures capture variables
/// from the outer setup_object_builtins scope — they operate entirely on their
/// lambda parameters and package-level helpers.

///|
fn make_freeze_func() -> Value {
  make_static_func_with_length("freeze", 1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        data.extensible = false
        // Freeze string properties
        let keys : Array[String] = []
        data.properties.each(fn(k, _v) { keys.push(k) })
        for key in keys {
          let existing = data.descriptors.get(key)
          data.descriptors[key] = {
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
          }
        }
        // Freeze symbol properties
        let sym_ids : Array[Int] = []
        data.symbol_properties.each(fn(id, _v) { sym_ids.push(id) })
        for id in sym_ids {
          let existing = data.symbol_descriptors.get(id)
          data.symbol_descriptors[id] = {
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
          }
        }
        obj
      }
      _ => obj
    }
  })
}

///|
fn make_seal_func() -> Value {
  make_static_func_with_length("seal", 1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        data.extensible = false
        // Seal string properties
        let keys : Array[String] = []
        data.properties.each(fn(k, _v) { keys.push(k) })
        for key in keys {
          let existing = data.descriptors.get(key)
          data.descriptors[key] = {
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
          }
        }
        // Seal symbol properties
        let sym_ids : Array[Int] = []
        data.symbol_properties.each(fn(id, _v) { sym_ids.push(id) })
        for id in sym_ids {
          let existing = data.symbol_descriptors.get(id)
          data.symbol_descriptors[id] = {
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
  make_static_func_with_length(
    "preventExtensions",
    1,
    fn(args) {
      let obj = if args.length() > 0 { args[0] } else { Undefined }
      match obj {
        Object(data) => {
          data.extensible = false
          obj
        }
        _ => obj
      }
    },
  )
}

///|
fn make_is_frozen_func() -> Value {
  make_static_func_with_length("isFrozen", 1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        if data.extensible {
          return Bool(false)
        }
        let mut frozen = true
        data.properties.each(fn(k, _v) {
          match data.descriptors.get(k) {
            Some(d) => if d.writable || d.configurable { frozen = false }
            None => frozen = false // No descriptor = writable+configurable
          }
        })
        Bool(frozen)
      }
      _ => Bool(true) // Non-objects are vacuously frozen
    }
  })
}

///|
fn make_is_sealed_func() -> Value {
  make_static_func_with_length("isSealed", 1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => {
        if data.extensible {
          return Bool(false)
        }
        let mut is_sealed = true
        data.properties.each(fn(k, _v) {
          match data.descriptors.get(k) {
            Some(d) => if d.configurable { is_sealed = false }
            None => is_sealed = false
          }
        })
        Bool(is_sealed)
      }
      _ => Bool(true)
    }
  })
}

///|
fn make_is_extensible_func() -> Value {
  make_static_func_with_length("isExtensible", 1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Object(data) => Bool(data.extensible)
      _ => Bool(false)
    }
  })
}

///|
fn make_is_func() -> Value {
  make_static_func_with_length("is", 2, fn(args) {
    // Object.is() - SameValue algorithm
    let x = if args.length() > 0 { args[0] } else { Undefined }
    let y = if args.length() > 1 { args[1] } else { Undefined }
    Bool(same_value(x, y))
  })
}

///|
fn make_from_entries_func() -> Value {
  make_static_func_with_length("fromEntries", 1, fn(args) raise {
    // Object.fromEntries() - create object from iterable of key-value pairs
    let iterable = if args.length() > 0 { args[0] } else { Undefined }
    let properties : Map[String, Value] = {}
    match iterable {
      Array(data) =>
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
              let key = match obj.properties.get("0") {
                Some(v) => v.to_string()
                None =>
                  raise @errors.TypeError(
                    message="Iterator value is not an entry object",
                  )
              }
              let value = match obj.properties.get("1") {
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
    Object({
      properties,
      symbol_properties: {},
      prototype: get_obj_proto(),
      callable: None,
      class_name: "Object",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })
  })
}

///|
fn make_group_by_func() -> Value {
  make_interp_static_func_with_length("groupBy", 2, fn(interp, args) raise {
    // Object.groupBy(items, callbackFn)
    let items = if args.length() > 0 { args[0] } else { Undefined }
    let callback = if args.length() > 1 { args[1] } else { Undefined }
    if !is_callable(callback) {
      raise @errors.TypeError(
        message=to_js_string(callback) + " is not a function",
      )
    }
    let loc = @token.Loc::default()
    let o = to_object(items, interp)
    let len = to_array_like_length_interp(o, interp)
    let group_arrays : Map[String, Array[Value]] = {}
    for k = 0; k < len; k = k + 1 {
      let kvalue = get_array_like_element_interp(interp, o, k)
      let key = interp.call_value(
        callback,
        Undefined,
        [kvalue, Number(k.to_double())],
        loc,
      )
      let property_key = to_js_string(key)
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
      result_props[key] = Array({ elements: arr })
    })
    Object({
      properties: result_props,
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "Object",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })
  })
}

///|
fn make_has_own_func() -> Value {
  make_interp_static_func_with_length("hasOwn", 2, fn(interp, args) raise {
    // Object.hasOwn() - ES spec 20.1.2.14: Let obj be ? ToObject(O)
    let raw = if args.length() > 0 { args[0] } else { Undefined }
    let key_val = if args.length() > 1 { args[1] } else { Undefined }
    let obj = to_object(raw, interp)
    match obj {
      Object(data) =>
        // Handle Symbol keys
        match key_val {
          Symbol(sym) => Bool(data.symbol_properties.contains(sym.id))
          _ => Bool(data.properties.contains(key_val.to_string()))
        }
      Array(data) => {
        let key = key_val.to_string()
        // Arrays support numeric index check
        if key == "length" {
          Bool(true)
        } else {
          let idx = @string.parse_int(key) catch { _ => -1 }
          Bool(
            idx >= 0 &&
            idx.to_string() == key &&
            idx < data.elements.length(),
          )
        }
      }
      _ => Bool(false)
    }
  })
}

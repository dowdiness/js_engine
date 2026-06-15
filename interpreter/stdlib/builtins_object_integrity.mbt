///|
/// Factory functions for Object integrity and utility static methods.
///
/// Each function returns a Value (a JS function object) for use as a static
/// method on the Object constructor.  None of these closures capture variables
/// from the outer setup_object_builtins scope — they operate entirely on their
/// lambda parameters and package-level helpers.

///|
fn make_freeze_func() -> Value {
  @runtime.make_native_func(name="freeze", length=1, fn(args) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.set_integrity_frozen(obj)
  })
}

///|
fn make_seal_func() -> Value {
  @runtime.make_native_func(name="seal", length=1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.set_integrity_sealed(obj)
  })
}

///|
fn make_prevent_extensions_func() -> Value {
  @runtime.make_interp_static_func(name="preventExtensions", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.object_prevent_extensions(interp, obj)
  })
}

///|
fn make_is_frozen_func() -> Value {
  @runtime.make_native_func(name="isFrozen", length=1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.test_integrity_frozen(obj)
  })
}

///|
fn make_is_sealed_func() -> Value {
  @runtime.make_native_func(name="isSealed", length=1, fn(args) {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.test_integrity_sealed(obj)
  })
}

///|
fn make_is_extensible_func() -> Value {
  @runtime.make_interp_static_func(name="isExtensible", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.object_is_extensible(interp, obj)
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
          internal_slots: {},
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
      let property_key = interp.to_js_string(key)
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
        internal_slots: {},
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

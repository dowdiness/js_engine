///|
/// Factory functions for Object property descriptor and definition methods.
///
/// Each function returns a Value (a JS function object) for use as a static
/// method on the Object constructor.
///
/// `[[OwnPropertyKeys]]`-class enumeration (getOwnPropertyNames /
/// getOwnPropertySymbols / the getOwnPropertyDescriptors+defineProperties key
/// snapshot) is owned by `@runtime` ops in `own_property_keys.mbt`; these
/// factories only call those ops rather than walking PropertyBag / ArrayData.

///|
fn make_get_own_property_names_func() -> Value {
  @runtime.make_interp_static_func(name="getOwnPropertyNames", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.own_string_property_names(interp, obj)
  })
}

///|
fn make_get_own_property_symbols_func() -> Value {
  @runtime.make_interp_static_func(name="getOwnPropertySymbols", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    @runtime.own_symbol_properties(interp, obj)
  })
}

///|
fn append_own_property_descriptor_result(
  interp : Interpreter,
  source : Value,
  key : Value,
  string_props : Map[String, Value],
  symbol_props : Map[Int, Value],
) -> Unit raise Error {
  match interp.get_own_property(source, key) {
    Some((desc, val)) => {
      let desc_value = @runtime.descriptor_to_value(desc, val)
      match key {
        Symbol(sym) => symbol_props[sym.id] = desc_value
        _ => string_props[@runtime.to_js_string(key)] = desc_value
      }
    }
    None => ()
  }
}

///|
fn append_own_property_descriptors_from_keys(
  interp : Interpreter,
  source : Value,
  keys : Array[Value],
  string_props : Map[String, Value],
  symbol_props : Map[Int, Value],
) -> Unit raise Error {
  for key in keys {
    append_own_property_descriptor_result(
      interp, source, key, string_props, symbol_props,
    )
  }
}

///|
fn collect_define_properties_pairs_from_keys(
  interp : Interpreter,
  obj : Value,
  keys : Array[Value],
  loc : @token.Loc,
) -> Array[(Value, @runtime.PartialDescriptor)] raise Error {
  let pairs : Array[(Value, @runtime.PartialDescriptor)] = []
  for key in keys {
    match interp.get_own_property(obj, key) {
      Some((own_desc, _)) =>
        if own_desc.enumerable {
          let desc_val = match key {
            Symbol(_) => interp.get_computed_property(obj, key, loc)
            _ => interp.get_property(obj, @runtime.to_js_string(key), loc)
          }
          let partial = interp.partial_descriptor_from_attrs(desc_val, loc)
          pairs.push((key, partial))
        }
      None => ()
    }
  }
  pairs
}

///|
fn apply_define_properties_pairs(
  interp : Interpreter,
  obj : Value,
  pairs : Array[(Value, @runtime.PartialDescriptor)],
  loc : @token.Loc,
) -> Unit raise Error {
  for pair in pairs {
    let (key, partial) = pair
    let ok = interp.define_own_property(obj, key, partial, loc)
    if !ok {
      let key_display = match key {
        Value::Symbol(_) => "Symbol"
        _ => @runtime.to_js_string(key)
      }
      raise @errors.TypeError(
        message="Cannot redefine property: \{key_display}",
      )
    }
  }
}

///|
fn define_properties_from_value(
  interp : Interpreter,
  obj : Value,
  descs : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  // §19.1.2.3 step 2: ToObject(Properties) — null/undefined throws.
  match descs {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    _ => ()
  }
  let props = match descs {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => descs
    _ => to_object(descs, interp)
  }
  // §19.1.2.3 steps 3-5: snapshot OwnPropertyKeys before running descriptor
  // getters. Keys added during ToPropertyDescriptor conversion are ignored.
  let keys = interp.own_property_keys(props)
  let pairs = collect_define_properties_pairs_from_keys(
    interp, props, keys, loc,
  )
  // §19.1.2.3 step 6: apply via dispatcher (ordinary / Array / Proxy).
  apply_define_properties_pairs(interp, obj, pairs, loc)
}

///|
fn make_get_own_property_descriptors_func() -> Value {
  @runtime.make_interp_static_func(name="getOwnPropertyDescriptors", length=1, fn(
    interp,
    args,
  ) raise {
    let raw = if args.length() > 0 { args[0] } else { Undefined }
    match raw {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      _ => ()
    }
    let obj = match raw {
      Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => raw
      _ => to_object(raw, interp)
    }
    let descriptors_props : Map[String, Value] = {}
    let symbol_descriptors_props : Map[Int, Value] = {}
    let keys = interp.own_property_keys(obj)
    append_own_property_descriptors_from_keys(
      interp, obj, keys, descriptors_props, symbol_descriptors_props,
    )
    Value::Object({
      bag: {
        properties: descriptors_props,
        symbol_properties: symbol_descriptors_props,
        descriptors: {},
        symbol_descriptors: {},
        internal_slots: {},
      },
      prototype: @runtime.get_obj_proto(realm_state=Some(interp.realm_state)),
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    })
  })
}

///|
fn make_define_property_func() -> Value {
  @runtime.make_interp_static_func(name="defineProperty", length=3, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    let prop_val = if args.length() > 1 { args[1] } else { Undefined }
    let descriptor = if args.length() > 2 { args[2] } else { Undefined }
    // §19.1.2.8 step 1: Object.defineProperty on non-object throws.
    if !@runtime.is_object_value(obj) {
      raise @errors.TypeError(
        message="Object.defineProperty called on non-object",
      )
    }
    let loc = @token.Loc::default()
    // §19.1.2.8 step 2: ToPropertyKey(P) runs BEFORE ToPropertyDescriptor,
    // so any Symbol.toPrimitive / toString hook on P observes attrs-object
    // getter side-effects in spec-defined order.
    let key = @runtime.to_property_key(prop_val, interp=Some(interp))
    // §6.2.5.5 ToPropertyDescriptor (includes attrs-must-be-object check).
    let partial = interp.partial_descriptor_from_attrs(descriptor, loc)
    // Dispatch through Interpreter::define_own_property (handles ordinary
    // / Array-exotic / Proxy-trap routing per §10.1.6 / §10.4.2.1 / §10.5.6).
    let ok = interp.define_own_property(obj, key, partial, loc)
    if !ok {
      let key_display = match key {
        Value::Symbol(_) => "Symbol"
        _ => @runtime.to_js_string(key)
      }
      raise @errors.TypeError(
        message="Cannot redefine property: \{key_display}",
      )
    }
    obj
  })
}

///|
fn make_get_own_property_descriptor_func() -> Value {
  @runtime.make_interp_static_func(name="getOwnPropertyDescriptor", length=2, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    let prop_key = if args.length() > 1 { args[1] } else { Undefined }
    // §19.1.2.9 step 1: ToObject. Null/Undefined throws; primitives other
    // than String_ aren't used as descriptor sources in this engine.
    match obj {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      _ => ()
    }
    // §19.1.2.9 on string primitives: inline the ToObject(String)
    // characterization — `length` (data, writable:false, enumerable:false,
    // configurable:false) and indexed character slots (data, writable:false,
    // enumerable:true, configurable:false).
    match obj {
      Value::String_(s) => {
        // String primitive has no own symbol properties — return undefined
        // before ToString (which would throw on Symbol keys).
        let string_prop_key = @runtime.to_property_key(
          prop_key,
          interp=Some(interp),
        )
        if string_prop_key is Symbol(_) {
          return Undefined
        }
        let prop_name = interp.to_js_string(string_prop_key)
        if prop_name == "length" {
          return make_data_desc_obj(
            Value::Number(s.length().to_double()),
            false,
            false,
            false,
            realm_state=Some(interp.realm_state),
          )
        }
        let idx = @string.parse_int(prop_name) catch { _ => -1 }
        if idx >= 0 && idx.to_string() == prop_name && idx < s.length() {
          let chars = s.to_array()
          let buf = StringBuilder::new()
          buf.write_char(chars[idx])
          return make_data_desc_obj(
            Value::String_(buf.to_string()),
            false,
            true,
            false,
            realm_state=Some(interp.realm_state),
          )
        }
        return Undefined
      }
      _ => ()
    }
    if !@runtime.is_object_value(obj) {
      return Undefined
    }
    // §10.5.5 / §10.1.5 via dispatcher — Proxy getOwnPropertyDescriptor trap fires.
    match interp.get_own_property(obj, prop_key) {
      None => Undefined
      Some((desc, val)) =>
        @runtime.descriptor_to_value(
          desc,
          val,
          realm_state=Some(interp.realm_state),
        )
    }
  })
}

///|
fn make_define_properties_func() -> Value {
  @runtime.make_interp_static_func(name="defineProperties", length=2, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    let descs = if args.length() > 1 { args[1] } else { Undefined }
    // §19.1.2.3 step 1: Object.defineProperties on non-object throws.
    if !@runtime.is_object_value(obj) {
      raise @errors.TypeError(
        message="Object.defineProperties called on non-object",
      )
    }
    let loc = @token.Loc::default()
    define_properties_from_value(interp, obj, descs, loc)
    obj
  })
}

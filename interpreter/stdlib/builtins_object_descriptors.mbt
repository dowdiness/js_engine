///|
/// Factory functions for Object property descriptor and definition methods.
///
/// Each function returns a Value (a JS function object) for use as a static
/// method on the Object constructor.

///|
fn is_internal_array_bag_key(key : String) -> Bool {
  key.has_prefix("[[")
}

///|
fn make_get_own_property_names_func() -> Value {
  @runtime.make_interp_static_func(name="getOwnPropertyNames", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      Value::Proxy(proxy_data) => {
        let all_keys = @runtime.proxy_own_property_keys(interp, proxy_data)
        let result : Array[Value] = []
        match all_keys {
          Value::Array(arr) =>
            for key in arr.elements {
              match key {
                Value::String_(_) => result.push(key)
                _ => () // getOwnPropertyNames only returns strings
              }
            }
          _ => ()
        }
        @runtime.make_array(result)
      }
      Object(data) => {
        let keys : Array[Value] = []
        let sorted = @runtime.sort_property_keys(data.bag.properties)
        for k in sorted {
          keys.push(Value::String_(k))
        }
        @runtime.make_array(keys)
      }
      Value::Array(data) => {
        let keys : Array[Value] = []
        for i = 0; i < data.elements.length(); i = i + 1 {
          keys.push(Value::String_(i.to_string()))
        }
        keys.push(Value::String_("length"))
        let sorted = @runtime.sort_property_keys(data.bag.properties)
        for k in sorted {
          if !is_internal_array_bag_key(k) {
            keys.push(Value::String_(k))
          }
        }
        @runtime.make_array(keys)
      }
      Value::String_(s) => {
        let keys : Array[Value] = []
        let chars = s.to_array()
        for i = 0; i < chars.length(); i = i + 1 {
          keys.push(Value::String_(i.to_string()))
        }
        keys.push(Value::String_("length"))
        @runtime.make_array(keys)
      }
      _ => @runtime.make_array([])
    }
  })
}

///|
fn make_get_own_property_symbols_func(sym_state : SymbolState) -> Value {
  @runtime.make_interp_static_func(name="getOwnPropertySymbols", length=1, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      Value::Proxy(proxy_data) => {
        let all_keys = @runtime.proxy_own_property_keys(interp, proxy_data)
        let result : Array[Value] = []
        match all_keys {
          Value::Array(arr) =>
            for key in arr.elements {
              match key {
                Value::Symbol(_) => result.push(key)
                _ => () // getOwnPropertySymbols only returns symbols
              }
            }
          _ => ()
        }
        @runtime.make_array(result)
      }
      Object(data) => {
        let symbols : Array[Value] = []
        data.bag.symbol_properties.each(fn(sym_id, _val) {
          match sym_state.get_symbol_by_id(sym_id) {
            Some(sym_data) => symbols.push(Symbol(sym_data))
            None => ()
          }
        })
        @runtime.make_array(symbols)
      }
      Value::Array(data) => {
        let symbols : Array[Value] = []
        data.bag.symbol_properties.each(fn(sym_id, _val) {
          match sym_state.get_symbol_by_id(sym_id) {
            Some(sym_data) => symbols.push(Symbol(sym_data))
            None => ()
          }
        })
        @runtime.make_array(symbols)
      }
      _ => @runtime.make_array([])
    }
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
fn is_hidden_internal_property_key(source : Value, key : String) -> Bool {
  let known_internal = key == "[[StringData]]" ||
    key == "[[NumberData]]" ||
    key == "[[BooleanData]]" ||
    key == "[[SymbolData]]" ||
    key == "[[PrimitiveValue]]" ||
    key == "[[ArrayLengthOverride]]" ||
    key == "[[TypedArrayName]]" ||
    key == "[[ViewedArrayBuffer]]" ||
    key == "[[ArrayBufferID]]" ||
    key == "[[ByteOffset]]" ||
    key == "[[ByteLength]]" ||
    key == "[[ArrayLength]]" ||
    key == "[[DateValue]]" ||
    key == "[[ArrayBufferByteLength]]" ||
    key == "[[RegExpStringIterator]]" ||
    key == "[[EvalFunctionReconcile]]"
  if !known_internal {
    return false
  }
  match source {
    Object(data) => data.class_name != "Object"
    Array(_) => key == "[[ArrayLengthOverride]]"
    _ => false
  }
}

///|
fn sort_visible_own_string_keys(
  source : Value,
  bag : @runtime.PropertyBag,
) -> Array[String] {
  let int_keys : Array[String] = []
  let str_keys : Array[String] = []
  bag.properties.each(fn(k, _v) {
    if is_hidden_internal_property_key(source, k) {
      return
    }
    let idx = @string.parse_int(k) catch { _ => -1 }
    if idx >= 0 && idx.to_string() == k {
      int_keys.push(k)
    } else {
      str_keys.push(k)
    }
  })
  int_keys.sort_by(fn(a, b) {
    let na = @string.parse_int(a) catch { _ => 0 }
    let nb = @string.parse_int(b) catch { _ => 0 }
    na - nb
  })
  let result : Array[String] = []
  for k in int_keys {
    result.push(k)
  }
  for k in str_keys {
    result.push(k)
  }
  result
}

///|
fn append_bag_own_keys(
  keys : Array[Value],
  source : Value,
  bag : @runtime.PropertyBag,
  sym_state : SymbolState,
) -> Unit {
  for prop_name in sort_visible_own_string_keys(source, bag) {
    keys.push(Value::String_(prop_name))
  }
  bag.symbol_properties.each(fn(sym_id, _raw) {
    match sym_state.get_symbol_by_id(sym_id) {
      Some(sym) => keys.push(Value::Symbol(sym))
      None => ()
    }
  })
}

///|
fn append_array_own_keys(
  keys : Array[Value],
  data : @runtime.ArrayData,
  sym_state : SymbolState,
) -> Unit {
  let source = Value::Array(data)
  let element_len = data.elements.length()
  for i = 0; i < element_len; i = i + 1 {
    if !data.holes.contains(i) {
      keys.push(Value::String_(i.to_string()))
    }
  }
  keys.push(Value::String_("length"))
  for prop_name in sort_visible_own_string_keys(source, data.bag) {
    let idx = @string.parse_int(prop_name) catch { _ => -1 }
    if idx >= 0 && idx.to_string() == prop_name && idx < element_len {
      continue
    }
    keys.push(Value::String_(prop_name))
  }
  data.bag.symbol_properties.each(fn(sym_id, _raw) {
    match sym_state.get_symbol_by_id(sym_id) {
      Some(sym) => keys.push(Value::Symbol(sym))
      None => ()
    }
  })
}

///|
fn own_property_keys_snapshot(
  interp : Interpreter,
  source : Value,
  sym_state : SymbolState,
) -> Array[Value] raise Error {
  let keys : Array[Value] = []
  match source {
    Object(data) => append_bag_own_keys(keys, source, data.bag, sym_state)
    Array(data) => append_array_own_keys(keys, data, sym_state)
    Map(data) => append_bag_own_keys(keys, source, data.bag, sym_state)
    Set(data) => append_bag_own_keys(keys, source, data.bag, sym_state)
    Promise(data) => append_bag_own_keys(keys, source, data.bag, sym_state)
    Proxy(proxy_data) =>
      match @runtime.proxy_own_property_keys(interp, proxy_data) {
        Value::Array(proxy_keys) =>
          for key in proxy_keys.elements {
            keys.push(key)
          }
        _ => ()
      }
    _ => ()
  }
  keys
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
  sym_state : SymbolState,
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
  let keys = own_property_keys_snapshot(interp, props, sym_state)
  let pairs = collect_define_properties_pairs_from_keys(
    interp, props, keys, loc,
  )
  // §19.1.2.3 step 6: apply via dispatcher (ordinary / Array / Proxy).
  apply_define_properties_pairs(interp, obj, pairs, loc)
}

///|
fn make_get_own_property_descriptors_func(sym_state : SymbolState) -> Value {
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
    let keys = own_property_keys_snapshot(interp, obj, sym_state)
    append_own_property_descriptors_from_keys(
      interp, obj, keys, descriptors_props, symbol_descriptors_props,
    )
    Value::Object({
      bag: {
        properties: descriptors_props,
        symbol_properties: symbol_descriptors_props,
        descriptors: {},
        symbol_descriptors: {},
      },
      prototype: @runtime.get_obj_proto(),
      callable: None,
      class_name: "Object",
      extensible: true,
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
        // before to_js_string (which would throw on Symbol keys).
        if prop_key is Symbol(_) {
          return Undefined
        }
        let prop_name = @runtime.to_js_string(prop_key)
        if prop_name == "length" {
          return make_data_desc_obj(
            Value::Number(s.length().to_double()),
            false,
            false,
            false,
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
      Some((desc, val)) => @runtime.descriptor_to_value(desc, val)
    }
  })
}

///|
fn make_define_properties_func(sym_state : SymbolState) -> Value {
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
    define_properties_from_value(interp, obj, descs, sym_state, loc)
    obj
  })
}

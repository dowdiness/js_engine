///|
/// Factory functions for Object property descriptor and definition methods.
///
/// Each function returns a Value (a JS function object) for use as a static
/// method on the Object constructor.

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
      _ => @runtime.make_array([])
    }
  })
}

///|
fn make_get_own_property_descriptors_func() -> Value {
  @runtime.make_native_func(name="getOwnPropertyDescriptors", length=1, fn(
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    match obj {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      Object(data) => {
        let descriptors_props : Map[String, Value] = {}
        data.bag.properties.each(fn(key, val) {
          let desc = data.bag.descriptors.get(key)
          let is_accessor = match desc {
            Some(d) => d.getter is Some(_) || d.setter is Some(_)
            None => false
          }
          if is_accessor {
            let getter_val = match desc {
              Some(d) =>
                match d.getter {
                  Some(g) => g
                  None => Undefined
                }
              None => Undefined
            }
            let setter_val = match desc {
              Some(d) =>
                match d.setter {
                  Some(s) => s
                  None => Undefined
                }
              None => Undefined
            }
            let enumerable = match desc {
              Some(d) => d.enumerable
              None => true
            }
            let configurable = match desc {
              Some(d) => d.configurable
              None => true
            }
            descriptors_props[key] = make_accessor_desc_obj(
              getter_val, setter_val, enumerable, configurable,
            )
          } else {
            let writable = match desc {
              Some(d) => d.writable
              None => true
            }
            let enumerable = match desc {
              Some(d) => d.enumerable
              None => true
            }
            let configurable = match desc {
              Some(d) => d.configurable
              None => true
            }
            descriptors_props[key] = make_data_desc_obj(
              val, writable, enumerable, configurable,
            )
          }
        })
        // Also include symbol-keyed property descriptors
        let sym_descs : Map[Int, Value] = {}
        data.bag.symbol_properties.each(fn(sym_id, val) {
          let desc = data.bag.symbol_descriptors.get(sym_id)
          let is_accessor = match desc {
            Some(d) => d.getter is Some(_) || d.setter is Some(_)
            None => false
          }
          if is_accessor {
            let getter_val = match desc {
              Some(d) =>
                match d.getter {
                  Some(g) => g
                  None => Undefined
                }
              None => Undefined
            }
            let setter_val = match desc {
              Some(d) =>
                match d.setter {
                  Some(s) => s
                  None => Undefined
                }
              None => Undefined
            }
            let enumerable = match desc {
              Some(d) => d.enumerable
              None => true
            }
            let configurable = match desc {
              Some(d) => d.configurable
              None => true
            }
            sym_descs[sym_id] = make_accessor_desc_obj(
              getter_val, setter_val, enumerable, configurable,
            )
          } else {
            let writable = match desc {
              Some(d) => d.writable
              None => true
            }
            let enumerable = match desc {
              Some(d) => d.enumerable
              None => true
            }
            let configurable = match desc {
              Some(d) => d.configurable
              None => true
            }
            sym_descs[sym_id] = make_data_desc_obj(
              val, writable, enumerable, configurable,
            )
          }
        })
        Value::Object({
          bag: {
            properties: descriptors_props,
            symbol_properties: sym_descs,
            descriptors: {},
            symbol_descriptors: {},
          },
          prototype: @runtime.get_obj_proto(),
          callable: None,
          class_name: "Object",
          extensible: true,
        })
      }
      _ =>
        Value::Object({
          bag: @runtime.PropertyBag::new(),
          prototype: @runtime.get_obj_proto(),
          callable: None,
          class_name: "Object",
          extensible: true,
        })
    }
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
    // §6.2.5.5 ToPropertyDescriptor (includes attrs-must-be-object check).
    let partial = interp.partial_descriptor_from_attrs(descriptor, loc)
    // Dispatch through Interpreter::define_own_property (handles ordinary
    // / Array-exotic / Proxy-trap routing per §10.1.6 / §10.4.2.1 / §10.5.6).
    let ok = interp.define_own_property(obj, prop_val, partial, loc)
    if !ok {
      raise @errors.TypeError(
        message="Cannot redefine property: \{@runtime.to_js_string(prop_val)}",
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
    // §19.1.2.3 step 2: ToObject(Properties) — null/undefined throws.
    match descs {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      _ => ()
    }
    let loc = @token.Loc::default()
    // §19.1.2.3 steps 3-5: collect (key, PartialDescriptor) pairs first.
    // Per spec, all ToPropertyDescriptor conversions must run before ANY
    // define is applied — if any conversion throws, the target is unmutated.
    let pairs : Array[(String, @runtime.PartialDescriptor)] = []
    // §19.1.2.3 step 3: OwnPropertyKeys(props). We iterate the underlying
    // PropertyBag regardless of exotic variant (Object/Array/Map/Set/Promise
    // all carry one). Proxy-as-Properties is not yet supported — the trap
    // chain for ownKeys + getOwnPropertyDescriptor on the source object is
    // a separate follow-up.
    let maybe_bag : @runtime.PropertyBag? = match descs {
      Object(d) => Some(d.bag)
      Array(d) => Some(d.bag)
      Map(d) => Some(d.bag)
      Set(d) => Some(d.bag)
      Promise(d) => Some(d.bag)
      _ => None
    }
    match maybe_bag {
      Some(bag) =>
        bag.properties.each(fn(prop_name, _raw) raise {
          if prop_name.has_prefix("[[") {
            return
          }
          let desc_enumerable = match bag.descriptors.get(prop_name) {
            Some(d) => d.enumerable
            None => true
          }
          if !desc_enumerable {
            return
          }
          // §19.1.2.3 step 5.b.i: Get(props, nextKey) — invokes any getters.
          let desc_val = interp.get_property(descs, prop_name, loc)
          // §6.2.5.5 ToPropertyDescriptor (validates descriptor shape).
          let partial = interp.partial_descriptor_from_attrs(desc_val, loc)
          pairs.push((prop_name, partial))
        })
      None => ()
    }
    // §19.1.2.3 step 6: apply via dispatcher (handles ordinary / Array-exotic
    // / Proxy-trap routing per §10.1.6 / §10.4.2.1 / §10.5.6).
    for pair in pairs {
      let (key, partial) = pair
      let ok = interp.define_own_property(
        obj,
        Value::String_(key),
        partial,
        loc,
      )
      if !ok {
        raise @errors.TypeError(message="Cannot redefine property: \{key}")
      }
    }
    obj
  })
}

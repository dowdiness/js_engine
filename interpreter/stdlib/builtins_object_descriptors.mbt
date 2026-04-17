///|
/// Factory functions for Object property descriptor and definition methods.
///
/// Each function returns a Value (a JS function object) for use as a static
/// method on the Object constructor.

///|
fn make_get_own_property_names_func() -> Value {
  @runtime.make_interp_static_func_with_length("getOwnPropertyNames", 1, fn(
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
  @runtime.make_interp_static_func_with_length("getOwnPropertySymbols", 1, fn(
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
  @runtime.make_static_func_with_length("getOwnPropertyDescriptors", 1, fn(
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
  @runtime.make_interp_static_func_with_length("defineProperty", 3, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    let prop_val = if args.length() > 1 { args[1] } else { Undefined }
    let descriptor = if args.length() > 2 { args[2] } else { Undefined }
    // Per ES spec, Object.defineProperty on non-object throws TypeError
    // Array, Map, Set, Promise are JS objects
    match obj {
      Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
      _ =>
        raise @errors.TypeError(
          message="Object.defineProperty called on non-object",
        )
    }
    // Per ES spec, descriptor must be an object
    // Array, Map, Set, Promise are JS objects
    match descriptor {
      Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
      _ =>
        raise @errors.TypeError(
          message="Property description must be an object: \{descriptor.to_string()}",
        )
    }
    // Extract descriptor properties using full Get (ToPropertyDescriptor spec)
    // This handles inherited properties and accessor properties (getters)
    let desc_props : Map[String, Value] = {
      let result : Map[String, Value] = {}
      let loc = @token.Loc::default()
      let desc_keys = [
        "value", "writable", "enumerable", "configurable", "get", "set",
      ]
      for key in desc_keys {
        // Use @runtime.has_property to check if key exists (includes prototype chain)
        let has = @runtime.has_property(descriptor, key, interp=Some(interp))
        if has {
          let v = interp.get_property(descriptor, key, loc)
          result[key] = v
        }
      }
      result
    }
    // Detect accessor vs data descriptor
    let has_get = desc_props.contains("get")
    let has_set = desc_props.contains("set")
    let has_value = desc_props.contains("value")
    let has_writable = desc_props.contains("writable")
    let is_accessor = has_get || has_set
    let is_data = has_value || has_writable

    // Accessor and data descriptor properties cannot be mixed
    if is_accessor && is_data {
      raise @errors.TypeError(
        message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
      )
    }
    let new_writable = match desc_props.get("writable") {
      Some(v) => Some(@runtime.is_truthy(v))
      None => None
    }
    let new_enumerable = match desc_props.get("enumerable") {
      Some(v) => Some(@runtime.is_truthy(v))
      None => None
    }
    let new_configurable = match desc_props.get("configurable") {
      Some(v) => Some(@runtime.is_truthy(v))
      None => None
    }

    // Extract getter/setter from accessor descriptor
    let new_getter : Value? = if has_get {
      match desc_props.get("get") {
        Some(Undefined) => Some(Undefined)
        Some(v) => Some(v)
        None => None
      }
    } else {
      None
    }
    let new_setter : Value? = if has_set {
      match desc_props.get("set") {
        Some(Undefined) => Some(Undefined)
        Some(v) => Some(v)
        None => None
      }
    } else {
      None
    }

    // Validate getter/setter are callable (or undefined)
    match new_getter {
      Some(Object(g)) =>
        if g.callable is None {
          raise @errors.TypeError(
            message="Getter must be a function: [object Object]",
          )
        }
      Some(Undefined) | None => ()
      Some(_) =>
        raise @errors.TypeError(
          message="Getter must be a function: \{new_getter.unwrap().to_string()}",
        )
    }
    match new_setter {
      Some(Object(s)) =>
        if s.callable is None {
          raise @errors.TypeError(
            message="Setter must be a function: [object Object]",
          )
        }
      Some(Undefined) | None => ()
      Some(_) =>
        raise @errors.TypeError(
          message="Setter must be a function: \{new_setter.unwrap().to_string()}",
        )
    }
    match obj {
      Object(data) => {
        // Determine if key is a Symbol or string
        let is_symbol_key = prop_val is Symbol(_)
        let sym_id = match prop_val {
          Value::Symbol(s) => s.id
          _ => 0
        }
        let prop_name = if is_symbol_key {
          ""
        } else {
          @runtime.to_js_string(prop_val)
        }

        // Check if property exists (using symbol or string storage)
        let prop_exists = if is_symbol_key {
          data.bag.symbol_properties.contains(sym_id)
        } else {
          data.bag.properties.contains(prop_name)
        }

        // Get existing descriptor
        let existing_desc : PropDescriptor? = if is_symbol_key {
          data.bag.symbol_descriptors.get(sym_id)
        } else {
          data.bag.descriptors.get(prop_name)
        }

        // Property key display name for error messages
        let prop_display = if is_symbol_key {
          prop_val.to_string()
        } else {
          prop_name
        }

        // Validate non-configurable constraints or extensibility
        match existing_desc {
          Some(existing) =>
            @runtime.validate_non_configurable(
              existing,
              prop_display,
              is_accessor,
              is_data,
              has_value,
              new_writable,
              new_enumerable,
              new_configurable,
              new_getter,
              new_setter,
              fn() {
                if is_symbol_key {
                  match data.bag.symbol_properties.get(sym_id) {
                    Some(v) => v
                    None => Undefined
                  }
                } else {
                  match data.bag.properties.get(prop_name) {
                    Some(v) => v
                    None => Undefined
                  }
                }
              },
              fn() { desc_props.get("value") },
            )
          None =>
            // Check extensibility when adding new property
            if !prop_exists && !data.extensible {
              raise @errors.TypeError(
                message="Cannot add property \{prop_display}, object is not extensible",
              )
            }
        }
        if is_accessor {
          // Accessor descriptor
          // Set a placeholder in properties if not present
          if is_symbol_key {
            if !data.bag.symbol_properties.contains(sym_id) {
              data.bag.symbol_properties[sym_id] = Undefined
            }
          } else if !data.bag.properties.contains(prop_name) {
            data.bag.properties[prop_name] = Undefined
          }
          let enumerable = match new_enumerable {
            Some(e) => e
            None =>
              match existing_desc {
                Some(d) => d.enumerable
                None => if prop_exists { true } else { false }
              }
          }
          let configurable = match new_configurable {
            Some(c) => c
            None =>
              match existing_desc {
                Some(d) => d.configurable
                None => if prop_exists { true } else { false }
              }
          }
          let getter = match new_getter {
            Some(v) =>
              match v {
                Undefined => None
                _ => Some(v)
              }
            None =>
              match existing_desc {
                Some(d) => d.getter
                None => None
              }
          }
          let setter = match new_setter {
            Some(v) =>
              match v {
                Undefined => None
                _ => Some(v)
              }
            None =>
              match existing_desc {
                Some(d) => d.setter
                None => None
              }
          }
          let final_desc : PropDescriptor = {
            writable: false,
            enumerable,
            configurable,
            getter,
            setter,
          }
          if is_symbol_key {
            data.bag.symbol_descriptors[sym_id] = final_desc
          } else {
            data.bag.descriptors[prop_name] = final_desc
          }
        } else {
          // Data descriptor
          // Set value
          match desc_props.get("value") {
            Some(v) =>
              if is_symbol_key {
                data.bag.symbol_properties[sym_id] = v
              } else {
                data.bag.properties[prop_name] = v
              }
            None =>
              if is_symbol_key {
                if !data.bag.symbol_properties.contains(sym_id) {
                  data.bag.symbol_properties[sym_id] = Undefined
                }
              } else if !data.bag.properties.contains(prop_name) {
                data.bag.properties[prop_name] = Undefined
              }
          }
          // Build final descriptor using new values or existing defaults
          // If property exists but has no explicit descriptor, defaults are true
          // (property was created by normal assignment)
          let writable = match new_writable {
            Some(w) => w
            None =>
              match existing_desc {
                Some(d) => d.writable
                None => if prop_exists { true } else { false }
              }
          }
          let enumerable = match new_enumerable {
            Some(e) => e
            None =>
              match existing_desc {
                Some(d) => d.enumerable
                None => if prop_exists { true } else { false }
              }
          }
          let configurable = match new_configurable {
            Some(c) => c
            None =>
              match existing_desc {
                Some(d) => d.configurable
                None => if prop_exists { true } else { false }
              }
          }
          let final_desc : PropDescriptor = {
            writable,
            enumerable,
            configurable,
            getter: None,
            setter: None,
          }
          if is_symbol_key {
            data.bag.symbol_descriptors[sym_id] = final_desc
          } else {
            data.bag.descriptors[prop_name] = final_desc
          }
        }
      }
      Array(arr_data) => {
        // Handle defineProperty on Array targets
        let handles_iterator_override = match prop_val {
          Value::Symbol(sym) => sym.id == @runtime.get_iterator_symbol().id
          _ => false
        }
        if handles_iterator_override {
          if is_accessor {
            let getter = match new_getter {
              Some(v) =>
                match v {
                  Undefined => None
                  _ => Some(v)
                }
              None => None
            }
            @runtime.set_array_iterator_override(arr_data, getter, None)
          } else {
            let value = match desc_props.get("value") {
              Some(v) => v
              None => Undefined
            }
            @runtime.set_array_iterator_override(arr_data, None, Some(value))
          }
        } else {
          let prop_name = @runtime.to_js_string(prop_val)
          if prop_name == "length" {
            // Handle length property changes
            match desc_props.get("value") {
              Some(val) => {
                let n = @runtime.to_number(val)
                let new_len = n.to_int()
                if new_len < 0 || new_len.to_double() != n || n.is_nan() {
                  raise @errors.RangeError(message="Invalid array length")
                }
                // Truncate or extend the array
                while arr_data.elements.length() > new_len {
                  let _removed = arr_data.elements.pop()
                }
                while arr_data.elements.length() < new_len {
                  arr_data.elements.push(Undefined)
                }
              }
              None => ()
            }
          } else {
            // Check if prop_name is a valid array index
            let idx = @string.parse_int(prop_name) catch { _ => -1 }
            if idx >= 0 && idx.to_string() == prop_name {
              // Only write value if descriptor specifies one
              match desc_props.get("value") {
                Some(v) => {
                  // Extend array if needed
                  while arr_data.elements.length() <= idx {
                    arr_data.elements.push(Undefined)
                  }
                  arr_data.elements[idx] = v
                }
                None => ()
              }
            }
            // Non-index properties on arrays: silently succeed
            // (our Array representation doesn't support named props)
          }
        }
      }
      Value::Promise(data) => {
        let prop_name = @runtime.to_js_string(prop_val)
        let existing_desc = data.bag.descriptors.get(prop_name)
        if is_accessor {
          if !data.bag.properties.contains(prop_name) {
            data.bag.properties[prop_name] = Undefined
          }
          let enumerable = match new_enumerable {
            Some(e) => e
            None =>
              match existing_desc {
                Some(d) => d.enumerable
                None => false
              }
          }
          let configurable = match new_configurable {
            Some(c) => c
            None =>
              match existing_desc {
                Some(d) => d.configurable
                None => false
              }
          }
          let getter = match new_getter {
            Some(v) =>
              match v {
                Undefined => None
                _ => Some(v)
              }
            None =>
              match existing_desc {
                Some(d) => d.getter
                None => None
              }
          }
          let setter = match new_setter {
            Some(v) =>
              match v {
                Undefined => None
                _ => Some(v)
              }
            None =>
              match existing_desc {
                Some(d) => d.setter
                None => None
              }
          }
          data.bag.descriptors[prop_name] = {
            writable: false,
            enumerable,
            configurable,
            getter,
            setter,
          }
        } else {
          match desc_props.get("value") {
            Some(v) => data.bag.properties[prop_name] = v
            None =>
              if !data.bag.properties.contains(prop_name) {
                data.bag.properties[prop_name] = Undefined
              }
          }
          let writable = match new_writable {
            Some(w) => w
            None =>
              match existing_desc {
                Some(d) => d.writable
                None => false
              }
          }
          let enumerable = match new_enumerable {
            Some(e) => e
            None =>
              match existing_desc {
                Some(d) => d.enumerable
                None => false
              }
          }
          let configurable = match new_configurable {
            Some(c) => c
            None =>
              match existing_desc {
                Some(d) => d.configurable
                None => false
              }
          }
          data.bag.descriptors[prop_name] = {
            writable,
            enumerable,
            configurable,
            getter: None,
            setter: None,
          }
        }
      }
      Value::Proxy(proxy_data) => {
        // Delegate defineProperty to the target through the proxy
        let target = match proxy_data.target {
          Some(t) => t
          None =>
            raise @errors.TypeError(
              message="Cannot perform 'defineProperty' on a proxy that has been revoked",
            )
        }
        match target {
          Object(data) => {
            let is_symbol_key = prop_val is Symbol(_)
            let sym_id = match prop_val {
              Value::Symbol(s) => s.id
              _ => 0
            }
            let prop_name = @runtime.to_js_string(prop_val)
            let prop_exists = if is_symbol_key {
              data.bag.symbol_properties.contains(sym_id)
            } else {
              data.bag.properties.contains(prop_name)
            }
            let existing_desc : PropDescriptor? = if is_symbol_key {
              data.bag.symbol_descriptors.get(sym_id)
            } else {
              data.bag.descriptors.get(prop_name)
            }
            let prop_also_in_desc = if is_symbol_key {
              data.bag.symbol_descriptors.contains(sym_id)
            } else {
              data.bag.descriptors.contains(prop_name)
            }
            if !prop_exists && !prop_also_in_desc && !data.extensible {
              let prop_display = if is_symbol_key {
                prop_val.to_string()
              } else {
                prop_name
              }
              raise @errors.TypeError(
                message="Cannot add property \{prop_display}, object is not extensible",
              )
            }
            // Validate non-configurable constraints
            match existing_desc {
              Some(existing) => {
                let prop_display = if is_symbol_key {
                  prop_val.to_string()
                } else {
                  prop_name
                }
                @runtime.validate_non_configurable(
                  existing,
                  prop_display,
                  is_accessor,
                  is_data,
                  has_value,
                  new_writable,
                  new_enumerable,
                  new_configurable,
                  new_getter,
                  new_setter,
                  fn() {
                    if is_symbol_key {
                      match data.bag.symbol_properties.get(sym_id) {
                        Some(v) => v
                        None => Undefined
                      }
                    } else {
                      match data.bag.properties.get(prop_name) {
                        Some(v) => v
                        None => Undefined
                      }
                    }
                  },
                  fn() {
                    match desc_props.get("value") {
                      Some(v) => Some(v)
                      None => None
                    }
                  },
                )
              }
              None => ()
            }
            if is_accessor {
              if is_symbol_key {
                if !data.bag.symbol_properties.contains(sym_id) {
                  data.bag.symbol_properties[sym_id] = Undefined
                }
              } else if !data.bag.properties.contains(prop_name) {
                data.bag.properties[prop_name] = Undefined
              }
              let enumerable = match new_enumerable {
                Some(e) => e
                None =>
                  match existing_desc {
                    Some(d) => d.enumerable
                    None => false
                  }
              }
              let configurable = match new_configurable {
                Some(c) => c
                None =>
                  match existing_desc {
                    Some(d) => d.configurable
                    None => false
                  }
              }
              let getter = match new_getter {
                Some(v) =>
                  match v {
                    Undefined => None
                    _ => Some(v)
                  }
                None =>
                  match existing_desc {
                    Some(d) => d.getter
                    None => None
                  }
              }
              let setter = match new_setter {
                Some(v) =>
                  match v {
                    Undefined => None
                    _ => Some(v)
                  }
                None =>
                  match existing_desc {
                    Some(d) => d.setter
                    None => None
                  }
              }
              let final_desc : PropDescriptor = {
                writable: false,
                enumerable,
                configurable,
                getter,
                setter,
              }
              if is_symbol_key {
                data.bag.symbol_descriptors[sym_id] = final_desc
              } else {
                data.bag.descriptors[prop_name] = final_desc
              }
            } else {
              match desc_props.get("value") {
                Some(v) =>
                  if is_symbol_key {
                    data.bag.symbol_properties[sym_id] = v
                  } else {
                    data.bag.properties[prop_name] = v
                  }
                None =>
                  if is_symbol_key {
                    if !data.bag.symbol_properties.contains(sym_id) {
                      data.bag.symbol_properties[sym_id] = Undefined
                    }
                  } else if !data.bag.properties.contains(prop_name) {
                    data.bag.properties[prop_name] = Undefined
                  }
              }
              let writable = match new_writable {
                Some(w) => w
                None =>
                  match existing_desc {
                    Some(d) => d.writable
                    None => false
                  }
              }
              let enumerable = match new_enumerable {
                Some(e) => e
                None =>
                  match existing_desc {
                    Some(d) => d.enumerable
                    None => false
                  }
              }
              let configurable = match new_configurable {
                Some(c) => c
                None =>
                  match existing_desc {
                    Some(d) => d.configurable
                    None => false
                  }
              }
              let final_desc : PropDescriptor = {
                writable,
                enumerable,
                configurable,
                getter: None,
                setter: None,
              }
              if is_symbol_key {
                data.bag.symbol_descriptors[sym_id] = final_desc
              } else {
                data.bag.descriptors[prop_name] = final_desc
              }
            }
          }
          _ => ()
        }
      }
      _ => ()
    }
    obj
  })
}

///|
fn make_get_own_property_descriptor_func() -> Value {
  @runtime.make_static_func_with_length("getOwnPropertyDescriptor", 2, fn(
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    let prop_key = if args.length() > 1 { args[1] } else { Undefined }
    let is_symbol_key = prop_key is Symbol(_)
    let sym_id = match prop_key {
      Value::Symbol(s) => s.id
      _ => 0
    }
    let prop_name = prop_key.to_string()
    match obj {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      Object(data) =>
        // Handle Symbol keys
        if is_symbol_key {
          if data.bag.symbol_properties.contains(sym_id) {
            let val = match data.bag.symbol_properties.get(sym_id) {
              Some(v) => v
              None => Undefined
            }
            let desc = data.bag.symbol_descriptors.get(sym_id)
            let is_accessor = match desc {
              Some(d) => d.getter is Some(_) || d.setter is Some(_)
              None => false
            }
            if is_accessor {
              let getter_val : Value = match desc {
                Some(d) =>
                  match d.getter {
                    Some(g) => g
                    None => Undefined
                  }
                None => Undefined
              }
              let setter_val : Value = match desc {
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
              make_accessor_desc_obj(
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
              make_data_desc_obj(val, writable, enumerable, configurable)
            }
          } else {
            Undefined
          }
        } else if data.bag.properties.contains(prop_name) &&
          !prop_name.has_prefix("[[") {
          let val = match data.bag.properties.get(prop_name) {
            Some(v) => v
            None => Undefined
          }
          let desc = data.bag.descriptors.get(prop_name)
          // Check if this is an accessor descriptor
          let is_accessor = match desc {
            Some(d) => d.getter is Some(_) || d.setter is Some(_)
            None => false
          }
          if is_accessor {
            // Return accessor descriptor format
            let getter_val : Value = match desc {
              Some(d) =>
                match d.getter {
                  Some(g) => g
                  None => Undefined
                }
              None => Undefined
            }
            let setter_val : Value = match desc {
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
            make_accessor_desc_obj(
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
            make_data_desc_obj(val, writable, enumerable, configurable)
          }
        } else if data.bag.descriptors.contains(prop_name) {
          // Check for accessor-only properties in descriptors (e.g., strict mode arguments.callee)
          let desc = data.bag.descriptors.get(prop_name)
          let is_accessor = match desc {
            Some(d) => d.getter is Some(_) || d.setter is Some(_)
            None => false
          }
          if is_accessor {
            let getter_val : Value = match desc {
              Some(d) =>
                match d.getter {
                  Some(g) => g
                  None => Undefined
                }
              None => Undefined
            }
            let setter_val : Value = match desc {
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
            make_accessor_desc_obj(
              getter_val, setter_val, enumerable, configurable,
            )
          } else {
            // Data descriptor without a value in properties
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
            make_data_desc_obj(Undefined, writable, enumerable, configurable)
          }
        } else {
          // Check for built-in function properties (length, name)
          match data.callable {
            Some(callable) =>
              if prop_name == "length" {
                let len : Double = match callable {
                  UserFunc(f) => f.params.length().to_double()
                  UserFuncExt(f) => f.params.length().to_double()
                  ArrowFunc(f) => f.params.length().to_double()
                  ArrowFuncExt(f) => f.params.length().to_double()
                  NativeCallable(_, _) => 0.0
                  NonConstructableCallable(_, _) => 0.0
                  MethodCallable(_, _) => 0.0
                  InterpreterCallable(_, _) => 0.0
                  ConstructorOnlyCallable(_, _) => 0.0
                  BoundFunc(_, _, _) => 0.0
                  FuncCallMethod(_) => 0.0
                  FuncApplyMethod(_) => 0.0
                  ClassConstructor(_) => 0.0
                }
                make_data_desc_obj(Value::Number(len), false, false, true)
              } else if prop_name == "name" {
                let name : String = match callable {
                  UserFunc(f) =>
                    match f.name {
                      Some(n) => n
                      None => ""
                    }
                  UserFuncExt(f) =>
                    match f.name {
                      Some(n) => n
                      None => ""
                    }
                  ArrowFunc(f) =>
                    match f.name {
                      Some(n) => n
                      None => ""
                    }
                  ArrowFuncExt(f) =>
                    match f.name {
                      Some(n) => n
                      None => ""
                    }
                  NativeCallable(n, _) => n
                  NonConstructableCallable(n, _) => n
                  MethodCallable(n, _) => n
                  InterpreterCallable(n, _) => n
                  ConstructorOnlyCallable(n, _) => n
                  BoundFunc(_, _, _) => "bound "
                  FuncCallMethod(_) => "call"
                  FuncApplyMethod(_) => "apply"
                  ClassConstructor({ name: n, .. }) => n
                }
                make_data_desc_obj(Value::String_(name), false, false, true)
              } else {
                Undefined
              }
            None => Undefined
          }
        }
      Value::Array(data) =>
        if prop_name == "length" {
          make_data_desc_obj(
            Value::Number(data.elements.length().to_double()),
            true,
            false,
            false,
          )
        } else {
          // Check indexed properties
          let idx = @string.parse_int(prop_name) catch { _ => -1 }
          if idx >= 0 &&
            idx.to_string() == prop_name &&
            idx < data.elements.length() {
            make_data_desc_obj(data.elements[idx], true, true, true)
          } else {
            Undefined
          }
        }
      Value::String_(s) =>
        if prop_name == "length" {
          make_data_desc_obj(
            Value::Number(s.length().to_double()),
            false,
            false,
            false,
          )
        } else {
          let idx = @string.parse_int(prop_name) catch { _ => -1 }
          if idx >= 0 && idx.to_string() == prop_name && idx < s.length() {
            let chars = s.to_array()
            let buf = StringBuilder::new()
            buf.write_char(chars[idx])
            make_data_desc_obj(
              Value::String_(buf.to_string()),
              false,
              true,
              false,
            )
          } else {
            Undefined
          }
        }
      Value::Proxy(proxy_data) =>
        // Unwrap proxy and get descriptor from target
        match proxy_data.target {
          Some(target) =>
            match target {
              Object(data) =>
                if is_symbol_key {
                  if data.bag.symbol_properties.contains(sym_id) ||
                    data.bag.symbol_descriptors.contains(sym_id) {
                    let val = match data.bag.symbol_properties.get(sym_id) {
                      Some(v) => v
                      None => Undefined
                    }
                    let desc = data.bag.symbol_descriptors.get(sym_id)
                    let is_acc = match desc {
                      Some(d) => d.getter is Some(_) || d.setter is Some(_)
                      None => false
                    }
                    if is_acc {
                      let getter_val : Value = match desc {
                        Some(d) =>
                          match d.getter {
                            Some(g) => g
                            None => Undefined
                          }
                        None => Undefined
                      }
                      let setter_val : Value = match desc {
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
                      make_accessor_desc_obj(
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
                      make_data_desc_obj(
                        val, writable, enumerable, configurable,
                      )
                    }
                  } else {
                    Undefined
                  }
                } else if data.bag.properties.contains(prop_name) ||
                  data.bag.descriptors.contains(prop_name) {
                  let val = match data.bag.properties.get(prop_name) {
                    Some(v) => v
                    None => Undefined
                  }
                  let desc = data.bag.descriptors.get(prop_name)
                  let is_acc = match desc {
                    Some(d) => d.getter is Some(_) || d.setter is Some(_)
                    None => false
                  }
                  if is_acc {
                    let getter_val : Value = match desc {
                      Some(d) =>
                        match d.getter {
                          Some(g) => g
                          None => Undefined
                        }
                      None => Undefined
                    }
                    let setter_val : Value = match desc {
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
                    make_accessor_desc_obj(
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
                    make_data_desc_obj(val, writable, enumerable, configurable)
                  }
                } else {
                  Undefined
                }
              _ => Undefined
            }
          None =>
            raise @errors.TypeError(
              message="Cannot perform 'getOwnPropertyDescriptor' on a proxy that has been revoked",
            )
        }
      _ => Undefined
    }
  })
}

///|
fn make_define_properties_func() -> Value {
  @runtime.make_interp_static_func_with_length("defineProperties", 2, fn(
    interp,
    args,
  ) raise {
    let obj = if args.length() > 0 { args[0] } else { Undefined }
    let descs = if args.length() > 1 { args[1] } else { Undefined }
    // Per ES spec, Object.defineProperties on non-object throws TypeError
    // Array, Map, Set, Promise are JS objects
    match obj {
      Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
      _ =>
        raise @errors.TypeError(
          message="Object.defineProperties called on non-object",
        )
    }
    // Per ES spec step 2: ToObject(Properties) - null/undefined throws TypeError
    match descs {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      _ => ()
    }
    let iloc = @token.Loc::default()
    match (obj, descs) {
      (Object(data), Object(desc_obj)) =>
        // Only iterate enumerable own properties of descriptors object
        // Use get_property to invoke getters on the Properties object
        desc_obj.bag.properties.each(fn(prop_name, _raw_val) raise {
          // Skip internal slots
          if prop_name.has_prefix("[[") {
            return
          }
          let desc_enumerable = match desc_obj.bag.descriptors.get(prop_name) {
            Some(d) => d.enumerable
            None => true
          }
          if !desc_enumerable {
            return
          }
          let desc_val = interp.get_property(descs, prop_name, iloc)
          match desc_val {
            Object(_) => {
              let has_get = @runtime.has_property(desc_val, "get")
              let has_set = @runtime.has_property(desc_val, "set")
              let has_value = @runtime.has_property(desc_val, "value")
              let has_writable = @runtime.has_property(desc_val, "writable")
              let is_accessor = has_get || has_set
              let is_data = has_value || has_writable
              if is_accessor && is_data {
                raise @errors.TypeError(
                  message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
                )
              }
              let prop_exists = data.bag.properties.contains(prop_name)
              let existing_desc = data.bag.descriptors.get(prop_name)

              // Validate getter/setter - use get_property for prototype chain
              let new_getter : Value? = if has_get {
                let v = interp.get_property(desc_val, "get", iloc)
                match v {
                  Undefined => Some(Undefined)
                  _ => Some(v)
                }
              } else {
                None
              }
              let new_setter : Value? = if has_set {
                let v = interp.get_property(desc_val, "set", iloc)
                match v {
                  Undefined => Some(Undefined)
                  _ => Some(v)
                }
              } else {
                None
              }
              match new_getter {
                Some(Object(g)) =>
                  if g.callable is None {
                    raise @errors.TypeError(
                      message="Getter must be a function: [object Object]",
                    )
                  }
                Some(Undefined) | None => ()
                Some(_) =>
                  raise @errors.TypeError(
                    message="Getter must be a function: \{new_getter.unwrap().to_string()}",
                  )
              }
              match new_setter {
                Some(Object(s)) =>
                  if s.callable is None {
                    raise @errors.TypeError(
                      message="Setter must be a function: [object Object]",
                    )
                  }
                Some(Undefined) | None => ()
                Some(_) =>
                  raise @errors.TypeError(
                    message="Setter must be a function: \{new_setter.unwrap().to_string()}",
                  )
              }
              let new_writable = if @runtime.has_property(desc_val, "writable") {
                Some(
                  @runtime.is_truthy(
                    interp.get_property(desc_val, "writable", iloc),
                  ),
                )
              } else {
                None
              }
              let new_enumerable = if @runtime.has_property(
                  desc_val, "enumerable",
                ) {
                Some(
                  @runtime.is_truthy(
                    interp.get_property(desc_val, "enumerable", iloc),
                  ),
                )
              } else {
                None
              }
              let new_configurable = if @runtime.has_property(
                  desc_val, "configurable",
                ) {
                Some(
                  @runtime.is_truthy(
                    interp.get_property(desc_val, "configurable", iloc),
                  ),
                )
              } else {
                None
              }

              // Pre-extract new value for validation (invoke getter if needed)
              let new_desc_value : Value? = if has_value {
                Some(interp.get_property(desc_val, "value", iloc))
              } else {
                None
              }
              // Validate non-configurable constraints or extensibility
              match existing_desc {
                Some(existing) =>
                  @runtime.validate_non_configurable(
                    existing,
                    prop_name,
                    is_accessor,
                    is_data,
                    has_value,
                    new_writable,
                    new_enumerable,
                    new_configurable,
                    new_getter,
                    new_setter,
                    fn() {
                      match data.bag.properties.get(prop_name) {
                        Some(v) => v
                        None => Undefined
                      }
                    },
                    fn() { new_desc_value },
                  )
                None =>
                  if !prop_exists && !data.extensible {
                    raise @errors.TypeError(
                      message="Cannot add property \{prop_name}, object is not extensible",
                    )
                  }
              }
              if is_accessor {
                if !data.bag.properties.contains(prop_name) {
                  data.bag.properties[prop_name] = Undefined
                }
                let enumerable = match new_enumerable {
                  Some(e) => e
                  None =>
                    match existing_desc {
                      Some(d) => d.enumerable
                      None => false
                    }
                }
                let configurable = match new_configurable {
                  Some(c) => c
                  None =>
                    match existing_desc {
                      Some(d) => d.configurable
                      None => false
                    }
                }
                let final_getter = match new_getter {
                  Some(v) =>
                    match v {
                      Undefined => None
                      _ => Some(v)
                    }
                  None =>
                    match existing_desc {
                      Some(d) => d.getter
                      None => None
                    }
                }
                let final_setter = match new_setter {
                  Some(v) =>
                    match v {
                      Undefined => None
                      _ => Some(v)
                    }
                  None =>
                    match existing_desc {
                      Some(d) => d.setter
                      None => None
                    }
                }
                data.bag.descriptors[prop_name] = {
                  writable: false,
                  enumerable,
                  configurable,
                  getter: final_getter,
                  setter: final_setter,
                }
              } else {
                match new_desc_value {
                  Some(v) => data.bag.properties[prop_name] = v
                  None =>
                    if !data.bag.properties.contains(prop_name) {
                      data.bag.properties[prop_name] = Undefined
                    }
                }
                let writable = match new_writable {
                  Some(w) => w
                  None =>
                    match existing_desc {
                      Some(d) => d.writable
                      None => false
                    }
                }
                let enumerable = match new_enumerable {
                  Some(e) => e
                  None =>
                    match existing_desc {
                      Some(d) => d.enumerable
                      None => false
                    }
                }
                let configurable = match new_configurable {
                  Some(c) => c
                  None =>
                    match existing_desc {
                      Some(d) => d.configurable
                      None => false
                    }
                }
                data.bag.descriptors[prop_name] = {
                  writable,
                  enumerable,
                  configurable,
                  getter: None,
                  setter: None,
                }
              }
            }
            _ =>
              // Per ES spec, ToPropertyDescriptor: if Obj is not an Object, throw TypeError
              raise @errors.TypeError(
                message="Property description must be an object: " +
                  @runtime.to_js_string(desc_val),
              )
          }
        })
      (Value::Proxy(proxy_data), Object(desc_obj)) =>
        // Handle defineProperties on Proxy targets by delegating to target
        match proxy_data.target {
          Some(Object(data)) =>
            desc_obj.bag.properties.each(fn(prop_name, desc_val) raise {
              let desc_enumerable = match
                desc_obj.bag.descriptors.get(prop_name) {
                Some(d) => d.enumerable
                None => true
              }
              if !desc_enumerable {
                return
              }
              match desc_val {
                Object(desc) => {
                  let has_get = desc.bag.properties.contains("get")
                  let has_set = desc.bag.properties.contains("set")
                  let has_value = desc.bag.properties.contains("value")
                  let has_writable = desc.bag.properties.contains("writable")
                  let is_accessor = has_get || has_set
                  let is_data = has_value || has_writable
                  if is_accessor && is_data {
                    raise @errors.TypeError(
                      message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
                    )
                  }
                  // Extensibility check
                  let prop_exists = data.bag.properties.contains(prop_name) ||
                    data.bag.descriptors.contains(prop_name)
                  if !prop_exists && !data.extensible {
                    raise @errors.TypeError(
                      message="Cannot add property \{prop_name}, object is not extensible",
                    )
                  }
                  // Non-configurable validation
                  match data.bag.descriptors.get(prop_name) {
                    Some(existing) =>
                      @runtime.validate_non_configurable(
                        existing,
                        prop_name,
                        is_accessor,
                        is_data,
                        has_value,
                        match desc.bag.properties.get("writable") {
                          Some(v) => Some(@runtime.is_truthy(v))
                          None => None
                        },
                        match desc.bag.properties.get("enumerable") {
                          Some(v) => Some(@runtime.is_truthy(v))
                          None => None
                        },
                        match desc.bag.properties.get("configurable") {
                          Some(v) => Some(@runtime.is_truthy(v))
                          None => None
                        },
                        match desc.bag.properties.get("get") {
                          Some(v) => Some(v)
                          None => None
                        },
                        match desc.bag.properties.get("set") {
                          Some(v) => Some(v)
                          None => None
                        },
                        fn() {
                          match data.bag.properties.get(prop_name) {
                            Some(v) => v
                            None => Undefined
                          }
                        },
                        fn() {
                          match desc.bag.properties.get("value") {
                            Some(v) => Some(v)
                            None => None
                          }
                        },
                      )
                    None => ()
                  }
                  if is_accessor {
                    // Accessor descriptor
                    if !data.bag.properties.contains(prop_name) {
                      data.bag.properties[prop_name] = Undefined
                    }
                    let getter : Value? = match desc.bag.properties.get("get") {
                      Some(v) =>
                        match v {
                          Undefined => None
                          _ => Some(v)
                        }
                      None => None
                    }
                    let setter : Value? = match desc.bag.properties.get("set") {
                      Some(v) =>
                        match v {
                          Undefined => None
                          _ => Some(v)
                        }
                      None => None
                    }
                    // Validate getter/setter are callable
                    match getter {
                      Some(Object(g)) =>
                        if g.callable is None {
                          raise @errors.TypeError(
                            message="Getter must be a function: [object Object]",
                          )
                        }
                      Some(Undefined) | None => ()
                      Some(_) =>
                        raise @errors.TypeError(
                          message="Getter must be a function: \{getter.unwrap().to_string()}",
                        )
                    }
                    match setter {
                      Some(Object(s)) =>
                        if s.callable is None {
                          raise @errors.TypeError(
                            message="Setter must be a function: [object Object]",
                          )
                        }
                      Some(Undefined) | None => ()
                      Some(_) =>
                        raise @errors.TypeError(
                          message="Setter must be a function: \{setter.unwrap().to_string()}",
                        )
                    }
                    let enumerable = match
                      desc.bag.properties.get("enumerable") {
                      Some(v) => @runtime.is_truthy(v)
                      None => false
                    }
                    let configurable = match
                      desc.bag.properties.get("configurable") {
                      Some(v) => @runtime.is_truthy(v)
                      None => false
                    }
                    data.bag.descriptors[prop_name] = {
                      writable: false,
                      enumerable,
                      configurable,
                      getter,
                      setter,
                    }
                  } else {
                    // Data descriptor
                    if has_value {
                      data.bag.properties[prop_name] = match
                        desc.bag.properties.get("value") {
                        Some(v) => v
                        None => Undefined
                      }
                    } else if !data.bag.properties.contains(prop_name) {
                      data.bag.properties[prop_name] = Undefined
                    }
                    let writable = match desc.bag.properties.get("writable") {
                      Some(v) => @runtime.is_truthy(v)
                      None => false
                    }
                    let enumerable = match
                      desc.bag.properties.get("enumerable") {
                      Some(v) => @runtime.is_truthy(v)
                      None => false
                    }
                    let configurable = match
                      desc.bag.properties.get("configurable") {
                      Some(v) => @runtime.is_truthy(v)
                      None => false
                    }
                    data.bag.descriptors[prop_name] = {
                      writable,
                      enumerable,
                      configurable,
                      getter: None,
                      setter: None,
                    }
                  }
                }
                _ => ()
              }
            })
          Some(_) => ()
          None =>
            raise @errors.TypeError(
              message="Cannot perform 'defineProperty' on a proxy that has been revoked",
            )
        }
      (Array(arr_data), Object(desc_obj)) =>
        // Handle defineProperties on Array targets
        desc_obj.bag.properties.each(fn(prop_name, desc_val) raise {
          let desc_enumerable = match desc_obj.bag.descriptors.get(prop_name) {
            Some(d) => d.enumerable
            None => true
          }
          if !desc_enumerable {
            return
          }
          match desc_val {
            Object(desc) =>
              if prop_name == "length" {
                match desc.bag.properties.get("value") {
                  Some(val) => {
                    let n = @runtime.to_number(val)
                    let new_len = n.to_int()
                    if new_len < 0 || new_len.to_double() != n || n.is_nan() {
                      raise @errors.RangeError(message="Invalid array length")
                    }
                    while arr_data.elements.length() > new_len {
                      let _removed = arr_data.elements.pop()
                    }
                    while arr_data.elements.length() < new_len {
                      arr_data.elements.push(Undefined)
                    }
                  }
                  None => ()
                }
              } else {
                let idx = @string.parse_int(prop_name) catch { _ => -1 }
                if idx >= 0 && idx.to_string() == prop_name {
                  // Only write value if descriptor specifies one
                  match desc.bag.properties.get("value") {
                    Some(v) => {
                      while arr_data.elements.length() <= idx {
                        arr_data.elements.push(Undefined)
                      }
                      arr_data.elements[idx] = v
                    }
                    None => ()
                  }
                }
              }
            _ => ()
          }
        })
      _ => ()
    }
    obj
  })
}

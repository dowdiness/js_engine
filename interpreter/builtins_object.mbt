///|
/// ToObject (ES spec 7.1.13): convert primitives to their wrapper objects.
/// Throws TypeError for null/undefined. Objects/Arrays/etc pass through unchanged.
fn to_object(val : Value, interp : Interpreter) -> Value raise Error {
  match val {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => val
    String_(s) => {
      let string_proto = interp.global.get("[[StringPrototype]]") catch {
        _ => Null
      }
      let props : Map[String, Value] = {}
      props["[[StringData]]"] = String_(s)
      props["length"] = Number(s.length().to_double())
      let chars = s.to_array()
      for i = 0; i < chars.length(); i = i + 1 {
        let buf = StringBuilder::new()
        buf.write_char(chars[i])
        props[i.to_string()] = String_(buf.to_string())
      }
      let descs : Map[String, PropDescriptor] = {}
      descs["length"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      }
      for i = 0; i < chars.length(); i = i + 1 {
        descs[i.to_string()] = {
          writable: false,
          enumerable: true,
          configurable: false,
          getter: None,
          setter: None,
        }
      }
      Object({
        properties: props,
        symbol_properties: {},
        prototype: string_proto,
        callable: None,
        class_name: "String",
        descriptors: descs,
        symbol_descriptors: {},
        extensible: true,
      })
    }
    Number(n) => {
      let number_proto = interp.global.get("[[NumberPrototype]]") catch {
        _ => Null
      }
      Object({
        properties: { "[[NumberData]]": Number(n) },
        symbol_properties: {},
        prototype: number_proto,
        callable: None,
        class_name: "Number",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
    Bool(b) => {
      let boolean_proto = interp.global.get("[[BooleanPrototype]]") catch {
        _ => Null
      }
      Object({
        properties: { "[[BooleanData]]": Bool(b) },
        symbol_properties: {},
        prototype: boolean_proto,
        callable: None,
        class_name: "Boolean",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
    Symbol(_) => {
      let symbol_proto = interp.global.get("[[SymbolPrototype]]") catch {
        _ => Null
      }
      Object({
        properties: { "[[SymbolData]]": val },
        symbol_properties: {},
        prototype: symbol_proto,
        callable: None,
        class_name: "Symbol",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
  }
}

///|
fn validate_accessor(value : Value?, label : String) -> Unit raise Error {
  match value {
    Some(Object(o)) =>
      if o.callable is None {
        raise @errors.TypeError(
          message="\{label} must be a function: [object Object]",
        )
      }
    Some(Undefined) | None => ()
    Some(v) =>
      raise @errors.TypeError(
        message="\{label} must be a function: \{v.to_string()}",
      )
  }
}

///|
/// Get a property from a Value by walking the prototype chain (like [[Get]])
fn get_value_property(val : Value, key : String) -> (Bool, Value) {
  match val {
    Object(data) => {
      match data.properties.get(key) {
        Some(v) => {
          // Check for accessor descriptor
          match data.descriptors.get(key) {
            Some(desc) =>
              match desc.getter {
                Some(_) => (true, Undefined) // accessor, but can't call getter without interp
                None => (true, v)
              }
            None => (true, v)
          }
        }
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) =>
                match proto_data.properties.get(key) {
                  Some(v) => {
                    match proto_data.descriptors.get(key) {
                      Some(desc) =>
                        match desc.getter {
                          Some(_) => return (true, Undefined)
                          None => return (true, v)
                        }
                      None => return (true, v)
                    }
                  }
                  None => current = proto_data.prototype
                }
              _ => break
            }
          }
          (false, Undefined)
        }
      }
    }
    _ => (false, Undefined)
  }
}

///|
fn apply_property_descriptor(
  data : ObjectData,
  prop_name : String,
  desc : ObjectData,
) -> Unit raise Error {
  // Per spec ToPropertyDescriptor, use [[Get]] which walks prototype chain
  let desc_val = Object(desc)
  let (has_get, _) = get_value_property(desc_val, "get")
  let (has_set, _) = get_value_property(desc_val, "set")
  let is_accessor = has_get || has_set
  let (has_value, _) = get_value_property(desc_val, "value")
  let (has_writable, _) = get_value_property(desc_val, "writable")
  let is_data = has_value || has_writable
  if is_accessor && is_data {
    raise @errors.TypeError(
      message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
    )
  }
  if is_accessor {
    if not(data.properties.contains(prop_name)) {
      data.properties[prop_name] = Undefined
    }
    let getter : Value? = match get_value_property(desc_val, "get") {
      (true, Undefined) => None
      (true, v) => Some(v)
      _ => None
    }
    let setter : Value? = match get_value_property(desc_val, "set") {
      (true, Undefined) => None
      (true, v) => Some(v)
      _ => None
    }
    validate_accessor(getter, "Getter")
    validate_accessor(setter, "Setter")
    let enumerable = match get_value_property(desc_val, "enumerable") {
      (true, v) => is_truthy(v)
      _ => false
    }
    let configurable = match get_value_property(desc_val, "configurable") {
      (true, v) => is_truthy(v)
      _ => false
    }
    data.descriptors[prop_name] = {
      writable: false,
      enumerable,
      configurable,
      getter,
      setter,
    }
  } else {
    match get_value_property(desc_val, "value") {
      (true, v) => data.properties[prop_name] = v
      _ =>
        if not(data.properties.contains(prop_name)) {
          data.properties[prop_name] = Undefined
        }
    }
    let writable = match get_value_property(desc_val, "writable") {
      (true, v) => is_truthy(v)
      _ => false
    }
    let enumerable = match get_value_property(desc_val, "enumerable") {
      (true, v) => is_truthy(v)
      _ => false
    }
    let configurable = match get_value_property(desc_val, "configurable") {
      (true, v) => is_truthy(v)
      _ => false
    }
    data.descriptors[prop_name] = {
      writable,
      enumerable,
      configurable,
      getter: None,
      setter: None,
    }
  }
}

///|
pub fn setup_object_builtins(env : Environment) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // Object.keys, Object.values, Object.entries, Object.create, Object.assign,
  // Object.getPrototypeOf, Object.getOwnPropertyNames
  let obj_proto_props : Map[String, Value] = {}
  obj_proto_props["toString"] = make_method_func("toString", 0, fn(this_val, _args) raise {
    match this_val {
      Undefined => String_("[object Undefined]")
      Null => String_("[object Null]")
      Bool(_) => String_("[object Boolean]")
      Number(_) => String_("[object Number]")
      String_(_) => String_("[object String]")
      Array(_) => String_("[object Array]")
      Symbol(_) => String_("[object Symbol]")
      Map(_) => String_("[object Map]")
      Set(_) => String_("[object Set]")
      Promise(_) => String_("[object Promise]")
      Proxy(_) => String_("[object Object]")
      Object(data) => {
        // Per spec, always check Symbol.toStringTag first (it overrides built-in tags)
        let tag = get_tostringtag_value(data)
        match tag {
          Some(t) => String_("[object \{t}]")
          None =>
            if data.class_name == "Function" {
              String_("[object Function]")
            } else if data.class_name == "RegExp" {
              String_("[object RegExp]")
            } else if data.class_name == "Error" ||
              data.class_name == "TypeError" ||
              data.class_name == "ReferenceError" ||
              data.class_name == "SyntaxError" ||
              data.class_name == "RangeError" ||
              data.class_name == "URIError" ||
              data.class_name == "EvalError" ||
              data.class_name == "AggregateError" {
              String_("[object Error]")
            } else if data.class_name == "Date" {
              String_("[object Date]")
            } else if data.class_name == "Map" {
              String_("[object Map]")
            } else if data.class_name == "Set" {
              String_("[object Set]")
            } else if data.class_name == "Promise" {
              String_("[object Promise]")
            } else if data.class_name == "Arguments" {
              String_("[object Arguments]")
            } else if data.class_name == "Number" {
              String_("[object Number]")
            } else if data.class_name == "String" {
              String_("[object String]")
            } else if data.class_name == "Boolean" {
              String_("[object Boolean]")
            } else {
              String_("[object Object]")
            }
        }
      }
    }
  })
  obj_proto_props["valueOf"] = make_interp_method_func("valueOf", 0, fn(interp, this_val, _args) raise {
        to_object(this_val, interp)
      })
  obj_proto_props["hasOwnProperty"] = make_method_func("hasOwnProperty", 1, fn(this_val, args) {
    // RequireObjectCoercible(this) - throw TypeError for null/undefined
    match this_val {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      _ => ()
    }
    let key_val = if args.length() > 0 { args[0] } else { Undefined }
    match this_val {
      Object(data) =>
        match key_val {
          Symbol(sym) => Bool(data.symbol_properties.contains(sym.id))
          _ => Bool(data.properties.contains(to_js_string(key_val)))
        }
      Array(data) =>
        match key_val {
          Symbol(sym) => Bool(get_array_symbol_prop(data, sym.id) is Some(_))
          _ => {
            let key = to_js_string(key_val)
            if key == "length" {
              Bool(true)
            } else {
              // Check numeric index
              let idx = @strconv.parse_int(key) catch { _ => -1 }
              if idx >= 0 && idx.to_string() == key && idx < data.elements.length() {
                Bool(true)
              } else {
                // Check named properties side-table
                Bool(get_array_named_prop(data, key) is Some(_))
              }
            }
          }
        }
      String_(s) => {
        let key = to_js_string(key_val)
        if key == "length" {
          Bool(true)
        } else {
          let idx = @strconv.parse_int(key) catch { _ => -1 }
          Bool(idx >= 0 && idx.to_string() == key && idx < s.length())
        }
      }
      _ => Bool(false)
    }
  })
  obj_proto_props["propertyIsEnumerable"] = make_method_func("propertyIsEnumerable", 1, fn(this_val, args) {
    // RequireObjectCoercible(this) - throw TypeError for null/undefined
    match this_val {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      _ => ()
    }
    let key_val = if args.length() > 0 { args[0] } else { Undefined }
    // Handle Symbol keys
    match key_val {
      Symbol(sym) =>
        match this_val {
          Object(data) =>
            match data.symbol_descriptors.get(sym.id) {
              Some(d) => return Bool(d.enumerable)
              None =>
                if data.symbol_properties.contains(sym.id) {
                  return Bool(true)
                } else {
                  return Bool(false)
                }
            }
          _ => return Bool(false)
        }
      _ => ()
    }
    let key = to_js_string(key_val)
    match this_val {
      Object(data) =>
        if data.properties.contains(key) {
          match data.descriptors.get(key) {
            Some(d) => Bool(d.enumerable)
            None => Bool(true)
          }
        } else {
          Bool(false)
        }
      Array(data) =>
        if key == "length" {
          Bool(false) // length is not enumerable
        } else {
          let idx = @strconv.parse_int(key) catch { _ => -1 }
          Bool(
            idx >= 0 &&
            idx.to_string() == key &&
            idx < data.elements.length(),
          )
        }
      String_(s) =>
        if key == "length" {
          Bool(false)
        } else {
          let idx = @strconv.parse_int(key) catch { _ => -1 }
          Bool(idx >= 0 && idx.to_string() == key && idx < s.length())
        }
      _ => Bool(false)
    }
  })
  obj_proto_props["isPrototypeOf"] = make_method_func("isPrototypeOf", 1, fn(this_val, args) {
    // RequireObjectCoercible(this) - throw TypeError for null/undefined
    match this_val {
      Null | Undefined =>
        raise @errors.TypeError(
          message="Cannot convert undefined or null to object",
        )
      _ => ()
    }
    // Walk the argument's prototype chain looking for this_val
    let arg = if args.length() > 0 { args[0] } else { Undefined }
    let mut current : Value = match arg {
      Object(data) => data.prototype
      Array(_) =>
        match current_interpreter.val {
          Some(interp) =>
            get_constructor_prototype(interp.global, "Array")
          None => Null
        }
      Promise(_) => Null
      _ => return Bool(false)
    }
    while true {
      match current {
        Null | Undefined => return Bool(false)
        Object(proto_data) => {
          // Compare by reference identity - check if this_val is the same object
          match this_val {
            Object(this_data) =>
              if physical_equal(this_data, proto_data) {
                return Bool(true)
              }
            _ => ()
          }
          current = proto_data.prototype
        }
        _ => return Bool(false)
      }
    }
    Bool(false)
  })
  obj_proto_props["toLocaleString"] = make_method_func("toLocaleString", 0, fn(this_val, _args) raise {
    match this_val {
      Object(data) =>
        match data.properties.get("toString") {
          Some(Object(fn_data)) =>
            match fn_data.callable {
              Some(MethodCallable(_, f)) => f(this_val, [])
              _ => String_(this_val.to_string())
            }
          _ => String_(this_val.to_string())
        }
      _ => String_(this_val.to_string())
    }
  })
  // Annex B: __defineGetter__, __defineSetter__, __lookupGetter__, __lookupSetter__
  obj_proto_props["__defineGetter__"] = make_interp_method_func("__defineGetter__", 2, fn(interp, this_val, args) raise {
    let o = to_object(this_val, interp)
    let getter = if args.length() > 1 { args[1] } else { Undefined }
    if not(is_callable(getter)) {
      raise @errors.TypeError(message="getter must be a function")
    }
    let prop = if args.length() > 0 { to_js_string(args[0]) } else { "" }
    match o {
      Object(data) => {
        // Check if property exists and is non-configurable
        match data.descriptors.get(prop) {
          Some(d) =>
            if not(d.configurable) {
              raise @errors.TypeError(
                message="Cannot redefine property: \{prop}",
              )
            }
          None => ()
        }
        if not(data.extensible) && not(data.properties.contains(prop)) {
          raise @errors.TypeError(
            message="Cannot define property on a non-extensible object",
          )
        }
        let existing_setter : Value? = match data.descriptors.get(prop) {
          Some(d) => d.setter
          None => None
        }
        data.descriptors[prop] = {
          writable: false, enumerable: true, configurable: true,
          getter: Some(getter), setter: existing_setter,
        }
        data.properties[prop] = Undefined
      }
      _ => ()
    }
    Undefined
  })
  obj_proto_props["__defineSetter__"] = make_interp_method_func("__defineSetter__", 2, fn(interp, this_val, args) raise {
    let o = to_object(this_val, interp)
    let setter = if args.length() > 1 { args[1] } else { Undefined }
    if not(is_callable(setter)) {
      raise @errors.TypeError(message="setter must be a function")
    }
    let prop = if args.length() > 0 { to_js_string(args[0]) } else { "" }
    match o {
      Object(data) => {
        match data.descriptors.get(prop) {
          Some(d) =>
            if not(d.configurable) {
              raise @errors.TypeError(
                message="Cannot redefine property: \{prop}",
              )
            }
          None => ()
        }
        if not(data.extensible) && not(data.properties.contains(prop)) {
          raise @errors.TypeError(
            message="Cannot define property on a non-extensible object",
          )
        }
        let existing_getter : Value? = match data.descriptors.get(prop) {
          Some(d) => d.getter
          None => None
        }
        data.descriptors[prop] = {
          writable: false, enumerable: true, configurable: true,
          getter: existing_getter, setter: Some(setter),
        }
        data.properties[prop] = Undefined
      }
      _ => ()
    }
    Undefined
  })
  obj_proto_props["__lookupGetter__"] = make_interp_method_func("__lookupGetter__", 1, fn(interp, this_val, args) raise {
    let prop = if args.length() > 0 { to_js_string(args[0]) } else { "" }
    let mut current = to_object(this_val, interp)
    while true {
      match current {
        Object(data) => {
          match data.descriptors.get(prop) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return getter
                None => ()
              }
            None => ()
          }
          current = data.prototype
        }
        _ => break
      }
    }
    Undefined
  })
  obj_proto_props["__lookupSetter__"] = make_interp_method_func("__lookupSetter__", 1, fn(interp, this_val, args) raise {
    let prop = if args.length() > 0 { to_js_string(args[0]) } else { "" }
    let mut current = to_object(this_val, interp)
    while true {
      match current {
        Object(data) => {
          match data.descriptors.get(prop) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => return setter
                None => ()
              }
            None => ()
          }
          current = data.prototype
        }
        _ => break
      }
    }
    Undefined
  })
  let obj_proto_descs : Map[String, PropDescriptor] = {}
  let obj_method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  obj_proto_descs["toString"] = obj_method_desc
  obj_proto_descs["valueOf"] = obj_method_desc
  obj_proto_descs["hasOwnProperty"] = obj_method_desc
  obj_proto_descs["propertyIsEnumerable"] = obj_method_desc
  obj_proto_descs["isPrototypeOf"] = obj_method_desc
  obj_proto_descs["toLocaleString"] = obj_method_desc
  obj_proto_descs["__defineGetter__"] = obj_method_desc
  obj_proto_descs["__defineSetter__"] = obj_method_desc
  obj_proto_descs["__lookupGetter__"] = obj_method_desc
  obj_proto_descs["__lookupSetter__"] = obj_method_desc
  let obj_proto : Value = Object({
    properties: obj_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: obj_proto_descs,
    symbol_descriptors: {},
    extensible: true,
  })
  // Store Object.prototype so plain objects {} can link to it
  env.def_builtin("[[ObjectPrototype]]", obj_proto)
  env.def_builtin(
    "Object",
    Object({
      properties: {
        "prototype": obj_proto,
        "name": String_("Object"),
        "length": Number(1.0),
        "keys": make_static_func_with_length("keys", 1, fn(args) raise {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(data) => {
              let keys : Array[Value] = []
              let sorted = sort_property_keys(data.properties)
              for k in sorted {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  keys.push(String_(k))
                }
              }
              Array({ elements: keys })
            }
            String_(s) => {
              // String objects have enumerable indexed properties
              let keys : Array[Value] = []
              let len = s.length()
              for i = 0; i < len; i = i + 1 {
                keys.push(String_(i.to_string()))
              }
              Array({ elements: keys })
            }
            Array(data) => {
              // Array objects have enumerable indexed properties
              let keys : Array[Value] = []
              for i = 0; i < data.elements.length(); i = i + 1 {
                keys.push(String_(i.to_string()))
              }
              Array({ elements: keys })
            }
            _ => Array({ elements: [] })
          }
        }),
        "values": make_static_func_with_length("values", 1, fn(args) raise {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(data) => {
              let vals : Array[Value] = []
              let sorted = sort_property_keys(data.properties)
              for k in sorted {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  match data.properties.get(k) {
                    Some(v) => vals.push(v)
                    None => ()
                  }
                }
              }
              Array({ elements: vals })
            }
            String_(s) => {
              // String objects have enumerable indexed properties
              let vals : Array[Value] = []
              let chars = s.to_array()
              for ch in chars {
                vals.push(String_(ch.to_string()))
              }
              Array({ elements: vals })
            }
            Array(data) => {
              // Array objects - return array elements (defensive copy)
              let vals : Array[Value] = []
              for elem in data.elements {
                vals.push(elem)
              }
              Array({ elements: vals })
            }
            _ => Array({ elements: [] })
          }
        }),
        "entries": make_static_func_with_length("entries", 1, fn(args) raise {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(data) => {
              let entries : Array[Value] = []
              let sorted = sort_property_keys(data.properties)
              for k in sorted {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  match data.properties.get(k) {
                    Some(v) => entries.push(Array({ elements: [String_(k), v] }))
                    None => ()
                  }
                }
              }
              Array({ elements: entries })
            }
            String_(s) => {
              // String objects have enumerable indexed properties
              let entries : Array[Value] = []
              let chars = s.to_array()
              for i = 0; i < chars.length(); i = i + 1 {
                entries.push(
                  Array({
                    elements: [
                      String_(i.to_string()),
                      String_(chars[i].to_string()),
                    ],
                  }),
                )
              }
              Array({ elements: entries })
            }
            Array(data) => {
              // Array objects - keys must be strings per spec
              let entries : Array[Value] = []
              for i = 0; i < data.elements.length(); i = i + 1 {
                entries.push(
                  Array({ elements: [String_(i.to_string()), data.elements[i]] }),
                )
              }
              Array({ elements: entries })
            }
            _ => Array({ elements: [] })
          }
        }),
        "create": make_static_func_with_length("create", 2, fn(args) raise {
          let proto = if args.length() > 0 { args[0] } else { Null }
          // Per spec, first argument must be Object or null
          match proto {
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) | Null => ()
            _ =>
              raise @errors.TypeError(
                message="Object prototype may only be an Object or null: " +
                  type_of(proto),
              )
          }
          let obj = Object({
            properties: {},
            symbol_properties: {},
            prototype: proto,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
          // Handle optional second argument (property descriptors)
          if args.length() > 1 {
            match args[1] {
              Undefined => ()
              // Per ECMAScript spec, only Object with properties field accepted
              // Arrays, Maps, Sets don't have properties field in our implementation
              Proxy(proxy_data) =>
                // Unwrap Proxy and use target's properties as descriptors
                match proxy_data.target {
                  Some(Object(desc_obj)) =>
                    match obj {
                      Object(data) =>
                        desc_obj.properties.each(fn(prop_name, desc_val) raise {
                          match desc_val {
                            Object(desc) =>
                              apply_property_descriptor(data, prop_name, desc)
                            _ => ()
                          }
                        })
                      _ => ()
                    }
                  _ =>
                    raise @errors.TypeError(
                      message="Property descriptors must be an object",
                    )
                }
              Null
              | String_(_)
              | Number(_)
              | Bool(_)
              | Symbol(_)
              | Array(_)
              | Map(_)
              | Set(_) =>
                raise @errors.TypeError(
                  message="Property descriptors must be an object",
                )
              Object(desc_obj) =>
                match obj {
                  Object(data) =>
                    desc_obj.properties.each(fn(prop_name, desc_val) raise {
                      match desc_val {
                        Object(desc) =>
                          apply_property_descriptor(data, prop_name, desc)
                        _ => ()
                      }
                    })
                  _ => ()
                }
              Promise(desc_obj) =>
                match obj {
                  Object(data) =>
                    desc_obj.properties.each(fn(prop_name, desc_val) raise {
                      match desc_val {
                        Object(desc) =>
                          apply_property_descriptor(data, prop_name, desc)
                        _ => ()
                      }
                    })
                  _ => ()
                }
            }
          }
          obj
        }),
        "assign": make_static_func_with_length("assign", 2, fn(args) raise {
          let raw_target = if args.length() > 0 { args[0] } else { Undefined }
          // Step 1: ToObject(target) — throw for null/undefined, wrap primitives
          let target : Value = match raw_target {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
              raw_target
            Number(_) =>
              Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Number",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            Bool(_) =>
              Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Boolean",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            String_(s) => {
              let props : Map[String, Value] = {}
              props["length"] = Number(s.length().to_double())
              let chars = s.to_array()
              for i = 0; i < chars.length(); i = i + 1 {
                let buf = StringBuilder::new()
                buf.write_char(chars[i])
                props[i.to_string()] = String_(buf.to_string())
              }
              Object({
                properties: props,
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "String",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
            Symbol(_) =>
              Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Symbol",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
          }
          match target {
            Object(data) => {
              for i = 1; i < args.length(); i = i + 1 {
                match args[i] {
                  // ToObject conversion: skip null and undefined
                  Null | Undefined => ()
                  // ToObject conversion: String primitives enumerate characters
                  String_(s) => {
                    let chars = s.to_array()
                    for idx = 0; idx < chars.length(); idx = idx + 1 {
                      let k = idx.to_string()
                      let v = String_(chars[idx].to_string())
                      // Check writable on target property
                      let can_write = match data.descriptors.get(k) {
                        Some(d) => d.writable
                        None => true
                      }
                      let exists = data.properties.contains(k)
                      if not(can_write) {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only property '\{k}'",
                        )
                      }
                      if not(exists) && not(data.extensible) {
                        raise @errors.TypeError(
                          message="Cannot add property '\{k}' to non-extensible object",
                        )
                      }
                      data.properties[k] = v
                    }
                  }
                  // ToObject conversion: Arrays enumerate elements as indexed properties
                  Array(src) =>
                    // Copy array elements as indexed properties
                    for idx = 0; idx < src.elements.length(); idx = idx + 1 {
                      let k = idx.to_string()
                      let v = src.elements[idx]
                      let can_write = match data.descriptors.get(k) {
                        Some(d) => d.writable
                        None => true
                      }
                      let exists = data.properties.contains(k)
                      if not(can_write) {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only property '\{k}'",
                        )
                      }
                      if not(exists) && not(data.extensible) {
                        raise @errors.TypeError(
                          message="Cannot add property '\{k}' to non-extensible object",
                        )
                      }
                      data.properties[k] = v
                    }
                  // Regular objects have properties and descriptors
                  Object(src) => {
                    // Copy enumerable string properties
                    src.properties.each(fn(k, v) raise {
                      let enumerable = match src.descriptors.get(k) {
                        Some(d) => d.enumerable
                        None => true
                      }
                      if enumerable {
                        // Check writable on target property
                        let can_write = match data.descriptors.get(k) {
                          Some(d) => d.writable
                          None => true
                        }
                        // Check extensibility if property doesn't exist
                        let exists = data.properties.contains(k)
                        // Per ECMAScript spec, Object.assign throws TypeError on Set failure
                        if not(can_write) {
                          raise @errors.TypeError(
                            message="Cannot assign to read-only property '\{k}'",
                          )
                        }
                        if not(exists) && not(data.extensible) {
                          raise @errors.TypeError(
                            message="Cannot add property '\{k}' to non-extensible object",
                          )
                        }
                        data.properties[k] = v
                      }
                    })
                    // Copy enumerable symbol properties
                    src.symbol_properties.each(fn(sym_id, v) raise {
                      let enumerable = match
                        src.symbol_descriptors.get(sym_id) {
                        Some(d) => d.enumerable
                        None => true
                      }
                      if enumerable {
                        // Check writable on target property
                        let can_write = match
                          data.symbol_descriptors.get(sym_id) {
                          Some(d) => d.writable
                          None => true
                        }
                        // Check extensibility if property doesn't exist
                        let exists = data.symbol_properties.contains(sym_id)
                        // Per ECMAScript spec, Object.assign throws TypeError on Set failure
                        if not(can_write) {
                          raise @errors.TypeError(
                            message="Cannot assign to read-only symbol property",
                          )
                        }
                        if not(exists) && not(data.extensible) {
                          raise @errors.TypeError(
                            message="Cannot add symbol property to non-extensible object",
                          )
                        }
                        data.symbol_properties[sym_id] = v
                      }
                    })
                  }
                  // Promises have properties but no descriptors
                  Promise(src) => {
                    // Copy all string properties (no descriptors to check)
                    src.properties.each(fn(k, v) raise {
                      let can_write = match data.descriptors.get(k) {
                        Some(d) => d.writable
                        None => true
                      }
                      let exists = data.properties.contains(k)
                      if not(can_write) {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only property '\{k}'",
                        )
                      }
                      if not(exists) && not(data.extensible) {
                        raise @errors.TypeError(
                          message="Cannot add property '\{k}' to non-extensible object",
                        )
                      }
                      data.properties[k] = v
                    })
                    // Copy symbol properties
                    src.symbol_properties.each(fn(sym_id, v) raise {
                      let can_write = match
                        data.symbol_descriptors.get(sym_id) {
                        Some(d) => d.writable
                        None => true
                      }
                      let exists = data.symbol_properties.contains(sym_id)
                      if not(can_write) {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only symbol property",
                        )
                      }
                      if not(exists) && not(data.extensible) {
                        raise @errors.TypeError(
                          message="Cannot add symbol property to non-extensible object",
                        )
                      }
                      data.symbol_properties[sym_id] = v
                    })
                  }
                  // Proxy sources: unwrap to target and copy enumerable properties
                  Proxy(proxy_data) =>
                    match proxy_data.target {
                      Some(target) =>
                        match target {
                          Object(src) => {
                            src.properties.each(fn(k, v) raise {
                              let enumerable = match src.descriptors.get(k) {
                                Some(d) => d.enumerable
                                None => true
                              }
                              if enumerable {
                                let can_write = match data.descriptors.get(k) {
                                  Some(d) => d.writable
                                  None => true
                                }
                                let exists = data.properties.contains(k)
                                if not(can_write) {
                                  raise @errors.TypeError(
                                    message="Cannot assign to read-only property '\{k}'",
                                  )
                                }
                                if not(exists) && not(data.extensible) {
                                  raise @errors.TypeError(
                                    message="Cannot add property '\{k}' to non-extensible object",
                                  )
                                }
                                data.properties[k] = v
                              }
                            })
                            // Copy enumerable symbol properties from Proxy target
                            src.symbol_properties.each(fn(sym_id, v) raise {
                              let enumerable = match
                                src.symbol_descriptors.get(sym_id) {
                                Some(d) => d.enumerable
                                None => true
                              }
                              if enumerable {
                                let can_write = match
                                  data.symbol_descriptors.get(sym_id) {
                                  Some(d) => d.writable
                                  None => true
                                }
                                let exists = data.symbol_properties.contains(
                                  sym_id,
                                )
                                if not(can_write) {
                                  raise @errors.TypeError(
                                    message="Cannot assign to read-only symbol property",
                                  )
                                }
                                if not(exists) && not(data.extensible) {
                                  raise @errors.TypeError(
                                    message="Cannot add symbol property to non-extensible object",
                                  )
                                }
                                data.symbol_properties[sym_id] = v
                              }
                            })
                          }
                          _ => ()
                        }
                      None =>
                        raise @errors.TypeError(
                          message="Cannot perform 'ownKeys' on a proxy that has been revoked",
                        )
                    }
                  // ToObject conversion: Map, Set, Number, Bool, Symbol have no enumerable own string properties
                  Map(_) | Set(_) | Number(_) | Bool(_) | Symbol(_) => ()
                }
              }
              target
            }
            _ => target
          }
        }),
        "getPrototypeOf": make_static_func_with_length("getPrototypeOf", 1, fn(args) raise {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          fn get_ctor_proto(name : String) -> Value {
            let ctor = env.get(name) catch { _ => return Null }
            match ctor {
              Object(ctor_data) =>
                match ctor_data.properties.get("prototype") {
                  Some(proto) => proto
                  None => Null
                }
              _ => Null
            }
          }
          match obj {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(data) => data.prototype
            Array(_) => get_ctor_proto("Array")
            String_(_) => get_ctor_proto("String")
            Number(_) => get_ctor_proto("Number")
            Bool(_) => get_ctor_proto("Boolean")
            Symbol(_) => get_ctor_proto("Symbol")
            Map(_) => get_ctor_proto("Map")
            Set(_) => get_ctor_proto("Set")
            Promise(_) => get_ctor_proto("Promise")
            Proxy(proxy_data) =>
              match proxy_data.target {
                Some(target) =>
                  match target {
                    Object(data) => data.prototype
                    _ => Null
                  }
                None =>
                  raise @errors.TypeError(
                    message="Cannot perform 'getPrototypeOf' on a proxy that has been revoked",
                  )
              }
            _ => Null
          }
        }),
        "getOwnPropertyNames": make_static_func_with_length("getOwnPropertyNames", 1, fn(
          args,
        ) raise {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(data) => {
              let keys : Array[Value] = []
              let sorted = sort_property_keys(data.properties)
              for k in sorted {
                keys.push(String_(k))
              }
              Array({ elements: keys })
            }
            Array(data) => {
              let keys : Array[Value] = []
              for i = 0; i < data.elements.length(); i = i + 1 {
                keys.push(String_(i.to_string()))
              }
              keys.push(String_("length"))
              Array({ elements: keys })
            }
            String_(s) => {
              let keys : Array[Value] = []
              let chars = s.to_array()
              for i = 0; i < chars.length(); i = i + 1 {
                keys.push(String_(i.to_string()))
              }
              keys.push(String_("length"))
              Array({ elements: keys })
            }
            _ => Array({ elements: [] })
          }
        }),
        "getOwnPropertySymbols": make_static_func_with_length("getOwnPropertySymbols", 1, fn(
          args,
        ) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              let symbols : Array[Value] = []
              data.symbol_properties.each(fn(sym_id, _val) {
                match get_symbol_by_id(sym_id) {
                  Some(sym_data) => symbols.push(Symbol(sym_data))
                  None => () // Symbol no longer exists (shouldn't happen)
                }
              })
              Array({ elements: symbols })
            }
            _ => Array({ elements: [] })
          }
        }),
        "getOwnPropertyDescriptors": make_static_func_with_length(
          "getOwnPropertyDescriptors",
          1,
          fn(args) {
            let obj = if args.length() > 0 { args[0] } else { Undefined }
            match obj {
              Object(data) => {
                let descriptors_props : Map[String, Value] = {}
                data.properties.each(fn(key, val) {
                  let desc = data.descriptors.get(key)
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
                    descriptors_props[key] = Object({
                      properties: {
                        "get": getter_val,
                        "set": setter_val,
                        "enumerable": Bool(enumerable),
                        "configurable": Bool(configurable),
                      },
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
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
                    descriptors_props[key] = Object({
                      properties: {
                        "value": val,
                        "writable": Bool(writable),
                        "enumerable": Bool(enumerable),
                        "configurable": Bool(configurable),
                      },
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                  }
                })
                // Also include symbol-keyed property descriptors
                let sym_descs : Map[Int, Value] = {}
                data.symbol_properties.each(fn(sym_id, val) {
                  let desc = data.symbol_descriptors.get(sym_id)
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
                    sym_descs[sym_id] = Object({
                      properties: {
                        "get": getter_val,
                        "set": setter_val,
                        "enumerable": Bool(enumerable),
                        "configurable": Bool(configurable),
                      },
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
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
                    sym_descs[sym_id] = Object({
                      properties: {
                        "value": val,
                        "writable": Bool(writable),
                        "enumerable": Bool(enumerable),
                        "configurable": Bool(configurable),
                      },
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                  }
                })
                Object({
                  properties: descriptors_props,
                  symbol_properties: sym_descs,
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              }
              _ =>
                Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
            }
          },
        ),
        "defineProperty": make_static_func_with_length("defineProperty", 3, fn(args) raise {
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
              let interp = match current_interpreter.val {
                Some(i) => i
                None => abort("No interpreter")
              }
              let loc = @token.Loc::default()
              let desc_keys = [
                "value", "writable", "enumerable", "configurable", "get", "set",
              ]
              for key in desc_keys {
                // Use has_property to check if key exists (includes prototype chain)
                let has = has_property(descriptor, key)
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
            Some(v) => Some(is_truthy(v))
            None => None
          }
          let new_enumerable = match desc_props.get("enumerable") {
            Some(v) => Some(is_truthy(v))
            None => None
          }
          let new_configurable = match desc_props.get("configurable") {
            Some(v) => Some(is_truthy(v))
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
                Symbol(s) => s.id
                _ => 0
              }
              let prop_name = if is_symbol_key { "" } else { to_js_string(prop_val) }

              // Check if property exists (using symbol or string storage)
              let prop_exists = if is_symbol_key {
                data.symbol_properties.contains(sym_id)
              } else {
                data.properties.contains(prop_name)
              }

              // Get existing descriptor
              let existing_desc : PropDescriptor? = if is_symbol_key {
                data.symbol_descriptors.get(sym_id)
              } else {
                data.descriptors.get(prop_name)
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
                  validate_non_configurable(
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
                        match data.symbol_properties.get(sym_id) {
                          Some(v) => v
                          None => Undefined
                        }
                      } else {
                        match data.properties.get(prop_name) {
                          Some(v) => v
                          None => Undefined
                        }
                      }
                    },
                    fn() { desc_props.get("value") },
                  )
                None =>
                  // Check extensibility when adding new property
                  if not(prop_exists) && not(data.extensible) {
                    raise @errors.TypeError(
                      message="Cannot add property \{prop_display}, object is not extensible",
                    )
                  }
              }
              if is_accessor {
                // Accessor descriptor
                // Set a placeholder in properties if not present
                if is_symbol_key {
                  if not(data.symbol_properties.contains(sym_id)) {
                    data.symbol_properties[sym_id] = Undefined
                  }
                } else if not(data.properties.contains(prop_name)) {
                  data.properties[prop_name] = Undefined
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
                  data.symbol_descriptors[sym_id] = final_desc
                } else {
                  data.descriptors[prop_name] = final_desc
                }
              } else {
                // Data descriptor
                // Set value
                match desc_props.get("value") {
                  Some(v) =>
                    if is_symbol_key {
                      data.symbol_properties[sym_id] = v
                    } else {
                      data.properties[prop_name] = v
                    }
                  None =>
                    if is_symbol_key {
                      if not(data.symbol_properties.contains(sym_id)) {
                        data.symbol_properties[sym_id] = Undefined
                      }
                    } else if not(data.properties.contains(prop_name)) {
                      data.properties[prop_name] = Undefined
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
                  data.symbol_descriptors[sym_id] = final_desc
                } else {
                  data.descriptors[prop_name] = final_desc
                }
              }
            }
            Array(arr_data) => {
              // Handle defineProperty on Array targets
              let handles_iterator_override = match prop_val {
                Symbol(sym) => sym.id == get_iterator_symbol().id
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
                  set_array_iterator_override(arr_data, getter, None)
                } else {
                  let value = match desc_props.get("value") {
                    Some(v) => v
                    None => Undefined
                  }
                  set_array_iterator_override(arr_data, None, Some(value))
                }
              } else {
                let prop_name = to_js_string(prop_val)
                if prop_name == "length" {
                  // Handle length property changes
                  match desc_props.get("value") {
                    Some(val) => {
                      let n = to_number(val)
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
                  let idx = @strconv.parse_int(prop_name) catch { _ => -1 }
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
            Promise(data) => {
              let prop_name = to_js_string(prop_val)
              let existing_desc = data.descriptors.get(prop_name)
              if is_accessor {
                if not(data.properties.contains(prop_name)) {
                  data.properties[prop_name] = Undefined
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
                data.descriptors[prop_name] = {
                  writable: false,
                  enumerable,
                  configurable,
                  getter,
                  setter,
                }
              } else {
                match desc_props.get("value") {
                  Some(v) => data.properties[prop_name] = v
                  None =>
                    if not(data.properties.contains(prop_name)) {
                      data.properties[prop_name] = Undefined
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
                data.descriptors[prop_name] = {
                  writable,
                  enumerable,
                  configurable,
                  getter: None,
                  setter: None,
                }
              }
            }
            Proxy(proxy_data) => {
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
                    Symbol(s) => s.id
                    _ => 0
                  }
                  let prop_name = to_js_string(prop_val)
                  let prop_exists = if is_symbol_key {
                    data.symbol_properties.contains(sym_id)
                  } else {
                    data.properties.contains(prop_name)
                  }
                  let existing_desc : PropDescriptor? = if is_symbol_key {
                    data.symbol_descriptors.get(sym_id)
                  } else {
                    data.descriptors.get(prop_name)
                  }
                  let prop_also_in_desc = if is_symbol_key {
                    data.symbol_descriptors.contains(sym_id)
                  } else {
                    data.descriptors.contains(prop_name)
                  }
                  if not(prop_exists) &&
                    not(prop_also_in_desc) &&
                    not(data.extensible) {
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
                      validate_non_configurable(
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
                            match data.symbol_properties.get(sym_id) {
                              Some(v) => v
                              None => Undefined
                            }
                          } else {
                            match data.properties.get(prop_name) {
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
                      if not(data.symbol_properties.contains(sym_id)) {
                        data.symbol_properties[sym_id] = Undefined
                      }
                    } else if not(data.properties.contains(prop_name)) {
                      data.properties[prop_name] = Undefined
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
                      data.symbol_descriptors[sym_id] = final_desc
                    } else {
                      data.descriptors[prop_name] = final_desc
                    }
                  } else {
                    match desc_props.get("value") {
                      Some(v) =>
                        if is_symbol_key {
                          data.symbol_properties[sym_id] = v
                        } else {
                          data.properties[prop_name] = v
                        }
                      None =>
                        if is_symbol_key {
                          if not(data.symbol_properties.contains(sym_id)) {
                            data.symbol_properties[sym_id] = Undefined
                          }
                        } else if not(data.properties.contains(prop_name)) {
                          data.properties[prop_name] = Undefined
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
                      data.symbol_descriptors[sym_id] = final_desc
                    } else {
                      data.descriptors[prop_name] = final_desc
                    }
                  }
                }
                _ => ()
              }
            }
            _ => ()
          }
          obj
        }),
        "getOwnPropertyDescriptor": make_static_func_with_length(
          "getOwnPropertyDescriptor",
          2,
          fn(args) raise {
            let obj = if args.length() > 0 { args[0] } else { Undefined }
            let prop_key = if args.length() > 1 { args[1] } else { Undefined }
            let is_symbol_key = prop_key is Symbol(_)
            let sym_id = match prop_key {
              Symbol(s) => s.id
              _ => 0
            }
            let prop_name = prop_key.to_string()
            fn make_desc(
              val : Value,
              writable : Bool,
              enumerable : Bool,
              configurable : Bool,
            ) -> Value {
              Object({
                properties: {
                  "value": val,
                  "writable": Bool(writable),
                  "enumerable": Bool(enumerable),
                  "configurable": Bool(configurable),
                },
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Object",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }

            fn make_accessor_desc(
              getter_val : Value,
              setter_val : Value,
              enumerable : Bool,
              configurable : Bool,
            ) -> Value {
              Object({
                properties: {
                  "get": getter_val,
                  "set": setter_val,
                  "enumerable": Bool(enumerable),
                  "configurable": Bool(configurable),
                },
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Object",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }

            match obj {
              Object(data) =>
                // Handle Symbol keys
                if is_symbol_key {
                  if data.symbol_properties.contains(sym_id) {
                    let val = match data.symbol_properties.get(sym_id) {
                      Some(v) => v
                      None => Undefined
                    }
                    let desc = data.symbol_descriptors.get(sym_id)
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
                      make_accessor_desc(
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
                      make_desc(val, writable, enumerable, configurable)
                    }
                  } else {
                    Undefined
                  }
                } else if data.properties.contains(prop_name) {
                  let val = match data.properties.get(prop_name) {
                    Some(v) => v
                    None => Undefined
                  }
                  let desc = data.descriptors.get(prop_name)
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
                    make_accessor_desc(
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
                    make_desc(val, writable, enumerable, configurable)
                  }
                } else if data.descriptors.contains(prop_name) {
                  // Check for accessor-only properties in descriptors (e.g., strict mode arguments.callee)
                  let desc = data.descriptors.get(prop_name)
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
                    make_accessor_desc(
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
                    make_desc(Undefined, writable, enumerable, configurable)
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
                          ClassConstructor(_, _, _, _, _, _) => 0.0
                        }
                        make_desc(Number(len), false, false, true)
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
                          ClassConstructor(n, _, _, _, _, _) => n
                        }
                        make_desc(String_(name), false, false, true)
                      } else {
                        Undefined
                      }
                    None => Undefined
                  }
                }
              Array(data) =>
                if prop_name == "length" {
                  make_desc(
                    Number(data.elements.length().to_double()),
                    true,
                    false,
                    false,
                  )
                } else {
                  // Check indexed properties
                  let idx = @strconv.parse_int(prop_name) catch { _ => -1 }
                  if idx >= 0 &&
                    idx.to_string() == prop_name &&
                    idx < data.elements.length() {
                    make_desc(data.elements[idx], true, true, true)
                  } else {
                    Undefined
                  }
                }
              String_(s) =>
                if prop_name == "length" {
                  make_desc(Number(s.length().to_double()), false, false, false)
                } else {
                  let idx = @strconv.parse_int(prop_name) catch { _ => -1 }
                  if idx >= 0 &&
                    idx.to_string() == prop_name &&
                    idx < s.length() {
                    let chars = s.to_array()
                    let buf = StringBuilder::new()
                    buf.write_char(chars[idx])
                    make_desc(String_(buf.to_string()), false, true, false)
                  } else {
                    Undefined
                  }
                }
              Proxy(proxy_data) =>
                // Unwrap proxy and get descriptor from target
                match proxy_data.target {
                  Some(target) =>
                    match target {
                      Object(data) =>
                        if is_symbol_key {
                          if data.symbol_properties.contains(sym_id) ||
                            data.symbol_descriptors.contains(sym_id) {
                            let val = match data.symbol_properties.get(sym_id) {
                              Some(v) => v
                              None => Undefined
                            }
                            let desc = data.symbol_descriptors.get(sym_id)
                            let is_acc = match desc {
                              Some(d) =>
                                d.getter is Some(_) || d.setter is Some(_)
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
                              make_accessor_desc(
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
                              make_desc(val, writable, enumerable, configurable)
                            }
                          } else {
                            Undefined
                          }
                        } else if data.properties.contains(prop_name) ||
                          data.descriptors.contains(prop_name) {
                          let val = match data.properties.get(prop_name) {
                            Some(v) => v
                            None => Undefined
                          }
                          let desc = data.descriptors.get(prop_name)
                          let is_acc = match desc {
                            Some(d) =>
                              d.getter is Some(_) || d.setter is Some(_)
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
                            make_accessor_desc(
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
                            make_desc(val, writable, enumerable, configurable)
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
          },
        ),
        "freeze": make_static_func_with_length("freeze", 1, fn(args) {
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
        }),
        "seal": make_static_func_with_length("seal", 1, fn(args) {
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
        }),
        "preventExtensions": make_static_func_with_length("preventExtensions", 1, fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              data.extensible = false
              obj
            }
            _ => obj
          }
        }),
        "isFrozen": make_static_func_with_length("isFrozen", 1, fn(args) {
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
        }),
        "isSealed": make_static_func_with_length("isSealed", 1, fn(args) {
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
        }),
        "isExtensible": make_static_func_with_length("isExtensible", 1, fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => Bool(data.extensible)
            _ => Bool(false)
          }
        }),
        "is": make_static_func_with_length("is", 2, fn(args) {
          // Object.is() - SameValue algorithm
          let x = if args.length() > 0 { args[0] } else { Undefined }
          let y = if args.length() > 1 { args[1] } else { Undefined }
          Bool(same_value(x, y))
        }),
        "fromEntries": make_static_func_with_length("fromEntries", 1, fn(args) raise {
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
            prototype: Null,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
        }),
        "groupBy": make_static_func_with_length("groupBy", 2, fn(args) raise {
          // Object.groupBy(items, callbackFn)
          let items = if args.length() > 0 { args[0] } else { Undefined }
          let callback = if args.length() > 1 { args[1] } else { Undefined }
          if not(is_callable(callback)) {
            raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
          }
          let interp = match current_interpreter.val {
            Some(i) => i
            None => abort("No interpreter")
          }
          let loc = @token.Loc::default()
          let o = to_object(items, interp)
          let len = to_array_like_length_interp(o, interp)
          let group_arrays : Map[String, Array[Value]] = {}
          for k = 0; k < len; k = k + 1 {
            let kvalue = get_array_like_element_interp(interp, o, k)
            let key = interp.call_value(callback, Undefined, [kvalue, Number(k.to_double())], loc)
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
        }),
        "hasOwn": make_static_func_with_length("hasOwn", 2, fn(args) {
          // Object.hasOwn() - modern hasOwnProperty replacement
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          let key_val = if args.length() > 1 { args[1] } else { Undefined }
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
                let idx = @strconv.parse_int(key) catch { _ => -1 }
                Bool(
                  idx >= 0 &&
                  idx.to_string() == key &&
                  idx < data.elements.length(),
                )
              }
            }
            _ => Bool(false)
          }
        }),
        "setPrototypeOf": make_static_func_with_length("setPrototypeOf", 2, fn(args) raise {
          // Object.setPrototypeOf(obj, prototype)
          // Sets the prototype of the specified object
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          let proto = if args.length() > 1 { args[1] } else { Null }
          // Validate proto is Object or null
          match proto {
            Object(_) | Null => ()
            _ =>
              raise @errors.TypeError(
                message="Object prototype may only be an Object or null",
              )
          }
          // Set the prototype if obj is an Object (return primitives unchanged)
          match obj {
            Object(data) => {
              // Check if object is extensible (frozen/sealed objects can't change prototype)
              if not(data.extensible) {
                raise @errors.TypeError(
                  message="Cannot set prototype of non-extensible object",
                )
              }
              data.prototype = proto
            }
            // Per ECMAScript spec, primitives are returned unchanged
            _ => ()
          }
          obj
        }),
        "defineProperties": make_static_func_with_length("defineProperties", 2, fn(
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
          let interp = match current_interpreter.val {
            Some(i) => i
            None => abort("No interpreter")
          }
          let iloc = @token.Loc::default()
          match (obj, descs) {
            (Object(data), Object(desc_obj)) =>
              // Only iterate enumerable own properties of descriptors object
              // Use get_property to invoke getters on the Properties object
              desc_obj.properties.each(fn(prop_name, _raw_val) raise {
                let desc_enumerable = match
                  desc_obj.descriptors.get(prop_name) {
                  Some(d) => d.enumerable
                  None => true
                }
                if not(desc_enumerable) {
                  return
                }
                let desc_val = interp.get_property(descs, prop_name, iloc)
                match desc_val {
                  Object(desc) => {
                    let has_get = has_property(desc_val, "get")
                    let has_set = has_property(desc_val, "set")
                    let has_value = has_property(desc_val, "value")
                    let has_writable = has_property(desc_val, "writable")
                    let is_accessor = has_get || has_set
                    let is_data = has_value || has_writable
                    if is_accessor && is_data {
                      raise @errors.TypeError(
                        message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
                      )
                    }
                    let prop_exists = data.properties.contains(prop_name)
                    let existing_desc = data.descriptors.get(prop_name)

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
                    let new_writable = if has_property(desc_val, "writable") {
                      Some(is_truthy(interp.get_property(desc_val, "writable", iloc)))
                    } else { None }
                    let new_enumerable = if has_property(desc_val, "enumerable") {
                      Some(is_truthy(interp.get_property(desc_val, "enumerable", iloc)))
                    } else { None }
                    let new_configurable = if has_property(desc_val, "configurable") {
                      Some(is_truthy(interp.get_property(desc_val, "configurable", iloc)))
                    } else { None }

                    // Pre-extract new value for validation (invoke getter if needed)
                    let new_desc_value : Value? = if has_value {
                      Some(interp.get_property(desc_val, "value", iloc))
                    } else { None }
                    // Validate non-configurable constraints or extensibility
                    match existing_desc {
                      Some(existing) =>
                        validate_non_configurable(
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
                            match data.properties.get(prop_name) {
                              Some(v) => v
                              None => Undefined
                            }
                          },
                          fn() { new_desc_value },
                        )
                      None =>
                        if not(prop_exists) && not(data.extensible) {
                          raise @errors.TypeError(
                            message="Cannot add property \{prop_name}, object is not extensible",
                          )
                        }
                    }
                    if is_accessor {
                      if not(data.properties.contains(prop_name)) {
                        data.properties[prop_name] = Undefined
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
                      data.descriptors[prop_name] = {
                        writable: false,
                        enumerable,
                        configurable,
                        getter: final_getter,
                        setter: final_setter,
                      }
                    } else {
                      match new_desc_value {
                        Some(v) => data.properties[prop_name] = v
                        None =>
                          if not(data.properties.contains(prop_name)) {
                            data.properties[prop_name] = Undefined
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
                      data.descriptors[prop_name] = {
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
                      message="Property description must be an object: " + to_js_string(desc_val),
                    )
                }
              })
            (Proxy(proxy_data), Object(desc_obj)) =>
              // Handle defineProperties on Proxy targets by delegating to target
              match proxy_data.target {
                Some(Object(data)) =>
                  desc_obj.properties.each(fn(prop_name, desc_val) raise {
                    let desc_enumerable = match
                      desc_obj.descriptors.get(prop_name) {
                      Some(d) => d.enumerable
                      None => true
                    }
                    if not(desc_enumerable) {
                      return
                    }
                    match desc_val {
                      Object(desc) => {
                        let has_get = desc.properties.contains("get")
                        let has_set = desc.properties.contains("set")
                        let has_value = desc.properties.contains("value")
                        let has_writable = desc.properties.contains("writable")
                        let is_accessor = has_get || has_set
                        let is_data = has_value || has_writable
                        if is_accessor && is_data {
                          raise @errors.TypeError(
                            message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
                          )
                        }
                        // Extensibility check
                        let prop_exists = data.properties.contains(prop_name) ||
                          data.descriptors.contains(prop_name)
                        if not(prop_exists) && not(data.extensible) {
                          raise @errors.TypeError(
                            message="Cannot add property \{prop_name}, object is not extensible",
                          )
                        }
                        // Non-configurable validation
                        match data.descriptors.get(prop_name) {
                          Some(existing) =>
                            validate_non_configurable(
                              existing,
                              prop_name,
                              is_accessor,
                              is_data,
                              has_value,
                              match desc.properties.get("writable") {
                                Some(v) => Some(is_truthy(v))
                                None => None
                              },
                              match desc.properties.get("enumerable") {
                                Some(v) => Some(is_truthy(v))
                                None => None
                              },
                              match desc.properties.get("configurable") {
                                Some(v) => Some(is_truthy(v))
                                None => None
                              },
                              match desc.properties.get("get") {
                                Some(v) => Some(v)
                                None => None
                              },
                              match desc.properties.get("set") {
                                Some(v) => Some(v)
                                None => None
                              },
                              fn() {
                                match data.properties.get(prop_name) {
                                  Some(v) => v
                                  None => Undefined
                                }
                              },
                              fn() {
                                match desc.properties.get("value") {
                                  Some(v) => Some(v)
                                  None => None
                                }
                              },
                            )
                          None => ()
                        }
                        if is_accessor {
                          // Accessor descriptor
                          if not(data.properties.contains(prop_name)) {
                            data.properties[prop_name] = Undefined
                          }
                          let getter : Value? = match
                            desc.properties.get("get") {
                            Some(v) =>
                              match v {
                                Undefined => None
                                _ => Some(v)
                              }
                            None => None
                          }
                          let setter : Value? = match
                            desc.properties.get("set") {
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
                            desc.properties.get("enumerable") {
                            Some(v) => is_truthy(v)
                            None => false
                          }
                          let configurable = match
                            desc.properties.get("configurable") {
                            Some(v) => is_truthy(v)
                            None => false
                          }
                          data.descriptors[prop_name] = {
                            writable: false,
                            enumerable,
                            configurable,
                            getter,
                            setter,
                          }
                        } else {
                          // Data descriptor
                          if has_value {
                            data.properties[prop_name] = match
                              desc.properties.get("value") {
                              Some(v) => v
                              None => Undefined
                            }
                          } else if not(data.properties.contains(prop_name)) {
                            data.properties[prop_name] = Undefined
                          }
                          let writable = match desc.properties.get("writable") {
                            Some(v) => is_truthy(v)
                            None => false
                          }
                          let enumerable = match
                            desc.properties.get("enumerable") {
                            Some(v) => is_truthy(v)
                            None => false
                          }
                          let configurable = match
                            desc.properties.get("configurable") {
                            Some(v) => is_truthy(v)
                            None => false
                          }
                          data.descriptors[prop_name] = {
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
              desc_obj.properties.each(fn(prop_name, desc_val) raise {
                let desc_enumerable = match
                  desc_obj.descriptors.get(prop_name) {
                  Some(d) => d.enumerable
                  None => true
                }
                if not(desc_enumerable) {
                  return
                }
                match desc_val {
                  Object(desc) =>
                    if prop_name == "length" {
                      match desc.properties.get("value") {
                        Some(val) => {
                          let n = to_number(val)
                          let new_len = n.to_int()
                          if new_len < 0 || new_len.to_double() != n || n.is_nan() {
                            raise @errors.RangeError(
                              message="Invalid array length",
                            )
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
                      let idx = @strconv.parse_int(prop_name) catch { _ => -1 }
                      if idx >= 0 && idx.to_string() == prop_name {
                        // Only write value if descriptor specifies one
                        match desc.properties.get("value") {
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
        }),
      },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Object", fn(args) raise {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          match val {
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
              val
            Undefined | Null =>
              Object({
                properties: {},
                symbol_properties: {},
                prototype: obj_proto,
                callable: None,
                class_name: "Object",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            String_(s) => {
              // ToObject: wrap string as boxed String object
              let string_proto = env.get("[[StringPrototype]]") catch {
                _ => Null
              }
              let props : Map[String, Value] = {}
              props["[[StringData]]"] = String_(s)
              props["length"] = Number(s.length().to_double())
              for i = 0; i < s.length(); i = i + 1 {
                props[i.to_string()] = String_(s[i:i + 1].to_string())
              }
              let descs : Map[String, PropDescriptor] = {}
              descs["length"] = {
                writable: false,
                enumerable: false,
                configurable: false,
                getter: None,
                setter: None,
              }
              for i = 0; i < s.length(); i = i + 1 {
                descs[i.to_string()] = {
                  writable: false,
                  enumerable: true,
                  configurable: false,
                  getter: None,
                  setter: None,
                }
              }
              Object({
                properties: props,
                symbol_properties: {},
                prototype: string_proto,
                callable: None,
                class_name: "String",
                descriptors: descs,
                symbol_descriptors: {},
                extensible: true,
              })
            }
            Number(n) => {
              // ToObject: wrap number as boxed Number object
              let number_proto = env.get("[[NumberPrototype]]") catch {
                _ => Null
              }
              Object({
                properties: { "[[NumberData]]": Number(n) },
                symbol_properties: {},
                prototype: number_proto,
                callable: None,
                class_name: "Number",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
            Bool(b) => {
              // ToObject: wrap boolean as boxed Boolean object
              let boolean_proto = env.get("[[BooleanPrototype]]") catch {
                _ => Null
              }
              Object({
                properties: { "[[BooleanData]]": Bool(b) },
                symbol_properties: {},
                prototype: boolean_proto,
                callable: None,
                class_name: "Boolean",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
            Symbol(_) => {
              // ToObject: wrap symbol as boxed Symbol object
              let symbol_proto = env.get("[[SymbolPrototype]]") catch {
                _ => Null
              }
              Object({
                properties: { "[[SymbolData]]": val },
                symbol_properties: {},
                prototype: symbol_proto,
                callable: None,
                class_name: "Symbol",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
          }
        }),
      ),
      class_name: "Function",
      descriptors: {
        "name": nf_desc, "length": nf_desc, "prototype": { writable: false, enumerable: false, configurable: false, getter: None, setter: None },
        "keys": obj_method_desc, "values": obj_method_desc, "entries": obj_method_desc,
        "create": obj_method_desc, "assign": obj_method_desc,
        "getPrototypeOf": obj_method_desc, "setPrototypeOf": obj_method_desc,
        "getOwnPropertyNames": obj_method_desc, "getOwnPropertyDescriptor": obj_method_desc,
        "getOwnPropertyDescriptors": obj_method_desc, "getOwnPropertySymbols": obj_method_desc,
        "defineProperty": obj_method_desc, "defineProperties": obj_method_desc,
        "freeze": obj_method_desc, "seal": obj_method_desc,
        "isFrozen": obj_method_desc, "isSealed": obj_method_desc,
        "is": obj_method_desc, "isExtensible": obj_method_desc,
        "preventExtensions": obj_method_desc, "fromEntries": obj_method_desc,
        "hasOwn": obj_method_desc,
        "groupBy": obj_method_desc,
      },
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // Set Object.prototype.constructor = Object
  match obj_proto {
    Object(data) => {
      let obj_ctor = env.get("Object") catch { _ => Undefined }
      data.properties["constructor"] = obj_ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }

  // Create Array.prototype with all array methods
  let array_proto_props : Map[String, Value] = {}
  let array_proto_descs : Map[String, PropDescriptor] = {}
  let method_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }

  // Non-callback methods (using MethodCallable for this-aware dispatch)
  array_proto_props["push"] = make_interp_method_func("push", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        match o {
          Array(arr) => {
            for arg in args {
              arr.elements.push(arg)
            }
            Number(arr.elements.length().to_double())
          }
          _ => {
            let mut len = to_array_like_length_interp(o, interp)
            for arg in args {
              set_array_like_element(o, len, arg)
              len = len + 1
            }
            set_array_like_length(o, len)
            Number(len.to_double())
          }
        }
      })
  array_proto_props["pop"] = make_interp_method_func("pop", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        match o {
          Array(arr) =>
            if arr.elements.length() == 0 {
              Undefined
            } else {
              arr.elements.pop() |> Option::unwrap
            }
          _ => {
            let len = to_array_like_length_interp(o, interp)
            if len == 0 {
              set_array_like_length(o, 0)
              Undefined
            } else {
              let new_len = len - 1
              let val = get_array_like_element_interp(interp, o, new_len)
              delete_array_like_element(o, new_len)
              set_array_like_length(o, new_len)
              val
            }
          }
        }
      })
  array_proto_props["shift"] = make_interp_method_func("shift", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        match o {
          Array(arr) => {
            if arr.elements.length() == 0 {
              return Undefined
            }
            let first = arr.elements[0]
            let new_elems : Array[Value] = []
            for i = 1; i < arr.elements.length(); i = i + 1 {
              new_elems.push(arr.elements[i])
            }
            while arr.elements.length() > 0 {
              let _ = arr.elements.pop()
            }
            for el in new_elems {
              arr.elements.push(el)
            }
            first
          }
          _ => {
            let len = to_array_like_length_interp(o, interp)
            if len == 0 {
              set_array_like_length(o, 0)
              return Undefined
            }
            let first = get_array_like_element_interp(interp, o, 0)
            for i = 1; i < len; i = i + 1 {
              set_array_like_element(o, i - 1, get_array_like_element_interp(interp, o, i))
            }
            delete_array_like_element(o, len - 1)
            set_array_like_length(o, len - 1)
            first
          }
        }
      })
  array_proto_props["unshift"] = make_interp_method_func("unshift", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        match o {
          Array(arr) => {
            let old : Array[Value] = []
            for el in arr.elements {
              old.push(el)
            }
            while arr.elements.length() > 0 {
              let _ = arr.elements.pop()
            }
            for arg in args {
              arr.elements.push(arg)
            }
            for el in old {
              arr.elements.push(el)
            }
            Number(arr.elements.length().to_double())
          }
          _ => {
            let len = to_array_like_length_interp(o, interp)
            let argc = args.length()
            // Shift existing elements up by argc
            for i = len - 1; i >= 0; i = i - 1 {
              set_array_like_element(o, i + argc, get_array_like_element_interp(interp, o, i))
            }
            // Insert new elements at the beginning
            for i = 0; i < argc; i = i + 1 {
              set_array_like_element(o, i, args[i])
            }
            let new_len = len + argc
            set_array_like_length(o, new_len)
            Number(new_len.to_double())
          }
        }
      })
  array_proto_props["join"] = make_interp_method_func("join", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let sep = if args.length() > 0 {
          match args[0] {
            Undefined => ","
            v => v.to_string()
          }
        } else {
          ","
        }
        let parts : Array[String] = []
        for i = 0; i < len; i = i + 1 {
          let v = get_array_like_element_interp(interp, o, i)
          match v {
            Null | Undefined => parts.push("")
            _ => parts.push(v.to_string())
          }
        }
        String_(parts.join(sep))
      })
  array_proto_props["indexOf"] = make_interp_method_func("indexOf", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let search = if args.length() > 0 { args[0] } else { Undefined }
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let start = if from_idx < 0 {
          let s = len + from_idx
          if s < 0 {
            0
          } else {
            s
          }
        } else {
          from_idx
        }
        for i = start; i < len; i = i + 1 {
          if has_array_like_element(o, i) {
            if strict_equal_val(get_array_like_element_interp(interp, o, i), search) {
              return Number(i.to_double())
            }
          }
        }
        Number(-1.0)
      })
  array_proto_props["lastIndexOf"] = make_interp_method_func("lastIndexOf", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let search = if args.length() > 0 { args[0] } else { Undefined }
        let start = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          len - 1
        }
        let from = if start < 0 {
          len + start
        } else if start >= len {
          len - 1
        } else {
          start
        }
        for i = from; i >= 0; i = i - 1 {
          if has_array_like_element(o, i) {
            if strict_equal_val(get_array_like_element_interp(interp, o, i), search) {
              return Number(i.to_double())
            }
          }
        }
        Number(-1.0)
      })
  array_proto_props["includes"] = make_interp_method_func("includes", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let search = if args.length() > 0 { args[0] } else { Undefined }
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let start = if from_idx < 0 {
          let s = len + from_idx
          if s < 0 {
            0
          } else {
            s
          }
        } else {
          from_idx
        }
        for i = start; i < len; i = i + 1 {
          if same_value_zero(get_array_like_element_interp(interp, o, i), search) {
            return Bool(true)
          }
        }
        Bool(false)
      })
  array_proto_props["slice"] = make_interp_method_func("slice", 2, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let alen = to_array_like_length_interp(o, interp)
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 1 {
          match args[1] {
            Undefined => alen
            _ => to_number(args[1]).to_int()
          }
        } else {
          alen
        }
        if start < 0 {
          start = alen + start
          if start < 0 {
            start = 0
          }
        }
        if end < 0 {
          end = alen + end
          if end < 0 {
            end = 0
          }
        }
        if end > alen {
          end = alen
        }
        let result : Array[Value] = []
        for i = start; i < end; i = i + 1 {
          result.push(get_array_like_element_interp(interp, o, i))
        }
        Array({ elements: result })
      })
  array_proto_props["concat"] = make_interp_method_func("concat", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let result : Array[Value] = []
        let concat_sym_id = get_isconcatspreadable_symbol().id
        // Process this value and each argument per ES2015 concat spec
        let items : Array[Value] = [o]
        for a in args {
          items.push(a)
        }
        for item in items {
          // Determine spreadability: check @@isConcatSpreadable
          let spreadable = match item {
            Object(data) => {
              // Check own symbol property, then walk prototype chain
              let sym_val = match data.symbol_properties.get(concat_sym_id) {
                Some(v) => v
                None => {
                  let mut found : Value = Undefined
                  let mut cur = data.prototype
                  while true {
                    match cur {
                      Object(pd) =>
                        match pd.symbol_properties.get(concat_sym_id) {
                          Some(v) => { found = v; break }
                          None => cur = pd.prototype
                        }
                      _ => break
                    }
                  }
                  found
                }
              }
              match sym_val {
                Undefined => data.class_name == "Array"
                _ => is_truthy(sym_val)
              }
            }
            Array(arr_data) =>
              match get_array_symbol_prop(arr_data, concat_sym_id) {
                Some(v) =>
                  match v {
                    Undefined => true // default: arrays are spreadable
                    _ => is_truthy(v)
                  }
                None => true // default: arrays are spreadable
              }
            _ => false
          }
          if spreadable {
            let len = to_array_like_length_interp(item, interp)
            for i = 0; i < len; i = i + 1 {
              if has_array_like_element(item, i) {
                result.push(get_array_like_element_interp(interp, item, i))
              } else {
                result.push(Undefined)
              }
            }
          } else {
            result.push(item)
          }
        }
        Array({ elements: result })
      })
  array_proto_props["reverse"] = make_interp_method_func("reverse", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        match o {
          Array(arr) => {
            arr.elements.rev_in_place()
            Array(arr)
          }
          _ => {
            let len = to_array_like_length_interp(o, interp)
            let mut lower = 0
            let mut upper = len - 1
            while lower < upper {
              let lower_val = get_array_like_element_interp(interp, o, lower)
              let upper_val = get_array_like_element_interp(interp, o, upper)
              set_array_like_element(o, lower, upper_val)
              set_array_like_element(o, upper, lower_val)
              lower = lower + 1
              upper = upper - 1
            }
            o
          }
        }
      })
  array_proto_props["fill"] = make_interp_method_func("fill", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let fill_val = if args.length() > 0 { args[0] } else { Undefined }
        let alen = to_array_like_length_interp(o, interp)
        let mut start = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 2 {
          match args[2] {
            Undefined => alen
            _ => to_number(args[2]).to_int()
          }
        } else {
          alen
        }
        if start < 0 {
          start = alen + start
          if start < 0 {
            start = 0
          }
        }
        if start > alen {
          start = alen
        }
        if end < 0 {
          end = alen + end
          if end < 0 {
            end = 0
          }
        }
        if end > alen {
          end = alen
        }
        for i = start; i < end; i = i + 1 {
          set_array_like_element(o, i, fill_val)
        }
        o
      })
  array_proto_props["toString"] = make_interp_method_func("toString", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        // Per spec, toString calls join if available, otherwise Object.prototype.toString
        let join_fn = interp.get_property(o, "join", @token.Loc::default())
        if is_callable(join_fn) {
          interp.call_value(join_fn, o, [], @token.Loc::default())
        } else {
          let cls = match o {
            Object(d) => d.class_name
            _ => "Object"
          }
          String_("[object " + cls + "]")
        }
      })
  array_proto_props["at"] = make_interp_method_func("at", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let actual_idx = if idx < 0 { len + idx } else { idx }
        if actual_idx >= 0 && actual_idx < len {
          get_array_like_element_interp(interp, o, actual_idx)
        } else {
          Undefined
        }
      })
  array_proto_props["toLocaleString"] = make_interp_method_func("toLocaleString", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let parts : Array[String] = []
        for i = 0; i < len; i = i + 1 {
          let v = get_array_like_element_interp(interp, o, i)
          match v {
            Null | Undefined => parts.push("")
            _ => {
              // Per spec, call toLocaleString on each element
              let tls = interp.get_property(v, "toLocaleString", @token.Loc::default())
              if is_callable(tls) {
                let result = interp.call_value(tls, v, [], @token.Loc::default())
                parts.push(to_js_string(result))
              } else {
                parts.push(v.to_string())
              }
            }
          }
        }
        String_(parts.join(","))
      })

  // Callback-requiring methods (using InterpreterCallable)
  array_proto_props["forEach"] = make_interp_method_func("forEach", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(o, i) {
            let _ = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element_interp(interp, o, i),
                Number(i.to_double()),
                o,
              ],
              loc,
            )
          }
        }
        Undefined
      })
  array_proto_props["map"] = make_interp_method_func("map", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(o, i) {
            let val = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element_interp(interp, o, i),
                Number(i.to_double()),
                o,
              ],
              loc,
            )
            result.push(val)
          } else {
            result.push(Undefined)
          }
        }
        Array({ elements: result })
      })
  array_proto_props["filter"] = make_interp_method_func("filter", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(o, i) {
            let el = get_array_like_element_interp(interp, o, i)
            let val = interp.call_value(
              callback,
              this_arg,
              [el, Number(i.to_double()), o],
              loc,
            )
            if is_truthy(val) {
              result.push(el)
            }
          }
        }
        Array({ elements: result })
      })
  array_proto_props["reduce"] = make_interp_method_func("reduce", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        let mut acc : Value = Undefined
        let mut k = 0
        if args.length() > 1 {
          acc = args[1]
        } else {
          // Per spec: find first present element as initial value
          let mut k_present = false
          while k < len {
            if has_array_like_element(o, k) {
              acc = get_array_like_element_interp(interp, o, k)
              k = k + 1
              k_present = true
              break
            }
            k = k + 1
          }
          if not(k_present) {
            raise @errors.TypeError(
              message="Reduce of empty array with no initial value",
            )
          }
        }
        while k < len {
          if has_array_like_element(o, k) {
            acc = interp.call_value(
              callback,
              Undefined,
              [
                acc,
                get_array_like_element_interp(interp, o, k),
                Number(k.to_double()),
                o,
              ],
              loc,
            )
          }
          k = k + 1
        }
        acc
      })
  array_proto_props["reduceRight"] = make_interp_method_func("reduceRight", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        let mut acc : Value = Undefined
        let mut k = len - 1
        if args.length() > 1 {
          acc = args[1]
        } else {
          // Per spec: find last present element as initial value (searching right to left)
          let mut k_present = false
          while k >= 0 {
            if has_array_like_element(o, k) {
              acc = get_array_like_element_interp(interp, o, k)
              k = k - 1
              k_present = true
              break
            }
            k = k - 1
          }
          if not(k_present) {
            raise @errors.TypeError(
              message="Reduce of empty array with no initial value",
            )
          }
        }
        while k >= 0 {
          if has_array_like_element(o, k) {
            acc = interp.call_value(
              callback,
              Undefined,
              [
                acc,
                get_array_like_element_interp(interp, o, k),
                Number(k.to_double()),
                o,
              ],
              loc,
            )
          }
          k = k - 1
        }
        acc
      })
  array_proto_props["find"] = make_interp_method_func("find", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        for i = 0; i < len; i = i + 1 {
          let el = get_array_like_element_interp(interp, o, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), o],
            loc,
          )
          if is_truthy(val) {
            return el
          }
        }
        Undefined
      })
  array_proto_props["findIndex"] = make_interp_method_func("findIndex", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        for i = 0; i < len; i = i + 1 {
          let el = get_array_like_element_interp(interp, o, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), o],
            loc,
          )
          if is_truthy(val) {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      })
  array_proto_props["findLast"] = make_interp_method_func("findLast", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        for i = len - 1; i >= 0; i = i - 1 {
          let el = get_array_like_element_interp(interp, o, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), o],
            loc,
          )
          if is_truthy(val) {
            return el
          }
        }
        Undefined
      })
  array_proto_props["findLastIndex"] = make_interp_method_func("findLastIndex", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        for i = len - 1; i >= 0; i = i - 1 {
          let el = get_array_like_element_interp(interp, o, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), o],
            loc,
          )
          if is_truthy(val) {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      })
  array_proto_props["every"] = make_interp_method_func("every", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(o, i) {
            let val = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element_interp(interp, o, i),
                Number(i.to_double()),
                o,
              ],
              loc,
            )
            if not(is_truthy(val)) {
              return Bool(false)
            }
          }
        }
        Bool(true)
      })
  array_proto_props["some"] = make_interp_method_func("some", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(o, i) {
            let val = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element_interp(interp, o, i),
                Number(i.to_double()),
                o,
              ],
              loc,
            )
            if is_truthy(val) {
              return Bool(true)
            }
          }
        }
        Bool(false)
      })
  array_proto_props["sort"] = make_interp_method_func("sort", 1, fn(interp, this_val, args) raise {
        // Step 1: Validate comparefn
        if args.length() > 0 {
          let comparefn = args[0]
          match comparefn {
            Undefined => ()
            _ =>
              if not(is_callable(comparefn)) {
                raise @errors.TypeError(message=to_js_string(comparefn) + " is not a function")
              }
          }
        }
        // Extract elements into a mutable array for sorting
        let elements : Array[Value] = match this_val {
          Array(arr) => arr.elements
          _ => to_array_like_elements(this_val)
        }
        if args.length() > 0 {
          match args[0] {
            Undefined =>
              elements.sort_by(fn(a, b) {
                // Per spec: undefined sorts to end
                if a is Undefined && b is Undefined {
                  return 0
                }
                if a is Undefined {
                  return 1
                }
                if b is Undefined {
                  return -1
                }
                let sa = a.to_string()
                let sb = b.to_string()
                if sa < sb {
                  -1
                } else if sa > sb {
                  1
                } else {
                  0
                }
              })
            _ => {
              let comparefn = args[0]
              let loc = @token.Loc::default()
              let mut caught_error : Error? = None
              elements.sort_by(fn(a, b) {
                // Per spec: undefined sorts to end even with comparefn
                if a is Undefined && b is Undefined {
                  return 0
                }
                if a is Undefined {
                  return 1
                }
                if b is Undefined {
                  return -1
                }
                if caught_error is Some(_) {
                  return 0
                }
                let result = interp.call_value(
                  comparefn,
                  Undefined,
                  [a, b],
                  loc,
                ) catch {
                  e => {
                    caught_error = Some(e)
                    return 0
                  }
                }
                let cmp = to_number(result) catch {
                  e => {
                    caught_error = Some(e)
                    return 0
                  }
                }
                if cmp.is_nan() {
                  0
                } else if cmp < 0.0 {
                  -1
                } else if cmp > 0.0 {
                  1
                } else {
                  0
                }
              })
              match caught_error {
                Some(e) => raise e
                None => ()
              }
            }
          }
        } else {
          elements.sort_by(fn(a, b) {
            // Per spec: undefined sorts to end
            if a is Undefined && b is Undefined {
              return 0
            }
            if a is Undefined {
              return 1
            }
            if b is Undefined {
              return -1
            }
            let sa = a.to_string()
            let sb = b.to_string()
            if sa < sb {
              -1
            } else if sa > sb {
              1
            } else {
              0
            }
          })
        }
        // For non-array objects, write sorted elements back
        match this_val {
          Array(arr) => Array(arr)
          _ => {
            for i = 0; i < elements.length(); i = i + 1 {
              set_array_like_element(this_val, i, elements[i])
            }
            this_val
          }
        }
      })
  array_proto_props["flat"] = make_interp_method_func("flat", 0, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let depth = if args.length() > 0 {
          match args[0] {
            Undefined => 1
            _ => to_number(args[0]).to_int()
          }
        } else {
          1
        }
        let elements = to_array_like_elements(o)
        let result : Array[Value] = []
        flatten_array_val(elements, depth, result)
        Array({ elements: result })
      })
  array_proto_props["flatMap"] = make_interp_method_func("flatMap", 1, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        if not(is_callable(callback)) {
          raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length_interp(o, interp)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          let el = get_array_like_element_interp(interp, o, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), o],
            loc,
          )
          match val {
            Array(inner) =>
              for item in inner.elements {
                result.push(item)
              }
            _ => result.push(val)
          }
        }
        Array({ elements: result })
      })
  array_proto_props["splice"] = make_interp_method_func("splice", 2, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let alen = to_array_like_length_interp(o, interp)
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if start < 0 {
          start = alen + start
          if start < 0 {
            start = 0
          }
        }
        if start > alen {
          start = alen
        }
        let del_count = if args.length() > 1 {
          let d_num = to_number(args[1])
          if d_num.is_inf() || d_num >= (alen - start).to_double() {
            alen - start
          } else {
            let d = d_num.to_int()
            if d < 0 {
              0
            } else {
              d
            }
          }
        } else {
          alen - start
        }
        let removed : Array[Value] = []
        for i = start; i < start + del_count; i = i + 1 {
          removed.push(get_array_like_element_interp(interp, o, i))
        }
        let new_items : Array[Value] = []
        for i = 2; i < args.length(); i = i + 1 {
          new_items.push(args[i])
        }
        let items_count = new_items.length()
        // For Array type, use direct element manipulation
        match o {
          Array(arr) => {
            let tail : Array[Value] = []
            for i = start + del_count; i < alen; i = i + 1 {
              tail.push(arr.elements[i])
            }
            while arr.elements.length() > start {
              let _ = arr.elements.pop()
            }
            for item in new_items {
              arr.elements.push(item)
            }
            for item in tail {
              arr.elements.push(item)
            }
          }
          _ => {
            // For objects: shift elements appropriately
            if items_count < del_count {
              // Shift left
              for i = start; i < alen - del_count; i = i + 1 {
                set_array_like_element(o, i + items_count, get_array_like_element_interp(interp, o, i + del_count))
              }
              // Delete trailing elements
              let new_len = alen - del_count + items_count
              for i = new_len; i < alen; i = i + 1 {
                delete_array_like_element(o, i)
              }
              set_array_like_length(o, new_len)
            } else if items_count > del_count {
              // Shift right
              let new_len = alen - del_count + items_count
              for i = alen - 1; i >= start + del_count; i = i - 1 {
                set_array_like_element(o, i + items_count - del_count, get_array_like_element_interp(interp, o, i))
              }
              set_array_like_length(o, new_len)
            }
            // Insert new items
            for i = 0; i < items_count; i = i + 1 {
              set_array_like_element(o, start + i, new_items[i])
            }
            if items_count == del_count {
              // Length stays the same, no need to change
              ()
            }
          }
        }
        Array({ elements: removed })
      })
  array_proto_props["copyWithin"] = make_interp_method_func("copyWithin", 2, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let mut target = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let mut start = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 2 {
          match args[2] {
            Undefined => len
            _ => to_number(args[2]).to_int()
          }
        } else {
          len
        }
        if target < 0 {
          target = len + target
          if target < 0 {
            target = 0
          }
        }
        if start < 0 {
          start = len + start
          if start < 0 {
            start = 0
          }
        }
        if end < 0 {
          end = len + end
          if end < 0 {
            end = 0
          }
        }
        if end > len {
          end = len
        }
        let count = if end - start < len - target {
          end - start
        } else {
          len - target
        }
        if count > 0 {
          let temp : Array[Value] = []
          for i = start; i < start + count; i = i + 1 {
            temp.push(get_array_like_element_interp(interp, o, i))
          }
          for i = 0; i < count; i = i + 1 {
            if target + i < len {
              set_array_like_element(o, target + i, temp[i])
            }
          }
        }
        o
      })
  array_proto_props["entries"] = make_interp_method_func("entries", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          result.push(
            Array({ elements: [Number(i.to_double()), get_array_like_element_interp(interp, o, i)] }),
          )
        }
        make_array_iterator_value({ elements: result })
      })
  array_proto_props["keys"] = make_interp_method_func("keys", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          result.push(Number(i.to_double()))
        }
        make_array_iterator_value({ elements: result })
      })
  array_proto_props["values"] = make_interp_method_func("values", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          result.push(get_array_like_element_interp(interp, o, i))
        }
        make_array_iterator_value({ elements: result })
      })
  array_proto_props["toReversed"] = make_interp_method_func("toReversed", 0, fn(interp, this_val, _args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let result : Array[Value] = []
        for i = len - 1; i >= 0; i = i - 1 {
          result.push(get_array_like_element_interp(interp, o, i))
        }
        Array({ elements: result })
      })
  array_proto_props["toSorted"] = make_interp_method_func("toSorted", 1, fn(interp, this_val, args) raise {
        // Step 1: Validate comparefn
        if args.length() > 0 {
          let comparefn = args[0]
          match comparefn {
            Undefined => ()
            _ =>
              if not(is_callable(comparefn)) {
                raise @errors.TypeError(message=to_js_string(comparefn) + " is not a function")
              }
          }
        }
        let result = to_array_like_elements(this_val)
        if args.length() > 0 {
          match args[0] {
            Undefined =>
              result.sort_by(fn(a, b) {
                if a is Undefined && b is Undefined {
                  return 0
                }
                if a is Undefined {
                  return 1
                }
                if b is Undefined {
                  return -1
                }
                let sa = a.to_string()
                let sb = b.to_string()
                if sa < sb {
                  -1
                } else if sa > sb {
                  1
                } else {
                  0
                }
              })
            _ => {
              let comparefn = args[0]
              let loc = @token.Loc::default()
              let mut caught_error : Error? = None
              result.sort_by(fn(a, b) {
                if a is Undefined && b is Undefined {
                  return 0
                }
                if a is Undefined {
                  return 1
                }
                if b is Undefined {
                  return -1
                }
                if caught_error is Some(_) {
                  return 0
                }
                let cmp_result = interp.call_value(
                  comparefn,
                  Undefined,
                  [a, b],
                  loc,
                ) catch {
                  e => {
                    caught_error = Some(e)
                    return 0
                  }
                }
                let cmp = to_number(cmp_result) catch {
                  e => {
                    caught_error = Some(e)
                    return 0
                  }
                }
                if cmp.is_nan() {
                  0
                } else if cmp < 0.0 {
                  -1
                } else if cmp > 0.0 {
                  1
                } else {
                  0
                }
              })
              match caught_error {
                Some(e) => raise e
                None => ()
              }
            }
          }
        } else {
          result.sort_by(fn(a, b) {
            if a is Undefined && b is Undefined {
              return 0
            }
            if a is Undefined {
              return 1
            }
            if b is Undefined {
              return -1
            }
            let sa = a.to_string()
            let sb = b.to_string()
            if sa < sb {
              -1
            } else if sa > sb {
              1
            } else {
              0
            }
          })
        }
        Array({ elements: result })
      })
  array_proto_props["toSpliced"] = make_interp_method_func("toSpliced", 2, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let len = to_array_like_length_interp(o, interp)
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if start < 0 {
          start = len + start
          if start < 0 {
            start = 0
          }
        }
        if start > len {
          start = len
        }
        let del_count = if args.length() > 1 {
          let d = to_number(args[1]).to_int()
          if d < 0 {
            0
          } else if d > len - start {
            len - start
          } else {
            d
          }
        } else {
          len - start
        }
        let result : Array[Value] = []
        for i = 0; i < start; i = i + 1 {
          result.push(get_array_like_element_interp(interp, o, i))
        }
        for i = 2; i < args.length(); i = i + 1 {
          result.push(args[i])
        }
        for i = start + del_count; i < len; i = i + 1 {
          result.push(get_array_like_element_interp(interp, o, i))
        }
        Array({ elements: result })
      })
  array_proto_props["with"] = make_interp_method_func("with", 2, fn(interp, this_val, args) raise {
        let o = to_object(this_val, interp)
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let value = if args.length() > 1 { args[1] } else { Undefined }
        let len = to_array_like_length_interp(o, interp)
        let actual_idx = if idx < 0 { len + idx } else { idx }
        if actual_idx < 0 || actual_idx >= len {
          raise @errors.RangeError(message="Invalid index")
        }
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          if i == actual_idx {
            result.push(value)
          } else {
            result.push(get_array_like_element_interp(interp, o, i))
          }
        }
        Array({ elements: result })
      })
  array_proto_descs["push"] = method_desc
  array_proto_descs["pop"] = method_desc
  array_proto_descs["shift"] = method_desc
  array_proto_descs["unshift"] = method_desc
  array_proto_descs["join"] = method_desc
  array_proto_descs["indexOf"] = method_desc
  array_proto_descs["lastIndexOf"] = method_desc
  array_proto_descs["includes"] = method_desc
  array_proto_descs["slice"] = method_desc
  array_proto_descs["concat"] = method_desc
  array_proto_descs["reverse"] = method_desc
  array_proto_descs["fill"] = method_desc
  array_proto_descs["toString"] = method_desc
  array_proto_descs["at"] = method_desc
  array_proto_descs["toLocaleString"] = method_desc
  array_proto_descs["forEach"] = method_desc
  array_proto_descs["map"] = method_desc
  array_proto_descs["filter"] = method_desc
  array_proto_descs["reduce"] = method_desc
  array_proto_descs["reduceRight"] = method_desc
  array_proto_descs["find"] = method_desc
  array_proto_descs["findIndex"] = method_desc
  array_proto_descs["findLast"] = method_desc
  array_proto_descs["findLastIndex"] = method_desc
  array_proto_descs["every"] = method_desc
  array_proto_descs["some"] = method_desc
  array_proto_descs["sort"] = method_desc
  array_proto_descs["flat"] = method_desc
  array_proto_descs["flatMap"] = method_desc
  array_proto_descs["splice"] = method_desc
  array_proto_descs["copyWithin"] = method_desc
  array_proto_descs["entries"] = method_desc
  array_proto_descs["keys"] = method_desc
  array_proto_descs["values"] = method_desc
  array_proto_descs["toReversed"] = method_desc
  array_proto_descs["toSorted"] = method_desc
  array_proto_descs["toSpliced"] = method_desc
  array_proto_descs["with"] = method_desc
  // Array.prototype.length = 0 (per spec, Array.prototype is an Array with length 0)
  array_proto_props["length"] = Number(0.0)
  array_proto_descs["length"] = { writable: true, enumerable: false, configurable: false, getter: None, setter: None }
  let array_proto : Value = Object({
    properties: array_proto_props,
    symbol_properties: {},
    prototype: obj_proto,
    callable: None,
    class_name: "Array",
    descriptors: array_proto_descs,
    symbol_descriptors: {},
    extensible: true,
  })

  // Array constructor with Array.isArray, Array.from, Array.of
  let array_props : Map[String, Value] = {}
  array_props["prototype"] = array_proto
  array_props["name"] = String_("Array")
  array_props["length"] = Number(1.0)
  array_props["isArray"] = make_static_func_with_length("isArray", 1, fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    // Spec: Array.isArray unwraps proxies recursively
    let mut current = val
    while true {
      match current {
        Array(_) => return Bool(true)
        Object(data) =>
          // Array.prototype is an Object with class_name "Array"
          if data.class_name == "Array" {
            return Bool(true)
          } else {
            return Bool(false)
          }
        Proxy(proxy_data) =>
          match proxy_data.target {
            Some(target) => current = target
            None => return Bool(false)
          }
        _ => return Bool(false)
      }
    }
    Bool(false)
  })
  array_props["of"] = make_static_func("of", fn(args) {
    // Array.of() - creates array from arguments
    Array({ elements: args })
  })
  // Array.from with mapFn support using InterpreterCallable
  array_props["from"] = make_interp_method_func("from", 1, fn(interp, _this_val, args) raise {
        let source = if args.length() > 0 { args[0] } else { Undefined }
        // Per spec, items must not be null/undefined
        if source is (Null | Undefined) {
          raise @errors.TypeError(
            message="Cannot read properties of " +
              to_js_string(source) +
              " (reading 'Symbol(Symbol.iterator)')",
          )
        }
        let map_fn = if args.length() > 1 {
          match args[1] {
            Undefined => None
            fn_val => {
              if not(is_callable(fn_val)) {
                raise @errors.TypeError(
                  message=to_js_string(fn_val) + " is not a function",
                )
              }
              Some(fn_val)
            }
          }
        } else {
          None
        }
        let this_arg = if args.length() > 2 { args[2] } else { Undefined }
        let loc = @token.Loc::default()
        let elements : Array[Value] = []
        // Per spec: first try Symbol.iterator (iterable protocol)
        let iterator_sym = get_iterator_symbol()
        let mut used_iterator = false
        let iterator_method = interp.get_computed_property(
          source,
          Symbol(iterator_sym),
          loc,
        )
        if is_callable(iterator_method) {
          used_iterator = true
          let iterator = interp.call_value(iterator_method, source, [], loc)
          let mut k = 0
          while true {
            let next_fn = interp.get_property(iterator, "next", loc)
            let next = interp.call_value(next_fn, iterator, [], loc)
            let done = match next {
              Object(d) =>
                match d.properties.get("done") {
                  Some(v) => is_truthy(v)
                  _ => false
                }
              _ => true
            }
            if done {
              break
            }
            let value = match next {
              Object(d) =>
                match d.properties.get("value") {
                  Some(v) => v
                  None => Undefined
                }
              _ => Undefined
            }
            let mapped = match map_fn {
              Some(fn_val) =>
                interp.call_value(
                  fn_val,
                  this_arg,
                  [value, Number(k.to_double())],
                  loc,
                )
              None => value
            }
            elements.push(mapped)
            k = k + 1
          }
        }
        if not(used_iterator) {
          // Fallback: array-like behavior
          match source {
            Array(data) =>
              for i = 0; i < data.elements.length(); i = i + 1 {
                let el = data.elements[i]
                let mapped = match map_fn {
                  Some(fn_val) =>
                    interp.call_value(
                      fn_val,
                      this_arg,
                      [el, Number(i.to_double())],
                      loc,
                    )
                  None => el
                }
                elements.push(mapped)
              }
            String_(s) => {
              let chars = s.to_array()
              for i = 0; i < chars.length(); i = i + 1 {
                let el = String_(chars[i].to_string())
                let mapped = match map_fn {
                  Some(fn_val) =>
                    interp.call_value(
                      fn_val,
                      this_arg,
                      [el, Number(i.to_double())],
                      loc,
                    )
                  None => el
                }
                elements.push(mapped)
              }
            }
            _ => {
              let o = to_object(source, interp)
              let len = to_array_like_length_interp(o, interp)
              for i = 0; i < len; i = i + 1 {
                let el = interp.get_property(o, i.to_string(), loc)
                let mapped = match map_fn {
                  Some(fn_val) =>
                    interp.call_value(
                      fn_val,
                      this_arg,
                      [el, Number(i.to_double())],
                      loc,
                    )
                  None => el
                }
                elements.push(mapped)
              }
            }
          }
        }
        Array({ elements, })
      })
  env.def_builtin(
    "Array",
    Object({
      properties: array_props,
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Array", fn(args) raise {
          // Array constructor behavior
          if args.length() == 1 {
            match args[0] {
              Number(n) => {
                // Array(n) creates an array with the given length.
                // Validate using double to avoid int32 overflow
                if n < 0.0 || n > 4294967295.0 || n != @math.floor(n) || n.is_nan() {
                  raise @errors.RangeError(message="Invalid array length")
                }
                let len = n.to_int64().to_int()
                let elements : Array[Value] = []
                // Cap pre-allocation to prevent hangs with very large lengths
                if len >= 0 && len <= 100000 {
                  for _i = 0; _i < len; _i = _i + 1 {
                    elements.push(Undefined)
                  }
                }
                Array({ elements, })
              }
              _ => Array({ elements: args })
            }
          } else {
            Array({ elements: args })
          }
        }),
      ),
      class_name: "Function",
      descriptors: {
        "name": nf_desc, "length": nf_desc,
        "prototype": { writable: false, enumerable: false, configurable: false, getter: None, setter: None },
        "isArray": obj_method_desc, "from": obj_method_desc, "of": obj_method_desc,
      },
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  // Set Array.prototype.constructor = Array
  match array_proto {
    Object(data) => {
      let arr_ctor = env.get("Array") catch { _ => Undefined }
      data.properties["constructor"] = arr_ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
}

///|
/// Validate non-configurable property constraints.
/// Throws TypeError if the proposed descriptor change violates invariants.
fn validate_non_configurable(
  existing : PropDescriptor,
  prop_display : String,
  is_accessor : Bool,
  is_data : Bool,
  has_value : Bool,
  new_writable : Bool?,
  new_enumerable : Bool?,
  new_configurable : Bool?,
  new_getter : Value?,
  new_setter : Value?,
  get_old_value : () -> Value,
  get_new_value : () -> Value?,
) -> Unit raise Error {
  if existing.configurable {
    return
  }
  let existing_is_accessor = existing.getter is Some(_) ||
    existing.setter is Some(_)
  // Cannot change between accessor and data
  if existing_is_accessor && is_data {
    raise @errors.TypeError(
      message="Cannot redefine non-configurable property: \{prop_display}",
    )
  }
  if not(existing_is_accessor) && is_accessor {
    raise @errors.TypeError(
      message="Cannot redefine non-configurable property: \{prop_display}",
    )
  }
  let enumerable_ok = match new_enumerable {
    Some(e) => e == existing.enumerable
    None => true
  }
  let configurable_ok = match new_configurable {
    Some(c) => c == existing.configurable
    None => true
  }
  // Non-configurable accessor: validate getter/setter identity
  if existing_is_accessor && is_accessor {
    let getter_ok = match new_getter {
      Some(g) =>
        match existing.getter {
          Some(eg) => strict_equal_val(g, eg)
          None => g is Undefined
        }
      None => true
    }
    let setter_ok = match new_setter {
      Some(s) =>
        match existing.setter {
          Some(es) => strict_equal_val(s, es)
          None => s is Undefined
        }
      None => true
    }
    if not(enumerable_ok && configurable_ok && getter_ok && setter_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Non-configurable data: validate writable/value
  if not(existing_is_accessor) && not(is_accessor) {
    let writable_ok = match new_writable {
      Some(w) => if not(existing.writable) && w { false } else { true }
      None => true
    }
    let value_ok = if not(existing.writable) && has_value {
      match get_new_value() {
        Some(v) => strict_equal_val(v, get_old_value())
        None => true
      }
    } else {
      true
    }
    if not(writable_ok && enumerable_ok && configurable_ok && value_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Generic descriptor (no accessor/data fields)
  if not(is_accessor) && not(is_data) {
    if not(enumerable_ok && configurable_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
}

///|
fn flatten_array_val(
  elements : Array[Value],
  depth : Int,
  result : Array[Value],
) -> Unit {
  for el in elements {
    match el {
      Array(inner) =>
        if depth > 0 {
          flatten_array_val(inner.elements, depth - 1, result)
        } else {
          result.push(el)
        }
      _ => result.push(el)
    }
  }
}

///|
/// ToLength: Get length from any value as per ECMAScript spec (array-like objects)
pub fn to_array_like_length(val : Value) -> Int raise {
  match val {
    Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Array(data) => data.elements.length()
    Object(data) => {
      // Check for getter-based length first, then fall back to properties
      let length_val : Value? = match data.properties.get("length") {
        Some(v) => Some(v)
        None =>
          // Check if length is defined as an accessor (getter)
          match data.descriptors.get("length") {
            Some(desc) =>
              match desc.getter {
                Some(Object(getter_data)) =>
                  match getter_data.callable {
                    Some(NativeCallable(_, f)) => Some(f([]))
                    Some(NonConstructableCallable(_, f)) => Some(f([]))
                    Some(MethodCallable(_, f)) => Some(f(Object(data), []))
                    _ => None
                  }
                _ => None
              }
            None => None
          }
      }
      to_length_from_value(length_val)
    }
    String_(s) => s.length()
    _ => 0
  }
}

///|
/// ToLength with full interpreter support for user-defined getter-based length
pub fn to_array_like_length_interp(val : Value, interp : Interpreter) -> Int raise {
  match val {
    Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Array(data) => data.elements.length()
    String_(s) => s.length()
    _ => {
      // Use interpreter's get_property to properly handle getters and prototype chains
      let length_val = interp.get_property(val, "length", @token.Loc::default())
      to_length_from_value(Some(length_val))
    }
  }
}

///|
fn to_length_from_value(v : Value?) -> Int raise {
  match v {
    Some(Number(n)) => {
      let len = n.to_int()
      if len < 0 {
        0
      } else {
        len
      }
    }
    Some(v) => {
      let n = to_number(v)
      if n.is_nan() {
        0
      } else if n.is_inf() {
        if n > 0.0 {
          0x7FFFFFFF
        } else {
          0
        }
      } else {
        let i = n.to_int()
        if i < 0 {
          0
        } else {
          i
        }
      }
    }
    None => 0
  }
}

///|
/// Get indexed element from array-like value
pub fn get_array_like_element(val : Value, index : Int) -> Value {
  let key = index.to_string()
  match val {
    Array(data) =>
      if index >= 0 && index < data.elements.length() {
        data.elements[index]
      } else {
        Undefined
      }
    Object(data) => {
      // Check for accessor descriptor (getter) on own property first
      let getter_result : Value? = match data.descriptors.get(key) {
        Some(desc) =>
          match desc.getter {
            Some(Object(getter_data)) =>
              match getter_data.callable {
                Some(NativeCallable(_, f)) => try { Some(f([])) } catch { _ => None }
                Some(NonConstructableCallable(_, f)) => try { Some(f([])) } catch { _ => None }
                Some(MethodCallable(_, f)) => try { Some(f(Object(data), [])) } catch { _ => None }
                _ => None
              }
            _ => None
          }
        None => None
      }
      match getter_result {
        Some(v) => v
        None =>
          // Walk prototype chain for property lookup
          match data.properties.get(key) {
            Some(v) => v
            None => {
              let mut current = data.prototype
              let mut result : Value = Undefined
              while true {
                match current {
                  Object(proto_data) =>
                    match proto_data.properties.get(key) {
                      Some(v) => {
                        result = v
                        break
                      }
                      None => current = proto_data.prototype
                    }
                  _ => break
                }
              }
              result
            }
          }
      }
    }
    String_(s) => {
      let chars = s.to_array()
      if index >= 0 && index < chars.length() {
        let buf = StringBuilder::new()
        buf.write_char(chars[index])
        String_(buf.to_string())
      } else {
        Undefined
      }
    }
    _ => Undefined
  }
}

///|
/// Get indexed element from array-like value using interpreter (handles user-defined getters)
pub fn get_array_like_element_interp(
  interp : Interpreter,
  val : Value,
  index : Int
) -> Value raise {
  match val {
    Array(data) =>
      if index >= 0 && index < data.elements.length() {
        data.elements[index]
      } else {
        Undefined
      }
    _ => interp.get_property(val, index.to_string(), @token.Loc::default())
  }
}

///|
/// Check if array-like value has indexed property
pub fn has_array_like_element(val : Value, index : Int) -> Bool {
  let key = index.to_string()
  match val {
    Array(data) => index >= 0 && index < data.elements.length()
    Object(data) => {
      if data.properties.contains(key) {
        return true
      }
      // Check for accessor descriptor
      match data.descriptors.get(key) {
        Some(desc) if desc.getter is Some(_) => return true
        _ => ()
      }
      // Walk prototype chain
      let mut current = data.prototype
      while true {
        match current {
          Object(proto_data) => {
            if proto_data.properties.contains(key) {
              return true
            }
            match proto_data.descriptors.get(key) {
              Some(desc) if desc.getter is Some(_) => return true
              _ => ()
            }
            current = proto_data.prototype
          }
          Array(arr_data) => return index >= 0 && index < arr_data.elements.length()
          _ => break
        }
      }
      false
    }
    String_(s) => index >= 0 && index < s.length()
    _ => false
  }
}

///|
/// Set indexed element on array-like value
pub fn set_array_like_element(val : Value, index : Int, value : Value) -> Unit {
  let key = index.to_string()
  match val {
    Array(data) =>
      if index >= 0 && index < data.elements.length() {
        data.elements[index] = value
      }
    Object(data) => data.properties[key] = value
    _ => ()
  }
}

///|
/// Set the length property on an array-like value
pub fn set_array_like_length(val : Value, len : Int) -> Unit {
  match val {
    Object(data) => data.properties["length"] = Number(len.to_double())
    _ => ()
  }
}

///|
/// Delete indexed element from array-like value
pub fn delete_array_like_element(val : Value, index : Int) -> Unit {
  let key = index.to_string()
  match val {
    Object(data) => data.properties.remove(key) |> ignore
    _ => ()
  }
}

///|
/// Convert array-like value to an Array of Values
pub fn to_array_like_elements(val : Value) -> Array[Value] raise {
  let len = to_array_like_length(val)
  let result : Array[Value] = []
  for i = 0; i < len; i = i + 1 {
    result.push(get_array_like_element(val, i))
  }
  result
}

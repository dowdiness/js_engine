///|
// Helper functions (to_object, validate_accessor, get_value_property,
// apply_property_descriptor, validate_non_configurable) live in
// builtins_object_helpers.mbt.
//
// Integrity/utility factory functions (make_freeze_func, make_seal_func, …)
// live in builtins_object_integrity.mbt.
//
// This file: setup_object_builtins coordinator, Object.prototype methods,
// Object.keys/values/entries/create/assign, getPrototypeOf/setPrototypeOf,
// getOwnProperty* inspection, and the Object constructor callable.

///|
pub fn setup_object_builtins(
  env : Environment,
  sym_state : SymbolState,
) -> Unit {
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
  obj_proto_props["toString"] = @runtime.make_method_func("toString", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Undefined => Value::String_("[object Undefined]")
      Null => Value::String_("[object Null]")
      Bool(_) => Value::String_("[object Boolean]")
      Value::Number(_) => Value::String_("[object Number]")
      Value::String_(_) => Value::String_("[object String]")
      Array(_) => Value::String_("[object Array]")
      Symbol(_) => Value::String_("[object Symbol]")
      Map(_) => Value::String_("[object Map]")
      Set(_) => Value::String_("[object Set]")
      Promise(_) => Value::String_("[object Promise]")
      Proxy(_) => Value::String_("[object Object]")
      Object(data) => {
        // Per spec, always check Symbol.toStringTag first (it overrides built-in tags)
        let tag = @runtime.get_tostringtag_value(data)
        match tag {
          Some(t) => Value::String_("[object \{t}]")
          None =>
            if data.class_name == "Function" {
              Value::String_("[object Function]")
            } else if data.class_name == "RegExp" {
              Value::String_("[object RegExp]")
            } else if data.class_name == "Error" ||
              data.class_name == "TypeError" ||
              data.class_name == "ReferenceError" ||
              data.class_name == "SyntaxError" ||
              data.class_name == "RangeError" ||
              data.class_name == "URIError" ||
              data.class_name == "EvalError" ||
              data.class_name == "AggregateError" {
              Value::String_("[object Error]")
            } else if data.class_name == "Date" {
              Value::String_("[object Date]")
            } else if data.class_name == "Map" {
              Value::String_("[object Map]")
            } else if data.class_name == "Set" {
              Value::String_("[object Set]")
            } else if data.class_name == "Promise" {
              Value::String_("[object Promise]")
            } else if data.class_name == "Arguments" {
              Value::String_("[object Arguments]")
            } else if data.class_name == "Number" {
              Value::String_("[object Number]")
            } else if data.class_name == "String" {
              Value::String_("[object String]")
            } else if data.class_name == "Boolean" {
              Value::String_("[object Boolean]")
            } else {
              Value::String_("[object Object]")
            }
        }
      }
    }
  })
  obj_proto_props["valueOf"] = @runtime.make_interp_method_func("valueOf", 0, fn(
    interp,
    this_val,
    _args,
  ) raise {
    to_object(this_val, interp)
  })
  obj_proto_props["hasOwnProperty"] = @runtime.make_method_func(
    "hasOwnProperty",
    1,
    fn(this_val, args) raise {
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
            Value::Symbol(sym) => Bool(data.symbol_properties.contains(sym.id))
            _ => Bool(data.properties.contains(@runtime.to_js_string(key_val)))
          }
        Value::Array(data) =>
          match key_val {
            Value::Symbol(sym) =>
              Bool(@runtime.get_array_symbol_prop(data, sym.id) is Some(_))
            _ => {
              let key = @runtime.to_js_string(key_val)
              if key == "length" {
                Value::Bool(true)
              } else {
                // Check numeric index
                let idx = @string.parse_int(key) catch { _ => -1 }
                if idx >= 0 &&
                  idx.to_string() == key &&
                  idx < data.elements.length() {
                  Value::Bool(true)
                } else {
                  // Check named properties side-table
                  Bool(@runtime.get_array_named_prop(data, key) is Some(_))
                }
              }
            }
          }
        Value::String_(s) => {
          let key = @runtime.to_js_string(key_val)
          if key == "length" {
            Value::Bool(true)
          } else {
            let idx = @string.parse_int(key) catch { _ => -1 }
            Bool(idx >= 0 && idx.to_string() == key && idx < s.length())
          }
        }
        _ => Value::Bool(false)
      }
    },
  )
  obj_proto_props["propertyIsEnumerable"] = @runtime.make_method_func(
    "propertyIsEnumerable",
    1,
    fn(this_val, args) raise {
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
        Value::Symbol(sym) =>
          match this_val {
            Object(data) =>
              match data.symbol_descriptors.get(sym.id) {
                Some(d) => return Bool(d.enumerable)
                None =>
                  if data.symbol_properties.contains(sym.id) {
                    return Value::Bool(true)
                  } else {
                    return Value::Bool(false)
                  }
              }
            _ => return Value::Bool(false)
          }
        _ => ()
      }
      let key = @runtime.to_js_string(key_val)
      match this_val {
        Object(data) =>
          if data.properties.contains(key) {
            match data.descriptors.get(key) {
              Some(d) => Bool(d.enumerable)
              None => Value::Bool(true)
            }
          } else {
            Value::Bool(false)
          }
        Value::Array(data) =>
          if key == "length" {
            Value::Bool(false) // length is not enumerable
          } else {
            let idx = @string.parse_int(key) catch { _ => -1 }
            Bool(
              idx >= 0 && idx.to_string() == key && idx < data.elements.length(),
            )
          }
        Value::String_(s) =>
          if key == "length" {
            Value::Bool(false)
          } else {
            let idx = @string.parse_int(key) catch { _ => -1 }
            Bool(idx >= 0 && idx.to_string() == key && idx < s.length())
          }
        _ => Value::Bool(false)
      }
    },
  )
  obj_proto_props["isPrototypeOf"] = @runtime.make_interp_method_func(
    "isPrototypeOf",
    1,
    fn(interp, this_val, args) raise {
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
        Array(_) => @runtime.get_constructor_prototype(interp.global, "Array")
        Promise(_) => Null
        _ => return Value::Bool(false)
      }
      while true {
        match current {
          Null | Undefined => return Value::Bool(false)
          Object(proto_data) => {
            // Compare by reference identity - check if this_val is the same object
            match this_val {
              Object(this_data) =>
                if physical_equal(this_data, proto_data) {
                  return Value::Bool(true)
                }
              _ => ()
            }
            current = proto_data.prototype
          }
          _ => return Value::Bool(false)
        }
      }
      Value::Bool(false)
    },
  )
  obj_proto_props["toLocaleString"] = @runtime.make_method_func(
    "toLocaleString",
    0,
    fn(this_val, _args) raise {
      match this_val {
        Object(data) =>
          match data.properties.get("toString") {
            Some(Object(fn_data)) =>
              match fn_data.callable {
                Some(MethodCallable(_, f)) => f(this_val, [])
                _ => Value::String_(this_val.to_string())
              }
            _ => Value::String_(this_val.to_string())
          }
        _ => Value::String_(this_val.to_string())
      }
    },
  )
  // Annex B: __defineGetter__, __defineSetter__, __lookupGetter__, __lookupSetter__
  obj_proto_props["__defineGetter__"] = @runtime.make_interp_method_func(
    "__defineGetter__",
    2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let getter = if args.length() > 1 { args[1] } else { Undefined }
      if !@runtime.is_callable(getter) {
        raise @errors.TypeError(message="getter must be a function")
      }
      let prop = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        ""
      }
      match o {
        Object(data) => {
          // Check if property exists and is non-configurable
          match data.descriptors.get(prop) {
            Some(d) =>
              if !d.configurable {
                raise @errors.TypeError(
                  message="Cannot redefine property: \{prop}",
                )
              }
            None => ()
          }
          if !data.extensible && !data.properties.contains(prop) {
            raise @errors.TypeError(
              message="Cannot define property on a non-extensible object",
            )
          }
          let existing_setter : Value? = match data.descriptors.get(prop) {
            Some(d) => d.setter
            None => None
          }
          data.descriptors[prop] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: Some(getter),
            setter: existing_setter,
          }
          data.properties[prop] = Undefined
        }
        _ => ()
      }
      Undefined
    },
  )
  obj_proto_props["__defineSetter__"] = @runtime.make_interp_method_func(
    "__defineSetter__",
    2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let setter = if args.length() > 1 { args[1] } else { Undefined }
      if !@runtime.is_callable(setter) {
        raise @errors.TypeError(message="setter must be a function")
      }
      let prop = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        ""
      }
      match o {
        Object(data) => {
          match data.descriptors.get(prop) {
            Some(d) =>
              if !d.configurable {
                raise @errors.TypeError(
                  message="Cannot redefine property: \{prop}",
                )
              }
            None => ()
          }
          if !data.extensible && !data.properties.contains(prop) {
            raise @errors.TypeError(
              message="Cannot define property on a non-extensible object",
            )
          }
          let existing_getter : Value? = match data.descriptors.get(prop) {
            Some(d) => d.getter
            None => None
          }
          data.descriptors[prop] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: existing_getter,
            setter: Some(setter),
          }
          data.properties[prop] = Undefined
        }
        _ => ()
      }
      Undefined
    },
  )
  obj_proto_props["__lookupGetter__"] = @runtime.make_interp_method_func(
    "__lookupGetter__",
    1,
    fn(interp, this_val, args) raise {
      let prop = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        ""
      }
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
    },
  )
  obj_proto_props["__lookupSetter__"] = @runtime.make_interp_method_func(
    "__lookupSetter__",
    1,
    fn(interp, this_val, args) raise {
      let prop = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        ""
      }
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
    },
  )
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
  let obj_proto : Value = Value::Object({
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
  @runtime.object_prototype_ref.val = Some(obj_proto)
  env.def_builtin(
    "Object",
    Value::Object({
      properties: {
        "prototype": obj_proto,
        "name": Value::String_("Object"),
        "length": Value::Number(1.0),
        "keys": @runtime.make_static_func_with_length("keys", 1, fn(
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
              let sorted = @runtime.sort_property_keys(data.properties)
              for k in sorted {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  keys.push(Value::String_(k))
                }
              }
              Value::Array({ elements: keys })
            }
            Value::String_(s) => {
              // String objects have enumerable indexed properties
              let keys : Array[Value] = []
              let len = s.length()
              for i = 0; i < len; i = i + 1 {
                keys.push(Value::String_(i.to_string()))
              }
              Value::Array({ elements: keys })
            }
            Value::Array(data) => {
              // Array objects have enumerable indexed properties
              let keys : Array[Value] = []
              for i = 0; i < data.elements.length(); i = i + 1 {
                keys.push(Value::String_(i.to_string()))
              }
              Value::Array({ elements: keys })
            }
            _ => Value::Array({ elements: [] })
          }
        }),
        "values": @runtime.make_static_func_with_length("values", 1, fn(
          args,
        ) raise {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(data) => {
              let vals : Array[Value] = []
              let sorted = @runtime.sort_property_keys(data.properties)
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
              Value::Array({ elements: vals })
            }
            Value::String_(s) => {
              // String objects have enumerable indexed properties
              let vals : Array[Value] = []
              let chars = s.to_array()
              for ch in chars {
                vals.push(Value::String_(ch.to_string()))
              }
              Value::Array({ elements: vals })
            }
            Value::Array(data) => {
              // Array objects - return array elements (defensive copy)
              let vals : Array[Value] = []
              for elem in data.elements {
                vals.push(elem)
              }
              Value::Array({ elements: vals })
            }
            _ => Value::Array({ elements: [] })
          }
        }),
        "entries": @runtime.make_static_func_with_length("entries", 1, fn(
          args,
        ) raise {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(data) => {
              let entries : Array[Value] = []
              let sorted = @runtime.sort_property_keys(data.properties)
              for k in sorted {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  match data.properties.get(k) {
                    Some(v) =>
                      entries.push(
                        Value::Array({ elements: [Value::String_(k), v] }),
                      )
                    None => ()
                  }
                }
              }
              Value::Array({ elements: entries })
            }
            Value::String_(s) => {
              // String objects have enumerable indexed properties
              let entries : Array[Value] = []
              let chars = s.to_array()
              for i = 0; i < chars.length(); i = i + 1 {
                entries.push(
                  Value::Array({
                    elements: [
                      Value::String_(i.to_string()),
                      Value::String_(chars[i].to_string()),
                    ],
                  }),
                )
              }
              Value::Array({ elements: entries })
            }
            Value::Array(data) => {
              // Array objects - keys must be strings per spec
              let entries : Array[Value] = []
              for i = 0; i < data.elements.length(); i = i + 1 {
                entries.push(
                  Value::Array({
                    elements: [Value::String_(i.to_string()), data.elements[i]],
                  }),
                )
              }
              Value::Array({ elements: entries })
            }
            _ => Value::Array({ elements: [] })
          }
        }),
        "create": @runtime.make_static_func_with_length("create", 2, fn(
          args,
        ) raise {
          let proto = if args.length() > 0 { args[0] } else { Null }
          // Per spec, first argument must be Object or null
          match proto {
            Object(_)
            | Array(_)
            | Map(_)
            | Set(_)
            | Promise(_)
            | Proxy(_)
            | Null => ()
            _ =>
              raise @errors.TypeError(
                message="Object prototype may only be an Object or null: " +
                  @runtime.type_of(proto),
              )
          }
          let obj = Value::Object({
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
              Value::Proxy(proxy_data) =>
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
              | Value::String_(_)
              | Value::Number(_)
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
        "assign": @runtime.make_static_func_with_length("assign", 2, fn(
          args,
        ) raise {
          let raw_target = if args.length() > 0 { args[0] } else { Undefined }
          // Step 1: ToObject(target) — throw for null/undefined, wrap primitives
          let target : Value = match raw_target {
            Null | Undefined =>
              raise @errors.TypeError(
                message="Cannot convert undefined or null to object",
              )
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
              raw_target
            Value::Number(n) =>
              Value::Object({
                properties: { "[[NumberData]]": Value::Number(n) },
                symbol_properties: {},
                prototype: @runtime.get_number_proto(),
                callable: None,
                class_name: "Number",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            Value::Bool(b) =>
              Value::Object({
                properties: { "[[BooleanData]]": Value::Bool(b) },
                symbol_properties: {},
                prototype: @runtime.get_boolean_proto(),
                callable: None,
                class_name: "Boolean",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            Value::String_(s) => {
              let props : Map[String, Value] = {}
              props["[[StringData]]"] = Value::String_(s)
              props["length"] = Value::Number(s.length().to_double())
              let chars = s.to_array()
              for i = 0; i < chars.length(); i = i + 1 {
                let buf = StringBuilder::new()
                buf.write_char(chars[i])
                props[i.to_string()] = Value::String_(buf.to_string())
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
              Value::Object({
                properties: props,
                symbol_properties: {},
                prototype: @runtime.get_string_proto(),
                callable: None,
                class_name: "String",
                descriptors: descs,
                symbol_descriptors: {},
                extensible: true,
              })
            }
            Symbol(_) =>
              Value::Object({
                properties: { "[[SymbolData]]": raw_target },
                symbol_properties: {},
                prototype: @runtime.get_symbol_proto(),
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
                  Value::String_(s) => {
                    let chars = s.to_array()
                    for idx = 0; idx < chars.length(); idx = idx + 1 {
                      let k = idx.to_string()
                      let v = Value::String_(chars[idx].to_string())
                      // Check writable on target property
                      let can_write = match data.descriptors.get(k) {
                        Some(d) => d.writable
                        None => true
                      }
                      let exists = data.properties.contains(k)
                      if !can_write {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only property '\{k}'",
                        )
                      }
                      if !exists && !data.extensible {
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
                      if !can_write {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only property '\{k}'",
                        )
                      }
                      if !exists && !data.extensible {
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
                        if !can_write {
                          raise @errors.TypeError(
                            message="Cannot assign to read-only property '\{k}'",
                          )
                        }
                        if !exists && !data.extensible {
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
                        if !can_write {
                          raise @errors.TypeError(
                            message="Cannot assign to read-only symbol property",
                          )
                        }
                        if !exists && !data.extensible {
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
                      if !can_write {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only property '\{k}'",
                        )
                      }
                      if !exists && !data.extensible {
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
                      if !can_write {
                        raise @errors.TypeError(
                          message="Cannot assign to read-only symbol property",
                        )
                      }
                      if !exists && !data.extensible {
                        raise @errors.TypeError(
                          message="Cannot add symbol property to non-extensible object",
                        )
                      }
                      data.symbol_properties[sym_id] = v
                    })
                  }
                  // Proxy sources: unwrap to target and copy enumerable properties
                  Value::Proxy(proxy_data) =>
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
                                if !can_write {
                                  raise @errors.TypeError(
                                    message="Cannot assign to read-only property '\{k}'",
                                  )
                                }
                                if !exists && !data.extensible {
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
                                if !can_write {
                                  raise @errors.TypeError(
                                    message="Cannot assign to read-only symbol property",
                                  )
                                }
                                if !exists && !data.extensible {
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
                  Map(_) | Set(_) | Value::Number(_) | Bool(_) | Symbol(_) => ()
                }
              }
              target
            }
            _ => target
          }
        }),
        "getPrototypeOf": @runtime.make_static_func_with_length(
          "getPrototypeOf",
          1,
          fn(args) raise {
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
              Value::String_(_) => get_ctor_proto("String")
              Value::Number(_) => get_ctor_proto("Number")
              Bool(_) => get_ctor_proto("Boolean")
              Symbol(_) => get_ctor_proto("Symbol")
              Map(_) => get_ctor_proto("Map")
              Set(_) => get_ctor_proto("Set")
              Promise(_) => get_ctor_proto("Promise")
              Value::Proxy(proxy_data) =>
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
            }
          },
        ),
        "getOwnPropertyNames": make_get_own_property_names_func(),
        "getOwnPropertySymbols": make_get_own_property_symbols_func(sym_state),
        "getOwnPropertyDescriptors": make_get_own_property_descriptors_func(),
        "defineProperty": make_define_property_func(),
        "getOwnPropertyDescriptor": make_get_own_property_descriptor_func(),
        "freeze": make_freeze_func(),
        "seal": make_seal_func(),
        "preventExtensions": make_prevent_extensions_func(),
        "isFrozen": make_is_frozen_func(),
        "isSealed": make_is_sealed_func(),
        "isExtensible": make_is_extensible_func(),
        "is": make_is_func(),
        "fromEntries": make_from_entries_func(),
        "groupBy": make_group_by_func(),
        "hasOwn": make_has_own_func(),
        "setPrototypeOf": @runtime.make_static_func_with_length(
          "setPrototypeOf",
          2,
          fn(args) raise {
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
                if !data.extensible {
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
          },
        ),
        "defineProperties": make_define_properties_func(),
      },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Object", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          match val {
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
              val
            Undefined | Null =>
              Value::Object({
                properties: {},
                symbol_properties: {},
                prototype: obj_proto,
                callable: None,
                class_name: "Object",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            Value::String_(s) => {
              // ToObject: wrap string as boxed String object
              let string_proto = env.get("[[StringPrototype]]") catch {
                _ => Null
              }
              let props : Map[String, Value] = {}
              props["[[StringData]]"] = Value::String_(s)
              props["length"] = Value::Number(s.length().to_double())
              for i = 0; i < s.length(); i = i + 1 {
                props[i.to_string()] = Value::String_(s[i:i + 1].to_string())
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
              Value::Object({
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
            Value::Number(n) => {
              // ToObject: wrap number as boxed Number object
              let number_proto = env.get("[[NumberPrototype]]") catch {
                _ => Null
              }
              Value::Object({
                properties: { "[[NumberData]]": Value::Number(n) },
                symbol_properties: {},
                prototype: number_proto,
                callable: None,
                class_name: "Number",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
            Value::Bool(b) => {
              // ToObject: wrap boolean as boxed Boolean object
              let boolean_proto = env.get("[[BooleanPrototype]]") catch {
                _ => Null
              }
              Value::Object({
                properties: { "[[BooleanData]]": Value::Bool(b) },
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
              Value::Object({
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
        "name": nf_desc,
        "length": nf_desc,
        "prototype": {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
        },
        "keys": obj_method_desc,
        "values": obj_method_desc,
        "entries": obj_method_desc,
        "create": obj_method_desc,
        "assign": obj_method_desc,
        "getPrototypeOf": obj_method_desc,
        "setPrototypeOf": obj_method_desc,
        "getOwnPropertyNames": obj_method_desc,
        "getOwnPropertyDescriptor": obj_method_desc,
        "getOwnPropertyDescriptors": obj_method_desc,
        "getOwnPropertySymbols": obj_method_desc,
        "defineProperty": obj_method_desc,
        "defineProperties": obj_method_desc,
        "freeze": obj_method_desc,
        "seal": obj_method_desc,
        "isFrozen": obj_method_desc,
        "isSealed": obj_method_desc,
        "is": obj_method_desc,
        "isExtensible": obj_method_desc,
        "preventExtensions": obj_method_desc,
        "fromEntries": obj_method_desc,
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

  setup_array_builtins(env, nf_desc, obj_proto, obj_method_desc)
}

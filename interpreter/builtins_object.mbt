///|
pub fn setup_object_builtins(env : Environment) -> Unit {
  // Object.keys, Object.values, Object.entries, Object.create, Object.assign,
  // Object.getPrototypeOf, Object.getOwnPropertyNames
  let obj_proto : Value = Object({
    properties: {
      "toString": Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("toString", fn(this_val, _args) {
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
              Object(data) =>
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
                  // Check Symbol.toStringTag on object and prototype chain
                  let tag = get_tostringtag_value(data)
                  match tag {
                    Some(t) => String_("[object \{t}]")
                    None => String_("[object Object]")
                  }
                }
            }
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
      "valueOf": Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("valueOf", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
      "hasOwnProperty": Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("hasOwnProperty", fn(this_val, args) {
            let key_val = if args.length() > 0 { args[0] } else { Undefined }
            match this_val {
              Object(data) =>
                match key_val {
                  Symbol(sym) => Bool(data.symbol_properties.contains(sym.id))
                  _ => Bool(data.properties.contains(key_val.to_string()))
                }
              Array(data) => {
                let key = key_val.to_string()
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
              String_(s) => {
                let key = key_val.to_string()
                if key == "length" {
                  Bool(true)
                } else {
                  let idx = @strconv.parse_int(key) catch { _ => -1 }
                  Bool(idx >= 0 && idx.to_string() == key && idx < s.length())
                }
              }
              _ => Bool(false)
            }
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
      "propertyIsEnumerable": Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("propertyIsEnumerable", fn(this_val, args) {
            let key_val = if args.length() > 0 { args[0] } else { Undefined }
            let key = key_val.to_string()
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
      "isPrototypeOf": Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("isPrototypeOf", fn(this_val, args) {
            // Walk the argument's prototype chain looking for this_val
            let arg = if args.length() > 0 { args[0] } else { Undefined }
            let mut current : Value = match arg {
              Object(data) => data.prototype
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
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
    },
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {
      "toString": {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "valueOf": {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "hasOwnProperty": {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "propertyIsEnumerable": {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "isPrototypeOf": {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
    },
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
        "keys": make_native_func("keys", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              let keys : Array[Value] = []
              data.properties.each(fn(k, _v) {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  keys.push(String_(k))
                }
              })
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
        "values": make_native_func("values", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              let vals : Array[Value] = []
              data.properties.each(fn(k, v) {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  vals.push(v)
                }
              })
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
        "entries": make_native_func("entries", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              let entries : Array[Value] = []
              data.properties.each(fn(k, v) {
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  entries.push(Array({ elements: [String_(k), v] }))
                }
              })
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
        "create": make_native_func("create", fn(args) raise {
          let proto = if args.length() > 0 { args[0] } else { Null }
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
                            Object(desc) => {
                              let has_get = desc.properties.contains("get")
                              let has_set = desc.properties.contains("set")
                              let has_value = desc.properties.contains("value")
                              let has_writable = desc.properties.contains(
                                "writable",
                              )
                              let is_accessor = has_get || has_set
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
                                let value = match desc.properties.get("value") {
                                  Some(v) => v
                                  None => Undefined
                                }
                                data.properties[prop_name] = value
                                let writable = match
                                  desc.properties.get("writable") {
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
                            _ =>
                              raise @errors.TypeError(
                                message="Property description must be an object",
                              )
                          }
                        })
                      _ => ()
                    }
                  _ =>
                    raise @errors.TypeError(
                      message="Property descriptors must be an object",
                    )
                }
              Null | String_(_) | Number(_) | Bool(_) | Symbol(_) | Array(_) |
              Map(_) | Set(_) =>
                raise @errors.TypeError(
                  message="Property descriptors must be an object",
                )
              Object(desc_obj) =>
                // Objects have properties field
                match obj {
                  Object(data) =>
                    desc_obj.properties.each(fn(prop_name, desc_val) raise {
                      match desc_val {
                        Object(desc) => {
                          let has_get = desc.properties.contains("get")
                          let has_set = desc.properties.contains("set")
                          let is_accessor = has_get || has_set
                          let has_value = desc.properties.contains("value")
                          let has_writable = desc.properties.contains(
                            "writable",
                          )
                          let is_data = has_value || has_writable
                          // Accessor and data descriptor properties cannot be mixed
                          if is_accessor && is_data {
                            raise @errors.TypeError(
                              message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute, #<Object>",
                            )
                          }
                          if is_accessor {
                            // Accessor descriptor
                            if not(data.properties.contains(prop_name)) {
                              data.properties[prop_name] = Undefined
                            }
                            let getter : Value? = match
                              desc.properties.get("get") {
                              Some(Undefined) => None
                              Some(v) => Some(v)
                              None => None
                            }
                            let setter : Value? = match
                              desc.properties.get("set") {
                              Some(Undefined) => None
                              Some(v) => Some(v)
                              None => None
                            }
                            // Validate getter/setter are callable (or undefined)
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
                              _ => false
                            }
                            let configurable = match
                              desc.properties.get("configurable") {
                              Some(v) => is_truthy(v)
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
                            // Data descriptor
                            match desc.properties.get("value") {
                              Some(v) => data.properties[prop_name] = v
                              None =>
                                if not(data.properties.contains(prop_name)) {
                                  data.properties[prop_name] = Undefined
                                }
                            }
                            let writable = match
                              desc.properties.get("writable") {
                              Some(v) => is_truthy(v)
                              _ => false
                            }
                            let enumerable = match
                              desc.properties.get("enumerable") {
                              Some(v) => is_truthy(v)
                              _ => false
                            }
                            let configurable = match
                              desc.properties.get("configurable") {
                              Some(v) => is_truthy(v)
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
                        _ => ()
                      }
                    })
                  _ => ()
                }
              Promise(desc_obj) =>
                // Promises also have properties field
                match obj {
                  Object(data) =>
                    desc_obj.properties.each(fn(prop_name, desc_val) raise {
                      match desc_val {
                        Object(desc) => {
                          let has_get = desc.properties.contains("get")
                          let has_set = desc.properties.contains("set")
                          let is_accessor = has_get || has_set
                          let has_value = desc.properties.contains("value")
                          let has_writable = desc.properties.contains(
                            "writable",
                          )
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
                            let getter : Value? = match
                              desc.properties.get("get") {
                              Some(Undefined) => None
                              Some(v) => Some(v)
                              None => None
                            }
                            let setter : Value? = match
                              desc.properties.get("set") {
                              Some(Undefined) => None
                              Some(v) => Some(v)
                              None => None
                            }
                            // Validate getter/setter are callable (or undefined)
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
                              _ => false
                            }
                            let configurable = match
                              desc.properties.get("configurable") {
                              Some(v) => is_truthy(v)
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
                            match desc.properties.get("value") {
                              Some(v) => data.properties[prop_name] = v
                              None =>
                                if not(data.properties.contains(prop_name)) {
                                  data.properties[prop_name] = Undefined
                                }
                            }
                            let writable = match
                              desc.properties.get("writable") {
                              Some(v) => is_truthy(v)
                              _ => false
                            }
                            let enumerable = match
                              desc.properties.get("enumerable") {
                              Some(v) => is_truthy(v)
                              _ => false
                            }
                            let configurable = match
                              desc.properties.get("configurable") {
                              Some(v) => is_truthy(v)
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
                        _ => ()
                      }
                    })
                  _ => ()
                }
            }
          }
          obj
        }),
        "assign": make_native_func("assign", fn(args) raise {
          let target = if args.length() > 0 { args[0] } else { Undefined }
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
        "getPrototypeOf": make_native_func("getPrototypeOf", fn(args) raise {
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
        "getOwnPropertyNames": make_native_func("getOwnPropertyNames", fn(
          args,
        ) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              let keys : Array[Value] = []
              data.properties.each(fn(k, _v) { keys.push(String_(k)) })
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
        "getOwnPropertySymbols": make_native_func("getOwnPropertySymbols", fn(
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
        "getOwnPropertyDescriptors": make_native_func(
          "getOwnPropertyDescriptors",
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
        "defineProperty": make_native_func("defineProperty", fn(args) raise {
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
          // Extract descriptor properties - works for Object; for Array/Map/Set/Promise use empty
          let desc_props : Map[String, Value] = match descriptor {
            Object(desc) => desc.properties
            _ => {}
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
              let prop_name = prop_val.to_string()

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
                let prop_name = prop_val.to_string()
                if prop_name == "length" {
                  // Handle length property changes
                  match desc_props.get("value") {
                    Some(Number(n)) => {
                      let new_len = n.to_int()
                      if new_len < 0 || new_len.to_double() != n {
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
                    Some(_) =>
                      raise @errors.RangeError(message="Invalid array length")
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
              let prop_name = prop_val.to_string()
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
                  let prop_name = prop_val.to_string()
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
                  if not(prop_exists) && not(prop_also_in_desc) &&
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
        "getOwnPropertyDescriptor": make_native_func(
          "getOwnPropertyDescriptor",
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
        "freeze": make_native_func("freeze", fn(args) {
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
        "seal": make_native_func("seal", fn(args) {
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
        "preventExtensions": make_native_func("preventExtensions", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              data.extensible = false
              obj
            }
            _ => obj
          }
        }),
        "isFrozen": make_native_func("isFrozen", fn(args) {
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
        "isSealed": make_native_func("isSealed", fn(args) {
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
        "isExtensible": make_native_func("isExtensible", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => Bool(data.extensible)
            _ => Bool(false)
          }
        }),
        "is": make_native_func("is", fn(args) {
          // Object.is() - SameValue algorithm
          let x = if args.length() > 0 { args[0] } else { Undefined }
          let y = if args.length() > 1 { args[1] } else { Undefined }
          Bool(same_value(x, y))
        }),
        "fromEntries": make_native_func("fromEntries", fn(args) raise {
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
        "hasOwn": make_native_func("hasOwn", fn(args) {
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
        "setPrototypeOf": make_native_func("setPrototypeOf", fn(args) raise {
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
        "defineProperties": make_native_func("defineProperties", fn(
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
          match (obj, descs) {
            (Object(data), Object(desc_obj)) =>
              // Only iterate enumerable own properties of descriptors object
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
                    let prop_exists = data.properties.contains(prop_name)
                    let existing_desc = data.descriptors.get(prop_name)

                    // Validate getter/setter
                    let new_getter : Value? = if has_get {
                      match desc.properties.get("get") {
                        Some(Undefined) => Some(Undefined)
                        Some(v) => Some(v)
                        None => None
                      }
                    } else {
                      None
                    }
                    let new_setter : Value? = if has_set {
                      match desc.properties.get("set") {
                        Some(Undefined) => Some(Undefined)
                        Some(v) => Some(v)
                        None => None
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
                    let new_writable = match desc.properties.get("writable") {
                      Some(v) => Some(is_truthy(v))
                      None => None
                    }
                    let new_enumerable = match
                      desc.properties.get("enumerable") {
                      Some(v) => Some(is_truthy(v))
                      None => None
                    }
                    let new_configurable = match
                      desc.properties.get("configurable") {
                      Some(v) => Some(is_truthy(v))
                      None => None
                    }

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
                          fn() { desc.properties.get("value") },
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
                      match desc.properties.get("value") {
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
                  _ => ()
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
                          let writable = match
                            desc.properties.get("writable") {
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
                        Some(Number(n)) => {
                          let new_len = n.to_int()
                          if new_len < 0 || new_len.to_double() != n {
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
                        Some(_) =>
                          raise @errors.RangeError(
                            message="Invalid array length",
                          )
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
        NativeCallable("Object", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          match val {
            Object(_) => val
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
            _ => val
          }
        }),
      ),
      class_name: "Function",
      descriptors: {},
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

  // Non-callback methods (using MethodCallable for this-aware dispatch)
  array_proto_props["push"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("push", fn(this_val, args) raise {
        match this_val {
          Array(arr) => {
            for arg in args {
              arr.elements.push(arg)
            }
            Number(arr.elements.length().to_double())
          }
          _ => raise @errors.TypeError(message="push called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["pop"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("pop", fn(this_val, _args) raise {
        match this_val {
          Array(arr) =>
            if arr.elements.length() == 0 {
              Undefined
            } else {
              arr.elements.pop() |> Option::unwrap
            }
          _ => raise @errors.TypeError(message="pop called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["shift"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("shift", fn(this_val, _args) raise {
        match this_val {
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
          _ => raise @errors.TypeError(message="shift called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["unshift"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("unshift", fn(this_val, args) raise {
        match this_val {
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
          _ => raise @errors.TypeError(message="unshift called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["join"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("join", fn(this_val, args) {
        let len = to_array_like_length(this_val)
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
          let v = get_array_like_element(this_val, i)
          match v {
            Null | Undefined => parts.push("")
            _ => parts.push(v.to_string())
          }
        }
        String_(parts.join(sep))
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["indexOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("indexOf", fn(this_val, args) raise {
        let len = to_array_like_length(this_val)
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
          if has_array_like_element(this_val, i) {
            if strict_equal_val(get_array_like_element(this_val, i), search) {
              return Number(i.to_double())
            }
          }
        }
        Number(-1.0)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["lastIndexOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("lastIndexOf", fn(this_val, args) raise {
        let len = to_array_like_length(this_val)
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
          if has_array_like_element(this_val, i) {
            if strict_equal_val(get_array_like_element(this_val, i), search) {
              return Number(i.to_double())
            }
          }
        }
        Number(-1.0)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["includes"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("includes", fn(this_val, args) raise {
        let len = to_array_like_length(this_val)
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
          if same_value_zero(get_array_like_element(this_val, i), search) {
            return Bool(true)
          }
        }
        Bool(false)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["slice"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("slice", fn(this_val, args) raise {
        let alen = to_array_like_length(this_val)
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
          result.push(get_array_like_element(this_val, i))
        }
        Array({ elements: result })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["concat"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("concat", fn(this_val, args) {
        let result : Array[Value] = []
        // Add elements from this
        let len = to_array_like_length(this_val)
        match this_val {
          Array(arr) =>
            for el in arr.elements {
              result.push(el)
            }
          _ =>
            for i = 0; i < len; i = i + 1 {
              result.push(get_array_like_element(this_val, i))
            }
        }
        for arg in args {
          match arg {
            Array(other) =>
              for el in other.elements {
                result.push(el)
              }
            _ => result.push(arg)
          }
        }
        Array({ elements: result })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["reverse"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("reverse", fn(this_val, _args) raise {
        match this_val {
          Array(arr) => {
            arr.elements.rev_in_place()
            Array(arr)
          }
          _ => raise @errors.TypeError(message="reverse called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["fill"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("fill", fn(this_val, args) raise {
        match this_val {
          Array(arr) => {
            let fill_val = if args.length() > 0 { args[0] } else { Undefined }
            let alen = arr.elements.length()
            let mut start = if args.length() > 1 {
              to_number(args[1]).to_int()
            } else {
              0
            }
            let mut end = if args.length() > 2 {
              to_number(args[2]).to_int()
            } else {
              alen
            }
            if start < 0 {
              start = alen + start
            }
            if end < 0 {
              end = alen + end
            }
            for i = start; i < end; i = i + 1 {
              if i >= 0 && i < alen {
                arr.elements[i] = fill_val
              }
            }
            Array(arr)
          }
          _ => raise @errors.TypeError(message="fill called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["toString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toString", fn(this_val, _args) {
        let len = to_array_like_length(this_val)
        let parts : Array[String] = []
        for i = 0; i < len; i = i + 1 {
          let v = get_array_like_element(this_val, i)
          match v {
            Null | Undefined => parts.push("")
            _ => parts.push(v.to_string())
          }
        }
        String_(parts.join(","))
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["at"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("at", fn(this_val, args) raise {
        let len = to_array_like_length(this_val)
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let actual_idx = if idx < 0 { len + idx } else { idx }
        if actual_idx >= 0 && actual_idx < len {
          get_array_like_element(this_val, actual_idx)
        } else {
          Undefined
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["toLocaleString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toLocaleString", fn(this_val, _args) {
        let len = to_array_like_length(this_val)
        let parts : Array[String] = []
        for i = 0; i < len; i = i + 1 {
          let v = get_array_like_element(this_val, i)
          match v {
            Null | Undefined => parts.push("")
            _ => parts.push(v.to_string())
          }
        }
        String_(parts.join(","))
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Callback-requiring methods (using InterpreterCallable)
  array_proto_props["forEach"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("forEach", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(this_val, i) {
            let _ = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element(this_val, i),
                Number(i.to_double()),
                this_val,
              ],
              loc,
            )
          }
        }
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["map"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("map", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(this_val, i) {
            let val = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element(this_val, i),
                Number(i.to_double()),
                this_val,
              ],
              loc,
            )
            result.push(val)
          } else {
            result.push(Undefined)
          }
        }
        Array({ elements: result })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["filter"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("filter", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(this_val, i) {
            let el = get_array_like_element(this_val, i)
            let val = interp.call_value(
              callback,
              this_arg,
              [el, Number(i.to_double()), this_val],
              loc,
            )
            if is_truthy(val) {
              result.push(el)
            }
          }
        }
        Array({ elements: result })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["reduce"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("reduce", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        let mut acc : Value = Undefined
        let mut start = 0
        if args.length() > 1 {
          acc = args[1]
        } else {
          if len == 0 {
            raise @errors.TypeError(
              message="Reduce of empty array with no initial value",
            )
          }
          acc = get_array_like_element(this_val, 0)
          start = 1
        }
        for i = start; i < len; i = i + 1 {
          if has_array_like_element(this_val, i) {
            acc = interp.call_value(
              callback,
              Undefined,
              [
                acc,
                get_array_like_element(this_val, i),
                Number(i.to_double()),
                this_val,
              ],
              loc,
            )
          }
        }
        acc
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["reduceRight"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("reduceRight", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        let mut acc : Value = Undefined
        let mut start = len - 1
        if args.length() > 1 {
          acc = args[1]
        } else {
          if len == 0 {
            raise @errors.TypeError(
              message="Reduce of empty array with no initial value",
            )
          }
          acc = get_array_like_element(this_val, start)
          start = start - 1
        }
        for i = start; i >= 0; i = i - 1 {
          if has_array_like_element(this_val, i) {
            acc = interp.call_value(
              callback,
              Undefined,
              [
                acc,
                get_array_like_element(this_val, i),
                Number(i.to_double()),
                this_val,
              ],
              loc,
            )
          }
        }
        acc
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["find"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("find", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        for i = 0; i < len; i = i + 1 {
          let el = get_array_like_element(this_val, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), this_val],
            loc,
          )
          if is_truthy(val) {
            return el
          }
        }
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["findIndex"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("findIndex", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        for i = 0; i < len; i = i + 1 {
          let el = get_array_like_element(this_val, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), this_val],
            loc,
          )
          if is_truthy(val) {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["findLast"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("findLast", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        for i = len - 1; i >= 0; i = i - 1 {
          let el = get_array_like_element(this_val, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), this_val],
            loc,
          )
          if is_truthy(val) {
            return el
          }
        }
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["findLastIndex"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("findLastIndex", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        for i = len - 1; i >= 0; i = i - 1 {
          let el = get_array_like_element(this_val, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Number(i.to_double()), this_val],
            loc,
          )
          if is_truthy(val) {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["every"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("every", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(this_val, i) {
            let val = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element(this_val, i),
                Number(i.to_double()),
                this_val,
              ],
              loc,
            )
            if not(is_truthy(val)) {
              return Bool(false)
            }
          }
        }
        Bool(true)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["some"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("some", fn(interp, this_val, args) raise {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        let len = to_array_like_length(this_val)
        for i = 0; i < len; i = i + 1 {
          if has_array_like_element(this_val, i) {
            let val = interp.call_value(
              callback,
              this_arg,
              [
                get_array_like_element(this_val, i),
                Number(i.to_double()),
                this_val,
              ],
              loc,
            )
            if is_truthy(val) {
              return Bool(true)
            }
          }
        }
        Bool(false)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["sort"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("sort", fn(interp, this_val, args) raise {
        match this_val {
          Array(arr) => {
            if args.length() > 0 {
              match args[0] {
                Undefined =>
                  arr.elements.sort_by(fn(a, b) {
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
                  // Store any exception to re-throw after sort (spec requires propagation)
                  let mut caught_error : Error? = None
                  arr.elements.sort_by(fn(a, b) {
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
                    // Use sign-based comparison to avoid truncating fractional values
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
              arr.elements.sort_by(fn(a, b) {
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
            Array(arr)
          }
          _ => raise @errors.TypeError(message="sort called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["flat"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("flat", fn(this_val, args) raise {
        match this_val {
          Array(arr) => {
            let depth = if args.length() > 0 {
              to_number(args[0]).to_int()
            } else {
              1
            }
            let result : Array[Value] = []
            flatten_array_val(arr.elements, depth, result)
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="flat called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["flatMap"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("flatMap", fn(interp, this_val, args) raise {
        match this_val {
          Array(arr) => {
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            let result : Array[Value] = []
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              match val {
                Array(inner) =>
                  for el in inner.elements {
                    result.push(el)
                  }
                _ => result.push(val)
              }
            }
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="flatMap called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["splice"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("splice", fn(this_val, args) raise {
        match this_val {
          Array(arr) => {
            let alen = arr.elements.length()
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
              let d = to_number(args[1]).to_int()
              if d < 0 {
                0
              } else if d > alen - start {
                alen - start
              } else {
                d
              }
            } else {
              alen - start
            }
            let removed : Array[Value] = []
            for i = start; i < start + del_count; i = i + 1 {
              removed.push(arr.elements[i])
            }
            let new_items : Array[Value] = []
            for i = 2; i < args.length(); i = i + 1 {
              new_items.push(args[i])
            }
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
            Array({ elements: removed })
          }
          _ => raise @errors.TypeError(message="splice called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["copyWithin"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("copyWithin", fn(this_val, args) raise {
        match this_val {
          Array(arr) => {
            let len = arr.elements.length()
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
                temp.push(arr.elements[i])
              }
              for i = 0; i < count; i = i + 1 {
                if target + i < len {
                  arr.elements[target + i] = temp[i]
                }
              }
            }
            Array(arr)
          }
          _ => raise @errors.TypeError(message="copyWithin called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["entries"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("entries", fn(this_val, _args) raise {
        match this_val {
          Array(arr) => {
            let result : Array[Value] = []
            for i = 0; i < arr.elements.length(); i = i + 1 {
              result.push(
                Array({ elements: [Number(i.to_double()), arr.elements[i]] }),
              )
            }
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="entries called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["keys"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("keys", fn(this_val, _args) raise {
        match this_val {
          Array(arr) => {
            let result : Array[Value] = []
            for i = 0; i < arr.elements.length(); i = i + 1 {
              result.push(Number(i.to_double()))
            }
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="keys called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["values"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("values", fn(this_val, _args) raise {
        match this_val {
          Array(arr) => {
            // Return a copy to prevent mutation of the original
            let result : Array[Value] = []
            for el in arr.elements {
              result.push(el)
            }
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="values called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["toReversed"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toReversed", fn(this_val, _args) raise {
        match this_val {
          Array(arr) => {
            let result : Array[Value] = []
            for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
              result.push(arr.elements[i])
            }
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="toReversed called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["toSorted"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("toSorted", fn(interp, this_val, args) raise {
        match this_val {
          Array(arr) => {
            let result : Array[Value] = []
            for el in arr.elements {
              result.push(el)
            }
            if args.length() > 0 {
              match args[0] {
                Undefined =>
                  result.sort_by(fn(a, b) {
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
                  // Store any exception to re-throw after sort (spec requires propagation)
                  let mut caught_error : Error? = None
                  result.sort_by(fn(a, b) {
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
                    // Use sign-based comparison to avoid truncating fractional values
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
          }
          _ => raise @errors.TypeError(message="toSorted called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["toSpliced"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toSpliced", fn(this_val, args) raise {
        match this_val {
          Array(arr) => {
            let len = arr.elements.length()
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
              result.push(arr.elements[i])
            }
            for i = 2; i < args.length(); i = i + 1 {
              result.push(args[i])
            }
            for i = start + del_count; i < len; i = i + 1 {
              result.push(arr.elements[i])
            }
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="toSpliced called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  array_proto_props["with"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("with", fn(this_val, args) raise {
        match this_val {
          Array(arr) => {
            let idx = if args.length() > 0 {
              to_number(args[0]).to_int()
            } else {
              0
            }
            let value = if args.length() > 1 { args[1] } else { Undefined }
            let len = arr.elements.length()
            let actual_idx = if idx < 0 { len + idx } else { idx }
            if actual_idx < 0 || actual_idx >= len {
              raise @errors.RangeError(message="Invalid index")
            }
            let result : Array[Value] = []
            for i = 0; i < len; i = i + 1 {
              if i == actual_idx {
                result.push(value)
              } else {
                result.push(arr.elements[i])
              }
            }
            Array({ elements: result })
          }
          _ => raise @errors.TypeError(message="with called on non-array")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let array_proto : Value = Object({
    properties: array_proto_props,
    symbol_properties: {},
    prototype: obj_proto,
    callable: None,
    class_name: "Array",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Array constructor with Array.isArray, Array.from, Array.of
  let array_props : Map[String, Value] = {}
  array_props["prototype"] = array_proto
  array_props["isArray"] = make_native_func("isArray", fn(args) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    match val {
      Array(_) => Bool(true)
      _ => Bool(false)
    }
  })
  array_props["of"] = make_native_func("of", fn(args) {
    // Array.of() - creates array from arguments
    Array({ elements: args })
  })
  // Array.from with mapFn support using InterpreterCallable
  array_props["from"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("from", fn(interp, _this_val, args) raise {
        let source = if args.length() > 0 { args[0] } else { Undefined }
        let map_fn = if args.length() > 1 {
          match args[1] {
            Undefined => None
            fn_val => Some(fn_val)
          }
        } else {
          None
        }
        let this_arg = if args.length() > 2 { args[2] } else { Undefined }
        let loc = @token.Loc::default()
        let elements : Array[Value] = []
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
          Object(data) => {
            let len = match data.properties.get("length") {
              Some(Number(n)) => n.to_int()
              Some(v) => to_number(v).to_int() catch { _ => 0 }
              None => 0
            }
            for i = 0; i < len; i = i + 1 {
              let key = i.to_string()
              let el = match data.properties.get(key) {
                Some(v) => v
                None => Undefined
              }
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
          _ => ()
        }
        Array({ elements, })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
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
                // Array(n) produces a dense array populated with undefined values.
                // LIMITATION: This interpreter does not support sparse arrays.
                // In standard JS, Array(n) creates sparse holes (empty slots), which
                // behave differently: hasOwnProperty returns false for holes,
                // 'in' operator returns false, and forEach/map/filter skip holes.
                // Our implementation fills with undefined instead, making all indices
                // present. This is an intentional simplification.
                let len = n.to_int()
                if len < 0 || n != len.to_double() || len > 0xFFFFFFFF {
                  raise @errors.RangeError(message="Invalid array length")
                }
                let elements : Array[Value] = []
                for _i = 0; _i < len; _i = _i + 1 {
                  elements.push(Undefined)
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
      descriptors: {},
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
pub fn to_array_like_length(val : Value) -> Int {
  match val {
    Array(data) => data.elements.length()
    Object(data) =>
      match data.properties.get("length") {
        Some(Number(n)) => {
          let len = n.to_int()
          if len < 0 {
            0
          } else {
            len
          }
        }
        Some(v) => {
          let n = to_number(v) catch { _ => 0.0 }
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
    String_(s) => s.length()
    _ => 0
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
    Object(data) =>
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
/// Check if array-like value has indexed property
pub fn has_array_like_element(val : Value, index : Int) -> Bool {
  let key = index.to_string()
  match val {
    Array(data) => index >= 0 && index < data.elements.length()
    Object(data) => {
      if data.properties.contains(key) {
        return true
      }
      // Walk prototype chain
      let mut current = data.prototype
      while true {
        match current {
          Object(proto_data) =>
            if proto_data.properties.contains(key) {
              return true
            } else {
              current = proto_data.prototype
            }
          _ => break
        }
      }
      false
    }
    String_(s) => index >= 0 && index < s.length()
    _ => false
  }
}

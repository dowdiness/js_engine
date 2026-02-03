///|
pub fn setup_object_builtins(env : Environment) -> Unit {
  // Object.keys, Object.values, Object.entries, Object.create, Object.assign,
  // Object.getPrototypeOf, Object.getOwnPropertyNames
  let obj_proto : Value = Object({
    properties: {
      "toString": make_native_func("toString", fn(_args) {
        String_("[object Object]")
      }),
      "valueOf": Object({
        properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("valueOf", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      }),
      "hasOwnProperty": Object({
        properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("hasOwnProperty", fn(this_val, args) {
            let key = if args.length() > 0 {
              args[0].to_string()
            } else {
              "undefined"
            }
            match this_val {
              Object(data) => Bool(data.properties.contains(key))
              _ => Bool(false)
            }
          }),
        ),
        class_name: "Function",
        descriptors: {},
        extensible: true,
      }),
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    extensible: true,
  })
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
            _ => Array({ elements: [] })
          }
        }),
        "values": make_native_func("values", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              let vals : Array[Value] = []
              data.properties.each(fn(_k, v) { vals.push(v) })
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
                entries.push(Array({ elements: [String_(k), v] }))
              })
              Array({ elements: entries })
            }
            _ => Array({ elements: [] })
          }
        }),
        "create": make_native_func("create", fn(args) {
          let proto = if args.length() > 0 { args[0] } else { Null }
          Object({
            properties: {},
            prototype: proto,
            callable: None,
            class_name: "Object",
            descriptors: {},
            extensible: true,
          })
        }),
        "assign": make_native_func("assign", fn(args) {
          let target = if args.length() > 0 { args[0] } else { Undefined }
          match target {
            Object(data) => {
              for i = 1; i < args.length(); i = i + 1 {
                match args[i] {
                  Object(src) =>
                    src.properties.each(fn(k, v) { data.properties[k] = v })
                  _ => ()
                }
              }
              target
            }
            _ => target
          }
        }),
        "getPrototypeOf": make_native_func("getPrototypeOf", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => data.prototype
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
            _ => Array({ elements: [] })
          }
        }),
        "defineProperty": make_native_func("defineProperty", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          let prop_name = if args.length() > 1 {
            args[1].to_string()
          } else {
            ""
          }
          let descriptor = if args.length() > 2 { args[2] } else { Undefined }
          match obj {
            Object(data) =>
              match descriptor {
                Object(desc) => {
                  // Check if configurable on existing descriptor
                  match data.descriptors.get(prop_name) {
                    Some(existing) =>
                      if not(existing.configurable) {
                        raise JsException(
                          String_(
                            "TypeError: Cannot redefine property: \{prop_name}",
                          ),
                        )
                      }
                    None => ()
                  }
                  // Set value
                  match desc.properties.get("value") {
                    Some(v) => data.properties[prop_name] = v
                    None =>
                      if not(data.properties.contains(prop_name)) {
                        data.properties[prop_name] = Undefined
                      }
                  }
                  // Build descriptor
                  let existing_desc = data.descriptors.get(prop_name)
                  let writable = match desc.properties.get("writable") {
                    Some(Bool(b)) => b
                    _ =>
                      match existing_desc {
                        Some(d) => d.writable
                        None => false
                      }
                  }
                  let enumerable = match desc.properties.get("enumerable") {
                    Some(Bool(b)) => b
                    _ =>
                      match existing_desc {
                        Some(d) => d.enumerable
                        None => false
                      }
                  }
                  let configurable = match desc.properties.get("configurable") {
                    Some(Bool(b)) => b
                    _ =>
                      match existing_desc {
                        Some(d) => d.configurable
                        None => false
                      }
                  }
                  data.descriptors[prop_name] = {
                    writable,
                    enumerable,
                    configurable,
                  }
                }
                _ => ()
              }
            _ => ()
          }
          obj
        }),
        "getOwnPropertyDescriptor": make_native_func(
          "getOwnPropertyDescriptor",
          fn(args) {
            let obj = if args.length() > 0 { args[0] } else { Undefined }
            let prop_name = if args.length() > 1 {
              args[1].to_string()
            } else {
              ""
            }
            match obj {
              Object(data) =>
                match data.properties.get(prop_name) {
                  Some(val) => {
                    let desc = data.descriptors.get(prop_name)
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
                    Object({
                      properties: {
                        "value": val,
                        "writable": Bool(writable),
                        "enumerable": Bool(enumerable),
                        "configurable": Bool(configurable),
                      },
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      extensible: true,
                    })
                  }
                  None => Undefined
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
              let keys : Array[String] = []
              data.properties.each(fn(k, _v) { keys.push(k) })
              for key in keys {
                data.descriptors[key] = {
                  writable: false,
                  enumerable: match data.descriptors.get(key) {
                    Some(d) => d.enumerable
                    None => true
                  },
                  configurable: false,
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
              let keys : Array[String] = []
              data.properties.each(fn(k, _v) { keys.push(k) })
              for key in keys {
                data.descriptors[key] = {
                  writable: match data.descriptors.get(key) {
                    Some(d) => d.writable
                    None => true
                  },
                  enumerable: match data.descriptors.get(key) {
                    Some(d) => d.enumerable
                    None => true
                  },
                  configurable: false,
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
                  Some(d) =>
                    if d.configurable {
                      is_sealed = false
                    }
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
        "fromEntries": make_native_func("fromEntries", fn(args) {
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
                    }
                  _ => ()
                }
              }
            _ => ()
          }
          Object({
            properties,
            prototype: Null,
            callable: None,
            class_name: "Object",
            descriptors: {},
            extensible: true,
          })
        }),
        "hasOwn": make_native_func("hasOwn", fn(args) {
          // Object.hasOwn() - modern hasOwnProperty replacement
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          let key = if args.length() > 1 {
            args[1].to_string()
          } else {
            "undefined"
          }
          match obj {
            Object(data) => Bool(data.properties.contains(key))
            Array(data) =>
              // Arrays support numeric index check
              if key == "length" {
                Bool(true)
              } else {
                let idx = try { @strconv.parse_int(key) } catch { _ => -1 }
                Bool(idx >= 0 && idx < data.elements.length())
              }
            _ => Bool(false)
          }
        }),
        "setPrototypeOf": make_native_func("setPrototypeOf", fn(args) {
          // Note: ObjectData.prototype is immutable in current implementation
          // This is a stub that validates arguments but doesn't modify prototype
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          let proto = if args.length() > 1 { args[1] } else { Null }
          match proto {
            Object(_) | Null => ()
            _ =>
              raise JsException(
                String_(
                  "TypeError: Object prototype may only be an Object or null",
                ),
              )
          }
          obj
        }),
        "defineProperties": make_native_func("defineProperties", fn(args) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          let descs = if args.length() > 1 { args[1] } else { Undefined }
          match (obj, descs) {
            (Object(data), Object(desc_obj)) =>
              desc_obj.properties.each(fn(prop_name, desc_val) {
                match desc_val {
                  Object(desc) => {
                    match desc.properties.get("value") {
                      Some(v) => data.properties[prop_name] = v
                      None =>
                        if not(data.properties.contains(prop_name)) {
                          data.properties[prop_name] = Undefined
                        }
                    }
                    let writable = match desc.properties.get("writable") {
                      Some(Bool(b)) => b
                      _ => false
                    }
                    let enumerable = match desc.properties.get("enumerable") {
                      Some(Bool(b)) => b
                      _ => false
                    }
                    let configurable = match
                      desc.properties.get("configurable") {
                      Some(Bool(b)) => b
                      _ => false
                    }
                    data.descriptors[prop_name] = {
                      writable,
                      enumerable,
                      configurable,
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
      prototype: Null,
      callable: Some(
        NativeCallable("Object", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          match val {
            Object(_) => val
            Undefined | Null =>
              Object({
                properties: {},
                prototype: Null,
                callable: None,
                class_name: "Object",
                descriptors: {},
                extensible: true,
              })
            _ => val
          }
        }),
      ),
      class_name: "Function",
      descriptors: {},
      extensible: true,
    }),
  )

  // Array constructor with Array.isArray, Array.from, Array.of
  env.def_builtin(
    "Array",
    Object({
      properties: {
        "isArray": make_native_func("isArray", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          match val {
            Array(_) => Bool(true)
            _ => Bool(false)
          }
        }),
        "of": make_native_func("of", fn(args) {
          // Array.of() - creates array from arguments
          Array({ elements: args })
        }),
        "from": make_native_func("from", fn(args) {
          // Array.from() - creates array from array-like or iterable
          // Note: mapFn callback not supported in this basic implementation
          let source = if args.length() > 0 { args[0] } else { Undefined }
          let elements : Array[Value] = []
          match source {
            Array(data) =>
              // Copy array elements
              for el in data.elements {
                elements.push(el)
              }
            String_(s) =>
              // String -> array of characters
              for c in s.to_array() {
                elements.push(String_(c.to_string()))
              }
            Object(data) => {
              // Array-like object: has length property and indexed elements
              let len = match data.properties.get("length") {
                Some(Number(n)) => n.to_int()
                Some(v) => to_number(v).to_int()
                None => 0
              }
              for i = 0; i < len; i = i + 1 {
                let key = i.to_string()
                match data.properties.get(key) {
                  Some(v) => elements.push(v)
                  None => elements.push(Undefined)
                }
              }
            }
            _ => ()
          }
          Array({ elements, })
        }),
      },
      prototype: Null,
      callable: Some(
        NativeCallable("Array", fn(args) {
          // Array constructor behavior
          if args.length() == 1 {
            match args[0] {
              Number(n) => {
                // Array(n) creates array with n empty slots
                let len = n.to_int()
                if len < 0 || n != len.to_double() {
                  raise JsException(
                    String_("RangeError: Invalid array length"),
                  )
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
      extensible: true,
    }),
  )
}

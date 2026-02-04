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
                // Handle Symbol keys
                match key_val {
                  Symbol(sym) => Bool(data.symbol_properties.contains(sym.id))
                  _ => Bool(data.properties.contains(key_val.to_string()))
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
    },
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
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
            symbol_properties: {},
            prototype: proto,
            callable: None,
            class_name: "Object",
            descriptors: {},
            symbol_descriptors: {},
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
        "getOwnPropertyDescriptors": make_native_func("getOwnPropertyDescriptors", fn(
          args,
        ) {
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          match obj {
            Object(data) => {
              let descriptors_props : Map[String, Value] = {}
              data.properties.each(fn(key, val) {
                let desc = data.descriptors.get(key)
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
              })
              Object({
                properties: descriptors_props,
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Object",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            }
            _ => Object({
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
                        raise JsTypeError(
                          "Cannot redefine property: \{prop_name}",
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
                      symbol_properties: {},
                      prototype: Null,
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
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
                    } else {
                      raise JsTypeError("Iterator value is not an entry object")
                    }
                  Object(obj) => {
                    // Object with numeric indices 0 and 1
                    let key = match obj.properties.get("0") {
                      Some(v) => v.to_string()
                      None => raise JsTypeError("Iterator value is not an entry object")
                    }
                    let value = match obj.properties.get("1") {
                      Some(v) => v
                      None => raise JsTypeError("Iterator value is not an entry object")
                    }
                    properties[key] = value
                  }
                  _ => raise JsTypeError("Iterator value is not an entry object")
                }
              }
            _ => raise JsTypeError("Object.fromEntries requires an iterable argument")
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
                let idx = try { @strconv.parse_int(key) } catch { _ => -1 }
                Bool(idx >= 0 && idx < data.elements.length())
              }
            }
            _ => Bool(false)
          }
        }),
        "setPrototypeOf": make_native_func("setPrototypeOf", fn(args) {
          // KNOWN LIMITATION: Object.setPrototypeOf does not actually modify the prototype chain.
          // ObjectData.prototype is set at object creation and is currently immutable.
          // This stub validates arguments and returns the object per spec behavior,
          // but prototype-based inheritance changes will not take effect.
          // Implementing full mutable prototypes requires architectural changes.
          let obj = if args.length() > 0 { args[0] } else { Undefined }
          let proto = if args.length() > 1 { args[1] } else { Null }
          match proto {
            Object(_) | Null => ()
            _ =>
              raise JsTypeError(
                "Object prototype may only be an Object or null",
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
                prototype: Null,
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

  // Create Array.prototype with all array methods
  let array_proto_props : Map[String, Value] = {}

  // Non-callback methods (using MethodCallable for this-aware dispatch)
  array_proto_props["push"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("push", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          for arg in args {
            arr.elements.push(arg)
          }
          Number(arr.elements.length().to_double())
        }
        _ => raise JsTypeError("push called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["pop"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("pop", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          if arr.elements.length() == 0 {
            Undefined
          } else {
            arr.elements.pop() |> Option::unwrap
          }
        }
        _ => raise JsTypeError("pop called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["shift"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("shift", fn(this_val, _args) {
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
        _ => raise JsTypeError("shift called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["unshift"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("unshift", fn(this_val, args) {
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
        _ => raise JsTypeError("unshift called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["join"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("join", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let sep = if args.length() > 0 {
            match args[0] {
              Undefined => ","
              v => v.to_string()
            }
          } else {
            ","
          }
          let parts : Array[String] = arr.elements.map(fn(v) {
            match v {
              Null | Undefined => ""
              _ => v.to_string()
            }
          })
          String_(parts.join(sep))
        }
        _ => raise JsTypeError("join called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["indexOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("indexOf", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let search = if args.length() > 0 { args[0] } else { Undefined }
          let from_idx = if args.length() > 1 {
            to_number(args[1]).to_int()
          } else {
            0
          }
          let start = if from_idx < 0 {
            let s = arr.elements.length() + from_idx
            if s < 0 { 0 } else { s }
          } else {
            from_idx
          }
          for i = start; i < arr.elements.length(); i = i + 1 {
            if strict_equal_val(arr.elements[i], search) {
              return Number(i.to_double())
            }
          }
          Number(-1.0)
        }
        _ => raise JsTypeError("indexOf called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["lastIndexOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("lastIndexOf", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let search = if args.length() > 0 { args[0] } else { Undefined }
          let start = if args.length() > 1 {
            to_number(args[1]).to_int()
          } else {
            arr.elements.length() - 1
          }
          let from = if start < 0 {
            arr.elements.length() + start
          } else if start >= arr.elements.length() {
            arr.elements.length() - 1
          } else {
            start
          }
          for i = from; i >= 0; i = i - 1 {
            if strict_equal_val(arr.elements[i], search) {
              return Number(i.to_double())
            }
          }
          Number(-1.0)
        }
        _ => raise JsTypeError("lastIndexOf called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["includes"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("includes", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let search = if args.length() > 0 { args[0] } else { Undefined }
          for el in arr.elements {
            if same_value_zero(el, search) {
              return Bool(true)
            }
          }
          Bool(false)
        }
        _ => raise JsTypeError("includes called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["slice"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("slice", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let alen = arr.elements.length()
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
            if start < 0 { start = 0 }
          }
          if end < 0 {
            end = alen + end
            if end < 0 { end = 0 }
          }
          if end > alen { end = alen }
          let result : Array[Value] = []
          for i = start; i < end; i = i + 1 {
            result.push(arr.elements[i])
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("slice called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["concat"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("concat", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let result : Array[Value] = []
          for el in arr.elements {
            result.push(el)
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
        }
        _ => raise JsTypeError("concat called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["reverse"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("reverse", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          arr.elements.rev_in_place()
          Array(arr)
        }
        _ => raise JsTypeError("reverse called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["fill"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("fill", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let fill_val = if args.length() > 0 { args[0] } else { Undefined }
          let alen = arr.elements.length()
          let mut start = if args.length() > 1 { to_number(args[1]).to_int() } else { 0 }
          let mut end = if args.length() > 2 { to_number(args[2]).to_int() } else { alen }
          if start < 0 { start = alen + start }
          if end < 0 { end = alen + end }
          for i = start; i < end; i = i + 1 {
            if i >= 0 && i < alen {
              arr.elements[i] = fill_val
            }
          }
          Array(arr)
        }
        _ => raise JsTypeError("fill called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["toString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("toString", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          let parts : Array[String] = arr.elements.map(fn(v) {
            match v {
              Null | Undefined => ""
              _ => v.to_string()
            }
          })
          String_(parts.join(","))
        }
        _ => raise JsTypeError("toString called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["at"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("at", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let idx = if args.length() > 0 { to_number(args[0]).to_int() } else { 0 }
          let len = arr.elements.length()
          let actual_idx = if idx < 0 { len + idx } else { idx }
          if actual_idx >= 0 && actual_idx < len {
            arr.elements[actual_idx]
          } else {
            Undefined
          }
        }
        _ => raise JsTypeError("at called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["toLocaleString"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("toLocaleString", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          let parts : Array[String] = arr.elements.map(fn(v) {
            match v {
              Null | Undefined => ""
              _ => v.to_string()
            }
          })
          String_(parts.join(","))
        }
        _ => raise JsTypeError("toLocaleString called on non-array")
      }
    })),
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
    callable: Some(InterpreterCallable("forEach", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          for i = 0; i < arr.elements.length(); i = i + 1 {
            let _ = interp.call_value(
              callback,
              this_arg,
              [arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
          }
          Undefined
        }
        _ => raise JsTypeError("forEach called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["map"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("map", fn(interp, this_val, args) {
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
            result.push(val)
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("map called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["filter"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("filter", fn(interp, this_val, args) {
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
            if is_truthy(val) {
              result.push(arr.elements[i])
            }
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("filter called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["reduce"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("reduce", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let loc = @token.Loc::default()
          let mut acc : Value = Undefined
          let mut start = 0
          if args.length() > 1 {
            acc = args[1]
          } else {
            if arr.elements.length() == 0 {
              raise JsTypeError("Reduce of empty array with no initial value")
            }
            acc = arr.elements[0]
            start = 1
          }
          for i = start; i < arr.elements.length(); i = i + 1 {
            acc = interp.call_value(
              callback,
              Undefined,
              [acc, arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
          }
          acc
        }
        _ => raise JsTypeError("reduce called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["reduceRight"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("reduceRight", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let loc = @token.Loc::default()
          let mut acc : Value = Undefined
          let mut start = arr.elements.length() - 1
          if args.length() > 1 {
            acc = args[1]
          } else {
            if arr.elements.length() == 0 {
              raise JsTypeError("Reduce of empty array with no initial value")
            }
            acc = arr.elements[start]
            start = start - 1
          }
          for i = start; i >= 0; i = i - 1 {
            acc = interp.call_value(
              callback,
              Undefined,
              [acc, arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
          }
          acc
        }
        _ => raise JsTypeError("reduceRight called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["find"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("find", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          for i = 0; i < arr.elements.length(); i = i + 1 {
            let val = interp.call_value(
              callback,
              this_arg,
              [arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
            if is_truthy(val) {
              return arr.elements[i]
            }
          }
          Undefined
        }
        _ => raise JsTypeError("find called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["findIndex"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("findIndex", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          for i = 0; i < arr.elements.length(); i = i + 1 {
            let val = interp.call_value(
              callback,
              this_arg,
              [arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
            if is_truthy(val) {
              return Number(i.to_double())
            }
          }
          Number(-1.0)
        }
        _ => raise JsTypeError("findIndex called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["findLast"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("findLast", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
            let val = interp.call_value(
              callback,
              this_arg,
              [arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
            if is_truthy(val) {
              return arr.elements[i]
            }
          }
          Undefined
        }
        _ => raise JsTypeError("findLast called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["findLastIndex"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("findLastIndex", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
            let val = interp.call_value(
              callback,
              this_arg,
              [arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
            if is_truthy(val) {
              return Number(i.to_double())
            }
          }
          Number(-1.0)
        }
        _ => raise JsTypeError("findLastIndex called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["every"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("every", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          for i = 0; i < arr.elements.length(); i = i + 1 {
            let val = interp.call_value(
              callback,
              this_arg,
              [arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
            if not(is_truthy(val)) {
              return Bool(false)
            }
          }
          Bool(true)
        }
        _ => raise JsTypeError("every called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["some"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("some", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          for i = 0; i < arr.elements.length(); i = i + 1 {
            let val = interp.call_value(
              callback,
              this_arg,
              [arr.elements[i], Number(i.to_double()), Array(arr)],
              loc,
            )
            if is_truthy(val) {
              return Bool(true)
            }
          }
          Bool(false)
        }
        _ => raise JsTypeError("some called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["sort"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("sort", fn(interp, this_val, args) {
      match this_val {
        Array(arr) => {
          if args.length() > 0 {
            match args[0] {
              Undefined =>
                arr.elements.sort_by(fn(a, b) {
                  let sa = a.to_string()
                  let sb = b.to_string()
                  if sa < sb { -1 } else if sa > sb { 1 } else { 0 }
                })
              _ => {
                let comparefn = args[0]
                let loc = @token.Loc::default()
                // Store any exception to re-throw after sort (spec requires propagation)
                let mut caught_error : Error? = None
                arr.elements.sort_by(fn(a, b) {
                  if caught_error is Some(_) { return 0 }
                  let result = try {
                    interp.call_value(comparefn, Undefined, [a, b], loc)
                  } catch {
                    e => { caught_error = Some(e); return 0 }
                  }
                  // Use sign-based comparison to avoid truncating fractional values
                  let cmp = try {
                    to_number(result)
                  } catch {
                    e => { caught_error = Some(e); return 0 }
                  }
                  if cmp.is_nan() { 0 } else if cmp < 0.0 { -1 } else if cmp > 0.0 { 1 } else { 0 }
                })
                match caught_error { Some(e) => raise e; None => () }
              }
            }
          } else {
            arr.elements.sort_by(fn(a, b) {
              let sa = a.to_string()
              let sb = b.to_string()
              if sa < sb { -1 } else if sa > sb { 1 } else { 0 }
            })
          }
          Array(arr)
        }
        _ => raise JsTypeError("sort called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["flat"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("flat", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let depth = if args.length() > 0 { to_number(args[0]).to_int() } else { 1 }
          let result : Array[Value] = []
          flatten_array_val(arr.elements, depth, result)
          Array({ elements: result })
        }
        _ => raise JsTypeError("flat called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["flatMap"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("flatMap", fn(interp, this_val, args) {
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
        _ => raise JsTypeError("flatMap called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["splice"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("splice", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let alen = arr.elements.length()
          let mut start = if args.length() > 0 { to_number(args[0]).to_int() } else { 0 }
          if start < 0 {
            start = alen + start
            if start < 0 { start = 0 }
          }
          if start > alen { start = alen }
          let del_count = if args.length() > 1 {
            let d = to_number(args[1]).to_int()
            if d < 0 { 0 } else if d > alen - start { alen - start } else { d }
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
        _ => raise JsTypeError("splice called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["copyWithin"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("copyWithin", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let len = arr.elements.length()
          let mut target = if args.length() > 0 { to_number(args[0]).to_int() } else { 0 }
          let mut start = if args.length() > 1 { to_number(args[1]).to_int() } else { 0 }
          let mut end = if args.length() > 2 {
            match args[2] {
              Undefined => len
              _ => to_number(args[2]).to_int()
            }
          } else { len }
          if target < 0 { target = len + target; if target < 0 { target = 0 } }
          if start < 0 { start = len + start; if start < 0 { start = 0 } }
          if end < 0 { end = len + end; if end < 0 { end = 0 } }
          if end > len { end = len }
          let count = if end - start < len - target { end - start } else { len - target }
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
        _ => raise JsTypeError("copyWithin called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["entries"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("entries", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          let result : Array[Value] = []
          for i = 0; i < arr.elements.length(); i = i + 1 {
            result.push(Array({ elements: [Number(i.to_double()), arr.elements[i]] }))
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("entries called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["keys"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("keys", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          let result : Array[Value] = []
          for i = 0; i < arr.elements.length(); i = i + 1 {
            result.push(Number(i.to_double()))
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("keys called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["values"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("values", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          // Return a copy to prevent mutation of the original
          let result : Array[Value] = []
          for el in arr.elements {
            result.push(el)
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("values called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["toReversed"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("toReversed", fn(this_val, _args) {
      match this_val {
        Array(arr) => {
          let result : Array[Value] = []
          for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
            result.push(arr.elements[i])
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("toReversed called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["toSorted"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable("toSorted", fn(interp, this_val, args) {
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
                  if sa < sb { -1 } else if sa > sb { 1 } else { 0 }
                })
              _ => {
                let comparefn = args[0]
                let loc = @token.Loc::default()
                // Store any exception to re-throw after sort (spec requires propagation)
                let mut caught_error : Error? = None
                result.sort_by(fn(a, b) {
                  if caught_error is Some(_) { return 0 }
                  let cmp_result = try {
                    interp.call_value(comparefn, Undefined, [a, b], loc)
                  } catch {
                    e => { caught_error = Some(e); return 0 }
                  }
                  // Use sign-based comparison to avoid truncating fractional values
                  let cmp = try {
                    to_number(cmp_result)
                  } catch {
                    e => { caught_error = Some(e); return 0 }
                  }
                  if cmp.is_nan() { 0 } else if cmp < 0.0 { -1 } else if cmp > 0.0 { 1 } else { 0 }
                })
                match caught_error { Some(e) => raise e; None => () }
              }
            }
          } else {
            result.sort_by(fn(a, b) {
              let sa = a.to_string()
              let sb = b.to_string()
              if sa < sb { -1 } else if sa > sb { 1 } else { 0 }
            })
          }
          Array({ elements: result })
        }
        _ => raise JsTypeError("toSorted called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["toSpliced"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("toSpliced", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let len = arr.elements.length()
          let mut start = if args.length() > 0 { to_number(args[0]).to_int() } else { 0 }
          if start < 0 { start = len + start; if start < 0 { start = 0 } }
          if start > len { start = len }
          let del_count = if args.length() > 1 {
            let d = to_number(args[1]).to_int()
            if d < 0 { 0 } else if d > len - start { len - start } else { d }
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
        _ => raise JsTypeError("toSpliced called on non-array")
      }
    })),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  array_proto_props["with"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(MethodCallable("with", fn(this_val, args) {
      match this_val {
        Array(arr) => {
          let idx = if args.length() > 0 { to_number(args[0]).to_int() } else { 0 }
          let value = if args.length() > 1 { args[1] } else { Undefined }
          let len = arr.elements.length()
          let actual_idx = if idx < 0 { len + idx } else { idx }
          if actual_idx < 0 || actual_idx >= len {
            raise JsRangeError("Invalid index")
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
        _ => raise JsTypeError("with called on non-array")
      }
    })),
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
    callable: Some(InterpreterCallable("from", fn(interp, _this_val, args) {
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
              Some(fn_val) => interp.call_value(fn_val, this_arg, [el, Number(i.to_double())], loc)
              None => el
            }
            elements.push(mapped)
          }
        String_(s) => {
          let chars = s.to_array()
          for i = 0; i < chars.length(); i = i + 1 {
            let el = String_(chars[i].to_string())
            let mapped = match map_fn {
              Some(fn_val) => interp.call_value(fn_val, this_arg, [el, Number(i.to_double())], loc)
              None => el
            }
            elements.push(mapped)
          }
        }
        Object(data) => {
          let len = match data.properties.get("length") {
            Some(Number(n)) => n.to_int()
            Some(v) => try { to_number(v).to_int() } catch { _ => 0 }
            None => 0
          }
          for i = 0; i < len; i = i + 1 {
            let key = i.to_string()
            let el = match data.properties.get(key) {
              Some(v) => v
              None => Undefined
            }
            let mapped = match map_fn {
              Some(fn_val) => interp.call_value(fn_val, this_arg, [el, Number(i.to_double())], loc)
              None => el
            }
            elements.push(mapped)
          }
        }
        _ => ()
      }
      Array({ elements, })
    })),
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
        NativeCallable("Array", fn(args) {
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
                if len < 0 || n != len.to_double() {
                  raise JsRangeError("Invalid array length")
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
}

///|
fn flatten_array_val(elements : Array[Value], depth : Int, result : Array[Value]) -> Unit {
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

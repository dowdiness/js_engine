///|
pub fn setup_object_builtins(env : Environment) -> Unit {
  // Object.keys, Object.values, Object.entries, Object.create, Object.assign,
  // Object.getPrototypeOf, Object.getOwnPropertyNames
  let obj_proto : Value = Object({
    properties: {
      "toString": make_native_func("toString", fn(_args) {
        String_("[object Object]")
      }),
      "valueOf": make_native_func("valueOf", fn(_args) { Undefined }),
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
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
              data.properties.each(fn(k, _v) { keys.push(String_(k)) })
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
                Object(desc) =>
                  match desc.properties.get("value") {
                    Some(v) => data.properties[prop_name] = v
                    None => ()
                  }
                _ => ()
              }
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
              })
            _ => val
          }
        }),
      ),
      class_name: "Function",
    }),
  )

  // Array constructor with Array.isArray
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
      },
      prototype: Null,
      callable: Some(
        NativeCallable("Array", fn(args) { Array({ elements: args }) }),
      ),
      class_name: "Function",
    }),
  )
}

///|
/// Convert an array-like value to an Array[Value] (CreateListFromArrayLike)
fn create_list_from_array_like(val : Value) -> Array[Value] raise Error {
  match val {
    Array(data) => data.elements.copy()
    Object(data) => {
      let result : Array[Value] = []
      match data.properties.get("length") {
        Some(len_val) => {
          let len = to_number(len_val).to_int()
          for i = 0; i < len; i = i + 1 {
            match data.properties.get(i.to_string()) {
              Some(v) => result.push(v)
              None => result.push(Undefined)
            }
          }
        }
        None => ()
      }
      result
    }
    _ =>
      raise @errors.TypeError(
        message="CreateListFromArrayLike called on non-object",
      )
  }
}

///|
/// Unwrap a Proxy to get its target ObjectData, throwing TypeError if revoked.
/// Returns None if the value is not a Proxy (caller should handle Object etc directly).
fn unwrap_proxy_target(val : Value) -> ObjectData? raise Error {
  match val {
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) =>
          match target {
            Object(data) => Some(data)
            Proxy(_) => unwrap_proxy_target(target)
            _ => None
          }
        None =>
          raise @errors.TypeError(
            message="Cannot perform operation on a proxy that has been revoked",
          )
      }
    _ => None
  }
}

///|
fn setup_reflect_builtins(env : Environment) -> Unit {
  let reflect_props : Map[String, Value] = {}

  // Reflect.apply(target, thisArg, argumentsList)
  reflect_props["apply"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("apply", fn(interp, _this_val, args) {
        if args.length() < 1 {
          raise @errors.TypeError(
            message="Reflect.apply requires a target function",
          )
        }
        let target = args[0]
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let arg_list = if args.length() > 2 {
          create_list_from_array_like(args[2])
        } else {
          []
        }
        let loc = @token.Loc::default()
        interp.call_value(target, this_arg, arg_list, loc)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.construct(target, argumentsList, newTarget?)
  reflect_props["construct"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("construct", fn(interp, _this_val, args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Reflect.construct requires at least 2 arguments",
          )
        }
        let target = args[0]
        let arg_list = create_list_from_array_like(args[1])
        let loc = @token.Loc::default()
        let result = interp.construct_value(target, arg_list, loc)
        // If newTarget is provided and differs from target, re-wire the prototype
        if args.length() > 2 {
          let new_target = args[2]
          match new_target {
            Object(nt_data) => {
              let proto = match nt_data.properties.get("prototype") {
                Some(p) => p
                None => Null
              }
              match result {
                Object(res_data) => res_data.prototype = proto
                _ => ()
              }
            }
            _ => ()
          }
        }
        result
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.defineProperty(target, propertyKey, attributes)
  reflect_props["defineProperty"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("defineProperty", fn(args) {
        if args.length() < 3 {
          raise @errors.TypeError(
            message="Reflect.defineProperty requires 3 arguments",
          )
        }
        let target = args[0]
        let prop = args[1].to_string()
        let attrs = args[2]
        // Unwrap Proxy to get ObjectData
        let data : ObjectData = match target {
          Object(data) => data
          Proxy(_) =>
            match unwrap_proxy_target(target) {
              Some(data) => data
              None =>
                raise @errors.TypeError(
                  message="Reflect.defineProperty called on non-object",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.defineProperty called on non-object",
            )
        }
        // Extract descriptor attributes
        match attrs {
          Object(attr_data) => {
            let has_value = attr_data.properties.contains("value")
            let has_get = attr_data.properties.contains("get")
            let has_set = attr_data.properties.contains("set")
            if has_value && (has_get || has_set) {
              raise @errors.TypeError(
                message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute",
              )
            }
            if has_get || has_set {
              // Accessor descriptor
              let getter = attr_data.properties.get("get")
              let setter = attr_data.properties.get("set")
              let enumerable = match attr_data.properties.get("enumerable") {
                Some(v) => is_truthy(v)
                None => false
              }
              let configurable = match attr_data.properties.get(
                "configurable",
              ) {
                Some(v) => is_truthy(v)
                None => false
              }
              data.descriptors[prop] = {
                writable: false,
                enumerable,
                configurable,
                getter,
                setter,
              }
              // Remove any data value
              let _ = data.properties.remove(prop)
            } else {
              // Data descriptor
              let writable = match attr_data.properties.get("writable") {
                Some(v) => is_truthy(v)
                None => false
              }
              let enumerable = match attr_data.properties.get("enumerable") {
                Some(v) => is_truthy(v)
                None => false
              }
              let configurable = match attr_data.properties.get(
                "configurable",
              ) {
                Some(v) => is_truthy(v)
                None => false
              }
              if has_value {
                data.properties[prop] = match attr_data.properties.get(
                  "value",
                ) {
                  Some(v) => v
                  None => Undefined
                }
              }
              data.descriptors[prop] = {
                writable,
                enumerable,
                configurable,
                getter: None,
                setter: None,
              }
            }
            Bool(true)
          }
          _ =>
            raise @errors.TypeError(
              message="Property description must be an object",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.deleteProperty(target, propertyKey)
  reflect_props["deleteProperty"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("deleteProperty", fn(args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Reflect.deleteProperty requires 2 arguments",
          )
        }
        let target = args[0]
        let prop = args[1].to_string()
        let data : ObjectData = match target {
          Object(data) => data
          Proxy(_) =>
            match unwrap_proxy_target(target) {
              Some(data) => data
              None =>
                raise @errors.TypeError(
                  message="Reflect.deleteProperty called on non-object",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.deleteProperty called on non-object",
            )
        }
        match data.descriptors.get(prop) {
          Some(desc) =>
            if not(desc.configurable) {
              return Bool(false)
            }
          None => ()
        }
        let _ = data.properties.remove(prop)
        let _ = data.descriptors.remove(prop)
        Bool(true)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.get(target, propertyKey, receiver?)
  reflect_props["get"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("get", fn(interp, _this_val, args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Reflect.get requires at least 2 arguments",
          )
        }
        let target = args[0]
        let key = args[1]
        let loc = @token.Loc::default()
        // Use computed property access to handle both string and Symbol keys
        match key {
          Symbol(_) => interp.get_computed_property(target, key, loc)
          _ => interp.get_property(target, key.to_string(), loc)
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.getOwnPropertyDescriptor(target, propertyKey)
  reflect_props["getOwnPropertyDescriptor"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("getOwnPropertyDescriptor", fn(args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Reflect.getOwnPropertyDescriptor requires 2 arguments",
          )
        }
        let target = args[0]
        let prop = args[1].to_string()
        let data : ObjectData = match target {
          Object(data) => data
          Proxy(_) =>
            match unwrap_proxy_target(target) {
              Some(data) => data
              None =>
                raise @errors.TypeError(
                  message="Reflect.getOwnPropertyDescriptor called on non-object",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.getOwnPropertyDescriptor called on non-object",
            )
        }
        let has_own_data = data.properties.contains(prop)
        let has_own_desc = data.descriptors.contains(prop)
        // Property must exist in either data or descriptors
        if not(has_own_data) && not(has_own_desc) {
          return Undefined
        }
        let result_props : Map[String, Value] = {}
        match data.descriptors.get(prop) {
          Some(desc) => {
            match desc.getter {
              Some(g) => {
                // Accessor descriptor
                result_props["get"] = g
                result_props["set"] = match desc.setter {
                  Some(s) => s
                  None => Undefined
                }
              }
              None => {
                // Data descriptor
                result_props["value"] = match data.properties.get(prop) {
                  Some(v) => v
                  None => Undefined
                }
                result_props["writable"] = Bool(desc.writable)
              }
            }
            result_props["enumerable"] = Bool(desc.enumerable)
            result_props["configurable"] = Bool(desc.configurable)
          }
          None => {
            result_props["value"] = match data.properties.get(prop) {
              Some(v) => v
              None => Undefined
            }
            result_props["writable"] = Bool(true)
            result_props["enumerable"] = Bool(true)
            result_props["configurable"] = Bool(true)
          }
        }
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
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.getPrototypeOf(target)
  reflect_props["getPrototypeOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("getPrototypeOf", fn(args) {
        if args.length() < 1 {
          raise @errors.TypeError(
            message="Reflect.getPrototypeOf requires 1 argument",
          )
        }
        match args[0] {
          Object(data) => data.prototype
          Proxy(_) =>
            match unwrap_proxy_target(args[0]) {
              Some(data) => data.prototype
              None => Null
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.getPrototypeOf called on non-object",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.has(target, propertyKey)
  reflect_props["has"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("has", fn(args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Reflect.has requires 2 arguments",
          )
        }
        let target = args[0]
        let prop = args[1].to_string()
        match target {
          Object(data) => {
            if data.properties.contains(prop) {
              return Bool(true)
            }
            // Walk prototype chain
            let mut current = data.prototype
            while true {
              match current {
                Object(proto_data) =>
                  if proto_data.properties.contains(prop) {
                    return Bool(true)
                  } else {
                    current = proto_data.prototype
                  }
                _ => break
              }
            }
            Bool(false)
          }
          Array(data) => {
            let key = prop
            // Check numeric index
            try {
              let idx = @strconv.parse_int(key)
              if idx >= 0 && idx < data.elements.length() {
                return Bool(true)
              }
            } catch {
              _ => ()
            }
            if key == "length" {
              return Bool(true)
            }
            Bool(false)
          }
          Proxy(_) =>
            // Unwrap proxy and check the target
            match unwrap_proxy_target(target) {
              Some(data) => {
                if data.properties.contains(prop) {
                  return Bool(true)
                }
                let mut current = data.prototype
                while true {
                  match current {
                    Object(proto_data) =>
                      if proto_data.properties.contains(prop) {
                        return Bool(true)
                      } else {
                        current = proto_data.prototype
                      }
                    _ => break
                  }
                }
                Bool(false)
              }
              None => Bool(false)
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.has called on non-object",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.isExtensible(target)
  reflect_props["isExtensible"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("isExtensible", fn(args) {
        if args.length() < 1 {
          raise @errors.TypeError(
            message="Reflect.isExtensible requires 1 argument",
          )
        }
        match args[0] {
          Object(data) => Bool(data.extensible)
          Proxy(_) =>
            match unwrap_proxy_target(args[0]) {
              Some(data) => Bool(data.extensible)
              None => Bool(false)
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.isExtensible called on non-object",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.ownKeys(target)
  reflect_props["ownKeys"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("ownKeys", fn(interp, _this_val, args) {
        if args.length() < 1 {
          raise @errors.TypeError(
            message="Reflect.ownKeys requires 1 argument",
          )
        }
        let target = args[0]
        match target {
          Proxy(proxy_data) => {
            // Check for ownKeys trap
            let trap = get_proxy_trap(proxy_data, "ownKeys")
            match trap {
              Some(trap_fn) => {
                let proxy_target = get_proxy_target(proxy_data)
                let handler = get_proxy_handler(proxy_data)
                let loc = @token.Loc::default()
                let result = interp.call_value(
                  trap_fn, handler, [proxy_target], loc,
                )
                // Convert result array to Array[Value]
                match result {
                  Array(data) => Array({ elements: data.elements.copy() })
                  _ =>
                    raise @errors.TypeError(
                      message="'ownKeys' on proxy: trap result is not an Array",
                    )
                }
              }
              None => {
                // No trap, delegate to target
                let proxy_target = get_proxy_target(proxy_data)
                let loc = @token.Loc::default()
                interp.call_value(
                  Object({
                    properties: {},
                    symbol_properties: {},
                    prototype: Null,
                    callable: Some(
                      InterpreterCallable("ownKeys_inner", fn(
                        inner_interp,
                        _tv,
                        inner_args,
                      ) {
                        // Recursively call Reflect.ownKeys on the proxy target
                        let reflect_obj = inner_interp.global.get("Reflect") catch {
                          _ => Undefined
                        }
                        let own_keys_fn = inner_interp.get_property(
                          reflect_obj, "ownKeys", loc,
                        )
                        inner_interp.call_value(
                          own_keys_fn, Undefined, inner_args, loc,
                        )
                      }),
                    ),
                    class_name: "Function",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  }),
                  Undefined,
                  [proxy_target],
                  loc,
                )
              }
            }
          }
          _ => {
            fn collect_own_keys(data : ObjectData) -> Value {
              let keys : Array[Value] = []
              data.properties.each(fn(k, _v) { keys.push(String_(k)) })
              data.symbol_properties.each(fn(id, _v) {
                match get_symbol_by_id(id) {
                  Some(sym) => keys.push(Symbol(sym))
                  None => ()
                }
              })
              // Also include keys from descriptors not in properties
              data.descriptors.each(fn(k, _v) {
                if not(data.properties.contains(k)) {
                  keys.push(String_(k))
                }
              })
              Array({ elements: keys })
            }
            match target {
              Object(data) => collect_own_keys(data)
              Array(data) => {
                let keys : Array[Value] = []
                for i = 0; i < data.elements.length(); i = i + 1 {
                  keys.push(String_(i.to_string()))
                }
                keys.push(String_("length"))
                Array({ elements: keys })
              }
              _ =>
                raise @errors.TypeError(
                  message="Reflect.ownKeys called on non-object",
                )
            }
          }
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.preventExtensions(target)
  reflect_props["preventExtensions"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("preventExtensions", fn(args) {
        if args.length() < 1 {
          raise @errors.TypeError(
            message="Reflect.preventExtensions requires 1 argument",
          )
        }
        match args[0] {
          Object(data) => {
            data.extensible = false
            Bool(true)
          }
          Proxy(_) =>
            match unwrap_proxy_target(args[0]) {
              Some(data) => {
                data.extensible = false
                Bool(true)
              }
              None => Bool(false)
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.preventExtensions called on non-object",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.set(target, propertyKey, value, receiver?)
  reflect_props["set"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("set", fn(interp, _this_val, args) {
        if args.length() < 3 {
          raise @errors.TypeError(
            message="Reflect.set requires at least 3 arguments",
          )
        }
        let target = args[0]
        let prop = args[1].to_string()
        let value = args[2]
        // Check for write failures before attempting set
        match target {
          Object(data) => {
            match data.descriptors.get(prop) {
              Some(desc) => {
                // Accessor with getter-only: write fails
                if desc.getter is Some(_) && desc.setter is None {
                  return Bool(false)
                }
                // Non-writable data property: write fails
                if desc.getter is None && not(desc.writable) {
                  return Bool(false)
                }
              }
              None => ()
            }
            // Non-extensible and property doesn't exist: write fails
            if not(data.extensible) && not(data.properties.contains(prop)) {
              return Bool(false)
            }
          }
          _ => ()
        }
        let loc = @token.Loc::default()
        try {
          let _ = interp.set_property(target, prop, value, loc)
          Bool(true)
        } catch {
          @errors.TypeError(_) => Bool(false)
          e => raise e
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.setPrototypeOf(target, proto)
  reflect_props["setPrototypeOf"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("setPrototypeOf", fn(args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Reflect.setPrototypeOf requires 2 arguments",
          )
        }
        let target = args[0]
        let proto = args[1]
        let data : ObjectData = match target {
          Object(data) => data
          Proxy(_) =>
            match unwrap_proxy_target(target) {
              Some(data) => data
              None =>
                raise @errors.TypeError(
                  message="Reflect.setPrototypeOf called on non-object",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="Reflect.setPrototypeOf called on non-object",
            )
        }
        match proto {
          Object(_) | Null => {
            data.prototype = proto
            Bool(true)
          }
          _ =>
            raise @errors.TypeError(
              message="Object prototype may only be an Object or null",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Create the Reflect object
  let tostringtag_sym = get_tostringtag_symbol()
  let reflect_sym_props : Map[Int, Value] = {}
  reflect_sym_props[tostringtag_sym.id] = String_("Reflect")
  let reflect_obj : Value = Object({
    properties: reflect_props,
    symbol_properties: reflect_sym_props,
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  env.def_builtin("Reflect", reflect_obj)
}

///|
pub fn Interpreter::get_property(
  self : Interpreter,
  obj : Value,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) => proxy_get(self, proxy_data, prop, obj)
    Object(data) => self.get_property_of_object(obj, data, prop, loc)
    Array(data) =>
      if prop == "length" {
        match get_array_length_override(data) {
          Some(n64) => Number(n64.to_double())
          None => Number(data.elements.length().to_double())
        }
      } else {
        // Check numeric index access first
        let num_idx = @string.parse_int(prop) catch { _ => -1 }
        if num_idx >= 0 &&
          num_idx < data.elements.length() &&
          num_idx.to_string() == prop {
          data.elements[num_idx]
        } else {
          // Check named properties side table (e.g., index, input on exec results)
          match get_array_named_prop(data, prop) {
            Some(v) => v
            None => {
              let result = (self.stdlib_hooks.get_array_method_with_interp)(
                data, prop,
              )
              match result {
                Undefined => lookup_builtin_proto(self, obj, "Array", prop, loc)
                _ => result
              }
            }
          }
        }
      }
    String_(s) =>
      if prop == "length" {
        Number(utf16_length(s).to_double())
      } else {
        let result = (self.stdlib_hooks.get_string_method)(
          s,
          prop,
          self.annex_b,
        )
        match result {
          Undefined => lookup_builtin_proto(self, obj, "String", prop, loc)
          _ => result
        }
      }
    Number(_) => {
      let result = (self.stdlib_hooks.get_number_method)(obj, prop)
      match result {
        Undefined => lookup_builtin_proto(self, obj, "Number", prop, loc)
        _ => result
      }
    }
    Bool(_) => lookup_builtin_proto(self, obj, "Boolean", prop, loc)
    Symbol(sym) =>
      // Symbol properties: description, toString
      if prop == "description" {
        match sym.description {
          Some(desc) => String_(desc)
          None => Undefined
        }
      } else if prop == "toString" {
        make_native_func("toString", fn(_args) {
          match sym.description {
            Some(desc) => String_("Symbol(\{desc})")
            None => String_("Symbol()")
          }
        })
      } else {
        lookup_builtin_proto(self, obj, "Symbol", prop, loc)
      }
    Map(data) => {
      // Check expando properties first (instance fields from subclasses)
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.properties.get(prop) {
        Some(v) => return v
        None => ()
      }
      if prop == "size" {
        Number(data.entries.length().to_double())
      } else {
        (self.stdlib_hooks.get_map_method)(data, prop)
      }
    }
    Set(data) => {
      // Check expando properties first (instance fields from subclasses)
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.properties.get(prop) {
        Some(v) => return v
        None => ()
      }
      if prop == "size" {
        Number(data.values.length().to_double())
      } else {
        (self.stdlib_hooks.get_set_method)(data, prop)
      }
    }
    Promise(data) =>
      // Check user-defined properties first, then prototype methods
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => self.call_value(getter, obj, [], loc)
            None =>
              match data.properties.get(prop) {
                Some(v) => v
                None => (self.stdlib_hooks.get_promise_method)(data, prop)
              }
          }
        None =>
          match data.properties.get(prop) {
            Some(v) => v
            None => (self.stdlib_hooks.get_promise_method)(data, prop)
          }
      }
    Null =>
      raise @errors.TypeError(
        message="Cannot read properties of null (reading '\{prop}')",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot read properties of undefined (reading '\{prop}')",
      )
  }
}

///|
/// Property access for Object values: checks own properties, walks prototype chain,
/// and falls back to built-in Function/Object methods for callable objects.
fn Interpreter::get_property_of_object(
  self : Interpreter,
  obj : Value,
  data : ObjectData,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  // Check for accessor descriptor (getter) on own property
  match data.descriptors.get(prop) {
    Some(desc) =>
      match desc.getter {
        Some(getter) => return self.call_value(getter, obj, [], loc)
        None => ()
      }
    None => ()
  }
  match data.properties.get(prop) {
    Some(v) => v
    None => {
      // Walk prototype chain
      let mut current = data.prototype
      let mut func_proto_checked = false
      while true {
        match current {
          Object(proto_data) => {
            // Check for accessor descriptor (getter) on prototype property
            match proto_data.descriptors.get(prop) {
              Some(desc) =>
                match desc.getter {
                  Some(getter) => return self.call_value(getter, obj, [], loc)
                  None => ()
                }
              None => ()
            }
            match proto_data.properties.get(prop) {
              Some(v) => return v
              None => current = proto_data.prototype
            }
          }
          Array(arr_data) => {
            // Handle Array values in the prototype chain
            if prop == "length" {
              return Number(arr_data.elements.length().to_double())
            }
            // Check numeric index access on array elements
            let num_idx = @string.parse_int(prop) catch { _ => -1 }
            if num_idx >= 0 && num_idx < arr_data.elements.length() {
              return arr_data.elements[num_idx]
            }
            match get_array_named_prop(arr_data, prop) {
              Some(v) => return v
              None => {
                let result = (self.stdlib_hooks.get_array_method_with_interp)(
                  arr_data, prop,
                )
                match result {
                  Undefined => {
                    // Continue to Array.prototype
                    let ctor = self.global.get("Array") catch { _ => break }
                    match ctor {
                      Object(ctor_data) =>
                        match ctor_data.properties.get("prototype") {
                          Some(proto) => current = proto
                          None => break
                        }
                      _ => break
                    }
                  }
                  _ => return result
                }
              }
            }
          }
          Map(map_data) => {
            // Handle Map values in the prototype chain
            if prop == "size" {
              return Number(map_data.entries.length().to_double())
            }
            let result = (self.stdlib_hooks.get_map_method)(map_data, prop)
            match result {
              Undefined => {
                let ctor = self.global.get("Map") catch { _ => break }
                match ctor {
                  Object(ctor_data) =>
                    match ctor_data.properties.get("prototype") {
                      Some(proto) => current = proto
                      None => break
                    }
                  _ => break
                }
              }
              _ => return result
            }
          }
          Set(set_data) => {
            // Handle Set values in the prototype chain
            if prop == "size" {
              return Number(set_data.values.length().to_double())
            }
            let result = (self.stdlib_hooks.get_set_method)(set_data, prop)
            match result {
              Undefined => {
                let ctor = self.global.get("Set") catch { _ => break }
                match ctor {
                  Object(ctor_data) =>
                    match ctor_data.properties.get("prototype") {
                      Some(proto) => current = proto
                      None => break
                    }
                  _ => break
                }
              }
              _ => return result
            }
          }
          Null =>
            // For function objects, fall back to Function.prototype (once)
            if !func_proto_checked {
              match data.callable {
                Some(_) => {
                  let fp = self.global.get("[[FunctionPrototype]]") catch {
                    _ => break
                  }
                  func_proto_checked = true
                  current = fp
                }
                None => break
              }
            } else {
              break
            }
          _ => break
        }
      }
      // Built-in Function methods (for callable objects)
      match data.callable {
        Some(callable) =>
          if prop == "call" {
            return Object({
              properties: {},
              symbol_properties: {},
              prototype: Null,
              callable: Some(FuncCallMethod(obj)),
              class_name: "Function",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })
          } else if prop == "apply" {
            return Object({
              properties: {},
              symbol_properties: {},
              prototype: Null,
              callable: Some(FuncApplyMethod(obj)),
              class_name: "Function",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })
          } else if prop == "bind" {
            let target = obj
            let target_length = get_func_length(callable)
            return make_native_func("bind", fn(args) {
              let bind_this = if args.length() > 0 {
                args[0]
              } else {
                Undefined
              }
              let bound_args : Array[Value] = []
              for i = 1; i < args.length(); i = i + 1 {
                bound_args.push(args[i])
              }
              let bound_name = get_bound_func_name(target)
              let bound_length = {
                let diff = target_length - bound_args.length()
                if diff < 0 {
                  0
                } else {
                  diff
                }
              }
              let nf_desc : PropDescriptor = {
                writable: false,
                enumerable: false,
                configurable: true,
                getter: None,
                setter: None,
              }
              let bprops : Map[String, Value] = {}
              bprops["name"] = String_(bound_name)
              bprops["length"] = Number(bound_length.to_double())
              Object({
                properties: bprops,
                symbol_properties: {},
                prototype: get_func_proto(),
                callable: Some(BoundFunc(target, bind_this, bound_args)),
                class_name: "Function",
                descriptors: { "name": nf_desc, "length": nf_desc },
                symbol_descriptors: {},
                extensible: true,
              })
            })
          } else if prop == "length" {
            // Return the number of formal parameters
            let param_count = get_func_length(callable)
            return Number(param_count.to_double())
          } else if prop == "name" {
            // Return the function name
            let func_name : String = match callable {
              UserFunc(func_data) => func_data.name.unwrap_or("")
              UserFuncExt(func_data) => func_data.name.unwrap_or("")
              ArrowFunc(_) => ""
              ArrowFuncExt(_) => ""
              BoundFunc(target, _, _) => get_bound_func_name(target)
              NativeCallable(n, _) => n
              NonConstructableCallable(n, _) => n
              FuncCallMethod(_) => "call"
              FuncApplyMethod(_) => "apply"
              MethodCallable(n, _) => n
              InterpreterCallable(n, _) => n
              ConstructorOnlyCallable(n, _) => n
              ClassConstructor({ name: n, .. }) => n
            }
            return String_(func_name)
          } else if prop == "toString" {
            // Return function string representation
            let func_str : String = match callable {
              UserFunc(func_data) => {
                let name = func_data.name.unwrap_or("")
                "function " + name + "() { [native code] }"
              }
              UserFuncExt(func_data) => {
                let name = func_data.name.unwrap_or("")
                "function " + name + "() { [native code] }"
              }
              ArrowFunc(_) => "() => { [native code] }"
              ArrowFuncExt(_) => "() => { [native code] }"
              BoundFunc(_, _, _) => "function () { [native code] }"
              NativeCallable(n, _) => "function " + n + "() { [native code] }"
              NonConstructableCallable(n, _) =>
                "function " + n + "() { [native code] }"
              FuncCallMethod(_) => "function call() { [native code] }"
              FuncApplyMethod(_) => "function apply() { [native code] }"
              MethodCallable(n, _) => "function " + n + "() { [native code] }"
              InterpreterCallable(n, _) =>
                "function " + n + "() { [native code] }"
              ConstructorOnlyCallable(n, _) =>
                "function " + n + "() { [native code] }"
              ClassConstructor({ name: n, .. }) =>
                "class " + n + " { [native code] }"
            }
            return make_native_func("toString", fn(_args) { String_(func_str) })
          } else if prop == "prototype" {
            // Only constructable functions have a prototype property
            // Non-constructable (arrow functions, bound functions, etc.) return undefined
            let is_constructable = match callable {
              UserFunc(_)
              | UserFuncExt(_)
              | NativeCallable(_, _)
              | ConstructorOnlyCallable(_, _)
              | ClassConstructor(_) => true
              ArrowFunc(_)
              | ArrowFuncExt(_)
              | BoundFunc(_, _, _)
              | NonConstructableCallable(_, _)
              | FuncCallMethod(_)
              | FuncApplyMethod(_)
              | MethodCallable(_, _)
              | InterpreterCallable(_, _) => false
            }
            if !is_constructable {
              return Undefined
            }
            // For constructable functions, check if prototype exists
            match data.properties.get("prototype") {
              Some(p) => return p
              None => {
                // Create and memoize default prototype
                let proto : Value = Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: get_obj_proto(),
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
                data.properties["prototype"] = proto
                return proto
              }
            }
          }
        None => ()
      }
      // Built-in Object methods (only for objects that inherit from Object.prototype)
      // Objects with null prototype (Object.create(null)) should NOT have these
      if !(data.prototype is Null && data.callable is None) {
        if prop == "hasOwnProperty" {
          return make_method_func("hasOwnProperty", 1, fn(this_val, args) {
            let key_val = if args.length() > 0 { args[0] } else { Undefined }
            match this_val {
              Object(d) =>
                match key_val {
                  Symbol(sym) => Bool(d.symbol_properties.contains(sym.id))
                  _ => Bool(d.properties.contains(key_val.to_string()))
                }
              Array(ad) =>
                match key_val {
                  Symbol(sym) =>
                    Bool(get_array_symbol_prop(ad, sym.id) is Some(_))
                  _ => {
                    let k = key_val.to_string()
                    if k == "length" {
                      return Bool(true)
                    }
                    let idx = @string.parse_int(k) catch { _ => -1 }
                    if idx >= 0 &&
                      idx.to_string() == k &&
                      idx < ad.elements.length() {
                      Bool(true)
                    } else {
                      Bool(get_array_named_prop(ad, k) is Some(_))
                    }
                  }
                }
              _ => Bool(false)
            }
          })
        }
        if prop == "toString" {
          return make_native_func("toString", fn(_args) {
            String_("[object Object]")
          })
        }
      }
      Undefined
    }
  }
}

///|
/// Look up a property on a built-in constructor's prototype (e.g. Array.prototype.constructor)
fn lookup_builtin_proto(
  interp : Interpreter,
  receiver : Value,
  ctor_name : String,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  let ctor = interp.global.get(ctor_name) catch { _ => return Undefined }
  match ctor {
    Object(ctor_data) =>
      match ctor_data.properties.get("prototype") {
        Some(Object(proto_data)) => {
          // Walk up prototype chain and honor accessor getters with `receiver`.
          let mut current : Value = Object(proto_data)
          while true {
            match current {
              Object(pdata) => {
                match pdata.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.getter {
                      Some(getter) =>
                        return interp.call_value(getter, receiver, [], loc)
                      None =>
                        match pdata.properties.get(prop) {
                          Some(v) => return v
                          None => ()
                        }
                    }
                  None =>
                    match pdata.properties.get(prop) {
                      Some(v) => return v
                      None => ()
                    }
                }
                current = pdata.prototype
              }
              _ => break
            }
          }
          Undefined
        }
        _ => Undefined
      }
    _ => Undefined
  }
}

///|
pub fn Interpreter::get_computed_property(
  self : Interpreter,
  obj : Value,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  // Handle Proxy objects first
  match obj {
    Proxy(proxy_data) => {
      // For string keys, use proxy_get with invariant checks
      // For symbol keys, call the trap directly (invariant checks TODO)
      let key_str = match key {
        Symbol(_) => ""
        _ => to_js_string(key)
      }
      match key {
        Symbol(_) => {
          let trap = get_proxy_trap(proxy_data, "get", self)
          match trap {
            Some(trap_fn) => {
              let target = get_proxy_target(proxy_data)
              let handler = get_proxy_handler(proxy_data)
              return self.call_value(trap_fn, handler, [target, key, obj], loc)
            }
            None => {
              let target = get_proxy_target(proxy_data)
              return self.get_computed_property(target, key, loc)
            }
          }
        }
        _ => return proxy_get(self, proxy_data, key_str, obj)
      }
    }
    _ => ()
  }
  // Handle Symbol keys specially
  match key {
    Symbol(sym) =>
      match obj {
        Object(data) => {
          // Check for symbol accessor descriptor (getter)
          match data.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => ()
              }
            None => ()
          }
          // Look up symbol property
          match data.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => {
              // Walk prototype chain for symbol properties
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    // Check for accessor on prototype
                    match proto_data.symbol_descriptors.get(sym.id) {
                      Some(desc) =>
                        match desc.getter {
                          Some(getter) =>
                            return self.call_value(getter, obj, [], loc)
                          None => ()
                        }
                      None => ()
                    }
                    match proto_data.symbol_properties.get(sym.id) {
                      Some(v) => return v
                      None => current = proto_data.prototype
                    }
                  }
                  _ => break
                }
              }
              // Boxed primitive objects: delegate Symbol.iterator to primitive
              let iterator_sym = get_iterator_symbol()
              if sym.id == iterator_sym.id {
                if data.class_name == "String" {
                  match data.properties.get("[[StringData]]") {
                    Some(String_(_)) =>
                      return make_method_func("[Symbol.iterator]", 0, fn(
                        this_val,
                        _args,
                      ) raise {
                        let str = match this_val {
                          String_(sv) => sv
                          Object(d) =>
                            if d.class_name == "String" {
                              match d.properties.get("[[StringData]]") {
                                Some(String_(sv)) => sv
                                _ => this_val.to_string()
                              }
                            } else {
                              this_val.to_string()
                            }
                          Null | Undefined =>
                            raise @errors.TypeError(
                              message="Cannot convert undefined or null to object",
                            )
                          _ => this_val.to_string()
                        }
                        make_string_iterator_value(str)
                      })
                    _ => ()
                  }
                } else if data.class_name == "Array" {
                  // Shouldn't reach here for arrays normally, but fallback
                  ()
                }
              }
              return Undefined
            }
          }
        }
        String_(s) => {
          // Handle Symbol.iterator for strings
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            // Return a function that creates a string iterator
            return make_method_func("[Symbol.iterator]", 0, fn(
              _this_val,
              _args,
            ) {
              make_string_iterator_value(s)
            })
          }
          return Undefined
        }
        Array(arr) => {
          // Check array's own symbol property side-table first
          match get_array_symbol_prop(arr, sym.id) {
            Some(v) => return v
            None => ()
          }
          // Check Array.prototype for symbol properties (e.g. overridden Symbol.iterator)
          let array_ctor = self.global.get("Array") catch { _ => Undefined }
          match array_ctor {
            Object(ctor_data) =>
              match ctor_data.properties.get("prototype") {
                Some(Object(proto_data)) => {
                  // Check symbol descriptors for getters
                  match proto_data.symbol_descriptors.get(sym.id) {
                    Some(desc) =>
                      match desc.getter {
                        Some(getter) =>
                          return self.call_value(getter, obj, [], loc)
                        None => ()
                      }
                    None => ()
                  }
                  // Check symbol properties
                  match proto_data.symbol_properties.get(sym.id) {
                    Some(v) => return v
                    None => ()
                  }
                }
                _ => ()
              }
            _ => ()
          }
          // Handle Symbol.iterator default for arrays
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            let (override_getter, override_value) = get_array_iterator_override(
              arr,
            )
            match override_getter {
              Some(getter) => return self.call_value(getter, obj, [], loc)
              None => ()
            }
            match override_value {
              Some(v) => return v
              None => ()
            }
            // Return default array iterator
            return make_method_func("[Symbol.iterator]", 0, fn(
              _this_val,
              _args,
            ) {
              make_array_iterator_value(arr)
            })
          }
          return Undefined
        }
        Map(map_data) => {
          // Check expando symbol properties first (instance fields from subclasses)
          match map_data.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => ()
              }
            None => ()
          }
          match map_data.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => ()
          }
          // Well-known symbols
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            return (self.stdlib_hooks.get_map_method)(map_data, "entries")
          }
          let tostringtag_sym = get_tostringtag_symbol()
          if sym.id == tostringtag_sym.id {
            return String_("Map")
          }
          return Undefined
        }
        Set(set_data) => {
          // Check expando symbol properties first (instance fields from subclasses)
          match set_data.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => ()
              }
            None => ()
          }
          match set_data.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => ()
          }
          // Well-known symbols
          let iterator_sym = get_iterator_symbol()
          if sym.id == iterator_sym.id {
            return (self.stdlib_hooks.get_set_method)(set_data, "values")
          }
          let tostringtag_sym = get_tostringtag_symbol()
          if sym.id == tostringtag_sym.id {
            return String_("Set")
          }
          return Undefined
        }
        Promise(data) =>
          match data.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => return Undefined
          }
        Symbol(_) => {
          // Delegate to Symbol.prototype for symbol-keyed property access
          let proto = self.global.get("[[SymbolPrototype]]") catch { _ => Null }
          match proto {
            Object(proto_data) => {
              match proto_data.symbol_descriptors.get(sym.id) {
                Some(desc) =>
                  match desc.getter {
                    Some(getter) => return self.call_value(getter, obj, [], loc)
                    None => ()
                  }
                None => ()
              }
              match proto_data.symbol_properties.get(sym.id) {
                Some(v) => return v
                None => return Undefined
              }
            }
            _ => return Undefined
          }
        }
        _ => return Undefined
      }
    _ => ()
  }
  match obj {
    Object(data) => {
      // TypedArray indexed access: intercept numeric keys before regular property lookup
      if is_typedarray_class(data.class_name) {
        match key {
          Number(n) => {
            let idx = n.to_int()
            if idx.to_double() == n && idx >= 0 {
              return (self.stdlib_hooks.typedarray_get_index)(data, idx)
            }
            // Non-integer or negative Number key: return undefined per spec
            return Undefined
          }
          String_(s) =>
            // Canonical numeric index string check per spec
            // Note: "-0" is NOT canonical (ToString(ToNumber("-0")) === "0"), so it falls through
            try {
              let n = @string.parse_double(s)
              // If string converts to a number and back to same string, it's a canonical numeric index
              if n.to_string() == s {
                let idx = n.to_int()
                if idx.to_double() == n && idx >= 0 {
                  return (self.stdlib_hooks.typedarray_get_index)(data, idx)
                }
                // Canonical numeric index but not a valid integer index
                return Undefined
              }
            } catch {
              _ => () // Not a numeric string, fall through to normal property lookup
            }
          _ => ()
        }
      }
      let prop = to_js_string(key)
      // Check for accessor descriptor (getter) on own property
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.properties.get(prop) {
        Some(v) => v
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                // Check for accessor descriptor on prototype
                match proto_data.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.getter {
                      Some(getter) =>
                        return self.call_value(getter, obj, [], loc)
                      None => ()
                    }
                  None => ()
                }
                match proto_data.properties.get(prop) {
                  Some(v) => return v
                  None => current = proto_data.prototype
                }
              }
              Array(arr_data) => {
                if prop == "length" {
                  return Number(arr_data.elements.length().to_double())
                }
                // Check numeric index access on array elements
                let num_idx2 = @string.parse_int(prop) catch { _ => -1 }
                if num_idx2 >= 0 && num_idx2 < arr_data.elements.length() {
                  return arr_data.elements[num_idx2]
                }
                match get_array_named_prop(arr_data, prop) {
                  Some(v) => return v
                  None => {
                    let result = (self.stdlib_hooks.get_array_method_with_interp)(
                      arr_data, prop,
                    )
                    match result {
                      Undefined => {
                        let ctor = self.global.get("Array") catch { _ => break }
                        match ctor {
                          Object(ctor_data) =>
                            match ctor_data.properties.get("prototype") {
                              Some(proto) => current = proto
                              None => break
                            }
                          _ => break
                        }
                      }
                      _ => return result
                    }
                  }
                }
              }
              Map(map_data) => {
                if prop == "size" {
                  return Number(map_data.entries.length().to_double())
                }
                let result = (self.stdlib_hooks.get_map_method)(map_data, prop)
                match result {
                  Undefined => {
                    let ctor = self.global.get("Map") catch { _ => break }
                    match ctor {
                      Object(ctor_data) =>
                        match ctor_data.properties.get("prototype") {
                          Some(proto) => current = proto
                          None => break
                        }
                      _ => break
                    }
                  }
                  _ => return result
                }
              }
              Set(set_data) => {
                if prop == "size" {
                  return Number(set_data.values.length().to_double())
                }
                let result = (self.stdlib_hooks.get_set_method)(set_data, prop)
                match result {
                  Undefined => {
                    let ctor = self.global.get("Set") catch { _ => break }
                    match ctor {
                      Object(ctor_data) =>
                        match ctor_data.properties.get("prototype") {
                          Some(proto) => current = proto
                          None => break
                        }
                      _ => break
                    }
                  }
                  _ => return result
                }
              }
              _ => break
            }
          }
          // Built-in Function methods (for callable objects)
          match data.callable {
            Some(callable) =>
              if prop == "call" {
                return Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: Null,
                  callable: Some(FuncCallMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else if prop == "apply" {
                return Object({
                  properties: {},
                  symbol_properties: {},
                  prototype: Null,
                  callable: Some(FuncApplyMethod(obj)),
                  class_name: "Function",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
              } else if prop == "bind" {
                let target = obj
                let target_length = get_func_length(callable)
                return make_native_func("bind", fn(args) {
                  let bind_this = if args.length() > 0 {
                    args[0]
                  } else {
                    Undefined
                  }
                  let bound_args : Array[Value] = []
                  for i = 1; i < args.length(); i = i + 1 {
                    bound_args.push(args[i])
                  }
                  let bound_name = get_bound_func_name(target)
                  let bound_length = {
                    let diff = target_length - bound_args.length()
                    if diff < 0 {
                      0
                    } else {
                      diff
                    }
                  }
                  let nf_desc : PropDescriptor = {
                    writable: false,
                    enumerable: false,
                    configurable: true,
                    getter: None,
                    setter: None,
                  }
                  let bprops : Map[String, Value] = {}
                  bprops["name"] = String_(bound_name)
                  bprops["length"] = Number(bound_length.to_double())
                  Object({
                    properties: bprops,
                    symbol_properties: {},
                    prototype: get_func_proto(),
                    callable: Some(BoundFunc(target, bind_this, bound_args)),
                    class_name: "Function",
                    descriptors: { "name": nf_desc, "length": nf_desc },
                    symbol_descriptors: {},
                    extensible: true,
                  })
                })
              } else if prop == "length" {
                // Return the number of formal parameters
                let param_count = get_func_length(callable)
                return Number(param_count.to_double())
              } else if prop == "name" {
                // Return the function name
                let func_name : String = match callable {
                  UserFunc(func_data) => func_data.name.unwrap_or("")
                  UserFuncExt(func_data) => func_data.name.unwrap_or("")
                  ArrowFunc(_) => ""
                  ArrowFuncExt(_) => ""
                  BoundFunc(target, _, _) => get_bound_func_name(target)
                  NativeCallable(n, _) => n
                  NonConstructableCallable(n, _) => n
                  FuncCallMethod(_) => "call"
                  FuncApplyMethod(_) => "apply"
                  MethodCallable(n, _) => n
                  InterpreterCallable(n, _) => n
                  ConstructorOnlyCallable(n, _) => n
                  ClassConstructor({ name: n, .. }) => n
                }
                return String_(func_name)
              } else if prop == "toString" {
                // Return function string representation
                let func_str : String = match callable {
                  UserFunc(func_data) => {
                    let name = func_data.name.unwrap_or("")
                    "function " + name + "() { [native code] }"
                  }
                  UserFuncExt(func_data) => {
                    let name = func_data.name.unwrap_or("")
                    "function " + name + "() { [native code] }"
                  }
                  ArrowFunc(_) => "() => { [native code] }"
                  ArrowFuncExt(_) => "() => { [native code] }"
                  BoundFunc(_, _, _) => "function () { [native code] }"
                  NativeCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  NonConstructableCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  FuncCallMethod(_) => "function call() { [native code] }"
                  FuncApplyMethod(_) => "function apply() { [native code] }"
                  MethodCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  InterpreterCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ConstructorOnlyCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ClassConstructor({ name: n, .. }) =>
                    "class " + n + " { [native code] }"
                }
                return make_native_func("toString", fn(_args) {
                  String_(func_str)
                })
              } else if prop == "prototype" {
                // Only constructable functions have a prototype property
                // Non-constructable (arrow functions, bound functions, etc.) return undefined
                let is_constructable = match callable {
                  UserFunc(_)
                  | UserFuncExt(_)
                  | NativeCallable(_, _)
                  | ConstructorOnlyCallable(_, _)
                  | ClassConstructor(_) => true
                  ArrowFunc(_)
                  | ArrowFuncExt(_)
                  | BoundFunc(_, _, _)
                  | NonConstructableCallable(_, _)
                  | FuncCallMethod(_)
                  | FuncApplyMethod(_)
                  | MethodCallable(_, _)
                  | InterpreterCallable(_, _) => false
                }
                if !is_constructable {
                  return Undefined
                }
                // For constructable functions, check if prototype exists
                match data.properties.get("prototype") {
                  Some(p) => return p
                  None => {
                    // Create and memoize default prototype
                    let proto : Value = Object({
                      properties: {},
                      symbol_properties: {},
                      prototype: get_obj_proto(),
                      callable: None,
                      class_name: "Object",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                    data.properties["prototype"] = proto
                    return proto
                  }
                }
              }
            None => ()
          }
          // Built-in Object methods (only for objects that inherit from Object.prototype)
          if !(data.prototype is Null && data.callable is None) {
            if prop == "hasOwnProperty" {
              return make_method_func("hasOwnProperty", 1, fn(this_val, args) {
                let key_val = if args.length() > 0 {
                  args[0]
                } else {
                  Undefined
                }
                match this_val {
                  Object(d) =>
                    match key_val {
                      Symbol(sym) => Bool(d.symbol_properties.contains(sym.id))
                      _ => Bool(d.properties.contains(key_val.to_string()))
                    }
                  Array(ad) =>
                    match key_val {
                      Symbol(sym) =>
                        Bool(get_array_symbol_prop(ad, sym.id) is Some(_))
                      _ => {
                        let k = key_val.to_string()
                        if k == "length" {
                          return Bool(true)
                        }
                        let idx = @string.parse_int(k) catch { _ => -1 }
                        if idx >= 0 &&
                          idx.to_string() == k &&
                          idx < ad.elements.length() {
                          Bool(true)
                        } else {
                          Bool(get_array_named_prop(ad, k) is Some(_))
                        }
                      }
                    }
                  _ => Bool(false)
                }
              })
            }
            if prop == "toString" {
              return make_native_func("toString", fn(_args) {
                String_("[object Object]")
              })
            }
          }
          Undefined
        }
      }
    }
    Array(data) =>
      match key {
        Number(n) => {
          let i = n.to_int()
          if i >= 0 && i < data.elements.length() {
            data.elements[i]
          } else {
            Undefined
          }
        }
        String_("length") => Number(data.elements.length().to_double())
        String_(s) => {
          // Canonical numeric index string check: parseDouble(s).toString() === s
          let mut numeric_result : Value? = None
          try {
            let n = @string.parse_double(s)
            if n.to_string() == s {
              let idx = n.to_int()
              if idx.to_double() == n &&
                idx >= 0 &&
                idx < data.elements.length() {
                numeric_result = Some(data.elements[idx])
              }
            }
          } catch {
            _ => () // Not a numeric string
          }
          match numeric_result {
            Some(v) => v
            None =>
              // Check side table for named properties, then methods
              match get_array_named_prop(data, s) {
                Some(v) => v
                None =>
                  (self.stdlib_hooks.get_array_method_with_interp)(data, s)
              }
          }
        }
        Symbol(sym) =>
          match get_array_symbol_prop(data, sym.id) {
            Some(v) => v
            None => Undefined
          }
        _ => Undefined
      }
    String_(s) =>
      match key {
        Number(n) => {
          let i = n.to_int()
          if i >= 0 && i < s.length() {
            let buf = StringBuilder::new()
            buf.write_char(s.to_array()[i])
            String_(buf.to_string())
          } else {
            Undefined
          }
        }
        String_("length") => Number(utf16_length(s).to_double())
        String_(method_name) =>
          (self.stdlib_hooks.get_string_method)(s, method_name, self.annex_b)
        _ => Undefined
      }
    Number(_) =>
      match key {
        String_(method_name) =>
          (self.stdlib_hooks.get_number_method)(obj, method_name)
        _ => Undefined
      }
    Promise(data) =>
      match key {
        Symbol(sym) =>
          match data.symbol_properties.get(sym.id) {
            Some(v) => v
            None => Undefined
          }
        _ => {
          let prop = to_js_string(key)
          match data.properties.get(prop) {
            Some(v) => v
            None => (self.stdlib_hooks.get_promise_method)(data, prop)
          }
        }
      }
    Null => {
      let key_str = match key {
        Symbol(sym) => "Symbol(\{sym.description})"
        String_(s) => s
        Number(n) => n.to_string()
        Bool(b) => b.to_string()
        _ => ""
      }
      raise @errors.TypeError(
        message="Cannot read properties of null (reading '\{key_str}')",
      )
    }
    Undefined => {
      let key_str = match key {
        Symbol(sym) => "Symbol(\{sym.description})"
        String_(s) => s
        Number(n) => n.to_string()
        Bool(b) => b.to_string()
        _ => ""
      }
      raise @errors.TypeError(
        message="Cannot read properties of undefined (reading '\{key_str}')",
      )
    }
    _ => Undefined
  }
}

///|
pub fn Interpreter::set_property(
  self : Interpreter,
  obj : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
  strict? : Bool = false,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) =>
      proxy_set(self, proxy_data, prop, value, obj, strict)
    Object(data) => {
      // TypedArray indexed write via dot notation (numeric string prop)
      if is_typedarray_class(data.class_name) {
        // Canonical numeric index string check per spec
        // Note: "-0" is NOT canonical (ToString(ToNumber("-0")) === "0"), so it falls through
        try {
          let n = @string.parse_double(prop)
          if n.to_string() == prop {
            let idx = n.to_int()
            if idx.to_double() == n && idx >= 0 {
              let num = to_number(value)
              (self.stdlib_hooks.typedarray_set_index)(data, idx, num)
            }
            // Canonical numeric index: don't fall through to regular property set
            return value
          }
        } catch {
          _ => () // Not a numeric string, fall through to normal property set
        }
      }
      // Check for accessor descriptor (setter)
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, obj, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if !desc.writable {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None => {
          // Walk prototype chain for inherited setters
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                match proto_data.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.setter {
                      Some(setter) => {
                        let _ = self.call_value(setter, obj, [value], loc)
                        return value
                      }
                      None =>
                        if desc.getter is Some(_) {
                          if strict {
                            raise @errors.TypeError(
                              message="Cannot set property \{prop} which has only a getter",
                            )
                          }
                          return value
                        } else if !desc.writable {
                          // Inherited non-writable data property blocks assignment
                          if strict {
                            raise @errors.TypeError(
                              message="Cannot assign to read only property '\{prop}'",
                            )
                          }
                          return value
                        }
                    }
                  None => ()
                }
                current = proto_data.prototype
              }
              _ => break
            }
          }
        }
      }
      // Check extensible for new properties
      if !data.properties.contains(prop) && !data.extensible {
        if strict {
          raise @errors.TypeError(
            message="Cannot add property \{prop}, object is not extensible",
          )
        }
        return value
      }
      data.properties[prop] = value
      value
    }
    Array(data) => {
      if prop == "length" {
        let num = to_number(value)
        // Validate: length must be a non-negative integer <= 2^32-1
        if num.is_nan() ||
          num < 0.0 ||
          num > 4294967295.0 ||
          num != @math.floor(num) {
          raise @errors.RangeError(message="Invalid array length")
        }
        let n64 = num.to_int64()
        // Truncate array if new length is shorter
        while data.elements.length().to_int64() > n64 {
          let _ = data.elements.pop()
        }
        let cur_elem_len = data.elements.length().to_int64()
        // Expand elements if the gap is small enough to materialise
        if n64 > cur_elem_len && n64 - cur_elem_len <= 100000L {
          let target = n64.to_int()
          while data.elements.length() < target {
            data.elements.push(Undefined)
          }
        }
        // Keep the length override in sync: set it when the logical length
        // exceeds elements.length(), clear it when they match.
        if n64 > data.elements.length().to_int64() {
          set_array_length_override(data, n64)
        } else {
          clear_array_length_override(data)
        }
      } else {
        // try numeric index
        let mut handled = false
        try {
          let i = @string.parse_int(prop)
          if i >= 0 {
            while data.elements.length() <= i {
              data.elements.push(Undefined)
            }
            data.elements[i] = value
            handled = true
          }
        } catch {
          _ => ()
        }
        if !handled {
          // Store named properties in side table
          set_array_named_prop(data, prop, value)
        }
      }
      value
    }
    Promise(data) => {
      match data.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, obj, [value], loc)
              return value
            }
            None =>
              if desc.getter is Some(_) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot set property \{prop} which has only a getter",
                  )
                }
                return value
              } else if !desc.writable {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot assign to read only property '\{prop}'",
                  )
                }
                return value
              }
          }
        None => ()
      }
      data.properties[prop] = value
      value
    }
    Null =>
      raise @errors.TypeError(
        message="Cannot set properties of null (setting '\{prop}')",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot set properties of undefined (setting '\{prop}')",
      )
    _ =>
      // In non-strict mode, setting a property on a primitive is silently ignored
      // (the temporary wrapper object is discarded). In strict mode, throw TypeError.
      if strict {
        raise @errors.TypeError(
          message="Cannot set property '\{prop}' of \{type_of(obj)}",
        )
      } else {
        value
      }
  }
}

///|
fn Interpreter::set_computed_property(
  self : Interpreter,
  obj : Value,
  key : Value,
  value : Value,
  loc : @token.Loc,
  strict? : Bool = false,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) => {
      let trap = get_proxy_trap(proxy_data, "set", self)
      match trap {
        Some(trap_fn) => {
          let target = get_proxy_target(proxy_data)
          let handler = get_proxy_handler(proxy_data)
          let prop_key = match key {
            Symbol(_) => key
            _ => String_(to_js_string(key))
          }
          let result = self.call_value(
            trap_fn,
            handler,
            [target, prop_key, value, obj],
            loc,
          )
          if !is_truthy(result) {
            if strict {
              raise @errors.TypeError(
                message="'set' on proxy: trap returned falsish",
              )
            }
          }
          return value
        }
        None => {
          let target = get_proxy_target(proxy_data)
          return self.set_computed_property(target, key, value, loc, strict~)
        }
      }
    }
    Object(data) =>
      match key {
        Symbol(sym) => {
          // Check symbol property accessor descriptor (setter)
          match data.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, obj, [value], loc)
                  return value
                }
                None =>
                  if desc.getter is Some(_) {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot set property which has only a getter",
                      )
                    }
                    return value
                  } else if !desc.writable {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property",
                      )
                    }
                    return value
                  }
              }
            None => {
              // Walk prototype chain for inherited symbol setters
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    match proto_data.symbol_descriptors.get(sym.id) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(setter, obj, [value], loc)
                            return value
                          }
                          None =>
                            if desc.getter is Some(_) {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot set property which has only a getter",
                                )
                              }
                              return value
                            } else if !desc.writable {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property",
                                )
                              }
                              return value
                            }
                        }
                      None => ()
                    }
                    current = proto_data.prototype
                  }
                  _ => break
                }
              }
            }
          }
          if !data.symbol_properties.contains(sym.id) && !data.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property, object is not extensible",
              )
            }
            return value
          }
          data.symbol_properties[sym.id] = value
          value
        }
        _ => {
          // TypedArray indexed write: intercept numeric keys
          if is_typedarray_class(data.class_name) {
            match key {
              Number(n) => {
                let idx = n.to_int()
                if idx.to_double() == n && idx >= 0 {
                  let num = to_number(value)
                  (self.stdlib_hooks.typedarray_set_index)(data, idx, num)
                }
                // Numeric key always intercepted for TypedArrays
                return value
              }
              String_(s) =>
                // Canonical numeric index string check per spec
                // Note: "-0" is NOT canonical (ToString(ToNumber("-0")) === "0"), so it falls through
                try {
                  let n = @string.parse_double(s)
                  if n.to_string() == s {
                    let idx = n.to_int()
                    if idx.to_double() == n && idx >= 0 {
                      let num = to_number(value)
                      (self.stdlib_hooks.typedarray_set_index)(data, idx, num)
                    }
                    return value
                  }
                } catch {
                  _ => () // Not numeric, fall through
                }
              _ => ()
            }
          }
          let prop = to_js_string(key)
          // Check for accessor descriptor (setter) on string key
          match data.descriptors.get(prop) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, obj, [value], loc)
                  return value
                }
                None =>
                  if desc.getter is Some(_) {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot set property \{prop} which has only a getter",
                      )
                    }
                    return value
                  } else if !desc.writable {
                    if strict {
                      raise @errors.TypeError(
                        message="Cannot assign to read only property '\{prop}'",
                      )
                    }
                    return value
                  }
              }
            None => {
              // Walk prototype chain for inherited setters
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    match proto_data.descriptors.get(prop) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(setter, obj, [value], loc)
                            return value
                          }
                          None =>
                            if desc.getter is Some(_) {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot set property \{prop} which has only a getter",
                                )
                              }
                              return value
                            } else if !desc.writable {
                              if strict {
                                raise @errors.TypeError(
                                  message="Cannot assign to read only property '\{prop}'",
                                )
                              }
                              return value
                            }
                        }
                      None => ()
                    }
                    current = proto_data.prototype
                  }
                  _ => break
                }
              }
            }
          }
          if !data.properties.contains(prop) && !data.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property \{prop}, object is not extensible",
              )
            }
            return value
          }
          data.properties[prop] = value
          value
        }
      }
    Map(data) =>
      // Write to expando properties bag (used for instance fields from subclasses)
      match key {
        Symbol(sym) => {
          data.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.properties[to_js_string(key)] = value
          value
        }
      }
    Set(data) =>
      // Write to expando properties bag (used for instance fields from subclasses)
      match key {
        Symbol(sym) => {
          data.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.properties[to_js_string(key)] = value
          value
        }
      }
    Array(data) =>
      match key {
        Symbol(sym) => {
          set_array_symbol_prop(data, sym.id, value)
          value
        }
        Number(n) => {
          let i = n.to_int()
          if i >= 0 {
            while data.elements.length() <= i {
              data.elements.push(Undefined)
            }
            data.elements[i] = value
          }
          value
        }
        _ => {
          let prop = to_js_string(key)
          if prop == "length" {
            let n = to_number(value).to_int()
            while data.elements.length() > n {
              let _ = data.elements.pop()
            }
          } else {
            // Canonical numeric index string check: parseDouble(s).toString() === s
            let mut handled = false
            try {
              let n = @string.parse_double(prop)
              if n.to_string() == prop {
                let idx = n.to_int()
                if idx.to_double() == n && idx >= 0 {
                  while data.elements.length() <= idx {
                    data.elements.push(Undefined)
                  }
                  data.elements[idx] = value
                  handled = true
                }
              }
            } catch {
              _ => ()
            }
            if !handled {
              // Store named properties in side table
              set_array_named_prop(data, prop, value)
            }
          }
          value
        }
      }
    Promise(data) =>
      match key {
        Symbol(sym) => {
          data.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.properties[to_js_string(key)] = value
          value
        }
      }
    Null => {
      let key_str = match key {
        Symbol(sym) => "Symbol(\{sym.description})"
        String_(s) => s
        Number(n) => n.to_string()
        Bool(b) => b.to_string()
        _ => ""
      }
      raise @errors.TypeError(
        message="Cannot set properties of null (setting '\{key_str}')",
      )
    }
    Undefined => {
      let key_str = match key {
        Symbol(sym) => "Symbol(\{sym.description})"
        String_(s) => s
        Number(n) => n.to_string()
        Bool(b) => b.to_string()
        _ => ""
      }
      raise @errors.TypeError(
        message="Cannot set properties of undefined (setting '\{key_str}')",
      )
    }
    _ =>
      if strict {
        raise @errors.TypeError(
          message="Cannot set property of \{type_of(obj)}",
        )
      } else {
        value
      }
  }
}

///|
fn Interpreter::eval_member(
  self : Interpreter,
  ctx : ExecContext,
  obj_expr : @ast.Expr,
  prop : String,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Special case: console.log
  match obj_expr {
    Ident("console", _) =>
      if prop == "log" {
        let output = self.host.output
        make_native_func("log", fn(args) {
          let parts : Array[String] = args.map(fn(a) { a.to_string() })
          output.push(parts.join(" "))
          Undefined
        })
      } else {
        raise @errors.TypeError(message="console.\{prop} is not supported")
      }
    _ => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      self.get_property(obj, prop, loc)
    }
  }
}

///|
pub fn get_bound_func_name(target : Value) -> String {
  match target {
    Object(td) => {
      // First check properties["name"] (set by Object.defineProperty or bind)
      let prop_name = match td.properties.get("name") {
        Some(String_(s)) => s
        _ => ""
      }
      if prop_name != "" {
        return "bound " + prop_name
      }
      match td.callable {
        Some(UserFunc(fd)) => "bound " + fd.name.unwrap_or("")
        Some(UserFuncExt(fd)) => "bound " + fd.name.unwrap_or("")
        Some(NativeCallable(n, _)) => "bound " + n
        Some(NonConstructableCallable(n, _)) => "bound " + n
        Some(BoundFunc(inner, _, _)) => "bound " + get_bound_func_name(inner)
        Some(ArrowFunc(fd)) => "bound " + fd.name.unwrap_or("")
        Some(ArrowFuncExt(fd)) => "bound " + fd.name.unwrap_or("")
        Some(ClassConstructor({ name: n, .. })) => "bound " + n
        Some(MethodCallable(n, _)) => "bound " + n
        Some(InterpreterCallable(n, _)) => "bound " + n
        Some(_) => "bound "
        None => "bound "
      }
    }
    _ => "bound "
  }
}

///|
pub fn get_func_length(callable : Callable) -> Int {
  match callable {
    UserFunc(func_data) => func_data.params.length()
    UserFuncExt(func_data) => {
      let mut len = 0
      for p in func_data.params {
        if p.default_val is Some(_) {
          break
        }
        len += 1
      }
      len
    }
    ArrowFunc(func_data) => func_data.params.length()
    ArrowFuncExt(func_data) => {
      let mut len = 0
      for p in func_data.params {
        if p.default_val is Some(_) {
          break
        }
        len += 1
      }
      len
    }
    BoundFunc(target, _, bound_args) =>
      match target {
        Object(td) =>
          match td.callable {
            Some(inner) => {
              let target_len = get_func_length(inner)
              let diff = target_len - bound_args.length()
              if diff < 0 {
                0
              } else {
                diff
              }
            }
            None => 0
          }
        _ => 0
      }
    NativeCallable(_, _) => 0
    NonConstructableCallable(_, _) => 0
    FuncCallMethod(_) => 1
    FuncApplyMethod(_) => 2
    MethodCallable(_, _) => 0
    InterpreterCallable(_, _) => 0
    ConstructorOnlyCallable(_, _) => 0
    ClassConstructor({ ctor_fn, .. }) =>
      match ctor_fn {
        Some((params, _, _)) => params.length()
        None => 0
      }
  }
}

///|
/// Sort property keys per OrdinaryOwnPropertyKeys spec order:
/// 1. Integer indices in ascending numeric order
/// 2. Other string keys in insertion order
pub fn sort_property_keys(props : Map[String, Value]) -> Array[String] {
  let int_keys : Array[String] = []
  let str_keys : Array[String] = []
  props.each(fn(k, _v) {
    // Skip internal slots (e.g., [[BooleanData]], [[NumberData]], [[StringData]])
    if k.has_prefix("[[") {
      return
    }
    let idx = @string.parse_int(k) catch { _ => -1 }
    if idx >= 0 && idx.to_string() == k {
      int_keys.push(k)
    } else {
      str_keys.push(k)
    }
  })
  // Sort integer keys by numeric value
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
/// Validate non-configurable property constraints per ES spec [[DefineOwnProperty]].
/// Throws TypeError if the proposed descriptor change violates invariants.
/// This is the sole authority for descriptor mutation constraints in the runtime.
pub fn validate_non_configurable(
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
  if !existing_is_accessor && is_accessor {
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
          Some(eg) => strict_equal(g, eg)
          None => g is Undefined
        }
      None => true
    }
    let setter_ok = match new_setter {
      Some(s) =>
        match existing.setter {
          Some(es) => strict_equal(s, es)
          None => s is Undefined
        }
      None => true
    }
    if !(enumerable_ok && configurable_ok && getter_ok && setter_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Non-configurable data: validate writable/value
  if !existing_is_accessor && !is_accessor {
    let writable_ok = match new_writable {
      Some(w) => if !existing.writable && w { false } else { true }
      None => true
    }
    let value_ok = if !existing.writable && has_value {
      match get_new_value() {
        Some(v) => strict_equal(v, get_old_value())
        None => true
      }
    } else {
      true
    }
    if !(writable_ok && enumerable_ok && configurable_ok && value_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Generic descriptor (no accessor/data fields)
  if !is_accessor && !is_data {
    if !(enumerable_ok && configurable_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
}

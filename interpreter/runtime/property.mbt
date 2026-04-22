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
        make_native_func(name="toString", fn(_args) {
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
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.bag.properties.get(prop) {
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
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.bag.properties.get(prop) {
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
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => self.call_value(getter, obj, [], loc)
            None =>
              match data.bag.properties.get(prop) {
                Some(v) => v
                None => (self.stdlib_hooks.get_promise_method)(data, prop)
              }
          }
        None =>
          match data.bag.properties.get(prop) {
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
  match data.bag.descriptors.get(prop) {
    Some(desc) =>
      match desc.getter {
        Some(getter) => return self.call_value(getter, obj, [], loc)
        None => ()
      }
    None => ()
  }
  match data.bag.properties.get(prop) {
    Some(v) => v
    None => {
      // Walk prototype chain
      let mut current = data.prototype
      let mut func_proto_checked = false
      while true {
        match current {
          Object(proto_data) => {
            // Check for accessor descriptor (getter) on prototype property
            match proto_data.bag.descriptors.get(prop) {
              Some(desc) =>
                match desc.getter {
                  Some(getter) => return self.call_value(getter, obj, [], loc)
                  None => ()
                }
              None => ()
            }
            match proto_data.bag.properties.get(prop) {
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
                        match ctor_data.bag.properties.get("prototype") {
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
                    match ctor_data.bag.properties.get("prototype") {
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
                    match ctor_data.bag.properties.get("prototype") {
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
              bag: PropertyBag::new(),
              prototype: Null,
              callable: Some(FuncCallMethod(obj)),
              class_name: "Function",
              extensible: true,
            })
          } else if prop == "apply" {
            return Object({
              bag: PropertyBag::new(),
              prototype: Null,
              callable: Some(FuncApplyMethod(obj)),
              class_name: "Function",
              extensible: true,
            })
          } else if prop == "bind" {
            let target = obj
            let target_length = get_func_length(callable)
            return make_native_func(name="bind", fn(args) {
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
                bag: {
                  properties: bprops,
                  symbol_properties: {},
                  descriptors: { "name": nf_desc, "length": nf_desc },
                  symbol_descriptors: {},
                },
                prototype: get_func_proto(),
                callable: Some(BoundFunc(target, bind_this, bound_args)),
                class_name: "Function",
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
              NonConstructableInterpreterCallable(n, _) => n
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
              NonConstructableInterpreterCallable(n, _) =>
                "function " + n + "() { [native code] }"
              ConstructorOnlyCallable(n, _) =>
                "function " + n + "() { [native code] }"
              ClassConstructor({ name: n, .. }) =>
                "class " + n + " { [native code] }"
            }
            return make_native_func(name="toString", fn(_args) {
              String_(func_str)
            })
          } else if prop == "prototype" {
            // Only constructable functions have a prototype property
            // Non-constructable (arrow functions, bound functions, etc.) return undefined
            let is_constructable = match callable {
              UserFunc(fd) => !fd.is_method
              UserFuncExt(fd) => !fd.is_method
              NativeCallable(_, _)
              | ConstructorOnlyCallable(_, _)
              | ClassConstructor(_) => true
              ArrowFunc(_)
              | ArrowFuncExt(_)
              | BoundFunc(_, _, _)
              | NonConstructableCallable(_, _)
              | NonConstructableInterpreterCallable(_, _)
              | FuncCallMethod(_)
              | FuncApplyMethod(_)
              | MethodCallable(_, _)
              | InterpreterCallable(_, _) => false
            }
            if !is_constructable {
              return Undefined
            }
            // For constructable functions, check if prototype exists
            match data.bag.properties.get("prototype") {
              Some(p) => return p
              None => {
                // Create and memoize default prototype
                let proto : Value = Object({
                  bag: PropertyBag::new(),
                  prototype: get_obj_proto(),
                  callable: None,
                  class_name: "Object",
                  extensible: true,
                })
                data.bag.properties["prototype"] = proto
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
          return make_method_func(name="hasOwnProperty", length=1, fn(
            this_val,
            args,
          ) {
            let key_val = if args.length() > 0 { args[0] } else { Undefined }
            match this_val {
              Object(d) =>
                match key_val {
                  Symbol(sym) => Bool(d.bag.symbol_properties.contains(sym.id))
                  _ => Bool(d.bag.properties.contains(key_val.to_string()))
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
          return make_native_func(name="toString", fn(_args) {
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
      match ctor_data.bag.properties.get("prototype") {
        Some(Object(proto_data)) => {
          // Walk up prototype chain and honor accessor getters with `receiver`.
          let mut current : Value = Object(proto_data)
          while true {
            match current {
              Object(pdata) => {
                match pdata.bag.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.getter {
                      Some(getter) =>
                        return interp.call_value(getter, receiver, [], loc)
                      None =>
                        match pdata.bag.properties.get(prop) {
                          Some(v) => return v
                          None => ()
                        }
                    }
                  None =>
                    match pdata.bag.properties.get(prop) {
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
          match data.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => ()
              }
            None => ()
          }
          // Look up symbol property
          match data.bag.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => {
              // Walk prototype chain for symbol properties
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    // Check for accessor on prototype
                    match proto_data.bag.symbol_descriptors.get(sym.id) {
                      Some(desc) =>
                        match desc.getter {
                          Some(getter) =>
                            return self.call_value(getter, obj, [], loc)
                          None => ()
                        }
                      None => ()
                    }
                    match proto_data.bag.symbol_properties.get(sym.id) {
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
                  match data.bag.properties.get("[[StringData]]") {
                    Some(String_(_)) =>
                      return make_method_func(
                        name="[Symbol.iterator]",
                        length=0,
                        fn(this_val, _args) raise {
                          let str = match this_val {
                            String_(sv) => sv
                            Object(d) =>
                              if d.class_name == "String" {
                                match d.bag.properties.get("[[StringData]]") {
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
                        },
                      )
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
            return make_method_func(name="[Symbol.iterator]", length=0, fn(
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
              match ctor_data.bag.properties.get("prototype") {
                Some(Object(proto_data)) => {
                  // Check symbol descriptors for getters
                  match proto_data.bag.symbol_descriptors.get(sym.id) {
                    Some(desc) =>
                      match desc.getter {
                        Some(getter) =>
                          return self.call_value(getter, obj, [], loc)
                        None => ()
                      }
                    None => ()
                  }
                  // Check symbol properties
                  match proto_data.bag.symbol_properties.get(sym.id) {
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
            return make_method_func(name="[Symbol.iterator]", length=0, fn(
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
          match map_data.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => ()
              }
            None => ()
          }
          match map_data.bag.symbol_properties.get(sym.id) {
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
          match set_data.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => ()
              }
            None => ()
          }
          match set_data.bag.symbol_properties.get(sym.id) {
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
          match data.bag.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => return Undefined
          }
        Symbol(_) => {
          // Delegate to Symbol.prototype for symbol-keyed property access
          let proto = self.global.get("[[SymbolPrototype]]") catch { _ => Null }
          match proto {
            Object(proto_data) => {
              match proto_data.bag.symbol_descriptors.get(sym.id) {
                Some(desc) =>
                  match desc.getter {
                    Some(getter) => return self.call_value(getter, obj, [], loc)
                    None => ()
                  }
                None => ()
              }
              match proto_data.bag.symbol_properties.get(sym.id) {
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
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.getter {
            Some(getter) => return self.call_value(getter, obj, [], loc)
            None => ()
          }
        None => ()
      }
      match data.bag.properties.get(prop) {
        Some(v) => v
        None => {
          // Walk prototype chain
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                // Check for accessor descriptor on prototype
                match proto_data.bag.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.getter {
                      Some(getter) =>
                        return self.call_value(getter, obj, [], loc)
                      None => ()
                    }
                  None => ()
                }
                match proto_data.bag.properties.get(prop) {
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
                            match ctor_data.bag.properties.get("prototype") {
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
                        match ctor_data.bag.properties.get("prototype") {
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
                        match ctor_data.bag.properties.get("prototype") {
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
                  bag: PropertyBag::new(),
                  prototype: Null,
                  callable: Some(FuncCallMethod(obj)),
                  class_name: "Function",
                  extensible: true,
                })
              } else if prop == "apply" {
                return Object({
                  bag: PropertyBag::new(),
                  prototype: Null,
                  callable: Some(FuncApplyMethod(obj)),
                  class_name: "Function",
                  extensible: true,
                })
              } else if prop == "bind" {
                let target = obj
                let target_length = get_func_length(callable)
                return make_native_func(name="bind", fn(args) {
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
                    bag: {
                      properties: bprops,
                      symbol_properties: {},
                      descriptors: { "name": nf_desc, "length": nf_desc },
                      symbol_descriptors: {},
                    },
                    prototype: get_func_proto(),
                    callable: Some(BoundFunc(target, bind_this, bound_args)),
                    class_name: "Function",
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
                  NonConstructableInterpreterCallable(n, _) => n
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
                  NonConstructableInterpreterCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ConstructorOnlyCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ClassConstructor({ name: n, .. }) =>
                    "class " + n + " { [native code] }"
                }
                return make_native_func(name="toString", fn(_args) {
                  String_(func_str)
                })
              } else if prop == "prototype" {
                // Only constructable functions have a prototype property
                // Non-constructable (arrow functions, bound functions, etc.) return undefined
                let is_constructable = match callable {
                  UserFunc(fd) => !fd.is_method
                  UserFuncExt(fd) => !fd.is_method
                  NativeCallable(_, _)
                  | ConstructorOnlyCallable(_, _)
                  | ClassConstructor(_) => true
                  ArrowFunc(_)
                  | ArrowFuncExt(_)
                  | BoundFunc(_, _, _)
                  | NonConstructableCallable(_, _)
                  | NonConstructableInterpreterCallable(_, _)
                  | FuncCallMethod(_)
                  | FuncApplyMethod(_)
                  | MethodCallable(_, _)
                  | InterpreterCallable(_, _) => false
                }
                if !is_constructable {
                  return Undefined
                }
                // For constructable functions, check if prototype exists
                match data.bag.properties.get("prototype") {
                  Some(p) => return p
                  None => {
                    // Create and memoize default prototype
                    let proto : Value = Object({
                      bag: PropertyBag::new(),
                      prototype: get_obj_proto(),
                      callable: None,
                      class_name: "Object",
                      extensible: true,
                    })
                    data.bag.properties["prototype"] = proto
                    return proto
                  }
                }
              }
            None => ()
          }
          // Built-in Object methods (only for objects that inherit from Object.prototype)
          if !(data.prototype is Null && data.callable is None) {
            if prop == "hasOwnProperty" {
              return make_method_func(name="hasOwnProperty", length=1, fn(
                this_val,
                args,
              ) {
                let key_val = if args.length() > 0 {
                  args[0]
                } else {
                  Undefined
                }
                match this_val {
                  Object(d) =>
                    match key_val {
                      Symbol(sym) =>
                        Bool(d.bag.symbol_properties.contains(sym.id))
                      _ => Bool(d.bag.properties.contains(key_val.to_string()))
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
              return make_native_func(name="toString", fn(_args) {
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
          match data.bag.symbol_properties.get(sym.id) {
            Some(v) => v
            None => Undefined
          }
        _ => {
          let prop = to_js_string(key)
          match data.bag.properties.get(prop) {
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
/// Stage B.1 [[Set]] dispatcher.
///
/// `receiver` threads through the prototype chain and proxy fallbacks per
/// ES §10.1.9 (OrdinarySet) and §10.5.9 (ProxyExoticObject.[[Set]]).
///
/// - Inherited setters are invoked with `receiver` as `this`.
/// - Trap-less Proxy forwards to `target.[[Set]](P, V, Receiver)`.
/// - When no own/inherited blocker exists and `receiver !== obj`, the write
///   lands on `receiver` via `define_value_on_receiver` (approximating
///   `CreateDataProperty(Receiver, P, V)` — a direct `[[DefineOwnProperty]]`
///   that bypasses `[[Set]]`, preventing the recursion loop that a naive
///   self-call would produce for nested trap-less proxies).
pub fn Interpreter::set_property(
  self : Interpreter,
  obj : Value,
  prop : String,
  value : Value,
  loc : @token.Loc,
  strict? : Bool = false,
  receiver? : Value = obj,
) -> Value raise Error {
  match obj {
    Proxy(proxy_data) =>
      proxy_set(self, proxy_data, prop, value, receiver, strict)
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
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, receiver, [value], loc)
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
          // Walk prototype chain for inherited setters. Per ES §10.1.9.2:
          // - Accessor getter-only / non-writable data → blocked.
          // - Inherited writable data (explicit descriptor OR implicit via
          //   bag.properties): TERMINATES the walk (step 2 data-descriptor
          //   branch lands on Receiver without consulting higher protos).
          //   Missing this short-circuit lets a higher Proxy prototype's
          //   set trap fire with unexpected side effects.
          // - Proxy on chain: delegate to its [[Set]] (§10.1.9.2 step 1.b).
          let mut current = data.prototype
          while true {
            match current {
              Object(proto_data) => {
                let mut stop_at_writable_data = false
                match proto_data.bag.descriptors.get(prop) {
                  Some(desc) =>
                    match desc.setter {
                      Some(setter) => {
                        let _ = self.call_value(setter, receiver, [value], loc)
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
                        } else {
                          // Writable data descriptor → stop walking.
                          stop_at_writable_data = true
                        }
                    }
                  None =>
                    // No explicit descriptor — plain assignments go to
                    // bag.properties and carry an implicit writable data
                    // descriptor per spec.
                    if proto_data.bag.properties.contains(prop) {
                      stop_at_writable_data = true
                    }
                }
                if stop_at_writable_data {
                  break
                }
                current = proto_data.prototype
              }
              Proxy(_) =>
                return self.set_property(
                  current,
                  prop,
                  value,
                  loc,
                  strict~,
                  receiver~,
                )
              _ => break
            }
          }
        }
      }
      // No own / inherited blocker — land the write on `receiver` per
      // ES §10.1.9.2 step 3. When `receiver !== obj` this goes through
      // `define_value_on_receiver` (approximates `CreateDataProperty`).
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
      // Common path: receiver === obj, write locally (byte-identical to pre-B.1).
      if !data.bag.properties.contains(prop) && !data.extensible {
        if strict {
          raise @errors.TypeError(
            message="Cannot add property \{prop}, object is not extensible",
          )
        }
        return value
      }
      data.bag.properties[prop] = value
      value
    }
    Array(data) => {
      // Arrays use ordinary [[Set]] (only [[DefineOwnProperty]] is exotic per
      // §10.4.2). When `receiver !== obj` (Array), land on the receiver via
      // the helper — matches `Reflect.set(arr, "0", 1, otherObj)` semantics.
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
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
      match data.bag.descriptors.get(prop) {
        Some(desc) =>
          match desc.setter {
            Some(setter) => {
              let _ = self.call_value(setter, receiver, [value], loc)
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
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(
          receiver,
          String_(prop),
          value,
          loc,
          strict,
        )
      }
      data.bag.properties[prop] = value
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
/// Helper predicate for §10.1.9.2 step 3.e: an existing receiver-side
/// descriptor blocks the landing write if it is an accessor descriptor
/// (getter or setter present) or a non-writable data descriptor. Writable
/// data descriptors do NOT block (the write lands as { [[Value]]: V }).
fn existing_receiver_desc_blocks(desc : PropDescriptor) -> Bool {
  desc.getter is Some(_) ||
  desc.setter is Some(_) ||
  (desc.getter is None && desc.setter is None && !desc.writable)
}

///|
/// Approximates ES `CreateDataProperty(Receiver, P, V)` / `Receiver.[[Define\
/// OwnProperty]]` for the Stage B.1 landing rule. This is NOT `[[Set]]` — it
/// must not invoke setters on `receiver`'s prototype chain, otherwise a
/// trap-less proxy chain would infinite-loop (per Codex's design review).
///
/// Implements §10.1.9.2 step 3.e as of the receiver-blocker fix: if receiver
/// has an existing own descriptor at `key`, accessor or non-writable data
/// blocks the landing (sloppy returns `value`, strict raises TypeError).
///
/// Stage B.2 will replace this with a full `[[DefineOwnProperty]]` dispatcher
/// that honors Proxy `defineProperty` traps.
fn Interpreter::define_value_on_receiver(
  self : Interpreter,
  receiver : Value,
  key : Value,
  value : Value,
  loc : @token.Loc,
  strict : Bool,
) -> Value raise Error {
  match receiver {
    // Proxy receiver without defineProperty dispatcher: unwrap to target.
    // For trap-less proxies this is spec-equivalent to DefineOwnProperty
    // forwarding. Trap-aware handling lands with Stage B.2.
    Proxy(pdata) =>
      self.define_value_on_receiver(
        get_proxy_target(pdata),
        key,
        value,
        loc,
        strict,
      )
    Object(rdata) =>
      match key {
        Symbol(sym) => {
          // §10.1.9.2 step 3.e: existing own descriptor blocker check.
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          if !rdata.bag.symbol_properties.contains(sym.id) && !rdata.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property, object is not extensible",
              )
            }
            return value
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key)
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          if !rdata.bag.properties.contains(prop) && !rdata.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property \{prop}, object is not extensible",
              )
            }
            return value
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    Promise(rdata) =>
      match key {
        Symbol(sym) => {
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key)
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    // Map / Set receivers carry an expando bag for instance fields from
    // subclasses (e.g. `class D extends Map { constructor() { super(); this.x = 1 } }`)
    // — the landing helper must write there rather than hitting the primitive
    // fall-through. Descriptor-blocker check mirrors the Object arm.
    Map(rdata) =>
      match key {
        Symbol(sym) => {
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key)
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    Set(rdata) =>
      match key {
        Symbol(sym) => {
          match rdata.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          let prop = to_js_string(key)
          match rdata.bag.descriptors.get(prop) {
            Some(desc) =>
              if existing_receiver_desc_blocks(desc) {
                if strict {
                  raise @errors.TypeError(
                    message="Cannot redefine non-writable or accessor property '\{prop}' on receiver",
                  )
                }
                return value
              }
            None => ()
          }
          rdata.bag.properties[prop] = value
          value
        }
      }
    // B.2: Array receiver landing diverges from the spec. `CreateDataProperty`
    // (the ES §10.1.9.2 step 3 landing) goes through `[[DefineOwnProperty]]`,
    // which for Arrays is exotic (§10.4.2.4 ArraySetLength rejects changes to
    // non-configurable/non-writable `length`; indexed `[[DefineOwnProperty]]`
    // interacts with length differently from `[[Set]]`). We don't yet have a
    // `[[DefineOwnProperty]]` dispatcher, so this branch delegates back through
    // set_property / set_computed_property with receiver===obj — that re-fires
    // Array's `[[Set]]` exotic path, which is NOT the same operation. Known
    // observable divergence: `Reflect.set({}, "length", 10, arr)` should return
    // false (attempts a full-attributes redefine of arr.length), but this
    // delegation truncates the array instead. The full
    // [[DefineOwnProperty]]-on-receiver protocol lands with Stage B.2.
    Array(_) =>
      match key {
        Symbol(_) =>
          self.set_computed_property(
            receiver,
            key,
            value,
            loc,
            strict~,
            receiver~,
          )
        _ =>
          self.set_property(
            receiver,
            to_js_string(key),
            value,
            loc,
            strict~,
            receiver~,
          )
      }
    // Null/Undefined/primitive receiver: per spec returns false. In strict
    // mode our dispatcher surface raises TypeError; in sloppy mode return
    // `value` to match existing set_property primitive handling.
    Null =>
      if strict {
        raise @errors.TypeError(message="Cannot set property on null receiver")
      } else {
        value
      }
    Undefined =>
      if strict {
        raise @errors.TypeError(
          message="Cannot set property on undefined receiver",
        )
      } else {
        value
      }
    _ =>
      if strict {
        raise @errors.TypeError(
          message="Cannot set property on primitive receiver",
        )
      } else {
        value
      }
  }
}

///|
pub fn Interpreter::set_computed_property(
  self : Interpreter,
  obj : Value,
  key : Value,
  value : Value,
  loc : @token.Loc,
  strict? : Bool = false,
  receiver? : Value = obj,
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
            [target, prop_key, value, receiver],
            loc,
          )
          if !is_truthy(result) {
            if strict {
              raise @errors.TypeError(
                message="'set' on proxy: trap returned falsish",
              )
            }
            return value
          }
          // ES §10.5.9 step 11-12 invariants. Same checks proxy_set runs for
          // the string-key path; must run here so `p[k] = v` and the proto-
          // chain delegation (Proxy(_) arm of the walk) match spec.
          check_proxy_set_trap_invariants(target, prop_key, value)
          return value
        }
        None => {
          // Trap-less fallback: target.[[Set]](P, V, Receiver) — thread
          // receiver through per ES §10.5.9 step 5.
          let target = get_proxy_target(proxy_data)
          return self.set_computed_property(
            target,
            key,
            value,
            loc,
            strict~,
            receiver~,
          )
        }
      }
    }
    Object(data) =>
      match key {
        Symbol(sym) => {
          // Check symbol property accessor descriptor (setter)
          match data.bag.symbol_descriptors.get(sym.id) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, receiver, [value], loc)
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
              // Walk prototype chain for inherited symbol setters. Writable
              // data on a proto (explicit or implicit via symbol_properties)
              // terminates the walk per §10.1.9.2; see string-key branch for
              // full rationale.
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    let mut stop_at_writable_data = false
                    match proto_data.bag.symbol_descriptors.get(sym.id) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(
                              setter,
                              receiver,
                              [value],
                              loc,
                            )
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
                            } else {
                              stop_at_writable_data = true
                            }
                        }
                      None =>
                        if proto_data.bag.symbol_properties.contains(sym.id) {
                          stop_at_writable_data = true
                        }
                    }
                    if stop_at_writable_data {
                      break
                    }
                    current = proto_data.prototype
                  }
                  Proxy(_) =>
                    return self.set_computed_property(
                      current,
                      key,
                      value,
                      loc,
                      strict~,
                      receiver~,
                    )
                  _ => break
                }
              }
            }
          }
          // Landing rule: if receiver differs, write lands on receiver.
          if !strict_equal(obj, receiver) {
            return self.define_value_on_receiver(
              receiver, key, value, loc, strict,
            )
          }
          if !data.bag.symbol_properties.contains(sym.id) && !data.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property, object is not extensible",
              )
            }
            return value
          }
          data.bag.symbol_properties[sym.id] = value
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
          match data.bag.descriptors.get(prop) {
            Some(desc) =>
              match desc.setter {
                Some(setter) => {
                  let _ = self.call_value(setter, receiver, [value], loc)
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
              // Walk prototype chain for inherited setters. Writable data on
              // a proto (explicit or implicit via bag.properties) terminates
              // the walk per §10.1.9.2; see set_property for full rationale.
              let mut current = data.prototype
              while true {
                match current {
                  Object(proto_data) => {
                    let mut stop_at_writable_data = false
                    match proto_data.bag.descriptors.get(prop) {
                      Some(desc) =>
                        match desc.setter {
                          Some(setter) => {
                            let _ = self.call_value(
                              setter,
                              receiver,
                              [value],
                              loc,
                            )
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
                            } else {
                              stop_at_writable_data = true
                            }
                        }
                      None =>
                        if proto_data.bag.properties.contains(prop) {
                          stop_at_writable_data = true
                        }
                    }
                    if stop_at_writable_data {
                      break
                    }
                    current = proto_data.prototype
                  }
                  Proxy(_) =>
                    return self.set_computed_property(
                      current,
                      key,
                      value,
                      loc,
                      strict~,
                      receiver~,
                    )
                  _ => break
                }
              }
            }
          }
          // Landing rule: if receiver differs, write lands on receiver.
          if !strict_equal(obj, receiver) {
            return self.define_value_on_receiver(
              receiver,
              String_(prop),
              value,
              loc,
              strict,
            )
          }
          if !data.bag.properties.contains(prop) && !data.extensible {
            if strict {
              raise @errors.TypeError(
                message="Cannot add property \{prop}, object is not extensible",
              )
            }
            return value
          }
          data.bag.properties[prop] = value
          value
        }
      }
    Map(data) => {
      // PRE-EXISTING LIMITATION (not a regression from B.1): Map/Set/Promise/
      // Array branches do not walk their instance's prototype chain for
      // inherited setters because MapData/SetData/PromiseData/ArrayData carry
      // no `prototype` field (only ObjectData does). Setters defined on
      // Map.prototype / Set.prototype / etc. are therefore invisible here and
      // also when receiver===obj below. Fixing this requires either adding
      // `prototype` to the four structs or threading the builtin prototypes
      // through the dispatcher — both out of B.1 scope.
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(receiver, key, value, loc, strict)
      }
      // Write to expando properties bag (used for instance fields from subclasses)
      match key {
        Symbol(sym) => {
          data.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.bag.properties[to_js_string(key)] = value
          value
        }
      }
    }
    Set(data) => {
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(receiver, key, value, loc, strict)
      }
      // Write to expando properties bag (used for instance fields from subclasses)
      match key {
        Symbol(sym) => {
          data.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.bag.properties[to_js_string(key)] = value
          value
        }
      }
    }
    Array(data) => {
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(receiver, key, value, loc, strict)
      }
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
    }
    Promise(data) => {
      if !strict_equal(obj, receiver) {
        return self.define_value_on_receiver(receiver, key, value, loc, strict)
      }
      match key {
        Symbol(sym) => {
          data.bag.symbol_properties[sym.id] = value
          value
        }
        _ => {
          data.bag.properties[to_js_string(key)] = value
          value
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
        make_native_func(name="log", fn(args) {
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
      let prop_name = match td.bag.properties.get("name") {
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
        Some(NonConstructableInterpreterCallable(n, _)) => "bound " + n
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
    NonConstructableInterpreterCallable(_, _) => 0
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

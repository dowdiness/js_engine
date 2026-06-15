///|
/// Spec [[Get]] for an integer index on an Array exotic object.
/// Centralises the descriptor / dense / hole / OOB dispatch and the
/// receiver-preserving prototype walk so every [[Get]] entry point
/// (`get_property` and both `get_computed_property` index branches)
/// stays in lockstep. The prototype-walk loop in
/// `get_property_from_prototype` keeps its own in-line dispatch
/// because it must `continue` the walk, not recurse.
fn Interpreter::array_get_indexed(
  self : Interpreter,
  obj : Value,
  data : ArrayData,
  index : Int,
  key : String,
  loc : @token.Loc,
) -> Value raise Error {
  match array_index_lookup_result(data, index) {
    Present(v) => v
    OwnAccessor(Some(getter)) => self.call_value(getter, obj, [], loc)
    OwnAccessor(None) => Undefined
    Hole | OutOfRange => {
      let proto = get_array_prototype(self.realm_state, data)
      self.get_property_from_prototype(obj, proto, key, loc)
    }
  }
}

///|
fn Interpreter::with_active_property_access_value(
  self : Interpreter,
  eval : () -> Value raise Error,
) -> Value raise Error {
  with_cleared_active_callee_realm(self.realm_state, fn() raise { eval() })
}

///|
pub fn Interpreter::get_property(
  self : Interpreter,
  obj : Value,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  match obj {
    Object(data) => {
      // Descriptor maps are empty for ordinary object-literal data slots.
      // Check emptiness first so that hot own-data reads avoid hashing the
      // property name into the descriptor map before the value-map lookup.
      let descriptors = data.bag.descriptors
      if descriptors.is_empty() || !descriptors.contains(prop) {
        match data.bag.properties.get(prop) {
          Some(v) => return v
          None => ()
        }
      }
    }
    _ => ()
  }
  self.with_active_property_access_value(fn() raise {
    self.get_property_impl(obj, prop, loc)
  })
}

///|
fn Interpreter::get_property_impl(
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
        if num_idx >= 0 && num_idx.to_string() == prop {
          self.array_get_indexed(obj, data, num_idx, prop, loc)
        } else {
          // Check named properties (e.g., index, input on exec results)
          match data.bag.descriptors.get(prop) {
            Some(desc) =>
              match desc.getter {
                Some(getter) => return self.call_value(getter, obj, [], loc)
                None => if desc.setter is Some(_) { return Undefined }
              }
            None => ()
          }
          match get_array_named_prop(data, prop) {
            Some(v) => v
            None =>
              match get_array_prototype_override(data) {
                Some(proto) =>
                  self.get_property_from_prototype(obj, proto, prop, loc)
                None => {
                  let result = (self.stdlib_hooks.get_array_method_with_interp)(
                    data,
                    prop,
                    self.realm_state,
                  )
                  match result {
                    Undefined =>
                      lookup_builtin_proto(self, obj, "Array", prop, loc)
                    _ => result
                  }
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
          self.realm_state,
          self.annex_b,
        )
        match result {
          Undefined => lookup_builtin_proto(self, obj, "String", prop, loc)
          _ => result
        }
      }
    Number(_) => {
      let result = (self.stdlib_hooks.get_number_method)(
        obj,
        prop,
        self.realm_state,
      )
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
        make_native_func(name="toString", realm_state=Some(self.realm_state), fn(
          _args,
        ) {
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
      let proto = match data.prototype {
        Null => self.realm_state.get_map_proto()
        proto => proto
      }
      self.get_property_from_prototype(obj, proto, prop, loc)
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
      let proto = match data.prototype {
        Null => self.realm_state.get_set_proto()
        proto => proto
      }
      self.get_property_from_prototype(obj, proto, prop, loc)
    }
    Promise(data) => {
      // Check user-defined properties first, then prototype methods.
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
      let proto = match data.prototype {
        Null => self.realm_state.get_promise_proto()
        proto => proto
      }
      self.get_property_from_prototype(obj, proto, prop, loc)
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
/// Look up an inherited property while preserving the original receiver for
/// accessors and Proxy `get` traps.
fn Interpreter::get_property_from_prototype(
  self : Interpreter,
  receiver : Value,
  proto : Value,
  prop : String,
  loc : @token.Loc,
) -> Value raise Error {
  let mut current = proto
  while true {
    match current {
      Object(data) => {
        match data.bag.descriptors.get(prop) {
          Some(desc) =>
            match desc.getter {
              Some(getter) => return self.call_value(getter, receiver, [], loc)
              None => if desc.setter is Some(_) { return Undefined }
            }
          None => ()
        }
        match data.bag.properties.get(prop) {
          Some(v) => return v
          None => current = data.prototype
        }
      }
      Array(data) => {
        if prop == "length" {
          return match get_array_length_override(data) {
            Some(n64) => Number(n64.to_double())
            None => Number(data.elements.length().to_double())
          }
        }
        let num_idx = @string.parse_int(prop) catch { _ => -1 }
        if num_idx >= 0 && num_idx.to_string() == prop {
          // Inside a prototype walk, an Array(data) node still needs spec
          // [[Get]] semantics: own descriptor / dense vs hole / fall through.
          match array_index_lookup_result(data, num_idx) {
            Present(v) => return v
            OwnAccessor(Some(getter)) =>
              return self.call_value(getter, receiver, [], loc)
            OwnAccessor(None) => return Undefined
            Hole | OutOfRange => {
              // Continue the chain via this array's own prototype.
              current = get_array_prototype(self.realm_state, data)
              continue
            }
          }
        }
        match data.bag.descriptors.get(prop) {
          Some(desc) =>
            match desc.getter {
              Some(getter) => return self.call_value(getter, receiver, [], loc)
              None => if desc.setter is Some(_) { return Undefined }
            }
          None => ()
        }
        match get_array_named_prop(data, prop) {
          Some(v) => return v
          None =>
            match get_array_prototype_override(data) {
              Some(next) => current = next
              None =>
                return lookup_builtin_proto(self, receiver, "Array", prop, loc)
            }
        }
      }
      Proxy(proxy_data) => return proxy_get(self, proxy_data, prop, receiver)
      Null => return Undefined
      _ => return self.get_property(current, prop, loc)
    }
  }
  Undefined
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
              return match get_array_length_override(arr_data) {
                Some(n64) => Number(n64.to_double())
                None => Number(arr_data.elements.length().to_double())
              }
            }
            // Check numeric index access on array elements
            let num_idx = @string.parse_int(prop) catch { _ => -1 }
            if num_idx >= 0 && num_idx < arr_data.elements.length() {
              match arr_data.bag.descriptors.get(prop) {
                Some(desc) =>
                  match desc.getter {
                    Some(getter) => return self.call_value(getter, obj, [], loc)
                    None => if desc.setter is Some(_) { return Undefined }
                  }
                None => ()
              }
              return arr_data.elements[num_idx]
            }
            match get_array_named_prop(arr_data, prop) {
              Some(v) => return v
              None => {
                let result = (self.stdlib_hooks.get_array_method_with_interp)(
                  arr_data,
                  prop,
                  self.realm_state,
                )
                match result {
                  Undefined => {
                    // Continue to this array's prototype, honoring per-array overrides.
                    let proto = get_array_prototype(self.realm_state, arr_data)
                    match proto {
                      Object(_) => current = proto
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
            let result = (self.stdlib_hooks.get_map_method)(
              map_data,
              prop,
              self.realm_state,
            )
            match result {
              Undefined => break
              _ => return result
            }
          }
          Set(set_data) => {
            // Handle Set values in the prototype chain
            if prop == "size" {
              return Number(set_data.values.length().to_double())
            }
            let result = (self.stdlib_hooks.get_set_method)(
              set_data,
              prop,
              self.realm_state,
            )
            match result {
              Undefined => break
              _ => return result
            }
          }
          Proxy(proxy_data) => return proxy_get(self, proxy_data, prop, obj)
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
            return stamp_function_realm(
              Object({
                bag: PropertyBag(),
                prototype: Null,
                callable: Some(FuncCallMethod(obj)),
                class_name: "Function",
                extensible: true,
                arraybuffer_state: None,
              }),
              realm_state=Some(self.realm_state),
            )
          } else if prop == "apply" {
            return stamp_function_realm(
              Object({
                bag: PropertyBag(),
                prototype: Null,
                callable: Some(FuncApplyMethod(obj)),
                class_name: "Function",
                extensible: true,
                arraybuffer_state: None,
              }),
              realm_state=Some(self.realm_state),
            )
          } else if prop == "bind" {
            let target = obj
            let target_length = get_function_length(target)
            let target_proto = data.prototype
            return make_native_func(
              name="bind",
              realm_state=Some(self.realm_state),
              fn(args) {
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
                  is_accessor: false,
                }
                let bprops : Map[String, Value] = {}
                bprops["name"] = String_(bound_name)
                bprops["length"] = Number(bound_length.to_double())
                stamp_function_realm(
                  Object({
                    bag: {
                      properties: bprops,
                      symbol_properties: {},
                      descriptors: { "name": nf_desc, "length": nf_desc },
                      symbol_descriptors: {},
                      internal_slots: {},
                    },
                    prototype: target_proto,
                    callable: Some(BoundFunc(target, bind_this, bound_args)),
                    class_name: "Function",
                    extensible: true,
                    arraybuffer_state: None,
                  }),
                  realm_state=Some(self.realm_state),
                )
              },
            )
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
              NativeCallable(n, _) | NativeCallableWithContext(n, _) => n
              NonConstructableCallable(n, _) => n
              FuncCallMethod(_) => "call"
              FuncApplyMethod(_) => "apply"
              MethodCallable(n, _) => n
              InterpreterCallable(n, _)
              | InterpreterCallableWithContext(n, _) => n
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
              NativeCallable(n, _) | NativeCallableWithContext(n, _) =>
                "function " + n + "() { [native code] }"
              NonConstructableCallable(n, _) =>
                "function " + n + "() { [native code] }"
              FuncCallMethod(_) => "function call() { [native code] }"
              FuncApplyMethod(_) => "function apply() { [native code] }"
              MethodCallable(n, _) => "function " + n + "() { [native code] }"
              InterpreterCallable(n, _)
              | InterpreterCallableWithContext(n, _) =>
                "function " + n + "() { [native code] }"
              NonConstructableInterpreterCallable(n, _) =>
                "function " + n + "() { [native code] }"
              ConstructorOnlyCallable(n, _) =>
                "function " + n + "() { [native code] }"
              ClassConstructor({ name: n, .. }) =>
                "class " + n + " { [native code] }"
            }
            return make_native_func(
              name="toString",
              realm_state=Some(self.realm_state),
              fn(_args) { String_(func_str) },
            )
          } else if prop == "prototype" {
            // Only constructable functions have a prototype property
            // Non-constructable (arrow functions, bound functions, etc.) return undefined
            let is_constructable = match callable {
              UserFunc(fd) => !fd.is_method
              UserFuncExt(fd) => !fd.is_method
              NativeCallable(_, _)
              | NativeCallableWithContext(_, _)
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
              | InterpreterCallable(_, _)
              | InterpreterCallableWithContext(_, _) => false
            }
            if !is_constructable || callable is ConstructorOnlyCallable(_, _) {
              return Undefined
            }
            // For constructable functions, check if prototype exists
            match data.bag.properties.get("prototype") {
              Some(p) => return p
              None => {
                // Create and memoize default prototype
                let proto : Value = Object({
                  bag: PropertyBag(),
                  prototype: get_obj_proto(realm_state=Some(self.realm_state)),
                  callable: None,
                  class_name: "Object",
                  extensible: true,
                  arraybuffer_state: None,
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
          return make_method_func(
            name="hasOwnProperty",
            length=1,
            realm_state=Some(self.realm_state),
            fn(this_val, args) {
              let key_val = if args.length() > 0 { args[0] } else { Undefined }
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
            },
          )
        }
        if prop == "toString" {
          return make_native_func(
            name="toString",
            realm_state=Some(self.realm_state),
            fn(_args) { String_("[object Object]") },
          )
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
  // Resolve the built-in prototype through the active callee realm rather
  // than re-deriving it through `globalThis[ctor_name].prototype`.
  // Unknown ctor names fall through to Undefined, matching the previous
  // `interp.global.get(...) catch { _ => Undefined }` behavior.
  let proto = match ctor_name {
    "Array" => get_array_proto(realm_state=Some(interp.realm_state))
    "String" => get_string_proto(realm_state=Some(interp.realm_state))
    "Number" => get_number_proto(realm_state=Some(interp.realm_state))
    "Boolean" => get_boolean_proto(realm_state=Some(interp.realm_state))
    "Symbol" => get_symbol_proto(realm_state=Some(interp.realm_state))
    _ => return Undefined
  }
  match proto {
    Object(proto_data) => {
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
}

///|
pub fn Interpreter::get_computed_property(
  self : Interpreter,
  obj : Value,
  key : Value,
  loc : @token.Loc,
) -> Value raise Error {
  self.with_active_property_access_value(fn() raise {
    self.get_computed_property_impl(obj, key, loc)
  })
}

///|
fn Interpreter::get_computed_property_impl(
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
        _ => to_js_string(key, interp=Some(self))
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
    Symbol(sym) => {
      let realm_state = self.realm_state
      let well_known_symbols = self.realm_state.well_known_symbols
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
              let iterator_sym = well_known_symbols.iterator
              if sym.id == iterator_sym.id {
                if data.class_name == "String" {
                  match data.bag.properties.get("[[StringData]]") {
                    Some(String_(_)) =>
                      return make_method_func(
                        name="[Symbol.iterator]",
                        length=0,
                        realm_state=Some(realm_state),
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
                          realm_state.make_string_iterator_value(str)
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
          let iterator_sym = well_known_symbols.iterator
          if sym.id == iterator_sym.id {
            // Return a function that creates a string iterator
            return make_method_func(
              name="[Symbol.iterator]",
              length=0,
              realm_state=Some(realm_state),
              fn(_this_val, _args) { realm_state.make_string_iterator_value(s) },
            )
          }
          return Undefined
        }
        Array(arr) => {
          // Check array's own symbol property bag first.
          match get_array_symbol_prop(arr, sym.id) {
            Some(v) => return v
            None => ()
          }
          // Check Array.prototype for symbol properties (e.g. overridden Symbol.iterator)
          // while honoring per-array prototype overrides.
          match get_array_prototype(self.realm_state, arr) {
            Object(proto_data) => {
              // Check symbol descriptors for getters
              match proto_data.bag.symbol_descriptors.get(sym.id) {
                Some(desc) =>
                  match desc.getter {
                    Some(getter) => return self.call_value(getter, obj, [], loc)
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
          // Handle Symbol.iterator default for arrays
          let iterator_sym = well_known_symbols.iterator
          if sym.id == iterator_sym.id {
            let (override_getter, override_value) = get_array_iterator_override(
              arr,
              well_known_symbols~,
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
            return make_method_func(
              name="[Symbol.iterator]",
              length=0,
              realm_state=Some(realm_state),
              fn(_this_val, _args) {
                realm_state.make_array_iterator_value(arr)
              },
            )
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
          let iterator_sym = well_known_symbols.iterator
          if sym.id == iterator_sym.id {
            return (self.stdlib_hooks.get_map_method)(
              map_data,
              "entries",
              self.realm_state,
            )
          }
          let tostringtag_sym = well_known_symbols.to_string_tag
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
          let iterator_sym = well_known_symbols.iterator
          if sym.id == iterator_sym.id {
            return (self.stdlib_hooks.get_set_method)(
              set_data,
              "values",
              self.realm_state,
            )
          }
          let tostringtag_sym = well_known_symbols.to_string_tag
          if sym.id == tostringtag_sym.id {
            return String_("Set")
          }
          return Undefined
        }
        Promise(data) => {
          match data.bag.symbol_properties.get(sym.id) {
            Some(v) => return v
            None => ()
          }
          let proto = match data.prototype {
            Null => self.realm_state.get_promise_proto()
            proto => proto
          }
          return self.get_symbol_property_from_prototype(obj, proto, sym, loc)
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
              return (self.stdlib_hooks.typedarray_get_index)(
                data,
                idx,
                self.realm_state,
              )
            }
            // Non-integer or negative Number key: return undefined per spec
            return Undefined
          }
          String_(s) =>
            match classify_typedarray_string_key(s) {
              Some(-1) => return Undefined
              Some(idx) =>
                return (self.stdlib_hooks.typedarray_get_index)(
                  data,
                  idx,
                  self.realm_state,
                )
              None => ()
            }
          _ => ()
        }
      }
      let prop = to_js_string(key, interp=Some(self))
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
                      arr_data,
                      prop,
                      self.realm_state,
                    )
                    match result {
                      Undefined => {
                        // Continue to this array's prototype, honoring per-array overrides.
                        let proto = get_array_prototype(
                          self.realm_state,
                          arr_data,
                        )
                        match proto {
                          Object(_) => current = proto
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
                let result = (self.stdlib_hooks.get_map_method)(
                  map_data,
                  prop,
                  self.realm_state,
                )
                match result {
                  Undefined => break
                  _ => return result
                }
              }
              Set(set_data) => {
                if prop == "size" {
                  return Number(set_data.values.length().to_double())
                }
                let result = (self.stdlib_hooks.get_set_method)(
                  set_data,
                  prop,
                  self.realm_state,
                )
                match result {
                  Undefined => break
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
                return stamp_function_realm(
                  Object({
                    bag: PropertyBag(),
                    prototype: Null,
                    callable: Some(FuncCallMethod(obj)),
                    class_name: "Function",
                    extensible: true,
                    arraybuffer_state: None,
                  }),
                  realm_state=Some(self.realm_state),
                )
              } else if prop == "apply" {
                return stamp_function_realm(
                  Object({
                    bag: PropertyBag(),
                    prototype: Null,
                    callable: Some(FuncApplyMethod(obj)),
                    class_name: "Function",
                    extensible: true,
                    arraybuffer_state: None,
                  }),
                  realm_state=Some(self.realm_state),
                )
              } else if prop == "bind" {
                let target = obj
                let target_length = get_function_length(target)
                let target_proto = data.prototype
                return make_native_func(
                  name="bind",
                  realm_state=Some(self.realm_state),
                  fn(args) {
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
                      is_accessor: false,
                    }
                    let bprops : Map[String, Value] = {}
                    bprops["name"] = String_(bound_name)
                    bprops["length"] = Number(bound_length.to_double())
                    stamp_function_realm(
                      Object({
                        bag: {
                          properties: bprops,
                          symbol_properties: {},
                          descriptors: { "name": nf_desc, "length": nf_desc },
                          symbol_descriptors: {},
                          internal_slots: {},
                        },
                        prototype: target_proto,
                        callable: Some(BoundFunc(target, bind_this, bound_args)),
                        class_name: "Function",
                        extensible: true,
                        arraybuffer_state: None,
                      }),
                      realm_state=Some(self.realm_state),
                    )
                  },
                )
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
                  NativeCallable(n, _) | NativeCallableWithContext(n, _) => n
                  NonConstructableCallable(n, _) => n
                  FuncCallMethod(_) => "call"
                  FuncApplyMethod(_) => "apply"
                  MethodCallable(n, _) => n
                  InterpreterCallable(n, _)
                  | InterpreterCallableWithContext(n, _) => n
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
                  NativeCallable(n, _) | NativeCallableWithContext(n, _) =>
                    "function " + n + "() { [native code] }"
                  NonConstructableCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  FuncCallMethod(_) => "function call() { [native code] }"
                  FuncApplyMethod(_) => "function apply() { [native code] }"
                  MethodCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  InterpreterCallable(n, _)
                  | InterpreterCallableWithContext(n, _) =>
                    "function " + n + "() { [native code] }"
                  NonConstructableInterpreterCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ConstructorOnlyCallable(n, _) =>
                    "function " + n + "() { [native code] }"
                  ClassConstructor({ name: n, .. }) =>
                    "class " + n + " { [native code] }"
                }
                return make_native_func(
                  name="toString",
                  realm_state=Some(self.realm_state),
                  fn(_args) { String_(func_str) },
                )
              } else if prop == "prototype" {
                // Only constructable functions have a prototype property
                // Non-constructable (arrow functions, bound functions, etc.) return undefined
                let is_constructable = match callable {
                  UserFunc(fd) => !fd.is_method
                  UserFuncExt(fd) => !fd.is_method
                  NativeCallable(_, _)
                  | NativeCallableWithContext(_, _)
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
                  | InterpreterCallable(_, _)
                  | InterpreterCallableWithContext(_, _) => false
                }
                if !is_constructable ||
                  callable is ConstructorOnlyCallable(_, _) {
                  return Undefined
                }
                // For constructable functions, check if prototype exists
                match data.bag.properties.get("prototype") {
                  Some(p) => return p
                  None => {
                    // Create and memoize default prototype
                    let proto : Value = Object({
                      bag: PropertyBag(),
                      prototype: get_obj_proto(
                        realm_state=Some(self.realm_state),
                      ),
                      callable: None,
                      class_name: "Object",
                      extensible: true,
                      arraybuffer_state: None,
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
              return make_method_func(
                name="hasOwnProperty",
                length=1,
                realm_state=Some(self.realm_state),
                fn(this_val, args) {
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
                        _ =>
                          Bool(d.bag.properties.contains(key_val.to_string()))
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
                },
              )
            }
            if prop == "toString" {
              return make_native_func(
                name="toString",
                realm_state=Some(self.realm_state),
                fn(_args) { String_("[object Object]") },
              )
            }
          }
          Undefined
        }
      }
    }
    Array(data) =>
      match key {
        Number(n) => {
          // Use Int64 to avoid overflow for indices >= 2^31.
          let i64 = n.to_int64()
          if n >= 0.0 && n == i64.to_double() && i64 <= 0x7FFFFFFFL {
            let i = i64.to_int()
            self.array_get_indexed(obj, data, i, i.to_string(), loc)
          } else {
            // Non-integer or very-large key: not handled by the dense
            // index path. Check own descriptors / named-prop bag first,
            // then fall through to prototype walk so inherited indexed
            // and non-indexed numeric keys are resolved per spec.
            let key_str = to_js_string(Number(n))
            match data.bag.descriptors.get(key_str) {
              Some(desc) =>
                match desc.getter {
                  Some(getter) => return self.call_value(getter, obj, [], loc)
                  None => if desc.setter is Some(_) { return Undefined }
                }
              None => ()
            }
            match get_array_named_prop(data, key_str) {
              Some(v) => v
              None => {
                let proto = get_array_prototype(self.realm_state, data)
                self.get_property_from_prototype(obj, proto, key_str, loc)
              }
            }
          }
        }
        String_("length") =>
          match get_array_length_override(data) {
            Some(n64) => Number(n64.to_double())
            None => Number(data.elements.length().to_double())
          }
        String_(s) => {
          // Canonical numeric index string check: parseDouble(s).toString() === s.
          // Mirror the Number(n) branch's Int-range discipline so large
          // numeric strings like "3000000000" (valid array length but
          // outside Int) flow into the non-index path and walk the
          // prototype, rather than overflowing `n.to_int()`.
          let mut is_index : Bool = false
          let mut idx : Int = -1
          try {
            let n = @string.parse_double(s)
            if n >= 0.0 && n.to_string() == s {
              let i64 = n.to_int64()
              if i64.to_double() == n && i64 <= 0x7FFFFFFFL {
                is_index = true
                idx = i64.to_int()
              }
            }
          } catch {
            _ => () // Not a numeric string
          }
          if is_index {
            self.array_get_indexed(obj, data, idx, s, loc)
          } else {
            // Non-index string key: own descriptor → method dispatch → prototype.
            match data.bag.descriptors.get(s) {
              Some(desc) =>
                match desc.getter {
                  Some(getter) => return self.call_value(getter, obj, [], loc)
                  None => if desc.setter is Some(_) { return Undefined }
                }
              None => ()
            }
            // Check bag-backed named properties, then prototype chain / methods.
            match get_array_named_prop(data, s) {
              Some(v) => v
              None =>
                // Prototype override (explicit Object.setPrototypeOf) must be
                // consulted before the built-in method shortcut so that, e.g.,
                // Object.setPrototypeOf(arr, { map: 42 }); arr["map"] === 42.
                match get_array_prototype_override(data) {
                  Some(proto) =>
                    self.get_property_from_prototype(obj, proto, s, loc)
                  None => {
                    // Mirror the `Interpreter::get_property` pattern: many
                    // built-in methods (map/filter/forEach/…) are delegated
                    // to the live `Array.prototype` and return Undefined
                    // from the shortcut. Fall through to the actual
                    // %Array.prototype% walk so `arr["map"]` resolves the
                    // built-in (and so non-index numeric strings keep
                    // ascending to `Object.prototype`).
                    let result = (self.stdlib_hooks.get_array_method_with_interp)(
                      data,
                      s,
                      self.realm_state,
                    )
                    match result {
                      Undefined =>
                        lookup_builtin_proto(self, obj, "Array", s, loc)
                      _ => result
                    }
                  }
                }
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
          (self.stdlib_hooks.get_string_method)(
            s,
            method_name,
            self.realm_state,
            self.annex_b,
          )
        _ => Undefined
      }
    Number(_) =>
      match key {
        String_(method_name) =>
          (self.stdlib_hooks.get_number_method)(
            obj,
            method_name,
            self.realm_state,
          )
        _ => Undefined
      }
    Map(_) | Set(_) => {
      let prop = to_js_string(key, interp=Some(self))
      self.get_property(obj, prop, loc)
    }
    Promise(_) => {
      let prop = to_js_string(key, interp=Some(self))
      self.get_property(obj, prop, loc)
    }
    Null => {
      let key_str = match key {
        Symbol(sym) =>
          match sym.description {
            Some(d) => "Symbol(\{d})"
            None => "Symbol()"
          }
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
        Symbol(sym) =>
          match sym.description {
            Some(d) => "Symbol(\{d})"
            None => "Symbol()"
          }
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

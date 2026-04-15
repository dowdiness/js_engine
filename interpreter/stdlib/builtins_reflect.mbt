///|
/// Convert an array-like value to an Array[Value] (CreateListFromArrayLike)
fn create_list_from_array_like(val : Value) -> Array[Value] raise Error {
  match val {
    Value::Array(data) => data.elements.copy()
    Object(data) => {
      let result : Array[Value] = []
      match data.properties.get("length") {
        Some(len_val) => {
          let len = @runtime.to_number(len_val).to_int()
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
    Value::Proxy(proxy_data) =>
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
fn setup_reflect_builtins(env : Environment, sym_state : SymbolState) -> Unit {
  let reflect_props : Map[String, Value] = {}
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }

  // Reflect.apply(target, thisArg, argumentsList)
  reflect_props["apply"] = @runtime.make_interp_method_func("apply", 3, fn(
    interp,
    _this_val,
    args,
  ) raise {
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
  })

  // Reflect.construct(target, argumentsList, newTarget?)
  reflect_props["construct"] = @runtime.make_interp_method_func(
    "construct",
    2,
    fn(interp, _this_val, args) raise {
      if args.length() < 2 {
        raise @errors.TypeError(
          message="Reflect.construct requires at least 2 arguments",
        )
      }
      let target = args[0]
      // target must be a constructor
      if !@runtime.is_constructor_value(target) {
        raise @errors.TypeError(
          message="Reflect.construct: target is not a constructor",
        )
      }
      let arg_list = create_list_from_array_like(args[1])
      let loc = @token.Loc::default()
      // Per spec, when newTarget differs from target, create instance with newTarget.prototype
      let proto_override : Value? = if args.length() > 2 {
        let new_target = args[2]
        // newTarget must be a constructor
        if !@runtime.is_constructor_value(new_target) {
          raise @errors.TypeError(
            message="Reflect.construct: newTarget is not a constructor",
          )
        }
        match new_target {
          Object(nt_data) =>
            Some(
              match nt_data.properties.get("prototype") {
                Some(p) => p
                None => Null
              },
            )
          _ => None
        }
      } else {
        None
      }
      interp.construct_value(target, arg_list, loc, proto_override~)
    },
  )

  // Reflect.defineProperty(target, propertyKey, attributes)
  reflect_props["defineProperty"] = Value::Object({
    properties: {
      "name": Value::String_("defineProperty"),
      "length": Value::Number(3.0),
    },
    symbol_properties: {},
    prototype: @runtime.get_func_proto(),
    callable: Some(
      NativeCallable("defineProperty", fn(args) raise {
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
            let has_writable = attr_data.properties.contains("writable")
            if has_value && (has_get || has_set) {
              raise @errors.TypeError(
                message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute",
              )
            }
            if has_writable && (has_get || has_set) {
              raise @errors.TypeError(
                message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute",
              )
            }
            let is_accessor = has_get || has_set
            let prop_exists = data.properties.contains(prop) ||
              data.descriptors.contains(prop)
            // Extensibility check: cannot add new property to non-extensible object
            if !prop_exists && !data.extensible {
              return Value::Bool(false)
            }
            // Non-configurable validation
            if prop_exists {
              match data.descriptors.get(prop) {
                Some(existing) =>
                  if !existing.configurable {
                    let existing_is_accessor = existing.getter is Some(_) ||
                      existing.setter is Some(_)
                    // Cannot change between accessor and data descriptor types
                    if existing_is_accessor &&
                      !is_accessor &&
                      (has_value || has_writable) {
                      return Value::Bool(false)
                    }
                    if !existing_is_accessor && is_accessor {
                      return Value::Bool(false)
                    }
                    // Cannot change configurable from false to true
                    match attr_data.properties.get("configurable") {
                      Some(v) =>
                        if @runtime.is_truthy(v) {
                          return Value::Bool(false)
                        }
                      None => ()
                    }
                    // Cannot change enumerable on non-configurable
                    match attr_data.properties.get("enumerable") {
                      Some(v) =>
                        if @runtime.is_truthy(v) != existing.enumerable {
                          return Value::Bool(false)
                        }
                      None => ()
                    }
                    // Non-configurable accessor: getter/setter identity must match
                    if existing_is_accessor && is_accessor {
                      match attr_data.properties.get("get") {
                        Some(g) =>
                          match existing.getter {
                            Some(eg) =>
                              if !strict_equal_val(g, eg) {
                                return Value::Bool(false)
                              }
                            None =>
                              if !(g is Undefined) {
                                return Value::Bool(false)
                              }
                          }
                        None => ()
                      }
                      match attr_data.properties.get("set") {
                        Some(s) =>
                          match existing.setter {
                            Some(es) =>
                              if !strict_equal_val(s, es) {
                                return Value::Bool(false)
                              }
                            None =>
                              if !(s is Undefined) {
                                return Value::Bool(false)
                              }
                          }
                        None => ()
                      }
                    }
                    // Non-configurable data: writable false->true forbidden, value change on non-writable forbidden
                    if !existing_is_accessor && !is_accessor {
                      if !existing.writable {
                        match attr_data.properties.get("writable") {
                          Some(v) =>
                            if @runtime.is_truthy(v) {
                              return Value::Bool(false)
                            }
                          None => ()
                        }
                        if has_value {
                          let new_val = match
                            attr_data.properties.get("value") {
                            Some(v) => v
                            None => Undefined
                          }
                          let old_val = match data.properties.get(prop) {
                            Some(v) => v
                            None => Undefined
                          }
                          if !strict_equal_val(new_val, old_val) {
                            return Value::Bool(false)
                          }
                        }
                      }
                    }
                  }
                None => ()
              }
            }
            if is_accessor {
              // Accessor descriptor
              let getter = attr_data.properties.get("get")
              let setter = attr_data.properties.get("set")
              let enumerable = match attr_data.properties.get("enumerable") {
                Some(v) => @runtime.is_truthy(v)
                None =>
                  match data.descriptors.get(prop) {
                    Some(d) => d.enumerable
                    None => false
                  }
              }
              let configurable = match
                attr_data.properties.get("configurable") {
                Some(v) => @runtime.is_truthy(v)
                None =>
                  match data.descriptors.get(prop) {
                    Some(d) => d.configurable
                    None => false
                  }
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
                Some(v) => @runtime.is_truthy(v)
                None =>
                  match data.descriptors.get(prop) {
                    Some(d) => d.writable
                    None => false
                  }
              }
              let enumerable = match attr_data.properties.get("enumerable") {
                Some(v) => @runtime.is_truthy(v)
                None =>
                  match data.descriptors.get(prop) {
                    Some(d) => d.enumerable
                    None => false
                  }
              }
              let configurable = match
                attr_data.properties.get("configurable") {
                Some(v) => @runtime.is_truthy(v)
                None =>
                  match data.descriptors.get(prop) {
                    Some(d) => d.configurable
                    None => false
                  }
              }
              if has_value {
                data.properties[prop] = match
                  attr_data.properties.get("value") {
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
            Value::Bool(true)
          }
          _ =>
            raise @errors.TypeError(
              message="Property description must be an object",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.deleteProperty(target, propertyKey)
  reflect_props["deleteProperty"] = @runtime.make_interp_method_func(
    "deleteProperty",
    2,
    fn(interp, _this_val, args) raise {
      if args.length() < 2 {
        raise @errors.TypeError(
          message="Reflect.deleteProperty requires 2 arguments",
        )
      }
      let target = args[0]
      let prop = args[1].to_string()
      match target {
        Value::Proxy(proxy_data) =>
          Bool(@runtime.proxy_delete_property(interp, proxy_data, prop))
        Object(data) => {
          match data.descriptors.get(prop) {
            Some(desc) => if !desc.configurable { return Value::Bool(false) }
            None => ()
          }
          let _ = data.properties.remove(prop)
          let _ = data.descriptors.remove(prop)
          Value::Bool(true)
        }
        _ =>
          raise @errors.TypeError(
            message="Reflect.deleteProperty called on non-object",
          )
      }
    },
  )

  // Reflect.get(target, propertyKey, receiver?)
  reflect_props["get"] = @runtime.make_interp_method_func("get", 2, fn(
    interp,
    _this_val,
    args,
  ) raise {
    if args.length() < 2 {
      raise @errors.TypeError(
        message="Reflect.get requires at least 2 arguments",
      )
    }
    let target = args[0]
    match target {
      Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
      _ => raise @errors.TypeError(message="Reflect.get called on non-object")
    }
    let key = args[1]
    let receiver = if args.length() > 2 { args[2] } else { target }
    let loc = @token.Loc::default()
    // For receiver support, we need to check for accessor descriptors
    // and call getters with the receiver as this
    let key_str = match key {
      Symbol(_) => ""
      _ => key.to_string()
    }
    // Helper to find accessor descriptor and call with receiver
    fn try_get_with_receiver(obj : Value) -> Value? raise {
      match obj {
        Object(data) =>
          match key {
            Value::Symbol(sym) =>
              match data.symbol_descriptors.get(sym.id) {
                Some(desc) =>
                  match desc.getter {
                    Some(getter) =>
                      Some(interp.call_value(getter, receiver, [], loc))
                    None =>
                      match data.symbol_properties.get(sym.id) {
                        Some(v) => Some(v)
                        None => None
                      }
                  }
                None =>
                  match data.symbol_properties.get(sym.id) {
                    Some(v) => Some(v)
                    None => None
                  }
              }
            _ =>
              match data.descriptors.get(key_str) {
                Some(desc) =>
                  match desc.getter {
                    Some(getter) =>
                      Some(interp.call_value(getter, receiver, [], loc))
                    None =>
                      match data.properties.get(key_str) {
                        Some(v) => Some(v)
                        None => None
                      }
                  }
                None =>
                  match data.properties.get(key_str) {
                    Some(v) => Some(v)
                    None => None
                  }
              }
          }
        _ => None
      }
    }
    // Check target first
    match try_get_with_receiver(target) {
      Some(v) => v
      None => {
        // Walk prototype chain
        let mut current = match target {
          Object(data) => data.prototype
          _ => Null
        }
        while true {
          match current {
            Object(data) =>
              match try_get_with_receiver(current) {
                Some(v) => return v
                None => current = data.prototype
              }
            Null => break
            _ => break
          }
        }
        // Fall back to regular property access if receiver == target
        if @runtime.strict_equal(receiver, target) {
          match key {
            Symbol(_) => interp.get_computed_property(target, key, loc)
            _ => interp.get_property(target, key_str, loc)
          }
        } else {
          Undefined
        }
      }
    }
  })

  // Reflect.getOwnPropertyDescriptor(target, propertyKey)
  reflect_props["getOwnPropertyDescriptor"] = Value::Object({
    properties: {
      "name": Value::String_("getOwnPropertyDescriptor"),
      "length": Value::Number(2.0),
    },
    symbol_properties: {},
    prototype: @runtime.get_func_proto(),
    callable: Some(
      NativeCallable("getOwnPropertyDescriptor", fn(args) raise {
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
        if !has_own_data && !has_own_desc {
          return Undefined
        }
        let result_props : Map[String, Value] = {}
        match data.descriptors.get(prop) {
          Some(desc) => {
            let is_accessor = desc.getter is Some(_) || desc.setter is Some(_)
            if is_accessor {
              // Accessor descriptor
              result_props["get"] = match desc.getter {
                Some(g) => g
                None => Undefined
              }
              result_props["set"] = match desc.setter {
                Some(s) => s
                None => Undefined
              }
            } else {
              // Data descriptor
              result_props["value"] = match data.properties.get(prop) {
                Some(v) => v
                None => Undefined
              }
              result_props["writable"] = Bool(desc.writable)
            }
            result_props["enumerable"] = Bool(desc.enumerable)
            result_props["configurable"] = Bool(desc.configurable)
          }
          None => {
            result_props["value"] = match data.properties.get(prop) {
              Some(v) => v
              None => Undefined
            }
            result_props["writable"] = Value::Bool(true)
            result_props["enumerable"] = Value::Bool(true)
            result_props["configurable"] = Value::Bool(true)
          }
        }
        Value::Object({
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
    descriptors: { "name": nf_desc, "length": nf_desc },
    symbol_descriptors: {},
    extensible: true,
  })

  // Reflect.getPrototypeOf(target)
  reflect_props["getPrototypeOf"] = @runtime.make_interp_method_func(
    "getPrototypeOf",
    1,
    fn(interp, _this_val, args) raise {
      if args.length() < 1 {
        raise @errors.TypeError(
          message="Reflect.getPrototypeOf requires 1 argument",
        )
      }
      match args[0] {
        Object(data) => data.prototype
        Value::Proxy(proxy_data) =>
          @runtime.proxy_get_prototype_of(interp, proxy_data)
        _ =>
          raise @errors.TypeError(
            message="Reflect.getPrototypeOf called on non-object",
          )
      }
    },
  )

  // Reflect.has(target, propertyKey)
  reflect_props["has"] = @runtime.make_interp_method_func("has", 2, fn(
    interp,
    _this_val,
    args,
  ) raise {
    if args.length() < 2 {
      raise @errors.TypeError(message="Reflect.has requires 2 arguments")
    }
    let target = args[0]
    let prop = args[1].to_string()
    match target {
      Value::Proxy(proxy_data) =>
        Bool(@runtime.proxy_has_property(interp, proxy_data, prop))
      Object(_) | Array(_) => Bool(interp.has_property(target, prop))
      _ =>
        raise @errors.TypeError(message="Reflect.has called on non-object")
    }
  })

  // Reflect.isExtensible(target)
  reflect_props["isExtensible"] = @runtime.make_interp_method_func(
    "isExtensible",
    1,
    fn(interp, _this_val, args) raise {
      if args.length() < 1 {
        raise @errors.TypeError(
          message="Reflect.isExtensible requires 1 argument",
        )
      }
      match args[0] {
        Object(data) => Bool(data.extensible)
        Value::Proxy(proxy_data) =>
          Bool(@runtime.proxy_is_extensible(interp, proxy_data))
        _ =>
          raise @errors.TypeError(
            message="Reflect.isExtensible called on non-object",
          )
      }
    },
  )

  // Reflect.ownKeys(target)
  reflect_props["ownKeys"] = @runtime.make_interp_method_func("ownKeys", 1, fn(
    interp,
    _this_val,
    args,
  ) raise {
    if args.length() < 1 {
      raise @errors.TypeError(message="Reflect.ownKeys requires 1 argument")
    }
    let target = args[0]
    match target {
      Value::Proxy(proxy_data) =>
        @runtime.proxy_own_property_keys(interp, proxy_data)
      Object(_) | Value::Array(_) =>
        Value::Array({
          elements: @runtime.collect_target_own_keys(target, interp.symbols),
        })
      _ =>
        raise @errors.TypeError(
          message="Reflect.ownKeys called on non-object",
        )
    }
  })

  // Reflect.preventExtensions(target)
  reflect_props["preventExtensions"] = @runtime.make_interp_method_func(
    "preventExtensions",
    1,
    fn(interp, _this_val, args) raise {
      if args.length() < 1 {
        raise @errors.TypeError(
          message="Reflect.preventExtensions requires 1 argument",
        )
      }
      match args[0] {
        Object(data) => {
          data.extensible = false
          Value::Bool(true)
        }
        Value::Proxy(proxy_data) =>
          Bool(@runtime.proxy_prevent_extensions(interp, proxy_data))
        _ =>
          raise @errors.TypeError(
            message="Reflect.preventExtensions called on non-object",
          )
      }
    },
  )

  // Reflect.set(target, propertyKey, value, receiver?)
  reflect_props["set"] = @runtime.make_interp_method_func("set", 3, fn(
    interp,
    _this_val,
    args,
  ) raise {
    if args.length() < 3 {
      raise @errors.TypeError(
        message="Reflect.set requires at least 3 arguments",
      )
    }
    let target = args[0]
    match target {
      Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
      _ => raise @errors.TypeError(message="Reflect.set called on non-object")
    }
    let prop = args[1].to_string()
    let value = args[2]
    // Check for write failures before attempting set
    match target {
      Object(data) => {
        match data.descriptors.get(prop) {
          Some(desc) => {
            // Accessor with getter-only: write fails
            if desc.getter is Some(_) && desc.setter is None {
              return Value::Bool(false)
            }
            // Non-writable data property: write fails
            if desc.getter is None && !desc.writable {
              return Value::Bool(false)
            }
          }
          None => ()
        }
        // Non-extensible and property doesn't exist: write fails
        if !data.extensible &&
          !data.properties.contains(prop) &&
          !data.descriptors.contains(prop) {
          return Value::Bool(false)
        }
      }
      _ => ()
    }
    let loc = @token.Loc::default()
    try {
      let _ = interp.set_property(target, prop, value, loc, strict=true)
      Value::Bool(true)
    } catch {
      @errors.TypeError(_) => Value::Bool(false)
      e => raise e
    }
  })

  // Reflect.setPrototypeOf(target, proto)
  reflect_props["setPrototypeOf"] = @runtime.make_interp_method_func(
    "setPrototypeOf",
    2,
    fn(interp, _this_val, args) raise {
      if args.length() < 2 {
        raise @errors.TypeError(
          message="Reflect.setPrototypeOf requires 2 arguments",
        )
      }
      let target = args[0]
      let proto = args[1]
      match proto {
        Object(_) | Null => ()
        _ =>
          raise @errors.TypeError(
            message="Object prototype may only be an Object or null",
          )
      }
      match target {
        Value::Proxy(proxy_data) =>
          Bool(@runtime.proxy_set_prototype_of(interp, proxy_data, proto))
        Object(data) => {
          if !data.extensible &&
            !@runtime.strict_equal(proto, data.prototype) {
            return Value::Bool(false)
          }
          data.prototype = proto
          Value::Bool(true)
        }
        _ =>
          raise @errors.TypeError(
            message="Reflect.setPrototypeOf called on non-object",
          )
      }
    },
  )

  // Create the Reflect object
  let tostringtag_sym = @runtime.get_tostringtag_symbol()
  let reflect_sym_props : Map[Int, Value] = {}
  reflect_sym_props[tostringtag_sym.id] = Value::String_("Reflect")
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let reflect_descs : Map[String, PropDescriptor] = {}
  reflect_descs["apply"] = method_desc
  reflect_descs["construct"] = method_desc
  reflect_descs["defineProperty"] = method_desc
  reflect_descs["deleteProperty"] = method_desc
  reflect_descs["get"] = method_desc
  reflect_descs["getOwnPropertyDescriptor"] = method_desc
  reflect_descs["getPrototypeOf"] = method_desc
  reflect_descs["has"] = method_desc
  reflect_descs["isExtensible"] = method_desc
  reflect_descs["ownKeys"] = method_desc
  reflect_descs["preventExtensions"] = method_desc
  reflect_descs["set"] = method_desc
  reflect_descs["setPrototypeOf"] = method_desc
  let reflect_sym_descs : Map[Int, PropDescriptor] = {}
  reflect_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let reflect_obj : Value = Value::Object({
    properties: reflect_props,
    symbol_properties: reflect_sym_props,
    prototype: Null,
    callable: None,
    class_name: "Object",
    descriptors: reflect_descs,
    symbol_descriptors: reflect_sym_descs,
    extensible: true,
  })
  env.def_builtin("Reflect", reflect_obj)
}

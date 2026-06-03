///|
// Helper functions (to_object and descriptor object builders) live in
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
  realm_state : @runtime.RealmState,
) -> Unit {
  let well_known_symbols = realm_state.well_known_symbols
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  // Object.keys, Object.values, Object.entries, Object.create, Object.assign,
  // Object.getPrototypeOf, Object.getOwnPropertyNames
  let obj_proto_props : Map[String, Value] = {}
  obj_proto_props["toString"] = @runtime.make_method_func(
    name="toString",
    length=0,
    fn(this_val, _args) raise {
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
          let tag = @runtime.get_tostringtag_value(data, well_known_symbols)
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
    },
  )
  obj_proto_props["valueOf"] = @runtime.make_interp_method_func(
    name="valueOf",
    length=0,
    fn(interp, this_val, _args) raise { to_object(this_val, interp) },
  )
  obj_proto_props["hasOwnProperty"] = @runtime.make_interp_method_func(
    name="hasOwnProperty",
    length=1,
    fn(interp, this_val, args) raise {
      let key_val = if args.length() > 0 { args[0] } else { Undefined }
      // §20.1.3.2 step 1: ToPropertyKey runs before ToObject/ToObject-like
      // receiver validation, so user coercion errors from the key win.
      let prop_key = @runtime.to_property_key(key_val, interp=Some(interp))
      // RequireObjectCoercible(this) - throw TypeError for null/undefined.
      match this_val {
        Null | Undefined =>
          raise @errors.TypeError(
            message="Cannot convert undefined or null to object",
          )
        _ => ()
      }
      match this_val {
        Object(data) =>
          match prop_key {
            Value::Symbol(sym) =>
              Bool(
                data.bag.symbol_properties.contains(sym.id) ||
                data.bag.symbol_descriptors.contains(sym.id),
              )
            Value::String_(key) =>
              Bool(
                data.bag.properties.contains(key) ||
                data.bag.descriptors.contains(key),
              )
            _ => Value::Bool(false)
          }
        Value::Array(data) =>
          match prop_key {
            Value::Symbol(sym) =>
              Bool(@runtime.get_array_symbol_prop(data, sym.id) is Some(_))
            Value::String_(key) =>
              if key == "length" {
                Value::Bool(true)
              } else {
                // Check numeric index
                let idx = @string.parse_int(key) catch { _ => -1 }
                if idx >= 0 &&
                  idx.to_string() == key &&
                  idx < data.elements.length() &&
                  !data.holes.contains(idx) {
                  Value::Bool(true)
                } else {
                  // Check named properties stored in ArrayData.bag.
                  Bool(@runtime.get_array_named_prop(data, key) is Some(_))
                }
              }
            _ => Value::Bool(false)
          }
        Value::String_(s) =>
          match prop_key {
            Value::String_(key) =>
              if key == "length" {
                Value::Bool(true)
              } else {
                let idx = @string.parse_int(key) catch { _ => -1 }
                Bool(idx >= 0 && idx.to_string() == key && idx < s.length())
              }
            _ => Value::Bool(false)
          }
        _ => Value::Bool(false)
      }
    },
  )
  obj_proto_props["propertyIsEnumerable"] = @runtime.make_method_func(
    name="propertyIsEnumerable",
    length=1,
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
              match data.bag.symbol_descriptors.get(sym.id) {
                Some(d) => return Bool(d.enumerable)
                None =>
                  if data.bag.symbol_properties.contains(sym.id) {
                    return Value::Bool(true)
                  } else {
                    return Value::Bool(false)
                  }
              }
            Value::Array(data) =>
              match data.bag.symbol_descriptors.get(sym.id) {
                Some(d) => return Bool(d.enumerable)
                None =>
                  if data.bag.symbol_properties.contains(sym.id) {
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
          if data.bag.properties.contains(key) {
            match data.bag.descriptors.get(key) {
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
            if idx >= 0 &&
              idx.to_string() == key &&
              idx < data.elements.length() &&
              !data.holes.contains(idx) {
              match data.bag.descriptors.get(key) {
                Some(d) => Bool(d.enumerable)
                None => Bool(true)
              }
            } else {
              match data.bag.descriptors.get(key) {
                Some(d) => Bool(d.enumerable)
                None => Bool(data.bag.properties.contains(key))
              }
            }
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
    name="isPrototypeOf",
    length=1,
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
        Array(data) =>
          match @runtime.get_array_prototype_override(data) {
            Some(proto) => proto
            None => interp.realm_state.get_array_proto()
          }
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
    name="toLocaleString",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Object(data) =>
          match data.bag.properties.get("toString") {
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
    name="__defineGetter__",
    length=2,
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
          match data.bag.descriptors.get(prop) {
            Some(d) =>
              if !d.configurable {
                raise @errors.TypeError(
                  message="Cannot redefine property: \{prop}",
                )
              }
            None => ()
          }
          if !data.extensible && !data.bag.properties.contains(prop) {
            raise @errors.TypeError(
              message="Cannot define property on a non-extensible object",
            )
          }
          let existing_setter : Value? = match data.bag.descriptors.get(prop) {
            Some(d) => d.setter
            None => None
          }
          data.bag.descriptors[prop] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: Some(getter),
            setter: existing_setter,
            is_accessor: true,
          }
          data.bag.properties[prop] = Undefined
        }
        _ => ()
      }
      Undefined
    },
  )
  obj_proto_props["__defineSetter__"] = @runtime.make_interp_method_func(
    name="__defineSetter__",
    length=2,
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
          match data.bag.descriptors.get(prop) {
            Some(d) =>
              if !d.configurable {
                raise @errors.TypeError(
                  message="Cannot redefine property: \{prop}",
                )
              }
            None => ()
          }
          if !data.extensible && !data.bag.properties.contains(prop) {
            raise @errors.TypeError(
              message="Cannot define property on a non-extensible object",
            )
          }
          let existing_getter : Value? = match data.bag.descriptors.get(prop) {
            Some(d) => d.getter
            None => None
          }
          data.bag.descriptors[prop] = {
            writable: false,
            enumerable: true,
            configurable: true,
            getter: existing_getter,
            setter: Some(setter),
            is_accessor: true,
          }
          data.bag.properties[prop] = Undefined
        }
        _ => ()
      }
      Undefined
    },
  )
  obj_proto_props["__lookupGetter__"] = @runtime.make_interp_method_func(
    name="__lookupGetter__",
    length=1,
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
            match data.bag.descriptors.get(prop) {
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
    name="__lookupSetter__",
    length=1,
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
            match data.bag.descriptors.get(prop) {
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
  obj_proto_props["__proto__"] = Undefined
  let proto_getter = @runtime.make_interp_method_func(
    name="get __proto__",
    length=0,
    fn(interp, this_val, _args) raise {
      let this_obj = to_object(this_val, interp)
      match this_obj {
        Object(data) => data.prototype
        Array(data) => {
          match @runtime.get_array_prototype_override(data) {
            Some(proto) => proto
            None => interp.realm_state.get_array_proto()
          }
        }
        Proxy(proxy_data) => @runtime.proxy_get_prototype_of(interp, proxy_data)
        Value::String_(_) => @runtime.get_string_proto(
          realm_state=Some(interp.realm_state),
        )
        Value::Number(_) => @runtime.get_number_proto(
          realm_state=Some(interp.realm_state),
        )
        Bool(_) => @runtime.get_boolean_proto(
          realm_state=Some(interp.realm_state),
        )
        Symbol(_) => @runtime.get_symbol_proto(
          realm_state=Some(interp.realm_state),
        )
        Map(data) => {
          match data.prototype {
            Null => interp.realm_state.get_map_proto()
            proto => proto
          }
        }
        Set(data) => {
          match data.prototype {
            Null => interp.realm_state.get_set_proto()
            proto => proto
          }
        }
        Promise(_) => interp.realm_state.get_promise_proto()
        _ => interp.realm_state.get_obj_proto()
      }
    },
  )
  let proto_setter = @runtime.make_interp_method_func(
    name="set __proto__",
    length=1,
    fn(interp, this_val, args) raise {
      let this_obj = to_object(this_val, interp)
      let proto = if args.length() > 0 { args[0] } else { Null }
      match proto {
        Object(_) | Proxy(_) | Null => ()
        _ =>
          raise @errors.TypeError(
            message="Object prototype may only be an Object or null",
          )
      }
      match this_obj {
        Object(data) => {
          if !data.extensible {
            raise @errors.TypeError(
              message="Cannot set prototype of non-extensible object",
            )
          }
          data.prototype = proto
        }
        Array(data) => {
          @runtime.set_array_prototype_override(data, proto)
        }
        Value::Proxy(proxy_data) => {
          let success = @runtime.proxy_set_prototype_of(
            interp,
            proxy_data,
            proto,
          )
          if !success {
            raise @errors.TypeError(
              message="Cannot set prototype of non-extensible object",
            )
          }
        }
        _ => ()
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
    is_accessor: false,
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
  obj_proto_descs["__proto__"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(proto_getter),
    setter: Some(proto_setter),
    is_accessor: true,
  }
  let obj_proto : Value = Value::Object({
    bag: {
      properties: obj_proto_props,
      symbol_properties: {},
      descriptors: obj_proto_descs,
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  // Store Object.prototype so plain objects {} can link to it
  env.def_builtin("[[ObjectPrototype]]", obj_proto)
  realm_state.object_prototype.val = Some(obj_proto)
  env.def_builtin(
    "Object",
    Value::Object({
      bag: {
        properties: {
          "prototype": obj_proto,
          "name": Value::String_("Object"),
          "length": Value::Number(1.0),
          "keys": @runtime.make_interp_static_func(name="keys", length=1, fn(
            interp,
            args,
          ) raise {
            let obj = if args.length() > 0 { args[0] } else { Undefined }
            match obj {
              Null | Undefined =>
                raise @errors.TypeError(
                  message="Cannot convert undefined or null to object",
                )
              Value::Proxy(proxy_data) => {
                // Call [[OwnPropertyKeys]] via proxy trap, then filter to enumerable strings
                let all_keys = @runtime.proxy_own_property_keys(
                  interp, proxy_data,
                )
                let result : Array[Value] = []
                match all_keys {
                  Value::Array(arr) =>
                    for key in arr.elements {
                      match key {
                        Value::String_(_) => result.push(key)
                        _ => () // Object.keys only returns strings
                      }
                    }
                  _ => ()
                }
                @runtime.make_array(result)
              }
              Object(data) => {
                let keys : Array[Value] = []
                let sorted = @runtime.sort_property_keys(data.bag.properties)
                for k in sorted {
                  let enumerable = match data.bag.descriptors.get(k) {
                    Some(d) => d.enumerable
                    None => true
                  }
                  if enumerable {
                    keys.push(Value::String_(k))
                  }
                }
                @runtime.make_array(keys)
              }
              Value::String_(s) => {
                // String objects have enumerable indexed properties
                let keys : Array[Value] = []
                let len = s.length()
                for i = 0; i < len; i = i + 1 {
                  keys.push(Value::String_(i.to_string()))
                }
                @runtime.make_array(keys)
              }
              Value::Array(data) => {
                // Array objects have enumerable indexed properties followed by
                // enumerable own named properties in their embedded bag.
                let keys : Array[Value] = []
                for i = 0; i < data.elements.length(); i = i + 1 {
                  if data.holes.contains(i) {
                    continue
                  }
                  let key = i.to_string()
                  let enumerable = match data.bag.descriptors.get(key) {
                    Some(d) => d.enumerable
                    None => true
                  }
                  if enumerable {
                    keys.push(Value::String_(key))
                  }
                }
                let sorted = @runtime.sort_property_keys(data.bag.properties)
                for k in sorted {
                  if is_internal_array_bag_key(k) {
                    continue
                  }
                  let enumerable = match data.bag.descriptors.get(k) {
                    Some(d) => d.enumerable
                    None => true
                  }
                  if enumerable {
                    keys.push(Value::String_(k))
                  }
                }
                @runtime.make_array(keys)
              }
              _ => @runtime.make_array([])
            }
          }),
          "values": @runtime.make_interp_static_func(name="values", length=1, fn(
            interp,
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
                let sorted = @runtime.sort_property_keys(data.bag.properties)
                for k in sorted {
                  let enumerable = match data.bag.descriptors.get(k) {
                    Some(d) => d.enumerable
                    None => true
                  }
                  if enumerable {
                    match data.bag.properties.get(k) {
                      Some(v) => vals.push(v)
                      None => ()
                    }
                  }
                }
                @runtime.make_array(vals)
              }
              Value::String_(s) => {
                // String objects have enumerable indexed properties
                let vals : Array[Value] = []
                let chars = s.to_array()
                for ch in chars {
                  vals.push(Value::String_(ch.to_string()))
                }
                @runtime.make_array(vals)
              }
              Value::Array(data) => {
                // Array objects - return array elements, then enumerable own
                // named properties from the embedded bag.
                let loc = @token.Loc::default()
                let vals : Array[Value] = []
                for i = 0; i < data.elements.length(); i = i + 1 {
                  if data.holes.contains(i) {
                    continue
                  }
                  let key = i.to_string()
                  match data.bag.descriptors.get(key) {
                    Some({ enumerable: false, .. }) => ()
                    Some({ getter: Some(g), .. }) =>
                      vals.push(interp.call_value(g, obj, [], loc))
                    _ => vals.push(data.elements[i])
                  }
                }
                let sorted = @runtime.sort_property_keys(data.bag.properties)
                for k in sorted {
                  if is_internal_array_bag_key(k) {
                    continue
                  }
                  let enumerable = match data.bag.descriptors.get(k) {
                    Some(d) => d.enumerable
                    None => true
                  }
                  if enumerable {
                    match data.bag.properties.get(k) {
                      Some(v) => vals.push(v)
                      None => ()
                    }
                  }
                }
                @runtime.make_array(vals)
              }
              _ => @runtime.make_array([])
            }
          }),
          "entries": @runtime.make_interp_static_func(
            name="entries",
            length=1,
            fn(interp, args) raise {
              let obj = if args.length() > 0 { args[0] } else { Undefined }
              match obj {
                Null | Undefined =>
                  raise @errors.TypeError(
                    message="Cannot convert undefined or null to object",
                  )
                Object(data) => {
                  let entries : Array[Value] = []
                  let sorted = @runtime.sort_property_keys(data.bag.properties)
                  for k in sorted {
                    let enumerable = match data.bag.descriptors.get(k) {
                      Some(d) => d.enumerable
                      None => true
                    }
                    if enumerable {
                      match data.bag.properties.get(k) {
                        Some(v) =>
                          entries.push(
                            @runtime.make_array([Value::String_(k), v]),
                          )
                        None => ()
                      }
                    }
                  }
                  @runtime.make_array(entries)
                }
                Value::String_(s) => {
                  // String objects have enumerable indexed properties
                  let entries : Array[Value] = []
                  let chars = s.to_array()
                  for i = 0; i < chars.length(); i = i + 1 {
                    entries.push(
                      @runtime.make_array([
                        Value::String_(i.to_string()),
                        Value::String_(chars[i].to_string()),
                      ]),
                    )
                  }
                  @runtime.make_array(entries)
                }
                Value::Array(data) => {
                  // Array objects - keys must be strings per spec.
                  let loc = @token.Loc::default()
                  let entries : Array[Value] = []
                  for i = 0; i < data.elements.length(); i = i + 1 {
                    if data.holes.contains(i) {
                      continue
                    }
                    let key = i.to_string()
                    match data.bag.descriptors.get(key) {
                      Some({ enumerable: false, .. }) => ()
                      Some({ getter: Some(g), .. }) =>
                        entries.push(
                          @runtime.make_array([
                            Value::String_(key),
                            interp.call_value(g, obj, [], loc),
                          ]),
                        )
                      _ =>
                        entries.push(
                          @runtime.make_array([
                            Value::String_(key),
                            data.elements[i],
                          ]),
                        )
                    }
                  }
                  let sorted = @runtime.sort_property_keys(data.bag.properties)
                  for k in sorted {
                    if is_internal_array_bag_key(k) {
                      continue
                    }
                    let enumerable = match data.bag.descriptors.get(k) {
                      Some(d) => d.enumerable
                      None => true
                    }
                    if enumerable {
                      match data.bag.properties.get(k) {
                        Some(v) =>
                          entries.push(
                            @runtime.make_array([Value::String_(k), v]),
                          )
                        None => ()
                      }
                    }
                  }
                  @runtime.make_array(entries)
                }
                _ => @runtime.make_array([])
              }
            },
          ),
          "create": @runtime.make_interp_static_func(name="create", length=2, fn(
            interp,
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
              bag: @runtime.PropertyBag(),
              prototype: proto,
              callable: None,
              class_name: "Object",
              extensible: true,
              arraybuffer_state: None,
            })
            // Handle optional second argument (property descriptors)
            if args.length() > 1 {
              match args[1] {
                Undefined => ()
                descs =>
                  define_properties_from_value(
                    interp,
                    obj,
                    descs,
                    sym_state,
                    @token.Loc::default(),
                  )
              }
            }
            obj
          }),
          "assign": @runtime.make_interp_static_func(name="assign", length=2, fn(
            interp,
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
                  bag: {
                    properties: { "[[NumberData]]": Value::Number(n) },
                    symbol_properties: {},
                    descriptors: {},
                    symbol_descriptors: {},
                  },
                  prototype: realm_state.get_number_proto(),
                  callable: None,
                  class_name: "Number",
                  extensible: true,
                  arraybuffer_state: None,
                })
              Value::Bool(b) =>
                Value::Object({
                  bag: {
                    properties: { "[[BooleanData]]": Value::Bool(b) },
                    symbol_properties: {},
                    descriptors: {},
                    symbol_descriptors: {},
                  },
                  prototype: realm_state.get_boolean_proto(),
                  callable: None,
                  class_name: "Boolean",
                  extensible: true,
                  arraybuffer_state: None,
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
                  is_accessor: false,
                }
                for i = 0; i < chars.length(); i = i + 1 {
                  descs[i.to_string()] = {
                    writable: false,
                    enumerable: true,
                    configurable: false,
                    getter: None,
                    setter: None,
                    is_accessor: false,
                  }
                }
                Value::Object({
                  bag: {
                    properties: props,
                    symbol_properties: {},
                    descriptors: descs,
                    symbol_descriptors: {},
                  },
                  prototype: realm_state.get_string_proto(),
                  callable: None,
                  class_name: "String",
                  extensible: true,
                  arraybuffer_state: None,
                })
              }
              Symbol(_) =>
                Value::Object({
                  bag: {
                    properties: { "[[SymbolData]]": raw_target },
                    symbol_properties: {},
                    descriptors: {},
                    symbol_descriptors: {},
                  },
                  prototype: realm_state.get_symbol_proto(),
                  callable: None,
                  class_name: "Symbol",
                  extensible: true,
                  arraybuffer_state: None,
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
                        let can_write = match data.bag.descriptors.get(k) {
                          Some(d) => d.writable
                          None => true
                        }
                        let exists = data.bag.properties.contains(k)
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
                        data.bag.properties[k] = v
                      }
                    }
                    // ToObject conversion: Arrays enumerate elements as indexed properties
                    Array(src) => {
                      // Copy array elements as indexed properties
                      let loc = @token.Loc::default()
                      for idx = 0; idx < src.elements.length(); idx = idx + 1 {
                        if src.holes.contains(idx) {
                          continue
                        }
                        let k = idx.to_string()
                        let v = match src.bag.descriptors.get(k) {
                          Some({ enumerable: false, .. }) => continue
                          Some({ getter: Some(g), .. }) =>
                            interp.call_value(g, args[i], [], loc)
                          _ => src.elements[idx]
                        }
                        let can_write = match data.bag.descriptors.get(k) {
                          Some(d) => d.writable
                          None => true
                        }
                        let exists = data.bag.properties.contains(k)
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
                        data.bag.properties[k] = v
                      }
                    }
                    // Regular objects have properties and descriptors
                    Object(src) => {
                      // Copy enumerable string properties
                      let loc = @token.Loc::default()
                      src.bag.properties.each(fn(k, v) raise {
                        let enumerable = match src.bag.descriptors.get(k) {
                          Some(d) => d.enumerable
                          None => true
                        }
                        if enumerable {
                          let _ = interp.set_property(
                            target,
                            k,
                            v,
                            loc,
                            strict=true,
                          )
                        }
                      })
                      // Copy enumerable symbol properties
                      src.bag.symbol_properties.each(fn(sym_id, v) raise {
                        let enumerable = match
                          src.bag.symbol_descriptors.get(sym_id) {
                          Some(d) => d.enumerable
                          None => true
                        }
                        if enumerable {
                          // Check writable on target property
                          let can_write = match
                            data.bag.symbol_descriptors.get(sym_id) {
                            Some(d) => d.writable
                            None => true
                          }
                          // Check extensibility if property doesn't exist
                          let exists = data.bag.symbol_properties.contains(
                            sym_id,
                          )
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
                          data.bag.symbol_properties[sym_id] = v
                        }
                      })
                    }
                    // Promises have properties but no descriptors
                    Promise(src) => {
                      // Copy all string properties (no descriptors to check)
                      src.bag.properties.each(fn(k, v) raise {
                        let can_write = match data.bag.descriptors.get(k) {
                          Some(d) => d.writable
                          None => true
                        }
                        let exists = data.bag.properties.contains(k)
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
                        data.bag.properties[k] = v
                      })
                      // Copy symbol properties
                      src.bag.symbol_properties.each(fn(sym_id, v) raise {
                        let can_write = match
                          data.bag.symbol_descriptors.get(sym_id) {
                          Some(d) => d.writable
                          None => true
                        }
                        let exists = data.bag.symbol_properties.contains(sym_id)
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
                        data.bag.symbol_properties[sym_id] = v
                      })
                    }
                    // Proxy sources: unwrap to target and copy enumerable properties
                    Value::Proxy(proxy_data) =>
                      match proxy_data.target {
                        Some(target) =>
                          match target {
                            Object(src) => {
                              src.bag.properties.each(fn(k, v) raise {
                                let enumerable = match
                                  src.bag.descriptors.get(k) {
                                  Some(d) => d.enumerable
                                  None => true
                                }
                                if enumerable {
                                  let can_write = match
                                    data.bag.descriptors.get(k) {
                                    Some(d) => d.writable
                                    None => true
                                  }
                                  let exists = data.bag.properties.contains(k)
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
                                  data.bag.properties[k] = v
                                }
                              })
                              // Copy enumerable symbol properties from Proxy target
                              src.bag.symbol_properties.each(fn(
                                sym_id,
                                v,
                              ) raise {
                                let enumerable = match
                                  src.bag.symbol_descriptors.get(sym_id) {
                                  Some(d) => d.enumerable
                                  None => true
                                }
                                if enumerable {
                                  let can_write = match
                                    data.bag.symbol_descriptors.get(sym_id) {
                                    Some(d) => d.writable
                                    None => true
                                  }
                                  let exists = data.bag.symbol_properties.contains(
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
                                  data.bag.symbol_properties[sym_id] = v
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
                    Map(_) | Set(_) | Value::Number(_) | Bool(_) | Symbol(_) =>
                      ()
                  }
                }
                target
              }
              _ => target
            }
          }),
          "getPrototypeOf": @runtime.make_interp_static_func(
            name="getPrototypeOf",
            length=1,
            fn(interp, args) raise {
              let obj = if args.length() > 0 { args[0] } else { Undefined }
              match obj {
                Null | Undefined =>
                  raise @errors.TypeError(
                    message="Cannot convert undefined or null to object",
                  )
                Object(data) => data.prototype
                Array(data) =>
                  match @runtime.get_array_prototype_override(data) {
                    Some(proto) => proto
                    None => interp.realm_state.get_array_proto()
                  }
                Value::String_(_) =>
                  @runtime.get_string_proto(
                    realm_state=Some(interp.realm_state),
                  )
                Value::Number(_) =>
                  @runtime.get_number_proto(
                    realm_state=Some(interp.realm_state),
                  )
                Bool(_) =>
                  @runtime.get_boolean_proto(
                    realm_state=Some(interp.realm_state),
                  )
                Symbol(_) =>
                  @runtime.get_symbol_proto(
                    realm_state=Some(interp.realm_state),
                  )
                Map(data) =>
                  match data.prototype {
                    Null => interp.realm_state.get_map_proto()
                    proto => proto
                  }
                Set(data) =>
                  match data.prototype {
                    Null => interp.realm_state.get_set_proto()
                    proto => proto
                  }
                Promise(_) => interp.realm_state.get_promise_proto()
                Value::Proxy(proxy_data) =>
                  @runtime.proxy_get_prototype_of(interp, proxy_data)
              }
            },
          ),
          "getOwnPropertyNames": make_get_own_property_names_func(),
          "getOwnPropertySymbols": make_get_own_property_symbols_func(sym_state),
          "getOwnPropertyDescriptors": make_get_own_property_descriptors_func(
            sym_state,
          ),
          "defineProperty": make_define_property_func(),
          "getOwnPropertyDescriptor": make_get_own_property_descriptor_func(),
          "freeze": make_freeze_func(),
          "seal": make_seal_func(),
          "preventExtensions": make_prevent_extensions_func(),
          "isFrozen": make_is_frozen_func(),
          "isSealed": make_is_sealed_func(),
          "isExtensible": make_is_extensible_func(),
          "is": make_is_func(),
          "fromEntries": make_from_entries_func(realm_state),
          "groupBy": make_group_by_func(),
          "hasOwn": make_has_own_func(),
          "setPrototypeOf": @runtime.make_interp_static_func(
            name="setPrototypeOf",
            length=2,
            fn(interp, args) raise {
              // Object.setPrototypeOf(obj, prototype)
              let obj = if args.length() > 0 { args[0] } else { Undefined }
              let proto = if args.length() > 1 { args[1] } else { Null }
              // §20.1.2.24 step 1: RequireObjectCoercible(O) — null/undefined throw
              match obj {
                Null | Undefined =>
                  raise @errors.TypeError(
                    message="Object.setPrototypeOf called on null or undefined",
                  )
                _ => ()
              }
              match proto {
                Object(_) | Proxy(_) | Null => ()
                _ =>
                  raise @errors.TypeError(
                    message="Object prototype may only be an Object or null",
                  )
              }
              match obj {
                Value::Proxy(proxy_data) => {
                  let success = @runtime.proxy_set_prototype_of(
                    interp, proxy_data, proto,
                  )
                  if !success {
                    raise @errors.TypeError(
                      message="Cannot set prototype of non-extensible object",
                    )
                  }
                }
                Object(data) => {
                  if !data.extensible {
                    raise @errors.TypeError(
                      message="Cannot set prototype of non-extensible object",
                    )
                  }
                  data.prototype = proto
                }
                Array(data) =>
                  @runtime.set_array_prototype_override(data, proto)
                _ => ()
              }
              obj
            },
          ),
          "defineProperties": make_define_properties_func(sym_state),
        },
        symbol_properties: {},
        descriptors: {
          "name": nf_desc,
          "length": nf_desc,
          "prototype": {
            writable: false,
            enumerable: false,
            configurable: false,
            getter: None,
            setter: None,
            is_accessor: false,
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
      },
      prototype: Null,
      callable: Some(
        NativeCallable("Object", fn(args) {
          let val = if args.length() > 0 { args[0] } else { Undefined }
          match val {
            Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) =>
              val
            Undefined | Null =>
              Value::Object({
                bag: @runtime.PropertyBag(),
                prototype: obj_proto,
                callable: None,
                class_name: "Object",
                extensible: true,
                arraybuffer_state: None,
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
                props[i.to_string()] = Value::String_(s[i:i + 1].to_owned())
              }
              let descs : Map[String, PropDescriptor] = {}
              descs["length"] = {
                writable: false,
                enumerable: false,
                configurable: false,
                getter: None,
                setter: None,
                is_accessor: false,
              }
              for i = 0; i < s.length(); i = i + 1 {
                descs[i.to_string()] = {
                  writable: false,
                  enumerable: true,
                  configurable: false,
                  getter: None,
                  setter: None,
                  is_accessor: false,
                }
              }
              Value::Object({
                bag: {
                  properties: props,
                  symbol_properties: {},
                  descriptors: descs,
                  symbol_descriptors: {},
                },
                prototype: string_proto,
                callable: None,
                class_name: "String",
                extensible: true,
                arraybuffer_state: None,
              })
            }
            Value::Number(n) => {
              // ToObject: wrap number as boxed Number object
              let number_proto = env.get("[[NumberPrototype]]") catch {
                _ => Null
              }
              Value::Object({
                bag: {
                  properties: { "[[NumberData]]": Value::Number(n) },
                  symbol_properties: {},
                  descriptors: {},
                  symbol_descriptors: {},
                },
                prototype: number_proto,
                callable: None,
                class_name: "Number",
                extensible: true,
                arraybuffer_state: None,
              })
            }
            Value::Bool(b) => {
              // ToObject: wrap boolean as boxed Boolean object
              let boolean_proto = env.get("[[BooleanPrototype]]") catch {
                _ => Null
              }
              Value::Object({
                bag: {
                  properties: { "[[BooleanData]]": Value::Bool(b) },
                  symbol_properties: {},
                  descriptors: {},
                  symbol_descriptors: {},
                },
                prototype: boolean_proto,
                callable: None,
                class_name: "Boolean",
                extensible: true,
                arraybuffer_state: None,
              })
            }
            Symbol(_) => {
              // ToObject: wrap symbol as boxed Symbol object
              let symbol_proto = env.get("[[SymbolPrototype]]") catch {
                _ => Null
              }
              Value::Object({
                bag: {
                  properties: { "[[SymbolData]]": val },
                  symbol_properties: {},
                  descriptors: {},
                  symbol_descriptors: {},
                },
                prototype: symbol_proto,
                callable: None,
                class_name: "Symbol",
                extensible: true,
                arraybuffer_state: None,
              })
            }
          }
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
  )

  // Set Object.prototype.constructor = Object
  match obj_proto {
    Object(data) => {
      let obj_ctor = env.get("Object") catch { _ => Undefined }
      data.bag.properties["constructor"] = obj_ctor
      data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }

  setup_array_builtins(env, realm_state, nf_desc, obj_proto, obj_method_desc)
}

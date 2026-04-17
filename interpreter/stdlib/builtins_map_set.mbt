///|
/// Map and Set built-in implementations
///
/// This module provides ES6 Map and Set collections with:
/// - SameValueZero equality for keys/values (NaN === NaN, +0 === -0)
/// - Insertion order preservation
/// - Iterator protocol support
/// - Standard methods (get/set/has/delete/clear for Map, add/has/delete/clear for Set)

///|
/// Global storage for Map prototype
let map_prototype_ref : Ref[Value?] = { val: None }

///|
/// Global storage for Set prototype
let set_prototype_ref : Ref[Value?] = { val: None }

///|
/// Get Map.prototype methods for a Map instance
pub fn get_map_method(_data : MapData, prop : String) -> Value {
  match map_prototype_ref.val {
    Some(proto) =>
      match proto {
        Object(proto_data) =>
          match proto_data.bag.properties.get(prop) {
            Some(m) => m
            None => Undefined
          }
        _ => Undefined
      }
    None => Undefined
  }
}

///|
/// Get Set.prototype methods for a Set instance
pub fn get_set_method(_data : SetData, prop : String) -> Value {
  match set_prototype_ref.val {
    Some(proto) =>
      match proto {
        Object(proto_data) =>
          match proto_data.bag.properties.get(prop) {
            Some(m) => m
            None => Undefined
          }
        _ => Undefined
      }
    None => Undefined
  }
}

///|
/// Setup Map and Set constructors and prototypes
pub fn setup_map_set_builtins(env : Environment) -> Unit {
  setup_map_builtins(env)
  setup_set_builtins(env)
}

///|
/// Setup Map constructor and prototype
fn setup_map_builtins(env : Environment) -> Unit {
  let iterator_sym = @runtime.get_iterator_symbol()

  // Map.prototype methods
  let map_proto_props : Map[String, Value] = {}

  // Map.prototype.get(key)
  map_proto_props["get"] = @runtime.make_method_func("get", 1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        // Find key using SameValueZero
        for i = 0; i < data.entries.length(); i = i + 1 {
          let (k, v) = data.entries[i]
          if same_value_zero(k, key) {
            return v
          }
        }
        Undefined
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.get called on incompatible receiver",
        )
    }
  })

  // Map.prototype.set(key, value)
  map_proto_props["set"] = @runtime.make_method_func("set", 2, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        let value = if args.length() > 1 { args[1] } else { Undefined }
        // Find existing key using SameValueZero
        for i = 0; i < data.entries.length(); i = i + 1 {
          let (k, _) = data.entries[i]
          if same_value_zero(k, key) {
            // Update existing entry
            data.entries[i] = (key, value)
            return this_val
          }
        }
        // Add new entry
        data.entries.push((key, value))
        this_val
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.set called on incompatible receiver",
        )
    }
  })

  // Map.prototype.has(key)
  map_proto_props["has"] = @runtime.make_method_func("has", 1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        // Find key using SameValueZero
        for i = 0; i < data.entries.length(); i = i + 1 {
          let (k, _) = data.entries[i]
          if same_value_zero(k, key) {
            return Value::Bool(true)
          }
        }
        Value::Bool(false)
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.has called on incompatible receiver",
        )
    }
  })

  // Map.prototype.delete(key)
  map_proto_props["delete"] = @runtime.make_method_func("delete", 1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        // Find and remove key using SameValueZero
        for i = 0; i < data.entries.length(); i = i + 1 {
          let (k, _) = data.entries[i]
          if same_value_zero(k, key) {
            let _ = data.entries.remove(i)
            return Value::Bool(true)
          }
        }
        Value::Bool(false)
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.delete called on incompatible receiver",
        )
    }
  })

  // Map.prototype.clear()
  map_proto_props["clear"] = @runtime.make_method_func("clear", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        data.entries.clear()
        Undefined
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.clear called on incompatible receiver",
        )
    }
  })

  // Map.prototype.forEach(callback, thisArg?)
  map_proto_props["forEach"] = @runtime.make_interp_method_func("forEach", 1, fn(
    interp,
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        // Iterate over entries
        for i = 0; i < data.entries.length(); i = i + 1 {
          let (key, value) = data.entries[i]
          // Call callback(value, key, map)
          let _ = interp.call_value(
            callback,
            this_arg,
            [value, key, this_val],
            loc,
          )
        }
        Undefined
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.forEach called on incompatible receiver",
        )
    }
  })

  // Map.prototype.keys() - returns iterator of keys
  map_proto_props["keys"] = @runtime.make_method_func("keys", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Map(data) => make_map_keys_iterator(data)
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.keys called on incompatible receiver",
        )
    }
  })

  // Map.prototype.values() - returns iterator of values
  map_proto_props["values"] = @runtime.make_method_func("values", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Map(data) => make_map_values_iterator(data)
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.values called on incompatible receiver",
        )
    }
  })

  // Map.prototype.entries() - returns iterator of [key, value] pairs
  map_proto_props["entries"] = @runtime.make_method_func("entries", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Map(data) => make_map_entries_iterator(data)
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.entries called on incompatible receiver",
        )
    }
  })

  // Map.prototype.getOrInsert(key, value)
  map_proto_props["getOrInsert"] = @runtime.make_method_func("getOrInsert", 2, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        let value = if args.length() > 1 { args[1] } else { Undefined }
        // If key exists, return existing value
        for i = 0; i < data.entries.length(); i = i + 1 {
          let (k, v) = data.entries[i]
          if same_value_zero(k, key) {
            return v
          }
        }
        // Key not found, insert and return value
        data.entries.push((key, value))
        value
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.getOrInsert called on incompatible receiver",
        )
    }
  })

  // Map.prototype.getOrInsertComputed(key, callbackfn)
  map_proto_props["getOrInsertComputed"] = @runtime.make_interp_method_func(
    "getOrInsertComputed",
    2,
    fn(interp, this_val, args) raise {
      match this_val {
        Value::Map(data) => {
          let key = if args.length() > 0 { args[0] } else { Undefined }
          let callbackfn = if args.length() > 1 { args[1] } else { Undefined }
          // If key exists, return existing value without calling callback
          for i = 0; i < data.entries.length(); i = i + 1 {
            let (k, v) = data.entries[i]
            if same_value_zero(k, key) {
              return v
            }
          }
          // Key not found, call callback to get value
          let loc = @token.Loc::default()
          let value = interp.call_value(callbackfn, Undefined, [key], loc)
          // Re-check if key was added by callback (mutation during callback)
          for i = 0; i < data.entries.length(); i = i + 1 {
            let (k, _) = data.entries[i]
            if same_value_zero(k, key) {
              // Overwrite with computed value per spec
              data.entries[i] = (key, value)
              return value
            }
          }
          data.entries.push((key, value))
          value
        }
        _ =>
          raise @errors.TypeError(
            message="Method Map.prototype.getOrInsertComputed called on incompatible receiver",
          )
      }
    },
  )

  // Non-enumerable descriptors for Map.prototype methods
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let map_proto_descs : Map[String, PropDescriptor] = {}
  map_proto_descs["get"] = method_desc
  map_proto_descs["set"] = method_desc
  map_proto_descs["has"] = method_desc
  map_proto_descs["delete"] = method_desc
  map_proto_descs["clear"] = method_desc
  map_proto_descs["forEach"] = method_desc
  map_proto_descs["keys"] = method_desc
  map_proto_descs["values"] = method_desc
  map_proto_descs["entries"] = method_desc
  map_proto_descs["getOrInsert"] = method_desc
  map_proto_descs["getOrInsertComputed"] = method_desc

  // Create size getter for Map.prototype (per spec, size is an accessor property)
  let size_getter = @runtime.make_method_func("get size", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Map(data) => Value::Number(data.entries.length().to_double())
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.size called on incompatible receiver",
        )
    }
  })
  map_proto_descs["size"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(size_getter),
    setter: None,
  }

  let map_proto : Value = Value::Object({
    bag: {
      properties: map_proto_props,
      symbol_properties: {},
      descriptors: map_proto_descs,
      symbol_descriptors: {},
    },
    prototype: @runtime.get_obj_proto(),
    callable: None,
    class_name: "Map",
    extensible: true,
  })

  // Store Map prototype globally for get_map_method access
  map_prototype_ref.val = Some(map_proto)

  // Add Map.prototype[Symbol.iterator] = Map.prototype.entries
  match map_proto {
    Object(data) => {
      data.bag.symbol_properties[iterator_sym.id] = map_proto_props["entries"]
      data.bag.symbol_descriptors[iterator_sym.id] = method_desc
      // Add Symbol.toStringTag = "Map"
      let tostringtag_sym = @runtime.get_tostringtag_symbol()
      data.bag.symbol_properties[tostringtag_sym.id] = Value::String_("Map")
      data.bag.symbol_descriptors[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }

  // Map constructor
  let map_ctor = @runtime.make_interp_method_func("Map", 0, fn(
    interp,
    _this_val,
    args,
  ) raise {
    if !@runtime.is_constructing.val {
      raise @errors.TypeError(
        message="Constructor Map cannot be invoked without 'new'",
      )
    }
    let new_map : Value = Value::Map(@runtime.make_map_data([]))
    let loc = @token.Loc::default()

    // If iterable provided, populate map
    if args.length() > 0 {
      let iterable = args[0]
      if !(match iterable {
          Undefined | Null => true
          _ => false
        }) {
        // Get iterator from iterable using Symbol.iterator
        let iterator_sym = @runtime.get_iterator_symbol()
        let iterator_method = interp.get_computed_property(
          iterable,
          Symbol(iterator_sym),
          loc,
        )
        let iterator = match iterator_method {
          Object(data) =>
            match data.callable {
              Some(_) => interp.call_value(iterator_method, iterable, [], loc)
              None =>
                raise @errors.TypeError(
                  message="Result of the Symbol.iterator method is not an object",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="\{@runtime.type_of(iterable)} is not iterable",
            )
        }

        // Iterate over the iterator
        while true {
          let next_method = interp.get_property(iterator, "next", loc)
          let result = interp.call_value(next_method, iterator, [], loc)
          let done = match interp.get_property(result, "done", loc) {
            Value::Bool(b) => b
            _ => false
          }
          if done {
            break
          }
          let value = interp.get_property(result, "value", loc)
          // Value should be [key, value] pair or array-like with '0' and '1' properties
          // Try to get key and value from the entry
          let key = interp.get_computed_property(value, Value::Number(0.0), loc)
          let val = interp.get_computed_property(value, Value::Number(1.0), loc)

          // Add to map using same SameValueZero upsert logic as Map.prototype.set
          match new_map {
            Value::Map(data) => {
              // Find existing key using SameValueZero
              let mut found = false
              for i = 0; i < data.entries.length(); i = i + 1 {
                let (k, _) = data.entries[i]
                if same_value_zero(k, key) {
                  // Update existing entry
                  data.entries[i] = (key, val)
                  found = true
                  break
                }
              }
              if !found {
                // Add new entry
                data.entries.push((key, val))
              }
            }
            _ => ()
          }
        }
      }
    }
    new_map
  })
  // Add prototype property to Map constructor
  match map_ctor {
    Object(data) => {
      data.bag.properties["prototype"] = map_proto
      data.bag.descriptors["prototype"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  // Add Map.groupBy static method
  match map_ctor {
    Object(ctor_data) => {
      ctor_data.bag.properties["groupBy"] = @runtime.make_interp_static_func_with_length(
        "groupBy",
        2,
        fn(interp, args) raise {
          // Map.groupBy(items, callbackFn)
          let items = if args.length() > 0 { args[0] } else { Undefined }
          let callback = if args.length() > 1 { args[1] } else { Undefined }
          if !@runtime.is_callable(callback) {
            raise @errors.TypeError(
              message=@runtime.to_js_string(callback) + " is not a function",
            )
          }
          let loc = @token.Loc::default()
          let o = to_object(items, interp)
          let len = @runtime.to_array_like_length_interp(o, interp)
          let group_keys : Array[Value] = []
          let group_arrays : Array[Array[Value]] = []
          for k = 0; k < len; k = k + 1 {
            let kvalue = @runtime.get_array_like_element_interp(interp, o, k)
            let key = interp.call_value(
              callback,
              Undefined,
              [kvalue, Value::Number(k.to_double())],
              loc,
            )
            // Find existing group
            let mut found_idx = -1
            for i = 0; i < group_keys.length(); i = i + 1 {
              if same_value_zero(group_keys[i], key) {
                found_idx = i
                break
              }
            }
            if found_idx >= 0 {
              group_arrays[found_idx].push(kvalue)
            } else {
              group_keys.push(key)
              group_arrays.push([kvalue])
            }
          }
          // Build result Map
          let entries : Array[(Value, Value)] = []
          for i = 0; i < group_keys.length(); i = i + 1 {
            entries.push((group_keys[i], @runtime.make_array(group_arrays[i])))
          }
          Value::Map(@runtime.make_map_data(entries))
        },
      )
      ctor_data.bag.descriptors["groupBy"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  env.def_builtin("Map", map_ctor)
  // Set Map.prototype.constructor = Map
  match map_proto {
    Object(data) => {
      data.bag.properties["constructor"] = map_ctor
      data.bag.descriptors["constructor"] = {
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
/// Setup Set constructor and prototype
fn setup_set_builtins(env : Environment) -> Unit {
  let iterator_sym = @runtime.get_iterator_symbol()

  // Set.prototype methods
  let set_proto_props : Map[String, Value] = {}

  // Set.prototype.add(value)
  set_proto_props["add"] = @runtime.make_method_func("add", 1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Set(data) => {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        // Check if value already exists using SameValueZero
        for i = 0; i < data.values.length(); i = i + 1 {
          if same_value_zero(data.values[i], value) {
            return this_val
          }
        }
        // Add new value
        data.values.push(value)
        this_val
      }
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.add called on incompatible receiver",
        )
    }
  })

  // Set.prototype.has(value)
  set_proto_props["has"] = @runtime.make_method_func("has", 1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Set(data) => {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        // Find value using SameValueZero
        for i = 0; i < data.values.length(); i = i + 1 {
          if same_value_zero(data.values[i], value) {
            return Value::Bool(true)
          }
        }
        Value::Bool(false)
      }
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.has called on incompatible receiver",
        )
    }
  })

  // Set.prototype.delete(value)
  set_proto_props["delete"] = @runtime.make_method_func("delete", 1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Set(data) => {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        // Find and remove value using SameValueZero
        for i = 0; i < data.values.length(); i = i + 1 {
          if same_value_zero(data.values[i], value) {
            let _ = data.values.remove(i)
            return Value::Bool(true)
          }
        }
        Value::Bool(false)
      }
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.delete called on incompatible receiver",
        )
    }
  })

  // Set.prototype.clear()
  set_proto_props["clear"] = @runtime.make_method_func("clear", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Set(data) => {
        data.values.clear()
        Undefined
      }
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.clear called on incompatible receiver",
        )
    }
  })

  // Set.prototype.forEach(callback, thisArg?)
  set_proto_props["forEach"] = @runtime.make_interp_method_func("forEach", 1, fn(
    interp,
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Set(data) => {
        let callback = if args.length() > 0 { args[0] } else { Undefined }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let loc = @token.Loc::default()
        // Iterate over values
        for i = 0; i < data.values.length(); i = i + 1 {
          let value = data.values[i]
          // Call callback(value, value, set) - note: Set forEach passes value twice
          let _ = interp.call_value(
            callback,
            this_arg,
            [value, value, this_val],
            loc,
          )
        }
        Undefined
      }
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.forEach called on incompatible receiver",
        )
    }
  })

  // Set.prototype.keys() - returns iterator of values (same as values())
  set_proto_props["keys"] = @runtime.make_method_func("keys", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Set(data) => make_set_values_iterator(data)
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.keys called on incompatible receiver",
        )
    }
  })

  // Set.prototype.values() - returns iterator of values
  set_proto_props["values"] = @runtime.make_method_func("values", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Set(data) => make_set_values_iterator(data)
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.values called on incompatible receiver",
        )
    }
  })

  // Set.prototype.entries() - returns iterator of [value, value] pairs
  set_proto_props["entries"] = @runtime.make_method_func("entries", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Set(data) => make_set_entries_iterator(data)
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.entries called on incompatible receiver",
        )
    }
  })

  // Non-enumerable descriptors for Set.prototype methods
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let set_proto_descs : Map[String, PropDescriptor] = {}
  set_proto_descs["add"] = method_desc
  set_proto_descs["has"] = method_desc
  set_proto_descs["delete"] = method_desc
  set_proto_descs["clear"] = method_desc
  set_proto_descs["forEach"] = method_desc
  set_proto_descs["keys"] = method_desc
  set_proto_descs["values"] = method_desc
  set_proto_descs["entries"] = method_desc

  // Create size getter for Set.prototype (per spec, size is an accessor property)
  let set_size_getter = @runtime.make_method_func("get size", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Set(data) => Value::Number(data.values.length().to_double())
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.size called on incompatible receiver",
        )
    }
  })
  set_proto_descs["size"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(set_size_getter),
    setter: None,
  }

  let set_proto : Value = Value::Object({
    bag: {
      properties: set_proto_props,
      symbol_properties: {},
      descriptors: set_proto_descs,
      symbol_descriptors: {},
    },
    prototype: @runtime.get_obj_proto(),
    callable: None,
    class_name: "Set",
    extensible: true,
  })

  // Store Set prototype globally for get_set_method access
  set_prototype_ref.val = Some(set_proto)

  // Add Set.prototype[Symbol.iterator] = Set.prototype.values
  match set_proto {
    Object(data) => {
      data.bag.symbol_properties[iterator_sym.id] = set_proto_props["values"]
      data.bag.symbol_descriptors[iterator_sym.id] = method_desc
      // Add Symbol.toStringTag = "Set"
      let tostringtag_sym = @runtime.get_tostringtag_symbol()
      data.bag.symbol_properties[tostringtag_sym.id] = Value::String_("Set")
      data.bag.symbol_descriptors[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }

  // Set constructor
  let set_ctor = @runtime.make_interp_method_func("Set", 0, fn(
    interp,
    _this_val,
    args,
  ) raise {
    if !@runtime.is_constructing.val {
      raise @errors.TypeError(
        message="Constructor Set cannot be invoked without 'new'",
      )
    }
    let new_set : Value = Value::Set(@runtime.make_set_data([]))
    let loc = @token.Loc::default()

    // If iterable provided, populate set
    if args.length() > 0 {
      let iterable = args[0]
      if !(match iterable {
          Undefined | Null => true
          _ => false
        }) {
        // Get iterator from iterable using Symbol.iterator
        let iterator_sym = @runtime.get_iterator_symbol()
        let iterator_method = interp.get_computed_property(
          iterable,
          Symbol(iterator_sym),
          loc,
        )
        let iterator = match iterator_method {
          Object(data) =>
            match data.callable {
              Some(_) => interp.call_value(iterator_method, iterable, [], loc)
              None =>
                raise @errors.TypeError(
                  message="Result of the Symbol.iterator method is not an object",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="\{@runtime.type_of(iterable)} is not iterable",
            )
        }

        // Iterate over the iterator
        while true {
          let next_method = interp.get_property(iterator, "next", loc)
          let result = interp.call_value(next_method, iterator, [], loc)
          let done = match interp.get_property(result, "done", loc) {
            Value::Bool(b) => b
            _ => false
          }
          if done {
            break
          }
          let value = interp.get_property(result, "value", loc)
          // Add to set (using SameValueZero)
          match new_set {
            Value::Set(data) => {
              let mut found = false
              for i = 0; i < data.values.length(); i = i + 1 {
                if same_value_zero(data.values[i], value) {
                  found = true
                  break
                }
              }
              if !found {
                data.values.push(value)
              }
            }
            _ => ()
          }
        }
      }
    }
    new_set
  })
  // Add prototype property to Set constructor
  match set_ctor {
    Object(data) => {
      data.bag.properties["prototype"] = set_proto
      data.bag.descriptors["prototype"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  env.def_builtin("Set", set_ctor)
  // Set Set.prototype.constructor = Set
  match set_proto {
    Object(data) => {
      data.bag.properties["constructor"] = set_ctor
      data.bag.descriptors["constructor"] = {
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
/// Shared %MapIteratorPrototype% - lazily initialized
let map_iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %MapIteratorPrototype%
fn get_map_iterator_proto() -> Value {
  match map_iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = @runtime.get_iterator_symbol()
      let tostringtag_sym = @runtime.get_tostringtag_symbol()
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[tostringtag_sym.id] = Value::String_("Map Iterator")
      let proto_props : Map[String, Value] = {}
      let proto_sym_descs : Map[Int, PropDescriptor] = {}
      proto_sym_descs[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      // Add [Symbol.iterator] that returns the iterator itself
      proto_sym_props[iterator_sym.id] = @runtime.make_method_func(
        "[Symbol.iterator]",
        0,
        fn(this_val, _args) { this_val },
      )
      // Add a placeholder next method with correct name/length on prototype
      proto_props["next"] = @runtime.make_method_func("next", 0, fn(
        _this_val,
        _args,
      ) raise {
        raise @errors.TypeError(
          message="Map Iterator.prototype.next requires that |this| be a Map Iterator",
        )
      })
      let proto = Value::Object({
        bag: {
          properties: proto_props,
          symbol_properties: proto_sym_props,
          descriptors: {
            "next": {
              writable: true,
              enumerable: false,
              configurable: true,
              getter: None,
              setter: None,
            },
          },
          symbol_descriptors: proto_sym_descs,
        },
        prototype: @runtime.get_iterator_proto(),
        callable: None,
        class_name: "Map Iterator",
        extensible: true,
      })
      map_iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Create a Map keys iterator
fn make_map_keys_iterator(map_data : MapData) -> Value {
  let map_iter_proto = get_map_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Value::Object({
    bag: {
      properties: {
        "length": Value::Number(0.0),
        "name": Value::String_("next"),
      },
      symbol_properties: {},
      descriptors: {
        "length": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < map_data.entries.length() {
          let (key, _) = map_data.entries[idx]
          index_ref.val = idx + 1
          let result_props : Map[String, Value] = {}
          result_props["value"] = key
          result_props["done"] = Value::Bool(false)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Value::Bool(true)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        }
      }),
    ),
    class_name: "Function",
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  Value::Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: map_iter_proto,
    callable: None,
    class_name: "Map Iterator",
    extensible: true,
  })
}

///|
/// Create a Map values iterator
fn make_map_values_iterator(map_data : MapData) -> Value {
  let map_iter_proto = get_map_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Value::Object({
    bag: {
      properties: {
        "length": Value::Number(0.0),
        "name": Value::String_("next"),
      },
      symbol_properties: {},
      descriptors: {
        "length": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < map_data.entries.length() {
          let (_, value) = map_data.entries[idx]
          index_ref.val = idx + 1
          let result_props : Map[String, Value] = {}
          result_props["value"] = value
          result_props["done"] = Value::Bool(false)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Value::Bool(true)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        }
      }),
    ),
    class_name: "Function",
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  Value::Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: map_iter_proto,
    callable: None,
    class_name: "Map Iterator",
    extensible: true,
  })
}

///|
/// Create a Map entries iterator
fn make_map_entries_iterator(map_data : MapData) -> Value {
  let map_iter_proto = get_map_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Value::Object({
    bag: {
      properties: {
        "length": Value::Number(0.0),
        "name": Value::String_("next"),
      },
      symbol_properties: {},
      descriptors: {
        "length": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < map_data.entries.length() {
          let (key, value) = map_data.entries[idx]
          index_ref.val = idx + 1
          // Return [key, value] array
          let entry_array = @runtime.make_array([key, value])
          let result_props : Map[String, Value] = {}
          result_props["value"] = entry_array
          result_props["done"] = Value::Bool(false)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Value::Bool(true)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        }
      }),
    ),
    class_name: "Function",
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  Value::Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: map_iter_proto,
    callable: None,
    class_name: "Map Iterator",
    extensible: true,
  })
}

///|
/// Shared %SetIteratorPrototype% - lazily initialized
let set_iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %SetIteratorPrototype%
fn get_set_iterator_proto() -> Value {
  match set_iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = @runtime.get_iterator_symbol()
      let tostringtag_sym = @runtime.get_tostringtag_symbol()
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[tostringtag_sym.id] = Value::String_("Set Iterator")
      let proto_props : Map[String, Value] = {}
      let proto_sym_descs : Map[Int, PropDescriptor] = {}
      proto_sym_descs[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      proto_sym_props[iterator_sym.id] = @runtime.make_method_func(
        "[Symbol.iterator]",
        0,
        fn(this_val, _args) { this_val },
      )
      proto_props["next"] = @runtime.make_method_func("next", 0, fn(
        _this_val,
        _args,
      ) raise {
        raise @errors.TypeError(
          message="Set Iterator.prototype.next requires that |this| be a Set Iterator",
        )
      })
      let proto = Value::Object({
        bag: {
          properties: proto_props,
          symbol_properties: proto_sym_props,
          descriptors: {
            "next": {
              writable: true,
              enumerable: false,
              configurable: true,
              getter: None,
              setter: None,
            },
          },
          symbol_descriptors: proto_sym_descs,
        },
        prototype: @runtime.get_iterator_proto(),
        callable: None,
        class_name: "Set Iterator",
        extensible: true,
      })
      set_iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Create a Set values iterator
fn make_set_values_iterator(set_data : SetData) -> Value {
  let set_iter_proto = get_set_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Value::Object({
    bag: {
      properties: {
        "length": Value::Number(0.0),
        "name": Value::String_("next"),
      },
      symbol_properties: {},
      descriptors: {
        "length": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < set_data.values.length() {
          let value = set_data.values[idx]
          index_ref.val = idx + 1
          let result_props : Map[String, Value] = {}
          result_props["value"] = value
          result_props["done"] = Value::Bool(false)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Value::Bool(true)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        }
      }),
    ),
    class_name: "Function",
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  Value::Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: set_iter_proto,
    callable: None,
    class_name: "Set Iterator",
    extensible: true,
  })
}

///|
/// Create a Set entries iterator (returns [value, value] pairs)
fn make_set_entries_iterator(set_data : SetData) -> Value {
  let set_iter_proto = get_set_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Value::Object({
    bag: {
      properties: {
        "length": Value::Number(0.0),
        "name": Value::String_("next"),
      },
      symbol_properties: {},
      descriptors: {
        "length": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        },
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < set_data.values.length() {
          let value = set_data.values[idx]
          index_ref.val = idx + 1
          // Return [value, value] array (Set entries are [value, value] pairs)
          let entry_array = @runtime.make_array([value, value])
          let result_props : Map[String, Value] = {}
          result_props["value"] = entry_array
          result_props["done"] = Value::Bool(false)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Value::Bool(true)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
          })
        }
      }),
    ),
    class_name: "Function",
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  Value::Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: set_iter_proto,
    callable: None,
    class_name: "Set Iterator",
    extensible: true,
  })
}

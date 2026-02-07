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
          match proto_data.properties.get(prop) {
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
          match proto_data.properties.get(prop) {
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
  let iterator_sym = get_iterator_symbol()

  // Map.prototype methods
  let map_proto_props : Map[String, Value] = {}

  // Map.prototype.get(key)
  map_proto_props["get"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("get", fn(this_val, args) {
        match this_val {
          Map(data) => {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.set(key, value)
  map_proto_props["set"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("set", fn(this_val, args) {
        match this_val {
          Map(data) => {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.has(key)
  map_proto_props["has"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("has", fn(this_val, args) {
        match this_val {
          Map(data) => {
            let key = if args.length() > 0 { args[0] } else { Undefined }
            // Find key using SameValueZero
            for i = 0; i < data.entries.length(); i = i + 1 {
              let (k, _) = data.entries[i]
              if same_value_zero(k, key) {
                return Bool(true)
              }
            }
            Bool(false)
          }
          _ =>
            raise @errors.TypeError(
              message="Method Map.prototype.has called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.delete(key)
  map_proto_props["delete"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("delete", fn(this_val, args) {
        match this_val {
          Map(data) => {
            let key = if args.length() > 0 { args[0] } else { Undefined }
            // Find and remove key using SameValueZero
            for i = 0; i < data.entries.length(); i = i + 1 {
              let (k, _) = data.entries[i]
              if same_value_zero(k, key) {
                let _ = data.entries.remove(i)
                return Bool(true)
              }
            }
            Bool(false)
          }
          _ =>
            raise @errors.TypeError(
              message="Method Map.prototype.delete called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.clear()
  map_proto_props["clear"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("clear", fn(this_val, _args) {
        match this_val {
          Map(data) => {
            data.entries.clear()
            Undefined
          }
          _ =>
            raise @errors.TypeError(
              message="Method Map.prototype.clear called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.forEach(callback, thisArg?)
  map_proto_props["forEach"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("forEach", fn(interp, this_val, args) {
        match this_val {
          Map(data) => {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.keys() - returns iterator of keys
  map_proto_props["keys"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("keys", fn(this_val, _args) {
        match this_val {
          Map(data) => make_map_keys_iterator(data)
          _ =>
            raise @errors.TypeError(
              message="Method Map.prototype.keys called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.values() - returns iterator of values
  map_proto_props["values"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("values", fn(this_val, _args) {
        match this_val {
          Map(data) => make_map_values_iterator(data)
          _ =>
            raise @errors.TypeError(
              message="Method Map.prototype.values called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Map.prototype.entries() - returns iterator of [key, value] pairs
  map_proto_props["entries"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("entries", fn(this_val, _args) {
        match this_val {
          Map(data) => make_map_entries_iterator(data)
          _ =>
            raise @errors.TypeError(
              message="Method Map.prototype.entries called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Create Map prototype
  let map_proto : Value = Object({
    properties: map_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Map",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Store Map prototype globally for get_map_method access
  map_prototype_ref.val = Some(map_proto)

  // Add Map.prototype[Symbol.iterator] = Map.prototype.entries
  match map_proto {
    Object(data) =>
      data.symbol_properties[iterator_sym.id] = map_proto_props["entries"]
    _ => ()
  }

  // Add size getter to Map.prototype
  // Note: In full ES6, size is a getter. We simulate it by checking in get_property
  // For now, we'll add it as a special method that returns the size
  map_proto_props["size"] = Number(0.0) // Placeholder - will be handled specially

  // Map constructor
  let map_ctor = Object({
    properties: { "prototype": map_proto },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("Map", fn(interp, _this_val, args) {
        // Create new Map instance
        let new_map : Value = Map({ entries: [] })
        let loc = @token.Loc::default()

        // If iterable provided, populate map
        if args.length() > 0 {
          let iterable = args[0]
          if not(
              match iterable {
                Undefined | Null => true
                _ => false
              },
            ) {
            // Get iterator from iterable using Symbol.iterator
            let iterator_sym = get_iterator_symbol()
            let iterator_method = interp.get_computed_property(
              iterable,
              Symbol(iterator_sym),
              loc,
            )
            let iterator = match iterator_method {
              Object(data) =>
                match data.callable {
                  Some(_) =>
                    interp.call_value(iterator_method, iterable, [], loc)
                  None =>
                    raise @errors.TypeError(
                      message="Result of the Symbol.iterator method is not an object",
                    )
                }
              _ =>
                raise @errors.TypeError(
                  message="\{type_of(iterable)} is not iterable",
                )
            }

            // Iterate over the iterator
            while true {
              let next_method = interp.get_property(iterator, "next", loc)
              let result = interp.call_value(next_method, iterator, [], loc)
              let done = match interp.get_property(result, "done", loc) {
                Bool(b) => b
                _ => false
              }
              if done {
                break
              }
              let value = interp.get_property(result, "value", loc)
              // Value should be [key, value] pair or array-like with '0' and '1' properties
              // Try to get key and value from the entry
              let key = interp.get_computed_property(value, Number(0.0), loc)
              let val = interp.get_computed_property(value, Number(1.0), loc)

              // Add to map using same SameValueZero upsert logic as Map.prototype.set
              match new_map {
                Map(data) => {
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
                  if not(found) {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  env.def_builtin("Map", map_ctor)
  // Set Map.prototype.constructor = Map
  match map_proto {
    Object(data) => {
      data.properties["constructor"] = map_ctor
      data.descriptors["constructor"] = {
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
  let iterator_sym = get_iterator_symbol()

  // Set.prototype methods
  let set_proto_props : Map[String, Value] = {}

  // Set.prototype.add(value)
  set_proto_props["add"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("add", fn(this_val, args) {
        match this_val {
          Set(data) => {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set.prototype.has(value)
  set_proto_props["has"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("has", fn(this_val, args) {
        match this_val {
          Set(data) => {
            let value = if args.length() > 0 { args[0] } else { Undefined }
            // Find value using SameValueZero
            for i = 0; i < data.values.length(); i = i + 1 {
              if same_value_zero(data.values[i], value) {
                return Bool(true)
              }
            }
            Bool(false)
          }
          _ =>
            raise @errors.TypeError(
              message="Method Set.prototype.has called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set.prototype.delete(value)
  set_proto_props["delete"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("delete", fn(this_val, args) {
        match this_val {
          Set(data) => {
            let value = if args.length() > 0 { args[0] } else { Undefined }
            // Find and remove value using SameValueZero
            for i = 0; i < data.values.length(); i = i + 1 {
              if same_value_zero(data.values[i], value) {
                let _ = data.values.remove(i)
                return Bool(true)
              }
            }
            Bool(false)
          }
          _ =>
            raise @errors.TypeError(
              message="Method Set.prototype.delete called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set.prototype.clear()
  set_proto_props["clear"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("clear", fn(this_val, _args) {
        match this_val {
          Set(data) => {
            data.values.clear()
            Undefined
          }
          _ =>
            raise @errors.TypeError(
              message="Method Set.prototype.clear called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set.prototype.forEach(callback, thisArg?)
  set_proto_props["forEach"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("forEach", fn(interp, this_val, args) {
        match this_val {
          Set(data) => {
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set.prototype.keys() - returns iterator of values (same as values())
  set_proto_props["keys"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("keys", fn(this_val, _args) {
        match this_val {
          Set(data) => make_set_values_iterator(data)
          _ =>
            raise @errors.TypeError(
              message="Method Set.prototype.keys called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set.prototype.values() - returns iterator of values
  set_proto_props["values"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("values", fn(this_val, _args) {
        match this_val {
          Set(data) => make_set_values_iterator(data)
          _ =>
            raise @errors.TypeError(
              message="Method Set.prototype.values called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set.prototype.entries() - returns iterator of [value, value] pairs
  set_proto_props["entries"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("entries", fn(this_val, _args) {
        match this_val {
          Set(data) => make_set_entries_iterator(data)
          _ =>
            raise @errors.TypeError(
              message="Method Set.prototype.entries called on incompatible receiver",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Create Set prototype
  let set_proto : Value = Object({
    properties: set_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Set",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Store Set prototype globally for get_set_method access
  set_prototype_ref.val = Some(set_proto)

  // Add Set.prototype[Symbol.iterator] = Set.prototype.values
  match set_proto {
    Object(data) =>
      data.symbol_properties[iterator_sym.id] = set_proto_props["values"]
    _ => ()
  }

  // Add size getter placeholder
  set_proto_props["size"] = Number(0.0) // Placeholder - will be handled specially

  // Set constructor
  let set_ctor = Object({
    properties: { "prototype": set_proto },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("Set", fn(interp, _this_val, args) {
        // Create new Set instance
        let new_set : Value = Set({ values: [] })
        let loc = @token.Loc::default()

        // If iterable provided, populate set
        if args.length() > 0 {
          let iterable = args[0]
          if not(
              match iterable {
                Undefined | Null => true
                _ => false
              },
            ) {
            // Get iterator from iterable using Symbol.iterator
            let iterator_sym = get_iterator_symbol()
            let iterator_method = interp.get_computed_property(
              iterable,
              Symbol(iterator_sym),
              loc,
            )
            let iterator = match iterator_method {
              Object(data) =>
                match data.callable {
                  Some(_) =>
                    interp.call_value(iterator_method, iterable, [], loc)
                  None =>
                    raise @errors.TypeError(
                      message="Result of the Symbol.iterator method is not an object",
                    )
                }
              _ =>
                raise @errors.TypeError(
                  message="\{type_of(iterable)} is not iterable",
                )
            }

            // Iterate over the iterator
            while true {
              let next_method = interp.get_property(iterator, "next", loc)
              let result = interp.call_value(next_method, iterator, [], loc)
              let done = match interp.get_property(result, "done", loc) {
                Bool(b) => b
                _ => false
              }
              if done {
                break
              }
              let value = interp.get_property(result, "value", loc)
              // Add to set (using SameValueZero)
              match new_set {
                Set(data) => {
                  let mut found = false
                  for i = 0; i < data.values.length(); i = i + 1 {
                    if same_value_zero(data.values[i], value) {
                      found = true
                      break
                    }
                  }
                  if not(found) {
                    data.values.push(value)
                  }
                }
                _ => ()
              }
            }
          }
        }
        new_set
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  env.def_builtin("Set", set_ctor)
  // Set Set.prototype.constructor = Set
  match set_proto {
    Object(data) => {
      data.properties["constructor"] = set_ctor
      data.descriptors["constructor"] = {
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
/// Create a Map keys iterator
fn make_map_keys_iterator(map_data : MapData) -> Value {
  let iterator_sym = get_iterator_symbol()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < map_data.entries.length() {
          let (key, _) = map_data.entries[idx]
          index_ref.val = idx + 1
          let result_props : Map[String, Value] = {}
          result_props["value"] = key
          result_props["done"] = Bool(false)
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
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Bool(true)
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
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  let iter_obj = Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Map Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add [Symbol.iterator] that returns the iterator itself
  match iter_obj {
    Object(data) =>
      data.symbol_properties[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    _ => ()
  }
  iter_obj
}

///|
/// Create a Map values iterator
fn make_map_values_iterator(map_data : MapData) -> Value {
  let iterator_sym = get_iterator_symbol()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < map_data.entries.length() {
          let (_, value) = map_data.entries[idx]
          index_ref.val = idx + 1
          let result_props : Map[String, Value] = {}
          result_props["value"] = value
          result_props["done"] = Bool(false)
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
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Bool(true)
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
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  let iter_obj = Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Map Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add [Symbol.iterator] that returns the iterator itself
  match iter_obj {
    Object(data) =>
      data.symbol_properties[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    _ => ()
  }
  iter_obj
}

///|
/// Create a Map entries iterator
fn make_map_entries_iterator(map_data : MapData) -> Value {
  let iterator_sym = get_iterator_symbol()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < map_data.entries.length() {
          let (key, value) = map_data.entries[idx]
          index_ref.val = idx + 1
          // Return [key, value] array
          let entry_array = Array({ elements: [key, value] })
          let result_props : Map[String, Value] = {}
          result_props["value"] = entry_array
          result_props["done"] = Bool(false)
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
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Bool(true)
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
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  let iter_obj = Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Map Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add [Symbol.iterator] that returns the iterator itself
  match iter_obj {
    Object(data) =>
      data.symbol_properties[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    _ => ()
  }
  iter_obj
}

///|
/// Create a Set values iterator
fn make_set_values_iterator(set_data : SetData) -> Value {
  let iterator_sym = get_iterator_symbol()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < set_data.values.length() {
          let value = set_data.values[idx]
          index_ref.val = idx + 1
          let result_props : Map[String, Value] = {}
          result_props["value"] = value
          result_props["done"] = Bool(false)
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
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Bool(true)
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
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  let iter_obj = Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Set Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add [Symbol.iterator] that returns the iterator itself
  match iter_obj {
    Object(data) =>
      data.symbol_properties[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    _ => ()
  }
  iter_obj
}

///|
/// Create a Set entries iterator (returns [value, value] pairs)
fn make_set_entries_iterator(set_data : SetData) -> Value {
  let iterator_sym = get_iterator_symbol()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < set_data.values.length() {
          let value = set_data.values[idx]
          index_ref.val = idx + 1
          // Return [value, value] array (Set entries are [value, value] pairs)
          let entry_array = Array({ elements: [value, value] })
          let result_props : Map[String, Value] = {}
          result_props["value"] = entry_array
          result_props["done"] = Bool(false)
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
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Bool(true)
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
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  let iter_obj = Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Set Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add [Symbol.iterator] that returns the iterator itself
  match iter_obj {
    Object(data) =>
      data.symbol_properties[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    _ => ()
  }
  iter_obj
}

///|
/// WeakMap and WeakSet built-in implementations
///
/// Per ECMAScript spec, WeakMap/WeakSet:
/// - Only accept objects (and symbols) as keys
/// - Are not iterable (no forEach, keys, values, entries, Symbol.iterator)
/// - Have no "size" property
/// - In this interpreter, implemented with standard Map/Set semantics
///   (true GC-based weakness is not possible in a tree-walking interpreter)

///|
/// Check if a value is a valid WeakMap/WeakSet key (must be an object or symbol)
fn is_valid_weak_key(val : Value) -> Bool {
  match val {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    Symbol(_) => true // ES2023: symbols are valid weak keys
    _ => false
  }
}

///|
/// Get the WeakMap ID from the per-realm side table (non-forgeable)
fn get_weakmap_id(realm_state : @runtime.RealmState, data : ObjectData) -> Int? {
  for i = 0; i < realm_state.weakmap_id_table.length(); i = i + 1 {
    let (existing, id) = realm_state.weakmap_id_table[i]
    if physical_equal(existing, data) {
      return Some(id)
    }
  }
  None
}

///|
/// Store a WeakMap ID in the per-realm side table
fn set_weakmap_id(
  realm_state : @runtime.RealmState,
  data : ObjectData,
  id : Int,
) -> Unit {
  realm_state.weakmap_id_table.push((data, id))
}

///|
/// Get the WeakSet ID from the per-realm side table (non-forgeable)
fn get_weakset_id(realm_state : @runtime.RealmState, data : ObjectData) -> Int? {
  for i = 0; i < realm_state.weakset_id_table.length(); i = i + 1 {
    let (existing, id) = realm_state.weakset_id_table[i]
    if physical_equal(existing, data) {
      return Some(id)
    }
  }
  None
}

///|
/// Store a WeakSet ID in the per-realm side table
fn set_weakset_id(
  realm_state : @runtime.RealmState,
  data : ObjectData,
  id : Int,
) -> Unit {
  realm_state.weakset_id_table.push((data, id))
}

///|
/// Compare two values by reference identity (for weak collection key comparison)
fn weak_key_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Object(a_data), Object(b_data)) => physical_equal(a_data, b_data)
    (Array(a_data), Array(b_data)) => physical_equal(a_data, b_data)
    (Map(a_data), Map(b_data)) => physical_equal(a_data, b_data)
    (Set(a_data), Set(b_data)) => physical_equal(a_data, b_data)
    (Promise(a_data), Promise(b_data)) => physical_equal(a_data, b_data)
    (Proxy(a_data), Proxy(b_data)) => physical_equal(a_data, b_data)
    (Symbol(a_sym), Symbol(b_sym)) => a_sym.id == b_sym.id
    _ => false
  }
}

///|
fn close_weak_collection_iterator(
  interp : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  let return_method = interp.get_property(iterator, "return", loc)
  match return_method {
    Undefined | Null => ()
    _ =>
      if @runtime.is_callable(return_method) {
        let _ = interp.call_value(return_method, iterator, [], loc)
      } else {
        raise @errors.TypeError(message="Iterator return is not callable")
      }
  }
}

///|
/// Look up a method on WeakMap.prototype for the given realm.
///
/// Pure prototype-chain lookup against `realm_state.weakmap_prototype`. Does
/// NOT consult the receiver's own properties, so callers who need full
/// [[Get]] semantics (own-property-then-prototype) must compose this with
/// the standard property-lookup path.
pub fn get_weakmap_method(
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match realm_state.weakmap_prototype.val {
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
/// Look up a method on WeakSet.prototype for the given realm.
///
/// Pure prototype-chain lookup against `realm_state.weakset_prototype`. Does
/// NOT consult the receiver's own properties, so callers who need full
/// [[Get]] semantics (own-property-then-prototype) must compose this with
/// the standard property-lookup path.
pub fn get_weakset_method(
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match realm_state.weakset_prototype.val {
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
/// Setup WeakMap and WeakSet constructors and prototypes
pub fn setup_weakmap_set_builtins(
  env : Environment,
  well_known_symbols : @runtime.WellKnownSymbols,
  realm_state : @runtime.RealmState,
) -> Unit {
  setup_weakmap_builtins(env, well_known_symbols, realm_state)
  setup_weakset_builtins(env, well_known_symbols, realm_state)
}

///|
/// Setup WeakMap constructor and prototype
fn setup_weakmap_builtins(
  env : Environment,
  well_known_symbols : @runtime.WellKnownSymbols,
  realm_state : @runtime.RealmState,
) -> Unit {
  let tostringtag_sym = well_known_symbols.to_string_tag

  // WeakMap.prototype methods
  let wm_proto_props : Map[String, Value] = {}

  // WeakMap.prototype.get(key)
  wm_proto_props["get"] = @runtime.make_method_func(name="get", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Object(data) =>
        match get_weakmap_id(realm_state, data) {
          Some(id) => {
            let key = if args.length() > 0 { args[0] } else { Undefined }
            match realm_state.weakmap_storage.get(id) {
              Some(entries) => {
                for i = 0; i < entries.length(); i = i + 1 {
                  let (k, v) = entries[i]
                  if weak_key_equal(k, key) {
                    return v
                  }
                }
                Undefined
              }
              None => Undefined
            }
          }
          None =>
            raise @errors.TypeError(
              message="Method WeakMap.prototype.get called on incompatible receiver",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Method WeakMap.prototype.get called on incompatible receiver",
        )
    }
  })

  // WeakMap.prototype.set(key, value)
  wm_proto_props["set"] = @runtime.make_method_func(name="set", length=2, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Object(data) =>
        match get_weakmap_id(realm_state, data) {
          Some(id) => {
            let key = if args.length() > 0 { args[0] } else { Undefined }
            let value = if args.length() > 1 { args[1] } else { Undefined }
            if !is_valid_weak_key(key) {
              raise @errors.TypeError(
                message="Invalid value used as weak map key",
              )
            }
            match realm_state.weakmap_storage.get(id) {
              Some(entries) => {
                for i = 0; i < entries.length(); i = i + 1 {
                  let (k, _) = entries[i]
                  if weak_key_equal(k, key) {
                    entries[i] = (key, value)
                    return this_val
                  }
                }
                entries.push((key, value))
                this_val
              }
              None => {
                // Initialize storage if somehow missing
                realm_state.weakmap_storage[id] = [(key, value)]
                this_val
              }
            }
          }
          None =>
            raise @errors.TypeError(
              message="Method WeakMap.prototype.set called on incompatible receiver",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Method WeakMap.prototype.set called on incompatible receiver",
        )
    }
  })

  // WeakMap.prototype.has(key)
  wm_proto_props["has"] = @runtime.make_method_func(name="has", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Object(data) =>
        match get_weakmap_id(realm_state, data) {
          Some(id) => {
            let key = if args.length() > 0 { args[0] } else { Undefined }
            match realm_state.weakmap_storage.get(id) {
              Some(entries) => {
                for i = 0; i < entries.length(); i = i + 1 {
                  let (k, _) = entries[i]
                  if weak_key_equal(k, key) {
                    return Value::Bool(true)
                  }
                }
                Value::Bool(false)
              }
              None => Value::Bool(false)
            }
          }
          None =>
            raise @errors.TypeError(
              message="Method WeakMap.prototype.has called on incompatible receiver",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Method WeakMap.prototype.has called on incompatible receiver",
        )
    }
  })

  // WeakMap.prototype.delete(key)
  wm_proto_props["delete"] = @runtime.make_method_func(
    name="delete",
    length=1,
    fn(this_val, args) raise {
      match this_val {
        Object(data) =>
          match get_weakmap_id(realm_state, data) {
            Some(id) => {
              let key = if args.length() > 0 { args[0] } else { Undefined }
              match realm_state.weakmap_storage.get(id) {
                Some(entries) => {
                  for i = 0; i < entries.length(); i = i + 1 {
                    let (k, _) = entries[i]
                    if weak_key_equal(k, key) {
                      let _ = entries.remove(i)
                      return Value::Bool(true)
                    }
                  }
                  Value::Bool(false)
                }
                None => Value::Bool(false)
              }
            }
            None =>
              raise @errors.TypeError(
                message="Method WeakMap.prototype.delete called on incompatible receiver",
              )
          }
        _ =>
          raise @errors.TypeError(
            message="Method WeakMap.prototype.delete called on incompatible receiver",
          )
      }
    },
  )

  // WeakMap.prototype.getOrInsert(key, value)
  wm_proto_props["getOrInsert"] = @runtime.make_method_func(
    name="getOrInsert",
    length=2,
    fn(this_val, args) raise {
      match this_val {
        Object(data) =>
          match get_weakmap_id(realm_state, data) {
            Some(id) => {
              let key = if args.length() > 0 { args[0] } else { Undefined }
              let value = if args.length() > 1 { args[1] } else { Undefined }
              if !is_valid_weak_key(key) {
                raise @errors.TypeError(
                  message="Invalid value used as weak map key",
                )
              }
              match realm_state.weakmap_storage.get(id) {
                Some(entries) => {
                  // If key exists, return existing value
                  for i = 0; i < entries.length(); i = i + 1 {
                    let (k, v) = entries[i]
                    if weak_key_equal(k, key) {
                      return v
                    }
                  }
                  // Key not found, insert and return value
                  entries.push((key, value))
                  value
                }
                None => {
                  realm_state.weakmap_storage[id] = [(key, value)]
                  value
                }
              }
            }
            None =>
              raise @errors.TypeError(
                message="Method WeakMap.prototype.getOrInsert called on incompatible receiver",
              )
          }
        _ =>
          raise @errors.TypeError(
            message="Method WeakMap.prototype.getOrInsert called on incompatible receiver",
          )
      }
    },
  )

  // WeakMap.prototype.getOrInsertComputed(key, callbackfn)
  wm_proto_props["getOrInsertComputed"] = @runtime.make_interp_method_func(
    name="getOrInsertComputed",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) =>
          match get_weakmap_id(realm_state, data) {
            Some(id) => {
              let key = if args.length() > 0 { args[0] } else { Undefined }
              let callbackfn = if args.length() > 1 {
                args[1]
              } else {
                Undefined
              }
              // Check callbackfn is callable before validating key (per spec order)
              let cb_is_callable = match callbackfn {
                Object(od) => od.callable is Some(_)
                _ => false
              }
              if !cb_is_callable {
                raise @errors.TypeError(message="callbackfn is not a function")
              }
              if !is_valid_weak_key(key) {
                raise @errors.TypeError(
                  message="Invalid value used as weak map key",
                )
              }
              match realm_state.weakmap_storage.get(id) {
                Some(entries) => {
                  // If key exists, return existing value without calling callback
                  for i = 0; i < entries.length(); i = i + 1 {
                    let (k, v) = entries[i]
                    if weak_key_equal(k, key) {
                      return v
                    }
                  }
                  // Key not found, call callback to get value
                  let loc = @token.Loc::default()
                  let value = interp.call_value(
                    callbackfn,
                    Undefined,
                    [key],
                    loc,
                  )
                  // Re-check if key was added by callback (mutation during callback)
                  for i = 0; i < entries.length(); i = i + 1 {
                    let (k, _) = entries[i]
                    if weak_key_equal(k, key) {
                      // Overwrite with computed value per spec
                      entries[i] = (key, value)
                      return value
                    }
                  }
                  entries.push((key, value))
                  value
                }
                None => {
                  let loc = @token.Loc::default()
                  let value = interp.call_value(
                    callbackfn,
                    Undefined,
                    [key],
                    loc,
                  )
                  // Re-read storage after callback (it may have inserted entries)
                  match realm_state.weakmap_storage.get(id) {
                    Some(entries) => {
                      // Check if key was already added by callback
                      for i = 0; i < entries.length(); i = i + 1 {
                        let (k, _) = entries[i]
                        if weak_key_equal(k, key) {
                          entries[i] = (key, value)
                          return value
                        }
                      }
                      entries.push((key, value))
                    }
                    None => realm_state.weakmap_storage[id] = [(key, value)]
                  }
                  value
                }
              }
            }
            None =>
              raise @errors.TypeError(
                message="Method WeakMap.prototype.getOrInsertComputed called on incompatible receiver",
              )
          }
        _ =>
          raise @errors.TypeError(
            message="Method WeakMap.prototype.getOrInsertComputed called on incompatible receiver",
          )
      }
    },
  )

  // Create descriptor map for WeakMap prototype methods
  let wm_proto_descs : Map[String, PropDescriptor] = {}
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  wm_proto_descs["get"] = method_desc
  wm_proto_descs["set"] = method_desc
  wm_proto_descs["has"] = method_desc
  wm_proto_descs["delete"] = method_desc
  wm_proto_descs["getOrInsert"] = method_desc
  wm_proto_descs["getOrInsertComputed"] = method_desc

  // Create WeakMap prototype
  let wm_proto_sym_props : Map[Int, Value] = {}
  wm_proto_sym_props[tostringtag_sym.id] = Value::String_("WeakMap")
  let wm_proto_sym_descs : Map[Int, PropDescriptor] = {}
  wm_proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let wm_proto : Value = Value::Object({
    bag: {
      properties: wm_proto_props,
      symbol_properties: wm_proto_sym_props,
      descriptors: wm_proto_descs,
      symbol_descriptors: wm_proto_sym_descs,
    },
    prototype: @runtime.get_obj_proto(),
    callable: None,
    class_name: "WeakMap",
    extensible: true,
    arraybuffer_state: None,
  })

  // Store WeakMap prototype in the realm.
  realm_state.weakmap_prototype.val = Some(wm_proto)

  // WeakMap constructor
  let wm_ctor = @runtime.make_interp_method_func_with_context(
    name="WeakMap",
    length=0,
    fn(interp, context, _this_val, args) raise {
      if !context.is_constructing() {
        raise @errors.TypeError(message="Constructor WeakMap requires 'new'")
      }
      // Create new WeakMap instance
      let id = realm_state.weakmap_id_counter.val
      realm_state.weakmap_id_counter.val = id + 1
      let entries : Array[(Value, Value)] = []
      realm_state.weakmap_storage[id] = entries
      let wm_data : ObjectData = {
        bag: @runtime.PropertyBag(),
        prototype: wm_proto,
        callable: None,
        class_name: "WeakMap",
        extensible: true,
        arraybuffer_state: None,
      }
      set_weakmap_id(realm_state, wm_data, id)
      let wm_obj : Value = Object(wm_data)

      // If iterable provided, populate
      if args.length() > 0 {
        let iterable = args[0]
        match iterable {
          Undefined | Null => ()
          _ => {
            let loc = @token.Loc::default()
            let adder = interp.get_property(wm_obj, "set", loc)
            if !@runtime.is_callable(adder) {
              raise @errors.TypeError(message="WeakMap adder is not callable")
            }
            let iterator_sym = interp.realm_state.well_known_symbols.iterator
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
                  message="\{@runtime.type_of(iterable)} is not iterable",
                )
            }

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
              // Value should be [key, value] pair
              let key = interp.get_computed_property(
                value,
                Value::Number(0.0),
                loc,
              )
              let val = interp.get_computed_property(
                value,
                Value::Number(1.0),
                loc,
              )
              let _ = interp.call_value(adder, wm_obj, [key, val], loc) catch {
                e => {
                  close_weak_collection_iterator(interp, iterator, loc) catch {
                    _ => ()
                  }
                  raise e
                }
              }
            }
          }
        }
      }
      wm_obj
    },
  )
  // Add prototype property to WeakMap constructor
  match wm_ctor {
    Object(data) => {
      data.bag.properties["prototype"] = wm_proto
      data.bag.descriptors["prototype"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }
  env.def_builtin("WeakMap", wm_ctor)

  // Set WeakMap.prototype.constructor = WeakMap
  match wm_proto {
    Object(data) => {
      data.bag.properties["constructor"] = wm_ctor
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
}

///|
/// Setup WeakSet constructor and prototype
fn setup_weakset_builtins(
  env : Environment,
  well_known_symbols : @runtime.WellKnownSymbols,
  realm_state : @runtime.RealmState,
) -> Unit {
  let tostringtag_sym = well_known_symbols.to_string_tag

  // WeakSet.prototype methods
  let ws_proto_props : Map[String, Value] = {}

  // WeakSet.prototype.add(value)
  ws_proto_props["add"] = @runtime.make_method_func(name="add", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Object(data) =>
        match get_weakset_id(realm_state, data) {
          Some(id) => {
            let value = if args.length() > 0 { args[0] } else { Undefined }
            if !is_valid_weak_key(value) {
              raise @errors.TypeError(message="Invalid value used in weak set")
            }
            match realm_state.weakset_storage.get(id) {
              Some(values) => {
                for i = 0; i < values.length(); i = i + 1 {
                  if weak_key_equal(values[i], value) {
                    return this_val
                  }
                }
                values.push(value)
                this_val
              }
              None => {
                realm_state.weakset_storage[id] = [value]
                this_val
              }
            }
          }
          None =>
            raise @errors.TypeError(
              message="Method WeakSet.prototype.add called on incompatible receiver",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Method WeakSet.prototype.add called on incompatible receiver",
        )
    }
  })

  // WeakSet.prototype.has(value)
  ws_proto_props["has"] = @runtime.make_method_func(name="has", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Object(data) =>
        match get_weakset_id(realm_state, data) {
          Some(id) => {
            let value = if args.length() > 0 { args[0] } else { Undefined }
            match realm_state.weakset_storage.get(id) {
              Some(values) => {
                for i = 0; i < values.length(); i = i + 1 {
                  if weak_key_equal(values[i], value) {
                    return Value::Bool(true)
                  }
                }
                Value::Bool(false)
              }
              None => Value::Bool(false)
            }
          }
          None =>
            raise @errors.TypeError(
              message="Method WeakSet.prototype.has called on incompatible receiver",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Method WeakSet.prototype.has called on incompatible receiver",
        )
    }
  })

  // WeakSet.prototype.delete(value)
  ws_proto_props["delete"] = @runtime.make_method_func(
    name="delete",
    length=1,
    fn(this_val, args) raise {
      match this_val {
        Object(data) =>
          match get_weakset_id(realm_state, data) {
            Some(id) => {
              let value = if args.length() > 0 { args[0] } else { Undefined }
              match realm_state.weakset_storage.get(id) {
                Some(values) => {
                  for i = 0; i < values.length(); i = i + 1 {
                    if weak_key_equal(values[i], value) {
                      let _ = values.remove(i)
                      return Value::Bool(true)
                    }
                  }
                  Value::Bool(false)
                }
                None => Value::Bool(false)
              }
            }
            None =>
              raise @errors.TypeError(
                message="Method WeakSet.prototype.delete called on incompatible receiver",
              )
          }
        _ =>
          raise @errors.TypeError(
            message="Method WeakSet.prototype.delete called on incompatible receiver",
          )
      }
    },
  )

  // Create descriptor map for WeakSet prototype methods
  let ws_proto_descs : Map[String, PropDescriptor] = {}
  let ws_method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  ws_proto_descs["add"] = ws_method_desc
  ws_proto_descs["has"] = ws_method_desc
  ws_proto_descs["delete"] = ws_method_desc

  // Create WeakSet prototype
  let ws_proto_sym_props : Map[Int, Value] = {}
  ws_proto_sym_props[tostringtag_sym.id] = Value::String_("WeakSet")
  let ws_proto_sym_descs : Map[Int, PropDescriptor] = {}
  ws_proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let ws_proto : Value = Value::Object({
    bag: {
      properties: ws_proto_props,
      symbol_properties: ws_proto_sym_props,
      descriptors: ws_proto_descs,
      symbol_descriptors: ws_proto_sym_descs,
    },
    prototype: @runtime.get_obj_proto(),
    callable: None,
    class_name: "WeakSet",
    extensible: true,
    arraybuffer_state: None,
  })

  // Store WeakSet prototype in the realm.
  realm_state.weakset_prototype.val = Some(ws_proto)

  // WeakSet constructor
  let ws_ctor = @runtime.make_interp_method_func_with_context(
    name="WeakSet",
    length=0,
    fn(interp, context, _this_val, args) raise {
      if !context.is_constructing() {
        raise @errors.TypeError(message="Constructor WeakSet requires 'new'")
      }
      // Create new WeakSet instance
      let id = realm_state.weakset_id_counter.val
      realm_state.weakset_id_counter.val = id + 1
      let values : Array[Value] = []
      realm_state.weakset_storage[id] = values
      let ws_data : ObjectData = {
        bag: @runtime.PropertyBag(),
        prototype: ws_proto,
        callable: None,
        class_name: "WeakSet",
        extensible: true,
        arraybuffer_state: None,
      }
      set_weakset_id(realm_state, ws_data, id)
      let ws_obj : Value = Object(ws_data)

      // If iterable provided, populate
      if args.length() > 0 {
        let iterable = args[0]
        match iterable {
          Undefined | Null => ()
          _ => {
            let loc = @token.Loc::default()
            let adder = interp.get_property(ws_obj, "add", loc)
            if !@runtime.is_callable(adder) {
              raise @errors.TypeError(message="WeakSet adder is not callable")
            }
            let iterator_sym = interp.realm_state.well_known_symbols.iterator
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
                  message="\{@runtime.type_of(iterable)} is not iterable",
                )
            }

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
              let _ = interp.call_value(adder, ws_obj, [value], loc) catch {
                e => {
                  close_weak_collection_iterator(interp, iterator, loc) catch {
                    _ => ()
                  }
                  raise e
                }
              }
            }
          }
        }
      }
      ws_obj
    },
  )
  // Add prototype property to WeakSet constructor
  match ws_ctor {
    Object(data) => {
      data.bag.properties["prototype"] = ws_proto
      data.bag.descriptors["prototype"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }
  env.def_builtin("WeakSet", ws_ctor)

  // Set WeakSet.prototype.constructor = WeakSet
  match ws_proto {
    Object(data) => {
      data.bag.properties["constructor"] = ws_ctor
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
}

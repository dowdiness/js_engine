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
/// Global counter for WeakMap instance IDs
let weakmap_id_counter : Ref[Int] = { val: 0 }

///|
/// Global storage for WeakMap entries keyed by instance ID
let weakmap_storage : Map[Int, Array[(Value, Value)]] = {}

///|
/// Global counter for WeakSet instance IDs
let weakset_id_counter : Ref[Int] = { val: 0 }

///|
/// Global storage for WeakSet entries keyed by instance ID
let weakset_storage : Map[Int, Array[Value]] = {}

///|
/// Global storage for WeakMap prototype
let weakmap_prototype_ref : Ref[Value?] = { val: None }

///|
/// Global storage for WeakSet prototype
let weakset_prototype_ref : Ref[Value?] = { val: None }

///|
/// Side table for WeakMap instance IDs (non-forgeable by user code)
let weakmap_id_table : Array[(ObjectData, Int)] = []

///|
/// Side table for WeakSet instance IDs (non-forgeable by user code)
let weakset_id_table : Array[(ObjectData, Int)] = []

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
/// Get the WeakMap ID from the side table (non-forgeable)
fn get_weakmap_id(data : ObjectData) -> Int? {
  for i = 0; i < weakmap_id_table.length(); i = i + 1 {
    let (existing, id) = weakmap_id_table[i]
    if physical_equal(existing, data) {
      return Some(id)
    }
  }
  None
}

///|
/// Store a WeakMap ID in the side table
fn set_weakmap_id(data : ObjectData, id : Int) -> Unit {
  weakmap_id_table.push((data, id))
}

///|
/// Get the WeakSet ID from the side table (non-forgeable)
fn get_weakset_id(data : ObjectData) -> Int? {
  for i = 0; i < weakset_id_table.length(); i = i + 1 {
    let (existing, id) = weakset_id_table[i]
    if physical_equal(existing, data) {
      return Some(id)
    }
  }
  None
}

///|
/// Store a WeakSet ID in the side table
fn set_weakset_id(data : ObjectData, id : Int) -> Unit {
  weakset_id_table.push((data, id))
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
/// Get WeakMap.prototype method for a WeakMap instance
pub fn get_weakmap_method(data : ObjectData, prop : String) -> Value {
  // Check own properties first
  match data.properties.get(prop) {
    Some(v) => return v
    None => ()
  }
  match weakmap_prototype_ref.val {
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
/// Get WeakSet.prototype method for a WeakSet instance
pub fn get_weakset_method(data : ObjectData, prop : String) -> Value {
  // Check own properties first
  match data.properties.get(prop) {
    Some(v) => return v
    None => ()
  }
  match weakset_prototype_ref.val {
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
/// Setup WeakMap and WeakSet constructors and prototypes
pub fn setup_weakmap_set_builtins(env : Environment) -> Unit {
  setup_weakmap_builtins(env)
  setup_weakset_builtins(env)
}

///|
/// Setup WeakMap constructor and prototype
fn setup_weakmap_builtins(env : Environment) -> Unit {
  let tostringtag_sym = get_tostringtag_symbol()

  // WeakMap.prototype methods
  let wm_proto_props : Map[String, Value] = {}

  // WeakMap.prototype.get(key)
  wm_proto_props["get"] = make_method_func("get", 1, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakmap_id(data) {
              Some(id) => {
                let key = if args.length() > 0 { args[0] } else { Undefined }
                match weakmap_storage.get(id) {
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
  wm_proto_props["set"] = make_method_func("set", 2, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakmap_id(data) {
              Some(id) => {
                let key = if args.length() > 0 { args[0] } else { Undefined }
                let value = if args.length() > 1 { args[1] } else { Undefined }
                if not(is_valid_weak_key(key)) {
                  raise @errors.TypeError(
                    message="Invalid value used as weak map key",
                  )
                }
                match weakmap_storage.get(id) {
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
                    weakmap_storage[id] = [(key, value)]
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
  wm_proto_props["has"] = make_method_func("has", 1, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakmap_id(data) {
              Some(id) => {
                let key = if args.length() > 0 { args[0] } else { Undefined }
                match weakmap_storage.get(id) {
                  Some(entries) => {
                    for i = 0; i < entries.length(); i = i + 1 {
                      let (k, _) = entries[i]
                      if weak_key_equal(k, key) {
                        return Bool(true)
                      }
                    }
                    Bool(false)
                  }
                  None => Bool(false)
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
  wm_proto_props["delete"] = make_method_func("delete", 1, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakmap_id(data) {
              Some(id) => {
                let key = if args.length() > 0 { args[0] } else { Undefined }
                match weakmap_storage.get(id) {
                  Some(entries) => {
                    for i = 0; i < entries.length(); i = i + 1 {
                      let (k, _) = entries[i]
                      if weak_key_equal(k, key) {
                        let _ = entries.remove(i)
                        return Bool(true)
                      }
                    }
                    Bool(false)
                  }
                  None => Bool(false)
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
      })

  // WeakMap.prototype.getOrInsert(key, value)
  wm_proto_props["getOrInsert"] = make_method_func("getOrInsert", 2, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakmap_id(data) {
              Some(id) => {
                let key = if args.length() > 0 { args[0] } else { Undefined }
                let value = if args.length() > 1 { args[1] } else { Undefined }
                if not(is_valid_weak_key(key)) {
                  raise @errors.TypeError(
                    message="Invalid value used as weak map key",
                  )
                }
                match weakmap_storage.get(id) {
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
                    weakmap_storage[id] = [(key, value)]
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
      })

  // WeakMap.prototype.getOrInsertComputed(key, callbackfn)
  wm_proto_props["getOrInsertComputed"] = make_interp_method_func("getOrInsertComputed", 2, fn(
        interp,
        this_val,
        args,
      ) raise {
        match this_val {
          Object(data) =>
            match get_weakmap_id(data) {
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
                if not(cb_is_callable) {
                  raise @errors.TypeError(
                    message="callbackfn is not a function",
                  )
                }
                if not(is_valid_weak_key(key)) {
                  raise @errors.TypeError(
                    message="Invalid value used as weak map key",
                  )
                }
                match weakmap_storage.get(id) {
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
                    match weakmap_storage.get(id) {
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
                      None => weakmap_storage[id] = [(key, value)]
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
      })

  // Create descriptor map for WeakMap prototype methods
  let wm_proto_descs : Map[String, PropDescriptor] = {}
  let method_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
  wm_proto_descs["get"] = method_desc
  wm_proto_descs["set"] = method_desc
  wm_proto_descs["has"] = method_desc
  wm_proto_descs["delete"] = method_desc
  wm_proto_descs["getOrInsert"] = method_desc
  wm_proto_descs["getOrInsertComputed"] = method_desc

  // Create WeakMap prototype
  let wm_proto_sym_props : Map[Int, Value] = {}
  wm_proto_sym_props[tostringtag_sym.id] = String_("WeakMap")
  let wm_proto_sym_descs : Map[Int, PropDescriptor] = {}
  wm_proto_sym_descs[tostringtag_sym.id] = { writable: false, enumerable: false, configurable: true, getter: None, setter: None }
  let wm_proto : Value = Object({
    properties: wm_proto_props,
    symbol_properties: wm_proto_sym_props,
    prototype: get_obj_proto(),
    callable: None,
    class_name: "WeakMap",
    descriptors: wm_proto_descs,
    symbol_descriptors: wm_proto_sym_descs,
    extensible: true,
  })

  // Store WeakMap prototype globally
  weakmap_prototype_ref.val = Some(wm_proto)

  // WeakMap constructor
  let wm_ctor = make_interp_method_func("WeakMap", 0, fn(interp, _this_val, args) raise {
        if not(is_constructing.val) {
          raise @errors.TypeError(message="Constructor WeakMap requires 'new'")
        }
        // Create new WeakMap instance
        let id = weakmap_id_counter.val
        weakmap_id_counter.val = id + 1
        let entries : Array[(Value, Value)] = []
        weakmap_storage[id] = entries
        let wm_data : ObjectData = {
          properties: {},
          symbol_properties: {},
          prototype: wm_proto,
          callable: None,
          class_name: "WeakMap",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        }
        set_weakmap_id(wm_data, id)
        let wm_obj : Value = Object(wm_data)

        // If iterable provided, populate
        if args.length() > 0 {
          let iterable = args[0]
          match iterable {
            Undefined | Null => ()
            _ => {
              let loc = @token.Loc::default()
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
                // Value should be [key, value] pair
                let key = interp.get_computed_property(value, Number(0.0), loc)
                let val = interp.get_computed_property(value, Number(1.0), loc)
                if not(is_valid_weak_key(key)) {
                  raise @errors.TypeError(
                    message="Invalid value used as weak map key",
                  )
                }
                // Upsert
                let mut found = false
                for i = 0; i < entries.length(); i = i + 1 {
                  let (k, _) = entries[i]
                  if weak_key_equal(k, key) {
                    entries[i] = (key, val)
                    found = true
                    break
                  }
                }
                if not(found) {
                  entries.push((key, val))
                }
              }
            }
          }
        }
        wm_obj
      })
  // Add prototype property to WeakMap constructor
  match wm_ctor {
    Object(data) => {
      data.properties["prototype"] = wm_proto
      data.descriptors["prototype"] = { writable: false, enumerable: false, configurable: false, getter: None, setter: None }
    }
    _ => ()
  }
  env.def_builtin("WeakMap", wm_ctor)

  // Set WeakMap.prototype.constructor = WeakMap
  match wm_proto {
    Object(data) => {
      data.properties["constructor"] = wm_ctor
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
/// Setup WeakSet constructor and prototype
fn setup_weakset_builtins(env : Environment) -> Unit {
  let tostringtag_sym = get_tostringtag_symbol()

  // WeakSet.prototype methods
  let ws_proto_props : Map[String, Value] = {}

  // WeakSet.prototype.add(value)
  ws_proto_props["add"] = make_method_func("add", 1, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakset_id(data) {
              Some(id) => {
                let value = if args.length() > 0 { args[0] } else { Undefined }
                if not(is_valid_weak_key(value)) {
                  raise @errors.TypeError(
                    message="Invalid value used in weak set",
                  )
                }
                match weakset_storage.get(id) {
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
                    weakset_storage[id] = [value]
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
  ws_proto_props["has"] = make_method_func("has", 1, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakset_id(data) {
              Some(id) => {
                let value = if args.length() > 0 { args[0] } else { Undefined }
                match weakset_storage.get(id) {
                  Some(values) => {
                    for i = 0; i < values.length(); i = i + 1 {
                      if weak_key_equal(values[i], value) {
                        return Bool(true)
                      }
                    }
                    Bool(false)
                  }
                  None => Bool(false)
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
  ws_proto_props["delete"] = make_method_func("delete", 1, fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            match get_weakset_id(data) {
              Some(id) => {
                let value = if args.length() > 0 { args[0] } else { Undefined }
                match weakset_storage.get(id) {
                  Some(values) => {
                    for i = 0; i < values.length(); i = i + 1 {
                      if weak_key_equal(values[i], value) {
                        let _ = values.remove(i)
                        return Bool(true)
                      }
                    }
                    Bool(false)
                  }
                  None => Bool(false)
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
      })

  // Create descriptor map for WeakSet prototype methods
  let ws_proto_descs : Map[String, PropDescriptor] = {}
  let ws_method_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
  ws_proto_descs["add"] = ws_method_desc
  ws_proto_descs["has"] = ws_method_desc
  ws_proto_descs["delete"] = ws_method_desc

  // Create WeakSet prototype
  let ws_proto_sym_props : Map[Int, Value] = {}
  ws_proto_sym_props[tostringtag_sym.id] = String_("WeakSet")
  let ws_proto_sym_descs : Map[Int, PropDescriptor] = {}
  ws_proto_sym_descs[tostringtag_sym.id] = { writable: false, enumerable: false, configurable: true, getter: None, setter: None }
  let ws_proto : Value = Object({
    properties: ws_proto_props,
    symbol_properties: ws_proto_sym_props,
    prototype: get_obj_proto(),
    callable: None,
    class_name: "WeakSet",
    descriptors: ws_proto_descs,
    symbol_descriptors: ws_proto_sym_descs,
    extensible: true,
  })

  // Store WeakSet prototype globally
  weakset_prototype_ref.val = Some(ws_proto)

  // WeakSet constructor
  let ws_ctor = make_interp_method_func("WeakSet", 0, fn(interp, _this_val, args) raise {
        if not(is_constructing.val) {
          raise @errors.TypeError(message="Constructor WeakSet requires 'new'")
        }
        // Create new WeakSet instance
        let id = weakset_id_counter.val
        weakset_id_counter.val = id + 1
        let values : Array[Value] = []
        weakset_storage[id] = values
        let ws_data : ObjectData = {
          properties: {},
          symbol_properties: {},
          prototype: ws_proto,
          callable: None,
          class_name: "WeakSet",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        }
        set_weakset_id(ws_data, id)
        let ws_obj : Value = Object(ws_data)

        // If iterable provided, populate
        if args.length() > 0 {
          let iterable = args[0]
          match iterable {
            Undefined | Null => ()
            _ => {
              let loc = @token.Loc::default()
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
                if not(is_valid_weak_key(value)) {
                  raise @errors.TypeError(
                    message="Invalid value used in weak set",
                  )
                }
                // Add if not present
                let mut found = false
                for i = 0; i < values.length(); i = i + 1 {
                  if weak_key_equal(values[i], value) {
                    found = true
                    break
                  }
                }
                if not(found) {
                  values.push(value)
                }
              }
            }
          }
        }
        ws_obj
      })
  // Add prototype property to WeakSet constructor
  match ws_ctor {
    Object(data) => {
      data.properties["prototype"] = ws_proto
      data.descriptors["prototype"] = { writable: false, enumerable: false, configurable: false, getter: None, setter: None }
    }
    _ => ()
  }
  env.def_builtin("WeakSet", ws_ctor)

  // Set WeakSet.prototype.constructor = WeakSet
  match ws_proto {
    Object(data) => {
      data.properties["constructor"] = ws_ctor
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

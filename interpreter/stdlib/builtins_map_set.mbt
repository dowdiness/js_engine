///|
/// Map and Set built-in implementations
///
/// This module provides ES6 Map and Set collections with:
/// - SameValueZero equality for keys/values (NaN === NaN, +0 === -0)
/// - Insertion order preservation
/// - Iterator protocol support
/// - Standard methods (get/set/has/delete/clear for Map, add/has/delete/clear for Set)

///|
fn lookup_prototype_method(proto : Value, prop : String) -> Value? {
  let mut current = proto
  while true {
    match current {
      Object(proto_data) =>
        match proto_data.bag.properties.get(prop) {
          Some(value) => return Some(value)
          None => current = proto_data.prototype
        }
      _ => return None
    }
  }
  None
}

///|
fn get_map_lookup_prototype(
  data : MapData,
  realm_state : @runtime.RealmState,
) -> Value {
  match data.prototype {
    Null => realm_state.get_map_proto()
    proto => proto
  }
}

///|
fn get_set_lookup_prototype(
  data : SetData,
  realm_state : @runtime.RealmState,
) -> Value {
  match data.prototype {
    Null => realm_state.get_set_proto()
    proto => proto
  }
}

///|
fn canonicalize_keyed_collection_key(key : Value) -> Value {
  match key {
    Number(n) if n == 0.0 => Number(0.0)
    _ => key
  }
}

///|
priv struct SetRecord {
  set_object : Value
  size : Double
  has : Value
  keys : Value
}

///|
/// ES2024 §7.4.2 GetSetRecord(obj)
fn get_set_record(
  interp : @runtime.Interpreter,
  obj : Value,
  loc : @token.Loc,
) -> SetRecord raise {
  guard @runtime.is_object_value(obj) else {
    raise @errors.TypeError(message="Set method argument is not an object")
  }
  let raw_size = interp.get_property(obj, "size", loc)
  let num_size = interp.to_number(raw_size)
  if num_size.is_nan() {
    raise @errors.TypeError(
      message="Set method argument's size property is not a number",
    )
  }
  // §7.4.2 step 5: ToIntegerOrInfinity truncates toward zero, not floor.
  // floor(-0.5) = -1 (would wrongly throw), trunc(-0.5) = 0 (valid).
  // +∞ is allowed and passes the < 0.0 check below; -∞ is caught by it.
  let int_size = if num_size >= 0.0 {
    num_size.floor()
  } else {
    num_size.ceil()
  }
  if int_size < 0.0 {
    raise @errors.RangeError(
      message="Set method argument's size property must be a non-negative integer",
    )
  }
  let has_val = interp.get_property(obj, "has", loc)
  guard @runtime.is_callable(has_val) else {
    raise @errors.TypeError(
      message="Set method argument's has property is not callable",
    )
  }
  let keys_val = interp.get_property(obj, "keys", loc)
  guard @runtime.is_callable(keys_val) else {
    raise @errors.TypeError(
      message="Set method argument's keys property is not callable",
    )
  }
  { set_object: obj, size: int_size, has: has_val, keys: keys_val }
}

///|
fn MapData::append_entry(self : MapData, key : Value, value : Value) -> Unit {
  self.entries.push((key, value))
  self.entry_ids.push(self.next_entry_id)
  self.next_entry_id += 1
}

///|
fn MapData::remove_entry_at(self : MapData, index : Int) -> Unit {
  let _ = self.entries.remove(index)
  let _ = self.entry_ids.remove(index)
}

///|
fn MapData::clear_entries(self : MapData) -> Unit {
  self.entries.clear()
  self.entry_ids.clear()
}

///|
/// Get Map.prototype methods for a Map instance
pub fn get_map_method(
  data : MapData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match
    lookup_prototype_method(get_map_lookup_prototype(data, realm_state), prop) {
    Some(m) => m
    None => Undefined
  }
}

///|
/// Get Set.prototype methods for a Set instance
pub fn get_set_method(
  data : SetData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match
    lookup_prototype_method(get_set_lookup_prototype(data, realm_state), prop) {
    Some(m) => m
    None => Undefined
  }
}

///|
/// Setup Map and Set constructors and prototypes
pub fn setup_map_set_builtins(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  setup_map_builtins(env, realm_state)
  setup_set_builtins(env, realm_state)
}

///|
// Engine-private negative symbol IDs for Map Iterator internal slots.
// These IDs are not registered in SymbolState, so JavaScript cannot obtain
// or enumerate keys for them via string or symbol property access.
const MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID = -130

///|
const MAP_ITERATOR_TARGET_SYMBOL_ID = -131

///|
const MAP_ITERATOR_KIND_SYMBOL_ID = -132

///|
const MAP_ITERATOR_KIND_KEY = 0

///|
const MAP_ITERATOR_KIND_VALUE = 1

///|
const MAP_ITERATOR_KIND_ENTRY = 2

///|
fn map_iterator_internal_slot_descriptor() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn map_iterator_type_error() -> Value raise Error {
  raise @errors.TypeError(
    message="Map Iterator.prototype.next requires that |this| be a Map Iterator",
  )
}

///|
fn map_iterator_result_value(
  kind : Int,
  key : Value,
  value : Value,
) -> Value raise Error {
  if kind == MAP_ITERATOR_KIND_KEY {
    key
  } else if kind == MAP_ITERATOR_KIND_VALUE {
    value
  } else if kind == MAP_ITERATOR_KIND_ENTRY {
    @runtime.make_array([key, value])
  } else {
    map_iterator_type_error()
  }
}

///|
fn map_iterator_next(this_val : Value) -> Value raise Error {
  match this_val {
    Object(data) => {
      guard data.class_name == "Map Iterator" else {
        return map_iterator_type_error()
      }
      let (current, iterated_map, kind) = match
        (
          @runtime.get_map_iterator_next_index(
            data,
            MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID,
          ),
          @runtime.get_map_iterator_target(data, MAP_ITERATOR_TARGET_SYMBOL_ID),
          @runtime.get_map_iterator_kind(data, MAP_ITERATOR_KIND_SYMBOL_ID),
        ) {
        (Some(Number(index)), Some(target), Some(Number(kind))) =>
          (index.to_int(), target, kind.to_int())
        _ => return map_iterator_type_error()
      }
      match iterated_map {
        Undefined => @runtime.create_iter_result(Undefined, true)
        Map(map_data) => {
          guard current < map_data.entries.length() else {
            @runtime.detach_map_iterator_target(
              data,
              MAP_ITERATOR_TARGET_SYMBOL_ID,
            )
            return @runtime.create_iter_result(Undefined, true)
          }
          let (key, value) = map_data.entries[current]
          @runtime.set_map_iterator_next_index(
            data,
            MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID,
            Number((current + 1).to_double()),
          )
          let result_value = map_iterator_result_value(kind, key, value)
          @runtime.create_iter_result(result_value, false)
        }
        _ => map_iterator_type_error()
      }
    }
    _ => map_iterator_type_error()
  }
}

///|
fn make_map_iterator(
  realm_state : @runtime.RealmState,
  map_data : MapData,
  kind : Int,
) -> Value {
  let map_iter_proto = get_map_iterator_proto(realm_state)
  let iter_sym_props : Map[Int, Value] = {}
  iter_sym_props[MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID] = Value::Number(0.0)
  iter_sym_props[MAP_ITERATOR_TARGET_SYMBOL_ID] = Value::Map(map_data)
  iter_sym_props[MAP_ITERATOR_KIND_SYMBOL_ID] = Value::Number(kind.to_double())
  let iter_sym_descs : Map[Int, PropDescriptor] = {}
  let slot_desc = map_iterator_internal_slot_descriptor()
  iter_sym_descs[MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID] = slot_desc
  iter_sym_descs[MAP_ITERATOR_TARGET_SYMBOL_ID] = slot_desc
  iter_sym_descs[MAP_ITERATOR_KIND_SYMBOL_ID] = slot_desc
  Value::Object({
    bag: {
      properties: {},
      symbol_properties: iter_sym_props,
      descriptors: {},
      symbol_descriptors: iter_sym_descs,
    },
    prototype: map_iter_proto,
    callable: None,
    class_name: "Map Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Setup Map constructor and prototype
fn setup_map_builtins(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  let well_known_symbols = realm_state.well_known_symbols
  let iterator_sym = well_known_symbols.iterator

  // Map.prototype methods
  let map_proto_props : Map[String, Value] = {}

  // Map.prototype.get(key)
  map_proto_props["get"] = @runtime.make_method_func(name="get", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        // Find key using SameValueZero
        match data.entries.search_by(entry => same_value_zero(entry.0, key)) {
          Some(i) => data.entries[i].1
          None => Undefined
        }
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.get called on incompatible receiver",
        )
    }
  })

  // Map.prototype.set(key, value)
  map_proto_props["set"] = @runtime.make_method_func(name="set", length=2, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        let value = if args.length() > 1 { args[1] } else { Undefined }
        // Find existing key using SameValueZero
        match data.entries.search_by(entry => same_value_zero(entry.0, key)) {
          Some(i) => {
            // Update existing entry
            data.entries[i] = (key, value)
            return this_val
          }
          None => ()
        }
        // Add new entry
        data.append_entry(key, value)
        this_val
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.set called on incompatible receiver",
        )
    }
  })

  // Map.prototype.has(key)
  map_proto_props["has"] = @runtime.make_method_func(name="has", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        let key = if args.length() > 0 { args[0] } else { Undefined }
        // Find key using SameValueZero
        Value::Bool(
          data.entries.search_by(entry => same_value_zero(entry.0, key))
          is Some(_),
        )
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.has called on incompatible receiver",
        )
    }
  })

  // Map.prototype.delete(key)
  map_proto_props["delete"] = @runtime.make_method_func(
    name="delete",
    length=1,
    fn(this_val, args) raise {
      match this_val {
        Value::Map(data) => {
          let key = if args.length() > 0 { args[0] } else { Undefined }
          // Find and remove key using SameValueZero
          match data.entries.search_by(entry => same_value_zero(entry.0, key)) {
            Some(i) => {
              data.remove_entry_at(i)
              Value::Bool(true)
            }
            None => Value::Bool(false)
          }
        }
        _ =>
          raise @errors.TypeError(
            message="Method Map.prototype.delete called on incompatible receiver",
          )
      }
    },
  )

  // Map.prototype.clear()
  map_proto_props["clear"] = @runtime.make_method_func(name="clear", length=0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Map(data) => {
        data.clear_entries()
        Undefined
      }
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.clear called on incompatible receiver",
        )
    }
  })

  // Map.prototype.forEach(callback, thisArg?)
  map_proto_props["forEach"] = @runtime.make_interp_method_func(
    name="forEach",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Value::Map(data) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          if !@runtime.is_callable(callback) {
            raise @errors.TypeError(message="callbackfn is not callable")
          }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          // Iterate by stable record id instead of compacted array index. Map
          // deletions physically remove entries here, but the spec's MapData
          // list keeps deleted records as empty slots; an id cursor preserves
          // that order when earlier/current entries are removed and successors
          // shift to lower indexes.
          let mut next_entry_id = 0
          while true {
            match data.entry_ids.search_by(id => id >= next_entry_id) {
              None => break
              Some(i) => {
                let entry_id = data.entry_ids[i]
                let (key, value) = data.entries[i]
                next_entry_id = entry_id + 1
                // Call callback(value, key, map)
                let _ = interp.call_value(
                  callback,
                  this_arg,
                  [value, key, this_val],
                  loc,
                )
              }
            }
          }
          Undefined
        }
        _ =>
          raise @errors.TypeError(
            message="Method Map.prototype.forEach called on incompatible receiver",
          )
      }
    },
  )

  // Map.prototype.keys() - returns iterator of keys
  map_proto_props["keys"] = @runtime.make_method_func(name="keys", length=0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Map(data) => make_map_keys_iterator(realm_state, data)
      _ =>
        raise @errors.TypeError(
          message="Method Map.prototype.keys called on incompatible receiver",
        )
    }
  })

  // Map.prototype.values() - returns iterator of values
  map_proto_props["values"] = @runtime.make_method_func(
    name="values",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Map(data) => make_map_values_iterator(realm_state, data)
        _ =>
          raise @errors.TypeError(
            message="Method Map.prototype.values called on incompatible receiver",
          )
      }
    },
  )

  // Map.prototype.entries() - returns iterator of [key, value] pairs
  map_proto_props["entries"] = @runtime.make_method_func(
    name="entries",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Map(data) => make_map_entries_iterator(realm_state, data)
        _ =>
          raise @errors.TypeError(
            message="Method Map.prototype.entries called on incompatible receiver",
          )
      }
    },
  )

  // Map.prototype.getOrInsert(key, value)
  map_proto_props["getOrInsert"] = @runtime.make_method_func(
    name="getOrInsert",
    length=2,
    fn(this_val, args) raise {
      match this_val {
        Value::Map(data) => {
          let key = if args.length() > 0 { args[0] } else { Undefined }
          let value = if args.length() > 1 { args[1] } else { Undefined }
          // If key exists, return existing value
          match data.entries.search_by(entry => same_value_zero(entry.0, key)) {
            Some(i) => return data.entries[i].1
            None => ()
          }
          // Key not found, insert and return value
          data.append_entry(key, value)
          value
        }
        _ =>
          raise @errors.TypeError(
            message="Method Map.prototype.getOrInsert called on incompatible receiver",
          )
      }
    },
  )

  // Map.prototype.getOrInsertComputed(key, callbackfn)
  map_proto_props["getOrInsertComputed"] = @runtime.make_interp_method_func(
    name="getOrInsertComputed",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Value::Map(data) => {
          let raw_key = if args.length() > 0 { args[0] } else { Undefined }
          let callbackfn = if args.length() > 1 { args[1] } else { Undefined }
          if !@runtime.is_callable(callbackfn) {
            raise @errors.TypeError(message="callbackfn is not callable")
          }
          let key = canonicalize_keyed_collection_key(raw_key)
          // If key exists, return existing value without calling callback
          match data.entries.search_by(entry => same_value_zero(entry.0, key)) {
            Some(i) => return data.entries[i].1
            None => ()
          }
          // Key not found, call callback to get value
          let loc = @token.Loc::default()
          let value = interp.call_value(callbackfn, Undefined, [key], loc)
          // Re-check if key was added by callback (mutation during callback)
          match data.entries.search_by(entry => same_value_zero(entry.0, key)) {
            Some(i) => {
              // Overwrite with computed value per spec
              data.entries[i] = (key, value)
              return value
            }
            None => ()
          }
          data.append_entry(key, value)
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
  let method_desc = @runtime.builtin_method_desc()
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
  let size_getter = @runtime.make_method_func(name="get size", length=0, fn(
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
    is_accessor: true,
  }

  let map_proto : Value = Value::Object({
    bag: {
      properties: map_proto_props,
      symbol_properties: {},
      descriptors: map_proto_descs,
      symbol_descriptors: {},
    },
    prototype: @runtime.get_obj_proto(realm_state=Some(realm_state)),
    callable: None,
    class_name: "Map",
    extensible: true,
    arraybuffer_state: None,
  })

  realm_state.map_prototype.val = Some(map_proto)

  // Add Map.prototype[Symbol.iterator] = Map.prototype.entries
  match map_proto {
    Object(data) => {
      @runtime.install_builtin_symbol_method(
        data,
        iterator_sym.id,
        map_proto_props["entries"],
      )
      let tostringtag_sym = well_known_symbols.to_string_tag
      @runtime.install_builtin_symbol_string(data, tostringtag_sym.id, "Map")
    }
    _ => ()
  }

  // Map constructor
  let map_ctor = @runtime.make_interp_method_func_with_context(
    name="Map",
    length=0,
    fn(interp, context, _this_val, args) raise {
      if !context.is_constructing() {
        raise @errors.TypeError(
          message="Constructor Map cannot be invoked without 'new'",
        )
      }
      let new_map : Value = Value::Map(
        @runtime.MapData([], prototype=map_proto),
      )
      let loc = @token.Loc::default()

      // If iterable provided, populate map
      if args.length() > 0 {
        let iterable = args[0]
        if !(match iterable {
            Undefined | Null => true
            _ => false
          }) {
          let adder = interp.get_property(new_map, "set", loc)
          if !@runtime.is_callable(adder) {
            raise @errors.TypeError(
              message="Map.prototype.set is not a function",
            )
          }

          // Get iterator from iterable using Symbol.iterator
          let iterator_sym = well_known_symbols.iterator
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

          let next_method = interp.get_iterator_next_method(iterator, loc)

          // Iterate over the iterator
          while true {
            let iter_result = match
              interp.iterator_step_result(iterator, next_method, loc) {
              None => break
              Some(result) => result
            }
            let value = interp.iterator_result_value(iter_result, loc)
            if !@runtime.is_object_value(value) {
              interp.iterator_close(iterator, loc) catch {
                _ => ()
              }
              raise @errors.TypeError(
                message="Iterator value " +
                  @runtime.to_js_string(value) +
                  " is not an entry object",
              )
            }
            let key = interp.get_computed_property(
              value,
              Value::Number(0.0),
              loc,
            ) catch {
              e => {
                interp.iterator_close(iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
            let val = interp.get_computed_property(
              value,
              Value::Number(1.0),
              loc,
            ) catch {
              e => {
                interp.iterator_close(iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
            let _ = interp.call_value(adder, new_map, [key, val], loc) catch {
              e => {
                interp.iterator_close(iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
          }
        }
      }
      new_map
    },
  )
  // Add prototype property to Map constructor
  match map_ctor {
    Object(data) =>
      @runtime.install_builtin_frozen_data(data, "prototype", map_proto)
    _ => ()
  }
  // Add Map.groupBy static method
  match map_ctor {
    Object(ctor_data) => {
      ctor_data.bag.properties["groupBy"] = @runtime.make_interp_static_func(
        name="groupBy",
        length=2,
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
          let iterator_sym = well_known_symbols.iterator
          let iterator_method = interp.get_computed_property(
            items,
            Symbol(iterator_sym),
            loc,
          )
          let iterator = if @runtime.is_callable(iterator_method) {
            let result = interp.call_value(iterator_method, items, [], loc)
            if !@runtime.is_object_value(result) {
              raise @errors.TypeError(
                message="Result of the Symbol.iterator method is not an object",
              )
            }
            result
          } else {
            raise @errors.TypeError(
              message="\{@runtime.type_of(items)} is not iterable",
            )
          }
          let next_method = interp.get_iterator_next_method(iterator, loc)
          let group_keys : Array[Value] = []
          let group_arrays : Array[Array[Value]] = []
          let mut k = 0
          while true {
            let iter_result = match
              interp.iterator_step_result(iterator, next_method, loc) {
              None => break
              Some(result) => result
            }
            let kvalue = interp.iterator_result_value(iter_result, loc)
            let raw_key = interp.call_value(
              callback,
              Undefined,
              [kvalue, Value::Number(k.to_double())],
              loc,
            ) catch {
              e => {
                interp.iterator_close(iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
            let key = canonicalize_keyed_collection_key(raw_key)
            // Find existing group
            match group_keys.search_by(gk => same_value(gk, key)) {
              Some(found_idx) => group_arrays[found_idx].push(kvalue)
              None => {
                group_keys.push(key)
                group_arrays.push([kvalue])
              }
            }
            k = k + 1
          }
          // Build result Map
          let entries : Array[(Value, Value)] = []
          for i, key in group_keys {
            entries.push((key, @runtime.make_array(group_arrays[i])))
          }
          Value::Map(@runtime.MapData(entries, prototype=map_proto))
        },
      )
      ctor_data.bag.descriptors["groupBy"] = {
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
  env.def_builtin("Map", map_ctor)
  // Set Map.prototype.constructor = Map
  match map_proto {
    Object(data) =>
      @runtime.install_builtin_method(data, "constructor", map_ctor)
    _ => ()
  }
}

///|
/// Setup Set constructor and prototype
fn setup_set_builtins(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  let well_known_symbols = realm_state.well_known_symbols
  let iterator_sym = well_known_symbols.iterator

  // Set.prototype methods
  let set_proto_props : Map[String, Value] = {}

  // Set.prototype.add(value)
  set_proto_props["add"] = @runtime.make_method_func(name="add", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Set(data) => {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        // Check if value already exists using SameValueZero
        if data.values.search_by(v => same_value_zero(v, value)) is Some(_) {
          return this_val
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
  set_proto_props["has"] = @runtime.make_method_func(name="has", length=1, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Value::Set(data) => {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        // Find value using SameValueZero
        Value::Bool(
          data.values.search_by(v => same_value_zero(v, value)) is Some(_),
        )
      }
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.has called on incompatible receiver",
        )
    }
  })

  // Set.prototype.delete(value)
  set_proto_props["delete"] = @runtime.make_method_func(
    name="delete",
    length=1,
    fn(this_val, args) raise {
      match this_val {
        Value::Set(data) => {
          let value = if args.length() > 0 { args[0] } else { Undefined }
          // Find and remove value using SameValueZero
          match data.values.search_by(v => same_value_zero(v, value)) {
            Some(i) => {
              let _ = data.values.remove(i)
              Value::Bool(true)
            }
            None => Value::Bool(false)
          }
        }
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.delete called on incompatible receiver",
          )
      }
    },
  )

  // Set.prototype.clear()
  set_proto_props["clear"] = @runtime.make_method_func(name="clear", length=0, fn(
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
  set_proto_props["forEach"] = @runtime.make_interp_method_func(
    name="forEach",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Value::Set(data) => {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let this_arg = if args.length() > 1 { args[1] } else { Undefined }
          let loc = @token.Loc::default()
          // Iterate over values. Use manual index loop; the callback may mutate
          // data.values via set.delete/set.add. `for x in arr` snapshots initial
          // length and crashes if the array shrinks. We also must not skip the
          // element that shifts into the deleted slot: only advance i when value
          // is still at position i after the callback (§24.2.3.12 live iteration).
          let mut i = 0
          while i < data.values.length() {
            let value = data.values[i]
            let _ = interp.call_value(
              callback,
              this_arg,
              [value, value, this_val],
              loc,
            )
            if i < data.values.length() &&
              same_value_zero(data.values[i], value) {
              i = i + 1
            }
          }
          Undefined
        }
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.forEach called on incompatible receiver",
          )
      }
    },
  )

  // Set.prototype.keys() - returns iterator of values (same as values())
  set_proto_props["keys"] = @runtime.make_method_func(name="keys", length=0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Value::Set(data) => make_set_values_iterator(realm_state, data)
      _ =>
        raise @errors.TypeError(
          message="Method Set.prototype.keys called on incompatible receiver",
        )
    }
  })

  // Set.prototype.values() - returns iterator of values
  set_proto_props["values"] = @runtime.make_method_func(
    name="values",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Set(data) => make_set_values_iterator(realm_state, data)
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.values called on incompatible receiver",
          )
      }
    },
  )

  // Set.prototype.entries() - returns iterator of [value, value] pairs
  set_proto_props["entries"] = @runtime.make_method_func(
    name="entries",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Set(data) => make_set_entries_iterator(realm_state, data)
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.entries called on incompatible receiver",
          )
      }
    },
  )

  // Set.prototype.union(other) - ES2024 §24.2.3.1
  set_proto_props["union"] = @runtime.make_interp_method_func(
    name="union",
    length=1,
    fn(interp, this_val, args) raise {
      let data = match this_val {
        Value::Set(d) => d
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.union called on incompatible receiver",
          )
      }
      let loc = @token.Loc::default()
      let other = if args.length() > 0 { args[0] } else { Undefined }
      let other_rec = get_set_record(interp, other, loc)
      // §24.2.3.1 step 4: Call other.keys() before copying this.[[SetData]] (step 6).
      // keys() is user code that may mutate the receiver; copy must happen after.
      let key_iter = interp.call_value(
        other_rec.keys,
        other_rec.set_object,
        [],
        loc,
      )
      let next_method = interp.get_iterator_next_method(key_iter, loc)
      let result_values : Array[Value] = []
      for v in data.values {
        result_values.push(v)
      }
      while true {
        let iter_result = match
          interp.iterator_step_result(key_iter, next_method, loc) {
          None => break
          Some(r) => r
        }
        let next_val = interp.iterator_result_value(iter_result, loc) catch {
          e => {
            interp.iterator_close(key_iter, loc)
            raise e
          }
        }
        let next_val = canonicalize_keyed_collection_key(next_val)
        if result_values.search_by(v => same_value_zero(v, next_val)) is None {
          result_values.push(next_val)
        }
      }
      Value::Set(
        @runtime.SetData(result_values, prototype=realm_state.get_set_proto()),
      )
    },
  )

  // Set.prototype.intersection(other) - ES2024 §24.2.3.2
  set_proto_props["intersection"] = @runtime.make_interp_method_func(
    name="intersection",
    length=1,
    fn(interp, this_val, args) raise {
      let data = match this_val {
        Value::Set(d) => d
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.intersection called on incompatible receiver",
          )
      }
      let loc = @token.Loc::default()
      let other = if args.length() > 0 { args[0] } else { Undefined }
      let other_rec = get_set_record(interp, other, loc)
      let result_values : Array[Value] = []
      let this_size = data.values.length().to_double()
      if this_size <= other_rec.size {
        // has-path: live index loop over thisData (§24.2.3.2 step 4 — spec iterates
        // the live [[SetData]] List, so elements added by has() must be visited).
        // Don't advance i if has() deleted the current element (it compacts the
        // array, so the element at i+1 shifts to i and must not be skipped).
        let mut i = 0
        while i < data.values.length() {
          let v = data.values[i]
          let has_result = interp.call_value(
            other_rec.has,
            other_rec.set_object,
            [v],
            loc,
          )
          if i < data.values.length() && same_value_zero(data.values[i], v) {
            i = i + 1
          }
          if @runtime.is_truthy(has_result) {
            if result_values.search_by(e => same_value_zero(e, v)) is None {
              result_values.push(v)
            }
          }
        }
      } else {
        // keys-path: iterate other.keys(), include keys also in this
        let key_iter = interp.call_value(
          other_rec.keys,
          other_rec.set_object,
          [],
          loc,
        )
        let next_method = interp.get_iterator_next_method(key_iter, loc)
        while true {
          let iter_result = match
            interp.iterator_step_result(key_iter, next_method, loc) {
            None => break
            Some(r) => r
          }
          let next_val = interp.iterator_result_value(iter_result, loc) catch {
            e => {
              interp.iterator_close(key_iter, loc)
              raise e
            }
          }
          let next_val = canonicalize_keyed_collection_key(next_val)
          // §24.2.3.2 step 6.a.i: skip if already in result (dedup)
          if result_values.search_by(e => same_value_zero(e, next_val)) is None &&
            data.values.search_by(e => same_value_zero(e, next_val)) is Some(_) {
            result_values.push(next_val)
          }
        }
      }
      Value::Set(
        @runtime.SetData(result_values, prototype=realm_state.get_set_proto()),
      )
    },
  )

  // Set.prototype.difference(other) - ES2024 §24.2.3.3
  set_proto_props["difference"] = @runtime.make_interp_method_func(
    name="difference",
    length=1,
    fn(interp, this_val, args) raise {
      let data = match this_val {
        Value::Set(d) => d
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.difference called on incompatible receiver",
          )
      }
      let loc = @token.Loc::default()
      let other = if args.length() > 0 { args[0] } else { Undefined }
      let other_rec = get_set_record(interp, other, loc)
      let result_values : Array[Value] = []
      let this_size = data.values.length().to_double()
      if this_size <= other_rec.size {
        // has-path: live index loop (§24.2.3.3 step 5 iterates the live [[SetData]],
        // so elements added by has() must be visited). Deletion-safe: don't advance
        // i when has() deletes the current element and compacts the array.
        let mut i = 0
        while i < data.values.length() {
          let v = data.values[i]
          let has_result = interp.call_value(
            other_rec.has,
            other_rec.set_object,
            [v],
            loc,
          )
          if i < data.values.length() && same_value_zero(data.values[i], v) {
            i = i + 1
          }
          if !@runtime.is_truthy(has_result) {
            if result_values.search_by(e => same_value_zero(e, v)) is None {
              result_values.push(v)
            }
          }
        }
      } else {
        // keys-path: start with copy of this, remove keys found in other
        for v in data.values {
          result_values.push(v)
        }
        let key_iter = interp.call_value(
          other_rec.keys,
          other_rec.set_object,
          [],
          loc,
        )
        let next_method = interp.get_iterator_next_method(key_iter, loc)
        while true {
          let iter_result = match
            interp.iterator_step_result(key_iter, next_method, loc) {
            None => break
            Some(r) => r
          }
          let next_val = interp.iterator_result_value(iter_result, loc) catch {
            e => {
              interp.iterator_close(key_iter, loc)
              raise e
            }
          }
          let next_val = canonicalize_keyed_collection_key(next_val)
          match result_values.search_by(v => same_value_zero(v, next_val)) {
            Some(i) => {
              let _ = result_values.remove(i)
            }
            None => ()
          }
        }
      }
      Value::Set(
        @runtime.SetData(result_values, prototype=realm_state.get_set_proto()),
      )
    },
  )

  // Set.prototype.symmetricDifference(other) - ES2024 §24.2.3.4
  set_proto_props["symmetricDifference"] = @runtime.make_interp_method_func(
    name="symmetricDifference",
    length=1,
    fn(interp, this_val, args) raise {
      let data = match this_val {
        Value::Set(d) => d
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.symmetricDifference called on incompatible receiver",
          )
      }
      let loc = @token.Loc::default()
      let other = if args.length() > 0 { args[0] } else { Undefined }
      let other_rec = get_set_record(interp, other, loc)
      // §24.2.3.4 step 4: Call other.keys() before copying this.[[SetData]] (step 6).
      let key_iter = interp.call_value(
        other_rec.keys,
        other_rec.set_object,
        [],
        loc,
      )
      let next_method = interp.get_iterator_next_method(key_iter, loc)
      // Start result as copy of this, then toggle membership based on other.keys()
      let result_values : Array[Value] = []
      for v in data.values {
        result_values.push(v)
      }
      while true {
        let iter_result = match
          interp.iterator_step_result(key_iter, next_method, loc) {
          None => break
          Some(r) => r
        }
        let next_val = interp.iterator_result_value(iter_result, loc) catch {
          e => {
            interp.iterator_close(key_iter, loc)
            raise e
          }
        }
        let next_val = canonicalize_keyed_collection_key(next_val)
        match data.values.search_by(v => same_value_zero(v, next_val)) {
          Some(_) =>
            // key is in this: remove from result
            match result_values.search_by(v => same_value_zero(v, next_val)) {
              Some(i) => {
                let _ = result_values.remove(i)
              }
              None => ()
            }
          None =>
            // key not in this: add to result if not already present
            if result_values.search_by(v => same_value_zero(v, next_val))
              is None {
              result_values.push(next_val)
            }
        }
      }
      Value::Set(
        @runtime.SetData(result_values, prototype=realm_state.get_set_proto()),
      )
    },
  )

  // Set.prototype.isSubsetOf(other) - ES2024 §24.2.3.5
  set_proto_props["isSubsetOf"] = @runtime.make_interp_method_func(
    name="isSubsetOf",
    length=1,
    fn(interp, this_val, args) raise {
      let data = match this_val {
        Value::Set(d) => d
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.isSubsetOf called on incompatible receiver",
          )
      }
      let loc = @token.Loc::default()
      let other = if args.length() > 0 { args[0] } else { Undefined }
      let other_rec = get_set_record(interp, other, loc)
      let this_size = data.values.length().to_double()
      if this_size > other_rec.size {
        return Value::Bool(false)
      }
      // Live index loop (§24.2.3.5 step 5 iterates the live [[SetData]], so
      // elements added by has() must be checked — they may not be in other).
      // Deletion-safe: don't advance i when has() deletes the current element.
      let mut i = 0
      while i < data.values.length() {
        let v = data.values[i]
        let has_result = interp.call_value(
          other_rec.has,
          other_rec.set_object,
          [v],
          loc,
        )
        if i < data.values.length() && same_value_zero(data.values[i], v) {
          i = i + 1
        }
        if !@runtime.is_truthy(has_result) {
          return Value::Bool(false)
        }
      }
      Value::Bool(true)
    },
  )

  // Set.prototype.isSupersetOf(other) - ES2024 §24.2.3.6
  set_proto_props["isSupersetOf"] = @runtime.make_interp_method_func(
    name="isSupersetOf",
    length=1,
    fn(interp, this_val, args) raise {
      let data = match this_val {
        Value::Set(d) => d
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.isSupersetOf called on incompatible receiver",
          )
      }
      let loc = @token.Loc::default()
      let other = if args.length() > 0 { args[0] } else { Undefined }
      let other_rec = get_set_record(interp, other, loc)
      let this_size = data.values.length().to_double()
      if this_size < other_rec.size {
        return Value::Bool(false)
      }
      let key_iter = interp.call_value(
        other_rec.keys,
        other_rec.set_object,
        [],
        loc,
      )
      let next_method = interp.get_iterator_next_method(key_iter, loc)
      while true {
        let iter_result = match
          interp.iterator_step_result(key_iter, next_method, loc) {
          None => break
          Some(r) => r
        }
        let next_val = interp.iterator_result_value(iter_result, loc) catch {
          e => {
            interp.iterator_close(key_iter, loc)
            raise e
          }
        }
        let next_val = canonicalize_keyed_collection_key(next_val)
        if data.values.search_by(v => same_value_zero(v, next_val)) is None {
          interp.iterator_close(key_iter, loc)
          return Value::Bool(false)
        }
      }
      Value::Bool(true)
    },
  )

  // Set.prototype.isDisjointFrom(other) - ES2024 §24.2.3.7
  set_proto_props["isDisjointFrom"] = @runtime.make_interp_method_func(
    name="isDisjointFrom",
    length=1,
    fn(interp, this_val, args) raise {
      let data = match this_val {
        Value::Set(d) => d
        _ =>
          raise @errors.TypeError(
            message="Method Set.prototype.isDisjointFrom called on incompatible receiver",
          )
      }
      let loc = @token.Loc::default()
      let other = if args.length() > 0 { args[0] } else { Undefined }
      let other_rec = get_set_record(interp, other, loc)
      let this_size = data.values.length().to_double()
      if this_size <= other_rec.size {
        // has-path: live index loop (§24.2.3.7 step 3 iterates the live [[SetData]],
        // so elements added by has() must be checked). Deletion-safe: don't advance
        // i when has() deletes the current element and compacts the array.
        let mut i = 0
        while i < data.values.length() {
          let v = data.values[i]
          let has_result = interp.call_value(
            other_rec.has,
            other_rec.set_object,
            [v],
            loc,
          )
          if i < data.values.length() && same_value_zero(data.values[i], v) {
            i = i + 1
          }
          if @runtime.is_truthy(has_result) {
            return Value::Bool(false)
          }
        }
      } else {
        // keys-path: iterate other.keys(); return false if any key is in this
        let key_iter = interp.call_value(
          other_rec.keys,
          other_rec.set_object,
          [],
          loc,
        )
        let next_method = interp.get_iterator_next_method(key_iter, loc)
        while true {
          let iter_result = match
            interp.iterator_step_result(key_iter, next_method, loc) {
            None => break
            Some(r) => r
          }
          let next_val = interp.iterator_result_value(iter_result, loc) catch {
            e => {
              interp.iterator_close(key_iter, loc)
              raise e
            }
          }
          let next_val = canonicalize_keyed_collection_key(next_val)
          if data.values.search_by(v => same_value_zero(v, next_val)) is Some(_) {
            interp.iterator_close(key_iter, loc)
            return Value::Bool(false)
          }
        }
      }
      Value::Bool(true)
    },
  )

  // Non-enumerable descriptors for Set.prototype methods
  let method_desc = @runtime.builtin_method_desc()
  let set_proto_descs : Map[String, PropDescriptor] = {}
  set_proto_descs["add"] = method_desc
  set_proto_descs["has"] = method_desc
  set_proto_descs["delete"] = method_desc
  set_proto_descs["clear"] = method_desc
  set_proto_descs["forEach"] = method_desc
  set_proto_descs["keys"] = method_desc
  set_proto_descs["values"] = method_desc
  set_proto_descs["entries"] = method_desc
  set_proto_descs["union"] = method_desc
  set_proto_descs["intersection"] = method_desc
  set_proto_descs["difference"] = method_desc
  set_proto_descs["symmetricDifference"] = method_desc
  set_proto_descs["isSubsetOf"] = method_desc
  set_proto_descs["isSupersetOf"] = method_desc
  set_proto_descs["isDisjointFrom"] = method_desc

  // Create size getter for Set.prototype (per spec, size is an accessor property)
  let set_size_getter = @runtime.make_method_func(name="get size", length=0, fn(
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
    is_accessor: true,
  }

  let set_proto : Value = Value::Object({
    bag: {
      properties: set_proto_props,
      symbol_properties: {},
      descriptors: set_proto_descs,
      symbol_descriptors: {},
    },
    prototype: @runtime.get_obj_proto(realm_state=Some(realm_state)),
    callable: None,
    class_name: "Set",
    extensible: true,
    arraybuffer_state: None,
  })

  realm_state.set_prototype.val = Some(set_proto)

  // Add Set.prototype[Symbol.iterator] = Set.prototype.values
  match set_proto {
    Object(data) => {
      @runtime.install_builtin_symbol_method(
        data,
        iterator_sym.id,
        set_proto_props["values"],
      )
      let tostringtag_sym = well_known_symbols.to_string_tag
      @runtime.install_builtin_symbol_string(data, tostringtag_sym.id, "Set")
    }
    _ => ()
  }

  // Set constructor
  let set_ctor = @runtime.make_interp_method_func_with_context(
    name="Set",
    length=0,
    fn(interp, context, _this_val, args) raise {
      if !context.is_constructing() {
        raise @errors.TypeError(
          message="Constructor Set cannot be invoked without 'new'",
        )
      }
      let new_set : Value = Value::Set(
        @runtime.SetData([], prototype=set_proto),
      )
      let loc = @token.Loc::default()

      // If iterable provided, populate set
      if args.length() > 0 {
        let iterable = args[0]
        if !(match iterable {
            Undefined | Null => true
            _ => false
          }) {
          let adder = interp.get_property(new_set, "add", loc)
          if !@runtime.is_callable(adder) {
            raise @errors.TypeError(
              message="Set.prototype.add is not a function",
            )
          }

          // Get iterator from iterable using Symbol.iterator
          let iterator_sym = well_known_symbols.iterator
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

          let next_method = interp.get_iterator_next_method(iterator, loc)

          // Iterate over the iterator
          while true {
            let iter_result = match
              interp.iterator_step_result(iterator, next_method, loc) {
              None => break
              Some(result) => result
            }
            let value = interp.iterator_result_value(iter_result, loc)
            let _ = interp.call_value(adder, new_set, [value], loc) catch {
              e => {
                interp.iterator_close(iterator, loc) catch {
                  _ => ()
                }
                raise e
              }
            }
          }
        }
      }
      new_set
    },
  )
  // Add prototype property to Set constructor
  match set_ctor {
    Object(data) =>
      @runtime.install_builtin_frozen_data(data, "prototype", set_proto)
    _ => ()
  }
  env.def_builtin("Set", set_ctor)
  // Set Set.prototype.constructor = Set
  match set_proto {
    Object(data) =>
      @runtime.install_builtin_method(data, "constructor", set_ctor)
    _ => ()
  }
}

///|
/// Get or create the realm-owned %MapIteratorPrototype%
fn get_map_iterator_proto(realm_state : @runtime.RealmState) -> Value {
  let well_known_symbols = realm_state.well_known_symbols
  match realm_state.runtime_iterator_prototypes.map_iterator_proto.val {
    Some(proto) => proto
    None => {
      let iterator_sym = well_known_symbols.iterator
      let tostringtag_sym = well_known_symbols.to_string_tag
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
        is_accessor: false,
      }
      // Add [Symbol.iterator] that returns the iterator itself
      proto_sym_props[iterator_sym.id] = @runtime.make_method_func(
        name="[Symbol.iterator]",
        length=0,
        realm_state=Some(realm_state),
        fn(this_val, _args) { this_val },
      )
      proto_props["next"] = @runtime.make_method_func(
        name="next",
        length=0,
        realm_state=Some(realm_state),
        fn(this_val, _args) raise { map_iterator_next(this_val) },
      )
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
              is_accessor: false,
            },
          },
          symbol_descriptors: proto_sym_descs,
        },
        prototype: realm_state.get_iterator_proto(),
        callable: None,
        class_name: "Map Iterator",
        extensible: true,
        arraybuffer_state: None,
      })
      realm_state.runtime_iterator_prototypes.map_iterator_proto.val = Some(
        proto,
      )
      proto
    }
  }
}

///|
/// Create a Map keys iterator
fn make_map_keys_iterator(
  realm_state : @runtime.RealmState,
  map_data : MapData,
) -> Value {
  make_map_iterator(realm_state, map_data, MAP_ITERATOR_KIND_KEY)
}

///|
/// Create a Map values iterator
fn make_map_values_iterator(
  realm_state : @runtime.RealmState,
  map_data : MapData,
) -> Value {
  make_map_iterator(realm_state, map_data, MAP_ITERATOR_KIND_VALUE)
}

///|
/// Create a Map entries iterator
fn make_map_entries_iterator(
  realm_state : @runtime.RealmState,
  map_data : MapData,
) -> Value {
  make_map_iterator(realm_state, map_data, MAP_ITERATOR_KIND_ENTRY)
}

///|
/// Get or create the realm-owned %SetIteratorPrototype%
fn get_set_iterator_proto(realm_state : @runtime.RealmState) -> Value {
  let well_known_symbols = realm_state.well_known_symbols
  match realm_state.runtime_iterator_prototypes.set_iterator_proto.val {
    Some(proto) => proto
    None => {
      let iterator_sym = well_known_symbols.iterator
      let tostringtag_sym = well_known_symbols.to_string_tag
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
        is_accessor: false,
      }
      proto_sym_props[iterator_sym.id] = @runtime.make_method_func(
        name="[Symbol.iterator]",
        length=0,
        realm_state=Some(realm_state),
        fn(this_val, _args) { this_val },
      )
      proto_props["next"] = @runtime.make_method_func(
        name="next",
        length=0,
        realm_state=Some(realm_state),
        fn(_this_val, _args) raise {
          raise @errors.TypeError(
            message="Set Iterator.prototype.next requires that |this| be a Set Iterator",
          )
        },
      )
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
              is_accessor: false,
            },
          },
          symbol_descriptors: proto_sym_descs,
        },
        prototype: realm_state.get_iterator_proto(),
        callable: None,
        class_name: "Set Iterator",
        extensible: true,
        arraybuffer_state: None,
      })
      realm_state.runtime_iterator_prototypes.set_iterator_proto.val = Some(
        proto,
      )
      proto
    }
  }
}

///|
/// Create a Set values iterator
fn make_set_values_iterator(
  realm_state : @runtime.RealmState,
  set_data : SetData,
) -> Value {
  let set_iter_proto = get_set_iterator_proto(realm_state)
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
          is_accessor: false,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
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
            arraybuffer_state: None,
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
            arraybuffer_state: None,
          })
        }
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = @runtime.stamp_function_realm(
    next_method,
    realm_state=Some(realm_state),
  )
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
    arraybuffer_state: None,
  })
}

///|
/// Create a Set entries iterator (returns [value, value] pairs)
fn make_set_entries_iterator(
  realm_state : @runtime.RealmState,
  set_data : SetData,
) -> Value {
  let set_iter_proto = get_set_iterator_proto(realm_state)
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
          is_accessor: false,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
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
            arraybuffer_state: None,
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
            arraybuffer_state: None,
          })
        }
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = @runtime.stamp_function_realm(
    next_method,
    realm_state=Some(realm_state),
  )
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
    arraybuffer_state: None,
  })
}

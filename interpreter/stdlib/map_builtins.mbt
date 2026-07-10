///|
/// Map built-in constructor, prototype methods, and iterator factories.

///|
const MAP_ITERATOR_NAME = "Map Iterator"

///|
const MAP_ITERATOR_KIND_KEY = 0

///|
const MAP_ITERATOR_KIND_VALUE = 1

///|
const MAP_ITERATOR_KIND_ENTRY = 2

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
    keyed_collection_iterator_type_error(MAP_ITERATOR_NAME)
  }
}

///|
fn map_iterator_next(this_val : Value) -> Value raise Error {
  match this_val {
    Object(data) => {
      guard data.class_name == MAP_ITERATOR_NAME else {
        return keyed_collection_iterator_type_error(MAP_ITERATOR_NAME)
      }
      let (current, iterated_map, kind) = match
        read_keyed_collection_iterator_state(data, map_iterator_slots) {
        Some(state) => state
        None => return keyed_collection_iterator_type_error(MAP_ITERATOR_NAME)
      }
      match iterated_map {
        Undefined => @runtime.create_iter_result(Undefined, true)
        Map(map_data) => {
          guard current < map_data.entries.length() else {
            @runtime.detach_keyed_collection_iterator_target(
              data,
              map_iterator_slots.target,
            )
            return @runtime.create_iter_result(Undefined, true)
          }
          let (key, value) = map_data.entries[current]
          @runtime.set_keyed_collection_iterator_next_index(
            data,
            map_iterator_slots.next_index,
            Number((current + 1).to_double()),
          )
          let result_value = map_iterator_result_value(kind, key, value)
          @runtime.create_iter_result(result_value, false)
        }
        _ => keyed_collection_iterator_type_error(MAP_ITERATOR_NAME)
      }
    }
    _ => keyed_collection_iterator_type_error(MAP_ITERATOR_NAME)
  }
}

///|
fn make_map_iterator(
  realm_state : @runtime.RealmState,
  map_data : MapData,
  kind : Int,
) -> Value {
  make_keyed_collection_iterator(
    get_map_iterator_proto(realm_state),
    MAP_ITERATOR_NAME,
    map_iterator_slots,
    Value::Map(map_data),
    kind,
  )
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
      internal_slots: {},
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
        @runtime.MapData([], prototype=Some(map_proto)),
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
              interp.iterator_close_throw(iterator, loc)
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
                interp.iterator_close_throw(iterator, loc)
                raise e
              }
            }
            let val = interp.get_computed_property(
              value,
              Value::Number(1.0),
              loc,
            ) catch {
              e => {
                interp.iterator_close_throw(iterator, loc)
                raise e
              }
            }
            let _ = interp.call_value(adder, new_map, [key, val], loc) catch {
              e => {
                interp.iterator_close_throw(iterator, loc)
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
                interp.iterator_close_throw(iterator, loc)
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
          Value::Map(@runtime.MapData(entries, prototype=Some(map_proto)))
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
/// Get or create the realm-owned %MapIteratorPrototype%
fn get_map_iterator_proto(realm_state : @runtime.RealmState) -> Value {
  get_or_create_keyed_collection_iterator_proto(
    realm_state.runtime_iterator_prototypes.map_iterator_proto,
    realm_state,
    MAP_ITERATOR_NAME,
    map_iterator_next,
  )
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

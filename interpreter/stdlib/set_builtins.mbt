///|
/// Set built-in constructor, prototype methods, and iterator factories.

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
// Engine-private negative symbol IDs for Set Iterator internal slots.
const SET_ITERATOR_NEXT_INDEX_SYMBOL_ID = -133

///|
const SET_ITERATOR_TARGET_SYMBOL_ID = -134

///|
const SET_ITERATOR_KIND_SYMBOL_ID = -135

///|
const SET_ITERATOR_KIND_VALUES = 0

///|
const SET_ITERATOR_KIND_ENTRIES = 1

///|
fn set_data_effective_size(data : SetData) -> Double {
  let ts_count = match data.tombstones {
    None => 0
    Some(ts) => ts.length()
  }
  (data.values.length() - ts_count).to_double()
}

///|
fn set_data_contains_live(data : SetData, value : Value) -> Bool {
  match data.tombstones {
    None => data.values.search_by(v => same_value_zero(v, value)) is Some(_)
    Some(ts) => {
      let mut found = false
      for i, v in data.values {
        if !ts.contains(i) && same_value_zero(v, value) {
          found = true
          break
        }
      }
      found
    }
  }
}

///|
fn compact_set_tombstones(data : SetData) -> Unit {
  match data.tombstones {
    None => ()
    Some(ts) => {
      let indices = ts.to_array()
      indices.sort_by(fn(a, b) { b - a })
      for i in indices {
        let _ = data.values.remove(i)
      }
      data.tombstones = None
    }
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
        // Only skip if the value exists at a non-tombstoned index. A tombstoned
        // slot is logically deleted, so delete+add during forEach must append.
        let already_live = match data.tombstones {
          None =>
            data.values.search_by(v => same_value_zero(v, value)) is Some(_)
          Some(ts) => {
            let mut found = false
            for i, v in data.values {
              if !ts.contains(i) && same_value_zero(v, value) {
                found = true
                break
              }
            }
            found
          }
        }
        if already_live {
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
        // Skip tombstoned indices: a value deleted during active forEach is not "in" the set.
        let found = match data.tombstones {
          None =>
            data.values.search_by(v => same_value_zero(v, value)) is Some(_)
          Some(ts) => {
            let mut found = false
            for i, v in data.values {
              if !ts.contains(i) && same_value_zero(v, value) {
                found = true
                break
              }
            }
            found
          }
        }
        Value::Bool(found)
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
          // Tombstone when iteration is active (tombstones is Some) to keep
          // array indices stable for forEach and for..of cursors. Compact
          // immediately when tombstones is None (no active or pending iteration).
          if data.tombstones is Some(_) {
            // Search only non-tombstoned slots.
            let mut found_idx : Int? = None
            match data.tombstones {
              None =>
                for i, v in data.values {
                  if same_value_zero(v, value) {
                    found_idx = Some(i)
                    break
                  }
                }
              Some(ts) =>
                for i, v in data.values {
                  if !ts.contains(i) && same_value_zero(v, value) {
                    found_idx = Some(i)
                    break
                  }
                }
            }
            match found_idx {
              None => Value::Bool(false)
              Some(i) => {
                let ts = match data.tombstones {
                  None => {
                    let ts : @set.Set[Int] = @set.Set::default()
                    data.tombstones = Some(ts)
                    ts
                  }
                  Some(ts) => ts
                }
                ts.add(i)
                Value::Bool(true)
              }
            }
          } else {
            // No active iteration: compact normally.
            match data.values.search_by(v => same_value_zero(v, value)) {
              Some(i) => {
                let _ = data.values.remove(i)
                Value::Bool(true)
              }
              None => Value::Bool(false)
            }
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
        if data.tombstones is Some(_) {
          // Iteration active (forEach or for..of): tombstone every current slot
          // so cursor indices stay stable. Elements added after clear() append
          // at higher indices and are visited normally by existing cursors.
          let n = data.values.length()
          if n > 0 {
            let ts = match data.tombstones {
              None => {
                let ts : @set.Set[Int] = @set.Set::default()
                data.tombstones = Some(ts)
                ts
              }
              Some(ts) => ts
            }
            for i in 0..<n {
              ts.add(i)
            }
          }
        } else {
          data.values.clear()
          data.tombstones = None
        }
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
          // §24.2.3.12: iteration is over the live [[SetData]] list. delete()
          // tombstones instead of compacting while tombstones is Some, so
          // array indices stay stable. add() appends; the new slot is visited
          // when the cursor reaches it.
          //
          // tombstones_pre_existed: true when tombstones was already Some (a
          // for..of or outer forEach was already active). We share the tombstone
          // set but do NOT compact on exit — the scope that entered tombstone
          // mode is responsible for compaction.
          // iteration_depth: counted per-forEach so that a nested for..of that
          // exhausts inside this callback can detect the active forEach and skip
          // compaction (compacting mid-forEach would corrupt our cursor).
          let tombstones_pre_existed = data.tombstones is Some(_)
          if !tombstones_pre_existed {
            data.tombstones = Some(@set.Set::default())
          }
          data.iteration_depth += 1
          let result : Result[Value, Error] = try {
            let mut i = 0
            while i < data.values.length() {
              let is_tombstoned = match data.tombstones {
                None => false
                Some(ts) => ts.contains(i)
              }
              if !is_tombstoned {
                let value = data.values[i]
                let _ = interp.call_value(
                  callback,
                  this_arg,
                  [value, value, this_val],
                  loc,
                )
              }
              // Always advance: values never compact during iteration.
              i += 1
            }
            Ok(Undefined)
          } catch {
            e => Err(e)
          }
          data.iteration_depth -= 1
          // Compact tombstones only when we entered tombstone mode (not
          // inherited). Preserves cursor stability for any outer for..of.
          if !tombstones_pre_existed {
            compact_set_tombstones(data)
          }
          match result {
            Ok(v) => v
            Err(e) => raise e
          }
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
      for i, v in data.values {
        let is_tombstoned = match data.tombstones {
          None => false
          Some(ts) => ts.contains(i)
        }
        if !is_tombstoned {
          result_values.push(v)
        }
      }
      while true {
        let iter_result = match
          interp.iterator_step_result(key_iter, next_method, loc) {
          None => break
          Some(r) => r
        }
        let next_val = interp.iterator_result_value(iter_result, loc) catch {
          e => {
            interp.iterator_close_throw(key_iter, loc)
            raise e
          }
        }
        let next_val = canonicalize_keyed_collection_key(next_val)
        if result_values.search_by(v => same_value_zero(v, next_val)) is None {
          result_values.push(next_val)
        }
      }
      Value::Set(
        @runtime.SetData(
          result_values,
          prototype=Some(realm_state.get_set_proto()),
        ),
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
      let this_size = set_data_effective_size(data)
      if this_size <= other_rec.size {
        // has-path: live index loop over thisData (§24.2.3.2 step 4 — spec iterates
        // the live [[SetData]] List, so elements added by has() must be visited).
        // Don't advance i if has() deleted the current element (it compacts the
        // array, so the element at i+1 shifts to i and must not be skipped).
        let mut i = 0
        while i < data.values.length() {
          let is_tombstoned = match data.tombstones {
            None => false
            Some(ts) => ts.contains(i)
          }
          if is_tombstoned {
            i = i + 1
          } else {
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
              interp.iterator_close_throw(key_iter, loc)
              raise e
            }
          }
          let next_val = canonicalize_keyed_collection_key(next_val)
          // §24.2.3.2 step 6.a.i: skip if already in result (dedup)
          if result_values.search_by(e => same_value_zero(e, next_val)) is None &&
            set_data_contains_live(data, next_val) {
            result_values.push(next_val)
          }
        }
      }
      Value::Set(
        @runtime.SetData(
          result_values,
          prototype=Some(realm_state.get_set_proto()),
        ),
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
      let this_size = set_data_effective_size(data)
      if this_size <= other_rec.size {
        // has-path: live index loop (§24.2.3.3 step 5 iterates the live [[SetData]],
        // so elements added by has() must be visited). Deletion-safe: don't advance
        // i when has() deletes the current element and compacts the array.
        let mut i = 0
        while i < data.values.length() {
          let is_tombstoned = match data.tombstones {
            None => false
            Some(ts) => ts.contains(i)
          }
          if is_tombstoned {
            i = i + 1
          } else {
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
        }
      } else {
        // keys-path: start with copy of live elements, remove keys found in other
        for i, v in data.values {
          let is_tombstoned = match data.tombstones {
            None => false
            Some(ts) => ts.contains(i)
          }
          if !is_tombstoned {
            result_values.push(v)
          }
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
              interp.iterator_close_throw(key_iter, loc)
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
        @runtime.SetData(
          result_values,
          prototype=Some(realm_state.get_set_proto()),
        ),
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
      // Start result as copy of live elements, then toggle membership based on other.keys()
      let result_values : Array[Value] = []
      for i, v in data.values {
        let is_tombstoned = match data.tombstones {
          None => false
          Some(ts) => ts.contains(i)
        }
        if !is_tombstoned {
          result_values.push(v)
        }
      }
      while true {
        let iter_result = match
          interp.iterator_step_result(key_iter, next_method, loc) {
          None => break
          Some(r) => r
        }
        let next_val = interp.iterator_result_value(iter_result, loc) catch {
          e => {
            interp.iterator_close_throw(key_iter, loc)
            raise e
          }
        }
        let next_val = canonicalize_keyed_collection_key(next_val)
        if set_data_contains_live(data, next_val) {
          // key is live in this: remove from result
          match result_values.search_by(v => same_value_zero(v, next_val)) {
            Some(i) => {
              let _ = result_values.remove(i)
            }
            None => ()
          }
          // key not in this (or tombstoned): add to result if not already present
        } else if result_values.search_by(v => same_value_zero(v, next_val))
          is None {
          result_values.push(next_val)
        }
      }
      Value::Set(
        @runtime.SetData(
          result_values,
          prototype=Some(realm_state.get_set_proto()),
        ),
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
      let this_size = set_data_effective_size(data)
      if this_size > other_rec.size {
        return Value::Bool(false)
      }
      // Live index loop (§24.2.3.5 step 5 iterates the live [[SetData]], so
      // elements added by has() must be checked — they may not be in other).
      // Deletion-safe: don't advance i when has() deletes the current element.
      let mut i = 0
      while i < data.values.length() {
        let is_tombstoned = match data.tombstones {
          None => false
          Some(ts) => ts.contains(i)
        }
        if is_tombstoned {
          i = i + 1
        } else {
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
      let this_size = set_data_effective_size(data)
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
            interp.iterator_close_throw(key_iter, loc)
            raise e
          }
        }
        let next_val = canonicalize_keyed_collection_key(next_val)
        if !set_data_contains_live(data, next_val) {
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
      let this_size = set_data_effective_size(data)
      if this_size <= other_rec.size {
        // has-path: live index loop (§24.2.3.7 step 3 iterates the live [[SetData]],
        // so elements added by has() must be checked). Deletion-safe: don't advance
        // i when has() deletes the current element and compacts the array.
        let mut i = 0
        while i < data.values.length() {
          let is_tombstoned = match data.tombstones {
            None => false
            Some(ts) => ts.contains(i)
          }
          if is_tombstoned {
            i = i + 1
          } else {
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
        }
      } else {
        // keys-path: iterate other.keys(); return false if any key is live in this
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
              interp.iterator_close_throw(key_iter, loc)
              raise e
            }
          }
          let next_val = canonicalize_keyed_collection_key(next_val)
          if set_data_contains_live(data, next_val) {
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
      Value::Set(data) => {
        let tombstone_count = match data.tombstones {
          None => 0
          Some(ts) => ts.length()
        }
        Value::Number((data.values.length() - tombstone_count).to_double())
      }
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
      internal_slots: {},
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
        @runtime.SetData([], prototype=Some(set_proto)),
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
                interp.iterator_close_throw(iterator, loc)
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
fn set_iterator_type_error() -> Value raise Error {
  raise @errors.TypeError(
    message="Set Iterator.prototype.next requires that |this| be a Set Iterator",
  )
}

///|
/// §23.2.5.2.1 %SetIteratorPrototype%.next
fn set_iterator_next(this_val : Value) -> Value raise Error {
  match this_val {
    Object(data) => {
      guard data.class_name == "Set Iterator" else {
        return set_iterator_type_error()
      }
      let current = match
        data.bag.symbol_properties.get(SET_ITERATOR_NEXT_INDEX_SYMBOL_ID) {
        Some(Number(n)) => n.to_int()
        _ => return set_iterator_type_error()
      }
      let kind = match
        data.bag.symbol_properties.get(SET_ITERATOR_KIND_SYMBOL_ID) {
        Some(Number(k)) => k.to_int()
        _ => return set_iterator_type_error()
      }
      // §23.2.5.2.1 step 7: [[IteratedSet]] undefined → already done
      match data.bag.symbol_properties.get(SET_ITERATOR_TARGET_SYMBOL_ID) {
        None => return set_iterator_type_error()
        Some(Undefined) => return @runtime.create_iter_result(Undefined, true)
        Some(Set(set_data)) => {
          // tombstone mode was entered at make_set_iterator so that delete/clear
          // tombstone instead of compacting while this iterator is live.
          // Skip tombstoned slots (entries deleted during live iteration).
          let mut idx = current
          while idx < set_data.values.length() {
            let is_tomb = match set_data.tombstones {
              None => false
              Some(ts) => ts.contains(idx)
            }
            if is_tomb {
              idx += 1
            } else {
              break
            }
          }
          if idx < set_data.values.length() {
            let value = set_data.values[idx]
            data.bag.symbol_properties[SET_ITERATOR_NEXT_INDEX_SYMBOL_ID] = Value::Number(
              (idx + 1).to_double(),
            )
            let result_value = if kind == SET_ITERATOR_KIND_ENTRIES {
              @runtime.make_array([value, value])
            } else {
              value
            }
            @runtime.create_iter_result(result_value, false)
          } else {
            // §23.2.5.2.1 step 12: set [[IteratedSet]] to undefined (done flag).
            // Do NOT compact here. Multiple live iterators share the same tombstone
            // set and compact at the same-time compacting would shift values[] indices,
            // corrupting any other iterator's stored numeric cursor. Tombstone cleanup
            // is the responsibility of forEach when it exits tombstone mode
            // (tombstones_pre_existed=false at forEach entry). Until then, tombstones
            // persist — size is bounded by the count of deleted entries (≤ values.length).
            data.bag.symbol_properties[SET_ITERATOR_TARGET_SYMBOL_ID] = Undefined
            @runtime.create_iter_result(Undefined, true)
          }
        }
        _ => set_iterator_type_error()
      }
    }
    _ => set_iterator_type_error()
  }
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
        fn(this_val, _args) raise { set_iterator_next(this_val) },
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
          internal_slots: {},
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
/// Create a Set iterator using internal slots (§23.2.5.1 CreateSetIterator).
/// kind: SET_ITERATOR_KIND_VALUES or SET_ITERATOR_KIND_ENTRIES.
/// next() lives on %SetIteratorPrototype%; each instance holds [[SetNextIndex]],
/// [[IteratedSet]], and [[SetIterationKind]] as hidden symbol slots.
/// Entering tombstone mode here (tombstones=Some) ensures that delete/clear
/// tombstone instead of compacting while any for..of is live.
fn make_set_iterator(
  realm_state : @runtime.RealmState,
  set_data : SetData,
  kind : Int,
) -> Value {
  // Enter tombstone mode so delete/clear tombstone (not compact) during for..of.
  if set_data.tombstones is None {
    set_data.tombstones = Some(@set.Set::default())
  }
  let set_iter_proto = get_set_iterator_proto(realm_state)
  let iter_sym_props : Map[Int, Value] = {}
  iter_sym_props[SET_ITERATOR_NEXT_INDEX_SYMBOL_ID] = Value::Number(0.0)
  iter_sym_props[SET_ITERATOR_TARGET_SYMBOL_ID] = Value::Set(set_data)
  iter_sym_props[SET_ITERATOR_KIND_SYMBOL_ID] = Value::Number(kind.to_double())
  let iter_sym_descs : Map[Int, PropDescriptor] = {}
  let slot_desc = map_iterator_internal_slot_descriptor()
  iter_sym_descs[SET_ITERATOR_NEXT_INDEX_SYMBOL_ID] = slot_desc
  iter_sym_descs[SET_ITERATOR_TARGET_SYMBOL_ID] = slot_desc
  iter_sym_descs[SET_ITERATOR_KIND_SYMBOL_ID] = slot_desc
  Value::Object({
    bag: {
      properties: {},
      symbol_properties: iter_sym_props,
      descriptors: {},
      symbol_descriptors: iter_sym_descs,
      internal_slots: {},
    },
    prototype: set_iter_proto,
    callable: None,
    class_name: "Set Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn make_set_values_iterator(
  realm_state : @runtime.RealmState,
  set_data : SetData,
) -> Value {
  make_set_iterator(realm_state, set_data, SET_ITERATOR_KIND_VALUES)
}

///|
fn make_set_entries_iterator(
  realm_state : @runtime.RealmState,
  set_data : SetData,
) -> Value {
  make_set_iterator(realm_state, set_data, SET_ITERATOR_KIND_ENTRIES)
}

///|
const JS_MAX_SAFE_INTEGER_I64 = 9007199254740991L

///|
const JS_MAX_SAFE_INTEGER_DOUBLE = 9007199254740991.0

///|
const JS_MAX_SAFE_INTEGER_EXCLUSIVE_DOUBLE = 9007199254740992.0

///|
const JS_MAX_ARRAY_LENGTH_I64 = 4294967295L

///|
const ARRAY_DENSE_MATERIALIZE_LIMIT_I64 = 10000000L

///|
/// Classification of an array-indexed lookup per ES2024 §10.1.5
/// OrdinaryGetOwnProperty. `Present` subsumes both "dense element, no
/// descriptor" and "own data descriptor" — data descriptors store
/// their value in `data.elements[i]`, not in the descriptor itself
/// (verified via `array_define_own_property:920`).
priv enum ArrayIndexHit {
  Present(Value)
  Hole
  OutOfRange
  OwnAccessor(Value?)
}

///|
/// Classify an array-indexed lookup without invoking any getter or
/// walking the prototype chain. Caller decides what to do with each
/// case (see `get_array_like_element_interp`, `has_array_like_element`,
/// and `Interpreter::get_property`).
fn array_index_lookup_result(data : ArrayData, i : Int) -> ArrayIndexHit {
  let key = i.to_string()
  match data.bag.descriptors.get(key) {
    Some(desc) =>
      if desc.is_accessor {
        OwnAccessor(desc.getter)
      } else if i >= 0 && i < data.elements.length() {
        Present(data.elements[i])
      } else {
        match data.bag.properties.get(key) {
          Some(v) => Present(v)
          None => OutOfRange
        }
      }
    None =>
      if i < 0 {
        OutOfRange
      } else if i < data.elements.length() {
        // Defensive read: `data.holes` is authoritative only when the
        // dense slot itself is `Undefined` (Phase 3 padding semantics
        // — Array(n), a.length=N, sparse assignment). A non-Undefined
        // value here means some future direct `data.elements` mutation
        // wrote to the slot without updating holes; trust the value
        // rather than the stale marker.
        //
        // An explicit `undefined` cannot be distinguished here, so
        // reordering/writing mutators must maintain `data.holes` when
        // moving values or materializing holes (issue #123).
        let v = data.elements[i]
        if data.holes.contains(i) && v is Undefined {
          Hole
        } else {
          Present(v)
        }
      } else if data.holes.contains(i) {
        Hole
      } else {
        match data.bag.properties.get(key) {
          Some(v) => Present(v)
          None => OutOfRange
        }
      }
  }
}

///|
fn array_index_lookup_result64(
  data : ArrayData,
  index : Int64,
) -> ArrayIndexHit {
  if index < 0L {
    return OutOfRange
  }
  if index <= 0x7FFFFFFFL {
    return array_index_lookup_result(data, index.to_int())
  }
  let key = index.to_string()
  match data.bag.descriptors.get(key) {
    Some(desc) =>
      if desc.is_accessor {
        OwnAccessor(desc.getter)
      } else {
        match data.bag.properties.get(key) {
          Some(v) => Present(v)
          None => OutOfRange
        }
      }
    None =>
      match data.bag.properties.get(key) {
        Some(v) => Present(v)
        None => OutOfRange
      }
  }
}

///|
pub fn flatten_array_val(
  elements : Array[Value],
  depth : Int,
  result : Array[Value],
) -> Unit {
  for el in elements {
    match el {
      Array(inner) =>
        if depth > 0 {
          flatten_array_val(inner.elements, depth - 1, result)
        } else {
          result.push(el)
        }
      _ => result.push(el)
    }
  }
}

///|
fn array_sparse_own_length(data : ArrayData) -> Int64 {
  let mut observed = data.elements.length().to_int64()
  let include_key = fn(key : String) -> Unit {
    match array_index64_from_string(key) {
      Some(idx64) => {
        let len64 = idx64 + 1L
        if len64 > observed {
          observed = len64
        }
      }
      _ => ()
    }
  }
  data.bag.properties.each(fn(key, _) { include_key(key) })
  data.bag.descriptors.each(fn(key, _) { include_key(key) })
  observed
}

///|
fn array_logical_length(data : ArrayData) -> Int64 {
  let observed = array_sparse_own_length(data)
  match get_array_length_override(data) {
    Some(n64) => n64
    None => observed
  }
}

///|
/// ToLength: Get length from any value as per ECMAScript spec (array-like objects)
pub fn to_array_like_length(val : Value) -> Int64 raise {
  match val {
    Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Array(data) => array_logical_length(data)
    Object(data) => {
      // Check for getter-based length first, then fall back to properties
      let length_val : Value? = match data.bag.properties.get("length") {
        Some(v) => Some(v)
        None =>
          // Check if length is defined as an accessor (getter)
          match data.bag.descriptors.get("length") {
            Some(desc) =>
              match desc.getter {
                Some(Object(getter_data)) =>
                  match getter_data.callable {
                    Some(NativeCallable(_, f)) => Some(f([]))
                    Some(NativeCallableWithContext(_, f)) => Some(f(Call, []))
                    Some(NonConstructableCallable(_, f)) => Some(f([]))
                    Some(MethodCallable(_, f)) => Some(f(Object(data), []))
                    _ => None
                  }
                _ => None
              }
            None => None
          }
      }
      to_length_from_value(length_val)
    }
    String_(s) => s.length().to_int64()
    _ => 0L
  }
}

///|
/// ToLength with full interpreter support for user-defined getter-based length
pub fn to_array_like_length_interp(
  val : Value,
  interp : Interpreter,
) -> Int64 raise {
  match val {
    Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Array(data) => array_logical_length(data)
    String_(s) => s.length().to_int64()
    _ => {
      // Use interpreter's get_property to properly handle getters and prototype chains
      let length_val = interp.get_property(val, "length", @token.Loc::default())
      to_length_from_value(Some(length_val), interp=Some(interp))
    }
  }
}

///|
fn to_length_number(n : Double) -> Int64 {
  if n.is_nan() || n <= 0.0 {
    0L
  } else if n.is_inf() || n >= JS_MAX_SAFE_INTEGER_DOUBLE {
    JS_MAX_SAFE_INTEGER_I64
  } else {
    n.floor().to_int64()
  }
}

///|
fn to_length_from_value(
  v : Value?,
  interp? : Interpreter? = None,
) -> Int64 raise {
  match v {
    Some(Number(n)) => to_length_number(n)
    Some(v) => to_length_number(to_number(v, interp~))
    None => 0L
  }
}

///|
/// Get indexed element from array-like value
pub fn get_array_like_element(val : Value, index : Int64) -> Value {
  let key = index.to_string()
  match val {
    Array(data) =>
      match array_index_lookup_result64(data, index) {
        Present(v) => v
        _ => Undefined
      }
    Object(data) => {
      // Check for accessor descriptor (getter) on own property first
      let getter_result : Value? = match data.bag.descriptors.get(key) {
        Some(desc) =>
          match desc.getter {
            Some(Object(getter_data)) =>
              match getter_data.callable {
                Some(NativeCallable(_, f)) => Some(f([])) catch { _ => None }
                Some(NativeCallableWithContext(_, f)) =>
                  Some(f(Call, [])) catch {
                    _ => None
                  }
                Some(NonConstructableCallable(_, f)) =>
                  Some(f([])) catch {
                    _ => None
                  }
                Some(MethodCallable(_, f)) =>
                  Some(f(Object(data), [])) catch {
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        None => None
      }
      match getter_result {
        Some(v) => v
        None =>
          // Walk prototype chain for property lookup
          match data.bag.properties.get(key) {
            Some(v) => v
            None => {
              let mut current = data.prototype
              let mut result : Value = Undefined
              while true {
                match current {
                  Object(proto_data) =>
                    match proto_data.bag.properties.get(key) {
                      Some(v) => {
                        result = v
                        break
                      }
                      None => current = proto_data.prototype
                    }
                  _ => break
                }
              }
              result
            }
          }
      }
    }
    String_(s) => {
      let chars = s.to_array()
      if index >= 0L && index <= 0x7FFFFFFFL && index.to_int() < chars.length() {
        let i = index.to_int()
        let buf = StringBuilder::new()
        buf.write_char(chars[i])
        String_(buf.to_string())
      } else {
        Undefined
      }
    }
    _ => Undefined
  }
}

///|
/// Get indexed element from array-like value using interpreter (handles user-defined getters)
pub fn get_array_like_element_interp(
  interp : Interpreter,
  val : Value,
  index : Int64,
) -> Value raise {
  match val {
    Array(data) =>
      match array_index_lookup_result64(data, index) {
        Present(v) => v
        OwnAccessor(Some(getter)) =>
          interp.call_value(getter, val, [], @token.Loc::default())
        OwnAccessor(None) => Undefined
        Hole | OutOfRange => {
          let proto = get_array_prototype(interp.realm_state, data)
          interp.get_property_from_prototype(
            val,
            proto,
            index.to_string(),
            @token.Loc::default(),
          )
        }
      }
    _ => interp.get_property(val, index.to_string(), @token.Loc::default())
  }
}

///|
/// Non-raising HasProperty walk along an explicit prototype chain for an
/// indexed key. Returns true if any reachable object has an own data or
/// accessor property at the given key. Does NOT invoke Proxy traps
/// (would require raising); Proxy-as-prototype is out of scope per the
/// iteration-model spec v5.
fn proto_chain_has_index(
  interp : Interpreter,
  proto : Value,
  key : String,
  index : Int64,
) -> Bool {
  let mut current = proto
  while true {
    match current {
      Object(proto_data) => {
        if proto_data.bag.properties.contains(key) {
          return true
        }
        match proto_data.bag.descriptors.get(key) {
          Some(_) => return true
          None => current = proto_data.prototype
        }
      }
      Array(arr_data) =>
        match array_index_lookup_result64(arr_data, index) {
          Present(_) | OwnAccessor(_) => return true
          Hole | OutOfRange =>
            // Array-as-prototype: continue walking via the array's own
            // prototype so inherited indices on Object.prototype are seen.
            current = get_array_prototype(interp.realm_state, arr_data)
        }
      _ => return false
    }
  }
  false
}

///|
/// Check if array-like value has indexed property.
/// `interp` is required so the Array branch can resolve `%Array.prototype%`
/// via `get_array_prototype(interp.realm_state,data)`.
pub fn has_array_like_element(
  interp : Interpreter,
  val : Value,
  index : Int64,
) -> Bool {
  let key = index.to_string()
  match val {
    Array(data) =>
      match array_index_lookup_result64(data, index) {
        Present(_) | OwnAccessor(_) => true
        Hole | OutOfRange => {
          let proto = get_array_prototype(interp.realm_state, data)
          proto_chain_has_index(interp, proto, key, index)
        }
      }
    Object(data) => {
      if data.bag.properties.contains(key) {
        return true
      }
      // Check for accessor descriptor
      match data.bag.descriptors.get(key) {
        Some(desc) if desc.is_accessor => return true
        _ => ()
      }
      // Walk prototype chain
      let mut current = data.prototype
      while true {
        match current {
          Object(proto_data) => {
            if proto_data.bag.properties.contains(key) {
              return true
            }
            match proto_data.bag.descriptors.get(key) {
              Some(desc) if desc.is_accessor => return true
              _ => ()
            }
            current = proto_data.prototype
          }
          Array(arr_data) =>
            // Don't terminate the walk on Hole/OutOfRange — an array used
            // as a prototype only owns its dense slots; missing indices
            // must fall through to the next prototype (typically
            // Array.prototype, then Object.prototype).
            match array_index_lookup_result64(arr_data, index) {
              Present(_) | OwnAccessor(_) => return true
              Hole | OutOfRange =>
                current = get_array_prototype(interp.realm_state, arr_data)
            }
          _ => break
        }
      }
      false
    }
    String_(s) =>
      index >= 0L && index <= 0x7FFFFFFFL && index.to_int() < s.length()
    Proxy(_) => interp.has_property(val, key) catch { _ => false }
    _ => false
  }
}

///|
/// Drop hole entries at indices >= `new_len` after a length shrink.
/// Used by both `Interpreter::set_property` and
/// `Interpreter::set_computed_property` length-set paths to avoid the
/// near-identical 12-line block being kept in sync by hand.
///
/// Hole keys are `Int` (≤ 2^31-1); if `new_len` exceeds Int range, no
/// in-range hole can be out-of-range, so the cleanup is a no-op — we
/// skip it to avoid an overflowing Int64→Int cast.
pub fn cleanup_holes_above_length(
  holes : Map[Int, Unit],
  new_len : Int64,
) -> Unit {
  if new_len > 0x7FFFFFFFL {
    return
  }
  let new_len_int = new_len.to_int()
  let stale : Array[Int] = []
  holes.each(fn(k, _) { if k >= new_len_int { stale.push(k) } })
  for k in stale {
    holes.remove(k)
  }
}

///|
fn cleanup_sparse_array_indices_above_length(
  arr : ArrayData,
  new_len : Int64,
) -> Int64? {
  let entries : Array[(Int64, String)] = []
  let dense_len64 = arr.elements.length().to_int64()
  arr.bag.properties.each(fn(key, _) {
    match array_index64_from_string(key) {
      Some(idx64) if idx64 >= new_len && idx64 >= dense_len64 =>
        entries.push((idx64, key))
      _ => ()
    }
  })
  arr.bag.descriptors.each(fn(key, _) {
    match array_index64_from_string(key) {
      Some(idx64) =>
        if idx64 >= new_len &&
          idx64 >= dense_len64 &&
          !arr.bag.properties.contains(key) {
          entries.push((idx64, key))
        }
      _ => ()
    }
  })
  entries.sort_by(fn(a, b) {
    if a.0 > b.0 {
      -1
    } else if a.0 < b.0 {
      1
    } else {
      0
    }
  })
  for entry in entries {
    let idx64 = entry.0
    let key = entry.1
    match arr.bag.descriptors.get(key) {
      Some(desc) if !desc.configurable => return Some(idx64 + 1L)
      _ => ()
    }
    let _ = arr.bag.properties.remove(key)
    let _ = arr.bag.descriptors.remove(key)
  }
  None
}

///|
/// Set indexed element on array-like value
pub fn set_array_like_element(
  val : Value,
  index : Int64,
  value : Value,
) -> Unit {
  let key = index.to_string()
  match val {
    Array(data) =>
      if index >= 0L &&
        index <= 0x7FFFFFFFL &&
        index.to_int() < data.elements.length() {
        let i = index.to_int()
        data.elements[i] = value
        data.holes.remove(i)
      } else if index >= 0L {
        data.bag.properties[key] = value
      }
    Object(data) => data.bag.properties[key] = value
    _ => ()
  }
}

///|
/// Set the length property on an array-like value
pub fn set_array_like_length(val : Value, len : Int64) -> Unit {
  match val {
    Array(data) => {
      if len > data.elements.length().to_int64() {
        set_array_length_override(data, len)
      } else {
        data.elements.truncate(len.to_int())
        clear_array_length_override(data)
      }
      cleanup_holes_above_length(data.holes, len)
    }
    Object(data) => data.bag.properties["length"] = Number(len.to_double())
    _ => ()
  }
}

///|
/// Delete indexed element from array-like value
pub fn delete_array_like_element(val : Value, index : Int) -> Unit {
  let key = index.to_string()
  match val {
    Object(data) => data.bag.properties.remove(key) |> ignore
    _ => ()
  }
}

///|
/// CreateDataPropertyOrThrow(O, P, V) per ES spec 7.3.5.
/// Sets an indexed property on a species result value and throws if
/// `[[DefineOwnProperty]]` rejects the creation.
pub fn create_data_property_or_throw(
  interp : Interpreter,
  target : Value,
  index : Int64,
  value : Value,
) -> Unit raise {
  let key = index.to_string()
  let ok = match target {
    Array(data) =>
      if index >= 0L &&
        index <= ARRAY_DENSE_MATERIALIZE_LIMIT_I64 &&
        data.extensible &&
        data.length_writable &&
        !data.bag.descriptors.contains(key) {
        let i = index.to_int()
        if i == data.elements.length() {
          data.elements.push(value)
        } else if i >= 0 && i < data.elements.length() {
          data.elements[i] = value
        } else {
          // Sparse case: pad with Undefined up to index (these are holes),
          // then set value at the target index (not a hole).
          while data.elements.length() < i {
            let pad_idx = data.elements.length()
            data.elements.push(Undefined)
            data.holes[pad_idx] = ()
          }
          data.elements.push(value)
        }
        data.holes.remove(i)
        match get_array_length_override(data) {
          Some(len) if index + 1L > len =>
            set_array_length_override(data, index + 1L)
          _ => ()
        }
        true
      } else {
        interp.define_own_property(
          target,
          String_(key),
          PartialDescriptor::data_default(value),
          @token.Loc::default(),
        )
      }
    _ =>
      interp.define_own_property(
        target,
        String_(key),
        PartialDescriptor::data_default(value),
        @token.Loc::default(),
      )
  }
  if !ok {
    raise @errors.TypeError(message="Cannot create data property")
  }
}

///|
/// ArraySpeciesCreate(originalArray, length) per ES spec 9.4.2.3
/// Looks up Symbol.species on the original array's constructor to determine
/// what constructor to use for the result. Returns a plain Array if no
/// custom species is found.
pub fn array_species_create(
  interp : Interpreter,
  original : Value,
  len : Int64,
) -> Value raise Error {
  // Step 1: If originalArray is not an Array, return a plain array.
  // IsArray unwraps proxies, so ArraySpeciesCreate must do the same before
  // deciding whether to consult constructor/@@species.
  let mut array_probe = original
  let mut is_array = false
  while true {
    match array_probe {
      Array(_) => {
        is_array = true
        break
      }
      Object(data) => {
        is_array = data.class_name == "Array"
        break
      }
      Proxy(proxy_data) =>
        match proxy_data.target {
          Some(target) => array_probe = target
          None => break
        }
      _ => break
    }
  }
  if !is_array {
    if len > JS_MAX_ARRAY_LENGTH_I64 {
      raise @errors.RangeError(message="Invalid array length")
    }
    return make_array([])
  }
  let loc = @token.Loc::default()
  // Step 2: Get C = Get(originalArray, "constructor")
  let c = interp.get_property(original, "constructor", loc)
  // Steps 4-5: If Type(C) is Object, set C = C[@@species]; if null/undefined use default.
  // If Type(C) is not Object and not undefined, preserve C so step 6 (IsConstructor check)
  // throws TypeError — e.g. when a.constructor is set to null, a number, or a string.
  let species : Value = match c {
    Undefined => Undefined
    _ =>
      if is_object_value(c) {
        let species_sym = interp.realm_state.well_known_symbols.species
        let s = interp.get_computed_property(c, Symbol(species_sym), loc)
        match s {
          Null | Undefined => Undefined
          _ => s
        }
      } else {
        c
      }
  }
  // Step 5: If C is undefined, return plain array
  if species is Undefined {
    if len > JS_MAX_ARRAY_LENGTH_I64 {
      raise @errors.RangeError(message="Invalid array length")
    }
    return make_array([])
  }
  // Step 6: If IsConstructor(C) is false, throw TypeError
  if !is_constructor_value(species) {
    raise @errors.TypeError(message="Species constructor is not a constructor")
  }
  // Step 7: Construct(C, « length »)
  interp.construct_value(species, [Number(len.to_double())], loc)
}

///|
/// Convert array-like value to an Array of Values
pub fn to_array_like_elements(val : Value) -> Array[Value] raise {
  let len = to_array_like_length(val)
  let result : Array[Value] = []
  for i = 0L; i < len; i = i + 1L {
    result.push(get_array_like_element(val, i))
  }
  result
}

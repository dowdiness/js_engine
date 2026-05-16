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
        OutOfRange
      }
    None =>
      if i < 0 {
        OutOfRange
      } else if data.holes.contains(i) {
        Hole
      } else if i < data.elements.length() {
        Present(data.elements[i])
      } else {
        OutOfRange
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
/// ToLength: Get length from any value as per ECMAScript spec (array-like objects)
pub fn to_array_like_length(val : Value) -> Int raise {
  match val {
    Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Array(data) => data.elements.length()
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
    String_(s) => s.length()
    _ => 0
  }
}

///|
/// ToLength with full interpreter support for user-defined getter-based length
pub fn to_array_like_length_interp(
  val : Value,
  interp : Interpreter,
) -> Int raise {
  match val {
    Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    Array(data) => data.elements.length()
    String_(s) => s.length()
    _ => {
      // Use interpreter's get_property to properly handle getters and prototype chains
      let length_val = interp.get_property(val, "length", @token.Loc::default())
      to_length_from_value(Some(length_val), interp=Some(interp))
    }
  }
}

///|
fn to_length_from_value(v : Value?, interp? : Interpreter? = None) -> Int raise {
  match v {
    Some(Number(n)) => {
      let len = n.to_int()
      if len < 0 {
        0
      } else {
        len
      }
    }
    Some(v) => {
      let n = to_number(v, interp~)
      if n.is_nan() {
        0
      } else if n.is_inf() {
        if n > 0.0 {
          0x7FFFFFFF
        } else {
          0
        }
      } else {
        let i = n.to_int()
        if i < 0 {
          0
        } else {
          i
        }
      }
    }
    None => 0
  }
}

///|
/// Get indexed element from array-like value
pub fn get_array_like_element(val : Value, index : Int) -> Value {
  let key = index.to_string()
  match val {
    Array(data) =>
      if index >= 0 && index < data.elements.length() {
        data.elements[index]
      } else {
        Undefined
      }
    Object(data) => {
      // Check for accessor descriptor (getter) on own property first
      let getter_result : Value? = match data.bag.descriptors.get(key) {
        Some(desc) =>
          match desc.getter {
            Some(Object(getter_data)) =>
              match getter_data.callable {
                Some(NativeCallable(_, f)) => Some(f([])) catch { _ => None }
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
      if index >= 0 && index < chars.length() {
        let buf = StringBuilder::new()
        buf.write_char(chars[index])
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
  index : Int,
) -> Value raise {
  match val {
    Array(data) =>
      match array_index_lookup_result(data, index) {
        Present(v) => v
        OwnAccessor(Some(getter)) =>
          interp.call_value(getter, val, [], @token.Loc::default())
        OwnAccessor(None) => Undefined
        Hole | OutOfRange => {
          let proto = get_array_prototype(interp.global, data)
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
fn proto_chain_has_index(proto : Value, key : String, index : Int) -> Bool {
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
        return match array_index_lookup_result(arr_data, index) {
          Present(_) | OwnAccessor(_) => true
          Hole | OutOfRange => false
        }
      _ => return false
    }
  }
  false
}

///|
/// Check if array-like value has indexed property.
/// `interp` is required so the Array branch can resolve `%Array.prototype%`
/// via `get_array_prototype(interp.global, data)`.
pub fn has_array_like_element(
  interp : Interpreter,
  val : Value,
  index : Int,
) -> Bool {
  let key = index.to_string()
  match val {
    Array(data) =>
      match array_index_lookup_result(data, index) {
        Present(_) | OwnAccessor(_) => true
        Hole | OutOfRange => {
          let proto = get_array_prototype(interp.global, data)
          proto_chain_has_index(proto, key, index)
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
            return match array_index_lookup_result(arr_data, index) {
              Present(_) | OwnAccessor(_) => true
              Hole | OutOfRange => false
            }
          _ => break
        }
      }
      false
    }
    String_(s) => index >= 0 && index < s.length()
    _ => false
  }
}

///|
/// Set indexed element on array-like value
pub fn set_array_like_element(val : Value, index : Int, value : Value) -> Unit {
  let key = index.to_string()
  match val {
    Array(data) =>
      if index >= 0 && index < data.elements.length() {
        data.elements[index] = value
        data.holes.remove(index)
      }
    Object(data) => data.bag.properties[key] = value
    _ => ()
  }
}

///|
/// Set the length property on an array-like value
pub fn set_array_like_length(val : Value, len : Int) -> Unit {
  match val {
    Array(data) =>
      while data.elements.length() < len {
        let new_idx = data.elements.length()
        data.elements.push(Undefined)
        data.holes[new_idx] = ()
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
/// CreateDataPropertyOrThrow(O, P, V) per ES spec 7.3.5
/// Sets an indexed property on a species result value, using the fast path
/// for plain Arrays and set_property for everything else.
pub fn create_data_property_or_throw(
  interp : Interpreter,
  target : Value,
  index : Int,
  value : Value,
) -> Unit raise {
  match target {
    Array(data) => {
      if index == data.elements.length() {
        data.elements.push(value)
      } else if index >= 0 && index < data.elements.length() {
        data.elements[index] = value
      } else {
        // Sparse case: pad with Undefined up to index (these are holes),
        // then set value at the target index (not a hole).
        while data.elements.length() < index {
          let pad_idx = data.elements.length()
          data.elements.push(Undefined)
          data.holes[pad_idx] = ()
        }
        data.elements.push(value)
      }
      data.holes.remove(index)
    }
    _ => {
      let _ = interp.set_property(
        target,
        index.to_string(),
        value,
        @token.Loc::default(),
        strict=true,
      )
    }
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
  len : Int,
) -> Value raise Error {
  // Step 1: If originalArray is not an Array, return a plain array
  let is_array = match original {
    Array(_) => true
    Object(data) => data.class_name == "Array"
    _ => false
  }
  if !is_array {
    return make_array([])
  }
  let loc = @token.Loc::default()
  // Step 2: Get C = Get(originalArray, "constructor")
  let c = interp.get_property(original, "constructor", loc)
  // Step 4: If Type(C) is Object, set C = Get(C, @@species)
  let species : Value = match c {
    Object(_) => {
      let species_sym = get_species_symbol()
      let s = interp.get_computed_property(c, Symbol(species_sym), loc)
      // If species is null or undefined, use default
      match s {
        Null | Undefined => Undefined
        _ => s
      }
    }
    Undefined => Undefined
    _ => Undefined
  }
  // Step 5: If C is undefined, return plain array
  if species is Undefined {
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
  for i = 0; i < len; i = i + 1 {
    result.push(get_array_like_element(val, i))
  }
  result
}

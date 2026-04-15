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
      let length_val : Value? = match data.properties.get("length") {
        Some(v) => Some(v)
        None =>
          // Check if length is defined as an accessor (getter)
          match data.descriptors.get("length") {
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
      to_length_from_value(Some(length_val))
    }
  }
}

///|
fn to_length_from_value(v : Value?) -> Int raise {
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
      let n = to_number(v)
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
      let getter_result : Value? = match data.descriptors.get(key) {
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
          match data.properties.get(key) {
            Some(v) => v
            None => {
              let mut current = data.prototype
              let mut result : Value = Undefined
              while true {
                match current {
                  Object(proto_data) =>
                    match proto_data.properties.get(key) {
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
      if index >= 0 && index < data.elements.length() {
        data.elements[index]
      } else {
        Undefined
      }
    _ => interp.get_property(val, index.to_string(), @token.Loc::default())
  }
}

///|
/// Check if array-like value has indexed property
pub fn has_array_like_element(val : Value, index : Int) -> Bool {
  let key = index.to_string()
  match val {
    Array(data) => index >= 0 && index < data.elements.length()
    Object(data) => {
      if data.properties.contains(key) {
        return true
      }
      // Check for accessor descriptor
      match data.descriptors.get(key) {
        Some(desc) if desc.getter is Some(_) => return true
        _ => ()
      }
      // Walk prototype chain
      let mut current = data.prototype
      while true {
        match current {
          Object(proto_data) => {
            if proto_data.properties.contains(key) {
              return true
            }
            match proto_data.descriptors.get(key) {
              Some(desc) if desc.getter is Some(_) => return true
              _ => ()
            }
            current = proto_data.prototype
          }
          Array(arr_data) =>
            return index >= 0 && index < arr_data.elements.length()
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
      }
    Object(data) => data.properties[key] = value
    _ => ()
  }
}

///|
/// Set the length property on an array-like value
pub fn set_array_like_length(val : Value, len : Int) -> Unit {
  match val {
    Array(data) =>
      while data.elements.length() < len {
        data.elements.push(Undefined)
      }
    Object(data) => data.properties["length"] = Number(len.to_double())
    _ => ()
  }
}

///|
/// Delete indexed element from array-like value
pub fn delete_array_like_element(val : Value, index : Int) -> Unit {
  let key = index.to_string()
  match val {
    Object(data) => data.properties.remove(key) |> ignore
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
    Array(data) =>
      if index == data.elements.length() {
        data.elements.push(value)
      } else if index >= 0 && index < data.elements.length() {
        data.elements[index] = value
      } else {
        // Sparse case: pad with Undefined up to index, then set
        while data.elements.length() < index {
          data.elements.push(Undefined)
        }
        data.elements.push(value)
      }
    _ => {
      let _ = interp.set_property(
        target,
        index.to_string(),
        value,
        @token.Loc::default(),
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
    return Array({ elements: [] })
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
    return Array({ elements: [] })
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

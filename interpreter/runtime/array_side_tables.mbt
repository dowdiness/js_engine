///|
/// Per-array override for Symbol.iterator defined via Object.defineProperty on
/// Array instances. Stored out-of-line because ArrayData currently models only
/// indexed elements.
let array_iterator_overrides : Array[(ArrayData, Value?, Value?)] = []

///|
/// Named properties on arrays (e.g., index, input on RegExp exec results)
let array_named_props : Array[(ArrayData, Map[String, Value])] = []

///|
/// Sparse-length overrides for arrays whose logical length differs from
/// elements.length() (e.g. new Array(n) where n > allocation cap).
/// Stored as Int64 to cover the full valid range 0..2^32-1.
let array_length_overrides : Array[(ArrayData, Int64)] = []

///|
pub fn set_array_length_override(arr : ArrayData, len : Int64) -> Unit {
  for i = 0; i < array_length_overrides.length(); i = i + 1 {
    let (existing, _) = array_length_overrides[i]
    if physical_equal(existing, arr) {
      array_length_overrides[i] = (arr, len)
      return
    }
  }
  array_length_overrides.push((arr, len))
}

///|
pub fn get_array_length_override(arr : ArrayData) -> Int64? {
  for i = 0; i < array_length_overrides.length(); i = i + 1 {
    let (existing, len) = array_length_overrides[i]
    if physical_equal(existing, arr) {
      return Some(len)
    }
  }
  None
}

///|
pub fn clear_array_length_override(arr : ArrayData) -> Unit {
  for i = 0; i < array_length_overrides.length(); i = i + 1 {
    let (existing, _) = array_length_overrides[i]
    if physical_equal(existing, arr) {
      let _ = array_length_overrides.remove(i)
      return
    }
  }
}

///|
pub fn set_array_named_prop(
  arr : ArrayData,
  key : String,
  value : Value,
) -> Unit {
  for i = 0; i < array_named_props.length(); i = i + 1 {
    let (existing, props) = array_named_props[i]
    if physical_equal(existing, arr) {
      props[key] = value
      return
    }
  }
  let props : Map[String, Value] = {}
  props[key] = value
  array_named_props.push((arr, props))
}

///|
pub fn get_array_named_prop(arr : ArrayData, key : String) -> Value? {
  for i = 0; i < array_named_props.length(); i = i + 1 {
    let (existing, props) = array_named_props[i]
    if physical_equal(existing, arr) {
      return props.get(key)
    }
  }
  None
}

///|
/// Symbol properties on arrays (side-table, same approach as named props)
let array_symbol_props : Array[(ArrayData, Map[Int, Value])] = []

///|
pub fn set_array_symbol_prop(
  arr : ArrayData,
  sym_id : Int,
  value : Value,
) -> Unit {
  for i = 0; i < array_symbol_props.length(); i = i + 1 {
    let (existing, props) = array_symbol_props[i]
    if physical_equal(existing, arr) {
      props[sym_id] = value
      return
    }
  }
  let props : Map[Int, Value] = {}
  props[sym_id] = value
  array_symbol_props.push((arr, props))
}

///|
pub fn get_array_symbol_prop(arr : ArrayData, sym_id : Int) -> Value? {
  for i = 0; i < array_symbol_props.length(); i = i + 1 {
    let (existing, props) = array_symbol_props[i]
    if physical_equal(existing, arr) {
      return props.get(sym_id)
    }
  }
  None
}

///|
pub fn set_array_iterator_override(
  arr : ArrayData,
  getter : Value?,
  value : Value?,
) -> Unit {
  for i = 0; i < array_iterator_overrides.length(); i = i + 1 {
    let (existing, _g, _v) = array_iterator_overrides[i]
    if physical_equal(existing, arr) {
      array_iterator_overrides[i] = (arr, getter, value)
      return
    }
  }
  array_iterator_overrides.push((arr, getter, value))
}

///|
pub fn get_array_iterator_override(arr : ArrayData) -> (Value?, Value?) {
  for i = 0; i < array_iterator_overrides.length(); i = i + 1 {
    let (existing, getter, value) = array_iterator_overrides[i]
    if physical_equal(existing, arr) {
      return (getter, value)
    }
  }
  (None, None)
}

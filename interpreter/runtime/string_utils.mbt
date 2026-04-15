///|
/// Convert a MoonBit string (sequence of Unicode code points) to an array
/// of UTF-16 code units.  Supplementary characters (code point > 0xFFFF) are
/// split into a surrogate pair (high surrogate + low surrogate).
pub fn string_to_utf16(s : String) -> Array[Int] {
  let units : Array[Int] = []
  let cps = s.to_array()
  for ch in cps {
    let cp = ch.to_int()
    if cp > 0xFFFF {
      // Encode as surrogate pair
      let adjusted = cp - 0x10000
      let high = 0xD800 + (adjusted >> 10)
      let low = 0xDC00 + (adjusted & 0x3FF)
      units.push(high)
      units.push(low)
    } else {
      units.push(cp)
    }
  }
  units
}

///|
/// Get the UTF-16 length of a string (counting code units, not code points).
pub fn utf16_length(s : String) -> Int {
  let cps = s.to_array()
  let mut len = 0
  for ch in cps {
    let cp = ch.to_int()
    if cp > 0xFFFF {
      len += 2
    } else {
      len += 1
    }
  }
  len
}

///|
/// Check if a class name corresponds to a TypedArray type.
pub fn is_typedarray_class(name : String) -> Bool {
  match name {
    "Int8Array"
    | "Uint8Array"
    | "Uint8ClampedArray"
    | "Int16Array"
    | "Uint16Array"
    | "Int32Array"
    | "Uint32Array"
    | "Float32Array"
    | "Float64Array" => true
    _ => false
  }
}

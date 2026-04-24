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

///|
/// Classify a string property key for TypedArray indexed-element interception
/// per ES §10.4.5 IntegerIndexedExoticObject + §7.1.21 CanonicalNumericIndexString.
///
/// Returns:
/// - `Some(idx)` with `idx >= 0`: a valid in-range integer index. The caller
///   should perform the indexed read/write.
/// - `Some(-1)`: a canonical numeric string (per §7.1.21) that is NOT a
///   valid integer index — `"-0"`, `"NaN"`, `"Infinity"`, `"-Infinity"`,
///   fractional like `"1.5"`, or negative. Per §10.4.5 these are still
///   intercepted (read returns `undefined`; write is a no-op) — they must
///   not fall through to ordinary property creation.
/// - `None`: not a canonical numeric string — caller should fall through to
///   ordinary property lookup / write.
///
/// Note: `"-0"` is a canonical numeric index string per §7.1.21 step 1 but
/// `-0𝔽` is not a valid integer index, so it is explicitly classified as
/// `Some(-1)`. Other canonical-but-invalid forms (NaN, Infinity, fractional)
/// are filtered by the IEEE round-trip check (`n.to_string() == s` plus
/// `idx.to_double() == n`).
pub fn classify_typedarray_string_key(s : String) -> Int? {
  if s == "-0" {
    return Some(-1)
  }
  try {
    let n = @string.parse_double(s)
    if n.to_string() == s {
      let idx = n.to_int()
      if idx.to_double() == n && idx >= 0 {
        Some(idx)
      } else {
        Some(-1)
      }
    } else {
      None
    }
  } catch {
    _ => None
  }
}

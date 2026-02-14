///|
/// Read a typed element from an ArrayBuffer's byte array at the given byte offset.
/// Returns the JS Number value.
fn typed_array_get_element(
  bytes : Array[Int],
  byte_offset : Int,
  type_name : String,
) -> Value {
  match type_name {
    "Int8Array" => {
      let v = bytes[byte_offset]
      let signed = if v >= 128 { v - 256 } else { v }
      Number(signed.to_double())
    }
    "Uint8Array" | "Uint8ClampedArray" => Number(bytes[byte_offset].to_double())
    "Int16Array" => {
      let lo = bytes[byte_offset]
      let hi = bytes[byte_offset + 1]
      let v = lo + hi * 256
      let signed = if v >= 32768 { v - 65536 } else { v }
      Number(signed.to_double())
    }
    "Uint16Array" => {
      let lo = bytes[byte_offset]
      let hi = bytes[byte_offset + 1]
      Number((lo + hi * 256).to_double())
    }
    "Int32Array" => {
      let b0 = bytes[byte_offset]
      let b1 = bytes[byte_offset + 1]
      let b2 = bytes[byte_offset + 2]
      let b3 = bytes[byte_offset + 3]
      let v = b0.to_int64() +
        b1.to_int64() * 256L +
        b2.to_int64() * 65536L +
        b3.to_int64() * 16777216L
      let signed = if v >= 2147483648L { v - 4294967296L } else { v }
      Number(signed.to_double())
    }
    "Uint32Array" => {
      let b0 = bytes[byte_offset]
      let b1 = bytes[byte_offset + 1]
      let b2 = bytes[byte_offset + 2]
      let b3 = bytes[byte_offset + 3]
      let v = b0.to_int64() +
        b1.to_int64() * 256L +
        b2.to_int64() * 65536L +
        b3.to_int64() * 16777216L
      Number(v.to_double())
    }
    "Float32Array" => {
      let b0 = bytes[byte_offset]
      let b1 = bytes[byte_offset + 1]
      let b2 = bytes[byte_offset + 2]
      let b3 = bytes[byte_offset + 3]
      let bits64 = b0.to_int64() +
        b1.to_int64() * 256L +
        b2.to_int64() * 65536L +
        b3.to_int64() * 16777216L
      Number(float32_bits_to_double(bits64.to_int()))
    }
    "Float64Array" => {
      let mut bits = 0L
      for i = 0; i < 8; i = i + 1 {
        bits = bits + (bytes[byte_offset + i].to_int64() << (i * 8))
      }
      Number(bits.reinterpret_as_double())
    }
    _ => Undefined
  }
}

///|
/// Write a typed element into an ArrayBuffer's byte array at the given byte offset.
fn typed_array_set_element(
  bytes : Array[Int],
  byte_offset : Int,
  type_name : String,
  value : Double,
) -> Unit {
  match type_name {
    "Int8Array" => {
      let v = to_int32(value)
      let byte_val = v & 0xFF
      bytes[byte_offset] = byte_val
    }
    "Uint8Array" => {
      let v = to_int32(value)
      let byte_val = v & 0xFF
      bytes[byte_offset] = byte_val
    }
    "Uint8ClampedArray" => {
      // Clamp to 0..255
      let v = if value.is_nan() {
        0
      } else {
        let rounded = value.round().to_int()
        if rounded < 0 {
          0
        } else if rounded > 255 {
          255
        } else {
          rounded
        }
      }
      bytes[byte_offset] = v
    }
    "Int16Array" => {
      let v = to_int32(value) & 0xFFFF
      bytes[byte_offset] = v & 0xFF
      bytes[byte_offset + 1] = (v >> 8) & 0xFF
    }
    "Uint16Array" => {
      let v = to_int32(value) & 0xFFFF
      bytes[byte_offset] = v & 0xFF
      bytes[byte_offset + 1] = (v >> 8) & 0xFF
    }
    "Int32Array" | "Uint32Array" => {
      let v = to_int32(value)
      bytes[byte_offset] = v & 0xFF
      bytes[byte_offset + 1] = (v >> 8) & 0xFF
      bytes[byte_offset + 2] = (v >> 16) & 0xFF
      bytes[byte_offset + 3] = (v >> 24) & 0xFF
    }
    "Float32Array" => {
      let bits = double_to_float32_bits(value)
      bytes[byte_offset] = bits & 0xFF
      bytes[byte_offset + 1] = (bits >> 8) & 0xFF
      bytes[byte_offset + 2] = (bits >> 16) & 0xFF
      bytes[byte_offset + 3] = (bits >> 24) & 0xFF
    }
    "Float64Array" => {
      let bits = value.reinterpret_as_uint64()
      for i = 0; i < 8; i = i + 1 {
        bytes[byte_offset + i] = (bits >> (i * 8)).to_int() & 0xFF
      }
    }
    _ => ()
  }
}

///|
/// Convert IEEE 754 single-precision bits (as int) to double.
fn float32_bits_to_double(bits : Int) -> Double {
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 }
  let exponent = (bits >> 23) & 0xFF
  let mantissa = bits & 0x7FFFFF
  if exponent == 0xFF {
    if mantissa != 0 {
      return 0.0 / 0.0 // NaN
    } else {
      return sign * (1.0 / 0.0) // Infinity
    }
  }
  if exponent == 0 {
    if mantissa == 0 {
      return sign * 0.0
    }
    // Denormalized number
    return sign * mantissa.to_double() * 1.401298464324817e-45 // 2^-149
  }
  // Normalized number: (-1)^sign * 2^(exp-127) * (1 + mantissa/2^23)
  let exp_val = exponent - 127
  let frac = 1.0 + mantissa.to_double() / 8388608.0 // 8388608 = 2^23
  sign * ldexp(frac, exp_val)
}

///|
/// Convert double to IEEE 754 single-precision bits (as int).
fn double_to_float32_bits(value : Double) -> Int {
  if value.is_nan() {
    return 0x7FC00000 // Canonical NaN
  }
  if value == 0.0 {
    // Check for -0: 0x80000000 as signed int = -2147483648
    if 1.0 / value < 0.0 {
      return -2147483648 // -0.0 float32 bits
    }
    return 0
  }
  if value.is_inf() {
    // +Inf = 0x7F800000, -Inf = 0xFF800000 (signed = -8388608)
    return if value > 0.0 { 0x7F800000 } else { -8388608 }
  }
  let sign_bit = if value < 0.0 { 1 } else { 0 }
  let abs_val = value.abs()
  // Find exponent and mantissa
  let mut exp = 0
  let mut frac = abs_val
  if frac >= 2.0 {
    while frac >= 2.0 {
      frac = frac / 2.0
      exp = exp + 1
    }
  } else if frac < 1.0 && frac > 0.0 {
    while frac < 1.0 && exp > -126 {
      frac = frac * 2.0
      exp = exp - 1
    }
  }
  if exp > 127 {
    // Overflow to infinity
    return (sign_bit << 31) | 0x7F800000
  }
  if exp <= -126 && frac < 1.0 {
    // Denormalized
    let mantissa = (frac * 8388608.0 + 0.5).to_int() & 0x7FFFFF
    return (sign_bit << 31) | mantissa
  }
  // Normalized: frac is in [1.0, 2.0)
  let mantissa = ((frac - 1.0) * 8388608.0 + 0.5).to_int() & 0x7FFFFF
  let biased_exp = (exp + 127) & 0xFF
  (sign_bit << 31) | (biased_exp << 23) | mantissa
}

///|
/// Simple ldexp: multiply by 2^exp
fn ldexp(value : Double, exp : Int) -> Double {
  let mut result = value
  let mut e = exp
  if e > 0 {
    while e > 0 {
      result = result * 2.0
      e = e - 1
    }
  } else {
    while e < 0 {
      result = result / 2.0
      e = e + 1
    }
  }
  result
}

///|
/// Create a TypedArray object with its own ArrayBuffer.
pub fn make_typedarray_object(
  type_name : String,
  length : Int,
  proto : Value,
  env : Environment,
) -> Value {
  let bpe = typed_array_bytes_per_element(type_name)
  let byte_length = length * bpe
  let ab_proto = env.get("[[ArrayBufferPrototype]]") catch { _ => Null }
  let buffer = make_arraybuffer_object(byte_length, ab_proto)
  let buf_id = match get_buffer_id(buffer) {
    Some(id) => id
    None => -1
  }
  let props : Map[String, Value] = {}
  props["[[TypedArrayName]]"] = String_(type_name)
  props["[[ViewedArrayBuffer]]"] = buffer
  props["[[ArrayBufferID]]"] = Number(buf_id.to_double())
  props["[[ByteOffset]]"] = Number(0.0)
  props["[[ByteLength]]"] = Number(byte_length.to_double())
  props["[[ArrayLength]]"] = Number(length.to_double())
  let descs : Map[String, PropDescriptor] = {}
  let internal_keys = [
    "[[TypedArrayName]]", "[[ViewedArrayBuffer]]", "[[ArrayBufferID]]",
    "[[ByteOffset]]", "[[ByteLength]]", "[[ArrayLength]]",
  ]
  for k in internal_keys {
    descs[k] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
    }
  }
  Object({
    properties: props,
    symbol_properties: {},
    prototype: proto,
    callable: None,
    class_name: type_name,
    descriptors: descs,
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Create a TypedArray from an existing buffer.
fn make_typedarray_from_buffer(
  type_name : String,
  buffer : Value,
  byte_offset : Int,
  length : Int,
  proto : Value,
) -> Value {
  let buf_id = match get_buffer_id(buffer) {
    Some(id) => id
    None => -1
  }
  let bpe = typed_array_bytes_per_element(type_name)
  let byte_length = length * bpe
  let props : Map[String, Value] = {}
  props["[[TypedArrayName]]"] = String_(type_name)
  props["[[ViewedArrayBuffer]]"] = buffer
  props["[[ArrayBufferID]]"] = Number(buf_id.to_double())
  props["[[ByteOffset]]"] = Number(byte_offset.to_double())
  props["[[ByteLength]]"] = Number(byte_length.to_double())
  props["[[ArrayLength]]"] = Number(length.to_double())
  let descs : Map[String, PropDescriptor] = {}
  let internal_keys = [
    "[[TypedArrayName]]", "[[ViewedArrayBuffer]]", "[[ArrayBufferID]]",
    "[[ByteOffset]]", "[[ByteLength]]", "[[ArrayLength]]",
  ]
  for k in internal_keys {
    descs[k] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
    }
  }
  Object({
    properties: props,
    symbol_properties: {},
    prototype: proto,
    callable: None,
    class_name: type_name,
    descriptors: descs,
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Get a typed element from a TypedArray object at the given index.
pub fn typedarray_get_index(data : ObjectData, index : Int) -> Value {
  let length = match data.properties.get("[[ArrayLength]]") {
    Some(Number(n)) => n.to_int()
    _ => 0
  }
  if index < 0 || index >= length {
    return Undefined
  }
  let buf_id = match data.properties.get("[[ArrayBufferID]]") {
    Some(Number(n)) => n.to_int()
    _ => return Undefined
  }
  if is_arraybuffer_detached(buf_id) {
    return Undefined
  }
  let byte_offset = match data.properties.get("[[ByteOffset]]") {
    Some(Number(n)) => n.to_int()
    _ => 0
  }
  let bpe = typed_array_bytes_per_element(data.class_name)
  let elem_offset = byte_offset + index * bpe
  match get_arraybuffer_bytes(buf_id) {
    Some(bytes) => typed_array_get_element(bytes, elem_offset, data.class_name)
    None => Undefined
  }
}

///|
/// Set a typed element on a TypedArray object at the given index.
pub fn typedarray_set_index(
  data : ObjectData,
  index : Int,
  value : Double,
) -> Unit {
  let length = match data.properties.get("[[ArrayLength]]") {
    Some(Number(n)) => n.to_int()
    _ => 0
  }
  if index < 0 || index >= length {
    return
  }
  let buf_id = match data.properties.get("[[ArrayBufferID]]") {
    Some(Number(n)) => n.to_int()
    _ => return
  }
  if is_arraybuffer_detached(buf_id) {
    return
  }
  let byte_offset = match data.properties.get("[[ByteOffset]]") {
    Some(Number(n)) => n.to_int()
    _ => 0
  }
  let bpe = typed_array_bytes_per_element(data.class_name)
  let elem_offset = byte_offset + index * bpe
  match get_arraybuffer_bytes(buf_id) {
    Some(bytes) => typed_array_set_element(bytes, elem_offset, data.class_name, value)
    None => ()
  }
}

///|
/// Get a TypedArray property by name (handles length, byteLength, byteOffset, buffer, and methods).
pub fn get_typedarray_prop(data : ObjectData, prop : String) -> Value {
  match prop {
    "length" =>
      match data.properties.get("[[ArrayLength]]") {
        Some(n) => n
        None => Number(0.0)
      }
    "byteLength" =>
      match data.properties.get("[[ByteLength]]") {
        Some(n) => n
        None => Number(0.0)
      }
    "byteOffset" =>
      match data.properties.get("[[ByteOffset]]") {
        Some(n) => n
        None => Number(0.0)
      }
    "buffer" =>
      match data.properties.get("[[ViewedArrayBuffer]]") {
        Some(buf) => buf
        None => Undefined
      }
    "BYTES_PER_ELEMENT" =>
      Number(typed_array_bytes_per_element(data.class_name).to_double())
    "constructor" =>
      match data.properties.get("constructor") {
        Some(v) => v
        None => Undefined
      }
    _ => {
      // Check if it's a numeric string (index access)
      try {
        let idx = @strconv.parse_int(prop)
        if idx >= 0 {
          return typedarray_get_index(data, idx)
        }
        Undefined
      } catch {
        _ => Undefined
      }
    }
  }
}

///|
/// Setup all TypedArray builtins.
pub fn setup_typedarray_builtins(env : Environment) -> Unit {
  let obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }
  let iterator_sym = get_iterator_symbol()
  let tostringtag_sym = get_tostringtag_symbol()

  // Create %TypedArray%.prototype (shared prototype for all typed array instances)
  let ta_proto_props : Map[String, Value] = {}
  let ta_proto_descs : Map[String, PropDescriptor] = {}

  // --- Prototype getters ---
  let getter_props = [
    ("length", "[[ArrayLength]]"),
    ("byteLength", "[[ByteLength]]"),
    ("byteOffset", "[[ByteOffset]]"),
  ]
  for pair in getter_props {
    let (getter_name, internal_slot) = pair
    ta_proto_props[getter_name] = Undefined
    ta_proto_descs[getter_name] = {
      writable: false,
      enumerable: false,
      configurable: true,
      getter: Some(
        Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            MethodCallable("get \{getter_name}", fn(this_val, _args) raise {
              match this_val {
                Object(data) =>
                  if is_typedarray_class(data.class_name) {
                    match data.properties.get(internal_slot) {
                      Some(n) => n
                      None => Number(0.0)
                    }
                  } else {
                    raise @errors.TypeError(
                      message="get \{getter_name} called on incompatible receiver",
                    )
                  }
                _ =>
                  raise @errors.TypeError(
                    message="get \{getter_name} called on incompatible receiver",
                  )
              }
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        }),
      ),
      setter: None,
    }
  }

  // buffer getter
  ta_proto_props["buffer"] = Undefined
  ta_proto_descs["buffer"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(
      Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("get buffer", fn(this_val, _args) raise {
            match this_val {
              Object(data) =>
                if is_typedarray_class(data.class_name) {
                  match data.properties.get("[[ViewedArrayBuffer]]") {
                    Some(buf) => buf
                    None => Undefined
                  }
                } else {
                  raise @errors.TypeError(
                    message="get buffer called on incompatible receiver",
                  )
                }
              _ =>
                raise @errors.TypeError(
                  message="get buffer called on incompatible receiver",
                )
            }
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
    ),
    setter: None,
  }

  // --- Prototype methods ---

  // set(source [, offset])
  ta_proto_props["set"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("set", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              if args.length() == 0 {
                raise @errors.TypeError(message="TypedArray.prototype.set requires at least 1 argument")
              }
              let target_offset = if args.length() > 1 {
                to_number(args[1]).to_int()
              } else {
                0
              }
              let ta_length = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              match args[0] {
                // Source is a TypedArray
                Object(src_data) if is_typedarray_class(src_data.class_name) => {
                  let src_len = match src_data.properties.get("[[ArrayLength]]") {
                    Some(Number(n)) => n.to_int()
                    _ => 0
                  }
                  if target_offset + src_len > ta_length {
                    raise @errors.RangeError(message="Source is too large")
                  }
                  // Buffer all source elements first to handle overlapping ArrayBuffers
                  let temp : Array[Double] = []
                  for i = 0; i < src_len; i = i + 1 {
                    let val = typedarray_get_index(src_data, i)
                    match val {
                      Number(n) => temp.push(n)
                      _ => temp.push(0.0)
                    }
                  }
                  for i = 0; i < src_len; i = i + 1 {
                    typedarray_set_index(data, target_offset + i, temp[i])
                  }
                  Undefined
                }
                // Source is an array-like
                Array(arr_data) => {
                  let src_len = arr_data.elements.length()
                  if target_offset + src_len > ta_length {
                    raise @errors.RangeError(message="Source is too large")
                  }
                  for i = 0; i < src_len; i = i + 1 {
                    let val = arr_data.elements[i]
                    let num = to_number(val)
                    typedarray_set_index(data, target_offset + i, num)
                  }
                  Undefined
                }
                _ => {
                  // Array-like with length property
                  Undefined
                }
              }
            } else {
              raise @errors.TypeError(message="TypedArray.prototype.set called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="TypedArray.prototype.set called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // subarray(begin, end)
  ta_proto_props["subarray"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("subarray", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let ta_length = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let relative_begin = if args.length() > 0 {
                to_number(args[0]).to_int()
              } else {
                0
              }
              let begin_index = if relative_begin < 0 {
                let b = ta_length + relative_begin
                if b < 0 { 0 } else { b }
              } else if relative_begin > ta_length {
                ta_length
              } else {
                relative_begin
              }
              let relative_end = if args.length() > 1 {
                match args[1] {
                  Undefined => ta_length
                  _ => to_number(args[1]).to_int()
                }
              } else {
                ta_length
              }
              let end_index = if relative_end < 0 {
                let e = ta_length + relative_end
                if e < 0 { 0 } else { e }
              } else if relative_end > ta_length {
                ta_length
              } else {
                relative_end
              }
              let new_length = if end_index > begin_index {
                end_index - begin_index
              } else {
                0
              }
              let buffer = match data.properties.get("[[ViewedArrayBuffer]]") {
                Some(buf) => buf
                None =>
                  raise @errors.TypeError(message="TypedArray has no buffer")
              }
              let cur_offset = match data.properties.get("[[ByteOffset]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let bpe = typed_array_bytes_per_element(data.class_name)
              let new_offset = cur_offset + begin_index * bpe
              // Get the prototype for this typed array type
              let proto = data.prototype
              make_typedarray_from_buffer(
                data.class_name,
                buffer,
                new_offset,
                new_length,
                proto,
              )
            } else {
              raise @errors.TypeError(message="subarray called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="subarray called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // slice(begin, end)
  ta_proto_props["slice"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("slice", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let ta_length = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let relative_begin = if args.length() > 0 {
                to_number(args[0]).to_int()
              } else {
                0
              }
              let begin_index = if relative_begin < 0 {
                let b = ta_length + relative_begin
                if b < 0 { 0 } else { b }
              } else if relative_begin > ta_length {
                ta_length
              } else {
                relative_begin
              }
              let relative_end = if args.length() > 1 {
                match args[1] {
                  Undefined => ta_length
                  _ => to_number(args[1]).to_int()
                }
              } else {
                ta_length
              }
              let end_index = if relative_end < 0 {
                let e = ta_length + relative_end
                if e < 0 { 0 } else { e }
              } else if relative_end > ta_length {
                ta_length
              } else {
                relative_end
              }
              let new_length = if end_index > begin_index {
                end_index - begin_index
              } else {
                0
              }
              let proto = data.prototype
              let new_ta = make_typedarray_object(
                data.class_name,
                new_length,
                proto,
                env,
              )
              match new_ta {
                Object(new_data) =>
                  for i = 0; i < new_length; i = i + 1 {
                    let val = typedarray_get_index(data, begin_index + i)
                    let num = match val {
                      Number(n) => n
                      _ => 0.0
                    }
                    typedarray_set_index(new_data, i, num)
                  }
                _ => ()
              }
              new_ta
            } else {
              raise @errors.TypeError(message="slice called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="slice called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // copyWithin(target, start [, end])
  ta_proto_props["copyWithin"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("copyWithin", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let target_idx = if args.length() > 0 {
                let t = to_number(args[0]).to_int()
                if t < 0 { let r = len + t; if r < 0 { 0 } else { r } } else { if t > len { len } else { t } }
              } else { 0 }
              let start_idx = if args.length() > 1 {
                let s = to_number(args[1]).to_int()
                if s < 0 { let r = len + s; if r < 0 { 0 } else { r } } else { if s > len { len } else { s } }
              } else { 0 }
              let end_idx = if args.length() > 2 {
                match args[2] {
                  Undefined => len
                  _ => {
                    let e = to_number(args[2]).to_int()
                    if e < 0 { let r = len + e; if r < 0 { 0 } else { r } } else { if e > len { len } else { e } }
                  }
                }
              } else { len }
              let count = {
                let c1 = end_idx - start_idx
                let c2 = len - target_idx
                if c1 < c2 { c1 } else { c2 }
              }
              if count > 0 {
                // Read all source values first to handle overlapping
                let temp : Array[Double] = []
                for i = 0; i < count; i = i + 1 {
                  let val = typedarray_get_index(data, start_idx + i)
                  match val {
                    Number(n) => temp.push(n)
                    _ => temp.push(0.0)
                  }
                }
                for i = 0; i < count; i = i + 1 {
                  typedarray_set_index(data, target_idx + i, temp[i])
                }
              }
              this_val
            } else {
              raise @errors.TypeError(message="copyWithin called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="copyWithin called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // fill(value [, start [, end]])
  ta_proto_props["fill"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("fill", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let fill_val = if args.length() > 0 {
                to_number(args[0])
              } else {
                0.0
              }
              let start_idx = if args.length() > 1 {
                let s = to_number(args[1]).to_int()
                if s < 0 { let r = len + s; if r < 0 { 0 } else { r } } else { if s > len { len } else { s } }
              } else { 0 }
              let end_idx = if args.length() > 2 {
                match args[2] {
                  Undefined => len
                  _ => {
                    let e = to_number(args[2]).to_int()
                    if e < 0 { let r = len + e; if r < 0 { 0 } else { r } } else { if e > len { len } else { e } }
                  }
                }
              } else { len }
              for i = start_idx; i < end_idx; i = i + 1 {
                typedarray_set_index(data, i, fill_val)
              }
              this_val
            } else {
              raise @errors.TypeError(message="fill called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="fill called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // indexOf(searchElement [, fromIndex])
  ta_proto_props["indexOf"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("indexOf", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              if len == 0 || args.length() == 0 {
                return Number(-1.0)
              }
              let search_val = to_number(args[0])
              let from_idx = if args.length() > 1 {
                let f = to_number(args[1]).to_int()
                if f < 0 { let r = len + f; if r < 0 { 0 } else { r } } else { f }
              } else { 0 }
              for i = from_idx; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                match elem {
                  Number(n) =>
                    if n == search_val {
                      return Number(i.to_double())
                    }
                  _ => ()
                }
              }
              Number(-1.0)
            } else {
              Number(-1.0)
            }
          _ => Number(-1.0)
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // lastIndexOf(searchElement [, fromIndex])
  ta_proto_props["lastIndexOf"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("lastIndexOf", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              if len == 0 || args.length() == 0 {
                return Number(-1.0)
              }
              let search_val = to_number(args[0])
              let from_idx = if args.length() > 1 {
                let f = to_number(args[1]).to_int()
                if f < 0 { len + f } else { if f >= len { len - 1 } else { f } }
              } else { len - 1 }
              for i = from_idx; i >= 0; i = i - 1 {
                let elem = typedarray_get_index(data, i)
                match elem {
                  Number(n) =>
                    if n == search_val {
                      return Number(i.to_double())
                    }
                  _ => ()
                }
              }
              Number(-1.0)
            } else {
              Number(-1.0)
            }
          _ => Number(-1.0)
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // includes(searchElement [, fromIndex])
  ta_proto_props["includes"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("includes", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              if len == 0 || args.length() == 0 {
                return Bool(false)
              }
              let search_val = to_number(args[0])
              let from_idx = if args.length() > 1 {
                let f = to_number(args[1]).to_int()
                if f < 0 { let r = len + f; if r < 0 { 0 } else { r } } else { f }
              } else { 0 }
              for i = from_idx; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                match elem {
                  Number(n) =>
                    if n == search_val || (n.is_nan() && search_val.is_nan()) {
                      return Bool(true)
                    }
                  _ => ()
                }
              }
              Bool(false)
            } else {
              Bool(false)
            }
          _ => Bool(false)
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // join(separator)
  ta_proto_props["join"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("join", fn(this_val, args) {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let sep = if args.length() > 0 {
                match args[0] {
                  Undefined => ","
                  _ => args[0].to_string()
                }
              } else {
                ","
              }
              let buf = StringBuilder::new()
              for i = 0; i < len; i = i + 1 {
                if i > 0 {
                  buf.write_string(sep)
                }
                let elem = typedarray_get_index(data, i)
                buf.write_string(elem.to_string())
              }
              String_(buf.to_string())
            } else {
              String_("")
            }
          _ => String_("")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // toString - delegates to join
  ta_proto_props["toString"] = Object({
    properties: { "length": Number(0.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("toString", fn(this_val, _args) {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let buf = StringBuilder::new()
              for i = 0; i < len; i = i + 1 {
                if i > 0 {
                  buf.write_string(",")
                }
                let elem = typedarray_get_index(data, i)
                buf.write_string(elem.to_string())
              }
              String_(buf.to_string())
            } else {
              String_("[object Object]")
            }
          _ => String_("[object Object]")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // reverse()
  ta_proto_props["reverse"] = Object({
    properties: { "length": Number(0.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("reverse", fn(this_val, _args) {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let mut lo = 0
              let mut hi = len - 1
              while lo < hi {
                let lo_val = typedarray_get_index(data, lo)
                let hi_val = typedarray_get_index(data, hi)
                let lo_num = match lo_val { Number(n) => n; _ => 0.0 }
                let hi_num = match hi_val { Number(n) => n; _ => 0.0 }
                typedarray_set_index(data, lo, hi_num)
                typedarray_set_index(data, hi, lo_num)
                lo = lo + 1
                hi = hi - 1
              }
              this_val
            } else {
              this_val
            }
          _ => this_val
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // sort([comparefn]) - uses InterpreterCallable for custom comparator support
  ta_proto_props["sort"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("sort", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              // Read all elements into temp array
              let temp : Array[Double] = []
              for i = 0; i < len; i = i + 1 {
                let val = typedarray_get_index(data, i)
                match val {
                  Number(n) => temp.push(n)
                  _ => temp.push(0.0)
                }
              }
              let has_comparefn = args.length() > 0 && not(args[0] is Undefined)
              let mut caught_error : Error? = None
              if has_comparefn {
                let comparefn = args[0]
                let loc = @token.Loc::default()
                temp.sort_by(fn(a, b) {
                  if caught_error is Some(_) {
                    return 0
                  }
                  let result = interp.call_value(
                    comparefn,
                    Undefined,
                    [Number(a), Number(b)],
                    loc,
                  ) catch {
                    e => {
                      caught_error = Some(e)
                      return 0
                    }
                  }
                  let cmp = to_number(result) catch {
                    e => {
                      caught_error = Some(e)
                      return 0
                    }
                  }
                  if cmp.is_nan() {
                    0
                  } else if cmp < 0.0 {
                    -1
                  } else if cmp > 0.0 {
                    1
                  } else {
                    0
                  }
                })
              } else {
                // Default numeric sort per spec: NaN sorts last, -0 < +0
                temp.sort_by(fn(a, b) {
                  if a.is_nan() && b.is_nan() {
                    return 0
                  }
                  if a.is_nan() {
                    return 1
                  }
                  if b.is_nan() {
                    return -1
                  }
                  if a == 0.0 && b == 0.0 {
                    // Distinguish -0 and +0: -0 < +0
                    let a_neg = 1.0 / a < 0.0
                    let b_neg = 1.0 / b < 0.0
                    if a_neg && not(b_neg) {
                      return -1
                    }
                    if not(a_neg) && b_neg {
                      return 1
                    }
                    return 0
                  }
                  if a < b {
                    -1
                  } else if a > b {
                    1
                  } else {
                    0
                  }
                })
              }
              match caught_error {
                Some(e) => raise e
                None => ()
              }
              // Write sorted elements back
              for i = 0; i < len; i = i + 1 {
                typedarray_set_index(data, i, temp[i])
              }
              this_val
            } else {
              this_val
            }
          _ => this_val
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // at(index)
  ta_proto_props["at"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("at", fn(this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let idx = if args.length() > 0 {
                to_number(args[0]).to_int()
              } else {
                0
              }
              let actual_idx = if idx < 0 { len + idx } else { idx }
              if actual_idx < 0 || actual_idx >= len {
                Undefined
              } else {
                typedarray_get_index(data, actual_idx)
              }
            } else {
              Undefined
            }
          _ => Undefined
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // entries() - returns an iterator of [index, value] pairs
  ta_proto_props["entries"] = Object({
    properties: { "length": Number(0.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("entries", fn(this_val, _args) {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let index_ref : Ref[Int] = { val: 0 }
              let next_method = make_native_func("next", fn(_a) raise {
                // Re-check detachment and length on each next() call per spec
                let buf_id = match data.properties.get("[[ArrayBufferID]]") {
                  Some(Number(n)) => n.to_int()
                  _ => -1
                }
                if buf_id >= 0 && is_arraybuffer_detached(buf_id) {
                  raise @errors.TypeError(message="Cannot iterate over a detached ArrayBuffer")
                }
                let len = match data.properties.get("[[ArrayLength]]") {
                  Some(Number(n)) => n.to_int()
                  _ => 0
                }
                let idx = index_ref.val
                if idx < len {
                  let value = typedarray_get_index(data, idx)
                  index_ref.val = idx + 1
                  let pair = Array({ elements: [Number(idx.to_double()), value] })
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = pair
                  result_props["done"] = Bool(false)
                  Object({
                    properties: result_props,
                    symbol_properties: {},
                    prototype: Null,
                    callable: None,
                    class_name: "Object",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  })
                } else {
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = Undefined
                  result_props["done"] = Bool(true)
                  Object({
                    properties: result_props,
                    symbol_properties: {},
                    prototype: Null,
                    callable: None,
                    class_name: "Object",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  })
                }
              })
              let iter_props : Map[String, Value] = {}
              iter_props["next"] = next_method
              let iter_sym_props : Map[Int, Value] = {}
              iter_sym_props[iterator_sym.id] = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  MethodCallable("[Symbol.iterator]", fn(tv, _a) { tv }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              Object({
                properties: iter_props,
                symbol_properties: iter_sym_props,
                prototype: Null,
                callable: None,
                class_name: "Array Iterator",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            } else {
              Undefined
            }
          _ => Undefined
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // keys() - returns an iterator of indices
  ta_proto_props["keys"] = Object({
    properties: { "length": Number(0.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("keys", fn(this_val, _args) {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let index_ref : Ref[Int] = { val: 0 }
              let next_method = make_native_func("next", fn(_a) raise {
                // Re-check detachment and length on each next() call per spec
                let buf_id = match data.properties.get("[[ArrayBufferID]]") {
                  Some(Number(n)) => n.to_int()
                  _ => -1
                }
                if buf_id >= 0 && is_arraybuffer_detached(buf_id) {
                  raise @errors.TypeError(message="Cannot iterate over a detached ArrayBuffer")
                }
                let len = match data.properties.get("[[ArrayLength]]") {
                  Some(Number(n)) => n.to_int()
                  _ => 0
                }
                let idx = index_ref.val
                if idx < len {
                  index_ref.val = idx + 1
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = Number(idx.to_double())
                  result_props["done"] = Bool(false)
                  Object({
                    properties: result_props,
                    symbol_properties: {},
                    prototype: Null,
                    callable: None,
                    class_name: "Object",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  })
                } else {
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = Undefined
                  result_props["done"] = Bool(true)
                  Object({
                    properties: result_props,
                    symbol_properties: {},
                    prototype: Null,
                    callable: None,
                    class_name: "Object",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  })
                }
              })
              let iter_props : Map[String, Value] = {}
              iter_props["next"] = next_method
              let iter_sym_props : Map[Int, Value] = {}
              iter_sym_props[iterator_sym.id] = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  MethodCallable("[Symbol.iterator]", fn(tv, _a) { tv }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              Object({
                properties: iter_props,
                symbol_properties: iter_sym_props,
                prototype: Null,
                callable: None,
                class_name: "Array Iterator",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            } else {
              Undefined
            }
          _ => Undefined
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // values() - returns an iterator of values (same as [Symbol.iterator])
  let values_fn = Object({
    properties: { "length": Number(0.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("values", fn(this_val, _args) {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              let index_ref : Ref[Int] = { val: 0 }
              let next_method = make_native_func("next", fn(_a) raise {
                // Re-check detachment and length on each next() call per spec
                let buf_id = match data.properties.get("[[ArrayBufferID]]") {
                  Some(Number(n)) => n.to_int()
                  _ => -1
                }
                if buf_id >= 0 && is_arraybuffer_detached(buf_id) {
                  raise @errors.TypeError(message="Cannot iterate over a detached ArrayBuffer")
                }
                let len = match data.properties.get("[[ArrayLength]]") {
                  Some(Number(n)) => n.to_int()
                  _ => 0
                }
                let idx = index_ref.val
                if idx < len {
                  let value = typedarray_get_index(data, idx)
                  index_ref.val = idx + 1
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = value
                  result_props["done"] = Bool(false)
                  Object({
                    properties: result_props,
                    symbol_properties: {},
                    prototype: Null,
                    callable: None,
                    class_name: "Object",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  })
                } else {
                  let result_props : Map[String, Value] = {}
                  result_props["value"] = Undefined
                  result_props["done"] = Bool(true)
                  Object({
                    properties: result_props,
                    symbol_properties: {},
                    prototype: Null,
                    callable: None,
                    class_name: "Object",
                    descriptors: {},
                    symbol_descriptors: {},
                    extensible: true,
                  })
                }
              })
              let iter_props : Map[String, Value] = {}
              iter_props["next"] = next_method
              let iter_sym_props : Map[Int, Value] = {}
              iter_sym_props[iterator_sym.id] = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  MethodCallable("[Symbol.iterator]", fn(tv, _a) { tv }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              Object({
                properties: iter_props,
                symbol_properties: iter_sym_props,
                prototype: Null,
                callable: None,
                class_name: "Array Iterator",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            } else {
              Undefined
            }
          _ => Undefined
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  ta_proto_props["values"] = values_fn

  // forEach(callbackFn [, thisArg])
  ta_proto_props["forEach"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("forEach", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="forEach requires a callback function")
              }
              let callback = args[0]
              let this_arg = if args.length() > 1 { args[1] } else { Undefined }
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              for i = 0; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                let _ = interp.call_value(callback, this_arg, [elem, Number(i.to_double()), this_val], loc)
              }
              Undefined
            } else {
              raise @errors.TypeError(message="forEach called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="forEach called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // map(callbackFn [, thisArg])
  ta_proto_props["map"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("map", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="map requires a callback function")
              }
              let callback = args[0]
              let this_arg = if args.length() > 1 { args[1] } else { Undefined }
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              let result = make_typedarray_object(data.class_name, len, data.prototype, env)
              match result {
                Object(result_data) =>
                  for i = 0; i < len; i = i + 1 {
                    let elem = typedarray_get_index(data, i)
                    let mapped = interp.call_value(callback, this_arg, [elem, Number(i.to_double()), this_val], loc)
                    let num = to_number(mapped)
                    typedarray_set_index(result_data, i, num)
                  }
                _ => ()
              }
              result
            } else {
              raise @errors.TypeError(message="map called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="map called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // filter(callbackFn [, thisArg])
  ta_proto_props["filter"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("filter", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="filter requires a callback function")
              }
              let callback = args[0]
              let this_arg = if args.length() > 1 { args[1] } else { Undefined }
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              let kept : Array[Double] = []
              for i = 0; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                let result = interp.call_value(callback, this_arg, [elem, Number(i.to_double()), this_val], loc)
                if is_truthy(result) {
                  match elem {
                    Number(n) => kept.push(n)
                    _ => kept.push(0.0)
                  }
                }
              }
              let result = make_typedarray_object(data.class_name, kept.length(), data.prototype, env)
              match result {
                Object(result_data) =>
                  for i = 0; i < kept.length(); i = i + 1 {
                    typedarray_set_index(result_data, i, kept[i])
                  }
                _ => ()
              }
              result
            } else {
              raise @errors.TypeError(message="filter called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="filter called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // reduce(callbackFn [, initialValue])
  ta_proto_props["reduce"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("reduce", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="reduce requires a callback function")
              }
              let callback = args[0]
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              let mut accumulator : Value = Undefined
              let mut start_idx = 0
              if args.length() > 1 {
                accumulator = args[1]
              } else {
                if len == 0 {
                  raise @errors.TypeError(message="Reduce of empty array with no initial value")
                }
                accumulator = typedarray_get_index(data, 0)
                start_idx = 1
              }
              for i = start_idx; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                accumulator = interp.call_value(callback, Undefined, [accumulator, elem, Number(i.to_double()), this_val], loc)
              }
              accumulator
            } else {
              raise @errors.TypeError(message="reduce called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="reduce called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // reduceRight(callbackFn [, initialValue])
  ta_proto_props["reduceRight"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("reduceRight", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="reduceRight requires a callback function")
              }
              let callback = args[0]
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              let mut accumulator : Value = Undefined
              let mut start_idx = len - 1
              if args.length() > 1 {
                accumulator = args[1]
              } else {
                if len == 0 {
                  raise @errors.TypeError(message="Reduce of empty array with no initial value")
                }
                accumulator = typedarray_get_index(data, len - 1)
                start_idx = len - 2
              }
              for i = start_idx; i >= 0; i = i - 1 {
                let elem = typedarray_get_index(data, i)
                accumulator = interp.call_value(callback, Undefined, [accumulator, elem, Number(i.to_double()), this_val], loc)
              }
              accumulator
            } else {
              raise @errors.TypeError(message="reduceRight called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="reduceRight called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // every(callbackFn [, thisArg])
  ta_proto_props["every"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("every", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="every requires a callback function")
              }
              let callback = args[0]
              let this_arg = if args.length() > 1 { args[1] } else { Undefined }
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              for i = 0; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                let result = interp.call_value(callback, this_arg, [elem, Number(i.to_double()), this_val], loc)
                if not(is_truthy(result)) {
                  return Bool(false)
                }
              }
              Bool(true)
            } else {
              raise @errors.TypeError(message="every called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="every called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // some(callbackFn [, thisArg])
  ta_proto_props["some"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("some", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="some requires a callback function")
              }
              let callback = args[0]
              let this_arg = if args.length() > 1 { args[1] } else { Undefined }
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              for i = 0; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                let result = interp.call_value(callback, this_arg, [elem, Number(i.to_double()), this_val], loc)
                if is_truthy(result) {
                  return Bool(true)
                }
              }
              Bool(false)
            } else {
              raise @errors.TypeError(message="some called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="some called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // find(callbackFn [, thisArg])
  ta_proto_props["find"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("find", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="find requires a callback function")
              }
              let callback = args[0]
              let this_arg = if args.length() > 1 { args[1] } else { Undefined }
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              for i = 0; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                let result = interp.call_value(callback, this_arg, [elem, Number(i.to_double()), this_val], loc)
                if is_truthy(result) {
                  return elem
                }
              }
              Undefined
            } else {
              raise @errors.TypeError(message="find called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="find called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // findIndex(callbackFn [, thisArg])
  ta_proto_props["findIndex"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("findIndex", fn(interp, this_val, args) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              validate_typedarray_buffer(data)
              if args.length() == 0 {
                raise @errors.TypeError(message="findIndex requires a callback function")
              }
              let callback = args[0]
              let this_arg = if args.length() > 1 { args[1] } else { Undefined }
              let len = match data.properties.get("[[ArrayLength]]") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let loc = @token.Loc::default()
              for i = 0; i < len; i = i + 1 {
                let elem = typedarray_get_index(data, i)
                let result = interp.call_value(callback, this_arg, [elem, Number(i.to_double()), this_val], loc)
                if is_truthy(result) {
                  return Number(i.to_double())
                }
              }
              Number(-1.0)
            } else {
              raise @errors.TypeError(message="findIndex called on non-TypedArray")
            }
          _ => raise @errors.TypeError(message="findIndex called on non-TypedArray")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Mark all prototype methods as non-enumerable (per spec)
  let method_names = [
    "set", "subarray", "slice", "copyWithin", "fill",
    "indexOf", "lastIndexOf", "includes", "join", "toString",
    "reverse", "sort", "at", "entries", "keys", "values",
    "forEach", "map", "filter", "reduce", "reduceRight",
    "every", "some", "find", "findIndex",
  ]
  for name in method_names {
    ta_proto_descs[name] = {
      writable: true,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
    }
  }

  // Create the shared %TypedArray%.prototype
  let ta_proto_sym_props : Map[Int, Value] = {}
  ta_proto_sym_props[iterator_sym.id] = values_fn // [Symbol.iterator] = values
  // Symbol.toStringTag getter - returns the constructor name dynamically
  ta_proto_sym_props[tostringtag_sym.id] = Undefined // placeholder
  let ta_proto_sym_descs : Map[Int, PropDescriptor] = {}
  ta_proto_sym_descs[iterator_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  ta_proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(
      Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("get [Symbol.toStringTag]", fn(this_val, _args) {
            match this_val {
              Object(data) =>
                if is_typedarray_class(data.class_name) {
                  String_(data.class_name)
                } else {
                  Undefined
                }
              _ => Undefined
            }
          }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      }),
    ),
    setter: None,
  }

  let ta_proto : Value = Object({
    properties: ta_proto_props,
    symbol_properties: ta_proto_sym_props,
    prototype: obj_proto,
    callable: None,
    class_name: "Object",
    descriptors: ta_proto_descs,
    symbol_descriptors: ta_proto_sym_descs,
    extensible: true,
  })
  env.def_builtin("[[TypedArrayPrototype]]", ta_proto)

  // --- Create individual TypedArray constructors ---
  let type_names = [
    "Int8Array", "Uint8Array", "Uint8ClampedArray",
    "Int16Array", "Uint16Array",
    "Int32Array", "Uint32Array",
    "Float32Array", "Float64Array",
  ]

  for type_name in type_names {
    let bpe = typed_array_bytes_per_element(type_name)

    // Per-type prototype inheriting from %TypedArray%.prototype
    let per_proto_props : Map[String, Value] = {}
    per_proto_props["BYTES_PER_ELEMENT"] = Number(bpe.to_double())
    let per_proto_descs : Map[String, PropDescriptor] = {}
    per_proto_descs["BYTES_PER_ELEMENT"] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
    }

    let per_proto : Value = Object({
      properties: per_proto_props,
      symbol_properties: {},
      prototype: ta_proto,
      callable: None,
      class_name: "Object",
      descriptors: per_proto_descs,
      symbol_descriptors: {},
      extensible: true,
    })

    // Constructor
    let ctor_props : Map[String, Value] = {}
    ctor_props["prototype"] = per_proto
    ctor_props["BYTES_PER_ELEMENT"] = Number(bpe.to_double())

    // Static from(source [, mapFn [, thisArg]])
    ctor_props["from"] = Object({
      properties: { "length": Number(1.0) },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        InterpreterCallable("from", fn(interp, _this_val, args) raise {
          if args.length() == 0 {
            raise @errors.TypeError(message="TypedArray.from requires at least 1 argument")
          }
          let source = args[0]
          let has_map_fn = args.length() > 1 && not(args[1] is Undefined)
          let map_fn = if has_map_fn { args[1] } else { Undefined }
          let this_arg = if args.length() > 2 { args[2] } else { Undefined }
          // Collect source values first
          let source_values : Array[Value] = []
          match source {
            Array(arr_data) =>
              for elem in arr_data.elements {
                source_values.push(elem)
              }
            Object(src_data) =>
              if is_typedarray_class(src_data.class_name) {
                let src_len = match src_data.properties.get("[[ArrayLength]]") {
                  Some(Number(n)) => n.to_int()
                  _ => 0
                }
                for i = 0; i < src_len; i = i + 1 {
                  source_values.push(typedarray_get_index(src_data, i))
                }
              } else {
                // Try length property
                match src_data.properties.get("length") {
                  Some(Number(len_n)) => {
                    let len = len_n.to_int()
                    for i = 0; i < len; i = i + 1 {
                      match src_data.properties.get(i.to_string()) {
                        Some(v) => source_values.push(v)
                        None => source_values.push(Undefined)
                      }
                    }
                  }
                  _ => ()
                }
              }
            _ => ()
          }
          // Apply mapFn if provided, then convert to numbers
          let elements : Array[Double] = []
          let loc = @token.Loc::default()
          for i = 0; i < source_values.length(); i = i + 1 {
            let val = source_values[i]
            let mapped = if has_map_fn {
              interp.call_value(
                map_fn,
                this_arg,
                [val, Number(i.to_double())],
                loc,
              )
            } else {
              val
            }
            elements.push(to_number(mapped))
          }
          let result = make_typedarray_object(type_name, elements.length(), per_proto, env)
          match result {
            Object(result_data) =>
              for i = 0; i < elements.length(); i = i + 1 {
                typedarray_set_index(result_data, i, elements[i])
              }
            _ => ()
          }
          result
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })

    // Static of(...items)
    ctor_props["of"] = Object({
      properties: { "length": Number(0.0) },
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("of", fn(args) raise {
          let result = make_typedarray_object(type_name, args.length(), per_proto, env)
          match result {
            Object(result_data) =>
              for i = 0; i < args.length(); i = i + 1 {
                let num = to_number(args[i])
                typedarray_set_index(result_data, i, num)
              }
            _ => ()
          }
          result
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })

    let ctor_descs : Map[String, PropDescriptor] = {}
    ctor_descs["prototype"] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
    }
    ctor_descs["BYTES_PER_ELEMENT"] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
    }

    let ctor : Value = Object({
      properties: ctor_props,
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable(type_name, fn(args) raise {
          if not(is_constructing.val) {
            raise @errors.TypeError(
              message="Constructor \{type_name} requires 'new'",
            )
          }
          if args.length() == 0 {
            return make_typedarray_object(type_name, 0, per_proto, env)
          }
          let first = args[0]
          match first {
            Number(n) => {
              let length = n.to_int()
              if length < 0 || n != length.to_double() || n.is_nan() {
                raise @errors.RangeError(message="Invalid typed array length: \{n}")
              }
              make_typedarray_object(type_name, length, per_proto, env)
            }
            // From another TypedArray
            Object(src_data) if is_typedarray_class(src_data.class_name) => {
              let src_len = match src_data.properties.get("[[ArrayLength]]") {
                Some(Number(ln)) => ln.to_int()
                _ => 0
              }
              let result = make_typedarray_object(type_name, src_len, per_proto, env)
              match result {
                Object(result_data) =>
                  for i = 0; i < src_len; i = i + 1 {
                    let val = typedarray_get_index(src_data, i)
                    let num = match val {
                      Number(nv) => nv
                      _ => 0.0
                    }
                    typedarray_set_index(result_data, i, num)
                  }
                _ => ()
              }
              result
            }
            // From ArrayBuffer
            Object(buf_data) if buf_data.class_name == "ArrayBuffer" => {
              // Check for detached buffer
              let check_buf_id = match buf_data.properties.get("[[ArrayBufferID]]") {
                Some(Number(n)) => n.to_int()
                _ => -1
              }
              if check_buf_id >= 0 && is_arraybuffer_detached(check_buf_id) {
                raise @errors.TypeError(
                  message="Cannot construct a TypedArray with a detached ArrayBuffer",
                )
              }
              let buf_byte_length = match buf_data.properties.get(
                "[[ArrayBufferByteLength]]",
              ) {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
              let byte_offset = if args.length() > 1 {
                match args[1] {
                  Undefined => 0
                  _ => {
                    let n = to_number(args[1]).to_int()
                    if n < 0 {
                      raise @errors.RangeError(
                        message="Start offset \{n} is outside the bounds of the buffer",
                      )
                    }
                    n
                  }
                }
              } else {
                0
              }
              if byte_offset % bpe != 0 {
                raise @errors.RangeError(
                  message="start offset of \{type_name} should be a multiple of \{bpe}",
                )
              }
              let length = if args.length() > 2 {
                match args[2] {
                  Undefined =>
                    if (buf_byte_length - byte_offset) % bpe != 0 {
                      raise @errors.RangeError(
                        message="byte length of \{type_name} should be a multiple of \{bpe}",
                      )
                    } else {
                      (buf_byte_length - byte_offset) / bpe
                    }
                  _ => to_number(args[2]).to_int()
                }
              } else if (buf_byte_length - byte_offset) % bpe != 0 {
                raise @errors.RangeError(
                  message="byte length of \{type_name} should be a multiple of \{bpe}",
                )
              } else {
                (buf_byte_length - byte_offset) / bpe
              }
              if byte_offset + length * bpe > buf_byte_length {
                raise @errors.RangeError(
                  message="Invalid typed array length: \{length}",
                )
              }
              make_typedarray_from_buffer(
                type_name,
                first,
                byte_offset,
                length,
                per_proto,
              )
            }
            // From array-like or iterable
            Array(arr_data) => {
              let len = arr_data.elements.length()
              let result = make_typedarray_object(type_name, len, per_proto, env)
              match result {
                Object(result_data) =>
                  for i = 0; i < len; i = i + 1 {
                    let num = to_number(arr_data.elements[i])
                    typedarray_set_index(result_data, i, num)
                  }
                _ => ()
              }
              result
            }
            // From generic object with length
            Object(src_data) => {
              match src_data.properties.get("length") {
                Some(Number(len_n)) => {
                  let len = len_n.to_int()
                  let result = make_typedarray_object(type_name, len, per_proto, env)
                  match result {
                    Object(result_data) =>
                      for i = 0; i < len; i = i + 1 {
                        match src_data.properties.get(i.to_string()) {
                          Some(v) => {
                            let num = to_number(v)
                            typedarray_set_index(result_data, i, num)
                          }
                          None => ()
                        }
                      }
                    _ => ()
                  }
                  result
                }
                _ =>
                  make_typedarray_object(type_name, 0, per_proto, env)
              }
            }
            _ =>
              make_typedarray_object(type_name, 0, per_proto, env)
          }
        }),
      ),
      class_name: "Function",
      descriptors: ctor_descs,
      symbol_descriptors: {},
      extensible: true,
    })

    // Link constructor
    match per_proto {
      Object(proto_data) => {
        proto_data.properties["constructor"] = ctor
        proto_data.descriptors["constructor"] = {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        }
      }
      _ => ()
    }

    env.def_builtin(type_name, ctor)
    env.def_builtin("[[\{type_name}Prototype]]", per_proto)
  }
}

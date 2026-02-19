///|
/// Read bytes from an ArrayBuffer for DataView operations.
/// Handles endianness (little_endian parameter).
fn dataview_get_int8(bytes : Array[Int], offset : Int) -> Value {
  let v = bytes[offset]
  let signed = if v >= 128 { v - 256 } else { v }
  Number(signed.to_double())
}

///|
fn dataview_get_uint8(bytes : Array[Int], offset : Int) -> Value {
  Number(bytes[offset].to_double())
}

///|
fn dataview_get_int16(
  bytes : Array[Int],
  offset : Int,
  little_endian : Bool,
) -> Value {
  let lo = if little_endian { bytes[offset] } else { bytes[offset + 1] }
  let hi = if little_endian { bytes[offset + 1] } else { bytes[offset] }
  let v = lo + hi * 256
  let signed = if v >= 32768 { v - 65536 } else { v }
  Number(signed.to_double())
}

///|
fn dataview_get_uint16(
  bytes : Array[Int],
  offset : Int,
  little_endian : Bool,
) -> Value {
  let lo = if little_endian { bytes[offset] } else { bytes[offset + 1] }
  let hi = if little_endian { bytes[offset + 1] } else { bytes[offset] }
  Number((lo + hi * 256).to_double())
}

///|
fn dataview_get_int32(
  bytes : Array[Int],
  offset : Int,
  little_endian : Bool,
) -> Value {
  let b0 = if little_endian { bytes[offset] } else { bytes[offset + 3] }
  let b1 = if little_endian { bytes[offset + 1] } else { bytes[offset + 2] }
  let b2 = if little_endian { bytes[offset + 2] } else { bytes[offset + 1] }
  let b3 = if little_endian { bytes[offset + 3] } else { bytes[offset] }
  let v = b0.to_int64() +
    b1.to_int64() * 256L +
    b2.to_int64() * 65536L +
    b3.to_int64() * 16777216L
  let signed = if v >= 2147483648L { v - 4294967296L } else { v }
  Number(signed.to_double())
}

///|
fn dataview_get_uint32(
  bytes : Array[Int],
  offset : Int,
  little_endian : Bool,
) -> Value {
  let b0 = if little_endian { bytes[offset] } else { bytes[offset + 3] }
  let b1 = if little_endian { bytes[offset + 1] } else { bytes[offset + 2] }
  let b2 = if little_endian { bytes[offset + 2] } else { bytes[offset + 1] }
  let b3 = if little_endian { bytes[offset + 3] } else { bytes[offset] }
  let v = b0.to_int64() +
    b1.to_int64() * 256L +
    b2.to_int64() * 65536L +
    b3.to_int64() * 16777216L
  Number(v.to_double())
}

///|
fn dataview_get_float32(
  bytes : Array[Int],
  offset : Int,
  little_endian : Bool,
) -> Value {
  let b0 = if little_endian { bytes[offset] } else { bytes[offset + 3] }
  let b1 = if little_endian { bytes[offset + 1] } else { bytes[offset + 2] }
  let b2 = if little_endian { bytes[offset + 2] } else { bytes[offset + 1] }
  let b3 = if little_endian { bytes[offset + 3] } else { bytes[offset] }
  let bits64 = b0.to_int64() +
    b1.to_int64() * 256L +
    b2.to_int64() * 65536L +
    b3.to_int64() * 16777216L
  Number(float32_bits_to_double(bits64.to_int()))
}

///|
fn dataview_get_float64(
  bytes : Array[Int],
  offset : Int,
  little_endian : Bool,
) -> Value {
  let mut bits = 0L
  if little_endian {
    for i = 0; i < 8; i = i + 1 {
      bits = bits + (bytes[offset + i].to_int64() << (i * 8))
    }
  } else {
    for i = 0; i < 8; i = i + 1 {
      bits = bits + (bytes[offset + i].to_int64() << ((7 - i) * 8))
    }
  }
  Number(bits.reinterpret_as_double())
}

///|
/// Set bytes in an ArrayBuffer for DataView operations.
fn dataview_set_int8(bytes : Array[Int], offset : Int, value : Double) -> Unit {
  let v = to_int32(value) & 0xFF
  bytes[offset] = v
}

///|
fn dataview_set_uint8(bytes : Array[Int], offset : Int, value : Double) -> Unit {
  let v = to_int32(value) & 0xFF
  bytes[offset] = v
}

///|
fn dataview_set_int16(
  bytes : Array[Int],
  offset : Int,
  value : Double,
  little_endian : Bool,
) -> Unit {
  let v = to_int32(value) & 0xFFFF
  if little_endian {
    bytes[offset] = v & 0xFF
    bytes[offset + 1] = (v >> 8) & 0xFF
  } else {
    bytes[offset] = (v >> 8) & 0xFF
    bytes[offset + 1] = v & 0xFF
  }
}

///|
fn dataview_set_uint16(
  bytes : Array[Int],
  offset : Int,
  value : Double,
  little_endian : Bool,
) -> Unit {
  let v = to_int32(value) & 0xFFFF
  if little_endian {
    bytes[offset] = v & 0xFF
    bytes[offset + 1] = (v >> 8) & 0xFF
  } else {
    bytes[offset] = (v >> 8) & 0xFF
    bytes[offset + 1] = v & 0xFF
  }
}

///|
fn dataview_set_int32(
  bytes : Array[Int],
  offset : Int,
  value : Double,
  little_endian : Bool,
) -> Unit {
  let v = to_int32(value)
  if little_endian {
    bytes[offset] = v & 0xFF
    bytes[offset + 1] = (v >> 8) & 0xFF
    bytes[offset + 2] = (v >> 16) & 0xFF
    bytes[offset + 3] = (v >> 24) & 0xFF
  } else {
    bytes[offset] = (v >> 24) & 0xFF
    bytes[offset + 1] = (v >> 16) & 0xFF
    bytes[offset + 2] = (v >> 8) & 0xFF
    bytes[offset + 3] = v & 0xFF
  }
}

///|
fn dataview_set_uint32(
  bytes : Array[Int],
  offset : Int,
  value : Double,
  little_endian : Bool,
) -> Unit {
  let v = to_int32(value)
  if little_endian {
    bytes[offset] = v & 0xFF
    bytes[offset + 1] = (v >> 8) & 0xFF
    bytes[offset + 2] = (v >> 16) & 0xFF
    bytes[offset + 3] = (v >> 24) & 0xFF
  } else {
    bytes[offset] = (v >> 24) & 0xFF
    bytes[offset + 1] = (v >> 16) & 0xFF
    bytes[offset + 2] = (v >> 8) & 0xFF
    bytes[offset + 3] = v & 0xFF
  }
}

///|
fn dataview_set_float32(
  bytes : Array[Int],
  offset : Int,
  value : Double,
  little_endian : Bool,
) -> Unit {
  let bits = double_to_float32_bits(value)
  if little_endian {
    bytes[offset] = bits & 0xFF
    bytes[offset + 1] = (bits >> 8) & 0xFF
    bytes[offset + 2] = (bits >> 16) & 0xFF
    bytes[offset + 3] = (bits >> 24) & 0xFF
  } else {
    bytes[offset] = (bits >> 24) & 0xFF
    bytes[offset + 1] = (bits >> 16) & 0xFF
    bytes[offset + 2] = (bits >> 8) & 0xFF
    bytes[offset + 3] = bits & 0xFF
  }
}

///|
fn dataview_set_float64(
  bytes : Array[Int],
  offset : Int,
  value : Double,
  little_endian : Bool,
) -> Unit {
  let bits = value.reinterpret_as_uint64()
  if little_endian {
    for i = 0; i < 8; i = i + 1 {
      bytes[offset + i] = (bits >> (i * 8)).to_int() & 0xFF
    }
  } else {
    for i = 0; i < 8; i = i + 1 {
      bytes[offset + i] = (bits >> ((7 - i) * 8)).to_int() & 0xFF
    }
  }
}

///|
/// Helper to get the littleEndian bool argument.
fn get_little_endian(args : Array[Value], arg_index : Int) -> Bool {
  if args.length() > arg_index {
    is_truthy(args[arg_index])
  } else {
    false
  }
}

///|
/// Helper to validate DataView access.
fn validate_dataview_access(
  data : ObjectData,
  byte_offset : Int,
  element_size : Int,
) -> (Array[Int], Int) raise Error {
  if data.class_name != "DataView" {
    raise @errors.TypeError(
      message="Method called on incompatible receiver: not a DataView",
    )
  }
  let buf_id = match data.properties.get("[[ArrayBufferID]]") {
    Some(Number(n)) => n.to_int()
    _ => raise @errors.TypeError(message="DataView access on invalid object")
  }
  if is_arraybuffer_detached(buf_id) {
    raise @errors.TypeError(
      message="Cannot perform DataView operation on a detached ArrayBuffer",
    )
  }
  let dv_offset = match data.properties.get("[[ByteOffset]]") {
    Some(Number(n)) => n.to_int()
    _ => 0
  }
  let dv_byte_length = match data.properties.get("[[ByteLength]]") {
    Some(Number(n)) => n.to_int()
    _ => 0
  }
  if byte_offset < 0 || byte_offset + element_size > dv_byte_length {
    raise @errors.RangeError(
      message="Offset is outside the bounds of the DataView",
    )
  }
  let bytes = match get_arraybuffer_bytes(buf_id) {
    Some(b) => b
    None =>
      raise @errors.TypeError(
        message="Cannot perform DataView operation on a detached ArrayBuffer",
      )
  }
  (bytes, dv_offset + byte_offset)
}

///|
pub fn setup_dataview_builtins(env : Environment) -> Unit {
  let obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }
  let tostringtag_sym = get_tostringtag_symbol()

  // DataView.prototype
  let dv_proto_props : Map[String, Value] = {}
  let dv_proto_descs : Map[String, PropDescriptor] = {}

  // Getters: buffer, byteLength, byteOffset
  let dv_getter_props = [
    ("buffer", "[[ViewedArrayBuffer]]"),
    ("byteLength", "[[ByteLength]]"),
    ("byteOffset", "[[ByteOffset]]"),
  ]
  for pair in dv_getter_props {
    let (getter_name, internal_slot) = pair
    dv_proto_props[getter_name] = Undefined
    dv_proto_descs[getter_name] = {
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
                  if data.class_name == "DataView" {
                    match data.properties.get(internal_slot) {
                      Some(n) => n
                      None => Number(0.0)
                    }
                  } else {
                    raise @errors.TypeError(
                      message="get DataView.prototype.\{getter_name} called on incompatible receiver",
                    )
                  }
                _ =>
                  raise @errors.TypeError(
                    message="get DataView.prototype.\{getter_name} called on incompatible receiver",
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

  // getInt8(byteOffset)
  dv_proto_props["getInt8"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getInt8", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 1,
            )
            dataview_get_int8(bytes, actual_offset)
          }
          _ => raise @errors.TypeError(message="getInt8 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // getUint8(byteOffset)
  dv_proto_props["getUint8"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getUint8", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 1,
            )
            dataview_get_uint8(bytes, actual_offset)
          }
          _ =>
            raise @errors.TypeError(message="getUint8 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // getInt16(byteOffset [, littleEndian])
  dv_proto_props["getInt16"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getInt16", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let le = get_little_endian(args, 1)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 2,
            )
            dataview_get_int16(bytes, actual_offset, le)
          }
          _ =>
            raise @errors.TypeError(message="getInt16 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // getUint16(byteOffset [, littleEndian])
  dv_proto_props["getUint16"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getUint16", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let le = get_little_endian(args, 1)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 2,
            )
            dataview_get_uint16(bytes, actual_offset, le)
          }
          _ =>
            raise @errors.TypeError(message="getUint16 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // getInt32(byteOffset [, littleEndian])
  dv_proto_props["getInt32"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getInt32", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let le = get_little_endian(args, 1)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 4,
            )
            dataview_get_int32(bytes, actual_offset, le)
          }
          _ =>
            raise @errors.TypeError(message="getInt32 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // getUint32(byteOffset [, littleEndian])
  dv_proto_props["getUint32"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getUint32", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let le = get_little_endian(args, 1)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 4,
            )
            dataview_get_uint32(bytes, actual_offset, le)
          }
          _ =>
            raise @errors.TypeError(message="getUint32 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // getFloat32(byteOffset [, littleEndian])
  dv_proto_props["getFloat32"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getFloat32", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let le = get_little_endian(args, 1)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 4,
            )
            dataview_get_float32(bytes, actual_offset, le)
          }
          _ =>
            raise @errors.TypeError(message="getFloat32 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // getFloat64(byteOffset [, littleEndian])
  dv_proto_props["getFloat64"] = Object({
    properties: { "length": Number(1.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("getFloat64", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let le = get_little_endian(args, 1)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 8,
            )
            dataview_get_float64(bytes, actual_offset, le)
          }
          _ =>
            raise @errors.TypeError(message="getFloat64 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setInt8(byteOffset, value)
  dv_proto_props["setInt8"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setInt8", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 1,
            )
            dataview_set_int8(bytes, actual_offset, value)
            Undefined
          }
          _ => raise @errors.TypeError(message="setInt8 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setUint8(byteOffset, value)
  dv_proto_props["setUint8"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setUint8", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 1,
            )
            dataview_set_uint8(bytes, actual_offset, value)
            Undefined
          }
          _ =>
            raise @errors.TypeError(message="setUint8 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setInt16(byteOffset, value [, littleEndian])
  dv_proto_props["setInt16"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setInt16", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let le = get_little_endian(args, 2)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 2,
            )
            dataview_set_int16(bytes, actual_offset, value, le)
            Undefined
          }
          _ =>
            raise @errors.TypeError(message="setInt16 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setUint16(byteOffset, value [, littleEndian])
  dv_proto_props["setUint16"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setUint16", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let le = get_little_endian(args, 2)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 2,
            )
            dataview_set_uint16(bytes, actual_offset, value, le)
            Undefined
          }
          _ =>
            raise @errors.TypeError(message="setUint16 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setInt32(byteOffset, value [, littleEndian])
  dv_proto_props["setInt32"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setInt32", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let le = get_little_endian(args, 2)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 4,
            )
            dataview_set_int32(bytes, actual_offset, value, le)
            Undefined
          }
          _ =>
            raise @errors.TypeError(message="setInt32 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setUint32(byteOffset, value [, littleEndian])
  dv_proto_props["setUint32"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setUint32", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let le = get_little_endian(args, 2)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 4,
            )
            dataview_set_uint32(bytes, actual_offset, value, le)
            Undefined
          }
          _ =>
            raise @errors.TypeError(message="setUint32 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setFloat32(byteOffset, value [, littleEndian])
  dv_proto_props["setFloat32"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setFloat32", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let le = get_little_endian(args, 2)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 4,
            )
            dataview_set_float32(bytes, actual_offset, value, le)
            Undefined
          }
          _ =>
            raise @errors.TypeError(message="setFloat32 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // setFloat64(byteOffset, value [, littleEndian])
  dv_proto_props["setFloat64"] = Object({
    properties: { "length": Number(2.0) },
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("setFloat64", fn(this_val, args) raise {
        match this_val {
          Object(data) => {
            let offset = if args.length() > 0 { to_index(args[0]) } else { 0 }
            let value = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
            let le = get_little_endian(args, 2)
            let (bytes, actual_offset) = validate_dataview_access(
              data, offset, 8,
            )
            dataview_set_float64(bytes, actual_offset, value, le)
            Undefined
          }
          _ =>
            raise @errors.TypeError(message="setFloat64 called on non-DataView")
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Symbol.toStringTag
  let dv_proto_sym_props : Map[Int, Value] = {}
  dv_proto_sym_props[tostringtag_sym.id] = String_("DataView")
  let dv_proto_sym_descs : Map[Int, PropDescriptor] = {}
  dv_proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }

  let dv_proto : Value = Object({
    properties: dv_proto_props,
    symbol_properties: dv_proto_sym_props,
    prototype: obj_proto,
    callable: None,
    class_name: "Object",
    descriptors: dv_proto_descs,
    symbol_descriptors: dv_proto_sym_descs,
    extensible: true,
  })
  env.def_builtin("[[DataViewPrototype]]", dv_proto)

  // DataView constructor
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let dv_ctor_props : Map[String, Value] = {}
  dv_ctor_props["prototype"] = dv_proto
  dv_ctor_props["name"] = String_("DataView")
  dv_ctor_props["length"] = Number(1.0)
  let dv_ctor_descs : Map[String, PropDescriptor] = {}
  dv_ctor_descs["prototype"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  dv_ctor_descs["name"] = nf_desc
  dv_ctor_descs["length"] = nf_desc

  let dv_ctor : Value = Object({
    properties: dv_ctor_props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("DataView", fn(args) raise {
        if not(is_constructing.val) {
          raise @errors.TypeError(message="Constructor DataView requires 'new'")
        }
        if args.length() == 0 {
          raise @errors.TypeError(
            message="First argument to DataView constructor must be an ArrayBuffer",
          )
        }
        let buffer = args[0]
        let buf_id = match get_buffer_id(buffer) {
          Some(id) => id
          None =>
            raise @errors.TypeError(
              message="First argument to DataView constructor must be an ArrayBuffer",
            )
        }
        if is_arraybuffer_detached(buf_id) {
          raise @errors.TypeError(
            message="Cannot construct DataView with a detached ArrayBuffer",
          )
        }
        let buf_byte_length = match buffer {
          Object(buf_data) =>
            match buf_data.properties.get("[[ArrayBufferByteLength]]") {
              Some(Number(n)) => n.to_int()
              _ => 0
            }
          _ => 0
        }
        let byte_offset = if args.length() > 1 {
          match args[1] {
            Undefined => 0
            _ => {
              let n = to_number(args[1]).to_int()
              if n < 0 || n > buf_byte_length {
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
        let byte_length = if args.length() > 2 {
          match args[2] {
            Undefined => buf_byte_length - byte_offset
            _ => {
              let n = to_number(args[2]).to_int()
              if n < 0 || byte_offset + n > buf_byte_length {
                raise @errors.RangeError(message="Invalid DataView length \{n}")
              }
              n
            }
          }
        } else {
          buf_byte_length - byte_offset
        }
        let props : Map[String, Value] = {}
        props["[[ViewedArrayBuffer]]"] = buffer
        props["[[ArrayBufferID]]"] = Number(buf_id.to_double())
        props["[[ByteOffset]]"] = Number(byte_offset.to_double())
        props["[[ByteLength]]"] = Number(byte_length.to_double())
        let descs : Map[String, PropDescriptor] = {}
        let internal_keys = [
          "[[ViewedArrayBuffer]]", "[[ArrayBufferID]]", "[[ByteOffset]]", "[[ByteLength]]",
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
          prototype: dv_proto,
          callable: None,
          class_name: "DataView",
          descriptors: descs,
          symbol_descriptors: {},
          extensible: true,
        })
      }),
    ),
    class_name: "Function",
    descriptors: dv_ctor_descs,
    symbol_descriptors: {},
    extensible: true,
  })

  // Link constructor
  match dv_proto {
    Object(data) => {
      data.properties["constructor"] = dv_ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }

  env.def_builtin("DataView", dv_ctor)
}

///|
/// Read bytes from an ArrayBuffer for DataView operations.
/// Handles endianness (little_endian parameter).
fn dataview_get_int8(bytes : Array[Int], offset : Int) -> Value {
  let v = bytes[offset]
  let signed = if v >= 128 { v - 256 } else { v }
  Value::Number(signed.to_double())
}

///|
fn dataview_get_uint8(bytes : Array[Int], offset : Int) -> Value {
  Value::Number(bytes[offset].to_double())
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
  Value::Number(signed.to_double())
}

///|
fn dataview_get_uint16(
  bytes : Array[Int],
  offset : Int,
  little_endian : Bool,
) -> Value {
  let lo = if little_endian { bytes[offset] } else { bytes[offset + 1] }
  let hi = if little_endian { bytes[offset + 1] } else { bytes[offset] }
  Value::Number((lo + hi * 256).to_double())
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
  Value::Number(signed.to_double())
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
  Value::Number(v.to_double())
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
  Value::Number(float32_bits_to_double(bits64.to_int()))
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
  Value::Number(bits.reinterpret_as_double())
}

///|
/// Set bytes in an ArrayBuffer for DataView operations.
fn dataview_set_int8(bytes : Array[Int], offset : Int, value : Double) -> Unit {
  let v = @runtime.to_int32(value) & 0xFF
  bytes[offset] = v
}

///|
fn dataview_set_uint8(bytes : Array[Int], offset : Int, value : Double) -> Unit {
  let v = @runtime.to_int32(value) & 0xFF
  bytes[offset] = v
}

///|
fn dataview_set_int16(
  bytes : Array[Int],
  offset : Int,
  value : Double,
  little_endian : Bool,
) -> Unit {
  let v = @runtime.to_int32(value) & 0xFFFF
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
  let v = @runtime.to_int32(value) & 0xFFFF
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
  let v = @runtime.to_int32(value)
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
  let v = @runtime.to_int32(value)
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
    @runtime.is_truthy(args[arg_index])
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
  realm_state : @runtime.RealmState,
) -> (Array[Int], Int) raise Error {
  if data.class_name != "DataView" {
    raise @errors.TypeError(
      message="Method called on incompatible receiver: not a DataView",
    )
  }
  let buf_id = match data.bag.internal_slots.get(@runtime.ArrayBufferID) {
    Some(Value::Number(n)) => n.to_int()
    _ => raise @errors.TypeError(message="DataView access on invalid object")
  }
  let storage_state = arraybuffer_state_from_data(
    data,
    realm_state.arraybuffer_state,
  )
  if is_arraybuffer_state_detached(storage_state, buf_id) {
    raise @errors.TypeError(
      message="Cannot perform DataView operation on a detached ArrayBuffer",
    )
  }
  let dv_offset = match data.bag.internal_slots.get(@runtime.ByteOffset) {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  let dv_byte_length = match data.bag.internal_slots.get(@runtime.ByteLength) {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  if byte_offset < 0 || byte_offset + element_size > dv_byte_length {
    raise @errors.RangeError(
      message="Offset is outside the bounds of the DataView",
    )
  }
  let bytes = match get_arraybuffer_state_bytes(storage_state, buf_id) {
    Some(b) => b
    None =>
      raise @errors.TypeError(
        message="Cannot perform DataView operation on a detached ArrayBuffer",
      )
  }
  (bytes, dv_offset + byte_offset)
}

///|
fn make_unimplemented_dataview_bigint_method(
  name : String,
  length : Int,
) -> Value {
  @runtime.make_method_func(name~, length~, fn(_this_val, _args) raise {
    raise @errors.TypeError(
      message="DataView BigInt methods are not implemented",
    )
  })
}

///|
fn install_unimplemented_dataview_bigint_methods(
  props : Map[String, Value],
) -> Unit {
  let method_specs : Array[(String, Int)] = [
    ("getBigInt64", 1),
    ("getBigUint64", 1),
    ("setBigInt64", 2),
    ("setBigUint64", 2),
  ]
  for spec in method_specs {
    let (name, length) = spec
    props[name] = make_unimplemented_dataview_bigint_method(name, length)
  }
}

///|
pub fn setup_dataview_builtins(
  env : Environment,
  well_known_symbols : @runtime.WellKnownSymbols,
  realm_state : @runtime.RealmState,
) -> Unit {
  let obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }
  let tostringtag_sym = well_known_symbols.to_string_tag

  // DataView.prototype
  let dv_proto_props : Map[String, Value] = {}
  let dv_proto_descs : Map[String, PropDescriptor] = {}

  // Getters: buffer, byteLength, byteOffset
  let dv_getter_props = [
    ("buffer", @runtime.ViewedArrayBuffer),
    ("byteLength", @runtime.ByteLength),
    ("byteOffset", @runtime.ByteOffset),
  ]
  for pair in dv_getter_props {
    let (getter_name, internal_slot) = pair
    dv_proto_props[getter_name] = Undefined
    dv_proto_descs[getter_name] = {
      writable: false,
      enumerable: false,
      configurable: true,
      getter: Some(
        @runtime.make_method_func(name="get \{getter_name}", length=0, fn(
          this_val,
          _args,
        ) raise {
          match this_val {
            Object(data) =>
              if data.class_name == "DataView" {
                if getter_name != "buffer" {
                  let buf_id = match
                    data.bag.internal_slots.get(@runtime.ArrayBufferID) {
                    Some(Value::Number(n)) => n.to_int()
                    _ =>
                      raise @errors.TypeError(
                        message="DataView accessor on invalid object",
                      )
                  }
                  let storage_state = arraybuffer_state_from_data(
                    data,
                    realm_state.arraybuffer_state,
                  )
                  if is_arraybuffer_state_detached(storage_state, buf_id) {
                    raise @errors.TypeError(
                      message="Cannot access DataView property on a detached ArrayBuffer",
                    )
                  }
                }
                match data.bag.internal_slots.get(internal_slot) {
                  Some(n) => n
                  None => Value::Number(0.0)
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
      setter: None,
      is_accessor: true,
    }
  }

  // getInt8(byteOffset)
  dv_proto_props["getInt8"] = @runtime.make_interp_method_func(
    name="getInt8",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 1, realm_state,
          )
          dataview_get_int8(bytes, actual_offset)
        }
        _ => raise @errors.TypeError(message="getInt8 called on non-DataView")
      }
    },
  )

  // getUint8(byteOffset)
  dv_proto_props["getUint8"] = @runtime.make_interp_method_func(
    name="getUint8",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 1, realm_state,
          )
          dataview_get_uint8(bytes, actual_offset)
        }
        _ => raise @errors.TypeError(message="getUint8 called on non-DataView")
      }
    },
  )

  // getInt16(byteOffset [, littleEndian])
  dv_proto_props["getInt16"] = @runtime.make_interp_method_func(
    name="getInt16",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let le = get_little_endian(args, 1)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 2, realm_state,
          )
          dataview_get_int16(bytes, actual_offset, le)
        }
        _ => raise @errors.TypeError(message="getInt16 called on non-DataView")
      }
    },
  )

  // getUint16(byteOffset [, littleEndian])
  dv_proto_props["getUint16"] = @runtime.make_interp_method_func(
    name="getUint16",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let le = get_little_endian(args, 1)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 2, realm_state,
          )
          dataview_get_uint16(bytes, actual_offset, le)
        }
        _ => raise @errors.TypeError(message="getUint16 called on non-DataView")
      }
    },
  )

  // getInt32(byteOffset [, littleEndian])
  dv_proto_props["getInt32"] = @runtime.make_interp_method_func(
    name="getInt32",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let le = get_little_endian(args, 1)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 4, realm_state,
          )
          dataview_get_int32(bytes, actual_offset, le)
        }
        _ => raise @errors.TypeError(message="getInt32 called on non-DataView")
      }
    },
  )

  // getUint32(byteOffset [, littleEndian])
  dv_proto_props["getUint32"] = @runtime.make_interp_method_func(
    name="getUint32",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let le = get_little_endian(args, 1)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 4, realm_state,
          )
          dataview_get_uint32(bytes, actual_offset, le)
        }
        _ => raise @errors.TypeError(message="getUint32 called on non-DataView")
      }
    },
  )

  // getFloat32(byteOffset [, littleEndian])
  dv_proto_props["getFloat32"] = @runtime.make_interp_method_func(
    name="getFloat32",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let le = get_little_endian(args, 1)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 4, realm_state,
          )
          dataview_get_float32(bytes, actual_offset, le)
        }
        _ =>
          raise @errors.TypeError(message="getFloat32 called on non-DataView")
      }
    },
  )

  // getFloat64(byteOffset [, littleEndian])
  dv_proto_props["getFloat64"] = @runtime.make_interp_method_func(
    name="getFloat64",
    length=1,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let le = get_little_endian(args, 1)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 8, realm_state,
          )
          dataview_get_float64(bytes, actual_offset, le)
        }
        _ =>
          raise @errors.TypeError(message="getFloat64 called on non-DataView")
      }
    },
  )

  install_unimplemented_dataview_bigint_methods(dv_proto_props)

  // setInt8(byteOffset, value)
  dv_proto_props["setInt8"] = @runtime.make_interp_method_func(
    name="setInt8",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            0.0
          }
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 1, realm_state,
          )
          dataview_set_int8(bytes, actual_offset, value)
          Undefined
        }
        _ => raise @errors.TypeError(message="setInt8 called on non-DataView")
      }
    },
  )

  // setUint8(byteOffset, value)
  dv_proto_props["setUint8"] = @runtime.make_interp_method_func(
    name="setUint8",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            0.0
          }
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 1, realm_state,
          )
          dataview_set_uint8(bytes, actual_offset, value)
          Undefined
        }
        _ => raise @errors.TypeError(message="setUint8 called on non-DataView")
      }
    },
  )

  // setInt16(byteOffset, value [, littleEndian])
  dv_proto_props["setInt16"] = @runtime.make_interp_method_func(
    name="setInt16",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            0.0
          }
          let le = get_little_endian(args, 2)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 2, realm_state,
          )
          dataview_set_int16(bytes, actual_offset, value, le)
          Undefined
        }
        _ => raise @errors.TypeError(message="setInt16 called on non-DataView")
      }
    },
  )

  // setUint16(byteOffset, value [, littleEndian])
  dv_proto_props["setUint16"] = @runtime.make_interp_method_func(
    name="setUint16",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            0.0
          }
          let le = get_little_endian(args, 2)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 2, realm_state,
          )
          dataview_set_uint16(bytes, actual_offset, value, le)
          Undefined
        }
        _ => raise @errors.TypeError(message="setUint16 called on non-DataView")
      }
    },
  )

  // setInt32(byteOffset, value [, littleEndian])
  dv_proto_props["setInt32"] = @runtime.make_interp_method_func(
    name="setInt32",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            0.0
          }
          let le = get_little_endian(args, 2)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 4, realm_state,
          )
          dataview_set_int32(bytes, actual_offset, value, le)
          Undefined
        }
        _ => raise @errors.TypeError(message="setInt32 called on non-DataView")
      }
    },
  )

  // setUint32(byteOffset, value [, littleEndian])
  dv_proto_props["setUint32"] = @runtime.make_interp_method_func(
    name="setUint32",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            0.0
          }
          let le = get_little_endian(args, 2)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 4, realm_state,
          )
          dataview_set_uint32(bytes, actual_offset, value, le)
          Undefined
        }
        _ => raise @errors.TypeError(message="setUint32 called on non-DataView")
      }
    },
  )

  // setFloat32(byteOffset, value [, littleEndian])
  dv_proto_props["setFloat32"] = @runtime.make_interp_method_func(
    name="setFloat32",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            interp.to_number(Undefined)
          }
          let le = get_little_endian(args, 2)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 4, realm_state,
          )
          dataview_set_float32(bytes, actual_offset, value, le)
          Undefined
        }
        _ =>
          raise @errors.TypeError(message="setFloat32 called on non-DataView")
      }
    },
  )

  // setFloat64(byteOffset, value [, littleEndian])
  dv_proto_props["setFloat64"] = @runtime.make_interp_method_func(
    name="setFloat64",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          let offset = if args.length() > 0 {
            interp.to_index(args[0])
          } else {
            0
          }
          let value = if args.length() > 1 {
            interp.to_number(args[1])
          } else {
            interp.to_number(Undefined)
          }
          let le = get_little_endian(args, 2)
          let (bytes, actual_offset) = validate_dataview_access(
            data, offset, 8, realm_state,
          )
          dataview_set_float64(bytes, actual_offset, value, le)
          Undefined
        }
        _ =>
          raise @errors.TypeError(message="setFloat64 called on non-DataView")
      }
    },
  )

  // Non-enumerable descriptors for all DataView prototype methods
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  dv_proto_descs["getInt8"] = method_desc
  dv_proto_descs["getUint8"] = method_desc
  dv_proto_descs["getInt16"] = method_desc
  dv_proto_descs["getUint16"] = method_desc
  dv_proto_descs["getInt32"] = method_desc
  dv_proto_descs["getUint32"] = method_desc
  dv_proto_descs["getFloat32"] = method_desc
  dv_proto_descs["getFloat64"] = method_desc
  dv_proto_descs["getBigInt64"] = method_desc
  dv_proto_descs["getBigUint64"] = method_desc
  dv_proto_descs["setInt8"] = method_desc
  dv_proto_descs["setUint8"] = method_desc
  dv_proto_descs["setInt16"] = method_desc
  dv_proto_descs["setUint16"] = method_desc
  dv_proto_descs["setInt32"] = method_desc
  dv_proto_descs["setUint32"] = method_desc
  dv_proto_descs["setFloat32"] = method_desc
  dv_proto_descs["setFloat64"] = method_desc
  dv_proto_descs["setBigInt64"] = method_desc
  dv_proto_descs["setBigUint64"] = method_desc

  // Symbol.toStringTag
  let dv_proto_sym_props : Map[Int, Value] = {}
  dv_proto_sym_props[tostringtag_sym.id] = Value::String_("DataView")
  let dv_proto_sym_descs : Map[Int, PropDescriptor] = {}
  dv_proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  let dv_proto : Value = Value::Object({
    bag: {
      properties: dv_proto_props,
      symbol_properties: dv_proto_sym_props,
      descriptors: dv_proto_descs,
      symbol_descriptors: dv_proto_sym_descs,
      internal_slots: {},
    },
    prototype: obj_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  env.def_builtin("[[DataViewPrototype]]", dv_proto)

  // DataView constructor
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let dv_ctor_props : Map[String, Value] = {}
  dv_ctor_props["prototype"] = dv_proto
  dv_ctor_props["name"] = Value::String_("DataView")
  dv_ctor_props["length"] = Value::Number(1.0)
  let dv_ctor_descs : Map[String, PropDescriptor] = {}
  dv_ctor_descs["prototype"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  dv_ctor_descs["name"] = nf_desc
  dv_ctor_descs["length"] = nf_desc

  let dv_ctor : Value = Value::Object({
    bag: {
      properties: dv_ctor_props,
      symbol_properties: {},
      descriptors: dv_ctor_descs,
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: Null,
    callable: Some(
      InterpreterCallableWithContext("DataView", fn(
        interp,
        context,
        _this_val,
        args,
      ) raise {
        if !context.is_constructing() {
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
        let storage_state = arraybuffer_state_from_value(
          buffer,
          realm_state.arraybuffer_state,
        )
        let byte_offset = if args.length() > 1 {
          match args[1] {
            Undefined => 0
            _ => interp.to_index(args[1])
          }
        } else {
          0
        }
        if is_arraybuffer_state_detached(storage_state, buf_id) {
          raise @errors.TypeError(
            message="Cannot construct DataView with a detached ArrayBuffer",
          )
        }
        let buf_byte_length = match buffer {
          Object(buf_data) =>
            match
              buf_data.bag.internal_slots.get(@runtime.ArrayBufferByteLength) {
              Some(Value::Number(n)) => n.to_int()
              _ => 0
            }
          _ => 0
        }
        if byte_offset > buf_byte_length {
          raise @errors.RangeError(
            message="Start offset \{byte_offset} is outside the bounds of the buffer",
          )
        }
        let byte_length = if args.length() > 2 {
          match args[2] {
            Undefined => buf_byte_length - byte_offset
            _ => {
              let n = interp.to_index(args[2])
              if byte_offset + n > buf_byte_length {
                raise @errors.RangeError(message="Invalid DataView length \{n}")
              }
              n
            }
          }
        } else {
          buf_byte_length - byte_offset
        }
        let loc = @token.Loc::default()
        let proto = match context.new_target() {
          Some(new_target) => {
            let prototype = interp.get_property(new_target, "prototype", loc)
            if @runtime.is_object_value(prototype) {
              prototype
            } else {
              dv_proto
            }
          }
          None => dv_proto
        }
        if is_arraybuffer_state_detached(storage_state, buf_id) {
          raise @errors.TypeError(
            message="Cannot construct DataView with a detached ArrayBuffer",
          )
        }
        Value::Object({
          bag: {
            properties: {},
            symbol_properties: {},
            descriptors: {},
            symbol_descriptors: {},
            internal_slots: Map::from_array([
              (@runtime.ViewedArrayBuffer, buffer),
              (@runtime.ArrayBufferID, Value::Number(buf_id.to_double())),
              (@runtime.ByteOffset, Value::Number(byte_offset.to_double())),
              (@runtime.ByteLength, Value::Number(byte_length.to_double())),
            ]),
          },
          prototype: proto,
          callable: None,
          class_name: "DataView",
          extensible: true,
          arraybuffer_state: Some(storage_state),
        })
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })

  // Link constructor
  match dv_proto {
    Object(data) =>
      @runtime.install_builtin_method(data, "constructor", dv_ctor)
    _ => ()
  }

  env.def_builtin("DataView", dv_ctor)
}

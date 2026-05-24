///|
/// ArrayBuffer byte data is owned by the RealmState that allocated the buffer.
/// Each ArrayBuffer Object gets a realm-local ID stored in "[[ArrayBufferID]]".
/// The actual bytes are stored in `realm_state.arraybuffer_store`, keyed by ID.
fn alloc_arraybuffer(
  realm_state : @runtime.RealmState,
  byte_length : Int,
) -> Int {
  let id = realm_state.arraybuffer_id_counter.val
  realm_state.arraybuffer_id_counter.val = id + 1
  let bytes : Array[Int] = []
  for i = 0; i < byte_length; i = i + 1 {
    let _ = i
    bytes.push(0)
  }
  realm_state.arraybuffer_store[id] = bytes
  id
}

///|
/// Get the byte array for a given buffer ID. Returns None if detached.
pub fn get_arraybuffer_bytes(
  realm_state : @runtime.RealmState,
  id : Int,
) -> Array[Int]? {
  if realm_state.detached_buffers.contains(id) {
    return None
  }
  realm_state.arraybuffer_store.get(id)
}

///|
/// Detach an ArrayBuffer by its ID.
pub fn detach_arraybuffer(realm_state : @runtime.RealmState, id : Int) -> Unit {
  realm_state.detached_buffers[id] = true
}

///|
/// Check if an ArrayBuffer is detached.
pub fn is_arraybuffer_detached(
  realm_state : @runtime.RealmState,
  id : Int,
) -> Bool {
  realm_state.detached_buffers.contains(id)
}

///|
fn arraybuffer_realm_from_env(env : Environment) -> @runtime.RealmState {
  match env.realm_state {
    Some(state) => state
    None => {
      let state = @runtime.RealmState()
      env.realm_state = Some(state)
      state
    }
  }
}

///|
/// Get the buffer ID from an ArrayBuffer Object value.
pub fn get_buffer_id(obj : Value) -> Int? {
  match obj {
    Object(data) =>
      if data.class_name == "ArrayBuffer" {
        match data.bag.properties.get("[[ArrayBufferID]]") {
          Some(Value::Number(n)) => Some(n.to_int())
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
/// Create an ArrayBuffer object with the given byte length.
pub fn make_arraybuffer_object(
  realm_state : @runtime.RealmState,
  byte_length : Int,
  proto : Value,
) -> Value {
  let id = alloc_arraybuffer(realm_state, byte_length)
  let props : Map[String, Value] = {}
  props["[[ArrayBufferID]]"] = Value::Number(id.to_double())
  props["[[ArrayBufferByteLength]]"] = Value::Number(byte_length.to_double())
  let descs : Map[String, PropDescriptor] = {}
  descs["[[ArrayBufferID]]"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  descs["[[ArrayBufferByteLength]]"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Value::Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: descs,
      symbol_descriptors: {},
    },
    prototype: proto,
    callable: None,
    class_name: "ArrayBuffer",
    extensible: true,
  })
}

///|
pub fn setup_arraybuffer_builtins(
  env : Environment,
  well_known_symbols : @runtime.WellKnownSymbols,
  realm_state : @runtime.RealmState,
) -> Unit {
  let obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }

  // ArrayBuffer.prototype
  let ab_proto_props : Map[String, Value] = {}
  let ab_proto_descs : Map[String, PropDescriptor] = {}

  // ArrayBuffer.prototype.byteLength (getter)
  ab_proto_props["byteLength"] = Undefined
  ab_proto_descs["byteLength"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(
      @runtime.make_method_func(name="get byteLength", length=0, fn(
        this_val,
        _args,
      ) raise {
        match this_val {
          Object(data) =>
            if data.class_name == "ArrayBuffer" {
              match data.bag.properties.get("[[ArrayBufferID]]") {
                Some(Value::Number(id_n)) =>
                  if is_arraybuffer_detached(realm_state, id_n.to_int()) {
                    raise @errors.TypeError(
                      message="Cannot perform get on a detached ArrayBuffer",
                    )
                  } else {
                    match data.bag.properties.get("[[ArrayBufferByteLength]]") {
                      Some(n) => n
                      None => Value::Number(0.0)
                    }
                  }
                _ => Value::Number(0.0)
              }
            } else {
              raise @errors.TypeError(
                message="get ArrayBuffer.prototype.byteLength called on incompatible receiver",
              )
            }
          _ =>
            raise @errors.TypeError(
              message="get ArrayBuffer.prototype.byteLength called on incompatible receiver",
            )
        }
      }),
    ),
    setter: None,
    is_accessor: true,
  }

  // ArrayBuffer.prototype.slice(begin, end)
  ab_proto_props["slice"] = @runtime.make_method_func(name="slice", length=2, fn(
    this_val,
    args,
  ) raise {
    match this_val {
      Object(data) =>
        if data.class_name == "ArrayBuffer" {
          let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
            Some(Value::Number(n)) => n.to_int()
            _ =>
              raise @errors.TypeError(
                message="ArrayBuffer.prototype.slice called on non-ArrayBuffer",
              )
          }
          if is_arraybuffer_detached(realm_state, buf_id) {
            raise @errors.TypeError(
              message="Cannot perform slice on a detached ArrayBuffer",
            )
          }
          let bytes = match get_arraybuffer_bytes(realm_state, buf_id) {
            Some(b) => b
            None =>
              raise @errors.TypeError(
                message="Cannot perform slice on a detached ArrayBuffer",
              )
          }
          let len = bytes.length()
          let relative_start = if args.length() > 0 {
            @runtime.to_number(args[0]).to_int()
          } else {
            0
          }
          let start = if relative_start < 0 {
            let s = len + relative_start
            if s < 0 {
              0
            } else {
              s
            }
          } else if relative_start > len {
            len
          } else {
            relative_start
          }
          let relative_end = if args.length() > 1 {
            match args[1] {
              Undefined => len
              _ => @runtime.to_number(args[1]).to_int()
            }
          } else {
            len
          }
          let end = if relative_end < 0 {
            let e = len + relative_end
            if e < 0 {
              0
            } else {
              e
            }
          } else if relative_end > len {
            len
          } else {
            relative_end
          }
          let new_len = if end > start { end - start } else { 0 }
          let ab_proto2 = env.get("[[ArrayBufferPrototype]]")
          let new_buf = make_arraybuffer_object(realm_state, new_len, ab_proto2)
          let new_id = match get_buffer_id(new_buf) {
            Some(id) => id
            None => -1
          }
          match get_arraybuffer_bytes(realm_state, new_id) {
            Some(new_bytes) =>
              for i = 0; i < new_len; i = i + 1 {
                new_bytes[i] = bytes[start + i]
              }
            None => ()
          }
          new_buf
        } else {
          raise @errors.TypeError(
            message="ArrayBuffer.prototype.slice called on non-ArrayBuffer",
          )
        }
      _ =>
        raise @errors.TypeError(
          message="ArrayBuffer.prototype.slice called on non-ArrayBuffer",
        )
    }
  })

  ab_proto_descs["slice"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  ab_proto_descs["constructor"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  // Add Symbol.toStringTag
  let tostringtag_sym = well_known_symbols.to_string_tag
  let ab_proto_sym_props : Map[Int, Value] = {}
  ab_proto_sym_props[tostringtag_sym.id] = Value::String_("ArrayBuffer")
  let ab_proto_sym_descs : Map[Int, PropDescriptor] = {}
  ab_proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  let ab_proto : Value = Value::Object({
    bag: {
      properties: ab_proto_props,
      symbol_properties: ab_proto_sym_props,
      descriptors: ab_proto_descs,
      symbol_descriptors: ab_proto_sym_descs,
    },
    prototype: obj_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
  })
  env.def_builtin("[[ArrayBufferPrototype]]", ab_proto)

  // ArrayBuffer constructor
  let ab_ctor_props : Map[String, Value] = {}
  ab_ctor_props["prototype"] = ab_proto
  ab_ctor_props["name"] = Value::String_("ArrayBuffer")
  ab_ctor_props["length"] = Value::Number(1.0)

  // ArrayBuffer.isView(arg)
  ab_ctor_props["isView"] = @runtime.make_native_func(name="isView", length=1, fn(
    args,
  ) {
    if args.length() == 0 {
      return Value::Bool(false)
    }
    match args[0] {
      Object(data) =>
        Bool(
          data.class_name == "DataView" || is_typedarray_class(data.class_name),
        )
      _ => Value::Bool(false)
    }
  })

  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let ab_ctor_descs : Map[String, PropDescriptor] = {}
  ab_ctor_descs["prototype"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  ab_ctor_descs["name"] = nf_desc
  ab_ctor_descs["length"] = nf_desc
  ab_ctor_descs["isView"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  let ab_ctor : Value = Value::Object({
    bag: {
      properties: ab_ctor_props,
      symbol_properties: {},
      descriptors: ab_ctor_descs,
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NativeCallable("ArrayBuffer", fn(args) raise {
        if !@runtime.is_constructing.val {
          raise @errors.TypeError(
            message="Constructor ArrayBuffer requires 'new'",
          )
        }
        let byte_length = if args.length() > 0 {
          let n = @runtime.to_number(args[0]).to_int()
          if n < 0 {
            raise @errors.RangeError(message="Invalid array buffer length")
          }
          n
        } else {
          0
        }
        make_arraybuffer_object(realm_state, byte_length, ab_proto)
      }),
    ),
    class_name: "Function",
    extensible: true,
  })

  // Link constructor
  match ab_proto {
    Object(data) => {
      data.bag.properties["constructor"] = ab_ctor
      data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }

  env.def_builtin("ArrayBuffer", ab_ctor)
}

///|
/// Check if a class_name represents a TypedArray type.
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
/// Validate that a TypedArray's underlying buffer is not detached.
/// Throws TypeError if detached. Per spec, iteration methods must check this.
pub fn validate_typedarray_buffer(
  data : ObjectData,
  realm_state : @runtime.RealmState,
) -> Unit raise Error {
  let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => -1
  }
  if buf_id >= 0 && is_arraybuffer_detached(realm_state, buf_id) {
    raise @errors.TypeError(
      message="Cannot perform operation on a detached ArrayBuffer",
    )
  }
}

///|
/// Get the bytes-per-element for a TypedArray type name.
pub fn typed_array_bytes_per_element(name : String) -> Int {
  match name {
    "Int8Array" | "Uint8Array" | "Uint8ClampedArray" => 1
    "Int16Array" | "Uint16Array" => 2
    "Int32Array" | "Uint32Array" | "Float32Array" => 4
    "Float64Array" => 8
    _ => 1
  }
}

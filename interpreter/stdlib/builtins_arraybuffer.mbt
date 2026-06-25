///|
/// Maximum in-memory backing store this interpreter will allocate. Larger Data
/// Blocks are impossible for this implementation and must throw RangeError
/// instead of leaking host allocation failures.
const MAX_ARRAYBUFFER_BYTE_LENGTH = 16777216

///|
/// ArrayBuffer byte data is owned by the RealmState that allocated the buffer.
/// Each ArrayBuffer Object gets a realm-local ID stored in "[[ArrayBufferID]]".
/// The actual bytes are stored in `realm_state.arraybuffer_store`, keyed by ID.
fn alloc_arraybuffer(
  arraybuffer_state : @runtime.ArrayBufferState,
  byte_length : Int,
) -> Int raise Error {
  if byte_length < 0 || byte_length > MAX_ARRAYBUFFER_BYTE_LENGTH {
    raise @errors.RangeError(message="ArrayBuffer allocation size is too large")
  }
  let id = arraybuffer_state.id_counter.val
  arraybuffer_state.id_counter.val = id + 1
  let bytes : Array[Int] = []
  for i = 0; i < byte_length; i = i + 1 {
    let _ = i
    bytes.push(0)
  }
  arraybuffer_state.store[id] = bytes
  id
}

///|
/// Get the byte array for a given buffer ID. Returns None if detached.
fn get_arraybuffer_state_bytes(
  arraybuffer_state : @runtime.ArrayBufferState,
  id : Int,
) -> Array[Int]? {
  if arraybuffer_state.detached.contains(id) {
    return None
  }
  arraybuffer_state.store.get(id)
}

///|
/// Get the byte array for a given buffer ID. Returns None if detached.
pub fn get_arraybuffer_bytes(
  realm_state : @runtime.RealmState,
  id : Int,
) -> Array[Int]? {
  get_arraybuffer_state_bytes(realm_state.arraybuffer_state, id)
}

///|
fn detach_arraybuffer_state(
  arraybuffer_state : @runtime.ArrayBufferState,
  id : Int,
) -> Unit {
  arraybuffer_state.detached[id] = true
}

///|
/// Detach an ArrayBuffer by its ID.
pub fn detach_arraybuffer(realm_state : @runtime.RealmState, id : Int) -> Unit {
  detach_arraybuffer_state(realm_state.arraybuffer_state, id)
}

///|
fn is_arraybuffer_state_detached(
  arraybuffer_state : @runtime.ArrayBufferState,
  id : Int,
) -> Bool {
  arraybuffer_state.detached.contains(id)
}

///|
/// Check if an ArrayBuffer is detached.
pub fn is_arraybuffer_detached(
  realm_state : @runtime.RealmState,
  id : Int,
) -> Bool {
  is_arraybuffer_state_detached(realm_state.arraybuffer_state, id)
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
fn arraybuffer_state_from_data(
  data : ObjectData,
  fallback : @runtime.ArrayBufferState,
) -> @runtime.ArrayBufferState {
  match data.arraybuffer_state {
    Some(state) => state
    None => fallback
  }
}

///|
fn arraybuffer_state_from_value(
  value : Value,
  fallback : @runtime.ArrayBufferState,
) -> @runtime.ArrayBufferState {
  match value {
    Object(data) => arraybuffer_state_from_data(data, fallback)
    _ => fallback
  }
}

///|
fn detach_arraybuffer_value(
  value : Value,
  fallback_realm_state : @runtime.RealmState,
) -> Bool {
  match get_buffer_id(value) {
    Some(id) => {
      let storage_state = arraybuffer_state_from_value(
        value,
        fallback_realm_state.arraybuffer_state,
      )
      detach_arraybuffer_state(storage_state, id)
      true
    }
    None => false
  }
}

///|
/// Get the buffer ID from an ArrayBuffer Object value.
pub fn get_buffer_id(obj : Value) -> Int? {
  match obj {
    Object(data) =>
      if data.class_name == "ArrayBuffer" {
        match data.bag.internal_slots.get(@runtime.ArrayBufferID) {
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
) -> Value raise Error {
  let id = alloc_arraybuffer(realm_state.arraybuffer_state, byte_length)
  Value::Object({
    bag: {
      properties: {},
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {
        let m : Map[@runtime.InternalSlotKey, Value] = {}
        m[@runtime.ArrayBufferID] = Value::Number(id.to_double())
        m[@runtime.ArrayBufferByteLength] = Value::Number(
          byte_length.to_double(),
        )
        m
      },
    },
    prototype: proto,
    callable: None,
    class_name: "ArrayBuffer",
    extensible: true,
    arraybuffer_state: Some(realm_state.arraybuffer_state),
  })
}

///|
/// §24.1.4.1 SpeciesConstructor(O, defaultConstructor) for ArrayBuffer.
fn arraybuffer_species_constructor(
  interp : @runtime.Interpreter,
  this_val : Value,
  default_constructor : Value,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let c = interp.get_property(this_val, "constructor", loc)
  if c is Undefined {
    return default_constructor
  }
  // Per ES262 §7.2.3, constructor must be an Object when present.
  if !@runtime.is_object_value(c) {
    raise @errors.TypeError(message="ArrayBuffer constructor is not an object")
  }
  let species_sym = interp.realm_state.well_known_symbols.species
  let s = interp.get_computed_property(c, Symbol(species_sym), loc)
  match s {
    Undefined | Null => default_constructor
    _ =>
      if @runtime.is_constructor_value(s) {
        s
      } else {
        raise @errors.TypeError(
          message="ArrayBuffer species is not a constructor",
        )
      }
  }
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
              let storage_state = arraybuffer_state_from_data(
                data,
                realm_state.arraybuffer_state,
              )
              match data.bag.internal_slots.get(@runtime.ArrayBufferID) {
                Some(Value::Number(id_n)) =>
                  if is_arraybuffer_state_detached(storage_state, id_n.to_int()) {
                    Value::Number(0.0)
                  } else {
                    match
                      data.bag.internal_slots.get(
                        @runtime.ArrayBufferByteLength,
                      ) {
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
  ab_proto_props["slice"] = @runtime.make_interp_method_func(
    name="slice",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) =>
          if data.class_name == "ArrayBuffer" {
            let storage_state = arraybuffer_state_from_data(
              data,
              realm_state.arraybuffer_state,
            )
            let buf_id = match
              data.bag.internal_slots.get(@runtime.ArrayBufferID) {
              Some(Value::Number(n)) => n.to_int()
              _ =>
                raise @errors.TypeError(
                  message="ArrayBuffer.prototype.slice called on non-ArrayBuffer",
                )
            }
            if is_arraybuffer_state_detached(storage_state, buf_id) {
              raise @errors.TypeError(
                message="Cannot perform slice on a detached ArrayBuffer",
              )
            }
            let source_bytes = match
              get_arraybuffer_state_bytes(storage_state, buf_id) {
              Some(b) => b
              None =>
                raise @errors.TypeError(
                  message="Cannot perform slice on a detached ArrayBuffer",
                )
            }
            let len = source_bytes.length()
            let relative_start = if args.length() > 0 {
              interp.to_number(args[0]).to_int()
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
                _ => interp.to_number(args[1]).to_int()
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
            let default_ctor = env.get("ArrayBuffer")
            let ctor = arraybuffer_species_constructor(
              interp, this_val, default_ctor,
            )
            let new_buf = interp.construct_value(
              ctor,
              [Number(new_len.to_double())],
              @token.Loc::default(),
            )
            let new_data = match new_buf {
              Object(data) =>
                if data.class_name == "ArrayBuffer" {
                  data
                } else {
                  raise @errors.TypeError(
                    message="ArrayBuffer species constructor produced non-ArrayBuffer",
                  )
                }
              _ =>
                raise @errors.TypeError(
                  message="ArrayBuffer species constructor produced non-ArrayBuffer",
                )
            }
            if same_value(new_buf, this_val) {
              raise @errors.TypeError(
                message="ArrayBuffer species constructor returned source buffer",
              )
            }
            let new_id = match get_buffer_id(new_buf) {
              Some(id) => id
              None =>
                raise @errors.TypeError(
                  message="ArrayBuffer species constructor produced non-ArrayBuffer",
                )
            }
            let new_storage_state = arraybuffer_state_from_data(
              new_data,
              realm_state.arraybuffer_state,
            )
            let new_bytes = match
              get_arraybuffer_state_bytes(new_storage_state, new_id) {
              Some(b) => b
              None =>
                raise @errors.TypeError(
                  message="ArrayBuffer species constructor produced detached ArrayBuffer",
                )
            }
            if new_bytes.length() < new_len {
              raise @errors.TypeError(
                message="ArrayBuffer species constructor produced too-small ArrayBuffer",
              )
            }
            if is_arraybuffer_state_detached(storage_state, buf_id) {
              raise @errors.TypeError(
                message="Cannot perform slice on a detached ArrayBuffer",
              )
            }
            let source_bytes = match
              get_arraybuffer_state_bytes(storage_state, buf_id) {
              Some(b) => b
              None =>
                raise @errors.TypeError(
                  message="Cannot perform slice on a detached ArrayBuffer",
                )
            }
            for i = 0; i < new_len; i = i + 1 {
              new_bytes[i] = source_bytes[start + i]
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
    },
  )

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
      internal_slots: {},
    },
    prototype: obj_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
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
      internal_slots: {},
    },
    prototype: Null,
    callable: Some(
      InterpreterCallableWithContext("ArrayBuffer", fn(
        interp,
        context,
        _this_val,
        args,
      ) raise {
        if !context.is_constructing() {
          raise @errors.TypeError(
            message="Constructor ArrayBuffer requires 'new'",
          )
        }
        let byte_length = if args.length() > 0 {
          interp.to_index(args[0])
        } else {
          0
        }
        let loc = @token.Loc::default()
        let proto = match context.new_target() {
          Some(new_target) => {
            let prototype = interp.get_property(new_target, "prototype", loc)
            if @runtime.is_object_value(prototype) {
              prototype
            } else {
              ab_proto
            }
          }
          None => ab_proto
        }
        make_arraybuffer_object(realm_state, byte_length, proto)
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })

  // Link constructor
  match ab_proto {
    Object(data) =>
      @runtime.install_builtin_method(data, "constructor", ab_ctor)
    _ => ()
  }

  // ArrayBuffer[@@species] getter returns `this` so subclassed constructors
  // can participate in species-based operations (e.g. slice).
  let species_getter = @runtime.make_method_func(
    name="get [Symbol.species]",
    length=0,
    fn(this_val, _args) { this_val },
  )
  let species_symbol_val = well_known_symbols.species
  match ab_ctor {
    Object(ab_ctor_data) =>
      @runtime.install_builtin_symbol_accessor(
        ab_ctor_data,
        species_symbol_val.id,
        species_getter,
      )
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
    | "Float64Array"
    | "BigInt64Array"
    | "BigUint64Array" => true
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
  let buf_id = match data.bag.internal_slots.get(@runtime.ArrayBufferID) {
    Some(Value::Number(n)) => n.to_int()
    _ => -1
  }
  let storage_state = arraybuffer_state_from_data(
    data,
    realm_state.arraybuffer_state,
  )
  if buf_id >= 0 && is_arraybuffer_state_detached(storage_state, buf_id) {
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
    "Float64Array" | "BigInt64Array" | "BigUint64Array" => 8
    _ => 1
  }
}

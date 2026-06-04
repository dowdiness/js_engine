///|
fn typedarray_collect_iterator_values(
  interp : Interpreter,
  source : Value,
  iterator_method : Value,
  loc : @token.Loc,
) -> Array[Value] raise Error {
  let values : Array[Value] = []
  let iterator = interp.call_value(iterator_method, source, [], loc)
  let next_method = interp.get_iterator_next_method(iterator, loc)
  while true {
    match interp.iterator_step_value(iterator, next_method, loc) {
      None => break
      Some(value) => values.push(value)
    }
  }
  values
}

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
      Value::Number(signed.to_double())
    }
    "Uint8Array" | "Uint8ClampedArray" =>
      Value::Number(bytes[byte_offset].to_double())
    "Int16Array" => {
      let lo = bytes[byte_offset]
      let hi = bytes[byte_offset + 1]
      let v = lo + hi * 256
      let signed = if v >= 32768 { v - 65536 } else { v }
      Value::Number(signed.to_double())
    }
    "Uint16Array" => {
      let lo = bytes[byte_offset]
      let hi = bytes[byte_offset + 1]
      Value::Number((lo + hi * 256).to_double())
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
      Value::Number(signed.to_double())
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
      Value::Number(v.to_double())
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
      Value::Number(float32_bits_to_double(bits64.to_int()))
    }
    "Float64Array" => {
      let mut bits = 0L
      for i = 0; i < 8; i = i + 1 {
        bits = bits + (bytes[byte_offset + i].to_int64() << (i * 8))
      }
      Value::Number(bits.reinterpret_as_double())
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
      let v = @runtime.to_int32(value)
      let byte_val = v & 0xFF
      bytes[byte_offset] = byte_val
    }
    "Uint8Array" => {
      let v = @runtime.to_int32(value)
      let byte_val = v & 0xFF
      bytes[byte_offset] = byte_val
    }
    "Uint8ClampedArray" => {
      // ToUint8Clamp: clamp to 0..255 with round-half-to-even (banker's rounding)
      let v = if value.is_nan() || value <= 0.0 {
        0
      } else if value >= 255.0 {
        255
      } else {
        let floored = value.floor()
        let frac = value - floored
        let n = floored.to_int()
        if frac > 0.5 {
          n + 1
        } else if frac < 0.5 {
          n
          // Exactly 0.5: round to nearest even
        } else if n % 2 == 0 {
          n
        } else {
          n + 1
        }
      }
      bytes[byte_offset] = v
    }
    "Int16Array" => {
      let v = @runtime.to_int32(value) & 0xFFFF
      bytes[byte_offset] = v & 0xFF
      bytes[byte_offset + 1] = (v >> 8) & 0xFF
    }
    "Uint16Array" => {
      let v = @runtime.to_int32(value) & 0xFFFF
      bytes[byte_offset] = v & 0xFF
      bytes[byte_offset + 1] = (v >> 8) & 0xFF
    }
    "Int32Array" | "Uint32Array" => {
      let v = @runtime.to_int32(value)
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
    let mantissa_raw = (frac * 8388608.0 + 0.5).to_int()
    if mantissa_raw == 0x800000 {
      // Mantissa rounds up to smallest normal: denormal -> normal with biased_exp=1
      return (sign_bit << 31) | (1 << 23)
    }
    let mantissa = mantissa_raw & 0x7FFFFF
    return (sign_bit << 31) | mantissa
  }
  // Normalized: frac is in [1.0, 2.0)
  let mantissa_raw = ((frac - 1.0) * 8388608.0 + 0.5).to_int()
  let mut biased_exp = exp + 127
  let mantissa = if mantissa_raw == 0x800000 {
    // Mantissa rounds up: carry into exponent, mantissa becomes 0
    biased_exp = biased_exp + 1
    if biased_exp >= 0xFF {
      // Exponent saturates to infinity
      return (sign_bit << 31) | 0x7F800000
    }
    0
  } else {
    mantissa_raw & 0x7FFFFF
  }
  (sign_bit << 31) | ((biased_exp & 0xFF) << 23) | mantissa
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
) -> Value raise Error {
  let bpe = typed_array_bytes_per_element(type_name)
  let byte_length = length * bpe
  let ab_proto = env.get("[[ArrayBufferPrototype]]") catch { _ => Null }
  let realm_state = arraybuffer_realm_from_env(env)
  let buffer = make_arraybuffer_object(realm_state, byte_length, ab_proto)
  let storage_state = realm_state.arraybuffer_state
  let buf_id = match get_buffer_id(buffer) {
    Some(id) => id
    None => -1
  }
  let props : Map[String, Value] = {}
  props["[[TypedArrayName]]"] = Value::String_(type_name)
  props["[[ViewedArrayBuffer]]"] = buffer
  props["[[ArrayBufferID]]"] = Value::Number(buf_id.to_double())
  props["[[ByteOffset]]"] = Value::Number(0.0)
  props["[[ByteLength]]"] = Value::Number(byte_length.to_double())
  props["[[ArrayLength]]"] = Value::Number(length.to_double())
  let descs : Map[String, PropDescriptor] = {}
  let internal_keys = [
    "[[TypedArrayName]]", "[[ViewedArrayBuffer]]", "[[ArrayBufferID]]", "[[ByteOffset]]",
    "[[ByteLength]]", "[[ArrayLength]]",
  ]
  for k in internal_keys {
    descs[k] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    }
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
    class_name: type_name,
    extensible: true,
    arraybuffer_state: Some(storage_state),
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
  let storage_state = arraybuffer_state_from_value(
    buffer,
    @runtime.ArrayBufferState(),
  )
  let bpe = typed_array_bytes_per_element(type_name)
  let byte_length = length * bpe
  let props : Map[String, Value] = {}
  props["[[TypedArrayName]]"] = Value::String_(type_name)
  props["[[ViewedArrayBuffer]]"] = buffer
  props["[[ArrayBufferID]]"] = Value::Number(buf_id.to_double())
  props["[[ByteOffset]]"] = Value::Number(byte_offset.to_double())
  props["[[ByteLength]]"] = Value::Number(byte_length.to_double())
  props["[[ArrayLength]]"] = Value::Number(length.to_double())
  let descs : Map[String, PropDescriptor] = {}
  let internal_keys = [
    "[[TypedArrayName]]", "[[ViewedArrayBuffer]]", "[[ArrayBufferID]]", "[[ByteOffset]]",
    "[[ByteLength]]", "[[ArrayLength]]",
  ]
  for k in internal_keys {
    descs[k] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    }
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
    class_name: type_name,
    extensible: true,
    arraybuffer_state: Some(storage_state),
  })
}

///|
fn typedarray_to_array_like_length(
  val : Value,
  interp : Interpreter,
) -> Int raise {
  let length_val = interp.get_property(val, "length", @token.Loc::default())
  let length_num = @runtime.to_number(length_val, interp=Some(interp))
  if length_num.is_nan() || length_num < 0.0 {
    return 0
  }
  if length_num > 2147483647.0 {
    raise @errors.RangeError(message="Invalid typed array length")
  }
  if length_num.to_int() > 0x7FFFFFFF {
    raise @errors.RangeError(message="Invalid typed array length")
  }
  let length = length_num.to_int()
  if length < 0 {
    raise @errors.RangeError(message="Invalid typed array length")
  }
  length
}

///|
fn typedarray_arraybuffer_state(
  data : ObjectData,
  fallback_realm_state : @runtime.RealmState,
) -> @runtime.ArrayBufferState {
  match data.arraybuffer_state {
    Some(state) => state
    None =>
      match data.bag.properties.get("[[ViewedArrayBuffer]]") {
        Some(buffer) =>
          arraybuffer_state_from_value(
            buffer,
            fallback_realm_state.arraybuffer_state,
          )
        None => fallback_realm_state.arraybuffer_state
      }
  }
}

///|
/// §10.4.5.18 IsValidIntegerIndex(O, index): true iff the buffer is not
/// detached and 0 ≤ index < O.[[ArrayLength]]. Caller is responsible for
/// the integrality / -0 checks (§10.4.5.18 steps 2-3) before calling this;
/// the classifier in `classify_typedarray_string_key` filters those out by
/// returning Some(-1) for canonical-invalid forms.
pub fn typedarray_is_valid_index(
  data : ObjectData,
  index : Int,
  realm_state : @runtime.RealmState,
) -> Bool {
  let length = match data.bag.properties.get("[[ArrayLength]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  if index < 0 || index >= length {
    return false
  }
  let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => return false
  }
  let storage_state = typedarray_arraybuffer_state(data, realm_state)
  !is_arraybuffer_state_detached(storage_state, buf_id)
}

///|
/// §22.2.3.5.1 ValidateTypedArray(O): the entry guard required at the top of
/// every %TypedArray%.prototype method's algorithm. Two failure modes:
///
/// 1. `this` is not a TypedArray (RequireInternalSlot fails) → TypeError
///    "<method> called on non-TypedArray".
/// 2. The underlying ArrayBuffer is detached (IsDetachedBuffer is true) →
///    TypeError "Cannot perform <method> on a detached ArrayBuffer".
///
/// Returns `(data, buf_id)` so the caller doesn't re-read them. `buf_id` is
/// guaranteed `>= 0` and non-detached when this returns normally.
///
/// All ~30 prototype methods (reverse, copyWithin, fill, slice, subarray,
/// set, map, filter, find*, indexOf, includes, join, sort, toSorted, ...)
/// must call this at entry. Mid-method re-validation (for tests like
/// `coerced-values-end-detached.js` where argument coercion detaches the
/// buffer) is a separate follow-up — this helper covers entry-validation
/// only.
pub fn validate_typed_array(
  this_val : Value,
  method_name : String,
  realm_state : @runtime.RealmState,
) -> (ObjectData, Int) raise Error {
  let data = match this_val {
    Object(d) =>
      if is_typedarray_class(d.class_name) {
        d
      } else {
        raise @errors.TypeError(
          message="\{method_name} called on non-TypedArray",
        )
      }
    _ =>
      raise @errors.TypeError(message="\{method_name} called on non-TypedArray")
  }
  let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
    Some(Value::Number(n)) => n.to_int()
    _ =>
      raise @errors.TypeError(message="\{method_name} called on non-TypedArray")
  }
  let storage_state = typedarray_arraybuffer_state(data, realm_state)
  if is_arraybuffer_state_detached(storage_state, buf_id) {
    raise @errors.TypeError(
      message="Cannot perform \{method_name} on a detached ArrayBuffer",
    )
  }
  (data, buf_id)
}

///|
/// §7.3.20 SpeciesConstructor(O, defaultConstructor) specialised for the
/// %TypedArray% family. Mirrors the spec-correct shape used by Promise's
/// `get_promise_species_constructor` (see `builtins_promise.mbt`).
///
/// Steps (per spec):
/// 1. Let C be Get(O, "constructor").
/// 2. If C is undefined, return defaultConstructor.
/// 3. If Type(C) is not Object, throw TypeError.
/// 4. Let S be Get(C, @@species).
/// 5. If S is null or undefined, return defaultConstructor.
/// 6. If IsConstructor(S) is true, return S. Else throw TypeError.
///
/// `default_ctor` should be the concrete TA constructor that matches the
/// receiver's [[TypedArrayName]] (Int8Array for Int8Array, etc.). Callers
/// resolve it via the intrinsic slot `[[<class_name>Constructor]]`, not the
/// mutable global, so user reassignments don't shift the species default.
fn typed_array_species_constructor(
  interp : @runtime.Interpreter,
  this_val : Value,
  default_ctor : Value,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let c = interp.get_property(this_val, "constructor", loc)
  // §7.3.20 step 3: "If C is undefined, return defaultConstructor."
  if c is Undefined {
    return default_ctor
  }
  // §7.3.20 step 4: "If Type(C) is not Object, throw a TypeError exception."
  // IMPORTANT: this runtime has six object-typed Value variants (Object,
  // Array, Map, Set, Promise, Proxy — see
  // `feedback_value_model_six_variants.md`). Gating on `Object(_)` alone
  // would spuriously reject `sample.constructor = []` or
  // `sample.constructor = new Proxy(..., {})`, which are valid per spec.
  if !@runtime.is_object_value(c) {
    raise @errors.TypeError(message="TypedArray constructor is not an object")
  }
  let species_sym = interp.realm_state.well_known_symbols.species
  let s = interp.get_computed_property(c, Symbol(species_sym), loc)
  // §7.3.20 step 6: "If S is either undefined or null, return defaultConstructor."
  match s {
    Undefined | Null => default_ctor
    _ =>
      // §7.3.20 step 7: "If IsConstructor(S) is true, return S. Else throw."
      // `is_constructor_value` handles all six object variants uniformly.
      if @runtime.is_constructor_value(s) {
        s
      } else {
        raise @errors.TypeError(
          message="TypedArray species is not a constructor",
        )
      }
  }
}

///|
/// §22.2.4.7 TypedArraySpeciesCreate(exemplar, argumentList).
/// Constructs a new TypedArray using the species constructor resolved from
/// `exemplar`. Validates the result is itself a non-detached TypedArray, and
/// (if argumentList is a single-element length argument) that the resulting
/// length is at least that value.
///
/// Out of scope for this engine: ContentType check (spec step 7) — BigInt64Array
/// and BigUint64Array currently exist for constructor/empty-instance shape only;
/// BigInt element value semantics remain unsupported/skipped.
pub fn typed_array_species_create(
  interp : @runtime.Interpreter,
  exemplar : Value,
  args : Array[Value],
) -> Value raise Error {
  // ES2024 §22.2.4.7 derives the default constructor purely from the
  // exemplar's [[TypedArrayName]] — it does NOT call ValidateTypedArray on
  // the exemplar. Source-detach checks belong at the call site's
  // spec-mandated point (e.g. slice's `if count > 0` guard). Re-validating
  // here would throw too early when argument coercion detached the buffer
  // between method entry and species_create — pre-empting the `Get(O,
  // "constructor")` / @@species path the spec requires.
  let class_name = match exemplar {
    Object(data) => data.class_name
    _ =>
      raise @errors.InternalError(
        message="typed_array_species_create called with non-Object exemplar — entry ValidateTypedArray should have rejected",
      )
  }
  // §22.2.4.7 step 2: defaultConstructor is the *intrinsic* TA constructor
  // for the exemplar's [[TypedArrayName]], not the mutable global binding.
  // Reading `interp.global.get("Int8Array")` would let user code reassign
  // `Int8Array = Uint8Array` (or any non-constructable value) and silently
  // poison the default species path. The intrinsic slot is registered under
  // a name JS source cannot rebind.
  let default_ctor = interp.global.get("[[\{class_name}Constructor]]") catch {
    _ => Undefined
  }
  let ctor = typed_array_species_constructor(interp, exemplar, default_ctor)
  let loc = @token.Loc::default()
  let result = interp.construct_value(ctor, args, loc)
  // Result must itself be a TypedArray with non-detached buffer.
  let (result_data, _) = validate_typed_array(
    result,
    "species create result",
    interp.realm_state,
  )
  // §22.2.4.7 step 8: if argumentList is « length », the result's length must
  // be at least that length. This catches a malicious species constructor
  // that ignores its argument or returns a shorter TA.
  if args.length() == 1 {
    match args[0] {
      Value::Number(n) => {
        let requested = n.to_int()
        let actual = match result_data.bag.properties.get("[[ArrayLength]]") {
          Some(Value::Number(m)) => m.to_int()
          _ => 0
        }
        if actual < requested {
          raise @errors.TypeError(
            message="TypedArray species result is too short",
          )
        }
      }
      _ => ()
    }
  }
  result
}

///|
/// Get a typed element from a TypedArray object at the given index.
pub fn typedarray_get_index(
  data : ObjectData,
  index : Int,
  realm_state : @runtime.RealmState,
) -> Value {
  let length = match data.bag.properties.get("[[ArrayLength]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  if index < 0 || index >= length {
    return Undefined
  }
  let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => return Undefined
  }
  let storage_state = typedarray_arraybuffer_state(data, realm_state)
  if is_arraybuffer_state_detached(storage_state, buf_id) {
    return Undefined
  }
  let byte_offset = match data.bag.properties.get("[[ByteOffset]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  let bpe = typed_array_bytes_per_element(data.class_name)
  let elem_offset = byte_offset + index * bpe
  match get_arraybuffer_state_bytes(storage_state, buf_id) {
    Some(bytes) => typed_array_get_element(bytes, elem_offset, data.class_name)
    None => Undefined
  }
}

///|
fn typedarray_index_search_matches(search : Value, elem : Value) -> Bool {
  @runtime.strict_equal(search, elem)
}

///|
fn typedarray_includes_search_matches(search : Value, elem : Value) -> Bool {
  same_value_zero(search, elem)
}

///|
/// Set a typed element on a TypedArray object at the given index.
pub fn typedarray_set_index(
  data : ObjectData,
  index : Int,
  value : Double,
  realm_state : @runtime.RealmState,
) -> Unit {
  let length = match data.bag.properties.get("[[ArrayLength]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  if index < 0 || index >= length {
    return
  }
  let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => return
  }
  let storage_state = typedarray_arraybuffer_state(data, realm_state)
  if is_arraybuffer_state_detached(storage_state, buf_id) {
    return
  }
  let byte_offset = match data.bag.properties.get("[[ByteOffset]]") {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  let bpe = typed_array_bytes_per_element(data.class_name)
  let elem_offset = byte_offset + index * bpe
  match get_arraybuffer_state_bytes(storage_state, buf_id) {
    Some(bytes) =>
      typed_array_set_element(bytes, elem_offset, data.class_name, value)
    None => ()
  }
}

///|
fn typedarray_is_detached(
  data : ObjectData,
  realm_state : @runtime.RealmState,
) -> Bool {
  match data.bag.properties.get("[[ArrayBufferID]]") {
    Some(Value::Number(n)) => {
      let storage_state = typedarray_arraybuffer_state(data, realm_state)
      is_arraybuffer_state_detached(storage_state, n.to_int())
    }
    _ => false
  }
}

///|
fn typedarray_get_view_slot(
  data : ObjectData,
  internal_slot : String,
  realm_state : @runtime.RealmState,
) -> Value {
  if typedarray_is_detached(data, realm_state) {
    Value::Number(0.0)
  } else {
    match data.bag.properties.get(internal_slot) {
      Some(n) => n
      None => Value::Number(0.0)
    }
  }
}

///|
/// Get a TypedArray property by name (handles length, byteLength, byteOffset, buffer, and methods).
pub fn get_typedarray_prop(
  data : ObjectData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match prop {
    "length" => typedarray_get_view_slot(data, "[[ArrayLength]]", realm_state)
    "byteLength" =>
      typedarray_get_view_slot(data, "[[ByteLength]]", realm_state)
    "byteOffset" =>
      typedarray_get_view_slot(data, "[[ByteOffset]]", realm_state)
    "buffer" =>
      match data.bag.properties.get("[[ViewedArrayBuffer]]") {
        Some(buf) => buf
        None => Undefined
      }
    "BYTES_PER_ELEMENT" =>
      Value::Number(typed_array_bytes_per_element(data.class_name).to_double())
    "constructor" =>
      match data.bag.properties.get("constructor") {
        Some(v) => v
        None => Undefined
      }
    _ =>
      // Check if it's a numeric string (index access)
      try {
        let idx = @string.parse_int(prop)
        if idx >= 0 {
          return typedarray_get_index(data, idx, realm_state)
        }
        Undefined
      } catch {
        _ => Undefined
      }
  }
}

///|
/// Setup all TypedArray builtins.
pub fn setup_typedarray_builtins(
  env : Environment,
  well_known_symbols : @runtime.WellKnownSymbols,
  realm_state : @runtime.RealmState,
) -> Unit {
  let obj_proto = env.get("[[ObjectPrototype]]") catch { _ => Null }
  let iterator_sym = well_known_symbols.iterator
  let tostringtag_sym = well_known_symbols.to_string_tag
  let array_ctor = env.get("Array") catch { _ => Undefined }
  let array_to_string = match array_ctor {
    Object(array_ctor_data) =>
      match array_ctor_data.bag.properties.get("prototype") {
        Some(Object(array_proto_data)) =>
          match array_proto_data.bag.properties.get("toString") {
            Some(value) => value
            None => Undefined
          }
        _ => Undefined
      }
    _ => Undefined
  }

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
        @runtime.make_method_func(name="get \{getter_name}", length=0, fn(
          this_val,
          _args,
        ) raise {
          match this_val {
            Object(data) =>
              if is_typedarray_class(data.class_name) {
                typedarray_get_view_slot(data, internal_slot, realm_state)
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
      setter: None,
      is_accessor: true,
    }
  }

  // buffer getter
  ta_proto_props["buffer"] = Undefined
  ta_proto_descs["buffer"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(
      @runtime.make_method_func(name="get buffer", length=0, fn(
        this_val,
        _args,
      ) raise {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              match data.bag.properties.get("[[ViewedArrayBuffer]]") {
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
    setter: None,
    is_accessor: true,
  }

  // --- Prototype methods ---

  // set(source [, offset])
  ta_proto_props["set"] = @runtime.make_interp_method_func(
    name="set",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(
        this_val, "TypedArray.prototype.set", realm_state,
      )
      if args.length() == 0 {
        raise @errors.TypeError(
          message="TypedArray.prototype.set requires at least 1 argument",
        )
      }
      let target_offset = if args.length() > 1 {
        interp.to_index(args[1])
      } else {
        0
      }
      let ta_length = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      match args[0] {
        // Source is a TypedArray
        Object(src_data) if is_typedarray_class(src_data.class_name) => {
          let src_len = match src_data.bag.properties.get("[[ArrayLength]]") {
            Some(Value::Number(n)) => n.to_int()
            _ => 0
          }
          if target_offset + src_len > ta_length {
            raise @errors.RangeError(message="Source is too large")
          }
          // Buffer all source elements first to handle overlapping ArrayBuffers
          let temp : Array[Double] = []
          for i = 0; i < src_len; i = i + 1 {
            let val = typedarray_get_index(src_data, i, realm_state)
            match val {
              Value::Number(n) => temp.push(n)
              _ => temp.push(0.0)
            }
          }
          for i = 0; i < src_len; i = i + 1 {
            typedarray_set_index(data, target_offset + i, temp[i], realm_state)
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
            let num = interp.to_number(val)
            typedarray_set_index(data, target_offset + i, num, realm_state)
          }
          Undefined
        }
        src => {
          // Generic array-like with length property
          let src_len = match src {
            Object(src_obj) =>
              match src_obj.bag.properties.get("length") {
                Some(v) => interp.to_number(v).to_int()
                _ => 0
              }
            _ => 0
          }
          if target_offset + src_len > ta_length {
            raise @errors.RangeError(message="Source is too large")
          }
          for i = 0; i < src_len; i = i + 1 {
            let val = match src {
              Object(src_obj) =>
                match src_obj.bag.properties.get(i.to_string()) {
                  Some(v) => v
                  _ => Undefined
                }
              _ => Undefined
            }
            let num = interp.to_number(val)
            typedarray_set_index(data, target_offset + i, num, realm_state)
          }
          Undefined
        }
      }
    },
  )

  // subarray(begin, end)
  ta_proto_props["subarray"] = @runtime.make_interp_method_func(
    name="subarray",
    length=2,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "subarray", realm_state)
      let ta_length = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let relative_begin = if args.length() > 0 {
        interp.to_number(args[0]).to_int()
      } else {
        0
      }
      let begin_index = if relative_begin < 0 {
        let b = ta_length + relative_begin
        if b < 0 {
          0
        } else {
          b
        }
      } else if relative_begin > ta_length {
        ta_length
      } else {
        relative_begin
      }
      let relative_end = if args.length() > 1 {
        match args[1] {
          Undefined => ta_length
          _ => interp.to_number(args[1]).to_int()
        }
      } else {
        ta_length
      }
      let end_index = if relative_end < 0 {
        let e = ta_length + relative_end
        if e < 0 {
          0
        } else {
          e
        }
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
      let buffer = match data.bag.properties.get("[[ViewedArrayBuffer]]") {
        Some(buf) => buf
        None => raise @errors.TypeError(message="TypedArray has no buffer")
      }
      let cur_offset = match data.bag.properties.get("[[ByteOffset]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let bpe = typed_array_bytes_per_element(data.class_name)
      let new_offset = cur_offset + begin_index * bpe
      // §22.2.3.27 step 22: TypedArraySpeciesCreate(O, « buffer, byteOffset,
      // newLength »). The species constructor receives the underlying buffer
      // + offset + length and is responsible for creating a view; the
      // default %TypedArray% constructor's three-arg form does exactly this.
      typed_array_species_create(interp, this_val, [
        buffer,
        Value::Number(new_offset.to_double()),
        Value::Number(new_length.to_double()),
      ])
    },
  )

  // slice(begin, end)
  ta_proto_props["slice"] = @runtime.make_interp_method_func(
    name="slice",
    length=2,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "slice", realm_state)
      let ta_length = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let relative_begin = if args.length() > 0 {
        interp.to_number(args[0]).to_int()
      } else {
        0
      }
      let begin_index = if relative_begin < 0 {
        let b = ta_length + relative_begin
        if b < 0 {
          0
        } else {
          b
        }
      } else if relative_begin > ta_length {
        ta_length
      } else {
        relative_begin
      }
      let relative_end = if args.length() > 1 {
        match args[1] {
          Undefined => ta_length
          _ => interp.to_number(args[1]).to_int()
        }
      } else {
        ta_length
      }
      let end_index = if relative_end < 0 {
        let e = ta_length + relative_end
        if e < 0 {
          0
        } else {
          e
        }
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
      // §22.2.3.27 step 13: TypedArraySpeciesCreate(O, « count »). Unlike
      // subarray, slice's result has its OWN buffer (per spec: a copy, not a
      // view), so the species ctor is given just the length argument.
      let new_ta = typed_array_species_create(interp, this_val, [
        Value::Number(new_length.to_double()),
      ])
      // §22.2.3.27 step 14: ONLY if count > 0, validate that the source's
      // buffer is still attached. A species ctor that detaches the source is
      // allowed when count == 0 — `ta.slice(0, 0)` must still return an empty
      // TA even if the species ctor (or arg coercion before species) detached
      // `ta.buffer`. Without this guard, we'd throw too eagerly.
      if new_length > 0 {
        let _ = validate_typed_array(this_val, "slice", realm_state)
        match new_ta {
          Object(new_data) =>
            for i = 0; i < new_length; i = i + 1 {
              let val = typedarray_get_index(data, begin_index + i, realm_state)
              let num = match val {
                Value::Number(n) => n
                _ => 0.0
              }
              typedarray_set_index(new_data, i, num, realm_state)
            }
          _ => ()
        }
      }
      new_ta
    },
  )

  // copyWithin(target, start [, end])
  ta_proto_props["copyWithin"] = @runtime.make_interp_method_func(
    name="copyWithin",
    length=2,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "copyWithin", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let target_idx = if args.length() > 0 {
        let t = interp.to_number(args[0]).to_int()
        if t < 0 {
          let r = len + t
          if r < 0 {
            0
          } else {
            r
          }
        } else if t > len {
          len
        } else {
          t
        }
      } else {
        0
      }
      let start_idx = if args.length() > 1 {
        let s = interp.to_number(args[1]).to_int()
        if s < 0 {
          let r = len + s
          if r < 0 {
            0
          } else {
            r
          }
        } else if s > len {
          len
        } else {
          s
        }
      } else {
        0
      }
      let end_idx = if args.length() > 2 {
        match args[2] {
          Undefined => len
          _ => {
            let e = interp.to_number(args[2]).to_int()
            if e < 0 {
              let r = len + e
              if r < 0 {
                0
              } else {
                r
              }
            } else if e > len {
              len
            } else {
              e
            }
          }
        }
      } else {
        len
      }
      let count = {
        let c1 = end_idx - start_idx
        let c2 = len - target_idx
        if c1 < c2 {
          c1
        } else {
          c2
        }
      }
      if count > 0 {
        // Read all source values first to handle overlapping
        let temp : Array[Double] = []
        for i = 0; i < count; i = i + 1 {
          let val = typedarray_get_index(data, start_idx + i, realm_state)
          match val {
            Value::Number(n) => temp.push(n)
            _ => temp.push(0.0)
          }
        }
        for i = 0; i < count; i = i + 1 {
          typedarray_set_index(data, target_idx + i, temp[i], realm_state)
        }
      }
      this_val
    },
  )

  // fill(value [, start [, end]])
  ta_proto_props["fill"] = @runtime.make_interp_method_func(
    name="fill",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "fill", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let fill_val = if args.length() > 0 {
        interp.to_number(args[0])
      } else {
        0.0
      }
      let start_idx = if args.length() > 1 {
        let s = interp.to_number(args[1]).to_int()
        if s < 0 {
          let r = len + s
          if r < 0 {
            0
          } else {
            r
          }
        } else if s > len {
          len
        } else {
          s
        }
      } else {
        0
      }
      let end_idx = if args.length() > 2 {
        match args[2] {
          Undefined => len
          _ => {
            let e = interp.to_number(args[2]).to_int()
            if e < 0 {
              let r = len + e
              if r < 0 {
                0
              } else {
                r
              }
            } else if e > len {
              len
            } else {
              e
            }
          }
        }
      } else {
        len
      }
      for i = start_idx; i < end_idx; i = i + 1 {
        typedarray_set_index(data, i, fill_val, realm_state)
      }
      this_val
    },
  )

  // indexOf(searchElement [, fromIndex])
  ta_proto_props["indexOf"] = @runtime.make_interp_method_func(
    name="indexOf",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "indexOf", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      if len == 0 || args.length() == 0 {
        return Value::Number(-1.0)
      }
      let search_val = args[0]
      let from_idx = if args.length() > 1 {
        let f = interp.to_number(args[1]).to_int()
        if f < 0 {
          let r = len + f
          if r < 0 {
            0
          } else {
            r
          }
        } else {
          f
        }
      } else {
        0
      }
      for i = from_idx; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        if typedarray_index_search_matches(search_val, elem) {
          return Value::Number(i.to_double())
        }
      }
      Value::Number(-1.0)
    },
  )

  // lastIndexOf(searchElement [, fromIndex])
  ta_proto_props["lastIndexOf"] = @runtime.make_interp_method_func(
    name="lastIndexOf",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "lastIndexOf", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      if len == 0 || args.length() == 0 {
        return Value::Number(-1.0)
      }
      let search_val = args[0]
      let from_idx = if args.length() > 1 {
        let f = interp.to_number(args[1]).to_int()
        if f < 0 {
          len + f
        } else if f >= len {
          len - 1
        } else {
          f
        }
      } else {
        len - 1
      }
      for i = from_idx; i >= 0; i = i - 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        if typedarray_index_search_matches(search_val, elem) {
          return Value::Number(i.to_double())
        }
      }
      Value::Number(-1.0)
    },
  )

  // includes(searchElement [, fromIndex])
  ta_proto_props["includes"] = @runtime.make_interp_method_func(
    name="includes",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "includes", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      if len == 0 || args.length() == 0 {
        return Value::Bool(false)
      }
      let search_val = args[0]
      let from_idx = if args.length() > 1 {
        let f = interp.to_number(args[1]).to_int()
        if f < 0 {
          let r = len + f
          if r < 0 {
            0
          } else {
            r
          }
        } else {
          f
        }
      } else {
        0
      }
      for i = from_idx; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        if typedarray_includes_search_matches(search_val, elem) {
          return Value::Bool(true)
        }
      }
      Value::Bool(false)
    },
  )

  // join(separator)
  ta_proto_props["join"] = @runtime.make_method_func(name="join", length=1, fn(
    this_val,
    args,
  ) raise {
    let (data, _) = validate_typed_array(this_val, "join", realm_state)
    let len = match data.bag.properties.get("[[ArrayLength]]") {
      Some(Value::Number(n)) => n.to_int()
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
      let elem = typedarray_get_index(data, i, realm_state)
      buf.write_string(elem.to_string())
    }
    Value::String_(buf.to_string())
  })

  // toString - delegates to join
  ta_proto_props["toString"] = match array_to_string {
    Undefined =>
      @runtime.make_method_func(name="toString", length=0, fn(
        this_val,
        _args,
      ) raise {
        let (data, _) = validate_typed_array(this_val, "toString", realm_state)
        let len = match data.bag.properties.get("[[ArrayLength]]") {
          Some(Value::Number(n)) => n.to_int()
          _ => 0
        }
        let buf = StringBuilder::new()
        for i = 0; i < len; i = i + 1 {
          if i > 0 {
            buf.write_string(",")
          }
          let elem = typedarray_get_index(data, i, realm_state)
          buf.write_string(elem.to_string())
        }
        Value::String_(buf.to_string())
      })
    to_string => to_string
  }

  ta_proto_props["toLocaleString"] = @runtime.make_interp_method_func(
    name="toLocaleString",
    length=0,
    fn(interp, this_val, _args) raise {
      let (data, _) = validate_typed_array(
        this_val, "toLocaleString", realm_state,
      )
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let parts : Array[String] = []
      let loc = @token.Loc::default()
      for i = 0; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        match elem {
          Null | Undefined => parts.push("")
          _ => {
            let tls = interp.get_property(elem, "toLocaleString", loc)
            if !@runtime.is_callable(tls) {
              raise @errors.TypeError(
                message="TypedArray.prototype.toLocaleString element method is not callable",
              )
            }
            let result = interp.call_value(tls, elem, [], loc)
            parts.push(interp.to_js_string(result))
          }
        }
      }
      Value::String_(parts.join(","))
    },
  )

  // reverse()
  ta_proto_props["reverse"] = @runtime.make_method_func(
    name="reverse",
    length=0,
    fn(this_val, _args) raise {
      let (data, _) = validate_typed_array(this_val, "reverse", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let mut lo = 0
      let mut hi = len - 1
      while lo < hi {
        let lo_val = typedarray_get_index(data, lo, realm_state)
        let hi_val = typedarray_get_index(data, hi, realm_state)
        let lo_num = match lo_val {
          Value::Number(n) => n
          _ => 0.0
        }
        let hi_num = match hi_val {
          Value::Number(n) => n
          _ => 0.0
        }
        typedarray_set_index(data, lo, hi_num, realm_state)
        typedarray_set_index(data, hi, lo_num, realm_state)
        lo = lo + 1
        hi = hi - 1
      }
      this_val
    },
  )

  // sort([comparefn]) - uses InterpreterCallable for custom comparator support
  ta_proto_props["sort"] = @runtime.make_interp_method_func(
    name="sort",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "sort", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      // Read all elements into temp array
      let temp : Array[Double] = []
      for i = 0; i < len; i = i + 1 {
        let val = typedarray_get_index(data, i, realm_state)
        match val {
          Value::Number(n) => temp.push(n)
          _ => temp.push(0.0)
        }
      }
      let has_comparefn = args.length() > 0 && !(args[0] is Undefined)
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
            [Value::Number(a), Value::Number(b)],
            loc,
          ) catch {
            e => {
              caught_error = Some(e)
              return 0
            }
          }
          let cmp = interp.to_number(result) catch {
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
            if a_neg && !b_neg {
              return -1
            }
            if !a_neg && b_neg {
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
        typedarray_set_index(data, i, temp[i], realm_state)
      }
      this_val
    },
  )

  // at(index)
  ta_proto_props["at"] = @runtime.make_interp_method_func(name="at", length=1, fn(
    interp,
    this_val,
    args,
  ) raise {
    let (data, _) = validate_typed_array(this_val, "at", realm_state)
    let len = match data.bag.properties.get("[[ArrayLength]]") {
      Some(Value::Number(n)) => n.to_int()
      _ => 0
    }
    let idx = if args.length() > 0 {
      interp.to_number(args[0]).to_int()
    } else {
      0
    }
    let actual_idx = if idx < 0 { len + idx } else { idx }
    if actual_idx < 0 || actual_idx >= len {
      Undefined
    } else {
      typedarray_get_index(data, actual_idx, realm_state)
    }
  })

  // entries() - returns an iterator of [index, value] pairs
  ta_proto_props["entries"] = @runtime.make_method_func(
    name="entries",
    length=0,
    fn(this_val, _args) raise {
      let (data, _) = validate_typed_array(this_val, "entries", realm_state)
      let index_ref : Ref[Int] = { val: 0 }
      let next_method = @runtime.make_native_func(name="next", fn(_a) raise {
        // Re-check detachment and length on each next() call per spec
        let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
          Some(Value::Number(n)) => n.to_int()
          _ => -1
        }
        if buf_id >= 0 &&
          is_arraybuffer_state_detached(
            typedarray_arraybuffer_state(data, realm_state),
            buf_id,
          ) {
          raise @errors.TypeError(
            message="Cannot iterate over a detached ArrayBuffer",
          )
        }
        let len = match data.bag.properties.get("[[ArrayLength]]") {
          Some(Value::Number(n)) => n.to_int()
          _ => 0
        }
        let idx = index_ref.val
        if idx < len {
          let value = typedarray_get_index(data, idx, realm_state)
          index_ref.val = idx + 1
          let pair = @runtime.make_array([Value::Number(idx.to_double()), value])
          let result_props : Map[String, Value] = {}
          result_props["value"] = pair
          result_props["done"] = Value::Bool(false)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
            arraybuffer_state: None,
          })
        } else {
          let result_props : Map[String, Value] = {}
          result_props["value"] = Undefined
          result_props["done"] = Value::Bool(true)
          Value::Object({
            bag: {
              properties: result_props,
              symbol_properties: {},
              descriptors: {},
              symbol_descriptors: {},
            },
            prototype: Null,
            callable: None,
            class_name: "Object",
            extensible: true,
            arraybuffer_state: None,
          })
        }
      })
      let iter_props : Map[String, Value] = {}
      iter_props["next"] = @runtime.stamp_function_realm(
        next_method,
        realm_state=Some(realm_state),
      )
      Value::Object({
        bag: {
          properties: iter_props,
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
        },
        prototype: realm_state.get_array_iterator_proto(),
        callable: None,
        class_name: "Array Iterator",
        extensible: true,
        arraybuffer_state: None,
      })
    },
  )

  // keys() - returns an iterator of indices
  ta_proto_props["keys"] = @runtime.make_method_func(name="keys", length=0, fn(
    this_val,
    _args,
  ) raise {
    let (data, _) = validate_typed_array(this_val, "keys", realm_state)
    let index_ref : Ref[Int] = { val: 0 }
    let next_method = @runtime.make_native_func(name="next", fn(_a) raise {
      // Re-check detachment and length on each next() call per spec
      let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => -1
      }
      if buf_id >= 0 &&
        is_arraybuffer_state_detached(
          typedarray_arraybuffer_state(data, realm_state),
          buf_id,
        ) {
        raise @errors.TypeError(
          message="Cannot iterate over a detached ArrayBuffer",
        )
      }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let idx = index_ref.val
      if idx < len {
        index_ref.val = idx + 1
        let result_props : Map[String, Value] = {}
        result_props["value"] = Value::Number(idx.to_double())
        result_props["done"] = Value::Bool(false)
        Value::Object({
          bag: {
            properties: result_props,
            symbol_properties: {},
            descriptors: {},
            symbol_descriptors: {},
          },
          prototype: Null,
          callable: None,
          class_name: "Object",
          extensible: true,
          arraybuffer_state: None,
        })
      } else {
        let result_props : Map[String, Value] = {}
        result_props["value"] = Undefined
        result_props["done"] = Value::Bool(true)
        Value::Object({
          bag: {
            properties: result_props,
            symbol_properties: {},
            descriptors: {},
            symbol_descriptors: {},
          },
          prototype: Null,
          callable: None,
          class_name: "Object",
          extensible: true,
          arraybuffer_state: None,
        })
      }
    })
    let iter_props : Map[String, Value] = {}
    iter_props["next"] = @runtime.stamp_function_realm(
      next_method,
      realm_state=Some(realm_state),
    )
    Value::Object({
      bag: {
        properties: iter_props,
        symbol_properties: {},
        descriptors: {},
        symbol_descriptors: {},
      },
      prototype: realm_state.get_array_iterator_proto(),
      callable: None,
      class_name: "Array Iterator",
      extensible: true,
      arraybuffer_state: None,
    })
  })

  // values() - returns an iterator of values (same as [Symbol.iterator])
  let values_fn = @runtime.make_method_func(name="values", length=0, fn(
    this_val,
    _args,
  ) raise {
    let (data, _) = validate_typed_array(this_val, "values", realm_state)
    let index_ref : Ref[Int] = { val: 0 }
    let next_method = @runtime.make_native_func(name="next", fn(_a) raise {
      // Re-check detachment and length on each next() call per spec
      let buf_id = match data.bag.properties.get("[[ArrayBufferID]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => -1
      }
      if buf_id >= 0 &&
        is_arraybuffer_state_detached(
          typedarray_arraybuffer_state(data, realm_state),
          buf_id,
        ) {
        raise @errors.TypeError(
          message="Cannot iterate over a detached ArrayBuffer",
        )
      }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let idx = index_ref.val
      if idx < len {
        let value = typedarray_get_index(data, idx, realm_state)
        index_ref.val = idx + 1
        let result_props : Map[String, Value] = {}
        result_props["value"] = value
        result_props["done"] = Value::Bool(false)
        Value::Object({
          bag: {
            properties: result_props,
            symbol_properties: {},
            descriptors: {},
            symbol_descriptors: {},
          },
          prototype: Null,
          callable: None,
          class_name: "Object",
          extensible: true,
          arraybuffer_state: None,
        })
      } else {
        let result_props : Map[String, Value] = {}
        result_props["value"] = Undefined
        result_props["done"] = Value::Bool(true)
        Value::Object({
          bag: {
            properties: result_props,
            symbol_properties: {},
            descriptors: {},
            symbol_descriptors: {},
          },
          prototype: Null,
          callable: None,
          class_name: "Object",
          extensible: true,
          arraybuffer_state: None,
        })
      }
    })
    let iter_props : Map[String, Value] = {}
    iter_props["next"] = @runtime.stamp_function_realm(
      next_method,
      realm_state=Some(realm_state),
    )
    Value::Object({
      bag: {
        properties: iter_props,
        symbol_properties: {},
        descriptors: {},
        symbol_descriptors: {},
      },
      prototype: realm_state.get_array_iterator_proto(),
      callable: None,
      class_name: "Array Iterator",
      extensible: true,
      arraybuffer_state: None,
    })
  })
  ta_proto_props["values"] = values_fn

  // forEach(callbackFn [, thisArg])
  ta_proto_props["forEach"] = @runtime.make_interp_method_func(
    name="forEach",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "forEach", realm_state)
      if args.length() == 0 {
        raise @errors.TypeError(message="forEach requires a callback function")
      }
      let callback = args[0]
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      for i = 0; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let _ = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
      }
      Undefined
    },
  )

  // map(callbackFn [, thisArg])
  ta_proto_props["map"] = @runtime.make_interp_method_func(
    name="map",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "map", realm_state)
      // §22.2.3.20 step 4: IsCallable(callbackfn) check happens BEFORE
      // species lookup. A non-callable callback must throw without any
      // observable species side effects (e.g. without invoking @@species).
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(message="map callback is not callable")
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      // §22.2.3.20 step 5: TypedArraySpeciesCreate(O, « len »).
      // Note: §22.2.3.20 has NO post-species source-detach validation. If a
      // user-supplied species ctor detaches the source mid-construction,
      // `typedarray_get_index` returns `Undefined`, the callback observes
      // it, and the result holds coerced values — that's spec-correct, not
      // a hazard. (Cf. §22.2.3.27 slice, which DOES validate, but only
      // when count > 0; the asymmetry is deliberate.)
      let result = typed_array_species_create(interp, this_val, [
        Value::Number(len.to_double()),
      ])
      match result {
        Object(result_data) =>
          for i = 0; i < len; i = i + 1 {
            let elem = typedarray_get_index(data, i, realm_state)
            let mapped = interp.call_value(
              callback,
              this_arg,
              [elem, Value::Number(i.to_double()), this_val],
              loc,
            )
            let num = interp.to_number(mapped)
            typedarray_set_index(result_data, i, num, realm_state)
          }
        _ => ()
      }
      result
    },
  )

  // filter(callbackFn [, thisArg])
  ta_proto_props["filter"] = @runtime.make_interp_method_func(
    name="filter",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "filter", realm_state)
      // §22.2.3.9 step 4: IsCallable(callbackfn) check happens BEFORE the
      // selection loop. A non-callable callback must throw immediately.
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(message="filter callback is not callable")
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      let kept : Array[Double] = []
      for i = 0; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let result = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
        if @runtime.is_truthy(result) {
          match elem {
            Value::Number(n) => kept.push(n)
            _ => kept.push(0.0)
          }
        }
      }
      // §22.2.3.9 step 10: TypedArraySpeciesCreate(O, « kept_length »).
      // Resolves the species constructor (may differ from `data.class_name`
      // if user sets `sample.constructor[@@species]` to a custom ctor) and
      // validates the result. The fast-path `make_typedarray_object` is
      // unsafe here — it ignores `@@species` and would silently bypass the
      // §7.3.20 conflict checks.
      let result = typed_array_species_create(interp, this_val, [
        Value::Number(kept.length().to_double()),
      ])
      match result {
        Object(result_data) =>
          for i = 0; i < kept.length(); i = i + 1 {
            typedarray_set_index(result_data, i, kept[i], realm_state)
          }
        _ => ()
      }
      result
    },
  )

  // reduce(callbackFn [, initialValue])
  ta_proto_props["reduce"] = @runtime.make_interp_method_func(
    name="reduce",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "reduce", realm_state)
      if args.length() == 0 {
        raise @errors.TypeError(message="reduce requires a callback function")
      }
      let callback = args[0]
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      let mut accumulator : Value = Undefined
      let mut start_idx = 0
      if args.length() > 1 {
        accumulator = args[1]
      } else {
        if len == 0 {
          raise @errors.TypeError(
            message="Reduce of empty array with no initial value",
          )
        }
        accumulator = typedarray_get_index(data, 0, realm_state)
        start_idx = 1
      }
      for i = start_idx; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        accumulator = interp.call_value(
          callback,
          Undefined,
          [accumulator, elem, Value::Number(i.to_double()), this_val],
          loc,
        )
      }
      accumulator
    },
  )

  // reduceRight(callbackFn [, initialValue])
  ta_proto_props["reduceRight"] = @runtime.make_interp_method_func(
    name="reduceRight",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "reduceRight", realm_state)
      if args.length() == 0 {
        raise @errors.TypeError(
          message="reduceRight requires a callback function",
        )
      }
      let callback = args[0]
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      let mut accumulator : Value = Undefined
      let mut start_idx = len - 1
      if args.length() > 1 {
        accumulator = args[1]
      } else {
        if len == 0 {
          raise @errors.TypeError(
            message="Reduce of empty array with no initial value",
          )
        }
        accumulator = typedarray_get_index(data, len - 1, realm_state)
        start_idx = len - 2
      }
      for i = start_idx; i >= 0; i = i - 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        accumulator = interp.call_value(
          callback,
          Undefined,
          [accumulator, elem, Value::Number(i.to_double()), this_val],
          loc,
        )
      }
      accumulator
    },
  )

  // every(callbackFn [, thisArg])
  ta_proto_props["every"] = @runtime.make_interp_method_func(
    name="every",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "every", realm_state)
      if args.length() == 0 {
        raise @errors.TypeError(message="every requires a callback function")
      }
      let callback = args[0]
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      for i = 0; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let result = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
        if !@runtime.is_truthy(result) {
          return Value::Bool(false)
        }
      }
      Value::Bool(true)
    },
  )

  // some(callbackFn [, thisArg])
  ta_proto_props["some"] = @runtime.make_interp_method_func(
    name="some",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "some", realm_state)
      if args.length() == 0 {
        raise @errors.TypeError(message="some requires a callback function")
      }
      let callback = args[0]
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      for i = 0; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let result = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
        if @runtime.is_truthy(result) {
          return Value::Bool(true)
        }
      }
      Value::Bool(false)
    },
  )

  // find(callbackFn [, thisArg])
  ta_proto_props["find"] = @runtime.make_interp_method_func(
    name="find",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "find", realm_state)
      if args.length() == 0 {
        raise @errors.TypeError(message="find requires a callback function")
      }
      let callback = args[0]
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      for i = 0; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let result = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
        if @runtime.is_truthy(result) {
          return elem
        }
      }
      Undefined
    },
  )

  // findIndex(callbackFn [, thisArg])
  ta_proto_props["findIndex"] = @runtime.make_interp_method_func(
    name="findIndex",
    length=1,
    fn(interp, this_val, args) raise {
      let (data, _) = validate_typed_array(this_val, "findIndex", realm_state)
      if args.length() == 0 {
        raise @errors.TypeError(
          message="findIndex requires a callback function",
        )
      }
      let callback = args[0]
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let loc = @token.Loc::default()
      for i = 0; i < len; i = i + 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let result = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
        if @runtime.is_truthy(result) {
          return Value::Number(i.to_double())
        }
      }
      Value::Number(-1.0)
    },
  )

  ta_proto_props["findLast"] = @runtime.make_interp_method_func(
    name="findLast",
    length=1,
    fn(interp, this_val, args) raise {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let (data, _) = validate_typed_array(this_val, "findLast", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      for i = len - 1; i >= 0; i = i - 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let result = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
        if @runtime.is_truthy(result) {
          return elem
        }
      }
      Undefined
    },
  )

  ta_proto_props["findLastIndex"] = @runtime.make_interp_method_func(
    name="findLastIndex",
    length=1,
    fn(interp, this_val, args) raise {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let (data, _) = validate_typed_array(
        this_val, "findLastIndex", realm_state,
      )
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      for i = len - 1; i >= 0; i = i - 1 {
        let elem = typedarray_get_index(data, i, realm_state)
        let result = interp.call_value(
          callback,
          this_arg,
          [elem, Value::Number(i.to_double()), this_val],
          loc,
        )
        if @runtime.is_truthy(result) {
          return Value::Number(i.to_double())
        }
      }
      Value::Number(-1.0)
    },
  )

  ta_proto_props["toReversed"] = @runtime.make_method_func(
    name="toReversed",
    length=0,
    fn(this_val, _args) raise {
      let (data, _) = validate_typed_array(this_val, "toReversed", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let proto = data.prototype
      let new_ta = make_typedarray_object(data.class_name, len, proto, env)
      match new_ta {
        Object(new_data) =>
          for i = 0; i < len; i = i + 1 {
            let val = typedarray_get_index(data, len - 1 - i, realm_state)
            let num = match val {
              Value::Number(n) => n
              _ => 0.0
            }
            typedarray_set_index(new_data, i, num, realm_state)
          }
        _ => ()
      }
      new_ta
    },
  )

  ta_proto_props["toSorted"] = @runtime.make_interp_method_func(
    name="toSorted",
    length=1,
    fn(interp, this_val, args) raise {
      let comparefn = if args.length() > 0 {
        match args[0] {
          Undefined => None
          v => Some(v)
        }
      } else {
        None
      }
      let (data, _) = validate_typed_array(this_val, "toSorted", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      // Collect elements
      let elements : Array[Double] = []
      for i = 0; i < len; i = i + 1 {
        let val = typedarray_get_index(data, i, realm_state)
        match val {
          Value::Number(n) => elements.push(n)
          _ => elements.push(0.0)
        }
      }
      let loc = @token.Loc::default()
      match comparefn {
        Some(cmp_fn) =>
          elements.sort_by(fn(a, b) {
            let result = interp.call_value(
              cmp_fn,
              Undefined,
              [Value::Number(a), Value::Number(b)],
              loc,
            ) catch {
              _ => Value::Number(0.0)
            }
            match result {
              Value::Number(n) =>
                if n < 0.0 {
                  -1
                } else if n > 0.0 {
                  1
                } else {
                  0
                }
              _ => 0
            }
          })
        None =>
          elements.sort_by(fn(a, b) {
            if a < b {
              -1
            } else if a > b {
              1
            } else {
              0
            }
          })
      }
      let proto = data.prototype
      let new_ta = make_typedarray_object(data.class_name, len, proto, env)
      match new_ta {
        Object(new_data) =>
          for i = 0; i < len; i = i + 1 {
            typedarray_set_index(new_data, i, elements[i], realm_state)
          }
        _ => ()
      }
      new_ta
    },
  )

  ta_proto_props["with"] = @runtime.make_interp_method_func(
    name="with",
    length=2,
    fn(interp, this_val, args) raise {
      let index_val = if args.length() > 0 { args[0] } else { Undefined }
      let value_val = if args.length() > 1 { args[1] } else { Undefined }
      let (data, _) = validate_typed_array(this_val, "with", realm_state)
      let len = match data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      let mut idx = interp.to_number(index_val).to_int()
      let replacement_num = interp.to_number(value_val)
      if idx < 0 {
        idx = len + idx
      }
      if idx < 0 || idx >= len {
        raise @errors.RangeError(
          message="Invalid index for TypedArray.prototype.with",
        )
      }
      let proto = data.prototype
      let new_ta = make_typedarray_object(data.class_name, len, proto, env)
      match new_ta {
        Object(new_data) => {
          for i = 0; i < len; i = i + 1 {
            let val = typedarray_get_index(data, i, realm_state)
            let num = match val {
              Value::Number(n) => n
              _ => 0.0
            }
            typedarray_set_index(new_data, i, num, realm_state)
          }
          typedarray_set_index(new_data, idx, replacement_num, realm_state)
        }
        _ => ()
      }
      new_ta
    },
  )

  // Mark all prototype methods as non-enumerable (per spec)
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  ta_proto_descs["set"] = method_desc
  ta_proto_descs["subarray"] = method_desc
  ta_proto_descs["slice"] = method_desc
  ta_proto_descs["copyWithin"] = method_desc
  ta_proto_descs["fill"] = method_desc
  ta_proto_descs["indexOf"] = method_desc
  ta_proto_descs["lastIndexOf"] = method_desc
  ta_proto_descs["includes"] = method_desc
  ta_proto_descs["join"] = method_desc
  ta_proto_descs["toLocaleString"] = method_desc
  ta_proto_descs["toString"] = method_desc
  ta_proto_descs["reverse"] = method_desc
  ta_proto_descs["sort"] = method_desc
  ta_proto_descs["at"] = method_desc
  ta_proto_descs["entries"] = method_desc
  ta_proto_descs["keys"] = method_desc
  ta_proto_descs["values"] = method_desc
  ta_proto_descs["forEach"] = method_desc
  ta_proto_descs["map"] = method_desc
  ta_proto_descs["filter"] = method_desc
  ta_proto_descs["reduce"] = method_desc
  ta_proto_descs["reduceRight"] = method_desc
  ta_proto_descs["every"] = method_desc
  ta_proto_descs["some"] = method_desc
  ta_proto_descs["find"] = method_desc
  ta_proto_descs["findIndex"] = method_desc
  ta_proto_descs["findLast"] = method_desc
  ta_proto_descs["findLastIndex"] = method_desc
  ta_proto_descs["toReversed"] = method_desc
  ta_proto_descs["toSorted"] = method_desc
  ta_proto_descs["with"] = method_desc

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
    is_accessor: false,
  }
  ta_proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(
      @runtime.make_method_func(name="get [Symbol.toStringTag]", length=0, fn(
        this_val,
        _args,
      ) {
        match this_val {
          Object(data) =>
            if is_typedarray_class(data.class_name) {
              Value::String_(data.class_name)
            } else {
              Undefined
            }
          _ => Undefined
        }
      }),
    ),
    setter: None,
    is_accessor: true,
  }

  let ta_proto : Value = Value::Object({
    bag: {
      properties: ta_proto_props,
      symbol_properties: ta_proto_sym_props,
      descriptors: ta_proto_descs,
      symbol_descriptors: ta_proto_sym_descs,
    },
    prototype: obj_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  env.def_builtin("[[TypedArrayPrototype]]", ta_proto)

  // --- Create %TypedArray% intrinsic constructor ---
  // Per spec, %TypedArray% is an abstract constructor (not directly exposed as a global).
  // It serves as the [[Prototype]] of all individual TypedArray constructors
  // (e.g., Object.getPrototypeOf(Int8Array) === TypedArray).
  // It is NOT directly constructible.
  let func_proto = env.get("[[FunctionPrototype]]") catch { _ => Null }
  let ta_ctor_props : Map[String, Value] = {}
  ta_ctor_props["prototype"] = ta_proto
  ta_ctor_props["name"] = Value::String_("TypedArray")
  ta_ctor_props["length"] = Value::Number(0.0)
  ta_ctor_props["from"] = @runtime.make_interp_method_func(
    name="from",
    length=1,
    fn(interp, this_val, args) raise {
      if !@runtime.is_constructor_value(this_val) {
        raise @errors.TypeError(
          message="TypedArray.from called on non-constructor",
        )
      }
      if args.length() == 0 {
        raise @errors.TypeError(
          message="TypedArray.from requires at least 1 argument",
        )
      }
      let source = args[0]
      let has_map_fn = args.length() > 1 && !(args[1] is Undefined)
      let map_fn = if has_map_fn { args[1] } else { Undefined }
      if has_map_fn && !@runtime.is_callable(map_fn) {
        raise @errors.TypeError(message="TypedArray.from mapFn is not callable")
      }
      let this_arg = if args.length() > 2 { args[2] } else { Undefined }
      let loc = @token.Loc::default()
      let source_values : Array[Value] = []
      let iterator_sym = interp.realm_state.well_known_symbols.iterator
      let iterator_method = interp.get_computed_property(
        source,
        Symbol(iterator_sym),
        loc,
      )
      match iterator_method {
        Undefined | Null => {
          let array_like = to_object(source, interp)
          let len = @runtime.to_array_like_length_interp(array_like, interp)
          for i = 0; i < len; i = i + 1 {
            source_values.push(
              interp.get_property(array_like, i.to_string(), loc),
            )
          }
        }
        _ => {
          if !@runtime.is_callable(iterator_method) {
            raise @errors.TypeError(
              message="TypedArray.from source is not iterable",
            )
          }
          for
            value in typedarray_collect_iterator_values(
              interp, source, iterator_method, loc,
            ) {
            source_values.push(value)
          }
        }
      }
      let len = source_values.length()
      let result = interp.construct_value(
        this_val,
        [Value::Number(len.to_double())],
        loc,
      )
      let (result_data, _) = validate_typed_array(
        result,
        "TypedArray.from result",
        interp.realm_state,
      )
      let actual_len = match result_data.bag.properties.get("[[ArrayLength]]") {
        Some(Value::Number(n)) => n.to_int()
        _ => 0
      }
      if actual_len < len {
        raise @errors.TypeError(message="TypedArray.from result is too short")
      }
      for i = 0; i < len; i = i + 1 {
        let value = source_values[i]
        let mapped = if has_map_fn {
          interp.call_value(
            map_fn,
            this_arg,
            [value, Value::Number(i.to_double())],
            loc,
          )
        } else {
          value
        }
        let _ = interp.set_property(
          result,
          i.to_string(),
          mapped,
          loc,
          strict=true,
        )
      }
      result
    },
  )
  ta_ctor_props["of"] = @runtime.make_interp_method_func(name="of", length=0, fn(
    interp,
    this_val,
    args,
  ) raise {
    if !@runtime.is_constructor_value(this_val) {
      raise @errors.TypeError(message="TypedArray.of called on non-constructor")
    }
    let loc = @token.Loc::default()
    let len = args.length()
    let result = interp.construct_value(
      this_val,
      [Value::Number(len.to_double())],
      loc,
    )
    let (result_data, _) = validate_typed_array(
      result,
      "TypedArray.of result",
      interp.realm_state,
    )
    let actual_len = match result_data.bag.properties.get("[[ArrayLength]]") {
      Some(Value::Number(n)) => n.to_int()
      _ => 0
    }
    if actual_len < len {
      raise @errors.TypeError(message="TypedArray.of result is too short")
    }
    for i = 0; i < len; i = i + 1 {
      let _ = interp.set_property(
        result,
        i.to_string(),
        args[i],
        loc,
        strict=true,
      )
    }
    result
  })

  let ta_ctor_descs : Map[String, PropDescriptor] = {}
  ta_ctor_descs["prototype"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  ta_ctor_descs["name"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  ta_ctor_descs["length"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  ta_ctor_descs["from"] = method_desc
  ta_ctor_descs["of"] = method_desc
  let ta_ctor : Value = Value::Object({
    bag: {
      properties: ta_ctor_props,
      symbol_properties: {},
      descriptors: ta_ctor_descs,
      symbol_descriptors: {},
    },
    prototype: func_proto,
    callable: Some(
      NativeCallable("TypedArray", fn(_args) raise {
        raise @errors.TypeError(
          message="Abstract class TypedArray not directly constructable",
        )
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  // Set ta_proto.constructor = %TypedArray%
  match ta_proto {
    Object(proto_data) => {
      proto_data.bag.properties["constructor"] = ta_ctor
      proto_data.bag.descriptors["constructor"] = {
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
  // §22.2.5.4 %TypedArray%[@@species]: getter returning `this`. Each concrete
  // TypedArray constructor (Int8Array, Float64Array, …) has %TypedArray% as
  // its [[Prototype]] (set at line ~2567 below), so they all inherit this
  // getter via the prototype chain — no need to attach @@species to each.
  let ta_species_getter = @runtime.make_method_func(
    name="get [Symbol.species]",
    length=0,
    fn(this_val, _args) { this_val },
  )
  let ta_species_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(ta_species_getter),
    setter: None,
    is_accessor: true,
  }
  match ta_ctor {
    Object(ctor_data) => {
      let sp_sym = well_known_symbols.species
      ctor_data.bag.symbol_properties[sp_sym.id] = Undefined
      ctor_data.bag.symbol_descriptors[sp_sym.id] = ta_species_desc
    }
    _ => ()
  }
  env.def_builtin("[[TypedArrayConstructor]]", ta_ctor)

  // --- Create individual TypedArray constructors ---
  let type_names = [
    "Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array",
    "Int32Array", "Uint32Array", "Float32Array", "Float64Array", "BigInt64Array",
    "BigUint64Array",
  ]

  for type_name in type_names {
    let bpe = typed_array_bytes_per_element(type_name)

    // Per-type prototype inheriting from %TypedArray%.prototype
    let per_proto_props : Map[String, Value] = {}
    per_proto_props["BYTES_PER_ELEMENT"] = Value::Number(bpe.to_double())
    let per_proto_descs : Map[String, PropDescriptor] = {}
    per_proto_descs["BYTES_PER_ELEMENT"] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    }

    let per_proto : Value = Value::Object({
      bag: {
        properties: per_proto_props,
        symbol_properties: {},
        descriptors: per_proto_descs,
        symbol_descriptors: {},
      },
      prototype: ta_proto,
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    })

    // Constructor
    let ctor_props : Map[String, Value] = {}
    ctor_props["prototype"] = per_proto
    ctor_props["BYTES_PER_ELEMENT"] = Value::Number(bpe.to_double())
    ctor_props["name"] = Value::String_(type_name)
    ctor_props["length"] = Value::Number(3.0) // TypedArray constructors have length 3

    let ctor_descs : Map[String, PropDescriptor] = {}
    ctor_descs["prototype"] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    }
    ctor_descs["BYTES_PER_ELEMENT"] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    }
    ctor_descs["name"] = {
      writable: false,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
      is_accessor: false,
    }
    ctor_descs["length"] = {
      writable: false,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
      is_accessor: false,
    }

    let ctor : Value = Value::Object({
      bag: {
        properties: ctor_props,
        symbol_properties: {},
        descriptors: ctor_descs,
        symbol_descriptors: {},
      },
      prototype: ta_ctor,
      callable: Some(
        InterpreterCallableWithContext(type_name, fn(
          interp,
          context,
          _this_val,
          args,
        ) raise {
          let loc = @token.Loc::default()
          let resolve_ctor_proto = fn() -> Value raise Error {
            match context.new_target() {
              Some(new_target) => {
                let prototype = interp.get_property(
                  new_target, "prototype", loc,
                )
                match prototype {
                  Object(_)
                  | Array(_)
                  | Map(_)
                  | Set(_)
                  | Promise(_)
                  | Proxy(_) => prototype
                  _ => per_proto
                }
              }
              None => per_proto
            }
          }
          if !context.is_constructing() {
            raise @errors.TypeError(
              message="Constructor \{type_name} requires 'new'",
            )
          }
          if args.length() == 0 {
            return make_typedarray_object(
              type_name,
              0,
              resolve_ctor_proto(),
              env,
            )
          }
          let first = args[0]
          match first {
            Value::Number(_)
            | Value::String_(_)
            | Value::Bool(_)
            | Value::Null
            | Value::Undefined
            | Value::Symbol(_) => {
              let length = interp.to_index(first)
              make_typedarray_object(
                type_name,
                length,
                resolve_ctor_proto(),
                env,
              )
            }
            // From another TypedArray
            Object(src_data) if is_typedarray_class(src_data.class_name) => {
              let src_len = match
                src_data.bag.properties.get("[[ArrayLength]]") {
                Some(Value::Number(ln)) => ln.to_int()
                _ => 0
              }
              let result = make_typedarray_object(
                type_name,
                src_len,
                resolve_ctor_proto(),
                env,
              )
              match result {
                Object(result_data) =>
                  for i = 0; i < src_len; i = i + 1 {
                    let val = typedarray_get_index(src_data, i, realm_state)
                    let num = match val {
                      Value::Number(nv) => nv
                      _ => 0.0
                    }
                    typedarray_set_index(result_data, i, num, realm_state)
                  }
                _ => ()
              }
              result
            }
            // From ArrayBuffer
            Object(buf_data) if buf_data.class_name == "ArrayBuffer" => {
              let buf_byte_length = match
                buf_data.bag.properties.get("[[ArrayBufferByteLength]]") {
                Some(Value::Number(n)) => n.to_int()
                _ => 0
              }
              let byte_offset = if args.length() > 1 {
                match args[1] {
                  Undefined => 0
                  _ => {
                    let n = interp.to_index(args[1])
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
              if byte_offset > buf_byte_length {
                raise @errors.RangeError(
                  message="Start offset \{byte_offset} is outside the bounds of the buffer",
                )
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
                  _ => interp.to_index(args[2])
                }
              } else if (buf_byte_length - byte_offset) % bpe != 0 {
                raise @errors.RangeError(
                  message="byte length of \{type_name} should be a multiple of \{bpe}",
                )
              } else {
                (buf_byte_length - byte_offset) / bpe
              }
              if length < 0 {
                raise @errors.RangeError(message="Invalid typed array length")
              }
              if byte_offset + length * bpe > buf_byte_length {
                raise @errors.RangeError(
                  message="Invalid typed array length: \{length}",
                )
              }
              let check_buf_id = match
                buf_data.bag.properties.get("[[ArrayBufferID]]") {
                Some(Value::Number(n)) => n.to_int()
                _ => -1
              }
              if check_buf_id >= 0 &&
                is_arraybuffer_state_detached(
                  arraybuffer_state_from_data(
                    buf_data,
                    realm_state.arraybuffer_state,
                  ),
                  check_buf_id,
                ) {
                raise @errors.TypeError(
                  message="Cannot construct a TypedArray with a detached ArrayBuffer",
                )
              }
              make_typedarray_from_buffer(
                type_name,
                first,
                byte_offset,
                length,
                resolve_ctor_proto(),
              )
            }
            // From array-like or iterable arrays
            Array(_) => {
              let loc = @token.Loc::default()
              let iterator_sym = interp.realm_state.well_known_symbols.iterator
              let iterator_method = interp.get_computed_property(
                first,
                Symbol(iterator_sym),
                loc,
              )
              match iterator_method {
                Undefined | Null => {
                  let len = typedarray_to_array_like_length(first, interp)
                  if len > 0x7FFFFFFF {
                    raise @errors.RangeError(
                      message="Invalid typed array length: \{len}",
                    )
                  }
                  let result = make_typedarray_object(
                    type_name,
                    len,
                    resolve_ctor_proto(),
                    env,
                  )
                  match result {
                    Object(result_data) =>
                      for i = 0; i < len; i = i + 1 {
                        let v = interp.get_property(first, i.to_string(), loc)
                        let num = interp.to_number(v)
                        typedarray_set_index(result_data, i, num, realm_state)
                      }
                    _ => ()
                  }
                  result
                }
                _ => {
                  if !@runtime.is_callable(iterator_method) {
                    raise @errors.TypeError(
                      message="\{@runtime.type_of(first)} is not iterable",
                    )
                  }
                  let values = typedarray_collect_iterator_values(
                    interp, first, iterator_method, loc,
                  )
                  let len = values.length()
                  let result = make_typedarray_object(
                    type_name,
                    len,
                    resolve_ctor_proto(),
                    env,
                  )
                  match result {
                    Object(result_data) =>
                      for i = 0; i < len; i = i + 1 {
                        let num = @runtime.to_number(
                          values[i],
                          interp=Some(interp),
                        )
                        typedarray_set_index(result_data, i, num, realm_state)
                      }
                    _ => ()
                  }
                  result
                }
              }
            }
            // From generic object with length
            Object(_) => {
              let loc = @token.Loc::default()
              let iterator_sym = interp.realm_state.well_known_symbols.iterator
              let iterator_method = interp.get_computed_property(
                first,
                Symbol(iterator_sym),
                loc,
              )
              match iterator_method {
                Undefined | Null => {
                  let len = typedarray_to_array_like_length(first, interp)
                  if len > 0x7FFFFFFF {
                    raise @errors.RangeError(
                      message="Invalid typed array length: \{len}",
                    )
                  }
                  let result = make_typedarray_object(
                    type_name,
                    len,
                    resolve_ctor_proto(),
                    env,
                  )
                  match result {
                    Object(result_data) =>
                      for i = 0; i < len; i = i + 1 {
                        let v = interp.get_property(first, i.to_string(), loc)
                        let num = interp.to_number(v)
                        typedarray_set_index(result_data, i, num, realm_state)
                      }
                    _ => ()
                  }
                  result
                }
                _ => {
                  if !@runtime.is_callable(iterator_method) {
                    raise @errors.TypeError(
                      message="\{@runtime.type_of(first)} is not iterable",
                    )
                  }
                  let values = typedarray_collect_iterator_values(
                    interp, first, iterator_method, loc,
                  )
                  let len = values.length()
                  let result = make_typedarray_object(
                    type_name,
                    len,
                    resolve_ctor_proto(),
                    env,
                  )
                  match result {
                    Object(result_data) =>
                      for i = 0; i < len; i = i + 1 {
                        let num = @runtime.to_number(
                          values[i],
                          interp=Some(interp),
                        )
                        typedarray_set_index(result_data, i, num, realm_state)
                      }
                    _ => ()
                  }
                  result
                }
              }
            }
            _ => make_typedarray_object(type_name, 0, resolve_ctor_proto(), env)
          }
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    })

    // Link constructor
    match per_proto {
      Object(proto_data) => {
        proto_data.bag.properties["constructor"] = ctor
        proto_data.bag.descriptors["constructor"] = {
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

    env.def_builtin(type_name, ctor)
    env.def_builtin("[[\{type_name}Prototype]]", per_proto)
    // §22.2.4.7 TypedArraySpeciesCreate uses the *intrinsic* TA constructor as
    // its default — independent of the writable global binding. Stash a
    // reference under a name that JS source cannot reach (the `[[…]]`
    // brackets aren't valid identifier characters), so user code reassigning
    // `Int8Array = Uint8Array` doesn't drift the species default.
    env.def_builtin("[[\{type_name}Constructor]]", ctor)
  }
}

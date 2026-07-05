///|
// Engine-private negative symbol IDs for Array Iterator internal slots.
// These IDs are not registered in SymbolState, so JavaScript cannot obtain
// or enumerate keys for them via string or symbol property access.
const ARRAY_ITERATOR_NEXT_INDEX_SYMBOL_ID = -3

///|
const ARRAY_ITERATOR_TARGET_SYMBOL_ID = -4

///|
const ARRAY_ITERATOR_KIND_SYMBOL_ID = -5

///|
priv enum ArrayIteratorKind {
  Keys
  Values
  Entries
}

///|
// Hidden slot on the realm-owned Array.prototype that preserves the original
// %ArrayProto_values% intrinsic even if user code later mutates the public
// `Array.prototype.values` property.
const ARRAY_PROTO_VALUES_INTRINSIC_SYMBOL_ID = -112

///|
// Engine-private negative symbol IDs for String Iterator internal slots.
const STRING_ITERATOR_NEXT_INDEX_SYMBOL_ID = -136

///|
const STRING_ITERATOR_STRING_SYMBOL_ID = -137

///|
fn array_iterator_internal_slot_descriptor() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
pub fn RealmState::set_array_proto_values_intrinsic(
  self : RealmState,
  values_fn : Value,
) -> Unit {
  match self.get_array_proto() {
    Object(proto_data) => {
      proto_data.bag.symbol_properties[ARRAY_PROTO_VALUES_INTRINSIC_SYMBOL_ID] = values_fn
      proto_data.bag.symbol_descriptors[ARRAY_PROTO_VALUES_INTRINSIC_SYMBOL_ID] = array_iterator_internal_slot_descriptor()
    }
    _ => ()
  }
}

///|
pub fn RealmState::get_array_proto_values_intrinsic(
  self : RealmState,
) -> Value? {
  match self.get_array_proto() {
    Object(proto_data) =>
      proto_data.bag.symbol_properties.get(
        ARRAY_PROTO_VALUES_INTRINSIC_SYMBOL_ID,
      )
    _ => None
  }
}

///|
fn make_iterator_result_object(value : Value, done : Bool) -> Value {
  Object({
    bag: {
      properties: { "value": value, "done": Bool(done) },
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn array_iterator_kind_to_slot_value(kind : ArrayIteratorKind) -> Value {
  match kind {
    Keys => Number(0.0)
    Values => Number(1.0)
    Entries => Number(2.0)
  }
}

///|
fn array_iterator_kind_from_slot_value(value : Value) -> ArrayIteratorKind? {
  match value {
    Number(n) =>
      match n.to_int() {
        0 => Some(Keys)
        1 => Some(Values)
        2 => Some(Entries)
        _ => None
      }
    _ => None
  }
}

///|
fn array_iterator_type_error() -> Value raise Error {
  raise @errors.TypeError(
    message="Array Iterator.prototype.next requires that |this| be an Array Iterator",
  )
}

///|
fn array_iterator_result_value(
  kind : ArrayIteratorKind,
  current : Int64,
  target : Value,
  interp : Interpreter,
) -> Value raise Error {
  match kind {
    Keys => Number(current.to_double())
    Values => get_array_like_element_interp(interp, target, current)
    Entries =>
      make_array([
        Number(current.to_double()),
        get_array_like_element_interp(interp, target, current),
      ])
  }
}

///|
fn array_iterator_next(
  interp : Interpreter,
  this_val : Value,
) -> Value raise Error {
  match this_val {
    Object(data) => {
      guard data.class_name == "Array Iterator" else {
        return array_iterator_type_error()
      }
      let (current, target, kind) = match
        (
          data.bag.symbol_properties.get(ARRAY_ITERATOR_NEXT_INDEX_SYMBOL_ID),
          data.bag.symbol_properties.get(ARRAY_ITERATOR_TARGET_SYMBOL_ID),
          data.bag.symbol_properties.get(ARRAY_ITERATOR_KIND_SYMBOL_ID),
        ) {
        (Some(Number(n)), Some(target), Some(kind_value)) =>
          match array_iterator_kind_from_slot_value(kind_value) {
            Some(kind) => (n.to_int64(), target, kind)
            None => return array_iterator_type_error()
          }
        _ => return array_iterator_type_error()
      }
      if target is Undefined {
        return make_iterator_result_object(Undefined, true)
      }
      let total = to_array_like_length_interp(target, interp)
      if current >= total {
        data.bag.symbol_properties[ARRAY_ITERATOR_TARGET_SYMBOL_ID] = Undefined
        return make_iterator_result_object(Undefined, true)
      }
      data.bag.symbol_properties[ARRAY_ITERATOR_NEXT_INDEX_SYMBOL_ID] = Number(
        (current + 1L).to_double(),
      )
      let value = array_iterator_result_value(kind, current, target, interp)
      make_iterator_result_object(value, false)
    }
    _ => array_iterator_type_error()
  }
}

///|
/// Per ES spec, %IteratorPrototype% has [Symbol.iterator] that returns `this`
/// and its [[Prototype]] is %Object.prototype% (§27.1.2).
fn make_iterator_proto_value(
  well_known_symbols : WellKnownSymbols,
  realm_state : RealmState,
) -> Value {
  let iterator_sym = well_known_symbols.iterator
  let proto_sym_props : Map[Int, Value] = {}
  proto_sym_props[iterator_sym.id] = make_method_func(
    name="[Symbol.iterator]",
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) { this_val },
  )
  let proto_sym_descs : Map[Int, PropDescriptor] = {}
  proto_sym_descs[iterator_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Object({
    bag: {
      properties: {},
      symbol_properties: proto_sym_props,
      descriptors: {},
      symbol_descriptors: proto_sym_descs,
      internal_slots: {},
    },
    prototype: realm_state.get_obj_proto(),
    callable: None,
    class_name: "Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Get or create the realm-owned %IteratorPrototype%.
pub fn RealmState::get_iterator_proto(self : RealmState) -> Value {
  match self.runtime_iterator_prototypes.iterator_proto.val {
    Some(proto) => proto
    None => {
      let proto = make_iterator_proto_value(self.well_known_symbols, self)
      self.runtime_iterator_prototypes.iterator_proto.val = Some(proto)
      proto
    }
  }
}

///|
fn make_array_iterator_proto_value(
  well_known_symbols : WellKnownSymbols,
  iterator_proto : Value,
  realm_state : RealmState,
) -> Value {
  let iterator_sym = well_known_symbols.iterator
  let tostringtag_sym = well_known_symbols.to_string_tag
  let proto_sym_props : Map[Int, Value] = {}
  proto_sym_props[tostringtag_sym.id] = String_("Array Iterator")
  let proto_props : Map[String, Value] = {}
  let proto_sym_descs : Map[Int, PropDescriptor] = {}
  proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  proto_sym_descs[iterator_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  proto_sym_props[iterator_sym.id] = make_method_func(
    name="[Symbol.iterator]",
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) { this_val },
  )
  proto_props["next"] = make_interp_method_func(
    name="next",
    length=0,
    realm_state=Some(realm_state),
    fn(interp, this_val, _args) raise { array_iterator_next(interp, this_val) },
  )
  let proto_descs : Map[String, PropDescriptor] = {}
  proto_descs["next"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Object({
    bag: {
      properties: proto_props,
      symbol_properties: proto_sym_props,
      descriptors: proto_descs,
      symbol_descriptors: proto_sym_descs,
      internal_slots: {},
    },
    prototype: iterator_proto,
    callable: None,
    class_name: "Array Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Get or create the realm-owned %ArrayIteratorPrototype%.
pub fn RealmState::get_array_iterator_proto(self : RealmState) -> Value {
  match self.runtime_iterator_prototypes.array_iterator_proto.val {
    Some(proto) => proto
    None => {
      let proto = make_array_iterator_proto_value(
        self.well_known_symbols,
        self.get_iterator_proto(),
        self,
      )
      self.runtime_iterator_prototypes.array_iterator_proto.val = Some(proto)
      proto
    }
  }
}

///|
/// Create an Array Iterator object with a live target and iteration kind.
fn make_array_iterator_value_with_proto(
  arr_iter_proto : Value,
  target : Value,
  kind : ArrayIteratorKind,
) -> Value {
  let iter_sym_props : Map[Int, Value] = {}
  iter_sym_props[ARRAY_ITERATOR_NEXT_INDEX_SYMBOL_ID] = Number(0.0)
  iter_sym_props[ARRAY_ITERATOR_TARGET_SYMBOL_ID] = target
  iter_sym_props[ARRAY_ITERATOR_KIND_SYMBOL_ID] = array_iterator_kind_to_slot_value(
    kind,
  )
  let iter_sym_descs : Map[Int, PropDescriptor] = {}
  let slot_desc = array_iterator_internal_slot_descriptor()
  iter_sym_descs[ARRAY_ITERATOR_NEXT_INDEX_SYMBOL_ID] = slot_desc
  iter_sym_descs[ARRAY_ITERATOR_TARGET_SYMBOL_ID] = slot_desc
  iter_sym_descs[ARRAY_ITERATOR_KIND_SYMBOL_ID] = slot_desc

  Object({
    bag: {
      properties: {},
      symbol_properties: iter_sym_props,
      descriptors: {},
      symbol_descriptors: iter_sym_descs,
      internal_slots: {},
    },
    prototype: arr_iter_proto,
    callable: None,
    class_name: "Array Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
pub fn RealmState::make_array_iterator_value(
  self : RealmState,
  arr : ArrayData,
) -> Value {
  make_array_iterator_value_with_proto(
    self.get_array_iterator_proto(),
    Array(arr),
    Values,
  )
}

///|
fn RealmState::make_array_iterator_for_value(
  self : RealmState,
  val : Value,
  kind : ArrayIteratorKind,
) -> Value raise Error {
  match val {
    Null | Undefined =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    _ => ()
  }
  make_array_iterator_value_with_proto(
    self.get_array_iterator_proto(),
    val,
    kind,
  )
}

///|
/// Create an array-like values iterator for objects with a `length` property.
pub fn RealmState::make_array_like_iterator_value(
  self : RealmState,
  val : Value,
) -> Value raise Error {
  self.make_array_values_iterator_value(val)
}

///|
pub fn RealmState::make_array_keys_iterator_value(
  self : RealmState,
  val : Value,
) -> Value raise Error {
  self.make_array_iterator_for_value(val, Keys)
}

///|
pub fn RealmState::make_array_values_iterator_value(
  self : RealmState,
  val : Value,
) -> Value raise Error {
  self.make_array_iterator_for_value(val, Values)
}

///|
pub fn RealmState::make_array_entries_iterator_value(
  self : RealmState,
  val : Value,
) -> Value raise Error {
  self.make_array_iterator_for_value(val, Entries)
}

///|
fn string_iterator_type_error() -> Value raise Error {
  raise @errors.TypeError(
    message="String Iterator.prototype.next requires that |this| be a String Iterator",
  )
}

///|
// §22.1.5.2.1 %StringIteratorPrototype%.next()
// Reads [[StringIteratorNextIndex]] and [[IteratedString]] from receiver slots.
// Missing STRING slot → TypeError (catches %StringIteratorPrototype% itself).
fn string_iterator_next(this_val : Value) -> Value raise Error {
  guard this_val is Object(data) else { return string_iterator_type_error() }
  guard data.class_name == "String Iterator" else {
    return string_iterator_type_error()
  }
  let index = match
    data.bag.symbol_properties.get(STRING_ITERATOR_NEXT_INDEX_SYMBOL_ID) {
    Some(Number(n)) => n.to_int()
    _ => return string_iterator_type_error()
  }
  match data.bag.symbol_properties.get(STRING_ITERATOR_STRING_SYMBOL_ID) {
    None => return string_iterator_type_error()
    // §22.1.5.2.1 step 7: [[IteratedString]] is undefined → already done
    Some(Undefined) => return create_iter_result(Undefined, true)
    Some(String_(s)) => {
      let len = s.length()
      guard index < len else {
        data.bag.symbol_properties[STRING_ITERATOR_STRING_SYMBOL_ID] = Undefined
        return create_iter_result(Undefined, true)
      }
      let code = s[index].to_int()
      let next_index = if code >= 0xD800 && code <= 0xDBFF && index + 1 < len {
        let next_code = s[index + 1].to_int()
        if next_code >= 0xDC00 && next_code <= 0xDFFF {
          index + 2
        } else {
          index + 1
        }
      } else {
        index + 1
      }
      data.bag.symbol_properties[STRING_ITERATOR_NEXT_INDEX_SYMBOL_ID] = Value::Number(
        next_index.to_double(),
      )
      create_iter_result(
        String_(s.unsafe_substring(start=index, end=next_index)),
        false,
      )
    }
    _ => return string_iterator_type_error()
  }
}

///|
fn make_string_iterator_proto_value(
  well_known_symbols : WellKnownSymbols,
  iterator_proto : Value,
  realm_state : RealmState,
) -> Value {
  let iterator_sym = well_known_symbols.iterator
  let tostringtag_sym = well_known_symbols.to_string_tag
  let proto_sym_props : Map[Int, Value] = {}
  proto_sym_props[tostringtag_sym.id] = String_("String Iterator")
  let proto_props : Map[String, Value] = {}
  let proto_sym_descs : Map[Int, PropDescriptor] = {}
  proto_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  proto_sym_props[iterator_sym.id] = make_method_func(
    name="[Symbol.iterator]",
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) { this_val },
  )
  proto_props["next"] = make_method_func(
    name="next",
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) raise { string_iterator_next(this_val) },
  )
  let str_proto_descs : Map[String, PropDescriptor] = {}
  str_proto_descs["next"] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Object({
    bag: {
      properties: proto_props,
      symbol_properties: proto_sym_props,
      descriptors: str_proto_descs,
      symbol_descriptors: proto_sym_descs,
      internal_slots: {},
    },
    prototype: iterator_proto,
    callable: None,
    class_name: "String Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Get or create the realm-owned %StringIteratorPrototype%.
pub fn RealmState::get_string_iterator_proto(self : RealmState) -> Value {
  match self.runtime_iterator_prototypes.string_iterator_proto.val {
    Some(proto) => proto
    None => {
      let proto = make_string_iterator_proto_value(
        self.well_known_symbols,
        self.get_iterator_proto(),
        self,
      )
      self.runtime_iterator_prototypes.string_iterator_proto.val = Some(proto)
      proto
    }
  }
}

///|
// §22.1.5.1 CreateStringIterator: stores [[IteratedString]] and
// [[StringIteratorNextIndex]] as hidden symbol slots; next() lives on the proto.
fn make_string_iterator_value_with_proto(
  str_iter_proto : Value,
  s : String,
  _realm_state : RealmState,
) -> Value {
  let slot_desc = array_iterator_internal_slot_descriptor()
  let iter_sym_props : Map[Int, Value] = {}
  iter_sym_props[STRING_ITERATOR_NEXT_INDEX_SYMBOL_ID] = Value::Number(0.0)
  iter_sym_props[STRING_ITERATOR_STRING_SYMBOL_ID] = Value::String_(s)
  let iter_sym_descs : Map[Int, PropDescriptor] = {}
  iter_sym_descs[STRING_ITERATOR_NEXT_INDEX_SYMBOL_ID] = slot_desc
  iter_sym_descs[STRING_ITERATOR_STRING_SYMBOL_ID] = slot_desc
  Object({
    bag: {
      properties: {},
      symbol_properties: iter_sym_props,
      descriptors: {},
      symbol_descriptors: iter_sym_descs,
      internal_slots: {},
    },
    prototype: str_iter_proto,
    callable: None,
    class_name: "String Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
pub fn RealmState::make_string_iterator_value(
  self : RealmState,
  s : String,
) -> Value {
  make_string_iterator_value_with_proto(
    self.get_string_iterator_proto(),
    s,
    self,
  )
}

///|
fn make_async_iterator_proto_value(
  well_known_symbols : WellKnownSymbols,
  realm_state : RealmState,
) -> Value {
  let async_iterator_sym = well_known_symbols.async_iterator
  let async_iter_sym_props : Map[Int, Value] = {}
  async_iter_sym_props[async_iterator_sym.id] = make_method_func(
    name="[Symbol.asyncIterator]",
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) { this_val },
  )
  let async_iter_sym_descs : Map[Int, PropDescriptor] = {}
  async_iter_sym_descs[async_iterator_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Object({
    bag: {
      properties: {},
      symbol_properties: async_iter_sym_props,
      descriptors: {},
      symbol_descriptors: async_iter_sym_descs,
      internal_slots: {},
    },
    prototype: realm_state.get_obj_proto(),
    callable: None,
    class_name: "AsyncIterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Create an Async-from-Sync Iterator wrapper per ES262 §27.1.4.
/// Wraps a sync iterator record so it can be used with for-await-of.
fn create_async_from_sync_iterator(
  interp : Interpreter,
  sync_iterator : Value,
  sync_next_method : Value,
  loc : @token.Loc,
) -> Value raise Error {
  // Get the sync return and throw methods too
  let sync_return_method = interp.get_property(sync_iterator, "return", loc)
  let sync_throw_method = interp.get_property(sync_iterator, "throw", loc)
  let async_iter_sym = interp.realm_state.well_known_symbols.async_iterator
  let async_iter_proto = interp.realm_state.get_async_iterator_proto()

  // Build next method
  let async_next = make_interp_method_func(
    name="next",
    length=1,
    realm_state=Some(interp.realm_state),
    fn(ip : Interpreter, _this : Value, _args : Array[Value]) -> Value {
      let result = ip.call_value(sync_next_method, sync_iterator, [], loc)
      let promise_ctor = ip.global.get("Promise")
      let resolve_m = ip.get_property(promise_ctor, "resolve", loc)
      ip.call_value(resolve_m, promise_ctor, [result], loc)
    },
  )
  // Build return method
  let async_return = make_interp_method_func(
    name="return",
    length=1,
    realm_state=Some(interp.realm_state),
    fn(ip : Interpreter, _this : Value, args : Array[Value]) -> Value {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      match sync_return_method {
        Undefined | Null =>
          make_resolved_promise(ip, make_iterator_result_object(value, true))
        _ => {
          let result = try {
            ip.call_value(sync_return_method, sync_iterator, [value], loc)
          } catch {
            JsException(e) => return make_rejected_promise(ip, e)
          e => {
            let err_val = js_error_to_value_with_env(e, Some(ip.global))
            return make_rejected_promise(ip, err_val)
          }
          }
          if !is_object_value(result) {
            raise @errors.TypeError(message="Iterator result is not an object")
          }
          let promise_ctor = ip.global.get("Promise")
          let resolve_m = ip.get_property(promise_ctor, "resolve", loc)
          ip.call_value(resolve_m, promise_ctor, [result], loc)
        }
      }
    },
  )
  // Build throw method
  let async_throw = make_interp_method_func(
    name="throw",
    length=1,
    realm_state=Some(interp.realm_state),
    fn(ip : Interpreter, _this : Value, args : Array[Value]) -> Value {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      match sync_throw_method {
        Undefined | Null => make_rejected_promise(ip, value)
        _ => {
          let result = try {
            ip.call_value(sync_throw_method, sync_iterator, [value], loc)
          } catch {
            JsException(e) => return make_rejected_promise(ip, e)
          e => {
            let err_val = js_error_to_value_with_env(e, Some(ip.global))
            return make_rejected_promise(ip, err_val)
          }
          }
          let promise_ctor = ip.global.get("Promise")
          let resolve_m = ip.get_property(promise_ctor, "resolve", loc)
          ip.call_value(resolve_m, promise_ctor, [result], loc)
        }
      }
    },
  )

  // Async-from-Sync Iterator object
  let async_iter_sym_props_obj : Map[Int, Value] = {}
  async_iter_sym_props_obj[async_iter_sym.id] = make_method_func(
    name="[Symbol.asyncIterator]",
    length=0,
    realm_state=Some(interp.realm_state),
    fn(this_val, _args) { this_val },
  )
  let async_iter_sym_descs_obj : Map[Int, PropDescriptor] = {}
  async_iter_sym_descs_obj[async_iter_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  let obj_props : Map[String, Value] = {
    "next": async_next,
    "return": async_return,
    "throw": async_throw,
  }
  let obj_descs : Map[String, PropDescriptor] = {}
  let next_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  obj_descs["next"] = { ..next_desc }
  obj_descs["return"] = { ..next_desc }
  obj_descs["throw"] = { ..next_desc }

  Object({
    bag: {
      properties: obj_props,
      symbol_properties: async_iter_sym_props_obj,
      descriptors: obj_descs,
      symbol_descriptors: async_iter_sym_descs_obj,
      internal_slots: {},
    },
    prototype: async_iter_proto,
    callable: None,
    class_name: "Async-from-Sync Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn make_resolved_promise(_interp : Interpreter, value : Value) -> Value {
  let promise_data = new_promise_data()
  promise_data.state = Fulfilled
  promise_data.result = value
  Promise(promise_data)
}

///|
fn make_rejected_promise(_interp : Interpreter, value : Value) -> Value {
  let promise_data = new_promise_data()
  promise_data.state = Rejected
  promise_data.result = value
  Promise(promise_data)
}

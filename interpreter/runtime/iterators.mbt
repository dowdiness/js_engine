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
fn make_iterator_result_object_with_proto(
  value : Value,
  done : Bool,
  proto : Value,
) -> Value {
  Object({
    bag: {
      properties: { "value": value, "done": Bool(done) },
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: proto,
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
/// Apply AsyncFromSyncIteratorContinuation (§27.1.4.1.1):
/// Promise.resolve(value).then(v => CreateIterResultObject(v, done)).
/// Errors propagate to the caller's catch handler (returns rejected promise).
fn chain_value_through_continuation(
  ip : Interpreter,
  value : Value,
  done : Bool,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let promise_ctor = ip.global.get("Promise")
  let resolve_m = ip.get_property(promise_ctor, "resolve", loc)
  let resolved = ip.call_value(resolve_m, promise_ctor, [value], loc)
  let on_fulfill = make_interp_method_func(
    name="",
    length=1,
    realm_state=Some(ip.realm_state),
    fn(i : Interpreter, _this : Value, args : Array[Value]) -> Value {
      let v = if args.length() > 0 { args[0] } else { Undefined }
      make_iterator_result_object_with_proto(
        v,
        done,
        i.realm_state.get_obj_proto(),
      )
    },
  )
  let then_m = ip.get_property(resolved, "then", loc)
  ip.call_value(then_m, resolved, [on_fulfill], loc)
}

///|
fn extract_iterator_done(
  ip : Interpreter,
  result : Value,
  loc : @token.Loc,
) -> Bool raise Error {
  let done_val = ip.get_property(result, "done", loc)
  is_truthy(done_val)
}

///|
fn extract_iterator_value(
  ip : Interpreter,
  result : Value,
  loc : @token.Loc,
) -> Value raise Error {
  ip.get_property(result, "value", loc)
}

///|
/// Helper: wrap a raise-bound operation with promise-based error handling.
/// Catches any raise and returns a rejected promise instead.
fn reject_on_error(ip : Interpreter, action : () -> Value raise Error) -> Value {
  action() catch {
    JsException(e) => make_rejected_promise(ip, e)
    e => {
      let err = js_error_to_value_with_env(e, Some(ip.global))
      make_rejected_promise(ip, err)
    }
  }
}

///|
/// %AsyncFromSyncIteratorPrototype%.next ( value )
fn async_from_sync_next(
  ip : Interpreter,
  this_val : Value,
  _args : Array[Value],
) -> Value {
  reject_on_error(ip, fn() -> Value raise Error {
    let data = match this_val {
      Object(d) => d
      _ =>
        raise @errors.TypeError(
          message="%AsyncFromSyncIteratorPrototype%.next called on incompatible receiver",
        )
    }
    let sync_iterator = match get_sync_iterator(data) {
      Some(v) => v
      None => raise @errors.TypeError(message="SyncIterator slot missing")
    }
    let sync_next = match get_sync_next_method(data) {
      Some(v) => v
      None => raise @errors.TypeError(message="SyncNextMethod slot missing")
    }
    let loc = @token.Loc::default()
    let result = ip.call_value(sync_next, sync_iterator, [], loc)
    let done = extract_iterator_done(ip, result, loc)
    let value = extract_iterator_value(ip, result, loc)
    chain_value_through_continuation(ip, value, done)
  })
}

///|
/// %AsyncFromSyncIteratorPrototype%.return ( value )
fn async_from_sync_return(
  ip : Interpreter,
  this_val : Value,
  args : Array[Value],
) -> Value {
  let arg = if args.length() > 0 { args[0] } else { Undefined }
  reject_on_error(ip, fn() -> Value raise Error {
    let data = match this_val {
      Object(d) => d
      _ =>
        raise @errors.TypeError(
          message="%AsyncFromSyncIteratorPrototype%.return called on incompatible receiver",
        )
    }
    let sync_iterator = match get_sync_iterator(data) {
      Some(v) => v
      None => raise @errors.TypeError(message="SyncIterator slot missing")
    }
    let loc = @token.Loc::default()
    let return_method = ip.get_property(sync_iterator, "return", loc)
    match return_method {
      Undefined | Null => {
        let obj_proto = ip.realm_state.get_obj_proto()
        let result = make_iterator_result_object_with_proto(
          arg, true, obj_proto,
        )
        make_resolved_promise(ip, result)
      }
      _ => {
        let call_result = ip.call_value(
          return_method,
          sync_iterator,
          [arg],
          loc,
        )
        guard is_object_value(call_result) else {
          raise @errors.TypeError(message="Iterator result is not an object")
        }
        let done = extract_iterator_done(ip, call_result, loc)
        let value = extract_iterator_value(ip, call_result, loc)
        chain_value_through_continuation(ip, value, done)
      }
    }
  })
}

///|
/// %AsyncFromSyncIteratorPrototype%.throw ( value )
fn async_from_sync_throw(
  ip : Interpreter,
  this_val : Value,
  args : Array[Value],
) -> Value {
  let arg = if args.length() > 0 { args[0] } else { Undefined }
  reject_on_error(ip, fn() -> Value raise Error {
    let data = match this_val {
      Object(d) => d
      _ =>
        raise @errors.TypeError(
          message="%AsyncFromSyncIteratorPrototype%.throw called on incompatible receiver",
        )
    }
    let sync_iterator = match get_sync_iterator(data) {
      Some(v) => v
      None => raise @errors.TypeError(message="SyncIterator slot missing")
    }
    let loc = @token.Loc::default()
    let throw_method = ip.get_property(sync_iterator, "throw", loc)
    match throw_method {
      Undefined | Null => make_rejected_promise(ip, arg)
      _ => {
        let call_result = ip.call_value(throw_method, sync_iterator, [arg], loc)
        guard is_object_value(call_result) else {
          raise @errors.TypeError(message="Iterator result is not an object")
        }
        let done = extract_iterator_done(ip, call_result, loc)
        let value = extract_iterator_value(ip, call_result, loc)
        chain_value_through_continuation(ip, value, done)
      }
    }
  })
}

///|
fn make_async_from_sync_iterator_proto_value(
  well_known_symbols : WellKnownSymbols,
  realm_state : RealmState,
) -> Value {
  let tostringtag_sym = well_known_symbols.to_string_tag
  let async_iterator_sym = well_known_symbols.async_iterator
  let proto_props : Map[String, Value] = {}
  let proto_descs : Map[String, PropDescriptor] = {}
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  proto_props["next"] = make_interp_method_func(
    name="next",
    length=1,
    realm_state=Some(realm_state),
    fn(ip : Interpreter, this_val : Value, args : Array[Value]) -> Value {
      async_from_sync_next(ip, this_val, args)
    },
  )
  proto_descs["next"] = { ..method_desc }
  proto_props["return"] = make_interp_method_func(
    name="return",
    length=1,
    realm_state=Some(realm_state),
    fn(ip : Interpreter, this_val : Value, args : Array[Value]) -> Value {
      async_from_sync_return(ip, this_val, args)
    },
  )
  proto_descs["return"] = { ..method_desc }
  proto_props["throw"] = make_interp_method_func(
    name="throw",
    length=1,
    realm_state=Some(realm_state),
    fn(ip : Interpreter, this_val : Value, args : Array[Value]) -> Value {
      async_from_sync_throw(ip, this_val, args)
    },
  )
  proto_descs["throw"] = { ..method_desc }
  let sym_props : Map[Int, Value] = {}
  let sym_descs : Map[Int, PropDescriptor] = {}
  sym_props[async_iterator_sym.id] = make_method_func(
    name="[Symbol.asyncIterator]",
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) { this_val },
  )
  sym_descs[async_iterator_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  sym_props[tostringtag_sym.id] = String_("Async-from-Sync Iterator")
  sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  Object({
    bag: {
      properties: proto_props,
      symbol_properties: sym_props,
      descriptors: proto_descs,
      symbol_descriptors: sym_descs,
      internal_slots: {},
    },
    prototype: realm_state.get_async_iterator_proto(),
    callable: None,
    class_name: "Async-from-Sync Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
/// Create an Async-from-Sync Iterator wrapper per ES262 §27.1.4.
/// Wraps a sync iterator record so it can be used with for-await-of.
/// The instance inherits next/return/throw from %AsyncFromSyncIteratorPrototype%
/// and stores sync iterator data in internal slots.
fn create_async_from_sync_iterator(
  interp : Interpreter,
  sync_iterator : Value,
  sync_next_method : Value,
  _loc : @token.Loc,
) -> Value {
  let async_iter_sym = interp.realm_state.well_known_symbols.async_iterator
  let async_sym_props : Map[Int, Value] = {}
  let async_sym_descs : Map[Int, PropDescriptor] = {}
  async_sym_props[async_iter_sym.id] = make_method_func(
    name="[Symbol.asyncIterator]",
    length=0,
    realm_state=Some(interp.realm_state),
    fn(this_val, _args) { this_val },
  )
  async_sym_descs[async_iter_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let internal_slots : Map[InternalSlotKey, Value] = {}
  internal_slots[SyncIterator] = sync_iterator
  internal_slots[SyncNextMethod] = sync_next_method
  let async_from_sync_proto = interp.realm_state.get_async_from_sync_iterator_proto()
  Object({
    bag: {
      properties: {},
      symbol_properties: async_sym_props,
      descriptors: {},
      symbol_descriptors: async_sym_descs,
      internal_slots,
    },
    prototype: async_from_sync_proto,
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

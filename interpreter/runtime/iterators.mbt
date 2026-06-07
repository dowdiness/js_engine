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
  current : Int,
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
            Some(kind) => (n.to_int(), target, kind)
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
        (current + 1).to_double(),
      )
      let value = array_iterator_result_value(kind, current, target, interp)
      make_iterator_result_object(value, false)
    }
    _ => array_iterator_type_error()
  }
}

///|
/// Per ES spec, %IteratorPrototype% has [Symbol.iterator] that returns `this`
/// and its [[Prototype]] is %Object.prototype% (Null for now since we don't
/// thread Object.prototype here — iterators still function correctly).
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
    },
    prototype: Null,
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
    fn(_this_val, _args) raise {
      raise @errors.TypeError(
        message="String Iterator.prototype.next requires that |this| be a String Iterator",
      )
    },
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
/// Create a string iterator object that iterates over string characters
/// Handles Unicode surrogate pairs correctly per ES6 spec
fn make_string_iterator_value_with_proto(
  str_iter_proto : Value,
  s : String,
  realm_state : RealmState,
) -> Value {
  let chars = s.to_array()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    bag: {
      properties: { "length": Number(0.0), "name": String_("next") },
      symbol_properties: {},
      descriptors: {
        "length": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        },
        "name": {
          writable: false,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        },
      },
      symbol_descriptors: {},
    },
    prototype: Null,
    callable: Some(
      NativeCallable("next", fn(_args) {
        let idx = index_ref.val
        if idx < chars.length() {
          let buf = StringBuilder::new()
          let c = chars[idx]
          let code = c.to_int()

          // Check if this is a high surrogate (0xD800-0xDBFF)
          // and the next char is a low surrogate (0xDC00-0xDFFF)
          if code >= 0xD800 && code <= 0xDBFF && idx + 1 < chars.length() {
            let next_code = chars[idx + 1].to_int()
            if next_code >= 0xDC00 && next_code <= 0xDFFF {
              // This is a surrogate pair - yield both together
              buf.write_char(c)
              buf.write_char(chars[idx + 1])
              index_ref.val = idx + 2
            } else {
              // High surrogate without valid low surrogate - yield as-is
              buf.write_char(c)
              index_ref.val = idx + 1
            }
          } else {
            // Regular character or lone surrogate
            buf.write_char(c)
            index_ref.val = idx + 1
          }
          let value = String_(buf.to_string())
          let result_props : Map[String, Value] = {}
          result_props["value"] = value
          result_props["done"] = Bool(false)
          Object({
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
          result_props["done"] = Bool(true)
          Object({
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
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = stamp_function_realm(
    next_method,
    realm_state=Some(realm_state),
  )
  Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
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

///|
/// Per ES spec, %IteratorPrototype% has [Symbol.iterator] that returns `this`
/// and its [[Prototype]] is %Object.prototype% (Null for now since we don't
/// thread Object.prototype here — iterators still function correctly).
fn make_iterator_proto_value(well_known_symbols : WellKnownSymbols) -> Value {
  let iterator_sym = well_known_symbols.iterator
  let proto_sym_props : Map[Int, Value] = {}
  proto_sym_props[iterator_sym.id] = make_method_func(
    name="[Symbol.iterator]",
    length=0,
    fn(this_val, _args) { this_val },
  )
  Object({
    bag: {
      properties: {},
      symbol_properties: proto_sym_props,
      descriptors: {},
      symbol_descriptors: {},
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
      let proto = make_iterator_proto_value(self.well_known_symbols)
      self.runtime_iterator_prototypes.iterator_proto.val = Some(proto)
      proto
    }
  }
}

///|
fn make_array_iterator_proto_value(
  well_known_symbols : WellKnownSymbols,
  iterator_proto : Value,
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
  proto_sym_props[iterator_sym.id] = make_method_func(
    name="[Symbol.iterator]",
    length=0,
    fn(this_val, _args) { this_val },
  )
  proto_props["next"] = make_method_func(name="next", length=0, fn(
    _this_val,
    _args,
  ) raise {
    raise @errors.TypeError(
      message="Array Iterator.prototype.next requires that |this| be an Array Iterator",
    )
  })
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
      )
      self.runtime_iterator_prototypes.array_iterator_proto.val = Some(proto)
      proto
    }
  }
}

///|
/// Create an array iterator object that iterates over array elements
fn make_array_iterator_value_with_proto(
  arr_iter_proto : Value,
  arr : ArrayData,
) -> Value {
  let index_ref : Ref[Int] = { val: 0 }

  // Create the next method
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
        if idx < arr.elements.length() {
          let value = arr.elements[idx]
          index_ref.val = idx + 1
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

  // Create the iterator object with next method
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method

  Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
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
  make_array_iterator_value_with_proto(self.get_array_iterator_proto(), arr)
}

///|
/// Create an array-like iterator for non-array objects with a `length` property.
/// Uses `get_array_like_element` / `to_array_like_length` to read indexed values.
fn make_array_like_iterator_value_with_proto(
  arr_iter_proto : Value,
  val : Value,
) -> Value raise Error {
  let index_ref : Ref[Int] = { val: 0 }
  let len = to_array_like_length(val)

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
        if idx < len {
          let value = get_array_like_element(val, idx)
          index_ref.val = idx + 1
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
  iter_props["next"] = next_method

  Object({
    bag: {
      properties: iter_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: arr_iter_proto,
    callable: None,
    class_name: "Array Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
pub fn RealmState::make_array_like_iterator_value(
  self : RealmState,
  val : Value,
) -> Value raise Error {
  make_array_like_iterator_value_with_proto(
    self.get_array_iterator_proto(),
    val,
  )
}

///|
fn make_string_iterator_proto_value(
  well_known_symbols : WellKnownSymbols,
  iterator_proto : Value,
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
    fn(this_val, _args) { this_val },
  )
  proto_props["next"] = make_method_func(name="next", length=0, fn(
    _this_val,
    _args,
  ) raise {
    raise @errors.TypeError(
      message="String Iterator.prototype.next requires that |this| be a String Iterator",
    )
  })
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
  iter_props["next"] = next_method
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
  make_string_iterator_value_with_proto(self.get_string_iterator_proto(), s)
}

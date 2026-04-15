///|
/// Shared %IteratorPrototype% - lazily initialized (ES spec §27.1.2)
let iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %IteratorPrototype%
/// Per ES spec, %IteratorPrototype% has [Symbol.iterator] that returns `this`
/// and its [[Prototype]] is %Object.prototype% (Null for now since we don't
/// thread Object.prototype here — iterators still function correctly).
pub fn get_iterator_proto() -> Value {
  match iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = get_iterator_symbol()
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[iterator_sym.id] = make_method_func(
        "[Symbol.iterator]",
        0,
        fn(this_val, _args) { this_val },
      )
      let proto : Value = Object({
        properties: {},
        symbol_properties: proto_sym_props,
        prototype: Null,
        callable: None,
        class_name: "Iterator",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
      iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Shared %ArrayIteratorPrototype% - lazily initialized
let array_iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %ArrayIteratorPrototype%
pub fn get_array_iterator_proto() -> Value {
  match array_iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = get_iterator_symbol()
      let tostringtag_sym = get_tostringtag_symbol()
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
      }
      proto_sym_props[iterator_sym.id] = make_method_func(
        "[Symbol.iterator]",
        0,
        fn(this_val, _args) { this_val },
      )
      proto_props["next"] = make_method_func("next", 0, fn(
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
      }
      let proto = Object({
        properties: proto_props,
        symbol_properties: proto_sym_props,
        prototype: get_iterator_proto(),
        callable: None,
        class_name: "Array Iterator",
        descriptors: proto_descs,
        symbol_descriptors: proto_sym_descs,
        extensible: true,
      })
      array_iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Create an array iterator object that iterates over array elements
pub fn make_array_iterator_value(arr : ArrayData) -> Value {
  let arr_iter_proto = get_array_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }

  // Create the next method
  let next_method = Object({
    properties: { "length": Number(0.0), "name": String_("next") },
    symbol_properties: {},
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
      }),
    ),
    class_name: "Function",
    descriptors: {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "name": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
    },
    symbol_descriptors: {},
    extensible: true,
  })

  // Create the iterator object with next method
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method

  Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: arr_iter_proto,
    callable: None,
    class_name: "Array Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Create an array-like iterator for non-array objects with a `length` property.
/// Uses `get_array_like_element` / `to_array_like_length` to read indexed values.
pub fn make_array_like_iterator_value(val : Value) -> Value raise Error {
  let arr_iter_proto = get_array_iterator_proto()
  let index_ref : Ref[Int] = { val: 0 }
  let len = to_array_like_length(val)

  let next_method = Object({
    properties: { "length": Number(0.0), "name": String_("next") },
    symbol_properties: {},
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
      }),
    ),
    class_name: "Function",
    descriptors: {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "name": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
    },
    symbol_descriptors: {},
    extensible: true,
  })

  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method

  Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: arr_iter_proto,
    callable: None,
    class_name: "Array Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Shared %StringIteratorPrototype% - lazily initialized
let string_iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %StringIteratorPrototype%
pub fn get_string_iterator_proto() -> Value {
  match string_iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = get_iterator_symbol()
      let tostringtag_sym = get_tostringtag_symbol()
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
      }
      proto_sym_props[iterator_sym.id] = make_method_func(
        "[Symbol.iterator]",
        0,
        fn(this_val, _args) { this_val },
      )
      proto_props["next"] = make_method_func("next", 0, fn(
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
      }
      let proto = Object({
        properties: proto_props,
        symbol_properties: proto_sym_props,
        prototype: get_iterator_proto(),
        callable: None,
        class_name: "String Iterator",
        descriptors: str_proto_descs,
        symbol_descriptors: proto_sym_descs,
        extensible: true,
      })
      string_iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

///|
/// Create a string iterator object that iterates over string characters
/// Handles Unicode surrogate pairs correctly per ES6 spec
pub fn make_string_iterator_value(s : String) -> Value {
  let str_iter_proto = get_string_iterator_proto()
  let chars = s.to_array()
  let index_ref : Ref[Int] = { val: 0 }
  let next_method = Object({
    properties: { "length": Number(0.0), "name": String_("next") },
    symbol_properties: {},
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
      }),
    ),
    class_name: "Function",
    descriptors: {
      "length": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
      "name": {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      },
    },
    symbol_descriptors: {},
    extensible: true,
  })
  let iter_props : Map[String, Value] = {}
  iter_props["next"] = next_method
  Object({
    properties: iter_props,
    symbol_properties: {},
    prototype: str_iter_proto,
    callable: None,
    class_name: "String Iterator",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

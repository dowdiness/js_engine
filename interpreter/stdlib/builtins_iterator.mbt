///|
/// Set up iterator protocol on Array and String prototypes
fn setup_iterator_protocol(env : Environment) -> Unit raise Error {
  let iterator_sym = @runtime.get_iterator_symbol()

  // Get Array constructor and add Symbol.iterator to its prototype
  let array_val = env.get("Array")
  match array_val {
    Object(array_ctor) =>
      match array_ctor.properties.get("prototype") {
        Some(Object(proto_data)) => {
          // Add [Symbol.iterator] method that returns an array iterator
          proto_data.symbol_properties[iterator_sym.id] = @runtime.make_method_func(
            "[Symbol.iterator]",
            0,
            fn(this_val, _args) raise {
              match this_val {
                Value::Array(arr) => @runtime.make_array_iterator_value(arr)
                _ => @runtime.make_array_like_iterator_value(this_val)
              }
            },
          )

          // Also add values() method (alias for [Symbol.iterator])
          proto_data.properties["values"] = @runtime.make_method_func(
            "values",
            0,
            fn(this_val, _args) raise {
              match this_val {
                Value::Array(arr) => @runtime.make_array_iterator_value(arr)
                _ => @runtime.make_array_like_iterator_value(this_val)
              }
            },
          )

          // Add keys() method that returns an iterator over indices
          proto_data.properties["keys"] = @runtime.make_method_func("keys", 0, fn(
            this_val,
            _args,
          ) raise {
            let len = @runtime.to_array_like_length(this_val)
            let index_ref : Ref[Int] = { val: 0 }
            let next_method = Value::Object({
              properties: {},
              symbol_properties: {},
              prototype: Null,
              callable: Some(
                NativeCallable("next", fn(_args) {
                  let idx = index_ref.val
                  if idx < len {
                    index_ref.val = idx + 1
                    let result_props : Map[String, Value] = {}
                    result_props["value"] = Value::Number(idx.to_double())
                    result_props["done"] = Value::Bool(false)
                    Value::Object({
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
                    result_props["done"] = Value::Bool(true)
                    Value::Object({
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
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })
            let iter_props : Map[String, Value] = {}
            iter_props["next"] = next_method
            let iter_obj = Value::Object({
              properties: iter_props,
              symbol_properties: {},
              prototype: Null,
              callable: None,
              class_name: "Array Iterator",
              descriptors: {},
              symbol_descriptors: {},
              extensible: true,
            })

            // Add [Symbol.iterator] to keys iterator
            match iter_obj {
              Object(data) =>
                data.symbol_properties[iterator_sym.id] = @runtime.make_method_func(
                  "[Symbol.iterator]",
                  0,
                  fn(this_val, _args) { this_val },
                )
              _ => ()
            }
            iter_obj
          })

          // Add entries() method that returns an iterator over [index, value] pairs
          proto_data.properties["entries"] = @runtime.make_method_func(
            "entries",
            0,
            fn(this_val, _args) raise {
              let the_val = this_val
              let len = @runtime.to_array_like_length(the_val)
              let index_ref : Ref[Int] = { val: 0 }
              let next_method = Value::Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  NativeCallable("next", fn(_args) {
                    let idx = index_ref.val
                    if idx < len {
                      let value = @runtime.get_array_like_element(the_val, idx)
                      index_ref.val = idx + 1
                      let result_props : Map[String, Value] = {}
                      result_props["value"] = Value::Array({
                        elements: [Value::Number(idx.to_double()), value],
                      })
                      result_props["done"] = Value::Bool(false)
                      Value::Object({
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
                      result_props["done"] = Value::Bool(true)
                      Value::Object({
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
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              let iter_props : Map[String, Value] = {}
              iter_props["next"] = next_method
              let iter_obj = Value::Object({
                properties: iter_props,
                symbol_properties: {},
                prototype: Null,
                callable: None,
                class_name: "Array Iterator",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })

              // Add [Symbol.iterator] to entries iterator
              match iter_obj {
                Object(data) =>
                  data.symbol_properties[iterator_sym.id] = @runtime.make_method_func(
                    "[Symbol.iterator]",
                    0,
                    fn(this_val, _args) { this_val },
                  )
                _ => ()
              }
              iter_obj
            },
          )
          // Add @@unscopables to Array.prototype
          let unscopables_sym_data = match env.get("Symbol") {
            Object(s) =>
              match s.properties.get("unscopables") {
                Some(Value::Symbol(sym)) => Some(sym)
                _ => None
              }
            _ => None
          }
          match unscopables_sym_data {
            Some(unscopables_sym2) => {
              let unscopable_props : Map[String, Value] = {}
              unscopable_props["at"] = Value::Bool(true)
              unscopable_props["copyWithin"] = Value::Bool(true)
              unscopable_props["entries"] = Value::Bool(true)
              unscopable_props["fill"] = Value::Bool(true)
              unscopable_props["find"] = Value::Bool(true)
              unscopable_props["findIndex"] = Value::Bool(true)
              unscopable_props["findLast"] = Value::Bool(true)
              unscopable_props["findLastIndex"] = Value::Bool(true)
              unscopable_props["flat"] = Value::Bool(true)
              unscopable_props["flatMap"] = Value::Bool(true)
              unscopable_props["includes"] = Value::Bool(true)
              unscopable_props["keys"] = Value::Bool(true)
              unscopable_props["toReversed"] = Value::Bool(true)
              unscopable_props["toSorted"] = Value::Bool(true)
              unscopable_props["toSpliced"] = Value::Bool(true)
              unscopable_props["values"] = Value::Bool(true)
              proto_data.symbol_properties[unscopables_sym2.id] = Value::Object({
                  properties: unscopable_props,
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                },
              )
              proto_data.symbol_descriptors[unscopables_sym2.id] = {
                writable: false,
                enumerable: false,
                configurable: true,
                getter: None,
                setter: None,
              }
            }
            None => ()
          }
        }
        _ => ()
      }
    _ => ()
  }

  // Add [Symbol.iterator] for String prototype
  let string_proto = env.get("[[StringPrototype]]")
  match string_proto {
    Object(proto_data) => {
      let iter_method = @runtime.make_method_func("[Symbol.iterator]", 0, fn(
        this_val,
        _args,
      ) {
        let s = this_val.to_string()
        @runtime.make_string_iterator_value(s)
      })
      proto_data.symbol_properties[iterator_sym.id] = iter_method
      let iter_method_desc : PropDescriptor = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      proto_data.symbol_descriptors[iterator_sym.id] = iter_method_desc
    }
    _ => ()
  }
}

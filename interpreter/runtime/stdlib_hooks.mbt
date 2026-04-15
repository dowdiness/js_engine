///|
/// Function pointer table for calling from runtime into stdlib.
/// This breaks the circular dependency: runtime defines the interface,
/// stdlib provides the implementation, root interpreter wires them together.
pub(all) struct StdlibHooks {
  get_string_method : (String, String, Bool) -> Value
  get_number_method : (Value, String) -> Value
  get_array_method_with_interp : (ArrayData, String) -> Value
  get_map_method : (MapData, String) -> Value
  get_set_method : (SetData, String) -> Value
  get_promise_method : (PromiseData, String) -> Value
  make_regexp_object : (String, String) -> Value raise Error
  typedarray_get_index : (ObjectData, Int) -> Value
  typedarray_set_index : (ObjectData, Int, Double) -> Unit
}

///|
/// Default no-op hooks used before stdlib is wired in.
pub fn default_stdlib_hooks() -> StdlibHooks {
  {
    get_string_method: fn(_s, _prop, _annex_b) { Undefined },
    get_number_method: fn(_obj, _prop) { Undefined },
    get_array_method_with_interp: fn(_data, _prop) { Undefined },
    get_map_method: fn(_data, _prop) { Undefined },
    get_set_method: fn(_data, _prop) { Undefined },
    get_promise_method: fn(_data, _prop) { Undefined },
    make_regexp_object: fn(_pattern, _flags) { Undefined },
    typedarray_get_index: fn(_data, _idx) { Undefined },
    typedarray_set_index: fn(_data, _idx, _val) { () },
  }
}

///|
pub fn get_typedarray_viewed_buffer(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ViewedArrayBuffer]]")
}

///|
pub fn get_typedarray_array_length(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayLength]]")
}

///|
pub fn get_typedarray_byte_length(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ByteLength]]")
}

///|
pub fn get_typedarray_byte_offset(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ByteOffset]]")
}

///|
pub fn get_typedarray_buffer_id(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayBufferID]]")
}

///|
pub fn get_arraybuffer_byte_length(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayBufferByteLength]]")
}

///|
pub fn get_arraybuffer_id(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayBufferID]]")
}

///|
pub fn get_boolean_data(data : ObjectData) -> Value? {
  data.bag.properties.get("[[BooleanData]]")
}

///|
pub fn get_map_iterator_target(data : ObjectData, sym_id : Int) -> Value? {
  data.bag.symbol_properties.get(sym_id)
}

///|
pub fn get_map_iterator_next_index(data : ObjectData, sym_id : Int) -> Value? {
  data.bag.symbol_properties.get(sym_id)
}

///|
pub fn get_map_iterator_kind(data : ObjectData, sym_id : Int) -> Value? {
  data.bag.symbol_properties.get(sym_id)
}

///|
pub fn set_map_iterator_next_index(
  data : ObjectData,
  sym_id : Int,
  value : Value,
) -> Unit {
  data.bag.symbol_properties[sym_id] = value
}

///|
pub fn detach_map_iterator_target(data : ObjectData, sym_id : Int) -> Unit {
  data.bag.symbol_properties[sym_id] = Undefined
}

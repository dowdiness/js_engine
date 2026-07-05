///|
pub fn get_typedarray_viewed_buffer(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(ViewedArrayBuffer)
}

///|
pub fn get_typedarray_array_length(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(ArrayLength)
}

///|
pub fn get_typedarray_byte_length(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(ByteLength)
}

///|
pub fn get_typedarray_byte_offset(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(ByteOffset)
}

///|
pub fn get_typedarray_buffer_id(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(ArrayBufferID)
}

///|
pub fn get_arraybuffer_byte_length(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(ArrayBufferByteLength)
}

///|
pub fn get_arraybuffer_id(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(ArrayBufferID)
}

///|
pub fn get_boolean_data(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(BooleanData)
}

///|
pub fn get_symbol_data(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(SymbolData)
}

///|
pub fn get_source_text(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(SourceText)
}

///|
pub fn get_sync_iterator(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(SyncIterator)
}

///|
pub fn get_sync_next_method(data : ObjectData) -> Value? {
  data.bag.internal_slots.get(SyncNextMethod)
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

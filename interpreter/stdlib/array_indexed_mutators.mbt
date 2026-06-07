///|
fn array_mutator_set_index(
  interp : Interpreter,
  o : Value,
  index : Int,
  value : Value,
) -> Unit raise Error {
  array_mutator_set_property_key(interp, o, index.to_string(), value)
}

///|
fn array_mutator_delete_index(
  interp : Interpreter,
  o : Value,
  index : Int,
) -> Unit raise Error {
  array_mutator_delete_property_key(interp, o, index.to_string())
}

///|
fn array_mutator_has_index(
  interp : Interpreter,
  o : Value,
  index : Int,
) -> Bool raise Error {
  interp.has_property(o, index.to_string())
}

///|
fn array_mutator_set_length(
  interp : Interpreter,
  o : Value,
  len : Int,
) -> Unit raise Error {
  array_mutator_set_length_number(interp, o, len.to_double())
}

///|
const ARRAY_MAX_SAFE_LENGTH : Double = 9007199254740991.0

///|
fn array_mutator_array_index64_from_key(key : String) -> Int64? {
  let idx = @string.parse_int(key) catch { _ => -1 }
  if idx >= 0 && idx.to_int64() <= 4294967294L && idx.to_string() == key {
    return Some(idx.to_int64())
  }
  try {
    let n = @string.parse_double(key)
    let i64 = n.to_int64()
    if n >= 2147483648.0 &&
      n == i64.to_double() &&
      i64 <= 4294967294L &&
      i64.to_string() == key {
      Some(i64)
    } else {
      None
    }
  } catch {
    _ => None
  }
}

///|
fn array_mutator_push_indexed_entry_if_absent(
  entries : Array[(Int64, String, Value)],
  idx64 : Int64,
  key : String,
  value : Value,
) -> Unit {
  if !array_mutator_entries_contain_index(entries, idx64) {
    entries.push((idx64, key, value))
  }
}

///|
fn array_mutator_append_indexed_bag_properties(
  entries : Array[(Int64, String, Value)],
  bag : @runtime.PropertyBag,
  len64 : Int64,
) -> Unit {
  bag.properties.each(fn(key, value) {
    match array_mutator_array_index64_from_key(key) {
      Some(idx64) if idx64 < len64 =>
        array_mutator_push_indexed_entry_if_absent(entries, idx64, key, value)
      _ => ()
    }
  })
  bag.descriptors.each(fn(key, _) {
    match array_mutator_array_index64_from_key(key) {
      Some(idx64) if idx64 < len64 =>
        array_mutator_push_indexed_entry_if_absent(
          entries,
          idx64,
          key,
          Undefined,
        )
      _ => ()
    }
  })
}

///|
fn array_mutator_append_dense_indexed_properties(
  entries : Array[(Int64, String, Value)],
  data : ArrayData,
  len64 : Int64,
) -> Unit {
  for i = 0; i < data.elements.length(); i = i + 1 {
    if !data.holes.contains(i) {
      let idx64 = i.to_int64()
      if idx64 < len64 {
        array_mutator_push_indexed_entry_if_absent(
          entries,
          idx64,
          i.to_string(),
          data.elements[i],
        )
      }
    }
  }
}

///|
fn array_mutator_entries_contain_index(
  entries : Array[(Int64, String, Value)],
  idx64 : Int64,
) -> Bool {
  for entry in entries {
    if entry.0 == idx64 {
      return true
    }
  }
  false
}

///|
fn array_mutator_compare_entry_index_ascending(
  a : (Int64, String, Value),
  b : (Int64, String, Value),
) -> Int {
  if a.0 < b.0 {
    -1
  } else if a.0 > b.0 {
    1
  } else {
    0
  }
}

///|
fn array_mutator_compare_entry_index_descending(
  a : (Int64, String, Value),
  b : (Int64, String, Value),
) -> Int {
  -array_mutator_compare_entry_index_ascending(a, b)
}

///|
fn array_mutator_set_property_key(
  interp : Interpreter,
  o : Value,
  key : String,
  value : Value,
) -> Unit raise Error {
  let _ = interp.set_property(o, key, value, @token.Loc::default(), strict=true)
}

///|
fn array_mutator_delete_property_key(
  interp : Interpreter,
  o : Value,
  key : String,
) -> Unit raise Error {
  let _ = @runtime.eval_delete_property(interp, o, key, true)
}

///|
fn array_mutator_set_length_number(
  interp : Interpreter,
  o : Value,
  len : Double,
) -> Unit raise Error {
  let _ = interp.set_property(
    o,
    "length",
    Value::Number(len),
    @token.Loc::default(),
    strict=true,
  )
}

///|
fn array_mutator_length_number(
  interp : Interpreter,
  o : Value,
) -> Double raise Error {
  match o {
    Array(arr) =>
      match @runtime.get_array_length_override(arr) {
        Some(n64) => n64.to_double()
        None => arr.elements.length().to_double()
      }
    _ => {
      let len_val = interp.get_property(o, "length", @token.Loc::default())
      let n = interp.to_number(len_val)
      if n.is_nan() || n <= 0.0 {
        0.0
      } else if n.is_inf() || n >= ARRAY_MAX_SAFE_LENGTH {
        ARRAY_MAX_SAFE_LENGTH
      } else {
        @math.floor(n)
      }
    }
  }
}

///|
fn array_push_indexed_properties(
  interp : Interpreter,
  o : Value,
  args : Array[Value],
) -> Value raise Error {
  let mut len = array_mutator_length_number(interp, o)
  if len + args.length().to_double() > ARRAY_MAX_SAFE_LENGTH {
    raise @errors.TypeError(message="Invalid array length")
  }
  for arg in args {
    array_mutator_set_property_key(interp, o, len.to_string(), arg)
    len = len + 1.0
  }
  array_mutator_set_length_number(interp, o, len)
  Value::Number(len)
}

///|
fn array_pop_indexed_properties(
  interp : Interpreter,
  o : Value,
) -> Value raise Error {
  let len = array_mutator_length_number(interp, o)
  if len == 0.0 {
    array_mutator_set_length_number(interp, o, 0.0)
    return Undefined
  }
  let new_len = len - 1.0
  let key = new_len.to_string()
  let element = interp.get_property(o, key, @token.Loc::default())
  array_mutator_delete_property_key(interp, o, key)
  array_mutator_set_length_number(interp, o, new_len)
  element
}

///|
fn array_mutator_relative_index(index : Int, len : Int) -> Int {
  if index < 0 {
    let from_end = len + index
    if from_end < 0 {
      0
    } else {
      from_end
    }
  } else if index > len {
    len
  } else {
    index
  }
}

///|
fn array_direct_reverse(arr : ArrayData) -> Value {
  let len = arr.elements.length()
  let mut lower = 0
  let mut upper = len - 1
  while lower < upper {
    let lower_value = arr.elements[lower]
    let upper_value = arr.elements[upper]
    let lower_hole = arr.holes.contains(lower)
    let upper_hole = arr.holes.contains(upper)
    arr.elements[lower] = upper_value
    arr.elements[upper] = lower_value
    if upper_hole {
      arr.holes[lower] = ()
    } else {
      arr.holes.remove(lower)
    }
    if lower_hole {
      arr.holes[upper] = ()
    } else {
      arr.holes.remove(upper)
    }
    lower = lower + 1
    upper = upper - 1
  }
  Value::Array(arr)
}

///|
fn array_direct_fill(arr : ArrayData, args : Array[Value]) -> Value raise Error {
  let fill_value = if args.length() > 0 { args[0] } else { Undefined }
  let len = arr.elements.length()
  let start = if args.length() > 1 {
    array_mutator_relative_index(@runtime.to_number(args[1]).to_int(), len)
  } else {
    0
  }
  let final_index = if args.length() > 2 {
    match args[2] {
      Undefined => len
      _ =>
        array_mutator_relative_index(@runtime.to_number(args[2]).to_int(), len)
    }
  } else {
    len
  }
  for i = start; i < final_index; i = i + 1 {
    arr.elements[i] = fill_value
    arr.holes.remove(i)
  }
  Value::Array(arr)
}

///|
fn array_direct_copy_within(
  arr : ArrayData,
  args : Array[Value],
) -> Value raise Error {
  let len = arr.elements.length()
  let mut target = if args.length() > 0 {
    array_mutator_relative_index(@runtime.to_number(args[0]).to_int(), len)
  } else {
    0
  }
  let mut start = if args.length() > 1 {
    array_mutator_relative_index(@runtime.to_number(args[1]).to_int(), len)
  } else {
    0
  }
  let final_index = if args.length() > 2 {
    match args[2] {
      Undefined => len
      _ =>
        array_mutator_relative_index(@runtime.to_number(args[2]).to_int(), len)
    }
  } else {
    len
  }
  let mut count = if final_index - start < len - target {
    final_index - start
  } else {
    len - target
  }
  if count > 0 {
    let mut direction = 1
    if start < target && target < start + count {
      direction = -1
      start = start + count - 1
      target = target + count - 1
    }
    while count > 0 {
      if arr.holes.contains(start) {
        arr.elements[target] = Undefined
        arr.holes[target] = ()
      } else {
        arr.elements[target] = arr.elements[start]
        arr.holes.remove(target)
      }
      start = start + direction
      target = target + direction
      count = count - 1
    }
  }
  Value::Array(arr)
}

///|
fn array_direct_sort_default(arr : ArrayData) -> Value {
  let len = arr.elements.length()
  let elements : Array[Value] = []
  for i = 0; i < len; i = i + 1 {
    if !arr.holes.contains(i) {
      elements.push(arr.elements[i])
    }
  }
  elements.sort_by(array_sort_default_compare)
  for i = 0; i < elements.length(); i = i + 1 {
    arr.elements[i] = elements[i]
    arr.holes.remove(i)
  }
  for i = elements.length(); i < len; i = i + 1 {
    arr.elements[i] = Undefined
    arr.holes[i] = ()
  }
  Value::Array(arr)
}

///|
fn array_reverse_indexed_properties(
  interp : Interpreter,
  o : Value,
) -> Value raise Error {
  // ES2024 §23.1.3.28: query lower/upper presence separately, then use
  // Set/DeletePropertyOrThrow so explicit undefined and holes swap correctly.
  let len = @runtime.to_array_like_length_interp(o, interp)
  let middle = len / 2
  for lower = 0; lower < middle; lower = lower + 1 {
    let upper = len - lower - 1
    let lower_exists = array_mutator_has_index(interp, o, lower)
    let lower_value = if lower_exists {
      Some(@runtime.get_array_like_element_interp(interp, o, lower))
    } else {
      None
    }
    let upper_exists = array_mutator_has_index(interp, o, upper)
    let upper_value = if upper_exists {
      Some(@runtime.get_array_like_element_interp(interp, o, upper))
    } else {
      None
    }
    match (lower_value, upper_value) {
      (Some(lv), Some(uv)) => {
        array_mutator_set_index(interp, o, lower, uv)
        array_mutator_set_index(interp, o, upper, lv)
      }
      (Some(lv), None) => {
        array_mutator_delete_index(interp, o, lower)
        array_mutator_set_index(interp, o, upper, lv)
      }
      (None, Some(uv)) => {
        array_mutator_set_index(interp, o, lower, uv)
        array_mutator_delete_index(interp, o, upper)
      }
      (None, None) => ()
    }
  }
  o
}

///|
fn array_copy_within_indexed_properties(
  interp : Interpreter,
  o : Value,
  args : Array[Value],
) -> Value raise Error {
  // ES2024 §23.1.3.4: copy direction handles overlap; absent source indices
  // delete the target instead of materializing undefined.
  let len = @runtime.to_array_like_length_interp(o, interp)
  let mut to = if args.length() > 0 {
    array_mutator_relative_index(@runtime.to_number(args[0]).to_int(), len)
  } else {
    0
  }
  let mut from = if args.length() > 1 {
    array_mutator_relative_index(@runtime.to_number(args[1]).to_int(), len)
  } else {
    0
  }
  let final_index = if args.length() > 2 {
    match args[2] {
      Undefined => len
      _ =>
        array_mutator_relative_index(@runtime.to_number(args[2]).to_int(), len)
    }
  } else {
    len
  }
  let mut count = if final_index - from < len - to {
    final_index - from
  } else {
    len - to
  }
  if count <= 0 {
    return o
  }
  let mut direction = 1
  if from < to && to < from + count {
    direction = -1
    from = from + count - 1
    to = to + count - 1
  }
  while count > 0 {
    if array_mutator_has_index(interp, o, from) {
      let from_value = @runtime.get_array_like_element_interp(interp, o, from)
      array_mutator_set_index(interp, o, to, from_value)
    } else {
      array_mutator_delete_index(interp, o, to)
    }
    from = from + direction
    to = to + direction
    count = count - 1
  }
  o
}

///|
fn array_fill_indexed_properties(
  interp : Interpreter,
  o : Value,
  args : Array[Value],
) -> Value raise Error {
  // ES2024 §23.1.3.6 uses Set for every covered index, so filling with
  // explicit undefined must clear any old hole marker.
  let fill_value = if args.length() > 0 { args[0] } else { Undefined }
  let len = @runtime.to_array_like_length_interp(o, interp)
  let start = if args.length() > 1 {
    array_mutator_relative_index(@runtime.to_number(args[1]).to_int(), len)
  } else {
    0
  }
  let final_index = if args.length() > 2 {
    match args[2] {
      Undefined => len
      _ =>
        array_mutator_relative_index(@runtime.to_number(args[2]).to_int(), len)
    }
  } else {
    len
  }
  for k = start; k < final_index; k = k + 1 {
    array_mutator_set_index(interp, o, k, fill_value)
  }
  o
}

///|
fn array_mutator_sparse_high_index_sources(
  interp : Interpreter,
  arr : ArrayData,
  len64 : Int64,
) -> Array[(Int64, String, Value)]? {
  let entries : Array[(Int64, String, Value)] = []
  array_mutator_append_dense_indexed_properties(entries, arr, len64)
  array_mutator_append_indexed_bag_properties(entries, arr.bag, len64)
  let mut current = @runtime.get_array_prototype(interp.realm_state, arr)
  while true {
    match current {
      Object(data) => {
        array_mutator_append_indexed_bag_properties(entries, data.bag, len64)
        current = data.prototype
      }
      Array(data) => {
        array_mutator_append_dense_indexed_properties(entries, data, len64)
        array_mutator_append_indexed_bag_properties(entries, data.bag, len64)
        current = @runtime.get_array_prototype(interp.realm_state, data)
      }
      Proxy(_) => return None
      _ => return Some(entries)
    }
  }
  None
}

///|
fn array_shift_sparse_high_index_properties(
  interp : Interpreter,
  arr : ArrayData,
  len : Double,
  len64 : Int64,
) -> Value? raise Error {
  guard len64 > 0x7FFFFFFFL else { return None }
  let entries = match
    array_mutator_sparse_high_index_sources(interp, arr, len64) {
    Some(entries) => entries
    None => return None
  }
  entries.sort_by(array_mutator_compare_entry_index_ascending)
  let mut first : Value = Undefined
  let target = Value::Array(arr)
  for entry in entries {
    let idx64 = entry.0
    let from_value = interp.get_property(target, entry.1, @token.Loc::default())
    if idx64 == 0L {
      first = from_value
    } else {
      array_mutator_set_property_key(
        interp,
        target,
        (idx64 - 1L).to_string(),
        from_value,
      )
    }
    if idx64 + 1L >= len64 ||
      !array_mutator_entries_contain_index(entries, idx64 + 1L) {
      array_mutator_delete_property_key(interp, target, entry.1)
    }
  }
  array_mutator_set_length_number(interp, target, len - 1.0)
  Some(first)
}

///|
fn array_unshift_sparse_high_index_properties(
  interp : Interpreter,
  arr : ArrayData,
  args : Array[Value],
  len : Double,
  len64 : Int64,
) -> Value? raise Error {
  guard len64 > 0x7FFFFFFFL else { return None }
  let entries = match
    array_mutator_sparse_high_index_sources(interp, arr, len64) {
    Some(entries) => entries
    None => return None
  }
  entries.sort_by(array_mutator_compare_entry_index_descending)
  let target = Value::Array(arr)
  let arg_count64 = args.length().to_int64()
  for entry in entries {
    let from_value = interp.get_property(target, entry.1, @token.Loc::default())
    array_mutator_set_property_key(
      interp,
      target,
      (entry.0 + arg_count64).to_string(),
      from_value,
    )
  }
  for entry in entries {
    let idx64 = entry.0
    if idx64 >= arg_count64 &&
      !array_mutator_entries_contain_index(entries, idx64 - arg_count64) {
      array_mutator_delete_property_key(interp, target, entry.1)
    }
  }
  for j = 0; j < args.length(); j = j + 1 {
    array_mutator_set_property_key(interp, target, j.to_string(), args[j])
  }
  let new_len = len + args.length().to_double()
  array_mutator_set_length_number(interp, target, new_len)
  Some(Value::Number(new_len))
}

///|
fn array_shift_indexed_properties(
  interp : Interpreter,
  o : Value,
) -> Value raise Error {
  // ES2024 §23.1.3.29 shifts only present source indices; absent sources
  // delete their target slots, preserving holes. Use string keys so sparse
  // Array lengths and generic array-likes near 2^53 do not narrow through Int.
  let len = array_mutator_length_number(interp, o)
  let len64 = len.to_int64()
  if len64 == 0L {
    array_mutator_set_length_number(interp, o, 0.0)
    return Undefined
  }
  match o {
    Array(arr) =>
      match array_shift_sparse_high_index_properties(interp, arr, len, len64) {
        Some(result) => return result
        None => ()
      }
    _ => ()
  }
  let first = interp.get_property(o, "0", @token.Loc::default())
  let mut k = 1L
  while k < len64 {
    let from_key = k.to_string()
    let to_key = (k - 1L).to_string()
    if interp.has_property(o, from_key) {
      let from_value = interp.get_property(o, from_key, @token.Loc::default())
      array_mutator_set_property_key(interp, o, to_key, from_value)
    } else {
      array_mutator_delete_property_key(interp, o, to_key)
    }
    k = k + 1L
  }
  array_mutator_delete_property_key(interp, o, (len64 - 1L).to_string())
  array_mutator_set_length_number(interp, o, len - 1.0)
  first
}

///|
fn array_unshift_indexed_properties(
  interp : Interpreter,
  o : Value,
  args : Array[Value],
) -> Value raise Error {
  // ES2024 §23.1.3.34 walks from the end so shifted holes remain holes and
  // inserted arguments become present properties even when they are undefined.
  // String keys preserve large sparse indices that cannot fit in Int.
  let len = array_mutator_length_number(interp, o)
  let len64 = len.to_int64()
  let arg_count = args.length()
  if arg_count > 0 {
    if len + arg_count.to_double() > ARRAY_MAX_SAFE_LENGTH {
      raise @errors.TypeError(message="Invalid array length")
    }
    match o {
      Array(arr) =>
        match
          array_unshift_sparse_high_index_properties(
            interp, arr, args, len, len64,
          ) {
          Some(result) => return result
          None => ()
        }
      _ => ()
    }
    let arg_count64 = arg_count.to_int64()
    let mut k = len64
    while k > 0L {
      let from_key = (k - 1L).to_string()
      let to_key = (k + arg_count64 - 1L).to_string()
      if interp.has_property(o, from_key) {
        let from_value = interp.get_property(o, from_key, @token.Loc::default())
        array_mutator_set_property_key(interp, o, to_key, from_value)
      } else {
        array_mutator_delete_property_key(interp, o, to_key)
      }
      k = k - 1L
    }
    for j = 0; j < arg_count; j = j + 1 {
      array_mutator_set_property_key(interp, o, j.to_string(), args[j])
    }
  }
  let new_len = len + arg_count.to_double()
  array_mutator_set_length_number(interp, o, new_len)
  Value::Number(new_len)
}

///|
fn array_splice_indexed_properties(
  interp : Interpreter,
  o : Value,
  args : Array[Value],
) -> Value raise Error {
  let alen = @runtime.to_array_like_length_interp(o, interp)
  let mut start = if args.length() > 0 {
    @runtime.to_number(args[0]).to_int()
  } else {
    0
  }
  if start < 0 {
    start = alen + start
    if start < 0 {
      start = 0
    }
  }
  if start > alen {
    start = alen
  }
  let del_count = if args.length() > 1 {
    let d_num = @runtime.to_number(args[1])
    if d_num.is_inf() || d_num >= (alen - start).to_double() {
      alen - start
    } else {
      let d = d_num.to_int()
      if d < 0 {
        0
      } else {
        d
      }
    }
  } else {
    alen - start
  }
  let removed = @runtime.array_species_create(interp, o, del_count)
  for i = 0; i < del_count; i = i + 1 {
    if array_mutator_has_index(interp, o, start + i) {
      @runtime.create_data_property_or_throw(
        interp,
        removed,
        i,
        @runtime.get_array_like_element_interp(interp, o, start + i),
      )
    }
  }
  @runtime.set_array_like_length(removed, del_count)
  let new_items : Array[Value] = []
  for i = 2; i < args.length(); i = i + 1 {
    new_items.push(args[i])
  }
  let items_count = new_items.length()
  let new_len = alen - del_count + items_count
  if items_count < del_count {
    for i = start; i < alen - del_count; i = i + 1 {
      let from = i + del_count
      let to = i + items_count
      if array_mutator_has_index(interp, o, from) {
        let from_value = @runtime.get_array_like_element_interp(interp, o, from)
        array_mutator_set_index(interp, o, to, from_value)
      } else {
        array_mutator_delete_index(interp, o, to)
      }
    }
    for i = alen; i > new_len; i = i - 1 {
      array_mutator_delete_index(interp, o, i - 1)
    }
  } else if items_count > del_count {
    for i = alen - del_count; i > start; i = i - 1 {
      let from = i + del_count - 1
      let to = i + items_count - 1
      if array_mutator_has_index(interp, o, from) {
        let from_value = @runtime.get_array_like_element_interp(interp, o, from)
        array_mutator_set_index(interp, o, to, from_value)
      } else {
        array_mutator_delete_index(interp, o, to)
      }
    }
  }
  for i = 0; i < items_count; i = i + 1 {
    array_mutator_set_index(interp, o, start + i, new_items[i])
  }
  array_mutator_set_length(interp, o, new_len)
  removed
}

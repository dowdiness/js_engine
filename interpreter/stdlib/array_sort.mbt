///|
/// Shared Array.prototype.sort implementation for both the prototype method
/// and the Array fast path. Follows ES2024 §23.1.3.30's observable shape:
/// collect present indices with skip-holes, sort present values, write them
/// back from index 0, then delete the remaining indices so holes stay holes.
fn array_sort_validate_comparefn(args : Array[Value]) -> Value raise Error {
  if args.length() == 0 {
    return Undefined
  }
  let comparefn = args[0]
  match comparefn {
    Undefined => Undefined
    _ => {
      if !@runtime.is_callable(comparefn) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(comparefn) + " is not a function",
        )
      }
      comparefn
    }
  }
}

///|
fn array_sort_default_compare(a : Value, b : Value) -> Int {
  // ES SortCompare orders undefined after all defined values before either
  // the user comparefn or string comparison is considered.
  if a is Undefined && b is Undefined {
    return 0
  }
  if a is Undefined {
    return 1
  }
  if b is Undefined {
    return -1
  }
  let sa = a.to_string()
  let sb = b.to_string()
  if sa < sb {
    -1
  } else if sa > sb {
    1
  } else {
    0
  }
}

///|
fn array_sort_values(
  interp : Interpreter,
  elements : Array[Value],
  comparefn : Value,
) -> Unit raise Error {
  match comparefn {
    Undefined => elements.sort_by(array_sort_default_compare)
    _ => {
      let loc = @token.Loc::default()
      let mut caught_error : Error? = None
      elements.sort_by(fn(a, b) {
        if a is Undefined && b is Undefined {
          return 0
        }
        if a is Undefined {
          return 1
        }
        if b is Undefined {
          return -1
        }
        if caught_error is Some(_) {
          return 0
        }
        let result = interp.call_value(comparefn, Undefined, [a, b], loc) catch {
          e => {
            caught_error = Some(e)
            return 0
          }
        }
        let cmp = interp.to_number(result) catch {
          e => {
            caught_error = Some(e)
            return 0
          }
        }
        if cmp.is_nan() {
          0
        } else if cmp < 0.0 {
          -1
        } else if cmp > 0.0 {
          1
        } else {
          0
        }
      })
      match caught_error {
        Some(e) => raise e
        None => ()
      }
    }
  }
}

///|
fn array_sort_indexed_properties(
  interp : Interpreter,
  o : Value,
  comparefn : Value,
) -> Value raise Error {
  let len = @runtime.to_array_like_length_interp(o, interp)
  let elements : Array[Value] = []
  // SortIndexedProperties(..., skip-holes): only values for indices where
  // HasProperty is true enter the sortable list. Holes are deleted later.
  for i = 0; i < len; i = i + 1 {
    if array_mutator_has_index(interp, o, i) {
      elements.push(@runtime.get_array_like_element_interp(interp, o, i))
    }
  }
  array_sort_values(interp, elements, comparefn)
  for i = 0; i < elements.length(); i = i + 1 {
    array_mutator_set_index(interp, o, i, elements[i])
  }
  for i = elements.length(); i < len; i = i + 1 {
    array_mutator_delete_index(interp, o, i)
  }
  o
}

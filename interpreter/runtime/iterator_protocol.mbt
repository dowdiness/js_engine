///|
/// Return an iterator's `next` method using the spec §7.4.1 `[[Get]]` path.
/// Per spec, callability is NOT checked here — GetIterator only gets the property.
/// The TypeError fires later in IteratorNext when Call(nextMethod, ...) is attempted.
pub fn Interpreter::get_iterator_next_method(
  self : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Value raise Error {
  if !is_object_value(iterator) {
    raise @errors.TypeError(message="Iterator is not an object")
  }
  self.get_property(iterator, "next", loc)
}

///|
/// Perform `IteratorNext(iteratorRecord)` with an already-resolved next method.
fn Interpreter::iterator_next_result(
  self : Interpreter,
  iterator : Value,
  next_method : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let result = self.call_value(next_method, iterator, [], loc)
  if !is_object_value(result) {
    raise @errors.TypeError(message="Iterator result is not an object")
  }
  result
}

///|
/// Perform `IteratorStep(iteratorRecord)`.
pub fn Interpreter::iterator_step_result(
  self : Interpreter,
  iterator : Value,
  next_method : Value,
  loc : @token.Loc,
) -> Value? raise Error {
  let result = self.iterator_next_result(iterator, next_method, loc)
  if is_truthy(self.get_property(result, "done", loc)) {
    None
  } else {
    Some(result)
  }
}

///|
/// Perform `IteratorValue(iterResult)`.
pub fn Interpreter::iterator_result_value(
  self : Interpreter,
  iter_result : Value,
  loc : @token.Loc,
) -> Value raise Error {
  if !is_object_value(iter_result) {
    raise @errors.TypeError(message="Iterator result is not an object")
  }
  self.get_property(iter_result, "value", loc)
}

///|
/// Perform `IteratorStep` followed by `IteratorValue`.
pub fn Interpreter::iterator_step_value(
  self : Interpreter,
  iterator : Value,
  next_method : Value,
  loc : @token.Loc,
) -> Value? raise Error {
  match self.iterator_step_result(iterator, next_method, loc) {
    None => None
    Some(result) => Some(self.iterator_result_value(result, loc))
  }
}

///|
/// `IteratorClose(iteratorRecord, completion)` for a non-throw completion.
///
/// Resolves `"return"` via [[Get]], calls it if present, and raises on
/// GetMethod/Call/IsObject failures (§7.4.11 steps 6–7). Use
/// `iterator_close_throw` when `completion` is a throw completion.
pub fn Interpreter::iterator_close(
  self : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  if !is_object_value(iterator) {
    return
  }
  let return_fn = self.get_property(iterator, "return", loc)
  match return_fn {
    Undefined | Null => ()
    _ =>
      if !is_callable(return_fn) {
        raise @errors.TypeError(message="iterator.return is not a function")
      } else {
        let result = self.call_value(return_fn, iterator, [], loc)
        if !is_object_value(result) {
          raise @errors.TypeError(
            message="Iterator return() must return an object",
          )
        }
      }
  }
}

///|
/// `IteratorClose(iteratorRecord, ThrowCompletion(...))` (§7.4.11 step 5).
///
/// Attempts `return()` for cleanup, then discards GetMethod/Call/IsObject
/// errors so the original ThrowCompletion remains the completion value.
/// Infallible: callers re-raise the original error after this returns.
pub fn Interpreter::iterator_close_throw(
  self : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Unit {
  if !is_object_value(iterator) {
    return
  }
  let return_fn = self.get_property(iterator, "return", loc) catch {
    _ => return
  }
  match return_fn {
    Undefined | Null => ()
    _ =>
      if is_callable(return_fn) {
        // Discard Call errors and skip IsObject: throw completion wins (§7.4.11 step 5).
        let _ = self.call_value(return_fn, iterator, [], loc) catch {
          _ => Undefined
        }
      }
  }
}

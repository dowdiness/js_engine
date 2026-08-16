///|
// Canonical built-in iterator fallback for spread. Array and String do not
// materialize their default @@iterator as an ordinary property in this
// runtime, so the fallback is selected only after the observable lookup
// returned undefined. An explicit Array own override, including undefined,
// suppresses the fallback and keeps the ordinary TypeError semantics.
fn Interpreter::default_iterable_iterator_if_unoverridden(
  self : Interpreter,
  iterable : Value,
  iterator_method : Value,
) -> Value? {
  guard iterator_method is Undefined else { return None }
  let iterator_sym = self.realm_state.well_known_symbols.iterator
  match iterable {
    Array(data) => {
      guard !data.bag.symbol_descriptors.contains(iterator_sym.id) &&
        !data.bag.symbol_properties.contains(iterator_sym.id) else {
        return None
      }
      Some(self.realm_state.make_array_iterator_value(data))
    }
    String_(value) => Some(self.realm_state.make_string_iterator_value(value))
    _ => None
  }
}

///|
// The batch is an internal Array Value so the neutral activation seam carries
// one owned result without exposing a sink callback to the runtime. Consumers
// copy the elements before appending them to their concrete destination.
pub fn executor_iterable_spread_batch_values(
  batch : Value,
) -> Array[Value] raise Error {
  match batch {
    Array(data) => data.elements.copy()
    _ =>
      raise @errors.InternalError(
        message="iterable spread completion was not an Array batch",
      )
  }
}

///|
priv enum ExecutorIterableSpreadPhase {
  ExecutorIterableSpreadNeedIteratorMethod(Value)
  ExecutorIterableSpreadAwaitIteratorMethod(Value)
  ExecutorIterableSpreadHaveIteratorMethod(Value, Value)
  ExecutorIterableSpreadAwaitIteratorCall
  ExecutorIterableSpreadHaveIterator(Value)
  ExecutorIterableSpreadNeedNextMethod(Value)
  ExecutorIterableSpreadAwaitNextMethod(Value)
  ExecutorIterableSpreadHaveNextMethod(Value, Value)
  ExecutorIterableSpreadAwaitNextCall(Value, Value)
  ExecutorIterableSpreadHaveNextResult(Value, Value, Value)
  ExecutorIterableSpreadNeedDone(Value, Value, Value)
  ExecutorIterableSpreadAwaitDone(Value, Value, Value)
  ExecutorIterableSpreadHaveDone(Value, Value, Value, Value)
  ExecutorIterableSpreadNeedValue(Value, Value, Value)
  ExecutorIterableSpreadAwaitValue(Value, Value, Value)
  ExecutorIterableSpreadComplete
}

///|
priv struct ExecutorIterableSpreadFrame {
  request : ExecutorIterableSpreadRequest
  values : Array[Value]
  mut phase : ExecutorIterableSpreadPhase
}

///|
fn ExecutorIterableSpreadFrame::ExecutorIterableSpreadFrame(
  request : ExecutorIterableSpreadRequest,
) -> ExecutorIterableSpreadFrame {
  {
    request,
    values: [],
    phase: ExecutorIterableSpreadNeedIteratorMethod(request.iterable),
  }
}

///|
fn ExecutorIterableSpreadFrame::step_frame(
  self : ExecutorIterableSpreadFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  let loc = self.request.loc
  match self.phase {
    ExecutorIterableSpreadNeedIteratorMethod(iterable) => {
      self.phase = ExecutorIterableSpreadAwaitIteratorMethod(iterable)
      executor_activation_symbol_property_get(
        iterable,
        interp.realm_state.well_known_symbols.iterator,
        loc,
      )
    }
    ExecutorIterableSpreadHaveIteratorMethod(iterable, iterator_method) =>
      if is_callable(iterator_method) {
        self.phase = ExecutorIterableSpreadAwaitIteratorCall
        ExecutorActivationCall(
          ExecutorCallRequest(
            callee=iterator_method,
            this_value=iterable,
            args=[],
            loc~,
          ),
        )
      } else {
        match
          interp.default_iterable_iterator_if_unoverridden(
            iterable, iterator_method,
          ) {
          Some(iterator) => {
            self.phase = ExecutorIterableSpreadHaveIterator(iterator)
            self.step_frame(interp)
          }
          None => {
            let message = match iterator_method {
              Undefined => type_of(iterable) + " is not iterable"
              _ =>
                type_of(iterable) +
                " is not iterable (Symbol.iterator is not a function)"
            }
            raise @errors.TypeError(message~)
          }
        }
      }
    ExecutorIterableSpreadHaveIterator(iterator) => {
      guard is_object_value(iterator) else {
        raise @errors.TypeError(message="Iterator is not an object")
      }
      self.phase = ExecutorIterableSpreadNeedNextMethod(iterator)
      self.step_frame(interp)
    }
    ExecutorIterableSpreadNeedNextMethod(iterator) => {
      self.phase = ExecutorIterableSpreadAwaitNextMethod(iterator)
      executor_activation_managed_property_get(iterator, "next", loc)
    }
    ExecutorIterableSpreadHaveNextMethod(iterator, next_method) => {
      self.phase = ExecutorIterableSpreadAwaitNextCall(iterator, next_method)
      ExecutorActivationCall(
        ExecutorCallRequest(
          callee=next_method,
          this_value=iterator,
          args=[],
          loc~,
        ),
      )
    }
    ExecutorIterableSpreadHaveNextResult(iterator, next_method, result) => {
      guard is_object_value(result) else {
        raise @errors.TypeError(message="Iterator result is not an object")
      }
      self.phase = ExecutorIterableSpreadNeedDone(iterator, next_method, result)
      self.step_frame(interp)
    }
    ExecutorIterableSpreadNeedDone(iterator, next_method, result) => {
      self.phase = ExecutorIterableSpreadAwaitDone(
        iterator, next_method, result,
      )
      executor_activation_managed_property_get(result, "done", loc)
    }
    ExecutorIterableSpreadHaveDone(iterator, next_method, result, done) =>
      if is_truthy(done) {
        self.phase = ExecutorIterableSpreadComplete
        // The Array Value is an internal, owned batch. The pending VM
        // destination unwraps it and appends the elements exactly once.
        ExecutorActivationNormal(make_array(self.values.copy()))
      } else {
        self.phase = ExecutorIterableSpreadNeedValue(
          iterator, next_method, result,
        )
        self.step_frame(interp)
      }
    ExecutorIterableSpreadNeedValue(iterator, next_method, result) => {
      self.phase = ExecutorIterableSpreadAwaitValue(
        iterator, next_method, result,
      )
      executor_activation_managed_property_get(result, "value", loc)
    }
    ExecutorIterableSpreadAwaitIteratorMethod(_)
    | ExecutorIterableSpreadAwaitIteratorCall
    | ExecutorIterableSpreadAwaitNextMethod(_)
    | ExecutorIterableSpreadAwaitNextCall(_, _)
    | ExecutorIterableSpreadAwaitDone(_, _, _)
    | ExecutorIterableSpreadAwaitValue(_, _, _) =>
      raise @errors.InternalError(
        message="iterable spread frame stepped while awaiting a child completion",
      )
    ExecutorIterableSpreadComplete =>
      raise @errors.InternalError(
        message="iterable spread frame stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for ExecutorIterableSpreadFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for ExecutorIterableSpreadFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        ExecutorIterableSpreadAwaitIteratorMethod(iterable) =>
          self.phase = ExecutorIterableSpreadHaveIteratorMethod(iterable, value)
        ExecutorIterableSpreadAwaitIteratorCall =>
          self.phase = ExecutorIterableSpreadHaveIterator(value)
        ExecutorIterableSpreadAwaitNextMethod(iterator) =>
          self.phase = ExecutorIterableSpreadHaveNextMethod(iterator, value)
        ExecutorIterableSpreadAwaitNextCall(iterator, next_method) =>
          self.phase = ExecutorIterableSpreadHaveNextResult(
            iterator, next_method, value,
          )
        ExecutorIterableSpreadAwaitDone(iterator, next_method, result) =>
          self.phase = ExecutorIterableSpreadHaveDone(
            iterator, next_method, result, value,
          )
        ExecutorIterableSpreadAwaitValue(iterator, next_method, result) => {
          self.values.push(value)
          self.phase = ExecutorIterableSpreadHaveNextMethod(
            iterator, next_method,
          )
          ignore(result)
        }
        ExecutorIterableSpreadNeedIteratorMethod(_)
        | ExecutorIterableSpreadHaveIteratorMethod(_, _)
        | ExecutorIterableSpreadHaveIterator(_)
        | ExecutorIterableSpreadNeedNextMethod(_)
        | ExecutorIterableSpreadHaveNextMethod(_, _)
        | ExecutorIterableSpreadHaveNextResult(_, _, _)
        | ExecutorIterableSpreadNeedDone(_, _, _)
        | ExecutorIterableSpreadHaveDone(_, _, _, _)
        | ExecutorIterableSpreadNeedValue(_, _, _)
        | ExecutorIterableSpreadComplete =>
          raise @errors.InternalError(
            message="iterable spread frame received an unexpected child completion",
          )
      }
  }
}

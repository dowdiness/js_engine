///|
priv enum FromAsyncSource {
  ArrayLike(Value, Int64)
  Iterator(Value, Value, Bool) // iterator, cached next, synchronous
}

///|
priv enum FromAsyncStep {
  Next
  IteratorResult(Value)
  MapValue(Value)
  StoreValue(Value)
  Finish
  Close(Value)
  Reject(Value)
}

///|
priv struct FromAsync {
  source : FromAsyncSource
  output : Value
  mapper : Value
  this_arg : Value
  promises : @runtime.PromiseIntrinsics
  resolve : Value
  reject : Value
  realm : @runtime.RealmState
}

///|
fn FromAsync::FromAsync(
  source : FromAsyncSource,
  output : Value,
  mapper : Value,
  this_arg : Value,
  promises : @runtime.PromiseIntrinsics,
  resolve : Value,
  reject : Value,
  realm : @runtime.RealmState,
) -> FromAsync {
  { source, output, mapper, this_arg, promises, resolve, reject, realm }
}

///|
fn from_async_reason(interp : Interpreter, error : Error) -> Value raise Error {
  guard @runtime.is_js_catchable_error(error) else { raise error }
  @runtime.js_error_to_value_with_env(error, Some(interp.global))
}

///|
fn FromAsync::await_value(
  self : FromAsync,
  interp : Interpreter,
  index : Int64,
  value : Value,
  fulfilled : (Value) -> FromAsyncStep,
  rejected : (Value) -> FromAsyncStep,
) -> Unit raise Error {
  let on_fulfill = @runtime.make_interp_method_func(
    name="",
    realm_state=Some(self.realm),
    fn(ip, _, args) raise {
      self.drive(ip, index, fulfilled(args[0]))
      Undefined
    },
  )
  let on_reject = @runtime.make_interp_method_func(
    name="",
    realm_state=Some(self.realm),
    fn(ip, _, args) raise {
      self.drive(ip, index, rejected(args[0]))
      Undefined
    },
  )
  self.promises.await_value(interp, value, on_fulfill, on_reject) catch {
    error =>
      self.drive(interp, index, rejected(from_async_reason(interp, error)))
  }
}

///|
/// Adapt next/return through an intrinsic Promise, including synchronous errors.
/// Closing after a rejected yielded value uses IteratorClose, not the async
/// adapter's return: its result and any JavaScript error must be ignored.
fn FromAsync::sync_call(
  self : FromAsync,
  interp : Interpreter,
  iterator : Value,
  next : Value,
  closing~ : Bool,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let (promise, resolve, reject) = self.promises.new_capability(interp)
  try {
    let method_value = if closing {
      interp.get_property(iterator, "return", loc)
    } else {
      next
    }
    if closing && method_value is (Null | Undefined) {
      let result = @runtime.make_object(
        { "value": Undefined, "done": Bool(true) },
        self.realm.get_obj_proto(),
        None,
        "Object",
        Map([]),
        true,
      )
      let _ = interp.call_value(resolve, Undefined, [result], loc)
      return promise
    }
    let result = interp.call_value(method_value, iterator, [], loc)
    guard @runtime.is_object_value(result) else {
      raise @errors.TypeError(message="Iterator result is not an object")
    }
    let done = @runtime.is_truthy(interp.get_property(result, "done", loc))
    let value = interp.get_property(result, "value", loc)
    let on_fulfill = @runtime.make_interp_method_func(
      name="",
      realm_state=Some(self.realm),
      fn(ip, _, args) raise {
        let result = @runtime.make_object(
          { "value": args[0], "done": Bool(done) },
          self.realm.get_obj_proto(),
          None,
          "Object",
          Map([]),
          true,
        )
        ip.call_value(resolve, Undefined, [result], loc)
      },
    )
    let on_reject = @runtime.make_interp_method_func(
      name="",
      realm_state=Some(self.realm),
      fn(ip, _, args) raise {
        if !closing && !done {
          try {
            let return_method = ip.get_property(iterator, "return", loc)
            match return_method {
              Null | Undefined => ()
              _ => {
                let _ = ip.call_value(return_method, iterator, [], loc)
              }
            }
          } catch {
            error => {
              guard @runtime.is_js_catchable_error(error) else { raise error }
            }
          }
        }
        ip.call_value(reject, Undefined, [args[0]], loc)
      },
    )
    self.promises.await_value(interp, value, on_fulfill, on_reject) catch {
      error => {
        let reason = from_async_reason(interp, error)
        let _ = interp.call_value(on_reject, Undefined, [reason], loc)
      }
    }
  } catch {
    error => {
      let reason = from_async_reason(interp, error)
      let _ = interp.call_value(reject, Undefined, [reason], loc)
    }
  }
  promise
}

///|
/// Synchronous transitions run in this loop. Every await returns to the job
/// queue; processing a long input never recursively consumes the host stack.
fn FromAsync::drive(
  self : FromAsync,
  interp : Interpreter,
  start_index : Int64,
  start_step : FromAsyncStep,
) -> Unit raise Error {
  let loc = @token.Loc::default()
  let mut index = start_index
  let mut step = start_step
  while true {
    let current = step
    step = try {
      match current {
        Next => {
          interp.observe_execution_step()
          match self.source {
            ArrayLike(input, length) =>
              if index >= length {
                Finish
              } else {
                let value = interp.get_property(input, index.to_string(), loc)
                self.await_value(
                  interp,
                  index,
                  value,
                  value => MapValue(value),
                  reason => Reject(reason),
                )
                return
              }
            Iterator(iterator, next, synchronous) => {
              guard index < 9007199254740991L else {
                raise @errors.TypeError(
                  message="Array.fromAsync input is too long",
                )
              }
              let result = if synchronous {
                self.sync_call(interp, iterator, next, closing=false)
              } else {
                interp.call_value(next, iterator, [], loc)
              }
              self.await_value(
                interp,
                index,
                result,
                value => IteratorResult(value),
                reason => Reject(reason),
              )
              return
            }
          }
        }
        IteratorResult(result) => {
          guard @runtime.is_object_value(result) else {
            raise @errors.TypeError(message="Iterator result is not an object")
          }
          if @runtime.is_truthy(interp.get_property(result, "done", loc)) {
            Finish
          } else {
            MapValue(interp.get_property(result, "value", loc))
          }
        }
        MapValue(value) =>
          if self.mapper is Undefined {
            StoreValue(value)
          } else {
            let mapped = interp.call_value(
              self.mapper,
              self.this_arg,
              [value, Number(index.to_double())],
              loc,
            )
            self.await_value(
              interp,
              index,
              mapped,
              value => StoreValue(value),
              reason => Close(reason),
            )
            return
          }
        StoreValue(value) => {
          @runtime.create_data_property_or_throw(
            interp,
            self.output,
            index,
            value,
          )
          index += 1L
          Next
        }
        Finish => {
          let _ = interp.set_property(
            self.output,
            "length",
            Number(index.to_double()),
            loc,
            strict=true,
          )
          let _ = interp.call_value(self.resolve, Undefined, [self.output], loc)
          return
        }
        Close(reason) =>
          match self.source {
            ArrayLike(_, _) => Reject(reason)
            Iterator(iterator, next, synchronous) => {
              let result = if synchronous {
                self.sync_call(interp, iterator, next, closing=true)
              } else {
                let return_method = interp.get_property(iterator, "return", loc)
                guard !(return_method is (Null | Undefined)) else {
                  step = Reject(reason)
                  continue
                }
                interp.call_value(return_method, iterator, [], loc)
              }
              self.await_value(interp, index, result, _ => Reject(reason), _ => {
                Reject(reason)
              })
              return
            }
          }
        Reject(reason) => {
          let _ = interp.call_value(self.reject, Undefined, [reason], loc)
          return
        }
      }
    } catch {
      error => {
        let reason = from_async_reason(interp, error)
        match current {
          Close(original) => Reject(original)
          MapValue(_) | StoreValue(_) => Close(reason)
          Next if index >= 9007199254740991L => Close(reason)
          _ => Reject(reason)
        }
      }
    }
  }
}

///|
fn from_async_method(
  interp : Interpreter,
  input : Value,
  symbol : @runtime.SymbolData,
) -> Value raise Error {
  let method_value = interp.get_computed_property(
    input,
    Symbol(symbol),
    @token.Loc::default(),
  )
  match method_value {
    Null | Undefined => Undefined
    _ => {
      guard @runtime.is_callable(method_value) else {
        raise @errors.TypeError(message="Iterator method is not callable")
      }
      method_value
    }
  }
}

///|
fn make_array_from_async(
  realm : @runtime.RealmState,
  promises : @runtime.PromiseIntrinsics,
) -> Value {
  @runtime.make_interp_method_func(
    name="fromAsync",
    length=1,
    realm_state=Some(realm),
    fn(interp, ctor, args) raise {
      let (promise, resolve, reject) = promises.new_capability(interp)
      let loc = @token.Loc::default()
      try {
        let input = if args.length() > 0 { args[0] } else { Undefined }
        let mapper = if args.length() > 1 { args[1] } else { Undefined }
        let this_arg = if args.length() > 2 { args[2] } else { Undefined }
        guard mapper is Undefined || @runtime.is_callable(mapper) else {
          raise @errors.TypeError(
            message="Array.fromAsync mapper is not callable",
          )
        }
        let async_method = from_async_method(
          interp,
          input,
          realm.well_known_symbols.async_iterator,
        )
        let synchronous = async_method is Undefined
        let iterator_method = if synchronous {
          from_async_method(interp, input, realm.well_known_symbols.iterator)
        } else {
          async_method
        }
        let source = if iterator_method is Undefined {
          let object = to_object(input, interp)
          ArrayLike(
            object,
            @runtime.to_array_like_length_interp(object, interp),
          )
        } else {
          let iterator = interp.call_value(iterator_method, input, [], loc)
          guard @runtime.is_object_value(iterator) else {
            raise @errors.TypeError(message="Iterator is not an object")
          }
          let next = interp.get_property(iterator, "next", loc)
          Iterator(iterator, next, synchronous)
        }
        let length = match source {
          ArrayLike(_, n) => n
          _ => 0L
        }
        let output = if @runtime.is_constructor_value(ctor) {
          let ctor_args = match source {
            ArrayLike(_, _) => [Value::Number(length.to_double())]
            _ => []
          }
          interp.construct_value(ctor, ctor_args, loc)
        } else {
          let array = @runtime.make_array_with_prototype(
            [],
            realm.get_array_proto(),
          )
          let _ = interp.set_property(
            array,
            "length",
            Number(length.to_double()),
            loc,
            strict=true,
          )
          array
        }
        FromAsync(
          source, output, mapper, this_arg, promises, resolve, reject, realm,
        ).drive(interp, 0L, Next)
      } catch {
        error => {
          let reason = from_async_reason(interp, error)
          let _ = interp.call_value(reject, Undefined, [reason], loc)
        }
      }
      promise
    },
  )
}

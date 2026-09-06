///|
/// Promise operations for builtins, independent of mutable global properties.
/// Capture the intrinsic constructor and prototype during realm setup.
pub struct PromiseIntrinsics {
  ctor : Value
  prototype : Value
}

///|
pub fn PromiseIntrinsics::PromiseIntrinsics(
  ctor : Value,
  prototype : Value,
) -> PromiseIntrinsics {
  { ctor, prototype }
}

///|
pub fn PromiseIntrinsics::new_capability(
  self : PromiseIntrinsics,
  interp : Interpreter,
) -> (Value, Value, Value) {
  let data = new_promise_data()
  data.prototype = Some(self.prototype)
  let (resolve, reject) = create_resolving_functions(interp, data)
  (Promise(data), resolve, reject)
}

///|
/// PromiseResolve(%Promise%, value) followed by PerformPromiseThen.
/// Neither Promise.resolve nor a user-overridden Promise.prototype.then is read.
pub fn PromiseIntrinsics::await_value(
  self : PromiseIntrinsics,
  interp : Interpreter,
  value : Value,
  on_fulfill : Value,
  on_reject : Value,
) -> Unit raise Error {
  let loc = @token.Loc::default()
  let data = match value {
    Promise(data) if strict_equal(
        interp.get_property(value, "constructor", loc),
        self.ctor,
      ) => data
    _ => {
      let data = new_promise_data()
      data.prototype = Some(self.prototype)
      let (resolve, _) = create_resolving_functions(interp, data)
      let _ = interp.call_value(resolve, Undefined, [value], loc)
      data
    }
  }
  data.is_handled = true
  attach_promise_reactions(interp, data, on_fulfill, on_reject)
}

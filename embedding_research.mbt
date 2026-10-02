///|
fn research_number_argument(
  call : HostCallbackContext,
  argument : HostedValue?,
) -> Double raise {
  let owner = call.frame.owner
  owner.begin_nested(call.frame)
  let value = match argument {
    Some(value) => value
    None => HostedValue::HostedValue(owner, @runtime.Undefined)
  }
  owner.require_owner(value)
  value.expect_number() catch {
    HostedExpectedNumber => {
      // Authority/control were checked before allocating the mapped JS error.
      let thrown = @runtime.js_error_to_value_with_env(
        @errors.TypeError(message="Expected a numeric argument"),
        Some(owner.session.engine.interp.global),
      )
      // Engine-private registry, not mutable guest TypeError/prototype lookup.
      let prototype = match
        owner.session.engine.interp.realm_state.constructor_prototype_registry {
        @runtime.Object(registry) =>
          match registry.bag.properties.get("TypeError") {
            Some(@runtime.Object(_) as prototype) => prototype
            _ => fail("missing intrinsic TypeError prototype")
          }
        _ => fail("missing intrinsic constructor prototype registry")
      }
      match thrown {
        @runtime.Object(error) => error.prototype = prototype
        _ => fail("TypeError allocation did not produce an object")
      }
      raise call.guest_failure(HostedValue::HostedValue(owner, thrown))
    }
    error => raise error
  }
}

///|
/// Experimental unary Host adapter. Only strict Double conversion is supported.
/// Missing/non-number arguments throw JS TypeError; user errors are not mapped.
pub fn host_number_unary(
  f : (Double) -> Double raise,
) -> (HostCallbackContext, Array[HostedValue]) -> HostedValue raise {
  (call, args) => {
    let value = research_number_argument(call, args.get(0))
    let result = f(value)
    call.frame.owner.begin_nested(call.frame)
    HostedValue::HostedValue(call.frame.owner, @runtime.Number(result))
  }
}

///|
/// Experimental binary Host adapter. Both strict arguments precede user code.
pub fn host_number_binary(
  f : (Double, Double) -> Double raise,
) -> (HostCallbackContext, Array[HostedValue]) -> HostedValue raise {
  (call, args) => {
    let a = research_number_argument(call, args.get(0))
    let b = research_number_argument(call, args.get(1))
    let result = f(a, b)
    call.frame.owner.begin_nested(call.frame)
    HostedValue::HostedValue(call.frame.owner, @runtime.Number(result))
  }
}

///|
/// Retain a unary JS function with strict Double input/output. Calls are public
/// Hosted turns, not callback-context reentry: Running rejects Busy before argument creation.
pub fn js_number_unary(
  function : HostedValue,
) -> (Double) -> Double raise HostedError {
  arg => {
    let value = function.owner.number(arg)
    function.call([value]).expect_number()
  }
}

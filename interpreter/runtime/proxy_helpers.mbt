///|
/// Get a trap function from the proxy handler, or None if the trap is not defined.
/// Throws TypeError if the proxy has been revoked.
/// Uses the engine's ordinary Get path (interp.get_property) so accessor traps
/// and proxy-handler proxies are resolved with full language semantics.
pub fn get_proxy_trap(
  proxy_data : ProxyData,
  trap_name : String,
  interp : Interpreter,
) -> Value? raise Error {
  let handler = match proxy_data.handler {
    Some(h) => h
    None =>
      raise @errors.TypeError(
        message="Cannot perform '\{trap_name}' on a proxy that has been revoked",
      )
  }
  let _ = match proxy_data.target {
    Some(_) => ()
    None =>
      raise @errors.TypeError(
        message="Cannot perform '\{trap_name}' on a proxy that has been revoked",
      )
  }
  // Use engine-level Get (GetMethod semantics per ES §10.5): this traverses
  // the prototype chain, invokes accessor getters, and handles proxy handlers
  // that are themselves proxies.
  let trap = interp.get_property(handler, trap_name, @token.Loc::default())
  match trap {
    Undefined | Null => None
    _ =>
      if is_callable(trap) {
        Some(trap)
      } else {
        raise @errors.TypeError(
          message="'\{trap_name}' on proxy: trap is not a function",
        )
      }
  }
}

///|
/// Get the target of a proxy, throwing TypeError if revoked.
pub fn get_proxy_target(proxy_data : ProxyData) -> Value raise Error {
  match proxy_data.target {
    Some(t) => t
    None =>
      raise @errors.TypeError(
        message="Cannot perform operation on a proxy that has been revoked",
      )
  }
}

///|
/// Get the handler of a proxy, throwing TypeError if revoked.
pub fn get_proxy_handler(proxy_data : ProxyData) -> Value raise Error {
  match proxy_data.handler {
    Some(h) => h
    None =>
      raise @errors.TypeError(
        message="Cannot perform operation on a proxy that has been revoked",
      )
  }
}

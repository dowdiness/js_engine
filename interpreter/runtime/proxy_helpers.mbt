///|
/// Get a trap function from the proxy handler, or None if the trap is not defined.
/// Throws TypeError if the proxy has been revoked.
pub fn get_proxy_trap(
  proxy_data : ProxyData,
  trap_name : String,
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
  // Walk handler's prototype chain to find trap (per spec GetMethod)
  fn find_trap(obj : Value, name : String) -> Value? raise Error {
    match obj {
      Object(data) =>
        match data.properties.get(name) {
          Some(trap) =>
            match trap {
              Undefined => None
              Null => None
              Object(td) =>
                match td.callable {
                  Some(_) => Some(trap)
                  None =>
                    raise @errors.TypeError(
                      message="'\{name}' on proxy: trap is not a function",
                    )
                }
              _ =>
                raise @errors.TypeError(
                  message="'\{name}' on proxy: trap is not a function",
                )
            }
          None =>
            // Walk prototype chain
            match data.prototype {
              Object(_) => find_trap(data.prototype, name)
              _ => None
            }
        }
      _ => None
    }
  }
  find_trap(handler, trap_name)
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

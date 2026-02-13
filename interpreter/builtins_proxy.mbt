///|
/// Get a trap function from the proxy handler, or None if the trap is not defined.
/// Throws TypeError if the proxy has been revoked.
fn get_proxy_trap(
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
  match handler {
    Object(data) =>
      match data.properties.get(trap_name) {
        Some(trap) =>
          match trap {
            Undefined => None
            Null => None
            Object(td) =>
              match td.callable {
                Some(_) => Some(trap)
                None =>
                  raise @errors.TypeError(
                    message="'\{trap_name}' on proxy: trap is not a function",
                  )
              }
            _ =>
              raise @errors.TypeError(
                message="'\{trap_name}' on proxy: trap is not a function",
              )
          }
        None => None
      }
    _ => None
  }
}

///|
/// Get the target of a proxy, throwing TypeError if revoked.
fn get_proxy_target(proxy_data : ProxyData) -> Value raise Error {
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
fn get_proxy_handler(proxy_data : ProxyData) -> Value raise Error {
  match proxy_data.handler {
    Some(h) => h
    None =>
      raise @errors.TypeError(
        message="Cannot perform operation on a proxy that has been revoked",
      )
  }
}

///|
fn setup_proxy_builtins(env : Environment) -> Unit {
  // Proxy constructor: new Proxy(target, handler)
  let proxy_ctor : Value = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      ConstructorOnlyCallable("Proxy", fn(_interp, args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Cannot create proxy with a non-object as target or handler",
          )
        }
        let target = args[0]
        let handler = args[1]
        // Validate target is an object
        match target {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
          _ =>
            raise @errors.TypeError(
              message="Cannot create proxy with a non-object as target or handler",
            )
        }
        // Validate handler is an object
        match handler {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
          _ =>
            raise @errors.TypeError(
              message="Cannot create proxy with a non-object as target or handler",
            )
        }
        Proxy({ target: Some(target), handler: Some(handler) })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Proxy.revocable(target, handler)
  let revocable_func : Value = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      NativeCallable("revocable", fn(args) {
        if args.length() < 2 {
          raise @errors.TypeError(
            message="Cannot create proxy with a non-object as target or handler",
          )
        }
        let target = args[0]
        let handler = args[1]
        // Validate target is an object
        match target {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
          _ =>
            raise @errors.TypeError(
              message="Cannot create proxy with a non-object as target or handler",
            )
        }
        // Validate handler is an object
        match handler {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
          _ =>
            raise @errors.TypeError(
              message="Cannot create proxy with a non-object as target or handler",
            )
        }
        let proxy_data : ProxyData = { target: Some(target), handler: Some(handler) }
        let proxy_val : Value = Proxy(proxy_data)
        // Create revoke function that nullifies both slots
        let revoke_func : Value = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            NativeCallable("revoke", fn(_args) {
              proxy_data.target = None
              proxy_data.handler = None
              Undefined
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        let result_props : Map[String, Value] = {}
        result_props["proxy"] = proxy_val
        result_props["revoke"] = revoke_func
        Object({
          properties: result_props,
          symbol_properties: {},
          prototype: Null,
          callable: None,
          class_name: "Object",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Add Proxy.revocable as a static method
  match proxy_ctor {
    Object(data) => data.properties["revocable"] = revocable_func
    _ => ()
  }

  env.def_builtin("Proxy", proxy_ctor)
}

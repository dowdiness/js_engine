///|
fn setup_proxy_builtins(env : Environment) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  // Proxy constructor: new Proxy(target, handler)
  let proxy_ctor : Value = Value::Object({
    bag: {
      properties: {
        "name": Value::String_("Proxy"),
        "length": Value::Number(2.0),
      },
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: Null,
    callable: Some(
      ConstructorOnlyCallable("Proxy", fn(_interp, args) raise {
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
        Value::Proxy({
          target: Some(target),
          handler: Some(handler),
          is_callable: @runtime.is_callable(target),
        })
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })

  // Proxy.revocable(target, handler)
  let revocable_func : Value = @runtime.make_native_func(
    name="revocable",
    length=2,
    fn(args) raise {
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
      let proxy_data : ProxyData = {
        target: Some(target),
        handler: Some(handler),
        is_callable: @runtime.is_callable(target),
      }
      let proxy_val : Value = Value::Proxy(proxy_data)
      // Create revoke function that nullifies both slots
      let revoke_func : Value = {
        let func = @runtime.make_native_func(name="", length=0, fn(_args) {
          @runtime.revoke_proxy(proxy_data)
          Value::Undefined
        })
        let func_proto = env.get("[[FunctionPrototype]]") catch { _ => Null }
        match func {
          Object(data) => data.prototype = func_proto
          _ => ()
        }
        func
      }
      let result_props : Map[String, Value] = {}
      result_props["proxy"] = proxy_val
      result_props["revoke"] = revoke_func
      Value::Object({
        bag: {
          properties: result_props,
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {},
        },
        prototype: Null,
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
      })
    },
  )

  // Add Proxy.revocable as a static method
  match proxy_ctor {
    Object(data) => {
      data.bag.properties["revocable"] = revocable_func
      data.bag.descriptors["revocable"] = @runtime.builtin_method_desc()
    }
    _ => ()
  }

  env.def_builtin("Proxy", proxy_ctor)
}

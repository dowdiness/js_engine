// Per-realm canonical Proxy constructor used by the standard-library wiring
// and exact activation admission. Its construct callback is a synchronous
// runtime leaf: it validates inputs and allocates ProxyData without invoking
// interpreted guest code.

///|
fn canonical_proxy_constructor_construct(
  _interp : Interpreter,
  args : Array[Value],
) -> Value raise Error {
  if args.length() < 2 {
    raise @errors.TypeError(
      message="Cannot create proxy with a non-object as target or handler",
    )
  }
  let target = args[0]
  let handler = args[1]
  match target {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
    _ =>
      raise @errors.TypeError(
        message="Cannot create proxy with a non-object as target or handler",
      )
  }
  match handler {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
    _ =>
      raise @errors.TypeError(
        message="Cannot create proxy with a non-object as target or handler",
      )
  }
  Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: is_callable(target),
    is_constructor: is_constructor_value(target),
  })
}

///|
pub fn make_canonical_proxy_constructor(realm_state : RealmState) -> Value {
  match realm_state.canonical_proxy_constructor.val {
    Some(existing) => existing
    None => {
      let fixed_descriptor : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      let proxy_constructor : Value = Object({
        bag: {
          properties: { "name": String_("Proxy"), "length": Number(2.0) },
          symbol_properties: Map([]),
          descriptors: { "name": fixed_descriptor, "length": fixed_descriptor },
          symbol_descriptors: Map([]),
          internal_slots: Map([]),
          host_slots: Map([]),
        },
        prototype: Null,
        callable: Some(
          ConstructorOnlyCallable(
            "Proxy", canonical_proxy_constructor_construct,
          ),
        ),
        class_name: "Function",
        extensible: true,
        arraybuffer_state: None,
      })
      realm_state.canonical_proxy_constructor.val = Some(proxy_constructor)
      proxy_constructor
    }
  }
}

///|
#warnings("-unused_value")
fn RealmState::canonical_proxy_constructor_matches(
  self : RealmState,
  candidate : Value,
) -> Bool {
  match (self.canonical_proxy_constructor.val, candidate) {
    (Some(Object(expected)), Object(actual)) => physical_equal(expected, actual)
    _ => false
  }
}

///|
fn proxy_get_recursion_trust_construct(
  _interp : Interpreter,
  args : Array[Value],
) -> Value raise Error {
  guard args.length() == 2 else {
    raise @errors.TypeError(message="expected Proxy target and handler")
  }
  guard args[0]
    is (Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_)) &&
    args[1] is (Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_)) else {
    raise @errors.TypeError(message="expected object-like Proxy inputs")
  }
  Proxy({
    target: Some(args[0]),
    handler: Some(args[1]),
    is_callable: is_callable(args[0]),
    is_constructor: is_constructor_value(args[0]),
  })
}

///|
fn proxy_get_recursion_trust_test_interpreter() -> Interpreter {
  let interp = Interpreter::new()
  let proxy_constructor = make_canonical_proxy_constructor(interp.realm_state)
  interp.global.def_builtin(
    PROXY_GET_RECURSION_CONSTRUCTOR_NAME,
    proxy_constructor,
  )
  match interp.global_this {
    Object(global_object) =>
      global_object.bag.properties[PROXY_GET_RECURSION_CONSTRUCTOR_NAME] = proxy_constructor
    _ => ()
  }
  interp
}

///|
fn proxy_get_recursion_trust_test_plan() -> (
  Array[@ast.Stmt],
  ProxyGetRecursionPlan,
) raise {
  let stmts = @parser.parse(proxy_get_recursion_exact_source()).stmts
  match classify_proxy_get_recursion_program(stmts) {
    Some(plan) => (stmts, plan)
    None => fail("expected an exact Proxy get recursion plan")
  }
}

///|
fn proxy_get_recursion_trust_execute_root_setup(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Unit raise {
  let ctx : ExecContext = { strict: false, current_generator: None }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  for index in 0..<3 {
    match interp.exec_stmt(ctx, stmts[index], interp.global) {
      Normal(_) => ()
      _ => fail("exact Proxy root setup must complete normally")
    }
  }
}

///|
fn proxy_get_recursion_trust_test_registry(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
  plan : ProxyGetRecursionPlan,
) -> TrustedProxyGetRecursionRegistry raise {
  let preflight = match interp.preflight_proxy_get_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free Proxy get preflight")
  }
  proxy_get_recursion_trust_execute_root_setup(interp, stmts)
  interp.seal_proxy_get_recursion_registry(preflight, stmts)
}

///|
fn proxy_get_recursion_trust_trap(
  capture : TrustedProxyGetCapture,
) -> Value raise {
  guard capture.handler is Object(handler_data) &&
    handler_data.bag.properties.get(PROXY_GET_RECURSION_TRAP_NAME) is Some(trap) else {
    fail("expected the sealed Proxy get trap")
  }
  trap
}

///|
test "Proxy get trust preflight requires fresh bindings and native constructor provenance" {
  let (_, plan) = proxy_get_recursion_trust_test_plan()
  let fresh = proxy_get_recursion_trust_test_interpreter()
  inspect(
    fresh.preflight_proxy_get_recursion_program(plan) is Some(_),
    content="true",
  )

  let occupied = proxy_get_recursion_trust_test_interpreter()
  occupied.global.def("p", Undefined, LetBinding)
  inspect(
    occupied.preflight_proxy_get_recursion_program(plan) is None,
    content="true",
  )

  let replaced = proxy_get_recursion_trust_test_interpreter()
  replaced.global.def_builtin(
    PROXY_GET_RECURSION_CONSTRUCTOR_NAME,
    make_native_func(name="Proxy", _args => Undefined),
  )
  inspect(
    replaced.preflight_proxy_get_recursion_program(plan) is None,
    content="true",
  )

  let same_name_alternate = proxy_get_recursion_trust_test_interpreter()
  same_name_alternate.global.def_builtin(
    PROXY_GET_RECURSION_CONSTRUCTOR_NAME,
    Object({
      bag: PropertyBag(),
      prototype: Null,
      callable: Some(
        ConstructorOnlyCallable(
          PROXY_GET_RECURSION_CONSTRUCTOR_NAME,
          proxy_get_recursion_trust_construct,
        ),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
  )
  inspect(
    same_name_alternate.preflight_proxy_get_recursion_program(plan) is None,
    content="true",
  )
}

///|
test "Proxy get trust preflight requires constructor mirror identity" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let (_, plan) = proxy_get_recursion_trust_test_plan()
  guard interp.global_this is Object(global_object) else {
    fail("expected the canonical global object")
  }
  global_object.bag.properties[PROXY_GET_RECURSION_CONSTRUCTOR_NAME] = Undefined
  inspect(
    interp.preflight_proxy_get_recursion_program(plan) is None,
    content="true",
  )
}

///|
test "Proxy get trust seals Proxy target handler trap and request identities" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let registry = proxy_get_recursion_trust_test_registry(interp, stmts, plan)
  let proxy = registry.require_proxy(interp)
  let capture = registry.capture_get(
    interp,
    proxy,
    String_(plan.property_name),
    proxy,
  )
  let trap = proxy_get_recursion_trust_trap(capture)
  let admitted = registry.require_resolved_trap(interp, capture, trap)
  inspect(admitted.counter_name, content="n")
  inspect(admitted.proxy_name, content="p")
  inspect(admitted.property_name, content="x")

  let wrong_key = try {
    let _ = registry.capture_get(interp, proxy, String_("y"), proxy)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(wrong_key, content="rejected")
}

///|
test "Proxy get trust rejects binding slots handler and target drift" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let registry = proxy_get_recursion_trust_test_registry(interp, stmts, plan)
  let proxy = registry.require_proxy(interp)
  let proxy_data = match proxy {
    Proxy(found) => found
    _ => fail("expected sealed Proxy")
  }
  let target = match proxy_data.target {
    Some(found) => found
    None => fail("expected sealed Proxy target")
  }
  let handler = match proxy_data.handler {
    Some(found) => found
    None => fail("expected sealed Proxy handler")
  }
  let handler_data = match handler {
    Object(found) => found
    _ => fail("expected ordinary Proxy handler")
  }
  let proxy_binding = match interp.global.bindings.get(plan.proxy_name) {
    Some(found) => found
    None => fail("expected sealed Proxy binding")
  }
  let trap = handler_data.bag.properties
    .get(PROXY_GET_RECURSION_TRAP_NAME)
    .unwrap_or(Undefined)

  proxy_binding.value = Undefined
  let binding_result = try {
    let _ = registry.require_proxy(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  proxy_binding.value = proxy

  proxy_data.target = None
  let slot_result = try {
    let _ = registry.require_proxy(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  proxy_data.target = Some(target)

  handler_data.bag.properties[PROXY_GET_RECURSION_TRAP_NAME] = Undefined
  let handler_result = try {
    let _ = registry.require_proxy(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  handler_data.bag.properties[PROXY_GET_RECURSION_TRAP_NAME] = trap

  guard target is Object(target_data) else { fail("expected ordinary target") }
  target_data.bag.properties["extra"] = Number(1.0)
  let target_result = try {
    let _ = registry.require_proxy(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  target_data.bag.properties.remove("extra")

  inspect(binding_result, content="rejected")
  inspect(slot_result, content="rejected")
  inspect(handler_result, content="rejected")
  inspect(target_result, content="rejected")
  let _ = registry.require_proxy(interp)
}

///|
test "resolved Proxy trap uses captured target and handler without rereading mutable slots" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let registry = proxy_get_recursion_trust_test_registry(interp, stmts, plan)
  let proxy = registry.require_proxy(interp)
  let capture = registry.capture_get(
    interp,
    proxy,
    String_(plan.property_name),
    proxy,
  )
  let trap = proxy_get_recursion_trust_trap(capture)
  let proxy_data = match proxy {
    Proxy(found) => found
    _ => fail("expected sealed Proxy")
  }
  proxy_data.target = None
  proxy_data.handler = None

  let admitted = registry.require_resolved_trap(interp, capture, trap)
  inspect(admitted.property_name, content="x")
  let admitted_call = registry.require_trap_call(
    interp,
    trap,
    capture.handler,
    [capture.target, capture.property_key, capture.receiver],
  )
  inspect(admitted_call.property_name, content="x")
  let next_access = try {
    let _ = registry.require_proxy(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(next_access, content="rejected")
}

///|
test "Proxy get trust rejects constructor drift before sealing" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let preflight = match interp.preflight_proxy_get_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free Proxy get preflight")
  }
  interp.global.def_builtin(
    PROXY_GET_RECURSION_CONSTRUCTOR_NAME,
    Object({
      bag: PropertyBag(),
      prototype: Null,
      callable: Some(
        ConstructorOnlyCallable(
          PROXY_GET_RECURSION_CONSTRUCTOR_NAME,
          proxy_get_recursion_trust_construct,
        ),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
  )
  proxy_get_recursion_trust_execute_root_setup(interp, stmts)
  let result = try {
    let _ = interp.seal_proxy_get_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
}

///|
test "Proxy get trust rejects post-seal constructor mirror drift" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let registry = proxy_get_recursion_trust_test_registry(interp, stmts, plan)
  guard interp.global_this is Object(global_object) else {
    fail("expected the canonical global object")
  }
  global_object.bag.properties[PROXY_GET_RECURSION_CONSTRUCTOR_NAME] = Undefined
  let result = try {
    let _ = registry.require_proxy(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
}

///|
test "Proxy get trust rejects ThrowTypeError drift before sealing" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let original = make_native_func(name="original ThrowTypeError", _args => {
    Undefined
  })
  let replacement = make_native_func(name="replacement ThrowTypeError", _args => {
    Undefined
  })
  interp.global.def_builtin("[[ThrowTypeError]]", original)
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let preflight = match interp.preflight_proxy_get_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free Proxy get preflight")
  }
  guard interp.global.bindings.get("[[ThrowTypeError]]") is Some(binding) else {
    fail("expected the direct ThrowTypeError binding")
  }
  binding.value = replacement
  proxy_get_recursion_trust_execute_root_setup(interp, stmts)
  let result = try {
    let _ = interp.seal_proxy_get_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
}

///|
test "Proxy get trust rejects post-seal trap source identity drift" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  interp.realm_state.active_source_identity.val = Some("sealed source")
  let (stmts, plan) = proxy_get_recursion_trust_test_plan()
  let registry = proxy_get_recursion_trust_test_registry(interp, stmts, plan)
  let proxy = registry.require_proxy(interp)
  let capture = registry.capture_get(
    interp,
    proxy,
    String_(plan.property_name),
    proxy,
  )
  let trap = proxy_get_recursion_trust_trap(capture)
  guard trap is Object(trap_data) &&
    trap_data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID)
    is Some(Array(metadata)) &&
    metadata.elements.length() > FUNCTION_SOURCE_IDENTITY_IDX else {
    fail("expected packed source metadata on the sealed Proxy trap")
  }
  metadata.elements[FUNCTION_SOURCE_IDENTITY_IDX] = String_("drifted source")
  let result = try {
    let _ = registry.require_proxy(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
}

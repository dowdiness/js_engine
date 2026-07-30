///|
fn getter_recursion_trust_test_source() -> String {
  "let n=256;" +
  "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
  "o.x;"
}

///|
fn getter_recursion_trust_test_plan(
  source : String,
) -> (Array[@ast.Stmt], GetterRecursionPlan) raise {
  let stmts = @parser.parse(source).stmts
  match classify_getter_recursion_program(stmts) {
    Some(plan) => (stmts, plan)
    None => fail("expected an exact getter-recursion plan")
  }
}

///|
fn getter_recursion_trust_execute_root_setup(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Unit raise {
  let ctx : ExecContext = { strict: false, current_generator: None }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  for index in 0..<2 {
    match interp.exec_stmt(ctx, stmts[index], interp.global) {
      Normal(_) => ()
      _ => fail("exact getter root setup must complete normally")
    }
  }
}

///|
fn getter_recursion_trust_test_registry(
  interp : Interpreter,
  stmts : Array[@ast.Stmt],
  plan : GetterRecursionPlan,
) -> TrustedGetterRecursionRegistry raise {
  let preflight = match interp.preflight_getter_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free getter preflight")
  }
  getter_recursion_trust_execute_root_setup(interp, stmts)
  interp.seal_getter_recursion_registry(preflight, stmts)
}

///|
test "getter recursion trust preflight accepts only fresh canonical bindings" {
  let (_, plan) = getter_recursion_trust_test_plan(
    getter_recursion_trust_test_source(),
  )
  let fresh = Interpreter::new()
  inspect(
    fresh.preflight_getter_recursion_program(plan) is Some(_),
    content="true",
  )
  let occupied = Interpreter::new()
  occupied.global.def("n", Number(1.0), LetBinding)
  inspect(
    occupied.preflight_getter_recursion_program(plan) is None,
    content="true",
  )
}

///|
test "getter recursion trust seals target descriptor getter and receiver identities" {
  let interp = Interpreter::new()
  let (stmts, plan) = getter_recursion_trust_test_plan(
    getter_recursion_trust_test_source(),
  )
  let registry = getter_recursion_trust_test_registry(interp, stmts, plan)
  let target = registry.require_target(interp)
  guard target is Object(target_data) &&
    target_data.bag.descriptors.get("x") is Some(descriptor) &&
    descriptor.getter is Some(getter) else {
    fail("expected the sealed own accessor")
  }
  let admitted = registry.require_getter(interp, getter, target)
  inspect(admitted.counter_name, content="n")
  inspect(admitted.object_name, content="o")
  inspect(admitted.property_name, content="x")
}

///|
test "getter recursion trust rejects binding and descriptor drift" {
  let interp = Interpreter::new()
  let (stmts, plan) = getter_recursion_trust_test_plan(
    getter_recursion_trust_test_source(),
  )
  let registry = getter_recursion_trust_test_registry(interp, stmts, plan)
  let target = registry.require_target(interp)
  guard target is Object(target_data) &&
    interp.global.bindings.get("o") is Some(object_binding) &&
    target_data.bag.descriptors.get("x") is Some(descriptor) else {
    fail("expected sealed getter storage")
  }

  object_binding.value = Undefined
  let binding_result = try {
    let _ = registry.require_target(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  object_binding.value = target

  target_data.bag.descriptors["x"] = { ..descriptor, getter: None }
  let descriptor_result = try {
    let _ = registry.require_target(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  target_data.bag.descriptors["x"] = descriptor

  inspect(binding_result, content="rejected")
  inspect(descriptor_result, content="rejected")
  let _ = registry.require_target(interp)
}

///|
test "getter recursion trust rejects ThrowTypeError drift before sealing" {
  let interp = Interpreter::new()
  let original = make_native_func(name="original ThrowTypeError", _args => {
    Undefined
  })
  let replacement = make_native_func(name="replacement ThrowTypeError", _args => {
    Undefined
  })
  interp.global.def_builtin("[[ThrowTypeError]]", original)
  let (stmts, plan) = getter_recursion_trust_test_plan(
    getter_recursion_trust_test_source(),
  )
  let preflight = match interp.preflight_getter_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free getter preflight")
  }
  guard interp.global.bindings.get("[[ThrowTypeError]]") is Some(binding) else {
    fail("expected the direct ThrowTypeError binding")
  }
  binding.value = replacement
  getter_recursion_trust_execute_root_setup(interp, stmts)
  let result = try {
    let _ = interp.seal_getter_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(result, content="rejected")
}

///|
test "getter recursion trust rejects post-seal source identity drift" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("sealed source")
  let (stmts, plan) = getter_recursion_trust_test_plan(
    getter_recursion_trust_test_source(),
  )
  let registry = getter_recursion_trust_test_registry(interp, stmts, plan)
  let target = registry.require_target(interp)
  guard target is Object(target_data) &&
    target_data.bag.descriptors.get("x") is Some(descriptor) &&
    descriptor.getter is Some(getter) &&
    getter is Object(getter_data) &&
    getter_data.bag.symbol_properties.get(
      FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID,
    )
    is Some(Array(metadata)) &&
    metadata.elements.length() > FUNCTION_SOURCE_IDENTITY_IDX else {
    fail("expected packed source metadata on the sealed getter")
  }
  metadata.elements[FUNCTION_SOURCE_IDENTITY_IDX] = String_("drifted source")
  let result = try {
    let _ = registry.require_getter(interp, getter, target)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="getter recursion candidate source identity changed after sealing",
  )
}

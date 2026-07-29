///|
fn numeric_recursion_trust_test_plan(
  source : String,
) -> (Array[@ast.Stmt], NumericRecursionPlan) raise {
  let stmts = @parser.parse(source).stmts
  match classify_numeric_recursion_program(stmts) {
    Some(plan) => (stmts, plan)
    None => fail("expected an exact numeric-recursion plan")
  }
}

///|
test "numeric recursion trust preflight accepts the canonical global without effects" {
  let interp = Interpreter::new()
  let (_, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  match interp.preflight_numeric_recursion_program(plan) {
    Some(preflight) => inspect(preflight.plan.entry.name, content="f")
    None => fail("the canonical interpreter global must be eligible")
  }
}

///|
test "numeric recursion trust preflight rejects a with global without traps" {
  let interp = Interpreter::new()
  let has_calls : Ref[Int] = { val: 0 }
  let get_calls : Ref[Int] = { val: 0 }
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let handler = make_object(
    {
      "has": make_native_func(name="has", _args => {
        has_calls.val += 1
        Bool(true)
      }),
      "get": make_native_func(name="get", _args => {
        get_calls.val += 1
        Undefined
      }),
    },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  interp.global.with_object = Some(
    Proxy({
      target: Some(target),
      handler: Some(handler),
      is_callable: false,
      is_constructor: false,
    }),
  )
  let (_, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )

  inspect(
    interp.preflight_numeric_recursion_program(plan) is None,
    content="true",
  )
  inspect(has_calls.val, content="0")
  inspect(get_calls.val, content="0")
}

///|
test "numeric recursion trust preflight rejects a ModuleExportCell without calling it" {
  let interp = Interpreter::new()
  let cell_calls : Ref[Int] = { val: 0 }
  let cell : Value = Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: Some(
      NonConstructableCallable("test export cell", _args => {
        cell_calls.val += 1
        Undefined
      }),
    ),
    class_name: "ModuleExportCell",
    extensible: false,
    arraybuffer_state: None,
  })
  interp.global.def_builtin("[[ThrowTypeError]]", cell)
  let (_, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )

  inspect(
    interp.preflight_numeric_recursion_program(plan) is None,
    content="true",
  )
  inspect(cell_calls.val, content="0")
}

///|
test "numeric recursion trust preflight rejects an existing lexical binding" {
  let interp = Interpreter::new()
  interp.global.def("f", Number(7.0), LetBinding)
  let (_, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )

  inspect(
    interp.preflight_numeric_recursion_program(plan) is None,
    content="true",
  )
}

///|
test "numeric recursion trust seals the fresh self declaration identity" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  let syntax = registry.require_callee(interp, callee)
  guard callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    fail("trusted declaration must retain its UserFunc capability")
  }

  inspect(registry.throw_type_error is None, content="true")
  inspect(syntax.name, content="f")
  inspect(syntax.parameter, content="n")
  match data.name {
    Some(name) => inspect(name, content="f")
    None => fail("trusted function must retain its declared name")
  }
  inspect(physical_equal(data.closure, interp.global), content="true")
  let by_name = registry.require_named(interp, "f")
  match by_name {
    Object(found) =>
      inspect(physical_equal(found, callee_object), content="true")
    _ => fail("named lookup must return the trusted Object capability")
  }
}

///|
test "numeric recursion trust seals both fresh mutual declarations" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(m){if(m===0)return 0;return 1+f(m-1);}" +
    "f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let entry_callee = registry.require_named(interp, "f")
  let peer_callee = registry.require_named(interp, "g")
  let entry = registry.require_callee(interp, entry_callee)
  let peer = registry.require_callee(interp, peer_callee)
  guard entry_callee is Object(entry_object) &&
    entry_object.callable is Some(UserFunc(entry_data)) &&
    peer_callee is Object(peer_object) &&
    peer_object.callable is Some(UserFunc(peer_data)) else {
    fail("trusted mutual declarations must remain UserFunc capabilities")
  }

  inspect(entry.recursive_callee, content="g")
  inspect(peer.recursive_callee, content="f")
  inspect(physical_equal(entry_data.closure, interp.global), content="true")
  inspect(physical_equal(peer_data.closure, interp.global), content="true")
  inspect(physical_equal(entry_object, peer_object), content="false")
}

///|
test "numeric recursion trust snapshots an existing var and rejects its stale identity" {
  let interp = Interpreter::new()
  let stale = make_native_func(name="stale f", _args => Undefined)
  interp.global.def("f", stale, VarBinding)
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None =>
      fail("an initialized var binding must remain eligible for re-hoisting")
  }
  guard stale is Object(stale_object) &&
    preflight.previous_entry_object is Some(snapshot) else {
    fail("preflight must retain the previous ObjectData identity")
  }
  inspect(physical_equal(snapshot, stale_object), content="true")
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  guard callee is Object(fresh_object) else {
    fail("trusted named lookup must return an Object capability")
  }

  inspect(physical_equal(fresh_object, stale_object), content="false")
  let stale_result = try {
    let _ = registry.require_callee(interp, stale)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(stale_result, content="rejected")
}

///|
test "numeric recursion trust rejects a clone that shares trusted FuncData" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  guard callee is Object(trusted_object) &&
    trusted_object.callable is Some(UserFunc(data)) else {
    fail("trusted named lookup must return a UserFunc capability")
  }
  let clone = make_func(data)
  guard clone is Object(cloned_object) else {
    fail("make_func must return an Object capability")
  }

  inspect(physical_equal(cloned_object, trusted_object), content="false")
  let clone_result = try {
    let _ = registry.require_callee(interp, clone)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  inspect(clone_result, content="rejected")
  let original = registry.require_callee(interp, callee)
  inspect(original.name, content="f")
}

///|
test "numeric recursion trust rejects post-seal FuncData array mutation" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  guard callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("trusted named lookup must return a UserFunc capability")
  }

  let original_parameter = data.params[0]
  data.params[0] = "changed"
  let parameter_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.params[0] = original_parameter

  let original_base_case = data.body[0]
  data.body[0] = @parser.parse("0;").stmts[0]
  let body_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.body[0] = original_base_case

  inspect(
    parameter_result,
    content="numeric recursion candidate no longer has exact UserFunc provenance",
  )
  inspect(
    body_result,
    content="numeric recursion candidate no longer has exact UserFunc provenance",
  )
}

///|
test "numeric recursion trust revalidates binding and mirror on every lookup" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  guard callee is Object({ callable: Some(UserFunc(data)), .. }) &&
    interp.global.bindings.get("f") is Some(binding) &&
    interp.global_this is Object(global_object) else {
    fail("expected trusted global UserFunc provenance")
  }
  let clone = make_func(data)

  let original_binding = binding.value
  binding.value = clone
  let binding_result = try {
    let _ = registry.require_named(interp, "f")
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  binding.value = original_binding

  let original_mirror = global_object.bag.properties["f"]
  global_object.bag.properties["f"] = clone
  let mirror_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  global_object.bag.properties["f"] = original_mirror

  inspect(
    binding_result,
    content="numeric recursion candidate diverged from its global binding",
  )
  inspect(
    mirror_result,
    content="numeric recursion candidate diverged from its global mirror",
  )
}

///|
test "numeric recursion trust rejects a replacement canonical global on lookup" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  let replacement_global = make_object(
    { "f": callee },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let replacement_interp : Interpreter = {
    ..interp,
    global_this: replacement_global,
  }
  interp.global.interpreter_context = Some(replacement_interp)
  let result = try {
    let _ = registry.require_named(replacement_interp, "f")
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion trusted global changed after sealing",
  )
}

///|
test "numeric recursion trust rejects seal against a different program" {
  let interp = Interpreter::new()
  let (_, admitted_plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let mismatched_stmts = @parser.parse(
      "function g(m){if(m===0)return 0;return 1+g(m-1);}g(256);",
    ).stmts
  let preflight = match
    interp.preflight_numeric_recursion_program(admitted_plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(mismatched_stmts, interp.global, false)
  let result = try {
    let _ = interp.seal_numeric_recursion_registry(preflight, mismatched_stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion program no longer matches its preflight plan",
  )
}

///|
test "numeric recursion trust rejects a binding and global mirror mismatch" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  guard interp.global.bindings.get("f") is Some(binding) &&
    binding.value is Object(hoisted) &&
    hoisted.callable is Some(UserFunc(data)) else {
    fail("expected a hoisted UserFunc binding")
  }
  binding.value = make_func(data)
  let result = try {
    let _ = interp.seal_numeric_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion declaration binding diverged from its global mirror",
  )
}

///|
test "numeric recursion trust rejects foreign realm metadata after context restoration" {
  let interp = Interpreter::new()
  let foreign = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.global.interpreter_context = Some(foreign)
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.global.interpreter_context = Some(interp)
  let result = try {
    let _ = interp.seal_numeric_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion UserFunc realm provenance changed during root hoisting",
  )
}

///|
test "numeric recursion trust rejects source identity drift with stable realm metadata" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("preflight source")
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.realm_state.active_source_identity.val = Some("hoist source")
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.realm_state.active_source_identity.val = Some("preflight source")
  guard interp.global.bindings.get("f") is Some({ value: callee, .. }) else {
    fail("expected the hoisted function binding")
  }
  inspect(
    numeric_recursion_realm_protos_match(
      preflight.expected_realm_protos,
      callee_realm_protos(callee),
    ),
    content="true",
  )
  match function_source_identity(callee) {
    Some(source) => inspect(source, content="hoist source")
    None => fail("expected hoist source identity metadata")
  }
  let result = try {
    let _ = interp.seal_numeric_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion UserFunc source identity changed during root hoisting",
  )
}

///|
test "numeric recursion trust rejects post-seal source identity drift on named lookup" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("sealed source")
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  guard callee is Object(data) &&
    data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID)
    is Some(Array(metadata)) &&
    metadata.elements.length() > FUNCTION_SOURCE_IDENTITY_IDX else {
    fail("expected packed source metadata on the trusted function")
  }
  metadata.elements[FUNCTION_SOURCE_IDENTITY_IDX] = String_("drifted source")
  let result = try {
    let _ = registry.require_named(interp, "f")
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion candidate source identity changed after sealing",
  )
}

///|
test "numeric recursion trust rejects post-seal realm metadata drift on callee lookup" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  let callee = registry.require_named(interp, "f")
  guard callee is Object(data) &&
    data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID)
    is Some(Array(metadata)) &&
    metadata.elements.length() > REALM_PROTO_IDX_OBJECT else {
    fail("expected packed realm metadata on the trusted function")
  }
  metadata.elements[REALM_PROTO_IDX_OBJECT] = make_object(
    Map([]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion candidate realm provenance changed after sealing",
  )
}

///|
test "numeric recursion trust rejects a noncanonical global at seal without traps" {
  let interp = Interpreter::new()
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let trap_calls : Ref[Int] = { val: 0 }
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let handler = make_object(
    {
      "has": make_native_func(name="has", _args => {
        trap_calls.val += 1
        Bool(true)
      }),
    },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  interp.global.with_object = Some(
    Proxy({
      target: Some(target),
      handler: Some(handler),
      is_callable: false,
      is_constructor: false,
    }),
  )
  let result = try {
    let _ = interp.seal_numeric_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    result,
    content="numeric recursion global changed after callback-free preflight",
  )
  inspect(trap_calls.val, content="0")
}

///|
test "numeric recursion trust preserves the exact ThrowTypeError identity" {
  let interp = Interpreter::new()
  let throw_calls : Ref[Int] = { val: 0 }
  let throw_type_error = make_native_func(name="trusted ThrowTypeError", _args => {
    throw_calls.val += 1
    Undefined
  })
  interp.global.def_builtin("[[ThrowTypeError]]", throw_type_error)
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_numeric_recursion_registry(preflight, stmts)
  guard throw_type_error is Object(expected) &&
    registry.throw_type_error is Some(Object(actual)) else {
    fail("trusted ThrowTypeError must remain an Object identity")
  }

  inspect(physical_equal(actual, expected), content="true")
  inspect(throw_calls.val, content="0")
}

///|
test "numeric recursion trust rejects ThrowTypeError identity drift" {
  let interp = Interpreter::new()
  let original = make_native_func(name="original ThrowTypeError", _args => {
    Undefined
  })
  let replacement = make_native_func(name="replacement ThrowTypeError", _args => {
    Undefined
  })
  interp.global.def_builtin("[[ThrowTypeError]]", original)
  let (stmts, plan) = numeric_recursion_trust_test_plan(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let preflight = match interp.preflight_numeric_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free preflight")
  }
  guard interp.global.bindings.get("[[ThrowTypeError]]") is Some(binding) else {
    fail("expected direct ThrowTypeError binding")
  }
  binding.value = replacement
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let result = try {
    let _ = interp.seal_numeric_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }

  inspect(result, content="rejected")
}

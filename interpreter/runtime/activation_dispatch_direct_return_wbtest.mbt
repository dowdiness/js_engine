///|
fn direct_return_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
const DIRECT_RETURN_TEST_SOURCE = "function f(n){if(n===0)return \"done\";return f(n-1);}f(256);"

///|
const DIRECT_RETURN_LEAF_TEST_SOURCE = "function leaf(){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);"

///|
const DIRECT_RETURN_LEAF_THROW_SOURCE = "function leaf(){throw \"boom\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);"

///|
test "direct-return admission recognizes the exact ordinary function shape" {
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact direct-return shape to be admitted")
  }
  inspect(plan.entry.syntax.name, content="f")
  inspect(plan.entry.syntax.parameter, content="n")
  inspect(plan.entry.syntax.recursive_callee, content="f")
  inspect(plan.initial_argument, content="256")
  match plan.entry.syntax.base_completion {
    DirectReturnBaseValue(DirectReturnClosedString(value)) =>
      inspect(value, content="done")
    _ => fail("expected a closed string return completion")
  }
  let interp = Interpreter::new()
  inspect(
    root_admission_test_kind(
      interp.classify_activation_dispatch_root_program(stmts),
    ),
    content="direct-return",
  )
}

///|
test "direct-return admission recognizes the closed throw twin" {
  let stmts = direct_return_test_program(
    "function f(n){if(n===0)throw \"boom\";return f(n-1);}f(256);",
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact direct-return throw shape to be admitted")
  }
  match plan.entry.syntax.base_completion {
    DirectReturnBaseThrow(DirectReturnClosedString(value)) =>
      inspect(value, content="boom")
    _ => fail("expected a closed string throw completion")
  }
}

///|
test "direct-return admission recognizes a sealed leaf callee" {
  let stmts = direct_return_test_program(DIRECT_RETURN_LEAF_TEST_SOURCE)
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact direct-return leaf shape to be admitted")
  }
  inspect(plan.entry.syntax.name, content="f")
  let leaf = match plan.leaf {
    Some(found) => found
    None => fail("expected a sealed direct-return leaf plan")
  }
  inspect(leaf.syntax.name, content="leaf")
  inspect(leaf.declaration_index, content="0")
  inspect(plan.entry.declaration_index, content="1")
  match plan.entry.syntax.base_completion {
    DirectReturnBaseLeafCall(name, _) => inspect(name, content="leaf")
    _ => fail("expected the base completion to call the sealed leaf")
  }
  match leaf.syntax.completion {
    DirectReturnBaseValue(DirectReturnClosedString(value)) =>
      inspect(value, content="done")
    _ => fail("expected the leaf to return a closed string")
  }
}

///|
test "direct-return leaf admission rejects exact-shape near misses" {
  for
    source in [
      "function f(n){if(n===0)return leaf();return f(n-1);}function leaf(){return \"done\";}f(256);",
      "function leaf(x){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);",
      "function leaf(){return String(\"done\");}function f(n){if(n===0)return leaf();return f(n-1);}f(256);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return leaf(0);return f(n-1);}f(256);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return (leaf)();return f(n-1);}f(256);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(255);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);0;",
      "function leaf(){\"use strict\";return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);",
    ] {
    guard classify_direct_return_recursion_program(
        direct_return_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted direct-return leaf near miss: " + source)
    }
  }
}

///|
test "direct-return admission rejects exact-shape near misses" {
  for
    source in [
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);", "function f(n){if(n==0)return \"done\";return f(n-1);}f(256);",
      "function f(n){if(n===0){return \"done\";}return f(n-1);}f(256);", "function f(n){if(n===0)return n;return f(n-1);}f(256);",
      "function f(n){if(n===0)return \"done\";return f(n-2);}f(256);", "function f(n){if(n===0)return \"done\";return (f)(n-1);}f(256);",
      "function f(n){if(n===0)return \"done\";return f(n-1);}f(255);", "function f(n){if(n===0)return \"done\";return f(n-1);}f(256);0;",
      "function f(n=0){if(n===0)return \"done\";return f(n-1);}f(256);", "function* f(n){if(n===0)return \"done\";return f(n-1);}f(256);",
      "function eval(n){if(n===0)return \"done\";return eval(n-1);}eval(256);", "function arguments(n){if(n===0)return \"done\";return arguments(n-1);}arguments(256);",
      "function f(n){return f(n-1);if(n===0)return \"done\";}f(256);", "function f(n){if(n===0)return \"done\";return f(n-1);}f(256,0);",
      "function f(n){if(n===0)return \"done\";return f(n-1);}({f:f}).f(256);", "function f(n){if(n===0)return \"done\";return f(n-1);}g(256);",
      "function f(n){\"use strict\";if(n===0)return \"done\";return f(n-1);}f(256);",
    ] {
    guard classify_direct_return_recursion_program(
        direct_return_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted direct-return near miss: " + source)
    }
  }
}

///|
fn direct_return_observation_fixture_for_source(
  interp : Interpreter,
  probe : DispatchObservationProbe,
  source : String,
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  let stmts = direct_return_test_program(source)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact direct-return preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  (shell, stmts, { strict: false, current_generator: None })
}

///|
fn direct_return_observation_fixture(
  interp : Interpreter,
  probe : DispatchObservationProbe,
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_TEST_SOURCE,
  )
}

///|
fn run_direct_return_shell_source_once(
  interp : Interpreter,
  source : String,
  expected_count : Int,
) -> Value raise Error {
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp, probe, source,
  )
  let value = activation_dispatch_root_value(
    shell.drive_root_program(stmts, ctx),
  )
  expect_dispatch_observation_balanced(probe, expected_count)
  inspect(shell.cleanup_stack.length(), content="0")
  value
}

///|
fn run_direct_return_shell_once(interp : Interpreter) -> Value raise Error {
  run_direct_return_shell_source_once(interp, DIRECT_RETURN_TEST_SOURCE, 257)
}

///|
test "direct-return observation balances every nested ordinary call" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 109)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture(interp, probe)
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other => fail("expected direct-return completion, got " + other.to_string())
  }
  expect_nested_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 109)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return leaf catalog balances entry and leaf activations" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 127)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_LEAF_TEST_SOURCE,
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("expected direct-return leaf result, got " + other.to_string())
  }
  expect_dispatch_observation_balanced(probe, 258)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 127)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return closed throw crosses depth 256 without host recursion" {
  let interp = Interpreter::new()
  let source = "function f(n){if(n===0)throw \"boom\";return f(n-1);}f(256);"
  let result = try {
    let _ = interp.run(direct_return_test_program(source))
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="boom")
}

///|
test "direct-return leaf throw crosses every admitted return continuation" {
  let interp = Interpreter::new()
  let result = try {
    let _ = interp.run(
      direct_return_test_program(DIRECT_RETURN_LEAF_THROW_SOURCE),
    )
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="boom")
}

///|
test "direct-return trust rejects global binding mutation before sealing" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  guard interp.global.bindings.get("f") is Some(binding) else {
    fail("expected the hoisted direct-return binding")
  }
  let original = binding.value
  binding.value = Number(0.0)
  let result = try {
    let _ = interp.seal_direct_return_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  binding.value = original
  inspect(
    result,
    content="direct-return declaration did not hoist a function object",
  )
}

///|
test "direct-return trust rejects post-seal UserFunc mutation" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let callee = registry.entry.callee
  guard callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("expected a trusted direct-return UserFunc")
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
    content="direct-return callee provenance changed after sealing",
  )
  inspect(
    body_result,
    content="direct-return callee provenance changed after sealing",
  )
  let restored = registry.require_callee(interp, callee)
  inspect(restored.name, content="f")
}

///|
test "direct-return trust rejects post-seal leaf mutation" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_LEAF_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return leaf preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.leaf {
    Some(found) => found
    None => fail("expected a trusted direct-return leaf")
  }
  guard leaf.callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("expected a trusted direct-return leaf UserFunc")
  }
  let original_stmt = data.body[0]
  data.body[0] = @parser.parse("return 0;").stmts[0]
  let result = try {
    let _ = registry.require_leaf(interp, leaf.callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.body[0] = original_stmt
  inspect(result, content="direct-return leaf provenance changed after sealing")
  let restored = registry.require_leaf(interp, leaf.callee)
  inspect(restored.name, content="leaf")
}

///|
test "direct-return trust revalidates binding and mirror after sealing" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let callee = registry.entry.callee
  guard callee is Object({ callable: Some(UserFunc(data)), .. }) &&
    interp.global.bindings.get("f") is Some(binding) &&
    interp.global_this is Object(global_object) else {
    fail("expected trusted direct-return global UserFunc provenance")
  }
  let replacement = make_func(data)

  let original_binding = binding.value
  binding.value = replacement
  let binding_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  binding.value = original_binding

  let original_mirror = global_object.bag.properties["f"]
  global_object.bag.properties["f"] = replacement
  let mirror_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  global_object.bag.properties["f"] = original_mirror

  inspect(
    binding_result,
    content="direct-return callee diverged from its global binding",
  )
  inspect(
    mirror_result,
    content="direct-return callee diverged from its global mirror",
  )
}

///|
test "direct-return execution rejects a foreign activation environment" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    direct_return_registry=Some(registry),
  )
  let foreign_parent = Environment::new()
  let wrong_parent = Environment::new(parent=Some(foreign_parent))
  wrong_parent.is_var_scope = true
  let with_object = Environment::new(parent=Some(interp.global))
  with_object.is_var_scope = true
  with_object.with_object = Some(Undefined)
  let non_var_scope = Environment::new(parent=Some(interp.global))
  for env in [wrong_parent, with_object, non_var_scope] {
    env.def_parameter("n", Number(1.0))
    let result = try {
      let _ = shell.execute_direct_return_statement({
        ctx: { strict: false, current_generator: None },
        stmt: registry.entry.body[0],
        env,
        index: 0,
      })
      "accepted"
    } catch {
      InvalidActivationDispatchShell(message) => message
    }
    inspect(
      result,
      content="direct-return statement lost its sealed body provenance",
    )
  }
}

///|
test "direct-return trust rejects source identity drift during hoisting" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("preflight.js")
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.realm_state.active_source_identity.val = Some("hoist.js")
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.realm_state.active_source_identity.val = Some("preflight.js")
  let result = try {
    let _ = interp.seal_direct_return_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="direct-return UserFunc source identity changed during root hoisting",
  )
}

///|
test "direct-return trust rejects foreign realm metadata during hoisting" {
  let interp = Interpreter::new()
  let foreign = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.global.interpreter_context = Some(foreign)
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.global.interpreter_context = Some(interp)
  let result = try {
    let _ = interp.seal_direct_return_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="direct-return UserFunc realm provenance changed during root hoisting",
  )
}

///|
test "direct-return one-short budget stops before later recursive calls" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = direct_return_observation_fixture(interp, probe)
  let control = ExecutionControl(
    remaining_steps=513,
    maximum_active_depth=300,
    interruption=ExecutionInterruptionRequest(),
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, ctx)
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ => fail("expected the one-short direct-return execution limit")
  }
  inspect(probe.attempts, content="256")
  inspect(probe.accepted, content=probe.released.to_string())
  inspect(probe.active, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return interruption suppresses later recursive calls" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let interruption = ExecutionInterruptionRequest()
  let base_port = probe.port()
  let port = ActivationObservationPort(
    begin_entry=() => {
      let hooks = (base_port.begin_entry)()
      if probe.attempts == 128 {
        interruption.request()
      }
      hooks
    },
    denied=() => (base_port.denied)(),
  )
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact direct-return preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=port,
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=300,
    interruption~,
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, { strict: false, current_generator: None })
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(Interrupted)) => ()
    _ => fail("expected direct-return interruption identity")
  }
  inspect(probe.attempts, content="128")
  inspect(probe.accepted, content=probe.released.to_string())
  inspect(probe.active, content="0")
  inspect(probe.lifo_violations, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return interruption at leaf bypasses saved return consumers" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let interruption = ExecutionInterruptionRequest()
  let base_port = probe.port()
  let port = ActivationObservationPort(
    begin_entry=() => {
      let hooks = (base_port.begin_entry)()
      if probe.attempts == 258 {
        interruption.request()
      }
      hooks
    },
    denied=() => (base_port.denied)(),
  )
  let stmts = direct_return_test_program(DIRECT_RETURN_LEAF_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact direct-return leaf preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=port,
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=300,
    interruption~,
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, { strict: false, current_generator: None })
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(Interrupted)) => ()
    _ => fail("expected interruption at the direct-return leaf")
  }
  expect_dispatch_observation_balanced(probe, 258)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return cleanup permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 113)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  match run_direct_return_shell_once(interp) {
    String_(value) => inspect(value, content="done")
    other => fail("unexpected first direct-return result: " + other.to_string())
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 113)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after first direct-return run")
  }
  match run_direct_return_shell_once(interp) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("unexpected second direct-return result: " + other.to_string())
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 113)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after second direct-return run")
  }
}

///|
test "direct-return leaf cleanup permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 131)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  for attempt in 0..<2 {
    match
      run_direct_return_shell_source_once(
        interp,
        DIRECT_RETURN_LEAF_TEST_SOURCE,
        258,
      ) {
      String_(value) => inspect(value, content="done")
      other =>
        fail(
          "unexpected direct-return leaf result at attempt " +
          attempt.to_string() +
          ": " +
          other.to_string(),
        )
    }
    dispatch_shell_test_expect_realm_sentinel(interp, 131)
    match interp.realm_state.active_source_identity.val {
      Some(source) => inspect(source, content="caller.js")
      None => fail("expected source identity after direct-return leaf run")
    }
  }
}

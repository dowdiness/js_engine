///| Focused whitebox coverage for execution-control dispatch wiring.

///|
fn run_dispatch_source(
  interp : Interpreter,
  source : String,
  control : ExecutionControl,
) -> Value raise Error {
  let program = @parser.parse(source)
  interp.with_execution_control(control, fn() raise {
    interp.run(program.stmts)
  })
}

///|
test "execution control charges statement and expression dispatch" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = run_dispatch_source(interp, "42", control)
  match result {
    Number(value) if value == 42.0 => ()
    other => fail("expected numeric result, got " + other.to_string())
  }
  inspect(control.remaining_steps(), content="0")
}

///|
test "unbounded execution remains unchanged before and after a control scope" {
  let interp = Interpreter::new()
  let before = @parser.parse("1")
  match interp.run(before.stmts) {
    Number(value) if value == 1.0 => ()
    _ => fail("expected unbounded execution to succeed")
  }
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let _ = run_dispatch_source(interp, "2", control)
  let after = @parser.parse("3")
  match interp.run(after.stmts) {
    Number(value) if value == 3.0 => ()
    _ => fail("expected unbounded execution after scope to succeed")
  }
}

///|
test "zero budget rejects before the first statement side effect" {
  let interp = Interpreter::new()
  interp.global.def("counter", Number(0.0), VarBinding)
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ = run_dispatch_source(interp, "counter = 1", control)
    "none"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  match interp.global.get("counter") {
    Number(value) if value == 0.0 => ()
    _ => fail("statement side effect started before rejection")
  }
  inspect(control.remaining_steps(), content="0")
}

///|
test "one budget charges the statement then rejects its expression" {
  let interp = Interpreter::new()
  interp.global.def("counter", Number(0.0), VarBinding)
  let control = ExecutionControl(
    remaining_steps=1,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ = run_dispatch_source(interp, "counter = 1", control)
    "none"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  match interp.global.get("counter") {
    Number(value) if value == 0.0 => ()
    _ => fail("expression side effect started before rejection")
  }
  inspect(control.remaining_steps(), content="0")
}

///|
test "interruption precedes zero budget at dispatch" {
  let interp = Interpreter::new()
  interp.global.def("counter", Number(0.0), VarBinding)
  let interruption = ExecutionInterruptionRequest()
  interruption.request()
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=1,
    interruption~,
  )
  let failure = try {
    let _ = run_dispatch_source(interp, "counter = 1", control)
    "none"
  } catch {
    ExecutionControlError(Interrupted) => "interrupted"
    _ => "wrong-failure"
  }
  inspect(failure, content="interrupted")
  match interp.global.get("counter") {
    Number(value) if value == 0.0 => ()
    _ => fail("interrupted statement started side effects")
  }
  inspect(control.remaining_steps(), content="0")
}

///|
test "normal control scope restores the previous state" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let _ = run_dispatch_source(interp, "1", control)
  match interp.global.bindings.get(EXECUTION_CONTROL_BINDING) {
    None => ()
    Some(_) => fail("normal scope did not restore the previous state")
  }
}

///|
test "raised control scope restores state and preserves the original error" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let message = try {
    let _ : Unit = interp.with_execution_control(control, fn() raise {
      raise @errors.RangeError(message="scope sentinel")
    })
    "no error"
  } catch {
    @errors.RangeError(message~) => message
    _ => "wrong error"
  }
  inspect(message, content="scope sentinel")
  match interp.global.bindings.get(EXECUTION_CONTROL_BINDING) {
    None => ()
    Some(_) => fail("raised scope did not restore the previous state")
  }
}

///|
test "unbounded native-progress guard is a no-op and the interpreter remains reusable" {
  let interp = Interpreter::new()
  interp.reject_unobserved_native_progress()
  let result = interp.run(@parser.parse("3").stmts)
  match result {
    Number(value) if value == 3.0 => ()
    _ => fail("unbounded guard must not alter interpreter execution")
  }
}

///|
test "bounded native-progress guard fails before work and restores the interpreter" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=7,
    maximum_active_depth=3,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ : Unit = interp.with_execution_control(control, fn() raise {
      interp.reject_unobserved_native_progress()
    })
    "none"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  inspect(control.remaining_steps(), content="7")
  inspect(control.active_depth(), content="0")
  match interp.global.bindings.get(EXECUTION_CONTROL_BINDING) {
    None => ()
    Some(_) => fail("bounded guard scope leaked its execution carrier")
  }
  match interp.run(@parser.parse("4").stmts) {
    Number(value) if value == 4.0 => ()
    _ => fail("interpreter must be reusable after guarded interruption")
  }
}

///|
test "bounded native-progress failure bypasses JavaScript catch" {
  let interp = Interpreter::new()
  interp.global.def("counter", Number(0.0), VarBinding)
  let native_guard = make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("test-native-progress-guard", fn(_args) raise {
        interp.reject_unobserved_native_progress()
        Undefined
      }),
    ),
    "Function",
    Map([]),
    true,
  )
  interp.global.def_builtin("testNativeGuard", native_guard)
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=3,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ = run_dispatch_source(
      interp, "try { testNativeGuard(); counter = 1 } catch (error) { counter = 99 }",
      control,
    )
    "none"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  match interp.global.get("counter") {
    Number(value) if value == 0.0 => ()
    _ => fail("execution-control failure reached JavaScript catch")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "execution-control failure is not caught as a JavaScript exception" {
  let interp = Interpreter::new()
  interp.global.def("counter", Number(0.0), VarBinding)
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ = run_dispatch_source(
      interp, "try { counter = 1 } catch (error) { counter = 99 }", control,
    )
    "none"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  match interp.global.get("counter") {
    Number(value) if value == 0.0 => ()
    _ => fail("execution-control failure reached JavaScript catch")
  }
}

///|
test "dynamic eval shares the outer remaining counter" {
  let interp = Interpreter::new()
  interp.global.def("counter", Number(0.0), VarBinding)
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ : Value = interp.with_execution_control(control, fn() raise {
      interp.perform_eval("counter = 1", interp.global, true)
    })
    "none"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  match interp.global.get("counter") {
    Number(value) if value == 0.0 => ()
    _ => fail("dynamic eval reset or bypassed the outer budget")
  }
  inspect(control.remaining_steps(), content="0")
}

///|
test "separate interpreters do not share control state" {
  let limited = Interpreter::new()
  let independent = Interpreter::new()
  independent.global.def("counter", Number(0.0), VarBinding)
  let limited_control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ = run_dispatch_source(limited, "1", limited_control)
    "none"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  let program = @parser.parse("counter = 1")
  match independent.run(program.stmts) {
    Number(value) if value == 1.0 => ()
    _ => fail("one interpreter observed another interpreter's control")
  }
}

///|
test "nested expression dispatches share one remaining counter" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=5,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = run_dispatch_source(interp, "1 + 2", control)
  match result {
    Number(value) if value == 3.0 => ()
    _ => fail("expected nested expression to complete")
  }
  inspect(control.remaining_steps(), content="1")
}

///|
test "bounded loop termination is deterministic" {
  let run_once = fn() -> (String, Int) raise Error {
    let interp = Interpreter::new()
    interp.global.def("counter", Number(0.0), VarBinding)
    let control = ExecutionControl(
      remaining_steps=15,
      maximum_active_depth=1,
      interruption=ExecutionInterruptionRequest(),
    )
    let failure = try {
      let _ = run_dispatch_source(
        interp, "while (true) { counter = counter + 1 }", control,
      )
      "none"
    } catch {
      ExecutionControlError(ExecutionLimit) => "execution-limit"
      _ => "wrong-failure"
    }
    let count = match interp.global.get("counter") {
      Number(value) => value.to_int()
      _ => -1
    }
    (failure, count)
  }
  let first = run_once()
  let second = run_once()
  inspect(first.0, content="execution-limit")
  inspect(second.0, content="execution-limit")
  inspect(first.1, content="2")
  inspect(second.1, content="2")
}

///|
test "public direct recursion rejects at the logical depth boundary" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let parsed = @parser.parse(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  inspect(
    interp.preflight_dispatchable_numeric_recursion_program(parsed.stmts)
    is Some(_),
    content="true",
  )
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = try {
    let value = run_dispatch_source(
      interp, "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);", control,
    )
    match value {
      Number(value) => "completed:" + value.to_string()
      _ => "completed:other"
    }
  } catch {
    JsException(Object(data)) => {
      let message = match data.bag.properties.get("message") {
        Some(String_(value)) => value
        _ => "missing-message"
      }
      data.class_name + ":" + message
    }
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "other-error"
  }
  inspect(outcome, content="RangeError:Maximum call stack size exceeded")
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("depth rejection must preserve the caller source identity")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public protected recursion catches the logical depth RangeError" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = run_dispatch_source(
    interp,
    "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
    "try{throw f(256);}catch(e){e;}",
    control,
  )
  match result {
    Object(data) => {
      inspect(data.class_name, content="RangeError")
      match data.bag.properties.get("message") {
        Some(String_(message)) =>
          inspect(message, content="Maximum call stack size exceeded")
        _ => fail("expected the engine-owned depth-limit message")
      }
    }
    _ => fail("expected catch to consume the logical depth RangeError")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public mutual recursion catches the logical depth RangeError" {
  let interp = Interpreter::new()
  let source = "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(n){if(n===0)return 0;return 1+f(n-1);}" +
    "try{throw f(256);}catch(e){e;}"
  let parsed = @parser.parse(source)
  inspect(
    interp.preflight_dispatchable_numeric_recursion_program(parsed.stmts)
    is Some(_),
    content="true",
  )
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = run_dispatch_source(interp, source, control)
  match result {
    Object(data) => {
      inspect(data.class_name, content="RangeError")
      match data.bag.properties.get("message") {
        Some(String_(message)) =>
          inspect(message, content="Maximum call stack size exceeded")
        _ => fail("expected the engine-owned depth-limit message")
      }
    }
    _ => fail("expected catch to consume the logical depth RangeError")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public mutual recursion below the logical limit preserves its value" {
  let interp = Interpreter::new()
  let source = "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(n){if(n===0)return 0;return 1+f(n-1);}" +
    "f(8);"
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=9,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = run_dispatch_source(interp, source, control)
  match result {
    Number(value) => inspect(value, content="8")
    _ => fail("expected finite mutual recursion result")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public getter recursion rejects at the logical depth boundary" {
  let interp = Interpreter::new()
  let source = "let n=256;" +
    "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
    "o.x;"
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = try {
    let _ = run_dispatch_source(interp, source, control)
    "completed"
  } catch {
    JsException(Object(data)) => {
      let message = match data.bag.properties.get("message") {
        Some(String_(value)) => value
        _ => "missing-message"
      }
      data.class_name + ":" + message
    }
    other => "host-error:" + other.to_string()
  }
  inspect(outcome, content="RangeError:Maximum call stack size exceeded")
  match interp.global.get("n") {
    Number(value) => inspect(value, content="255")
    _ => fail("getter entry must run before its recursive child is rejected")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public getter recursion preserves finite result below logical limit" {
  let interp = Interpreter::new()
  let source = "let n=8;" +
    "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
    "o.x;"
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=9,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = run_dispatch_source(interp, source, control)
  match result {
    Number(value) => inspect(value, content="8")
    _ => fail("expected finite getter result")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public Proxy get recursion rejects at the logical depth boundary" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let source = "let n=256;" +
    "let p;" +
    "p=new Proxy({},{get(t,k,r){" +
    "if(n===0)return 0;n=n-1;return 1+p.x;" +
    "}});" +
    "p.x;"
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = try {
    let _ = run_dispatch_source(interp, source, control)
    "completed"
  } catch {
    JsException(Object(data)) => {
      let message = match data.bag.properties.get("message") {
        Some(String_(value)) => value
        _ => "missing-message"
      }
      data.class_name + ":" + message
    }
    other => "host-error:" + other.to_string()
  }
  inspect(outcome, content="RangeError:Maximum call stack size exceeded")
  match interp.global.get("n") {
    Number(value) => inspect(value, content="255")
    _ =>
      fail("Proxy trap entry must run before its recursive child is rejected")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public getter depth rejection preserves guest source identity" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("getter.js")
  let source = "let n=256;" +
    "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
    "o.x;"
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let observed = observe_source_failure(interp.realm_state, () => {
    let _ = run_dispatch_source(interp, source, control)
    ()
  })
  match observed {
    Err(failure) =>
      match failure.source_identity() {
        Some(source_identity) => inspect(source_identity, content="getter.js")
        None => fail("depth rejection must preserve the getter source identity")
      }
    Ok(_) => fail("expected getter depth rejection")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public Proxy depth rejection preserves guest source identity" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  interp.realm_state.active_source_identity.val = Some("proxy.js")
  let source = "let n=256;" +
    "let p;" +
    "p=new Proxy({},{get(t,k,r){" +
    "if(n===0)return 0;n=n-1;return 1+p.x;" +
    "}});" +
    "p.x;"
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let observed = observe_source_failure(interp.realm_state, () => {
    let _ = run_dispatch_source(interp, source, control)
    ()
  })
  match observed {
    Err(failure) =>
      match failure.source_identity() {
        Some(source_identity) => inspect(source_identity, content="proxy.js")
        None => fail("depth rejection must preserve the Proxy source identity")
      }
    Ok(_) => fail("expected Proxy depth rejection")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public call_value mutual recursion rejects at the logical depth boundary" {
  let interp = Interpreter::new()
  let program = @parser.parse(
    "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(n){if(n===0)return 0;return 1+f(n-1);}",
  )
  ignore(interp.run(program.stmts))
  let callee = interp.global.get("f")
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = try {
    let _ = interp.with_execution_control(control, () => {
      interp.call_value(
        callee,
        Undefined,
        [Number(256.0)],
        @token.Loc::default(),
      )
    })
    "completed"
  } catch {
    @errors.RangeError(message~) => "RangeError:" + message
    JsException(Object(data)) => {
      let message = match data.bag.properties.get("message") {
        Some(String_(value)) => value
        _ => "missing-message"
      }
      data.class_name + ":" + message
    }
    other => "host-error:" + other.to_string()
  }
  inspect(outcome, content="RangeError:Maximum call stack size exceeded")
  inspect(control.active_depth(), content="0")
}

///|
test "public mutual depth rejection preserves the entry source identity" {
  let interp = Interpreter::new()
  let entry = @parser.parse("function f(n){if(n===0)return 0;return 1+g(n-1);}")
  interp.realm_state.active_source_identity.val = Some("entry.js")
  ignore(interp.run(entry.stmts))
  let peer = @parser.parse("function g(n){if(n===0)return 0;return 1+f(n-1);}")
  interp.realm_state.active_source_identity.val = Some("peer.js")
  ignore(interp.run(peer.stmts))
  let callee = interp.global.get("f")
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let observed = observe_source_failure(interp.realm_state, () => {
    let _ = interp.with_execution_control(control, () => {
      interp.call_value(
        callee,
        Undefined,
        [Number(256.0)],
        @token.Loc::default(),
      )
    })
    ()
  })
  match observed {
    Err(failure) =>
      match failure.source_identity() {
        Some(source_identity) => inspect(source_identity, content="entry.js")
        None => fail("depth rejection must preserve the mutual entry identity")
      }
    Ok(_) => fail("expected mutual depth rejection")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "public direct recursion below the logical limit preserves its value" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=100000,
    maximum_active_depth=257,
    interruption=ExecutionInterruptionRequest(),
  )
  let value = run_dispatch_source(
    interp, "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);", control,
  )
  match value {
    Number(value) => inspect(value, content="256")
    _ => fail("expected the finite direct recursion result")
  }
  inspect(control.active_depth(), content="0")
}

///|
test "execution control adapter observes activation through the carrier" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = interp.with_execution_control(control, () => {
    let _ = observe_activation_entry(
      interp.execution_control_activation_observation_port(),
    )
    "accepted"
  }) catch {
    ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
    _ => "other"
  }
  inspect(outcome, content="stack-depth-limit")
}

///|
test "dispatch shell default observation is policy-free" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = interp.with_execution_control(control, () => {
    let shell = PrimitiveProgramDispatchShell(interp)
    let attempt = observe_activation_entry(shell.activation_observation_port)
    let token = attempt.accept()
    token.release()
    "accepted"
  }) catch {
    ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
    _ => "other"
  }
  inspect(outcome, content="accepted")
  inspect(control.active_depth(), content="0")
}

///|
test "direct activation releases logical depth after a guest throw" {
  let (interp, _, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  interp.with_execution_control(control, () => {
    let shell = PrimitiveProgramDispatchShell(
      interp,
      numeric_registry=Some(registry),
      activation_observation_port=interp.execution_control_activation_observation_port(),
    )
    let (cleanup, _) = numeric_activation_test_enter(
      shell,
      registry,
      "f",
      1.0,
      plan.root_call_loc,
    )
    inspect(control.active_depth(), content="1")
    numeric_activation_test_release(
      shell,
      cleanup,
      DispatchThrow(@errors.RangeError(message="guest sentinel")),
    )
  })
  inspect(control.active_depth(), content="0")
}

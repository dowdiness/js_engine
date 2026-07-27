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

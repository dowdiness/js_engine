///|
test "execution control rejects zero budget before charging" {
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.observe_step() {
    Err(ExecutionControlFailure::ExecutionLimit) => ()
    _ => fail("expected execution limit")
  }
  inspect(control.remaining_steps(), content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control charges one successful step" {
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.observe_step() {
    Ok(_) => ()
    Err(_) => fail("expected step observation to succeed")
  }
  inspect(control.remaining_steps(), content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control interruption precedes execution limit" {
  let interruption = ExecutionInterruptionRequest()
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=1,
    interruption~,
  )
  interruption.request()
  match control.observe_step() {
    Err(ExecutionControlFailure::Interrupted) => ()
    _ => fail("expected interruption")
  }
  inspect(control.remaining_steps(), content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control stack depth precedes execution limit" {
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=0,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.observe_activation() {
    Err(ExecutionControlFailure::StackDepthLimit) => ()
    _ => fail("expected stack-depth limit")
  }
  inspect(control.remaining_steps(), content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control interruption precedes stack depth" {
  let interruption = ExecutionInterruptionRequest()
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=0,
    interruption~,
  )
  interruption.request()
  match control.observe_activation() {
    Err(ExecutionControlFailure::Interrupted) => ()
    _ => fail("expected interruption")
  }
  inspect(control.remaining_steps(), content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control rejected activation preserves state" {
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.observe_activation() {
    Err(ExecutionControlFailure::ExecutionLimit) => ()
    _ => fail("expected execution limit")
  }
  inspect(control.remaining_steps(), content="0")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control successful activation charges and enters" {
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.observe_activation() {
    Ok(_) => ()
    Err(_) => fail("expected activation observation to succeed")
  }
  inspect(control.remaining_steps(), content="1")
  inspect(control.active_depth(), content="1")
}

///|
test "execution control normal activation exit restores depth" {
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let depth_inside : Ref[Int] = { val: -1 }
  match
    control.with_activation(() => {
      depth_inside.val = control.active_depth()
      42
    }) {
    Ok(42) => ()
    Ok(_) => fail("expected callback result")
    Err(_) => fail("expected activation to succeed")
  }
  inspect(depth_inside.val, content="1")
  inspect(control.remaining_steps(), content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control raised activation exit restores depth and error" {
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let caught = try {
    let _ : Result[Unit, ExecutionControlFailure] = control.with_activation(() => {
      raise @errors.RangeError(message="activation sentinel")
    })
    "no error"
  } catch {
    @errors.RangeError(message~) => message
    error => "wrong error: " + error.to_string()
  }
  inspect(caught, content="activation sentinel")
  inspect(control.remaining_steps(), content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control nested activations reach exact boundary" {
  let control = ExecutionControl(
    remaining_steps=3,
    maximum_active_depth=2,
    interruption=ExecutionInterruptionRequest(),
  )
  let outer = control.with_activation(() => {
    inspect(control.active_depth(), content="1")
    let inner = control.with_activation(() => {
      inspect(control.active_depth(), content="2")
      match control.observe_activation() {
        Err(ExecutionControlFailure::StackDepthLimit) => ()
        _ => fail("expected exact stack-depth boundary")
      }
      inspect(control.remaining_steps(), content="1")
      inspect(control.active_depth(), content="2")
    })
    match inner {
      Ok(_) => ()
      Err(_) => fail("expected inner activation to succeed")
    }
    inspect(control.active_depth(), content="1")
  })
  match outer {
    Ok(_) => ()
    Err(_) => fail("expected outer activation to succeed")
  }
  inspect(control.remaining_steps(), content="1")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control repeated interruption request is idempotent" {
  let interruption = ExecutionInterruptionRequest()
  inspect(interruption.is_requested(), content="false")
  interruption.request()
  interruption.request()
  inspect(interruption.is_requested(), content="true")
}

///|
test "execution control aliases share monotonic interruption state" {
  let interruption = ExecutionInterruptionRequest()
  let shared_view = interruption
  let first = ExecutionControl(
    remaining_steps=1,
    maximum_active_depth=1,
    interruption~,
  )
  let second = ExecutionControl(
    remaining_steps=1,
    maximum_active_depth=1,
    interruption=shared_view,
  )
  shared_view.request()
  inspect(interruption.is_requested(), content="true")
  match first.observe_step() {
    Err(ExecutionControlFailure::Interrupted) => ()
    _ => fail("expected first alias to observe interruption")
  }
  match second.observe_step() {
    Err(ExecutionControlFailure::Interrupted) => ()
    _ => fail("expected second alias to observe interruption")
  }
  inspect(first.remaining_steps(), content="1")
  inspect(second.remaining_steps(), content="1")
}

///|
test "execution control decrements maximum portable counter without overflow" {
  let control = ExecutionControl(
    remaining_steps=2147483647,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  inspect(control.remaining_steps(), content="2147483647")
  match control.observe_step() {
    Ok(_) => ()
    Err(_) => fail("expected maximum portable counter to be accepted")
  }
  inspect(control.remaining_steps(), content="2147483646")
  inspect(control.active_depth(), content="0")
}

///|
test "execution control activation port releases accepted entry exactly once" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=10,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  interp.with_execution_control(control, () => {
    let attempt = observe_activation_entry(
      interp.execution_control_activation_observation_port(),
    )
    inspect(control.active_depth(), content="1")
    let token = attempt.accept()
    token.release()
    inspect(control.active_depth(), content="0")
    inspect(control.remaining_steps(), content="9")
  })
}

///|
test "execution control activation port releases rejected setup without a token" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=10,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  interp.with_execution_control(control, () => {
    let attempt = observe_activation_entry(
      interp.execution_control_activation_observation_port(),
    )
    inspect(control.active_depth(), content="1")
    attempt.reject()
    inspect(control.active_depth(), content="0")
    inspect(control.remaining_steps(), content="9")
  })
}

///|
test "execution control activation port denies at the boundary without release" {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=10,
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
  inspect(control.active_depth(), content="0")
  inspect(control.remaining_steps(), content="10")
}

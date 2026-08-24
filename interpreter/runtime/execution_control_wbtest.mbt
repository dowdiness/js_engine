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
  let depth_inside : Ref[Int64] = { val: -1L }
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
    inspect(control.active_depth(), content="1")
    attempt.release_after_rejection()
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

///|
test "execution control stale release preserves zero depth" {
  let control = ExecutionControl(
    remaining_steps=10,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.release_activation() {
    Err(ExecutionControlFailure::StaleActivationRelease) => ()
    _ => fail("stale release must surface without mutating depth")
  }
  inspect(control.active_depth(), content="0")
  inspect(control.remaining_steps(), content="10")
}

///|
test "execution control rejects negative step budget before carrier creation" {
  let outcome = try {
    let _ = ExecutionControl(
      remaining_steps=-1L,
      maximum_active_depth=1L,
      interruption=ExecutionInterruptionRequest(),
    )
    "accepted"
  } catch {
    InvalidExecutionControlConfiguration(StepBudget, value) => value.to_string()
    _ => "wrong-error"
  }
  inspect(outcome, content="-1")
}

///|
test "execution control rejects negative stack depth before carrier creation" {
  let outcome = try {
    let _ = ExecutionControl(
      remaining_steps=1L,
      maximum_active_depth=-1L,
      interruption=ExecutionInterruptionRequest(),
    )
    "accepted"
  } catch {
    InvalidExecutionControlConfiguration(StackDepth, value) => value.to_string()
    _ => "wrong-error"
  }
  inspect(outcome, content="-1")
}

///|
test "execution control rejects above-maximum step budget before carrier creation" {
  let outcome = try {
    let _ = ExecutionControl(
      remaining_steps=2147483648L,
      maximum_active_depth=1L,
      interruption=ExecutionInterruptionRequest(),
    )
    "accepted"
  } catch {
    InvalidExecutionControlConfiguration(StepBudget, value) => value.to_string()
    _ => "wrong-error"
  }
  inspect(outcome, content="2147483648")
}

///|
test "execution control rejects above-maximum depth before carrier creation" {
  let outcome = try {
    let _ = ExecutionControl(
      remaining_steps=1L,
      maximum_active_depth=2147483648L,
      interruption=ExecutionInterruptionRequest(),
    )
    "accepted"
  } catch {
    InvalidExecutionControlConfiguration(StackDepth, value) => value.to_string()
    _ => "wrong-error"
  }
  inspect(outcome, content="2147483648")
}

///|
test "execution control accepts the maximum portable limits without wrapping" {
  let control = ExecutionControl(
    remaining_steps=2147483647L,
    maximum_active_depth=2147483647L,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.observe_step() {
    Ok(_) => ()
    Err(_) => fail("maximum portable step budget must be accepted")
  }
  inspect(control.remaining_steps(), content="2147483646")
  match control.observe_activation() {
    Ok(_) => ()
    Err(_) => fail("maximum portable depth must be accepted")
  }
  inspect(control.active_depth(), content="1")
  let _ = control.release_activation()
  inspect(control.active_depth(), content="0")
}

///|
test "execution control reducer returns immutable next state and decision" {
  let initial : ExecutionControlState = {
    remaining_steps: 2L,
    maximum_active_depth: 1L,
    active_depth: 0L,
  }
  let (next, decision) = reduce_execution_control(initial, ObserveStep(false))
  match decision {
    ExecutionControlDecision::StepObserved => ()
    _ => fail("step transition must report an observed step")
  }
  inspect(initial.remaining_steps, content="2")
  inspect(next.remaining_steps, content="1")
  inspect(next.active_depth, content="0")
}

///|
test "execution control reducer preserves exact rejection state at boundaries" {
  let depth_limited : ExecutionControlState = {
    remaining_steps: 7L,
    maximum_active_depth: 3L,
    active_depth: 3L,
  }
  let (depth_next, depth_decision) = reduce_execution_control(
    depth_limited,
    ObserveActivation(false),
  )
  match depth_decision {
    ExecutionControlDecision::Rejected(StackDepthLimit) => ()
    _ => fail("exact depth rejection must preserve the counters")
  }
  inspect(depth_next.remaining_steps, content="7")
  inspect(depth_next.active_depth, content="3")

  let budget_limited : ExecutionControlState = {
    remaining_steps: 0L,
    maximum_active_depth: 4L,
    active_depth: 2L,
  }
  let (budget_next, budget_decision) = reduce_execution_control(
    budget_limited,
    ObserveActivation(false),
  )
  match budget_decision {
    ExecutionControlDecision::Rejected(ExecutionLimit) => ()
    _ => fail("exact budget rejection must preserve the counters")
  }
  inspect(budget_next.remaining_steps, content="0")
  inspect(budget_next.active_depth, content="2")
}

///|
test "execution control reducer reaches maximum depth without wraparound" {
  let before_maximum : ExecutionControlState = {
    remaining_steps: 1L,
    maximum_active_depth: 2147483647L,
    active_depth: 2147483646L,
  }
  let (at_maximum, accepted) = reduce_execution_control(
    before_maximum,
    ObserveActivation(false),
  )
  match accepted {
    ExecutionControlDecision::ActivationObserved => ()
    _ => fail("the maximum portable depth must be reachable")
  }
  inspect(at_maximum.remaining_steps, content="0")
  inspect(at_maximum.active_depth, content="2147483647")
  let (after_rejection, rejected) = reduce_execution_control(
    at_maximum,
    ObserveActivation(false),
  )
  match rejected {
    ExecutionControlDecision::Rejected(StackDepthLimit) => ()
    _ => fail("the maximum portable depth must reject without wrapping")
  }
  inspect(after_rejection.remaining_steps, content="0")
  inspect(after_rejection.active_depth, content="2147483647")
}

///|
test "unobserved native progress is rejected without charging the carrier" {
  let control = ExecutionControl(
    remaining_steps=7,
    maximum_active_depth=3,
    interruption=ExecutionInterruptionRequest(),
  )
  match control.reject_unobserved_native_progress() {
    Err(ExecutionControlFailure::ExecutionLimit) => ()
    _ => fail("unobserved native progress must fail closed")
  }
  inspect(control.remaining_steps(), content="7")
  inspect(control.active_depth(), content="0")
}

///|
test "interruption takes precedence for unobserved native progress" {
  let interruption = ExecutionInterruptionRequest()
  interruption.request()
  let control = ExecutionControl(
    remaining_steps=7,
    maximum_active_depth=3,
    interruption~,
  )
  match control.reject_unobserved_native_progress() {
    Err(ExecutionControlFailure::Interrupted) => ()
    _ => fail("interruption must precede the fail-closed execution limit")
  }
  inspect(control.remaining_steps(), content="7")
  inspect(control.active_depth(), content="0")
}

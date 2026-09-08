///|
priv struct CompletedStepProbe {
  step : ExecutorActivationStep
  delivered : Array[ExecutorActivationCompletion]
  events : Array[String]
}

///|
fn CompletedStepProbe::CompletedStepProbe(
  step : ExecutorActivationStep,
  events? : Array[String] = [],
) -> CompletedStepProbe {
  { step, delivered: [], events, }
}

///|
impl ExecutorCode for CompletedStepProbe with fn start(self, _, _) {
  self as &ExecutorActivationFrame
}

///|
impl ExecutorActivationFrame for CompletedStepProbe with fn step(self, _) {
  self.step
}

///|
impl ExecutorActivationFrame for CompletedStepProbe with fn deliver_activation_completion(
  self,
  completion,
) {
  self.events.push("deliver")
  self.delivered.push(completion)
}

///|
// Keep stack layout in the fixture; tests specify only the child result and
// the runtime policy that consumes it. Owned children use run_child_entry.
fn CompletedStepProbe::run_child(
  self : CompletedStepProbe,
  tag : ExecutorChildCompletion,
  step : ExecutorActivationStep,
) -> Unit raise Error {
  self.run_child_entry(Interpreter::new(), {
    frame: CompletedStepProbe(step),
    completion: Some(tag),
    cleanup: None,
    graph_cursor: None,
  })
}

///|
fn CompletedStepProbe::run_child_entry(
  self : CompletedStepProbe,
  interp : Interpreter,
  child : ExecutorActivationStackEntry,
) -> Unit raise Error {
  ignore(
    interp.drive_executor_activation_stack([
      { frame: self, completion: None, cleanup: None, graph_cursor: None, },
      child,
    ]),
  )
}

///|
fn CompletedStepProbe::assert_abrupt(
  self : CompletedStepProbe,
  message : String,
) -> Error raise {
  guard self.delivered is [ExecutorActivationCompletionAbrupt(error)] else {
    fail("expected exactly one abrupt child delivery")
  }
  match error {
    @errors.InternalError(message=actual) => assert_eq(actual, message)
    _ => fail("expected an InternalError completion")
  }
  error
}

///|
fn completed_step_test_reference() -> ResolvedBindingReference {
  resolved_binding_reference(
    ResolvedBindingUnresolvable,
    "terminal-reference",
    { strict: false, current_generator: None, },
    @token.Loc::default(),
  )
}

///|
test "completed step public root preserves normal return and reference" {
  let interp = Interpreter::new()
  let reference = completed_step_test_reference()
  for
    step in [
      ExecutorActivationNormal(Number(7)),
      ExecutorActivationReturn(Number(7)),
      ExecutorActivationReference(reference),
    ] {
    let root = CompletedStepProbe(step)
    let result = interp.run_executor_activation_coordinator(root)
    match (step, result) {
      (ExecutorActivationNormal(value), ExecutorActivationNormal(actual))
      | (ExecutorActivationReturn(value), ExecutorActivationReturn(actual)) =>
        assert_true(strict_equal(value, actual))
      (
        ExecutorActivationReference(expected),
        ExecutorActivationReference(actual),
      ) => assert_true(physical_equal(expected, actual))
      _ => fail("public root changed its terminal kind")
    }
    assert_eq(root.delivered.length(), 0)
  }
}

///|
test "completed step calls distinguish fallthrough from return at both entries" {
  let interp = Interpreter::new()
  for
    case in [
      (ExecutorActivationNormal(Number(7)), Undefined),
      (ExecutorActivationReturn(Number(7)), Number(7)),
    ] {
    let (step, expected) = case
    let callee = make_executor_function(
      Some("terminal-call"),
      [],
      interp.global,
      false,
      CompletedStepProbe(step),
      constructable=false,
    )
    let synchronous = interp.call_value(
      callee,
      Undefined,
      [],
      @token.Loc::default(),
    )
    assert_true(strict_equal(synchronous, expected))
    let parent = ExecutorActivationCallFrame(
      callee~,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    )
    match interp.run_executor_activation_coordinator(parent) {
      ExecutorActivationReturn(actual) =>
        assert_true(strict_equal(actual, expected))
      _ => fail("managed call did not return its normalized child value")
    }
  }
}

///|
test "completed step call and construct reject references by raising the delivered error" {
  let reference = completed_step_test_reference()
  for
    case in [
      (
        ExecutorChildCall(OrdinaryExecutorCallable),
        "executor call completed with a binding reference",
      ),
      (
        ExecutorChildCall(ArrowExecutorCallable),
        "executor arrow call completed with a binding reference",
      ),
      (
        ExecutorChildConstruct(Null),
        "executor construct completed with a binding reference",
      ),
    ] {
    let (tag, message) = case
    let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
    let result : Result[Unit, Error] = Ok(
      parent.run_child(tag, ExecutorActivationReference(reference)),
    ) catch {
      error => Err(error)
    }
    guard result is Err(error) else { fail("expected normalization to raise") }
    assert_true(physical_equal(error, parent.assert_abrupt(message)))
  }
}

///|
test "completed step value operations deliver invalid references without raising" {
  let reference = completed_step_test_reference()
  for
    case in [
      (ExecutorChildArrayForEach, "forEach frame completed without a value"),
      (
        ExecutorChildPropertyGet,
        "value operation completed with a pending activation step",
      ),
      (
        ExecutorChildPropertyKey,
        "value operation completed with a pending activation step",
      ),
      (
        ExecutorChildComputedPropertyGet,
        "value operation completed with a pending activation step",
      ),
      (
        ExecutorChildPropertyUpdate,
        "property update completed with a pending activation step",
      ),
      (
        ExecutorChildCoercingAddition,
        "coercing addition completed with a pending activation step",
      ),
      (
        ExecutorChildCoercingRelational,
        "coercing relational completed with a pending activation step",
      ),
      (
        ExecutorChildCoercingSubtraction,
        "coercing subtraction completed with a pending activation step",
      ),
      (
        ExecutorChildCoercingMultiplicative,
        "coercing multiplicative completed with a pending activation step",
      ),
      (
        ExecutorChildNumericConversion,
        "numeric conversion completed with a pending activation",
      ),
      (
        ExecutorChildPropertyDelete,
        "property delete completed with a pending activation step",
      ),
      (
        ExecutorChildIterableSpread,
        "iterable spread frame completed without a value",
      ),
      (
        ExecutorChildCopyDataProperties,
        "CopyDataProperties frame completed with a pending step",
      ),
      (
        ExecutorChildBinding,
        "binding frame completed with a pending activation step",
      ),
      (
        ExecutorChildBindingReferenceAccess,
        "binding frame completed with a pending activation step",
      ),
      (
        ExecutorChildBindingUpdate,
        "binding update completed with a pending activation",
      ),
    ] {
    let (tag, message) = case
    let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
    parent.run_child(tag, ExecutorActivationReference(reference))
    ignore(parent.assert_abrupt(message))
  }
}

///|
test "completed step binding reference preserves identity" {
  let reference = completed_step_test_reference()
  let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
  parent.run_child(
    ExecutorChildBindingReference,
    ExecutorActivationReference(reference),
  )
  guard parent.delivered is [ExecutorActivationCompletionReference(actual)] else {
    fail("expected exactly one reference delivery")
  }
  assert_true(physical_equal(actual, reference))
}

///|
test "completed step assignment delivers the saved RHS regardless of child result" {
  let reference = completed_step_test_reference()
  for
    step in [
      ExecutorActivationNormal(Number(1)),
      ExecutorActivationReturn(Number(2)),
      ExecutorActivationReference(reference),
    ] {
    let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
    parent.run_child(ExecutorChildPropertySet(Number(9)), step)
    guard parent.delivered
      is [ExecutorActivationCompletionNormal(Number(actual))] else {
      fail("expected exactly one assignment value delivery")
    }
    assert_eq(actual, 9)
  }
}

///|
test "completed step normalization failure cleans child before delivery" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  install_executor_activation_probe(interp, events, None)
  let callee = make_executor_function(
    Some("reference-result"),
    [],
    interp.global,
    false,
    CompletedStepProbe(
      ExecutorActivationReference(completed_step_test_reference()),
    ),
    constructable=false,
  )
  guard callee is Object({ callable: Some(ExecutorCallable(executable)), .. }) else {
    fail("expected executor callable")
  }
  let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined), events~)
  let child = interp.start_executor_activation(
    executable,
    ExecutorStartCall(
      ExecutorCallRequest(
        callee~,
        this_value=Undefined,
        args=[],
        loc=@token.Loc::default(),
      ),
    ),
    None,
  )
  let result : Result[Unit, Error] = Ok(parent.run_child_entry(interp, child)) catch {
    error => Err(error)
  }
  guard result is Err(error) else { fail("expected normalization to raise") }
  let delivered = parent.assert_abrupt(
    "executor call completed with a binding reference",
  )
  assert_true(physical_equal(error, delivered))
  json_inspect(events, content=["attempt:cleared", "release:cleared", "deliver"])
  assert_true(interp.realm_state.active_overrides.val is None)
}

///|
test "completed step binding reference rejects value terminals without raising" {
  for
    step in [
      ExecutorActivationNormal(Undefined),
      ExecutorActivationReturn(Number(1)),
    ] {
    let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
    parent.run_child(ExecutorChildBindingReference, step)
    ignore(
      parent.assert_abrupt(
        "binding reference frame completed without a reference",
      ),
    )
  }
}

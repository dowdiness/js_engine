///|
priv struct CompletedStepProbe {
  step : ExecutorActivationStep
  delivered : Array[ExecutorActivationCompletion]
  events : Array[String]
  delivery_events : Array[Array[String]]
}

///|
fn CompletedStepProbe::CompletedStepProbe(
  step : ExecutorActivationStep,
  events? : Array[String] = [],
) -> CompletedStepProbe {
  { step, delivered: [], events, delivery_events: [], }
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
  self.delivery_events.push(self.events.copy())
  self.delivered.push(completion)
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
test "completed step invalid reference preserves tag diagnostics and transport" {
  let reference = completed_step_test_reference()
  let cases : Array[(ExecutorChildCompletion, String, Bool)] = [
    (
      ExecutorChildCall(OrdinaryExecutorCallable),
      "executor call completed with a binding reference",
      true,
    ),
    (
      ExecutorChildCall(ArrowExecutorCallable),
      "executor arrow call completed with a binding reference",
      true,
    ),
    (
      ExecutorChildConstruct(Null),
      "executor construct completed with a binding reference",
      true,
    ),
    (
      ExecutorChildArrayForEach,
      "forEach frame completed without a value",
      false,
    ),
    (
      ExecutorChildPropertyGet,
      "value operation completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildPropertyKey,
      "value operation completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildComputedPropertyGet,
      "value operation completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildPropertyUpdate,
      "property update completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildCoercingAddition,
      "coercing addition completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildCoercingRelational,
      "coercing relational completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildCoercingSubtraction,
      "coercing subtraction completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildCoercingMultiplicative,
      "coercing multiplicative completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildNumericConversion,
      "numeric conversion completed with a pending activation",
      false,
    ),
    (
      ExecutorChildPropertyDelete,
      "property delete completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildIterableSpread,
      "iterable spread frame completed without a value",
      false,
    ),
    (
      ExecutorChildCopyDataProperties,
      "CopyDataProperties frame completed with a pending step",
      false,
    ),
    (
      ExecutorChildBinding,
      "binding frame completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildBindingReferenceAccess,
      "binding frame completed with a pending activation step",
      false,
    ),
    (
      ExecutorChildBindingUpdate,
      "binding update completed with a pending activation",
      false,
    ),
  ]
  for case in cases {
    let (tag, message, raises) = case
    let interp = Interpreter::new()
    let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
    let child = CompletedStepProbe(ExecutorActivationReference(reference))
    let result : Result[Unit, Error] = Ok(
      ignore(
        interp.drive_executor_activation_stack([
          {
            frame: parent,
            completion: None,
            cleanup: None,
            graph_cursor: None,
          },
          {
            frame: child,
            completion: Some(tag),
            cleanup: None,
            graph_cursor: None,
          },
        ]),
      ),
    ) catch {
      error => Err(error)
    }
    match (raises, result) {
      (true, Err(@errors.InternalError(message=actual))) =>
        assert_eq(actual, message)
      (false, Ok(_)) => ()
      _ => fail("terminal error changed its raised-versus-delivered transport")
    }
    guard parent.delivered is [ExecutorActivationCompletionAbrupt(error)] else {
      fail("expected one abrupt child delivery")
    }
    match error {
      @errors.InternalError(message=actual) => assert_eq(actual, message)
      _ => fail("expected an InternalError completion")
    }
  }
}

///|
test "completed step reference identity and stored assignment value survive" {
  let reference = completed_step_test_reference()
  for
    tag in [ExecutorChildBindingReference, ExecutorChildPropertySet(Number(9))] {
    let interp = Interpreter::new()
    let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
    let child = CompletedStepProbe(ExecutorActivationReference(reference))
    ignore(
      interp.drive_executor_activation_stack([
        { frame: parent, completion: None, cleanup: None, graph_cursor: None, },
        {
          frame: child,
          completion: Some(tag),
          cleanup: None,
          graph_cursor: None,
        },
      ]),
    )
    match (tag, parent.delivered) {
      (
        ExecutorChildBindingReference,
        [ExecutorActivationCompletionReference(actual)],
      ) => assert_true(physical_equal(actual, reference))
      (
        ExecutorChildPropertySet(_),
        [ExecutorActivationCompletionNormal(Number(actual))],
      ) => assert_eq(actual, 9)
      _ => fail("reference or assignment result changed")
    }
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
  let result : Result[Unit, Error] = Ok(
    ignore(
      interp.drive_executor_activation_stack([
        { frame: parent, completion: None, cleanup: None, graph_cursor: None, },
        child,
      ]),
    ),
  ) catch {
    error => Err(error)
  }
  guard result is Err(error) else { fail("expected normalization to raise") }
  match error {
    @errors.InternalError(message~) =>
      assert_eq(message, "executor call completed with a binding reference")
    _ => fail("expected InternalError")
  }
  guard parent.delivered is [ExecutorActivationCompletionAbrupt(delivered)] else {
    fail("expected exactly one abrupt delivery")
  }
  assert_true(physical_equal(error, delivered))
  json_inspect(parent.delivery_events, content=[
    ["attempt:cleared", "release:cleared"],
  ])
  json_inspect(events, content=["attempt:cleared", "release:cleared"])
  assert_true(interp.realm_state.active_overrides.val is None)
}

///|
test "completed step binding reference rejects value terminals without raising" {
  for
    step in [
      ExecutorActivationNormal(Undefined),
      ExecutorActivationReturn(Number(1)),
    ] {
    let interp = Interpreter::new()
    let parent = CompletedStepProbe(ExecutorActivationNormal(Undefined))
    let child = CompletedStepProbe(step)
    ignore(
      interp.drive_executor_activation_stack([
        { frame: parent, completion: None, cleanup: None, graph_cursor: None, },
        {
          frame: child,
          completion: Some(ExecutorChildBindingReference),
          cleanup: None,
          graph_cursor: None,
        },
      ]),
    )
    guard parent.delivered is [ExecutorActivationCompletionAbrupt(error)] else {
      fail("expected one abrupt reference completion")
    }
    match error {
      @errors.InternalError(message~) =>
        assert_eq(
          message, "binding reference frame completed without a reference",
        )
      _ => fail("expected InternalError")
    }
  }
}

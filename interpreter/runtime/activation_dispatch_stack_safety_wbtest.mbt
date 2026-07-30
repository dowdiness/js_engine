///|
fn dispatch_stack_safety_statement_frames(count : Int) -> DispatchFrameStack {
  let mut frames = DispatchFrameStackEmpty
  for id in 0..<count {
    frames = DispatchFrameStackNode(
      DispatchStatementFrame(dispatch_test_statement_resume(id)),
      frames,
    )
  }
  frames
}

///|
fn dispatch_stack_safety_empty_statements() -> DispatchStatementCursor {
  DispatchStatementCursor(
    ctx={ strict: false, current_generator: None },
    stmts=[],
    env=Environment::new(),
  )
}

///|
test "completion routing drains 10000 completed statement frames" {
  let (_, decision) = route_dispatch_completion(
    dispatch_test_ready_state(dispatch_stack_safety_statement_frames(10000)),
    DispatchNormal(Number(42.0)),
  )
  match decision {
    DispatchFinish(DispatchNormal(Number(value))) =>
      inspect(value, content="42")
    _ => fail("expected exact normal completion after draining every frame")
  }
}

///|
test "abrupt completion drains 10000 completed statement frames" {
  let thrown : Error = @errors.TypeError(message="deep abrupt completion")
  let (_, decision) = route_dispatch_completion(
    dispatch_test_ready_state(dispatch_stack_safety_statement_frames(10000)),
    DispatchThrow(thrown),
  )
  match decision {
    DispatchFinish(DispatchThrow(found)) =>
      inspect(physical_equal(found, thrown), content="true")
    _ => fail("expected the exact abrupt completion after draining every frame")
  }
}

///|
test "completion routing drains 10000 empty finalizer frames" {
  let finalizer = dispatch_stack_safety_empty_statements()
  let mut frames = DispatchFrameStackEmpty
  for _ in 0..<5000 {
    frames = DispatchFrameStackNode(
      DispatchFinallyFrame(finalizer),
      DispatchFrameStackNode(
        DispatchNumericFinallyFrame(NumericRecursionClosedBodyEmpty),
        frames,
      ),
    )
  }
  let (_, decision) = route_dispatch_completion(
    dispatch_test_ready_state(frames),
    DispatchReturn(Number(17.0)),
  )
  match decision {
    DispatchFinish(DispatchReturn(Number(value))) =>
      inspect(value, content="17")
    _ => fail("expected empty finalizers to resume the exact saved completion")
  }
}

///|
test "completion routing drains 10000 synchronous numeric resume frames" {
  let token = DispatchNumericCatchBindingToken(id=10000)
  let catch_state = DispatchNumericCatchResume(
    token~,
    parameter=None,
    body=NumericRecursionClosedBodyEmpty,
  )
  let mut frames = DispatchFrameStackEmpty
  for _ in 0..<5000 {
    frames = DispatchFrameStackNode(
      DispatchContinuationFrame(
        DispatchContinueNumericExpression(
          DispatchAfterNumericCatchBindingRead(token),
        ),
      ),
      DispatchFrameStackNode(
        DispatchContinuationFrame(
          DispatchContinueNumericStatement(
            DispatchAfterNumericCatchEntry(catch_state),
          ),
        ),
        frames,
      ),
    )
  }
  let (_, decision) = route_dispatch_completion(
    dispatch_test_ready_state(frames),
    DispatchNormal(Undefined),
  )
  match decision {
    DispatchFinish(DispatchNormal(Undefined)) => ()
    _ => fail("expected synchronous numeric resumes to drain exactly")
  }
}

///|
fn dispatch_stack_safety_route_protected_completion(
  finalizer_result : DispatchCompletion,
) -> DispatchCompletion raise {
  let cleanup = DispatchActivationCleanup(30000)
  let catch_work = dispatch_test_catch_resume(30001)
  let finalizer_work = dispatch_test_statement_work(30002)
  let mut frames = DispatchFrameStackNode(
    DispatchCatchFrame(catch_work),
    DispatchFrameStackNode(
      DispatchFinallyFrame(finalizer_work),
      DispatchFrameStackNode(
        DispatchActivationFrame(cleanup, DispatchRootExit),
        DispatchFrameStackEmpty,
      ),
    ),
  )
  for id in 0..<10000 {
    frames = DispatchFrameStackNode(
      DispatchStatementFrame(dispatch_test_statement_resume(id)),
      frames,
    )
  }
  let original : Error = @errors.TypeError(message="deep protected throw")
  let (running_catch, catch_decision) = route_dispatch_completion(
    dispatch_test_ready_state(frames),
    DispatchThrow(original),
  )
  let catch_ticket = match catch_decision {
    DispatchPerform(
      ticket,
      DispatchRun(DispatchExecuteCatch(found_work, found_error))
    ) => {
      inspect(dispatch_test_work_label(found_work.body), content="30001")
      inspect(physical_equal(found_error, original), content="true")
      ticket
    }
    _ => fail("expected the deep throw to enter catch exactly once")
  }
  let (running_finalizer, finalizer_decision) = reduce_activation_dispatch(
    running_catch,
    DispatchEffectCompleted(
      catch_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(23.0))),
    ),
  )
  let finalizer_ticket = match finalizer_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      inspect(dispatch_test_step_label(step), content="30002")
      ticket
    }
    _ => fail("expected finalizer work after catch completion")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      running_finalizer,
      DispatchEffectCompleted(
        catch_ticket,
        DispatchWorkCompleted(DispatchNormal(Number(99.0))),
      ),
    )
  })
  let (releasing, release_decision) = reduce_activation_dispatch(
    running_finalizer,
    DispatchEffectCompleted(
      finalizer_ticket,
      DispatchWorkCompleted(finalizer_result),
    ),
  )
  let (release_ticket, released) = match release_decision {
    DispatchPerform(ticket, DispatchReleaseActivation(found, completion)) => {
      inspect(found.id, content="30000")
      (ticket, completion)
    }
    _ => fail("expected one activation release after the finalizer")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      releasing,
      DispatchEffectCompleted(
        finalizer_ticket,
        DispatchWorkCompleted(DispatchNormal(Undefined)),
      ),
    )
  })
  let (finished, finish_decision) = reduce_activation_dispatch(
    releasing,
    DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
  )
  let completion = match finish_decision {
    DispatchFinish(found) => found
    _ => fail("expected completion after one cleanup")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      finished,
      DispatchEffectCompleted(release_ticket, DispatchCleanupCompleted),
    )
  })
  match (released, completion) {
    (DispatchThrow(expected), DispatchThrow(found)) =>
      inspect(physical_equal(found, expected), content="true")
    _ =>
      inspect(
        dispatch_completion_tag(completion),
        content=dispatch_completion_tag(released),
      )
  }
  completion
}

///|
test "deep protected routing resumes a saved completion once" {
  let completion = dispatch_stack_safety_route_protected_completion(
    DispatchNormal(Undefined),
  )
  match completion {
    DispatchNormal(Number(value)) => inspect(value, content="23")
    _ => fail("expected normal finalizer to resume the caught completion")
  }
}

///|
test "deep protected routing replaces a saved completion once" {
  let replacement : Error = @errors.TypeError(message="finalizer replacement")
  let completion = dispatch_stack_safety_route_protected_completion(
    DispatchThrow(replacement),
  )
  match completion {
    DispatchThrow(found) =>
      inspect(physical_equal(found, replacement), content="true")
    _ => fail("expected abrupt finalizer to replace the caught completion")
  }
}

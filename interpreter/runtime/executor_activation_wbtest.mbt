///|
priv struct ExecutorActivationTestCode {
  starts : Ref[Int]
  steps : Ref[Int]
}

///|
fn ExecutorActivationTestCode::ExecutorActivationTestCode(
  starts~ : Ref[Int],
  steps~ : Ref[Int],
) -> ExecutorActivationTestCode {
  { starts, steps }
}

///|
priv struct ExecutorActivationTestFrame {
  steps : Ref[Int]
}

///|
priv struct ExecutorActivationThrowCode {
  error : Error
}

///|
fn ExecutorActivationThrowCode::ExecutorActivationThrowCode(
  error~ : Error,
) -> ExecutorActivationThrowCode {
  { error, }
}

///|
priv struct ExecutorActivationThrowFrame {
  error : Error
}

///|
priv struct ExecutorActivationCallCode {
  callee : Value
  this_value : Value
  args : Array[Value]
  loc : @token.Loc
}

///|
priv struct ExecutorActivationCallFrame {
  callee : Value
  this_value : Value
  args : Array[Value]
  loc : @token.Loc
  mut requested : Bool
  mut result : Value?
}

///|
fn ExecutorActivationCallCode::ExecutorActivationCallCode(
  callee~ : Value,
  this_value~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorActivationCallCode {
  { callee, this_value, args: args.copy(), loc }
}

///|
fn ExecutorActivationCallFrame::ExecutorActivationCallFrame(
  callee~ : Value,
  this_value~ : Value,
  args~ : Array[Value],
  loc~ : @token.Loc,
) -> ExecutorActivationCallFrame {
  { callee, this_value, args: args.copy(), loc, requested: false, result: None }
}

///|
fn ExecutorActivationThrowFrame::ExecutorActivationThrowFrame(
  error~ : Error,
) -> ExecutorActivationThrowFrame {
  { error, }
}

///|
fn ExecutorActivationTestFrame::ExecutorActivationTestFrame(
  steps : Ref[Int],
) -> ExecutorActivationTestFrame {
  { steps, }
}

///|
impl ExecutorCode for ExecutorActivationTestCode with fn start(
  self,
  interp,
  prepared,
) {
  self.starts.val += 1
  assert_false(prepared.context().strict)
  assert_true(
    physical_equal(prepared.environment().get("this"), interp.global_this),
  )
  match prepared.environment().get("x") {
    Number(value) => inspect(value, content="1")
    _ => fail("runtime must bind parameters before executor entry")
  }
  let arguments : ArrayView[Value] = prepared.arguments()
  match arguments {
    [Number(value)] => inspect(value, content="1")
    _ => fail("executor arguments must be exposed through an immutable view")
  }
  ExecutorActivationTestFrame(self.steps) as &ExecutorActivationFrame
}

///|
impl ExecutorActivationFrame for ExecutorActivationTestFrame with fn step(
  self,
  _interp,
) {
  self.steps.val += 1
  if self.steps.val < 3 {
    executor_activation_continue()
  } else {
    executor_activation_return(Number(7.0))
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationTestFrame with fn deliver_call_result(
  _self,
  _value,
) {
  ()
}

///|
impl ExecutorCode for ExecutorActivationThrowCode with fn start(
  self,
  _interp,
  _prepared,
) {
  ExecutorActivationThrowFrame(error=self.error) as &ExecutorActivationFrame
}

///|
impl ExecutorCode for ExecutorActivationCallCode with fn start(
  self,
  _interp,
  _prepared,
) {
  ExecutorActivationCallFrame(
    callee=self.callee,
    this_value=self.this_value,
    args=self.args,
    loc=self.loc,
  )
  as &ExecutorActivationFrame
}

///|
impl ExecutorActivationFrame for ExecutorActivationCallFrame with fn step(
  self,
  _interp,
) {
  if !self.requested {
    self.requested = true
    executor_activation_call(self.callee, self.this_value, self.args, self.loc)
  } else {
    match self.result {
      Some(value) => executor_activation_return(value)
      None =>
        raise @errors.InternalError(
          message="test call frame resumed without a result",
        )
    }
  }
}

///|
impl ExecutorActivationFrame for ExecutorActivationCallFrame with fn deliver_call_result(
  self,
  value,
) {
  guard self.requested && self.result is None else {
    raise @errors.InternalError(
      message="test call frame received a duplicate result",
    )
  }
  self.result = Some(value)
}

///|
impl ExecutorActivationFrame for ExecutorActivationThrowFrame with fn step(
  self,
  _interp,
) {
  raise self.error
}

///|
impl ExecutorActivationFrame for ExecutorActivationThrowFrame with fn deliver_call_result(
  _self,
  _value,
) {
  ()
}

///|
test "executor-neutral shell prepares once and drives explicit frame steps" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let function = make_executor_function(
    Some("stepper"),
    ["x"],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  interp.in_nonarrow_param_default_eval = true
  let result = interp.call_value(
    function,
    Undefined,
    [Number(1.0)],
    @token.Loc::default(),
  )
  inspect(result.to_string(), content="7")
  inspect(starts.val, content="1")
  inspect(steps.val, content="3")
  assert_true(interp.in_nonarrow_param_default_eval)
}

///|
test "executor-neutral shell preserves abrupt error and restores dynamic gate" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="executor sentinel")
  let function = make_executor_function(
    Some("thrower"),
    [],
    interp.global,
    true,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  interp.in_nonarrow_param_default_eval = true
  let caught : Error? = try {
    let _ = interp.call_value(function, Undefined, [], @token.Loc::default())
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("expected executor frame to raise")
  }
  assert_true(interp.in_nonarrow_param_default_eval)
}

///|
test "executor function retains an inspectable neutral payload before entry" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let function = make_executor_function(
    Some("inspectable"),
    ["x"],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  match function {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) => {
      inspect(starts.val, content="0")
      inspect(steps.val, content="0")
      let source_args = [Number(1.0)]
      let prepared = interp.prepare_executor_callable_call(
        executable,
        function,
        Undefined,
        source_args,
      )
      source_args[0] = Number(99.0)
      let _ = executable.start_frame(interp, prepared)
      inspect(starts.val, content="1")
      inspect(steps.val, content="0")
    }
    _ => fail("executor code must remain available as a neutral payload")
  }
}

///|
test "activation coordinator resumes one child result and normalizes it" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let child = make_executor_function(
    Some("child"),
    ["x"],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=child,
      this_value=Undefined,
      args=[Number(1.0)],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  match interp.run_executor_activation_coordinator(root) {
    ExecutorActivationReturn(value) => inspect(value.to_string(), content="7")
    _ => fail("coordinator must return the root frame's child result")
  }
  inspect(starts.val, content="1")
  inspect(steps.val, content="3")
}

///|
test "activation coordinator unwinds child errors and restores dynamic state" {
  let interp = Interpreter::new()
  let sentinel : Error = @errors.RangeError(message="coordinator sentinel")
  let child = make_executor_function(
    Some("thrower"),
    [],
    interp.global,
    false,
    ExecutorActivationThrowCode(error=sentinel),
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=child,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let caught : Error? = interp.with_execution_control(control, () => {
    interp.in_nonarrow_param_default_eval = true
    try {
      let _ = interp.run_executor_activation_coordinator(root)
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("expected child error to unwind the coordinator")
  }
  assert_true(interp.in_nonarrow_param_default_eval)
  inspect(control.active_depth(), content="0")
}

///|
test "activation coordinator rejects depth before child preparation" {
  let interp = Interpreter::new()
  let starts : Ref[Int] = { val: 0 }
  let steps : Ref[Int] = { val: 0 }
  let leaf = make_executor_function(
    Some("leaf"),
    [],
    interp.global,
    false,
    ExecutorActivationTestCode(starts~, steps~),
    constructable=false,
  )
  let middle = ExecutorActivationCallCode(
    callee=leaf,
    this_value=Undefined,
    args=[],
    loc=@token.Loc::default(),
  )
  let middle_value = make_executor_function(
    Some("middle"),
    [],
    interp.global,
    false,
    middle,
    constructable=false,
  )
  let root = ExecutorActivationCallFrame(
      callee=middle_value,
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    )
    as &ExecutorActivationFrame
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = interp.with_execution_control(control, () => {
    let _ = interp.run_executor_activation_coordinator(root)
    "completed"
  }) catch {
    ExecutionControlError(StackDepthLimit) => "stack-depth-limit"
    _ => "other-error"
  }
  inspect(outcome, content="stack-depth-limit")
  inspect(starts.val, content="0")
  inspect(control.active_depth(), content="0")
}

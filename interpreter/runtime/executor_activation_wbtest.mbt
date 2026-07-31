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
  let first_arguments = prepared.arguments()
  first_arguments[0] = Number(99.0)
  match prepared.arguments() {
    [Number(value)] => inspect(value, content="1")
    _ => fail("executor arguments must be returned as a defensive copy")
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
impl ExecutorCode for ExecutorActivationThrowCode with fn start(
  self,
  _interp,
  _prepared,
) {
  ExecutorActivationThrowFrame(error=self.error) as &ExecutorActivationFrame
}

///|
impl ExecutorActivationFrame for ExecutorActivationThrowFrame with fn step(
  self,
  _interp,
) {
  raise self.error
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
      let prepared = interp.prepare_executor_callable_call(
        executable,
        function,
        Undefined,
        [Number(1.0)],
      )
      let _ = executable.start_frame(interp, prepared)
      inspect(starts.val, content="1")
      inspect(steps.val, content="0")
    }
    _ => fail("executor code must remain available as a neutral payload")
  }
}

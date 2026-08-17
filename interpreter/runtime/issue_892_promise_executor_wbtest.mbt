///|
test "issue 892 settlement clears completed reaction records" {
  let interp = Interpreter::new()
  let promise_data = new_promise_data()
  let noop = make_native_func(name="promise-reaction-noop", _args => Undefined)
  let (resolve, reject) = make_promise_resolving_functions(interp, promise_data)
  promise_data.fulfill_reactions.push({
    handler: None,
    resolve,
    reject,
    reaction_type: Fulfill,
  })
  fulfill_promise(interp, promise_data, Number(1.0))
  assert_eq(promise_data.fulfill_reactions.length(), 0)
  assert_eq(promise_data.reject_reactions.length(), 0)
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(interp.host.microtask_queue.length(), 0)
  ignore(noop)
}

///|
test "issue 892 runtime activation failure consumes selected reaction and retains suffix" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let failure : Error = ExecutionControlError(ExecutionLimit)
  let handler = make_native_func(name="runtime-failure-handler", fn(_args) raise {
    raise failure
  })
  let noop = make_native_func(name="promise-reaction-noop", _args => Undefined)
  let suffix = make_native_func(name="suffix", fn(_args) {
    events.push("suffix")
    Undefined
  })
  enqueue_promise_reaction_job(
    interp,
    {
      handler: Some(handler),
      resolve: noop,
      reject: noop,
      reaction_type: Fulfill,
    },
    Number(1.0),
  )
  interp.enqueue_microtask(suffix, [])
  let observed = try {
    interp.run_microtasks()
    "normal"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-control"
    error => "unexpected:" + error.to_string()
  }
  assert_eq(observed, "execution-control")
  assert_eq(interp.host.microtask_queue.length(), 1)
  interp.run_microtasks()
  assert_eq(events, ["suffix"])
  assert_eq(interp.host.microtask_queue.length(), 0)
}

///|
test "issue 892 preselection failure retains the full Promise suffix" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  let handler = make_native_func(name="reaction", fn(_args) {
    events.push("reaction")
    Undefined
  })
  let noop = make_native_func(name="promise-reaction-noop", _args => Undefined)
  let suffix = make_native_func(name="suffix", fn(_args) {
    events.push("suffix")
    Undefined
  })
  enqueue_promise_reaction_job(
    interp,
    {
      handler: Some(handler),
      resolve: noop,
      reject: noop,
      reaction_type: Fulfill,
    },
    Number(1.0),
  )
  interp.enqueue_microtask(suffix, [])
  let control = ExecutionControl(
    remaining_steps=0,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let observed = try {
    interp.with_execution_control(control, () => {
      interp.run_microtasks()
      "normal"
    })
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-control"
    error => "unexpected:" + error.to_string()
  }
  assert_eq(observed, "execution-control")
  assert_eq(interp.host.microtask_queue.length(), 2)
  interp.run_microtasks()
  assert_eq(events, ["reaction", "suffix"])
  assert_eq(interp.host.microtask_queue.length(), 0)
}

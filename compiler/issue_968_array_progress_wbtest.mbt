///|
fn issue968_policy(step_budget : Int64) -> @runtime.ExecutionPolicy raise Error {
  match
    @runtime.ExecutionPolicy::new(
      step_budget,
      100L,
      @runtime.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded Array policy")
  }
}

///|
fn issue968_setup_source() -> String {
  (
    #|var values = Array(5000);
    #|for (var i = 0; i < 5000; i++) values[i] = i;
    #|var arrayLike = { length: 5000 };
    #|function joinLarge() { return values.join(); }
    #|function sliceLarge() { return values.slice(); }
    #|function concatLarge() { return values.concat(values); }
    #|function localeLarge() { return values.toLocaleString(); }
    #|function mapLarge() { return values.map(function(value) { return value; }); }
    #|function filterLarge() { return values.filter(function() { return false; }); }
    #|function reduceLarge() { return values.reduce(function(acc, value) { return acc + value; }, 0); }
    #|function reduceRightLarge() { return values.reduceRight(function(acc, value) { return acc + value; }, 0); }
    #|function findLarge() { return values.find(function() { return false; }); }
    #|function findIndexLarge() { return values.findIndex(function() { return false; }); }
    #|function findLastLarge() { return values.findLast(function() { return false; }); }
    #|function findLastIndexLarge() { return values.findLastIndex(function() { return false; }); }
    #|function everyLarge() { return values.every(function() { return true; }); }
    #|function someLarge() { return values.some(function() { return false; }); }
    #|function pushLarge() { return values.push.apply(values, values); }
    #|function shiftLarge() { return values.shift(); }
    #|function unshiftLarge() { return values.unshift.apply(values, values); }
    #|function reverseLarge() { return values.slice().reverse(); }
    #|function fillLarge() { return values.slice().fill(7); }
    #|function spliceLarge() { return values.slice().splice(100, 1000, 7); }
    #|function copyWithinLarge() { return values.slice().copyWithin(1, 0); }
    #|function toReversedLarge() { return values.toReversed(); }
    #|function toSplicedLarge() { return values.toSpliced(100, 1000, 7); }
    #|function withLarge() { return values.with(100, 7); }
    #|function arrayOfLarge() { return Array.of.apply(null, values); }
    #|function arrayConstructorLarge() { return Array.apply(null, values); }
    #|function fromArrayLikeLarge() { return Array.from(arrayLike); }
  )
}

///|
fn issue968_assert_candidate_limit(
  interp : @interpreter.Interpreter,
  call_source : String,
) -> Unit raise Error {
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let caught : Error? = interp.with_execution_policy(issue968_policy(1000L), () => {
    try {
      ignore(
        run_candidate_program_with_recorder(
          interp,
          @parser.parse(call_source).stmts,
          evidence,
        ),
      )
      None
    } catch {
      error => Some(error)
    }
  })
  match caught {
    Some(error) =>
      assert_eq(
        @runtime.execution_control_failure_code(error),
        Some("execution-limit"),
      )
    None =>
      fail(
        "residual Array work completed under the element budget: " + call_source,
      )
  }
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "candidate residual Array methods observe each logical unit" {
  let calls = [
    "joinLarge();", "sliceLarge();", "concatLarge();", "localeLarge();", "mapLarge();",
    "filterLarge();", "reduceLarge();", "reduceRightLarge();", "findLarge();", "findIndexLarge();",
    "findLastLarge();", "findLastIndexLarge();", "everyLarge();", "someLarge();",
    "pushLarge();", "shiftLarge();", "unshiftLarge();", "reverseLarge();", "fillLarge();",
    "spliceLarge();", "copyWithinLarge();", "toReversedLarge();", "toSplicedLarge();",
    "withLarge();", "arrayOfLarge();", "arrayConstructorLarge();", "fromArrayLikeLarge();",
  ]
  for call_source in calls {
    let interp = @interpreter.new_interpreter()
    ignore(run_executor_neutral_bytecode(interp, issue968_setup_source()))
    issue968_assert_candidate_limit(interp, call_source)
  }
}

///|
fn issue968_native_index_callback(
  trace : Ref[Array[Int]],
  result : @runtime.Value,
) -> @runtime.Value {
  @runtime.make_native_func(name="issue968NativeIndexCallback", args => {
    if args.length() > 1 {
      match args[1] {
        @runtime.Value::Number(index) => trace.val.push(index.to_int())
        _ => ()
      }
    }
    result
  })
}

///|
fn issue968_native_reducer(trace : Ref[Array[Int]]) -> @runtime.Value {
  @runtime.make_native_func(name="issue968NativeReducer", args => {
    if args.length() > 2 {
      match args[2] {
        @runtime.Value::Number(index) => trace.val.push(index.to_int())
        _ => ()
      }
    }
    @runtime.Value::Number(0.0)
  })
}

///|
fn issue968_assert_native_prefix(
  trace : Ref[Array[Int]],
  reverse : Bool,
) -> Unit raise Error {
  assert_true(trace.val.length() > 0)
  assert_true(trace.val.length() < 5000)
  let mut expected = if reverse { 4999 } else { 0 }
  for index in trace.val {
    assert_eq(index, expected)
    if reverse {
      expected -= 1
    } else {
      expected += 1
    }
  }
}

///|
test "candidate Array callbacks charge native host calls without guest overhead" {
  let interp = @interpreter.new_interpreter()
  let trace : Ref[Array[Int]] = { val: [], }
  interp.global.def_builtin(
    "issue968NativeIndexCallback",
    issue968_native_index_callback(trace, @runtime.Value::Bool(false)),
  )
  interp.global.def_builtin(
    "issue968NativeReducer",
    issue968_native_reducer(trace),
  )
  for
    (call_source, reverse) in [
      ("values.map(issue968NativeIndexCallback);", false),
      ("values.filter(issue968NativeIndexCallback);", false),
      ("values.find(issue968NativeIndexCallback);", false),
      ("values.findIndex(issue968NativeIndexCallback);", false),
      ("values.findLast(issue968NativeIndexCallback);", true),
      ("values.findLastIndex(issue968NativeIndexCallback);", true),
      ("values.some(issue968NativeIndexCallback);", false),
    ] {
    trace.val = []
    ignore(run_executor_neutral_bytecode(interp, issue968_setup_source()))
    issue968_assert_candidate_limit(interp, call_source)
    issue968_assert_native_prefix(trace, reverse)
  }
  for
    (call_source, reverse) in [
      ("values.reduce(issue968NativeReducer, 0);", false),
      ("values.reduceRight(issue968NativeReducer, 0);", true),
    ] {
    trace.val = []
    ignore(run_executor_neutral_bytecode(interp, issue968_setup_source()))
    issue968_assert_candidate_limit(interp, call_source)
    issue968_assert_native_prefix(trace, reverse)
  }
}

///|
fn issue968_mutator_setup_source() -> String {
  (
    #|var values = Array(5000);
    #|for (var i = 0; i < 5000; i++) values[i] = i;
    #|var mutatorTarget = Array(5000);
    #|for (var j = 0; j < 5000; j++) mutatorTarget[j] = j;
    #|mutatorTarget[0] = 9000;
    #|mutatorTarget[1] = 9001;
    #|mutatorTarget[4999] = 9999;
    #|function mutatorPush() { return mutatorTarget.push.apply(mutatorTarget, values); }
    #|function mutatorShift() { return mutatorTarget.shift(); }
    #|function mutatorUnshift() { return mutatorTarget.unshift.apply(mutatorTarget, values); }
    #|function mutatorReverse() { return mutatorTarget.reverse(); }
    #|function mutatorFill() { return mutatorTarget.fill(7); }
    #|function mutatorSplice() { return mutatorTarget.splice(0, 0, 7); }
    #|function mutatorCopyWithin() { return mutatorTarget.copyWithin(1, 0); }
    #|function mutatorState() { return mutatorTarget[0] + ":" + mutatorTarget[4999]; }
  )
}

///|
test "candidate Array mutators stop before the full destination state" {
  let cases = [
    ("mutatorPush();", "9000:9999"),
    ("mutatorShift();", "9001:9999"),
    ("mutatorUnshift();", "9000:9999"),
    ("mutatorFill();", "7:9999"),
    ("mutatorSplice();", "9000:4998"),
    ("mutatorCopyWithin();", "9000:4998"),
  ]
  for (call_source, expected_state) in cases {
    let interp = @interpreter.new_interpreter()
    ignore(
      run_executor_neutral_bytecode(interp, issue968_mutator_setup_source()),
    )
    issue968_assert_candidate_limit(interp, call_source)
    let actual_state = interp
      .run(@parser.parse("mutatorState();").stmts)
      .to_string()
    if actual_state != expected_state {
      fail(call_source + ": " + actual_state + " != " + expected_state)
    }
  }
  let interp = @interpreter.new_interpreter()
  ignore(run_executor_neutral_bytecode(interp, issue968_mutator_setup_source()))
  issue968_assert_candidate_limit(interp, "mutatorReverse();")
}

///|
test "Tree Array order observes before indexed getter work" {
  let trace : Ref[Array[String]] = { val: [], }
  let interp = @interpreter.new_interpreter()
  interp.global.def(
    "[[ExecutionControl]]",
    @runtime.make_native_func(name="issue968Observer", _args => {
      trace.val.push("observe")
      @runtime.Value::Undefined
    }),
    VarBinding,
  )
  ignore(
    interp.run(
      @parser.parse(
        "var observed = Array(1); Object.defineProperty(observed, '0', {" +
        "get: function() { issue968Log(); return 1; }});",
      ).stmts,
    ),
  )
  trace.val = []
  interp.global.def_builtin(
    "issue968Log",
    @runtime.make_native_func(name="issue968Log", _args => {
      trace.val.push("get")
      @runtime.Value::Number(1.0)
    }),
  )
  assert_eq(
    interp.run(@parser.parse("observed.join();").stmts).to_string(),
    "1",
  )
  let mut getter_index = -1
  for i, event in trace.val {
    if event == "get" {
      getter_index = i
      break
    }
  }
  assert_true(getter_index > 0)
  for i in 0..<getter_index {
    assert_eq(trace.val[i], "observe")
  }
}

///|
test "Array holes and early errors keep method-specific semantics" {
  let trace : Ref[Array[String]] = { val: [], }
  let interp = @interpreter.new_interpreter()
  interp.global.def(
    "[[ExecutionControl]]",
    @runtime.make_native_func(name="issue968HoleObserver", _args => {
      trace.val.push("observe")
      @runtime.Value::Undefined
    }),
    VarBinding,
  )
  let result = interp.run(@parser.parse("var sparse = Array(3);").stmts)
  ignore(result)
  trace.val = []
  let sparse = interp.global.get("sparse")
  let join = interp.get_property(sparse, "join", @token.Loc::default())
  assert_eq(
    interp
    .call_value(
      join,
      sparse,
      [@runtime.Value::String_("|")],
      @token.Loc::default(),
    )
    .to_string(),
    "||",
  )
  assert_eq(trace.val.length(), 3)
  trace.val = []
  let empty = @runtime.make_array([])
  let empty_join = interp.get_property(empty, "join", @token.Loc::default())
  assert_eq(
    interp.call_value(empty_join, empty, [], @token.Loc::default()).to_string(),
    "",
  )
  assert_eq(trace.val.length(), 0)
  let empty_map = interp.get_property(empty, "map", @token.Loc::default())
  let completion : Result[@runtime.Value, Error] = interp.with_execution_policy(
    issue968_policy(1L),
    () => {
      Ok(
        interp.call_value(
          empty_map,
          empty,
          [@runtime.Value::Number(0.0)],
          @token.Loc::default(),
        ),
      ) catch {
        error => Err(error)
      }
    },
  )
  match completion {
    Err(error) => {
      assert_eq(@runtime.execution_control_failure_code(error), None)
      assert_true(error.to_string().contains("TypeError"))
    }
    Ok(_) => fail("empty Array callback validation did not throw")
  }
}

///|
fn candidate_array_last_index_of_guardrail_policy_963(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid Array.lastIndexOf execution policy")
  }
}

///|
fn expect_candidate_array_last_index_of_result_963(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Json,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=expected)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "candidate Array.lastIndexOf observes sparse reverse traversal budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function missing() { return sparse.lastIndexOf(1); }",
  )
  match
    engine.call_json_bounded(
      "missing",
      [],
      candidate_array_last_index_of_guardrail_policy_963(1000L),
    ) {
    Ok(_) => fail("expected candidate Array.lastIndexOf to exhaust the budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("missing", []), content=-1)
}

///|
test "candidate Array.lastIndexOf preserves strict equality and fromIndex" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function boundaries() {
      #|  return [
      #|    [1, 2, 1].lastIndexOf(1),
      #|    [1, 2, 1].lastIndexOf(1, undefined),
      #|    [1, 2, 1].lastIndexOf(1, NaN),
      #|    [1, 2, 1].lastIndexOf(1, Infinity),
      #|    [1, 2, 1].lastIndexOf(1, -Infinity),
      #|    [1, 2, 1].lastIndexOf(1, -2),
      #|    [1, 2, 1].lastIndexOf(1, 3),
      #|    [NaN].lastIndexOf(NaN),
      #|    [0].lastIndexOf(-0),
      #|    Array(1).lastIndexOf(undefined)
      #|  ];
      #|}
    ),
  )
  expect_candidate_array_last_index_of_result_963(
    engine.call_json_bounded(
      "boundaries",
      [],
      candidate_array_last_index_of_guardrail_policy_963(1000L),
    ),
    [2, 0, 0, 2, -1, 0, 2, -1, 0, -1],
  )
}

///|
test "candidate Array.lastIndexOf preserves generic proxy order" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var events = [];
      #|var proxy = new Proxy({ 0: 1, 1: 2, length: 2 }, {
      #|  has: function(target, key) {
      #|    events.push("has:" + key);
      #|    return key === "1";
      #|  },
      #|  get: function(target, key, receiver) {
      #|    if (key !== "length") events.push("get:" + key);
      #|    return Reflect.get(target, key, receiver);
      #|  }
      #|});
      #|function proxyIndex() {
      #|  return [Array.prototype.lastIndexOf.call(proxy, 2), events.join("|")];
      #|}
    ),
  )
  expect_candidate_array_last_index_of_result_963(
    engine.call_json_bounded(
      "proxyIndex",
      [],
      candidate_array_last_index_of_guardrail_policy_963(1000L),
    ),
    [1, "has:1|get:1"],
  )
}

///|
test "candidate Array.lastIndexOf reuses the Engine after budget exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function missing() { return sparse.lastIndexOf(1); } " +
    "function small() { return [1, 2, 1].lastIndexOf(1); }",
  )
  match
    engine.call_json_bounded(
      "missing",
      [],
      candidate_array_last_index_of_guardrail_policy_963(1000L),
    ) {
    Ok(_) => fail("expected candidate Array.lastIndexOf to exhaust the budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("small", []), content=2)
}

///|
fn candidate_index_of_observation_guardrail_policy_961(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate Array.indexOf execution policy")
  }
}

///|
fn expect_candidate_array_index_result_961(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Json,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=expected)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "candidate Array.indexOf observes sparse traversal budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function missing() { return sparse.indexOf(1); }",
  )
  match
    engine.call_json_bounded(
      "missing",
      [],
      candidate_index_of_observation_guardrail_policy_961(1000L),
    ) {
    Ok(_) => fail("expected candidate Array.indexOf to exhaust the budget")
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
test "candidate Array.indexOf preserves strict equality and fromIndex" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function boundaries() {
      #|  return [
      #|    [1, 2, 3].indexOf(2),
      #|    [NaN].indexOf(NaN),
      #|    [0].indexOf(-0),
      #|    Array(1).indexOf(undefined),
      #|    [1, 2, 3].indexOf(1, 3),
      #|    [1, 2, 3].indexOf(1, -3),
      #|    [1, 2, 3].indexOf(1, undefined),
      #|    [1, 2, 3].indexOf(1, Infinity),
      #|    [1, 2, 3].indexOf(1, -Infinity)
      #|  ];
      #|}
    ),
  )
  expect_candidate_array_index_result_961(
    engine.call_json_bounded(
      "boundaries",
      [],
      candidate_index_of_observation_guardrail_policy_961(1000L),
    ),
    [1, -1, 0, -1, -1, 0, 0, -1, 0],
  )
}

///|
test "candidate Array.indexOf preserves generic inherited and proxy semantics" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var proto = { 0: "found" };
      #|var inherited = Object.create(proto);
      #|inherited.length = 1;
      #|function inheritedIndex() {
      #|  return Array.prototype.indexOf.call(inherited, "found");
      #|}
      #|var events = [];
      #|var proxy = new Proxy({ 0: 1, 1: 2, length: 2 }, {
      #|  has: function(target, key) {
      #|    events.push("has:" + key);
      #|    return key === "1";
      #|  },
      #|  get: function(target, key, receiver) {
      #|    events.push("get:" + key);
      #|    return Reflect.get(target, key, receiver);
      #|  }
      #|});
      #|function proxyIndex() {
      #|  return [Array.prototype.indexOf.call(proxy, 2), events.join("|")];
      #|}
      #|var getterEvents = [];
      #|var getterThrow = [0, 1];
      #|Object.defineProperty(getterThrow, "0", {
      #|  get: function() { getterEvents.push("get:0"); throw "getter"; }
      #|});
      #|Object.defineProperty(getterThrow, "1", {
      #|  get: function() { getterEvents.push("get:1"); return 1; }
      #|});
      #|function getterAbrupt() {
      #|  try { getterThrow.indexOf(1); } catch (_) {}
      #|  return getterEvents.join("|");
      #|}
    ),
  )
  expect_candidate_array_index_result_961(
    engine.call_json_bounded(
      "inheritedIndex",
      [],
      candidate_index_of_observation_guardrail_policy_961(1000L),
    ),
    0,
  )
  expect_candidate_array_index_result_961(
    engine.call_json_bounded(
      "proxyIndex",
      [],
      candidate_index_of_observation_guardrail_policy_961(1000L),
    ),
    [1, "get:length|has:0|has:1|get:1"],
  )
  expect_candidate_array_index_result_961(
    engine.call_json_bounded(
      "getterAbrupt",
      [],
      candidate_index_of_observation_guardrail_policy_961(1000L),
    ),
    "get:0",
  )
}

///|
test "candidate Array.indexOf reuses the Engine after budget exhaustion" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function missing() { return sparse.indexOf(1); } " +
    "function small() { return [1, 2, 3].indexOf(2); }",
  )
  match
    engine.call_json_bounded(
      "missing",
      [],
      candidate_index_of_observation_guardrail_policy_961(1000L),
    ) {
    Ok(_) => fail("expected candidate Array.indexOf to exhaust the budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("small", []), content=1)
}

///|
fn index_of_observation_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid Array.indexOf execution policy")
  }
}

///|
test "default Array.indexOf observes sparse traversal budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function missing() { return sparse.indexOf(1); }",
  )
  match
    engine.call_json_bounded(
      "missing",
      [],
      index_of_observation_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected Array.indexOf to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
fn expect_default_array_index_result_961(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Json,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=expected)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default Array.indexOf preserves strict equality and fromIndex" {
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
  expect_default_array_index_result_961(
    engine.call_json_bounded(
      "boundaries",
      [],
      index_of_observation_guardrail_policy(1000L),
    ),
    [1, -1, 0, -1, -1, 0, 0, -1, 0],
  )
}

///|
test "default Array.indexOf preserves generic inherited and proxy semantics" {
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
      #|var throwingEvents = [];
      #|var throwing = new Proxy({ length: 2 }, {
      #|  has: function(target, key) {
      #|    throwingEvents.push("has:" + key);
      #|    throw "boom";
      #|  },
      #|  get: function(target, key, receiver) {
      #|    throwingEvents.push("get:" + key);
      #|    return Reflect.get(target, key, receiver);
      #|  }
      #|});
      #|function throwingHas() {
      #|  try { Array.prototype.indexOf.call(throwing, 1); } catch (_) {}
      #|  return throwingEvents.join("|");
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
  expect_default_array_index_result_961(
    engine.call_json_bounded(
      "inheritedIndex",
      [],
      index_of_observation_guardrail_policy(1000L),
    ),
    0,
  )
  expect_default_array_index_result_961(
    engine.call_json_bounded(
      "proxyIndex",
      [],
      index_of_observation_guardrail_policy(1000L),
    ),
    [1, "get:length|has:0|has:1|get:1"],
  )
  expect_default_array_index_result_961(
    engine.call_json_bounded(
      "throwingHas",
      [],
      index_of_observation_guardrail_policy(1000L),
    ),
    "get:length|has:0",
  )
  expect_default_array_index_result_961(
    engine.call_json_bounded(
      "getterAbrupt",
      [],
      index_of_observation_guardrail_policy(1000L),
    ),
    "get:0",
  )
}

///|
test "default Array.indexOf snapshots length and preserves mutation" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var later = { length: 2, 0: 0, 1: 0 };
      #|Object.defineProperty(later, "0", {
      #|  get: function() { later[1] = 1; later.length = 0; return 0; }
      #|});
      #|function mutation() {
      #|  return [Array.prototype.indexOf.call(later, 1), later.length];
      #|}
      #|var fromCalls = 0;
      #|var fromIndex = { valueOf: function() { fromCalls += 1; return 0; } };
      #|function emptyLengthSkipsFromIndex() {
      #|  return [Array.prototype.indexOf.call([], 1, fromIndex), fromCalls];
      #|}
    ),
  )
  expect_default_array_index_result_961(
    engine.call_json_bounded(
      "mutation",
      [],
      index_of_observation_guardrail_policy(1000L),
    ),
    [1, 0],
  )
  expect_default_array_index_result_961(
    engine.call_json_bounded(
      "emptyLengthSkipsFromIndex",
      [],
      index_of_observation_guardrail_policy(1000L),
    ),
    [-1, 0],
  )
}

///|
test "default Array.indexOf reuses the Engine after budget exhaustion" {
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
      index_of_observation_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected Array.indexOf to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("small", []), content=1)
}

///|
fn array_last_index_of_guardrail_policy_963(
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
fn expect_array_last_index_of_result_963(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Json,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=expected)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "default Array.lastIndexOf observes sparse reverse traversal budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function missing() { return sparse.lastIndexOf(1); }",
  )
  match
    engine.call_json_bounded(
      "missing",
      [],
      array_last_index_of_guardrail_policy_963(1000L),
    ) {
    Ok(_) => fail("expected Array.lastIndexOf to exhaust the execution budget")
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
test "default Array.lastIndexOf preserves strict equality and fromIndex" {
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
  expect_array_last_index_of_result_963(
    engine.call_json_bounded(
      "boundaries",
      [],
      array_last_index_of_guardrail_policy_963(1000L),
    ),
    [2, 0, 0, 2, -1, 0, 2, -1, 0, -1],
  )
}

///|
test "default Array.lastIndexOf preserves inherited, proxy, and abrupt semantics" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var proto = { 0: "found" };
      #|var inherited = Object.create(proto);
      #|inherited.length = 1;
      #|function inheritedIndex() {
      #|  return Array.prototype.lastIndexOf.call(inherited, "found");
      #|}
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
      #|  try { Array.prototype.lastIndexOf.call(throwing, 1); } catch (_) {}
      #|  return throwingEvents.join("|");
      #|}
    ),
  )
  expect_array_last_index_of_result_963(
    engine.call_json_bounded(
      "inheritedIndex",
      [],
      array_last_index_of_guardrail_policy_963(1000L),
    ),
    0,
  )
  expect_array_last_index_of_result_963(
    engine.call_json_bounded(
      "proxyIndex",
      [],
      array_last_index_of_guardrail_policy_963(1000L),
    ),
    [1, "has:1|get:1"],
  )
  expect_array_last_index_of_result_963(
    engine.call_json_bounded(
      "throwingHas",
      [],
      array_last_index_of_guardrail_policy_963(1000L),
    ),
    "get:length|has:1",
  )
}

///|
test "default Array.lastIndexOf snapshots length and preserves mutation" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var later = { length: 2, 0: 0, 1: 0 };
      #|Object.defineProperty(later, "1", {
      #|  get: function() { later[0] = 1; later.length = 0; return 0; }
      #|});
      #|function mutation() {
      #|  return [Array.prototype.lastIndexOf.call(later, 1), later.length];
      #|}
      #|var fromCalls = 0;
      #|var fromIndex = { valueOf: function() { fromCalls += 1; return 0; } };
      #|function emptyLengthSkipsFromIndex() {
      #|  return [Array.prototype.lastIndexOf.call([], 1, fromIndex), fromCalls];
      #|}
    ),
  )
  expect_array_last_index_of_result_963(
    engine.call_json_bounded(
      "mutation",
      [],
      array_last_index_of_guardrail_policy_963(1000L),
    ),
    [0, 0],
  )
  expect_array_last_index_of_result_963(
    engine.call_json_bounded(
      "emptyLengthSkipsFromIndex",
      [],
      array_last_index_of_guardrail_policy_963(1000L),
    ),
    [-1, 0],
  )
}

///|
test "default Array.lastIndexOf reuses the Engine after budget exhaustion" {
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
      array_last_index_of_guardrail_policy_963(1000L),
    ) {
    Ok(_) => fail("expected Array.lastIndexOf to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("small", []), content=2)
}

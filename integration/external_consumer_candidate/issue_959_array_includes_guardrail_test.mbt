///|
fn candidate_array_includes_guardrail_policy(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid Array.includes execution policy")
  }
}

///|
fn expect_candidate_array_result(
  result : Result[Json, @js_engine.EngineDiagnostic],
  expected : Json,
) -> Unit raise Error {
  match result {
    Ok(value) => json_inspect(value, content=expected)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "candidate Array.includes observes sparse traversal budget" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var sparse = Array(100000); " +
    "function missing() { return sparse.includes(1); }",
  )
  match
    engine.call_json_bounded(
      "missing",
      [],
      candidate_array_includes_guardrail_policy(1000L),
    ) {
    Ok(_) => fail("expected Array.includes to exhaust the execution budget")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
  json_inspect(engine.call_json("missing", []), content=false)
}

///|
test "candidate Array.includes preserves SameValueZero and fromIndex semantics" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var fromIndexObject = { valueOf() { return 1; } };
      #|function boundaries() {
      #|  return [
      #|    [1, 2, 3].includes(2),
      #|    [NaN].includes(NaN),
      #|    [0].includes(-0),
      #|    Array(1).includes(undefined),
      #|    [1, 2, 3].includes(1, 3),
      #|    [1, 2, 3].includes(1, -3),
      #|    [1, 2, 3].includes(1, undefined),
      #|    [1, 2, 3].includes(2, fromIndexObject),
      #|    [1, 2, 3].includes(1, Infinity),
      #|    [1, 2, 3].includes(1, -Infinity)
      #|  ];
      #|}
    ),
  )
  expect_candidate_array_result(
    engine.call_json_bounded(
      "boundaries",
      [],
      candidate_array_includes_guardrail_policy(1000L),
    ),
    [true, true, true, true, false, true, true, true, false, true],
  )
}

///|
test "candidate Array.includes preserves generic getter and length semantics" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var later = { length: 2, 0: 0, 1: 0 };
      #|Object.defineProperty(later, "0", {
      #|  get() { later[1] = 1; later.length = 0; return 0; }
      #|});
      #|function mutation() {
      #|  return [Array.prototype.includes.call(later, 1), later.length];
      #|}
      #|var thrownEvents = "";
      #|var thrown = [0, 0];
      #|Object.defineProperty(thrown, "0", {
      #|  get() { thrownEvents += "a"; throw "boom"; }
      #|});
      #|Object.defineProperty(thrown, "1", {
      #|  get() { thrownEvents += "b"; return 1; }
      #|});
      #|function getterThrow() {
      #|  try { thrown.includes(1); } catch (_) {}
      #|  return thrownEvents;
      #|}
      #|var lengthReads = 0;
      #|var arrayLike = { 0: 1 };
      #|Object.defineProperty(arrayLike, "length", {
      #|  get() { lengthReads += 1; return 1; }
      #|});
      #|function lengthOnce() {
      #|  return [Array.prototype.includes.call(arrayLike, 1), lengthReads];
      #|}
    ),
  )
  expect_candidate_array_result(
    engine.call_json_bounded(
      "mutation",
      [],
      candidate_array_includes_guardrail_policy(1000L),
    ),
    [true, 0],
  )
  expect_candidate_array_result(
    engine.call_json_bounded(
      "getterThrow",
      [],
      candidate_array_includes_guardrail_policy(1000L),
    ),
    "a",
  )
  expect_candidate_array_result(
    engine.call_json_bounded(
      "lengthOnce",
      [],
      candidate_array_includes_guardrail_policy(1000L),
    ),
    [true, 1],
  )
}

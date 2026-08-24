///|
fn candidate_array_complex_guardrail_policy_969(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate Array guard policy")
  }
}

///|
fn expect_candidate_array_complex_guard_969(
  engine : @js_engine.Engine,
  function_name : String,
) -> Unit raise Error {
  match
    engine.call_json_bounded(
      function_name,
      [],
      candidate_array_complex_guardrail_policy_969(1000L),
    ) {
    Ok(_) => fail("expected candidate Array native work to fail closed")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="execution-limit")
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
    }
  }
}

///|
test "candidate Array complex guards reject before native work" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|var sparse = Array(100000);
      #|function sortLarge() { sparse.sort(); return 1; }
      #|function toSortLarge() { return sparse.toSorted().length; }
      #|function flattenLarge() { return sparse.flat().length; }
      #|function flatMapLarge() { return sparse.flatMap(Array).length; }
      #|var iterator = {
      #|  next: function() { return { done: true, value: 0 }; },
      #|  return: function() { return {}; }
      #|};
      #|var source = {};
      #|source[Symbol.iterator] = function() { return iterator; };
      #|function fromEmptyIterator() { return Array.from(source).length; }
    ),
  )
  for
    function_name in [
      "sortLarge", "toSortLarge", "flattenLarge", "flatMapLarge", "fromEmptyIterator",
    ] {
    expect_candidate_array_complex_guard_969(engine, function_name)
  }
}

///|
test "candidate Array complex consumers preserve unbounded results" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function results() {
      #|  return [
      #|    [3, 1, 2].sort().join(","),
      #|    [3, 1, 2].toSorted().join(","),
      #|    [1, [2, 3]].flat().join(","),
      #|    [1, 2].flatMap(function(x) { return [x]; }).join(",")
      #|  ];
      #|}
    ),
  )
  json_inspect(engine.call_json("results", []), content=[
    "1,2,3", "1,2,3", "1,2,3", "1,2",
  ])
}

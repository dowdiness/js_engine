///|
fn candidate_promise_guardrail_policy_977(
  step_budget : Int64,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget,
      100L,
      @js_engine.InterruptionHandle(),
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid candidate Promise execution policy")
  }
}

///|
test "candidate Promise combinators fail closed before native iteration" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977CandidateLargeArray = new Array(100000); " +
    "function issue977CandidateAllLarge() { " +
    "return Promise.all(issue977CandidateLargeArray); } " +
    "function issue977CandidateRaceLarge() { " +
    "return Promise.race(issue977CandidateLargeArray); } " +
    "function issue977CandidateAllSettledLarge() { " +
    "return Promise.allSettled(issue977CandidateLargeArray); } " +
    "function issue977CandidateAnyLarge() { " +
    "return Promise.any(issue977CandidateLargeArray); }",
  )
  for
    function_name in [
      "issue977CandidateAllLarge", "issue977CandidateRaceLarge", "issue977CandidateAllSettledLarge",
      "issue977CandidateAnyLarge",
    ] {
    match
      engine.call_json_bounded(
        function_name,
        [],
        candidate_promise_guardrail_policy_977(1000L),
      ) {
      Ok(_) => fail("candidate Promise bypassed bounded execution control")
      Err(diagnostic) => {
        inspect(diagnostic.failure_kind_code(), content="execution-limit")
        assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::None)
      }
    }
  }
}

///|
test "candidate Promise combinators close each acquired iterator once" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var issue977CandidateNextCalls = 0; " +
    "var issue977CandidateCloseCalls = 0; " +
    "var issue977CandidateIterable = { [Symbol.iterator]() { return { " +
    "next() { issue977CandidateNextCalls += 1; return { done: true }; }, " +
    "return() { issue977CandidateCloseCalls += 1; return {}; } }; } }; " +
    "function issue977CandidateGuardAll() { " +
    "return Promise.all(issue977CandidateIterable); } " +
    "function issue977CandidateGuardRace() { " +
    "return Promise.race(issue977CandidateIterable); } " +
    "function issue977CandidateGuardAllSettled() { " +
    "return Promise.allSettled(issue977CandidateIterable); } " +
    "function issue977CandidateGuardAny() { " +
    "return Promise.any(issue977CandidateIterable); } " +
    "function issue977CandidateCounts() { " +
    "return [issue977CandidateNextCalls, issue977CandidateCloseCalls]; }",
  )
  for
    function_name in [
      "issue977CandidateGuardAll", "issue977CandidateGuardRace", "issue977CandidateGuardAllSettled",
      "issue977CandidateGuardAny",
    ] {
    match
      engine.call_json_bounded(
        function_name,
        [],
        candidate_promise_guardrail_policy_977(1000L),
      ) {
      Ok(_) => fail("candidate guard must reject before the first next call")
      Err(diagnostic) =>
        inspect(diagnostic.failure_kind_code(), content="execution-limit")
    }
  }
  json_inspect(engine.call_json("issue977CandidateCounts", []), content=[0, 4])
}

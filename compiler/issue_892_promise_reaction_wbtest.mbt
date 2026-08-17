///|
// Issue #892 RED: a settled Promise must enqueue its selected reaction as a
// private executor callable while retaining the guest argument in the generic
// microtask carrier.  The current implementation uses an interpreter-native
// callback, so this intentionally fails until the managed reaction seam lands.
test "issue 892 candidate queues a typed Promise reaction executor" {
  let interp = @interpreter.new_interpreter()
  let source =
    #|var seen = 0;
    #|Promise.resolve(1).then(function(value) { seen = value; });
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(interp.host.microtask_queue.length(), 1)
  let task = interp.host.microtask_queue[0]
  match task.callback {
    @runtime.Object({ callable: Some(@runtime.ExecutorCallable(_)), .. }) => ()
    _ => fail("Promise reaction queue entry must be an executor callable")
  }
  assert_eq(task.args.length(), 1)
  assert_eq(task.args[0].to_string(), "1")
}

///|
fn issue892_candidate_run_and_drain_for_wb(
  source : String,
) -> (@runtime.Interpreter, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  interp.run_microtasks()
  (interp, evidence)
}

///|
fn issue892_global_string_for_wb(
  interp : @runtime.Interpreter,
  name : String,
) -> String raise Error {
  match interp.global.get(name) {
    @runtime.String_(value) => value
    value => fail("expected global string, got " + value.to_string())
  }
}

///|
test "issue 892 candidate reaction frame preserves FIFO and deep chaining" {
  let source =
    #|var events = "";
    #|Promise.resolve(1).then(function(value) { events = events + "a" + value; });
    #|Promise.resolve(2).then(function(value) { events = events + "b" + value; });
    #|Promise.resolve(3)
    #|  .then(function(value) { return value + 1; })
    #|  .then(function(value) { return value + 1; })
    #|  .then(function(value) { events = events + "c" + value; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "events"), "a1b2c5")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate managed resolution is first-call-wins" {
  let source =
    #|var resolve;
    #|var reject;
    #|var result = "";
    #|var p = new Promise(function(r, j) { resolve = r; reject = j; });
    #|resolve(1);
    #|reject(2);
    #|resolve(3);
    #|p.then(function(value) { result = "fulfilled:" + value; }, function(error) { result = "rejected:" + error; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "result"), "fulfilled:1")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate managed resolution assimilates thenable failures" {
  let source =
    #|var getterResult = "";
    #|var callResult = "";
    #|Promise.resolve({ get then() { throw "getter"; } }).catch(function(error) { getterResult = error; });
    #|Promise.resolve({ then: function() { throw "call"; } }).catch(function(error) { callResult = error; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "getterResult"), "getter")
  assert_eq(issue892_global_string_for_wb(interp, "callResult"), "call")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate managed resolution handles self and callable Proxy" {
  let source =
    #|var resolve;
    #|var selfResult = "";
    #|var proxyResult = "";
    #|var p = new Promise(function(r) { resolve = r; });
    #|resolve(p);
    #|p.catch(function(error) { selfResult = error instanceof TypeError ? "self" : "wrong"; });
    #|var thenable = new Proxy(function(r) { r(9); }, {});
    #|Promise.resolve({ then: thenable }).then(function(value) { proxyResult = String(value); });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "selfResult"), "self")
  assert_eq(issue892_global_string_for_wb(interp, "proxyResult"), "9")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 892 candidate reaction frame covers missing handlers and throws" {
  let source =
    #|var fulfilled = "";
    #|var rejected = "";
    #|var thrown = "";
    #|Promise.resolve(4).then().then(function(value) { fulfilled = String(value); });
    #|Promise.reject("bad").then(undefined, function(error) { rejected = error; });
    #|Promise.resolve(5).then(function() { throw "handler"; }).catch(function(error) { thrown = error; });
  let (interp, evidence) = issue892_candidate_run_and_drain_for_wb(source)
  assert_eq(issue892_global_string_for_wb(interp, "fulfilled"), "4")
  assert_eq(issue892_global_string_for_wb(interp, "rejected"), "bad")
  assert_eq(issue892_global_string_for_wb(interp, "thrown"), "handler")
  assert_true(evidence.val.summary.bytecode_starts > 1)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

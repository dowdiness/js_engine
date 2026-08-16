///|
// Issue #888 RED coverage. These tests deliberately require candidate bytecode
// admission for only array/call iterable spread; the current contracts still
// select the Tree-walker and therefore fail before the managed request exists.

///|
fn issue888_candidate_route_for_wb(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  candidate_run_with_evidence_for_wb(source)
}

///|
test "RED issue 888 candidate array spread must start bytecode" {
  let source =
    #|var xs = [0, ...[1, 2], 3];
    #|xs.length;
  let (value, evidence) = issue888_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "4")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("array iterable spread remained on the Tree-walker")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "RED issue 888 candidate plain and receiver calls must start bytecode" {
  let source =
    #|function take(first, second, third) { return third; }
    #|var obj = { value: 7, take: function(first, second) { return this.value; } };
    #|take(1, ...[2], 3) + ":" + obj.take(...[1, 2]);
  let (value, evidence) = issue888_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "3:7")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("call iterable spread remained on the Tree-walker")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "RED issue 888 candidate custom iterator records one ordered pass" {
  let source =
    #|var log = "";
    #|var iterable = {};
    #|iterable[Symbol.iterator] = function() {
    #|  var index = 0;
    #|  return { next: function() {
    #|    log = log + "n" + index;
    #|    if (index === 2) return { done: true };
    #|    var value = index;
    #|    index = index + 1;
    #|    return { get value() { log = log + "v" + value; return value; }, done: false };
    #|  } };
    #|};
    #|var xs = ["before", ...iterable, "after"];
    #|log + ":" + xs[0] + "," + xs[1] + "," + xs[2] + "," + xs[3];
  let (value, evidence) = issue888_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "n0v0n1v1n2:before,0,1,after")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("custom iterator spread remained on the Tree-walker")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "RED issue 888 constructor and direct eval spread stay excluded" {
  let ctor_source =
    #|new Object(...[9]).toString();
  let (constructor_value, constructor_evidence) =
    issue888_candidate_route_for_wb(ctor_source)
  assert_eq(constructor_value.to_string(), "9")
  assert_eq(constructor_evidence.val.summary.bytecode_starts, 0)
  assert_eq(constructor_evidence.val.summary.active_activations, 0)
  let direct_eval =
    #|var result = 0;
    #|eval(...["result = 4"]);
    #|result;
  let (eval_value, eval_evidence) = issue888_candidate_route_for_wb(direct_eval)
  assert_eq(eval_value.to_string(), "4")
  assert_eq(eval_evidence.val.summary.bytecode_starts, 0)
  assert_eq(eval_evidence.val.summary.active_activations, 0)
}

///|
// Issue #888 entry-gate and managed-route coverage. These tests require
// candidate bytecode admission only for array/call iterable spread and retain
// typed pre-start exclusions for constructor and direct-eval spread.

///|
fn issue888_candidate_route_for_wb(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  candidate_run_with_evidence_for_wb(source)
}

///|
fn issue888_assert_root_bytecode_for_wb(
  evidence : Ref[CandidateRouteEvidence],
) -> Unit raise Error {
  let root_id = match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) => prepared.activation_id
    _ => fail("candidate evidence must begin with root preparation")
  }
  let mut prepared_bytecode = false
  let mut started_bytecode = false
  for event in evidence.val.events {
    match event {
      CandidateRoutePreparedEvent(prepared) if prepared.activation_id == root_id =>
        match prepared.decision {
          UseBytecode(_) => prepared_bytecode = true
          UseTreeWalker(_) => fail("issue 888 root selected Tree-walker")
        }
      CandidateRouteStartedEvent(started) if started.activation_id == root_id =>
        match started.executor {
          CandidateBytecodeExecutor => started_bytecode = true
          CandidateTreeWalkerExecutor =>
            fail("issue 888 root started Tree-walker")
        }
      _ => ()
    }
  }
  assert_true(prepared_bytecode)
  assert_true(started_bytecode)
}

///|
test "RED issue 888 candidate array spread must start bytecode" {
  let source =
    #|var xs = [0, ...[1, 2], 3];
    #|xs.length;
  let (value, evidence) = issue888_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "4")
  issue888_assert_root_bytecode_for_wb(evidence)
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
  issue888_assert_root_bytecode_for_wb(evidence)
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("call iterable spread remained on the Tree-walker")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "RED issue 888 preserves multiple spreads holes and left-to-right order" {
  let array_source =
    #|var left = [1];
    #|var right = [3];
    #|[0, ...left, , ...right, 4].join(",");
  let (array_value, array_evidence) = issue888_candidate_route_for_wb(
    array_source,
  )
  assert_eq(array_value.to_string(), "0,1,,3,4")
  issue888_assert_root_bytecode_for_wb(array_evidence)
  assert_eq(array_evidence.val.summary.fallback_violations, 0)
  assert_eq(array_evidence.val.summary.replay_violations, 0)
  assert_eq(array_evidence.val.summary.active_activations, 0)
  let call_source =
    #|function collect(first, second, third, fourth, fifth) {
    #|  return [first, second, third, fourth, fifth].join(",");
    #|}
    #|var left = [1];
    #|var right = [3];
    #|var obj = { collect: function(first, second, third, fourth) {
    #|  return this.collector + ":" + [first, second, third, fourth].join(",");
    #|}, collector: "receiver" };
    #|collect(0, ...left, 2, ...right, 4) + ":" + obj.collect(...left, 2, ...right);
  let (call_value, call_evidence) = issue888_candidate_route_for_wb(call_source)
  assert_eq(call_value.to_string(), "0,1,2,3,4:receiver:1,2,3,")
  issue888_assert_root_bytecode_for_wb(call_evidence)
  assert_eq(call_evidence.val.summary.fallback_violations, 0)
  assert_eq(call_evidence.val.summary.replay_violations, 0)
  assert_eq(call_evidence.val.summary.active_activations, 0)
}

///|
test "RED issue 888 candidate custom iterator records one ordered pass" {
  let source =
    #|var log = "";
    #|var iterable = {};
    #|Object.defineProperty(iterable, Symbol.iterator, { value: function() {
    #|  var index = 0;
    #|  return { next: function() {
    #|    log = log + "n" + index;
    #|    if (index === 2) return { done: true };
    #|    var value = index;
    #|    index = index + 1;
    #|    return { get value() { log = log + "v" + value; return value; }, done: false };
    #|  } };
    #|} });
    #|var xs = ["before", ...iterable, "after"];
    #|log + ":" + xs.join(",");
  let (value, evidence) = issue888_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "n0v0n1v1n2:before,0,1,after")
  issue888_assert_root_bytecode_for_wb(evidence)
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("custom iterator spread remained on the Tree-walker")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 888 candidate callable Proxy iterator keeps route hygiene" {
  let source =
    #|var iterable = {};
    #|var calls = 0;
    #|iterable[Symbol.iterator] = new Proxy(function() {}, {
    #|  apply: function(target, thisArg, args) {
    #|    calls = calls + 1;
    #|    return [1, 2][Symbol.iterator]();
    #|  }
    #|});
    #|[...iterable].join(",") + ":" + calls;
  let (value, evidence) = issue888_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "1,2:1")
  issue888_assert_root_bytecode_for_wb(evidence)
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("nested array iterator callback must start Bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "RED issue 888 constructor and direct eval spread stay excluded" {
  let ctor_source =
    #|new Object(...[9]).toString();
  let (constructor_value, constructor_evidence) = issue888_candidate_route_for_wb(
    ctor_source,
  )
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

///|
fn computed_get_candidate_run(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  run_candidate_program_with_evidence(interp, @parser.parse(source).stmts)
}

///|
test "candidate computed get reads a dense numeric array index" {
  let (value, evidence) = computed_get_candidate_run(
    "var values = [7]; values[0];",
  )
  inspect(value.to_string(), content="7")
  assert_eq(evidence.val.summary.bytecode_starts, 1)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed get preserves object-key and getter order" {
  let source =
    #|var trace = "";
    #|var key = { toString: function() { trace = trace + "k"; return "x"; } };
    #|var target = {};
    #|Object.defineProperty(target, "x", {
    #|  get: function() { trace = trace + "g"; return 7; }
    #|});
    #|function read(target, key) { return target[key]; }
    #|var result = read(target, key);
    #|trace + ":" + result;
  let (value, evidence) = computed_get_candidate_run(source)
  inspect(value.to_string(), content="kg:7")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("computed get did not start bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed get validates a nullish base before key conversion" {
  let source =
    #|var trace = "";
    #|var key = { toString: function() { trace = trace + "k"; return "x"; } };
    #|function read(target, key) { return target[key]; }
    #|function attempt(target) {
    #|  try {
    #|    read(target, key);
    #|  } catch (error) {
    #|    trace = trace + (error instanceof TypeError ? "t" : "e");
    #|  }
    #|}
    #|attempt(null);
    #|attempt(undefined);
    #|trace;
  let (value, evidence) = computed_get_candidate_run(source)
  inspect(value.to_string(), content="tt")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("computed null-base get did not start bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate computed get preserves Proxy Symbol traps" {
  let source =
    #|var key = Symbol("key");
    #|var target = {};
    #|Object.defineProperty(target, key, { value: 9 });
    #|var sawKey = false;
    #|var proxy = new Proxy(target, {
    #|  get: function(inner, property, receiver) {
    #|    sawKey = property === key;
    #|    return Reflect.get(inner, property, receiver);
    #|  }
    #|});
    #|function read(target, key) { return target[key]; }
    #|var result = read(proxy, key);
    #|sawKey + ":" + result;
  let (value, evidence) = computed_get_candidate_run(source)
  inspect(value.to_string(), content="true:9")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("computed Proxy get did not start bytecode")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

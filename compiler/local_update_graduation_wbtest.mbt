///|
fn local_update_candidate_run(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let interp = @interpreter.new_interpreter()
  run_candidate_program_with_evidence(interp, @parser.parse(source).stmts)
}

///|
test "local updates preserve expression and stored values across numeric conversion" {
  let cases = [
    ("value++", 4, 5),
    ("++value", 5, 5),
    ("value--", 4, 3),
    ("--value", 3, 3),
  ]
  for entry in cases {
    let (expression, result, stored) = entry
    for input in ["4", "'4'", "({ valueOf: function() { return 4; } })"] {
      let source = "function update(value) {" +
        "var result = \{expression};" +
        "return result === \{result} && value === \{stored};" +
        "} update(\{input});"
      let (value, evidence) = local_update_candidate_run(source)
      assert_true(
        value is Bool(true),
        msg="\{expression} on \{input}: expected result \{result}, stored \{stored}",
      )
      assert_true(evidence.val.summary.bytecode_starts > 0)
      assert_eq(evidence.val.summary.tree_starts, 0)
      assert_eq(evidence.val.summary.fallback_violations, 0)
      assert_eq(evidence.val.summary.replay_violations, 0)
    }
  }
}

///|
test "candidate local update preserves numeric conversion and result order" {
  let source =
    #|function update() {
    #|  var trace = "";
    #|  var postValue = {
    #|    [Symbol.toPrimitive]: function(hint) {
    #|      trace = trace + hint;
    #|      return 4;
    #|    }
    #|  };
    #|  var prefixValue = {
    #|    valueOf: function() {
    #|      trace = trace + "v";
    #|      return 5;
    #|    }
    #|  };
    #|  var postResult = postValue++;
    #|  var prefixResult = ++prefixValue;
    #|  return trace + ":" + postResult + ":" + postValue + ":" + prefixResult + ":" + prefixValue;
    #|}
    #|update();
  let (value, evidence) = local_update_candidate_run(source)
  inspect(value.to_string(), content="numberv:4:5:6:6")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("local update did not start bytecode")
  }
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

///|
test "candidate local update preserves abrupt identity and stack reuse" {
  let source =
    #|var marker = {};
    #|var throwing = {
    #|  [Symbol.toPrimitive]: function() { throw marker; }
    #|};
    #|function update(value) { value++; return value; }
    #|function catchUpdate(value) {
    #|  try { update(value); return false; }
    #|  catch (error) { return error === marker; }
    #|}
    #|catchUpdate(throwing) + ":" + update(1);
  let (value, evidence) = local_update_candidate_run(source)
  inspect(value.to_string(), content="true:2")
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("local update did not resume bytecode after an abrupt conversion")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
}

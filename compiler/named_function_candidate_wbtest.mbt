///|
// Match the function's source coordinates, independently of activation order.
// The expected plan is prepared separately from the observed execution.
#callsite(autofill(loc))
fn assert_candidate_function_started_for_wb(
  evidence : Ref[CandidateRouteEvidence],
  function : CandidateFunction,
  executor : CandidateRouteExecutor,
  loc~ : SourceLoc,
) -> Unit raise Error {
  let starts = evidence.val.events.filter_map(event => {
    match event {
      CandidateRouteStartedEvent(started) if bytecode_source_identity_coordinates_equal_for_wb(
          started.source_identity,
          function.source_identity,
        ) => Some(started.executor)
      _ => None
    }
  })
  assert_true(
    !starts.is_empty(),
    msg="function was not observed executing",
    loc~,
  )
  assert_true(
    starts.iter().all(actual => actual == executor),
    msg="function used an unexpected executor",
    loc~,
  )
}

///|
test "named expression does not force eligible sibling into plain tree" {
  let source =
    #|function eligible() { return 42; }
    #|var named = function self() { return self; };
    #|eligible();
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "42")
  let eligible = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  assert_candidate_function_started_for_wb(
    evidence,
    eligible,
    CandidateBytecodeExecutor,
  )
}

///|
test "local named fallback preserves recursion shadowing and escaped children" {
  let cases = [
    (
      "recursive self-reference", "var f = function self(n) { if (n === 0) return 1; return n * self(n - 1); }; f(5);",
      "120",
    ),
    (
      "parameter shadows self-name", "var f = function self(self) { return self; }; f(42);",
      "42",
    ),
    (
      "var shadows self-name", "var f = function self() { var self = 42; return self; }; f();",
      "42",
    ),
    (
      "let shadows self-name", "var f = function self() { let self = 42; return self; }; f();",
      "42",
    ),
    (
      "default closure captures self-name before body shadowing", "var f = function self(read = function() { return self; }) { var self = 42; return read(); }; f() === f;",
      "true",
    ),
    (
      "escaped closure retains self-name after outer reassignment", "var f = function self() { return function() { return self; }; }; var read = f(); var saved = f; f = null; read() === saved;",
      "true",
    ),
    (
      "sloppy assignment preserves self-name", "var f = function self() { self = 42; return self; }; f() === f;",
      "true",
    ),
  ]
  for pair in cases {
    let (behavior, source, expected) = pair
    let tree = @interpreter.new_interpreter()
    assert_eq(
      tree.run(@parser.parse(source).stmts).to_string(),
      expected,
      msg="tree: " + behavior,
    )
    let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected, msg="candidate: " + behavior)
    assert_eq(evidence.val.summary.active_activations, 0)
    assert_eq(evidence.val.summary.fallback_violations, 0)
    assert_eq(evidence.val.summary.replay_violations, 0)
  }
}

///|
test "named fallback retains bytecode descendant and original source across turns" {
  let source =
    #|var f = function self() { return function() { return self; }; };
    #|var read = f();
  let interp = @interpreter.new_interpreter()
  let (_, original) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  let (value, later) = run_candidate_program_with_evidence(
    interp,
    @parser.parse("read() === f;").stmts,
  )
  assert_eq(value.to_string(), "true")
  let named = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  let escaped = named.children[0]
  assert_candidate_function_started_for_wb(
    original,
    named,
    CandidateTreeWalkerExecutor,
  )
  assert_candidate_function_started_for_wb(
    original,
    escaped,
    CandidateBytecodeExecutor,
  )
  // Calls made in a later turn still belong to the original source's recorder.
  assert_eq(later.val.summary.bytecode_starts, 1)
  assert_eq(original.val.summary.active_activations, 0)
}

///|
test "named fallback preserves Promise callback self binding after another turn" {
  let source =
    #|var result = false;
    #|var f = function self() {
    #|  Promise.resolve().then(function() { result = self === f; });
    #|};
    #|f();
  let tree = @interpreter.new_interpreter()
  let _ = tree.run(@parser.parse(source).stmts)
  let interp = @interpreter.new_interpreter()
  let (_, evidence) = run_candidate_program_with_evidence(
    interp,
    @parser.parse(source).stmts,
  )
  let _ = run_candidate_program_with_evidence(
    interp,
    @parser.parse("var unrelated = 1;").stmts,
  )
  tree.run_microtasks()
  interp.run_microtasks()
  assert_eq(tree.global.get("result").to_string(), "true")
  assert_eq(interp.global.get("result").to_string(), "true")
  let named = prepare_candidate_program(@parser.parse(source).stmts).root.children[0]
  let callback = named.children[0]
  assert_candidate_function_started_for_wb(
    evidence,
    named,
    CandidateTreeWalkerExecutor,
  )
  assert_candidate_function_started_for_wb(
    evidence,
    callback,
    CandidateBytecodeExecutor,
  )
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "local named fallback does not admit excluded async or generator families" {
  for
    excluded in [
      "function* g() { yield 1; }", "var g = function*() { yield 1; };", "async function g() { return 1; }",
      "var g = async function() { return 1; };", "var g = async () => 1;", "async function* g() { yield 1; }",
      "var g = async function*() { yield 1; };", "var g = { *m() { yield 1; } };",
      "var g = { async m() { return 1; } };", "var g = { async *m() { yield 1; } };",
    ] {
    let (value, evidence) = candidate_run_with_evidence_for_wb(
      "var named = function self() {}; " +
      excluded +
      " function eligible() { return 42; } eligible();",
    )
    assert_eq(value.to_string(), "42")
    // These forms must retain whole-program fallback, even with an eligible sibling.
    assert_eq(evidence.val.summary.tree_starts, 1, msg=excluded)
    assert_eq(evidence.val.summary.bytecode_starts, 0, msg=excluded)
  }
}

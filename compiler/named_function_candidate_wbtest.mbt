///|
test "named expression does not force eligible sibling into plain tree" {
  let (value, evidence) = candidate_run_with_evidence_for_wb(
    "function eligible() { return 42; } var named = function self() { return self; }; eligible();",
  )
  assert_eq(value.to_string(), "42")
  assert_eq(candidate_started_executor_labels_for_wb(evidence), "tree,bytecode")
}

///|
test "local named fallback preserves recursion shadowing and escaped children" {
  let cases = [
    (
      "var f = function self(n) { if (n === 0) return 1; return n * self(n - 1); }; f(5);",
      "120",
    ),
    ("var f = function self(self) { return self; }; f(42);", "42"),
    ("var f = function self() { var self = 42; return self; }; f();", "42"),
    ("var f = function self() { let self = 42; return self; }; f();", "42"),
    (
      "var f = function self(read = function() { return self; }) { var self = 42; return read(); }; f() === f;",
      "true",
    ),
    (
      "var f = function self() { return function() { return self; }; }; var read = f(); var saved = f; f = null; read() === saved;",
      "true",
    ),
    ("var f = function self() { self = 42; return self; }; f() === f;", "true"),
  ]
  for pair in cases {
    let (source, expected) = pair
    let tree = @interpreter.new_interpreter()
    assert_eq(tree.run(@parser.parse(source).stmts).to_string(), expected)
    let (actual, evidence) = candidate_run_with_evidence_for_wb(source)
    assert_eq(actual.to_string(), expected)
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
  assert_eq(
    candidate_started_executor_labels_for_wb(original),
    "tree,tree,bytecode",
  )
  assert_eq(later.val.summary.bytecode_starts, 1)
  let starts = original.val.events.filter_map(event => {
    match event {
      CandidateRouteStartedEvent(started) => Some(started)
      _ => None
    }
  })
  assert_eq(starts[2].source_identity.child_index, Some(0))
  assert_true(
    !bytecode_source_identity_equal(
      starts[1].source_identity,
      starts[2].source_identity,
    ),
  )
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
  assert_eq(
    candidate_started_executor_labels_for_wb(evidence),
    "tree,tree,bytecode",
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
    assert_eq(candidate_started_executor_labels_for_wb(evidence), "tree")
  }
}

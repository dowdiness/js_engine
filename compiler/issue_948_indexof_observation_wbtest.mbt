///|
test "candidate String.indexOf keeps the search function on Bytecode" {
  let source = "var large = \"x\".repeat(100000); " +
    "function indexOfMissing() { return large.indexOf(\"z\"); } " +
    "indexOfMissing();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("indexOf fixture must contain one function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) =>
      fail("String.indexOf function lost bytecode eligibility")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "-1")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

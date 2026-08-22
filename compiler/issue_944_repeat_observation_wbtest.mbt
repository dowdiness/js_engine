///|
test "candidate String.repeat function remains bytecode-eligible" {
  let source = "function repeatLength() { return \"x\".repeat(100000).length; } " +
    "repeatLength();"
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  guard program.root.children.length() == 1 else {
    fail("repeat fixture must contain one function candidate")
  }
  match program.root.children[0].selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("String.repeat function lost bytecode eligibility")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "100000")
  assert_eq(evidence.val.summary.bytecode_starts, 2)
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
// Issue #931 RED: a name update is currently typed pre-start, so the
// candidate route falls back before executing the UpdateName instruction.

///|
test "issue 931 candidate admits typed UpdateName" {
  let (value, evidence) = candidate_run_with_evidence_for_wb(
    "var value = 1; value++; value;",
  )
  assert_eq(value.to_string(), "2")
  assert_true(evidence.val.summary.bytecode_starts > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "Execution Session integrity policy fails closed unless reusable" {
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::Reusable)
    is Available,
  )
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::Discard) is Faulted,
  )
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::Unknown) is Faulted,
  )
  assert_true(
    execution_session_state_after_integrity(EngineIntegrity::NotApplicable)
    is Faulted,
  )
}

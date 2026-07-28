///|
test "required transcript covers every P1 scenario" {
  let transcript = required_transcript()
  assert_eq(transcript.length(), 97)
  let required_scenarios = [
    "read_without_approval_then_dispatch", "write_approved_success", "operator_rejects_write",
    "cancel_waiting_approval", "cancel_during_validation", "cancel_after_approval_before_dispatch",
    "duplicate_dispatch_blocked", "unknown_tool_rejected", "malformed_arguments_rejected",
    "worker_authority_escalation_rejected", "worker_host_action_injection_rejected",
    "capability_denied", "adapter_failure_sanitized", "approved_write_adapter_failure_no_commit",
    "credential_bearing_adapter_result_rejected", "stale_host_call_id_blocked", "tool_count_exact_and_exhausted",
    "request_bytes_exact_boundary", "request_bytes_over_limit",
  ]
  for scenario in required_scenarios {
    let needle = "\"scenario\":\"" + scenario + "\""
    assert_true(transcript.any(line => line.contains(needle)))
  }
}

///|
test "credential canary is absent from the transcript" {
  let transcript = required_transcript()
  assert_false(
    transcript.any(line => {
      line.contains("p1-fake-credential-canary-do-not-leak")
    }),
  )
}

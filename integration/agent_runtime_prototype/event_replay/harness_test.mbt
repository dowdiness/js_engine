///|
test "PROTOTYPE event log recovers write result without a second write" {
  let transcript = required_transcript()
  let joined = transcript.join("\n")
  assert_true(transcript.length() >= 20)
  assert_true(joined.contains("\"action\":\"crash_after_tool_result\""))
  assert_true(joined.contains("\"action\":\"replay\""))
  assert_true(joined.contains("\"fake_external_write_commits\":1"))
  assert_true(joined.contains("\"replay_adapter_invocations\":0"))
  assert_true(joined.contains("\"verdict\":\"GO\""))
}

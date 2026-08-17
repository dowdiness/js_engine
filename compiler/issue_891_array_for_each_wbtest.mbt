///|
// Issue #891 first RED: Array.prototype.forEach must preserve an abrupt
// Proxy [[HasProperty]] completion while the candidate root is bytecode.
test "RED issue 891 candidate forEach preserves Proxy has abrupt completion" {
  let source =
    #|var events = [];
    #|var target = [1];
    #|var receiver = new Proxy(target, { has: function() { events.push("has"); throw new Error("has"); } });
    #|var result = "none";
    #|try { Array.prototype.forEach.call(receiver, function() { events.push("callback"); }); }
    #|catch (error) { result = error instanceof Error ? error.message : "other"; }
    #|result + ":" + events.join(",");
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "has:has")
  assert_true(evidence.val.summary.bytecode_starts > 0)
}

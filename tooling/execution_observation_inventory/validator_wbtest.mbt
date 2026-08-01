///|
fn six_family_manifest(first_row : String) -> String {
  let first_row = if first_row.contains("\"accounting_entry_id\"") {
    first_row
  } else {
    first_row.replace(
      old="\"operation_family\":",
      new="\"accounting_entry_id\":\"fixture-first-entry\",\"operation_family\":",
    )
  }
  let rest =
    #|{"id":"expression","accounting_entry_id":"fixture-expression-entry","operation_family":"expression dispatch","current_accounting_owner":"expression","intended_final_accounting_owner":"expression","status":"observed-exactly-once","owning_implementation_or_issue":"expression","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"bounded","accounting_entry_id":"fixture-bounded-entry","operation_family":"bounded evaluation","current_accounting_owner":"bounded","intended_final_accounting_owner":"bounded","status":"observed-exactly-once","owning_implementation_or_issue":"bounded","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"activation","accounting_entry_id":"fixture-activation-entry","operation_family":"activation dispatch","current_accounting_owner":"activation","intended_final_accounting_owner":"activation","status":"observed-exactly-once","owning_implementation_or_issue":"activation","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"microtask","accounting_entry_id":"fixture-microtask-entry","operation_family":"microtask policy","current_accounting_owner":"microtask","intended_final_accounting_owner":"microtask","status":"observed-exactly-once","owning_implementation_or_issue":"microtask","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"timer","accounting_entry_id":"fixture-timer-entry","operation_family":"timer policy","current_accounting_owner":"timer","intended_final_accounting_owner":"timer","status":"observed-exactly-once","owning_implementation_or_issue":"timer","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false}
  "{\"version\":1,\"contract\":\"docs/decisions/engine-execution-guardrail-contract.md\",\"rows\":[" +
  first_row +
  "," +
  rest +
  "]}"
}

///|
fn paired_family_manifest(first_row : String, second_row : String) -> String {
  let first_row = if first_row.contains("\"accounting_entry_id\"") {
    first_row
  } else {
    first_row.replace(
      old="\"operation_family\":",
      new="\"accounting_entry_id\":\"fixture-first-entry\",\"operation_family\":",
    )
  }
  let second_row = if second_row.contains("\"accounting_entry_id\"") {
    second_row
  } else {
    second_row.replace(
      old="\"operation_family\":",
      new="\"accounting_entry_id\":\"fixture-second-entry\",\"operation_family\":",
    )
  }
  let rest =
    #|{"id":"bounded","accounting_entry_id":"fixture-bounded-entry","operation_family":"bounded evaluation","current_accounting_owner":"bounded","intended_final_accounting_owner":"bounded","status":"observed-exactly-once","owning_implementation_or_issue":"bounded","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"activation","accounting_entry_id":"fixture-activation-entry","operation_family":"activation dispatch","current_accounting_owner":"activation","intended_final_accounting_owner":"activation","status":"observed-exactly-once","owning_implementation_or_issue":"activation","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"microtask","accounting_entry_id":"fixture-microtask-entry","operation_family":"microtask policy","current_accounting_owner":"microtask","intended_final_accounting_owner":"microtask","status":"observed-exactly-once","owning_implementation_or_issue":"microtask","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"timer","accounting_entry_id":"fixture-timer-entry","operation_family":"timer policy","current_accounting_owner":"timer","intended_final_accounting_owner":"timer","status":"observed-exactly-once","owning_implementation_or_issue":"timer","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false}
  "{\"version\":1,\"contract\":\"docs/decisions/engine-execution-guardrail-contract.md\",\"rows\":[" +
  first_row +
  "," +
  second_row +
  "," +
  rest +
  "]}"
}

///|
fn tracking_issue_manifest(issue : String) -> String {
  six_family_manifest(
    "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"none\",\"intended_final_accounting_owner\":\"statement observation\",\"status\":\"unobserved\",\"owning_implementation_or_issue\":\"" +
    issue +
    "\",\"tracking_issue\":\"" +
    issue +
    "\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}",
  )
}

///|
test "validator accepts distinct accounting entries with one final owner" {
  let row = "\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"same\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false"
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\"," +
    row +
    "}"
  let second = "{\"id\":\"expression\",\"operation_family\":\"expression dispatch\"," +
    row +
    "}"
  match
    validate_manifest_text(
      paired_family_manifest(first, second),
      "same-final-owner.json",
    ) {
    Ok(_) => ()
    Err(message) =>
      fail("distinct accounting entries should validate: " + message)
  }
}

///|
test "validator accepts contract-excluded host JSON conversion" {
  let first =
    #|{"id":"statement","accounting_entry_id":"host-json-conversion-entry","operation_family":"statement dispatch","current_accounting_owner":"json bridge","intended_final_accounting_owner":"json bridge exclusion","status":"bounded-by-proof","owning_implementation_or_issue":"json bridge","focused_evidence":["fixture.mbt#anchor"],"entry_category":"direct host JSON conversion","contract_observation_category":"host-json-conversion","duplicate_charge_risk":"conversion must remain unobserved","public_facade_evidence_required":false}
  match
    validate_manifest_text(
      six_family_manifest(first),
      "host-json-conversion.json",
    ) {
    Ok(_) => ()
    Err(message) =>
      fail("contract-excluded host JSON conversion should validate: " + message)
  }
}

///|
test "validator rejects missing accounting owner" {
  let manifest = six_family_manifest(
    "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\"}",
  )
  let result = validate_manifest_text(manifest, "missing-owner.json")
  match result {
    Ok(_) => fail("expected missing accounting owner rejection")
    Err(message) => assert_true(message.contains("current_accounting_owner"))
  }
}

///|
test "validator rejects missing operation family" {
  let manifest =
    #|{"version": 1, "contract": "docs/decisions/engine-execution-guardrail-contract.md", "rows": [{"id": "row"}]}
  let result = validate_manifest_text(manifest, "missing-family.json")
  match result {
    Ok(_) => fail("expected missing operation family rejection")
    Err(message) => assert_true(message.contains("operation_family"))
  }
}

///|
test "validator rejects unobserved row without issue ownership" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"none\",\"intended_final_accounting_owner\":\"statement observation\",\"status\":\"unobserved\"}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "orphan-row.json",
  )
  match result {
    Ok(_) => fail("expected orphan row rejection")
    Err(message) =>
      assert_true(message.contains("owning_implementation_or_issue"))
  }
}

///|
test "validator rejects non-unobserved issue owner" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"statement\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"#999\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "observed-issue-owner.json",
  )
  match result {
    Ok(_) => fail("expected non-unobserved issue owner rejection")
    Err(message) => assert_true(message.contains("must not begin with #"))
  }
}

///|
test "validator rejects tracking issue on observed row" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"statement\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"implementation\",\"tracking_issue\":\"#749\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "observed-tracking-issue.json",
  )
  match result {
    Ok(_) => fail("expected observed tracking issue rejection")
    Err(message) =>
      assert_true(
        message.contains("only unobserved rows may have tracking_issue"),
      )
  }
}

///|
test "validator rejects invalid status" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"b\",\"status\":\"not-a-status\",\"owning_implementation_or_issue\":\"a\"}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "invalid-status.json",
  )
  match result {
    Ok(_) => fail("expected invalid status rejection")
    Err(message) => assert_true(message.contains("invalid status"))
  }
}

///|
test "validator rejects zero tracking issue" {
  let result = validate_manifest_text(
    tracking_issue_manifest("#0"),
    "zero-tracking-issue.json",
  )
  match result {
    Ok(_) => fail("expected zero tracking issue rejection")
    Err(message) =>
      assert_true(message.contains("positive integer issue reference"))
  }
}

///|
test "validator rejects tracking issue outside fixed registry" {
  let result = validate_manifest_text(
    tracking_issue_manifest("#762"),
    "outside-tracking-registry.json",
  )
  match result {
    Ok(_) => fail("expected tracking registry rejection")
    Err(message) => assert_true(message.contains("permitted Stage 4 registry"))
  }
}

///|
test "validator rejects empty focused evidence reference" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"b\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "empty-focused-evidence.json",
  )
  match result {
    Ok(_) => fail("expected empty focused evidence rejection")
    Err(message) => assert_true(message.contains("path#anchor"))
  }
}

///|
test "validator rejects focused evidence without anchor" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"b\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "missing-focused-anchor.json",
  )
  match result {
    Ok(_) => fail("expected missing focused anchor rejection")
    Err(message) => assert_true(message.contains("path#anchor"))
  }
}

///|
test "validator rejects public facade evidence without anchor" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"b\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":true,\"public_facade_evidence\":[\"fixture.mbt\"]}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "missing-public-facade-anchor.json",
  )
  match result {
    Ok(_) => fail("expected missing public facade anchor rejection")
    Err(message) => assert_true(message.contains("path#anchor"))
  }
}

///|
test "validator rejects observed row without evidence" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"b\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\"}"
  let result = validate_manifest_text(
    six_family_manifest(first),
    "missing-evidence.json",
  )
  match result {
    Ok(_) => fail("expected missing evidence rejection")
    Err(message) => assert_true(message.contains("focused_evidence"))
  }
}

///|
test "validator rejects duplicate row identifiers" {
  let manifest =
    #|{"version": 1, "contract": "docs/decisions/engine-execution-guardrail-contract.md", "rows": [
    #|  {"id": "dup", "accounting_entry_id": "duplicate-first", "operation_family": "statement dispatch", "current_accounting_owner": "a", "intended_final_accounting_owner": "b", "status": "observed-exactly-once", "owning_implementation_or_issue": "a", "focused_evidence": ["fixture.mbt#anchor"], "entry_category": "entry", "contract_observation_category": "dispatch-point", "duplicate_charge_risk": "risk", "public_facade_evidence_required": false},
    #|  {"id": "dup", "accounting_entry_id": "duplicate-second", "operation_family": "statement dispatch", "current_accounting_owner": "a", "intended_final_accounting_owner": "b", "status": "observed-exactly-once", "owning_implementation_or_issue": "a", "focused_evidence": ["fixture.mbt#anchor"], "entry_category": "entry", "contract_observation_category": "dispatch-point", "duplicate_charge_risk": "risk", "public_facade_evidence_required": false}
    #|]}
  let result = validate_manifest_text(manifest, "duplicate-id.json")
  match result {
    Ok(_) => fail("expected duplicate row identifier rejection")
    Err(message) => assert_true(message.contains("duplicate row identifier"))
  }
}

///|
test "validator rejects duplicate accounting entry identifiers" {
  let row = "\"accounting_entry_id\":\"same-entry\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"owner\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false"
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\"," +
    row +
    "}"
  let second = "{\"id\":\"expression\",\"operation_family\":\"expression dispatch\"," +
    row.replace(
      old="\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"owner\"",
      new="\"current_accounting_owner\":\"b\",\"intended_final_accounting_owner\":\"other-owner\"",
    ) +
    "}"
  let result = validate_manifest_text(
    paired_family_manifest(first, second),
    "duplicate-accounting-entry.json",
  )
  match result {
    Ok(_) => fail("expected duplicate accounting entry rejection")
    Err(message) => assert_true(message.contains("accounting entry"))
  }
}

///|
test "validator rejects empty row identifier" {
  let first = "{\"id\":\"\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"statement\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}"
  match
    validate_manifest_text(six_family_manifest(first), "empty-row-id.json") {
    Ok(_) => fail("expected empty row identifier rejection")
    Err(message) => assert_true(message.contains("row id must not be empty"))
  }
}

///|
test "validator rejects empty accounting entry identifier" {
  let first = "{\"id\":\"statement\",\"accounting_entry_id\":\"\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"statement\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}"
  match
    validate_manifest_text(
      six_family_manifest(first),
      "empty-accounting-entry.json",
    ) {
    Ok(_) => fail("expected empty accounting entry rejection")
    Err(message) =>
      assert_true(message.contains("accounting_entry_id must not be empty"))
  }
}

///|
test "validator rejects backslash parent traversal evidence" {
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"statement\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"..\\\\outside.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}"
  match
    validate_manifest_text(
      six_family_manifest(first),
      "backslash-traversal.json",
    ) {
    Ok(_) => fail("expected backslash traversal rejection")
    Err(message) => assert_true(message.contains("repository-relative"))
  }
}

///|
test "validator rejects incorrect contract" {
  let manifest = six_family_manifest(
    "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\",\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"statement\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false}",
  ).replace(
    old="docs/decisions/engine-execution-guardrail-contract.md",
    new="docs/decisions/other-contract.md",
  )
  match validate_manifest_text(manifest, "incorrect-contract.json") {
    Ok(_) => fail("expected incorrect contract rejection")
    Err(message) => assert_true(message.contains("contract must be"))
  }
}

///|
test "valid seeded manifest" {
  let text = @fs.read_file_to_string(
    "scripts/execution_observation_inventory.json",
  ) catch {
    _ => fail("could not read seeded manifest")
  }
  match
    validate_manifest_text(text, "scripts/execution_observation_inventory.json") {
    Ok(_) => ()
    Err(message) => fail("seeded manifest should validate: " + message)
  }
}

///|
fn seeded_inventory_row(
  rows : Array[Map[String, Json]],
  id : String,
) -> Map[String, Json] raise {
  let matches = rows.filter(row => {
    match row.get("id") {
      Some(value) => (@json.from_json(value) catch { _ => "" }) == id
      None => false
    }
  })
  assert_eq(matches.length(), 1)
  matches[0]
}

///|
fn assert_seeded_unobserved_issue_row(
  rows : Array[Map[String, Json]],
  id : String,
  issue : String,
) -> Unit raise {
  let row = seeded_inventory_row(rows, id)
  let status : String = @json.from_json(row["status"])
  let owner : String = @json.from_json(row["owning_implementation_or_issue"])
  let tracking : String = @json.from_json(row["tracking_issue"])
  assert_eq(status, "unobserved")
  assert_eq(owner, issue)
  assert_eq(tracking, issue)
}

///|
test "seeded queue accounting distinguishes implemented and tracked rows" {
  let root : Map[String, Json] = @json.from_json(
    @json.parse(
      @fs.read_file_to_string("scripts/execution_observation_inventory.json") catch {
        _ => fail("could not read seeded manifest")
      },
    ),
  )
  let rows : Array[Map[String, Json]] = @json.from_json(root["rows"])
  let microtask = seeded_inventory_row(rows, "microtask-policy-queue-entry")
  let microtask_status : String = @json.from_json(microtask["status"])
  let microtask_owner : String = @json.from_json(
    microtask["owning_implementation_or_issue"],
  )
  assert_eq(microtask_status, "observed-exactly-once")
  assert_eq(
    microtask_owner, "interpreter/runtime/promise_core.mbt#Interpreter::run_microtasks_observed",
  )
  assert_true(microtask.get("tracking_issue") is None)
  assert_seeded_unobserved_issue_row(rows, "timer-policy-queue-entry", "#750")
}

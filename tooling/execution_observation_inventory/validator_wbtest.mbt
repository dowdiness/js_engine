///|
fn six_family_manifest(first_row : String) -> String {
  let rest =
    #|{"id":"expression","operation_family":"expression dispatch","current_accounting_owner":"expression","intended_final_accounting_owner":"expression","status":"observed-exactly-once","owning_implementation_or_issue":"expression","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"bounded","operation_family":"bounded evaluation","current_accounting_owner":"bounded","intended_final_accounting_owner":"bounded","status":"observed-exactly-once","owning_implementation_or_issue":"bounded","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"activation","operation_family":"activation dispatch","current_accounting_owner":"activation","intended_final_accounting_owner":"activation","status":"observed-exactly-once","owning_implementation_or_issue":"activation","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"microtask","operation_family":"microtask policy","current_accounting_owner":"microtask","intended_final_accounting_owner":"microtask","status":"observed-exactly-once","owning_implementation_or_issue":"microtask","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"timer","operation_family":"timer policy","current_accounting_owner":"timer","intended_final_accounting_owner":"timer","status":"observed-exactly-once","owning_implementation_or_issue":"timer","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false}
  "{\"version\":1,\"rows\":[" + first_row + "," + rest + "]}"
}

///|
fn paired_family_manifest(first_row : String, second_row : String) -> String {
  let rest =
    #|{"id":"bounded","operation_family":"bounded evaluation","current_accounting_owner":"bounded","intended_final_accounting_owner":"bounded","status":"observed-exactly-once","owning_implementation_or_issue":"bounded","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"activation","operation_family":"activation dispatch","current_accounting_owner":"activation","intended_final_accounting_owner":"activation","status":"observed-exactly-once","owning_implementation_or_issue":"activation","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"microtask","operation_family":"microtask policy","current_accounting_owner":"microtask","intended_final_accounting_owner":"microtask","status":"observed-exactly-once","owning_implementation_or_issue":"microtask","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false},
    #|{"id":"timer","operation_family":"timer policy","current_accounting_owner":"timer","intended_final_accounting_owner":"timer","status":"observed-exactly-once","owning_implementation_or_issue":"timer","focused_evidence":["fixture.mbt#anchor"],"entry_category":"entry","contract_observation_category":"dispatch-point","duplicate_charge_risk":"risk","public_facade_evidence_required":false}
  "{\"version\":1,\"rows\":[" + first_row + "," + second_row + "," + rest + "]}"
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
test "validator rejects duplicate final accounting owners" {
  let row = "\"current_accounting_owner\":\"a\",\"intended_final_accounting_owner\":\"same\",\"status\":\"observed-exactly-once\",\"owning_implementation_or_issue\":\"a\",\"focused_evidence\":[\"fixture.mbt#anchor\"],\"entry_category\":\"entry\",\"contract_observation_category\":\"dispatch-point\",\"duplicate_charge_risk\":\"risk\",\"public_facade_evidence_required\":false"
  let first = "{\"id\":\"statement\",\"operation_family\":\"statement dispatch\"," +
    row +
    "}"
  let second = "{\"id\":\"expression\",\"operation_family\":\"expression dispatch\"," +
    row +
    "}"
  let result = validate_manifest_text(
    paired_family_manifest(first, second),
    "duplicate-owner.json",
  )
  match result {
    Ok(_) => fail("expected duplicate final owner rejection")
    Err(message) => assert_true(message.contains("final accounting owner"))
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
    #|{"version": 1, "rows": [{"id": "row"}]}
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
    #|{"version": 1, "rows": [
    #|  {"id": "dup", "operation_family": "statement dispatch", "current_accounting_owner": "a", "intended_final_accounting_owner": "b", "status": "observed-exactly-once", "owning_implementation_or_issue": "a", "focused_evidence": ["fixture.mbt#anchor"], "entry_category": "entry", "contract_observation_category": "dispatch-point", "duplicate_charge_risk": "risk", "public_facade_evidence_required": false},
    #|  {"id": "dup", "operation_family": "statement dispatch", "current_accounting_owner": "a", "intended_final_accounting_owner": "b", "status": "observed-exactly-once", "owning_implementation_or_issue": "a", "focused_evidence": ["fixture.mbt#anchor"], "entry_category": "entry", "contract_observation_category": "dispatch-point", "duplicate_charge_risk": "risk", "public_facade_evidence_required": false}
    #|]}
  let result = validate_manifest_text(manifest, "duplicate-id.json")
  match result {
    Ok(_) => fail("expected duplicate row identifier rejection")
    Err(message) => assert_true(message.contains("duplicate row identifier"))
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
fn assert_seeded_unobserved_issue_row(
  rows : Array[Map[String, Json]],
  id : String,
  issue : String,
) -> Unit raise {
  let matches = rows.filter(row => {
    match row.get("id") {
      Some(value) => (@json.from_json(value) catch { _ => "" }) == id
      None => false
    }
  })
  assert_eq(matches.length(), 1)
  let row = matches[0]
  let status : String = @json.from_json(row["status"])
  let owner : String = @json.from_json(row["owning_implementation_or_issue"])
  let tracking : String = @json.from_json(row["tracking_issue"])
  assert_eq(status, "unobserved")
  assert_eq(owner, issue)
  assert_eq(tracking, issue)
}

///|
test "seeded queue gaps are owned by their tracking issues" {
  let root : Map[String, Json] = @json.from_json(
    @json.parse(
      @fs.read_file_to_string("scripts/execution_observation_inventory.json") catch {
        _ => fail("could not read seeded manifest")
      },
    ),
  )
  let rows : Array[Map[String, Json]] = @json.from_json(root["rows"])
  assert_seeded_unobserved_issue_row(
    rows, "microtask-policy-queue-entry", "#749",
  )
  assert_seeded_unobserved_issue_row(rows, "timer-policy-queue-entry", "#750")
}

///|
fn valid_manifest_text() -> String {
  let text =
    #|{
    #|  "schema_version": 1,
    #|  "version": "0.8.0",
    #|  "candidate_tree": "0123456789abcdef",
    #|  "unit_tests": { "passed": 2621, "executed": 2621 },
    #|  "test262": {
    #|    "run_id": "30346236658",
    #|    "source_commit": "265bbfd89cef02bc",
    #|    "source_tree": "0123456789abcdef",
    #|    "corpus_commit": "abcdef0123456789",
    #|    "result_schema_version": 1,
    #|    "summary_sha256": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    #|    "skip_metadata_sha256": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    #|    "edition_report_sha256": "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    #|    "strict": {
    #|      "passed": 31737,
    #|      "executed": 34770,
    #|      "discovered": 44986,
    #|      "skipped": 10201
    #|    },
    #|    "non_strict": {
    #|      "passed": 33554,
    #|      "executed": 37001,
    #|      "discovered": 47692,
    #|      "skipped": 10672
    #|    }
    #|  },
    #|  "package": {
    #|    "content_sha256": "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    #|    "file_count": 444
    #|  }
    #|}
  text
}

///|
fn manifest_is_rejected(input : String) -> Bool {
  let result : Result[ReleaseCandidateManifest, ReleaseContractError] = Ok(
    parse_manifest(input),
  ) catch {
    error => Err(error)
  }
  match result {
    Err(ReleaseContractError::InvalidManifest(_)) => true
    Ok(_) => false
  }
}

///|
test "release candidate manifest round trips without losing evidence" {
  let manifest = parse_manifest(valid_manifest_text())
  let actual = @json.parse(render_manifest(manifest))
  assert_eq(actual, @json.parse(valid_manifest_text()))
}

///|
test "release candidate manifest rejects empty identity evidence" {
  let input = valid_manifest_text().replace(
    old="\"candidate_tree\": \"0123456789abcdef\"",
    new="\"candidate_tree\": \"\"",
  )
  assert_true(manifest_is_rejected(input))
}

///|
test "release candidate manifest rejects empty provenance evidence" {
  let replacements = [
    ("\"version\": \"0.8.0\"", "\"version\": \"\""),
    ("\"run_id\": \"30346236658\"", "\"run_id\": \"\""),
    ("\"source_commit\": \"265bbfd89cef02bc\"", "\"source_commit\": \"\""),
    ("\"source_tree\": \"0123456789abcdef\"", "\"source_tree\": \"\""),
    ("\"corpus_commit\": \"abcdef0123456789\"", "\"corpus_commit\": \"\""),
    (
      "\"summary_sha256\": \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"",
      "\"summary_sha256\": \"\"",
    ),
    (
      "\"skip_metadata_sha256\": \"sha256:1111111111111111111111111111111111111111111111111111111111111111\"",
      "\"skip_metadata_sha256\": \"\"",
    ),
    (
      "\"edition_report_sha256\": \"sha256:2222222222222222222222222222222222222222222222222222222222222222\"",
      "\"edition_report_sha256\": \"\"",
    ),
    (
      "\"content_sha256\": \"sha256:3333333333333333333333333333333333333333333333333333333333333333\"",
      "\"content_sha256\": \"\"",
    ),
  ]
  for replacement in replacements {
    let (old, new) = replacement
    assert_true(manifest_is_rejected(valid_manifest_text().replace(old~, new~)))
  }
}

///|
test "release candidate manifest rejects impossible counts" {
  let replacements = [
    (
      "\"unit_tests\": { \"passed\": 2621, \"executed\": 2621 }", "\"unit_tests\": { \"passed\": -1, \"executed\": 2621 }",
    ),
    (
      "\"unit_tests\": { \"passed\": 2621, \"executed\": 2621 }", "\"unit_tests\": { \"passed\": 2622, \"executed\": 2621 }",
    ),
    ("\"result_schema_version\": 1", "\"result_schema_version\": 0"),
    ("\"passed\": 31737", "\"passed\": -1"),
    ("\"passed\": 31737", "\"passed\": 34771"),
    ("\"executed\": 34770", "\"executed\": 44987"),
    ("\"skipped\": 10201", "\"skipped\": 44987"),
    ("\"file_count\": 444", "\"file_count\": 0"),
  ]
  for replacement in replacements {
    let (old, new) = replacement
    assert_true(manifest_is_rejected(valid_manifest_text().replace(old~, new~)))
  }
}

///|
test "release candidate manifest rejects a Test262 result from another tree" {
  let input = valid_manifest_text().replace(
    old="\"source_tree\": \"0123456789abcdef\"",
    new="\"source_tree\": \"fedcba9876543210\"",
  )
  assert_true(manifest_is_rejected(input))
}

///|
test "release candidate manifest rejects malformed content digests" {
  let replacements = [
    (
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      "sha256:summary",
    ),
    (
      "sha256:3333333333333333333333333333333333333333333333333333333333333333",
      "sha256:ABCDEF3333333333333333333333333333333333333333333333333333333333",
    ),
  ]
  for replacement in replacements {
    let (old, new) = replacement
    assert_true(manifest_is_rejected(valid_manifest_text().replace(old~, new~)))
  }
}

///|
test "release candidate manifest rejects unsupported schema versions" {
  let input = valid_manifest_text().replace(
    old="\"schema_version\": 1",
    new="\"schema_version\": 2",
  )
  let result : Result[ReleaseCandidateManifest, ReleaseContractError] = Ok(
    parse_manifest(input),
  ) catch {
    error => Err(error)
  }
  match result {
    Err(ReleaseContractError::InvalidManifest(_)) => ()
    Ok(_) => fail("expected an unsupported schema version to be rejected")
  }
}

///|
test "release candidate manifest rejects unknown root evidence" {
  let fields : Map[String, Json] = @json.from_json(
    @json.parse(valid_manifest_text()),
  )
  fields["unexpected"] = Json::boolean(true)
  let result : Result[ReleaseCandidateManifest, ReleaseContractError] = Ok(
    parse_manifest(Json::object(fields).stringify()),
  ) catch {
    error => Err(error)
  }
  match result {
    Err(ReleaseContractError::InvalidManifest(_)) => ()
    Ok(_) => fail("expected unknown root evidence to be rejected")
  }
}

///|
test "release candidate manifest rejects unknown nested evidence" {
  let input = valid_manifest_text().replace(
    old="\"skipped\": 10201",
    new="\"skipped\": 10201, \"unexpected\": 1",
  )
  let result : Result[ReleaseCandidateManifest, ReleaseContractError] = Ok(
    parse_manifest(input),
  ) catch {
    error => Err(error)
  }
  match result {
    Err(ReleaseContractError::InvalidManifest(_)) => ()
    Ok(_) => fail("expected unknown nested evidence to be rejected")
  }
}

///|
test "release validation reports every observed mismatch" {
  let expected = parse_manifest(valid_manifest_text())
  let observed = parse_manifest(
    valid_manifest_text()
    .replace(old="\"version\": \"0.8.0\"", new="\"version\": \"0.8.1\"")
    .replace(
      old="\"content_sha256\": \"sha256:3333333333333333333333333333333333333333333333333333333333333333\"",
      new="\"content_sha256\": \"sha256:4444444444444444444444444444444444444444444444444444444444444444\"",
    ),
  )
  let validation = validate_candidate(expected, observed)
  assert_false(validation.allowed())
  let diagnostics = validation.diagnostics()
  json_inspect(diagnostics.map(diagnostic => diagnostic.code()), content=[
    "version_mismatch", "package_content_mismatch",
  ])
  diagnostics.clear()
  assert_eq(validation.diagnostics().length(), 2)
}

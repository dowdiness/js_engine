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
    #|    "summary_sha256": "sha256:summary",
    #|    "skip_metadata_sha256": "sha256:skip",
    #|    "edition_report_sha256": "sha256:editions",
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
    #|    "content_sha256": "sha256:package",
    #|    "file_count": 444
    #|  }
    #|}
  text
}

///|
test "release candidate manifest round trips without losing evidence" {
  let manifest = parse_manifest(valid_manifest_text())
  let actual = @json.parse(render_manifest(manifest))
  assert_eq(actual, @json.parse(valid_manifest_text()))
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
      old="\"content_sha256\": \"sha256:package\"",
      new="\"content_sha256\": \"sha256:other\"",
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

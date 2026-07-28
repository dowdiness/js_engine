///|
const RELEASE_CANDIDATE_SCHEMA_VERSION = 1

///|
pub suberror ReleaseContractError {
  InvalidManifest(String)
}

///|
pub struct UnitTestCounts {
  passed : Int
  executed : Int
} derive(Debug, Eq)

///|
fn UnitTestCounts::UnitTestCounts(
  passed : Int,
  executed : Int,
) -> UnitTestCounts {
  { passed, executed }
}

///|
pub struct ConformanceCounts {
  passed : Int
  executed : Int
  discovered : Int
  skipped : Int
} derive(Debug, Eq)

///|
fn ConformanceCounts::ConformanceCounts(
  passed : Int,
  executed : Int,
  discovered : Int,
  skipped : Int,
) -> ConformanceCounts {
  { passed, executed, discovered, skipped }
}

///|
pub struct Test262Evidence {
  run_id : String
  source_commit : String
  source_tree : String
  corpus_commit : String
  result_schema_version : Int
  summary_sha256 : String
  skip_metadata_sha256 : String
  edition_report_sha256 : String
  strict : ConformanceCounts
  non_strict : ConformanceCounts
} derive(Debug, Eq)

///|
fn Test262Evidence::Test262Evidence(
  run_id : String,
  source_commit : String,
  source_tree : String,
  corpus_commit : String,
  result_schema_version : Int,
  summary_sha256 : String,
  skip_metadata_sha256 : String,
  edition_report_sha256 : String,
  strict : ConformanceCounts,
  non_strict : ConformanceCounts,
) -> Test262Evidence {
  {
    run_id,
    source_commit,
    source_tree,
    corpus_commit,
    result_schema_version,
    summary_sha256,
    skip_metadata_sha256,
    edition_report_sha256,
    strict,
    non_strict,
  }
}

///|
pub struct PackageEvidence {
  content_sha256 : String
  file_count : Int
} derive(Debug, Eq)

///|
fn PackageEvidence::PackageEvidence(
  content_sha256 : String,
  file_count : Int,
) -> PackageEvidence {
  { content_sha256, file_count }
}

///|
pub struct ReleaseCandidateManifest {
  schema_version : Int
  version : String
  candidate_tree : String
  unit_tests : UnitTestCounts
  test262 : Test262Evidence
  package_evidence : PackageEvidence
} derive(Debug, Eq)

///|
fn ReleaseCandidateManifest::ReleaseCandidateManifest(
  schema_version : Int,
  version : String,
  candidate_tree : String,
  unit_tests : UnitTestCounts,
  test262 : Test262Evidence,
  package_evidence : PackageEvidence,
) -> ReleaseCandidateManifest {
  {
    schema_version,
    version,
    candidate_tree,
    unit_tests,
    test262,
    package_evidence,
  }
}

///|
fn[T] manifest_error(message : String) -> T raise ReleaseContractError {
  raise ReleaseContractError::InvalidManifest(message)
}

///|
fn decode_object(
  value : Json,
  path : String,
) -> Map[String, Json] raise ReleaseContractError {
  @json.from_json(value) catch {
    _ => manifest_error(path + " must be an object")
  }
}

///|
fn validate_exact_fields(
  fields : Map[String, Json],
  expected : Array[String],
  path : String,
) -> Unit raise ReleaseContractError {
  guard fields.length() == expected.length() &&
    expected.all(key => fields.contains(key)) else {
    manifest_error(path + " must contain exactly: " + expected.join(", "))
  }
}

///|
fn require_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise ReleaseContractError {
  match fields.get(key) {
    Some(value) => value
    None => manifest_error(path + " is missing " + key)
  }
}

///|
fn decode_string_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ReleaseContractError {
  @json.from_json(require_field(fields, key, path)) catch {
    _ => manifest_error(path + "." + key + " must be a string")
  }
}

///|
fn decode_non_empty_string_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ReleaseContractError {
  let value = decode_string_field(fields, key, path)
  guard !value.is_empty() else {
    manifest_error(path + "." + key + " must not be empty")
  }
  value
}

///|
fn decode_sha256_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ReleaseContractError {
  let value = decode_non_empty_string_field(fields, key, path)
  guard value.length() == 71 && value.has_prefix("sha256:") else {
    manifest_error(path + "." + key + " must be sha256:<64 lowercase hex>")
  }
  let hex = value[7:].to_owned()
  guard hex.all(char => char.is_ascii_digit() || (char >= 'a' && char <= 'f')) else {
    manifest_error(path + "." + key + " must be sha256:<64 lowercase hex>")
  }
  value
}

///|
fn decode_int_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise ReleaseContractError {
  @json.from_json(require_field(fields, key, path)) catch {
    _ => manifest_error(path + "." + key + " must be an integer")
  }
}

///|
fn decode_object_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Map[String, Json] raise ReleaseContractError {
  decode_object(require_field(fields, key, path), path + "." + key)
}

///|
fn decode_unit_test_counts(
  fields : Map[String, Json],
  path : String,
) -> UnitTestCounts raise ReleaseContractError {
  validate_exact_fields(fields, ["passed", "executed"], path)
  let passed = decode_int_field(fields, "passed", path)
  let executed = decode_int_field(fields, "executed", path)
  guard passed >= 0 && passed <= executed else {
    manifest_error(path + " must satisfy 0 <= passed <= executed")
  }
  UnitTestCounts(passed, executed)
}

///|
fn decode_conformance_counts(
  fields : Map[String, Json],
  path : String,
) -> ConformanceCounts raise ReleaseContractError {
  validate_exact_fields(
    fields,
    ["passed", "executed", "discovered", "skipped"],
    path,
  )
  let passed = decode_int_field(fields, "passed", path)
  let executed = decode_int_field(fields, "executed", path)
  let discovered = decode_int_field(fields, "discovered", path)
  let skipped = decode_int_field(fields, "skipped", path)
  guard passed >= 0 && passed <= executed && executed <= discovered else {
    manifest_error(path + " must satisfy 0 <= passed <= executed <= discovered")
  }
  guard skipped >= 0 && skipped <= discovered else {
    manifest_error(path + ".skipped must be between 0 and discovered")
  }
  ConformanceCounts(passed, executed, discovered, skipped)
}

///|
fn decode_test262_evidence(
  fields : Map[String, Json],
  path : String,
) -> Test262Evidence raise ReleaseContractError {
  validate_exact_fields(
    fields,
    [
      "run_id", "source_commit", "source_tree", "corpus_commit", "result_schema_version",
      "summary_sha256", "skip_metadata_sha256", "edition_report_sha256", "strict",
      "non_strict",
    ],
    path,
  )
  let result_schema_version = decode_int_field(
    fields, "result_schema_version", path,
  )
  guard result_schema_version > 0 else {
    manifest_error(path + ".result_schema_version must be positive")
  }
  Test262Evidence(
    decode_non_empty_string_field(fields, "run_id", path),
    decode_non_empty_string_field(fields, "source_commit", path),
    decode_non_empty_string_field(fields, "source_tree", path),
    decode_non_empty_string_field(fields, "corpus_commit", path),
    result_schema_version,
    decode_sha256_field(fields, "summary_sha256", path),
    decode_sha256_field(fields, "skip_metadata_sha256", path),
    decode_sha256_field(fields, "edition_report_sha256", path),
    decode_conformance_counts(
      decode_object_field(fields, "strict", path),
      path + ".strict",
    ),
    decode_conformance_counts(
      decode_object_field(fields, "non_strict", path),
      path + ".non_strict",
    ),
  )
}

///|
fn decode_package_evidence(
  fields : Map[String, Json],
  path : String,
) -> PackageEvidence raise ReleaseContractError {
  validate_exact_fields(fields, ["content_sha256", "file_count"], path)
  let file_count = decode_int_field(fields, "file_count", path)
  guard file_count > 0 else {
    manifest_error(path + ".file_count must be positive")
  }
  PackageEvidence(
    decode_sha256_field(fields, "content_sha256", path),
    file_count,
  )
}

///|
pub fn parse_manifest(
  text : String,
) -> ReleaseCandidateManifest raise ReleaseContractError {
  let value = @json.parse(text) catch {
    _ => manifest_error("release candidate manifest must be valid JSON")
  }
  let root = decode_object(value, "manifest")
  validate_exact_fields(
    root,
    [
      "schema_version", "version", "candidate_tree", "unit_tests", "test262", "package",
    ],
    "manifest",
  )
  let schema_version = decode_int_field(root, "schema_version", "manifest")
  guard schema_version == RELEASE_CANDIDATE_SCHEMA_VERSION else {
    manifest_error(
      "manifest.schema_version must be " +
      RELEASE_CANDIDATE_SCHEMA_VERSION.to_string(),
    )
  }
  let version = decode_non_empty_string_field(root, "version", "manifest")
  let candidate_tree = decode_non_empty_string_field(
    root, "candidate_tree", "manifest",
  )
  let unit_tests = decode_unit_test_counts(
    decode_object_field(root, "unit_tests", "manifest"),
    "manifest.unit_tests",
  )
  let test262 = decode_test262_evidence(
    decode_object_field(root, "test262", "manifest"),
    "manifest.test262",
  )
  guard test262.source_tree == candidate_tree else {
    manifest_error("manifest.test262.source_tree must match candidate_tree")
  }
  let package_evidence = decode_package_evidence(
    decode_object_field(root, "package", "manifest"),
    "manifest.package",
  )
  ReleaseCandidateManifest(
    schema_version, version, candidate_tree, unit_tests, test262, package_evidence,
  )
}

///|
fn json_int(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn UnitTestCounts::to_json(self : UnitTestCounts) -> Json {
  Json::object({
    "passed": json_int(self.passed),
    "executed": json_int(self.executed),
  })
}

///|
fn ConformanceCounts::to_json(self : ConformanceCounts) -> Json {
  Json::object({
    "passed": json_int(self.passed),
    "executed": json_int(self.executed),
    "discovered": json_int(self.discovered),
    "skipped": json_int(self.skipped),
  })
}

///|
fn Test262Evidence::to_json(self : Test262Evidence) -> Json {
  Json::object({
    "run_id": Json::string(self.run_id),
    "source_commit": Json::string(self.source_commit),
    "source_tree": Json::string(self.source_tree),
    "corpus_commit": Json::string(self.corpus_commit),
    "result_schema_version": json_int(self.result_schema_version),
    "summary_sha256": Json::string(self.summary_sha256),
    "skip_metadata_sha256": Json::string(self.skip_metadata_sha256),
    "edition_report_sha256": Json::string(self.edition_report_sha256),
    "strict": self.strict.to_json(),
    "non_strict": self.non_strict.to_json(),
  })
}

///|
fn PackageEvidence::to_json(self : PackageEvidence) -> Json {
  Json::object({
    "content_sha256": Json::string(self.content_sha256),
    "file_count": json_int(self.file_count),
  })
}

///|
fn ReleaseCandidateManifest::to_json(self : ReleaseCandidateManifest) -> Json {
  Json::object({
    "schema_version": json_int(self.schema_version),
    "version": Json::string(self.version),
    "candidate_tree": Json::string(self.candidate_tree),
    "unit_tests": self.unit_tests.to_json(),
    "test262": self.test262.to_json(),
    "package": self.package_evidence.to_json(),
  })
}

///|
pub fn render_manifest(manifest : ReleaseCandidateManifest) -> String {
  manifest.to_json().stringify(indent=2) + "\n"
}

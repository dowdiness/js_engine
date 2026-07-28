///|
pub struct ReleaseDiagnostic {
  code : String
  expected : String
  actual : String
} derive(Debug, Eq)

///|
fn ReleaseDiagnostic::ReleaseDiagnostic(
  code : String,
  expected : String,
  actual : String,
) -> ReleaseDiagnostic {
  { code, expected, actual }
}

///|
pub fn ReleaseDiagnostic::code(self : ReleaseDiagnostic) -> String {
  self.code
}

///|
pub fn ReleaseDiagnostic::expected(self : ReleaseDiagnostic) -> String {
  self.expected
}

///|
pub fn ReleaseDiagnostic::actual(self : ReleaseDiagnostic) -> String {
  self.actual
}

///|
pub struct ReleaseValidation {
  allowed : Bool
  priv diagnostics : Array[ReleaseDiagnostic]
}

///|
fn ReleaseValidation::ReleaseValidation(
  diagnostics : Array[ReleaseDiagnostic],
) -> ReleaseValidation {
  { allowed: diagnostics.is_empty(), diagnostics: diagnostics.copy() }
}

///|
pub fn ReleaseValidation::allowed(self : ReleaseValidation) -> Bool {
  self.allowed
}

///|
pub fn ReleaseValidation::diagnostics(
  self : ReleaseValidation,
) -> Array[ReleaseDiagnostic] {
  self.diagnostics.copy()
}

///|
fn append_string_mismatch(
  diagnostics : Array[ReleaseDiagnostic],
  code : String,
  expected : String,
  actual : String,
) -> Unit {
  if expected != actual {
    diagnostics.push(ReleaseDiagnostic(code, expected, actual))
  }
}

///|
fn append_int_mismatch(
  diagnostics : Array[ReleaseDiagnostic],
  code : String,
  expected : Int,
  actual : Int,
) -> Unit {
  append_string_mismatch(
    diagnostics,
    code,
    expected.to_string(),
    actual.to_string(),
  )
}

///|
fn append_conformance_mismatches(
  diagnostics : Array[ReleaseDiagnostic],
  prefix : String,
  expected : ConformanceCounts,
  actual : ConformanceCounts,
) -> Unit {
  append_int_mismatch(
    diagnostics,
    prefix + "_passed_mismatch",
    expected.passed,
    actual.passed,
  )
  append_int_mismatch(
    diagnostics,
    prefix + "_executed_mismatch",
    expected.executed,
    actual.executed,
  )
  append_int_mismatch(
    diagnostics,
    prefix + "_discovered_mismatch",
    expected.discovered,
    actual.discovered,
  )
  append_int_mismatch(
    diagnostics,
    prefix + "_skipped_mismatch",
    expected.skipped,
    actual.skipped,
  )
}

///|
pub fn validate_candidate(
  expected : ReleaseCandidateManifest,
  observed : ReleaseCandidateManifest,
) -> ReleaseValidation {
  let diagnostics : Array[ReleaseDiagnostic] = []
  append_int_mismatch(
    diagnostics,
    "schema_version_mismatch",
    expected.schema_version,
    observed.schema_version,
  )
  append_string_mismatch(
    diagnostics,
    "version_mismatch",
    expected.version,
    observed.version,
  )
  append_string_mismatch(
    diagnostics,
    "candidate_tree_mismatch",
    expected.candidate_tree,
    observed.candidate_tree,
  )
  append_int_mismatch(
    diagnostics,
    "unit_tests_passed_mismatch",
    expected.unit_tests.passed,
    observed.unit_tests.passed,
  )
  append_int_mismatch(
    diagnostics,
    "unit_tests_executed_mismatch",
    expected.unit_tests.executed,
    observed.unit_tests.executed,
  )
  append_string_mismatch(
    diagnostics,
    "test262_run_id_mismatch",
    expected.test262.run_id,
    observed.test262.run_id,
  )
  append_string_mismatch(
    diagnostics,
    "test262_source_commit_mismatch",
    expected.test262.source_commit,
    observed.test262.source_commit,
  )
  append_string_mismatch(
    diagnostics,
    "test262_source_tree_mismatch",
    expected.test262.source_tree,
    observed.test262.source_tree,
  )
  append_string_mismatch(
    diagnostics,
    "test262_corpus_commit_mismatch",
    expected.test262.corpus_commit,
    observed.test262.corpus_commit,
  )
  append_int_mismatch(
    diagnostics,
    "test262_result_schema_version_mismatch",
    expected.test262.result_schema_version,
    observed.test262.result_schema_version,
  )
  append_string_mismatch(
    diagnostics,
    "test262_summary_digest_mismatch",
    expected.test262.summary_sha256,
    observed.test262.summary_sha256,
  )
  append_string_mismatch(
    diagnostics,
    "test262_skip_metadata_digest_mismatch",
    expected.test262.skip_metadata_sha256,
    observed.test262.skip_metadata_sha256,
  )
  append_string_mismatch(
    diagnostics,
    "test262_edition_report_digest_mismatch",
    expected.test262.edition_report_sha256,
    observed.test262.edition_report_sha256,
  )
  append_conformance_mismatches(
    diagnostics,
    "test262_strict",
    expected.test262.strict,
    observed.test262.strict,
  )
  append_conformance_mismatches(
    diagnostics,
    "test262_non_strict",
    expected.test262.non_strict,
    observed.test262.non_strict,
  )
  append_string_mismatch(
    diagnostics,
    "package_content_mismatch",
    expected.package_evidence.content_sha256,
    observed.package_evidence.content_sha256,
  )
  append_int_mismatch(
    diagnostics,
    "package_file_count_mismatch",
    expected.package_evidence.file_count,
    observed.package_evidence.file_count,
  )
  ReleaseValidation(diagnostics)
}

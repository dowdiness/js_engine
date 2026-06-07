///|
test "extract_features matches classifier inline and block forms" {
  let inline = extract_features(
    "/*---\nfeatures: [BigInt, class-fields-private]\n---*/\n",
  )
  assert_eq(inline.length(), 2)
  assert_eq(inline[0], "BigInt")
  assert_eq(inline[1], "class-fields-private")

  let block = extract_features(
    "/*---\nfeatures:\n  - Promise\n  - Array.prototype.includes\nflags: []\n---*/\n",
  )
  assert_eq(block.length(), 2)
  assert_eq(block[0], "Promise")
  assert_eq(block[1], "Array.prototype.includes")

  let last_field_block = extract_features(
    "/*---\nfeatures:\n  - Promise\n  - BigInt\n---*/\n",
  )
  assert_eq(last_field_block.length(), 2)
  assert_eq(last_field_block[0], "Promise")
  assert_eq(last_field_block[1], "BigInt")
}

///|
test "classify_path_by_edition uses path overrides and newest mapped feature" {
  let annex = classify_path_by_edition("test262/test/annexB/built-ins/foo.js", [])
  assert_eq(annex.0, "Annex B")

  let fallback = classify_path_by_edition(
    "test262/test/built-ins/BigInt/as-int-n.js",
    [],
  )
  assert_eq(fallback.0, "ES2020")

  let mixed = classify_path_by_edition("test262/test/language/example.js", [
    "Promise", "String.prototype.replaceAll",
  ])
  assert_eq(mixed.0, "ES2021")
  assert_eq(mixed.1.length(), 0)

  let unmapped = classify_path_by_edition("test262/test/language/example.js", [
    "not-yet-mapped",
  ])
  assert_eq(unmapped.0, "Unmapped")
  assert_eq(unmapped.1[0], "not-yet-mapped")
}

///|
test "validate_skip_metadata accepts live shared metadata entries" {
  let metadata = @metadata.load_skip_metadata(root=".")
  let features : Map[String, Bool] = {}
  let flags : Map[String, Bool] = {}
  for feature in metadata.skip_feature_names() {
    features[feature] = true
  }
  for flag in metadata.skip_flag_names() {
    flags[flag] = true
  }
  let suite = { files_scanned: 1, features, flags, paths: [] }
  assert_eq(validate_skip_metadata(suite, metadata).length(), 0)
}

///|
test "render_classify_table keeps skipped-only buckets in totals" {
  let buckets : Map[String, EditionBucket] = {}
  buckets["ES2015"] = bucket_record(
    bucket_record(empty_bucket(), "pass", path="p.js", reason=""),
    "fail",
    path="f.js",
    reason="TypeError: bad",
  )
  buckets["Stage 3"] = bucket_record(
    empty_bucket(),
    "skip",
    path="s.js",
    reason="unsupported feature: Temporal",
  )
  let lines = render_classify_table("strict", buckets)
  assert_true(
    lines.any(line => {
      line.contains("| ES2015 | 2 | 0 | 2 | 1 | 1 | 0 | 50.0% | 50.0% |")
    }),
  )
  assert_true(lines.any(line => line.contains("**3**")))
  assert_true(
    lines.any(line => {
      line.contains("Fully-skipped buckets") && line.contains("Stage 3 (1)")
    }),
  )
}

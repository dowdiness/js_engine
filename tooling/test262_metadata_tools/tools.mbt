///|
pub struct ToolRun {
  stdout_lines : Array[String]
  stderr_lines : Array[String]
  code : Int
} derive(Debug)

///|
struct TestFile {
  full_path : String
  rel_path : String
} derive(Debug)

///|
struct SuiteMetadata {
  files_scanned : Int
  features : @set.Set[String]
  flags : @set.Set[String]
  paths : Array[String]
} derive(Debug)

///|
struct ValidationIssue {
  kind : String
  entry : String
  detail : String
} derive(Debug)

///|
fn join_path(left : String, right : String) -> String {
  if left == "" || left == "." {
    right
  } else if left.has_suffix("/") {
    left + right
  } else {
    left + "/" + right
  }
}

///|
fn display_path(path : String) -> String {
  if path.has_prefix("./") {
    path[2:].to_owned()
  } else {
    path
  }
}

///|
fn normalize_path(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn absolute_path(path : String) -> String {
  if path.has_prefix("/") {
    path
  } else {
    match @env.current_dir() {
      Some(cwd) => join_path(cwd, path)
      None => path
    }
  }
}

///|
fn json_python_str(value : Json) -> String {
  match value {
    String(s) => s
    True => "True"
    False => "False"
    Null => "None"
    Number(_, repr=Some(repr)) => repr
    Number(n, repr=None) => n.to_string()
    Array(_) | Object(_) => value.stringify()
  }
}

///|
fn python_text_newlines(source : String) -> String {
  source.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
fn metadata_list_strings(
  data : Map[String, Json]?,
  key : String,
) -> Array[String] {
  match data {
    Some(fields) => @utils.as_list(fields.get(key)).map(json_python_str)
    None => []
  }
}

///|
fn collect_js_files_in_dir(
  dir : String,
  rel_prefix : String,
  files : Array[TestFile],
) -> Unit raise {
  let entries = @fs.read_dir(dir)
  entries.sort()
  for entry in entries {
    let full_path = join_path(dir, entry)
    let rel_path = if rel_prefix == "" {
      entry
    } else {
      join_path(rel_prefix, entry)
    }
    if @fs.is_dir(full_path) {
      collect_js_files_in_dir(full_path, rel_path, files)
    } else if @fs.is_file(full_path) && entry.has_suffix(".js") {
      files.push({ full_path, rel_path })
    }
  }
}

///|
fn collect_js_files(test_dir : String) -> Array[TestFile] raise {
  let files : Array[TestFile] = []
  collect_js_files_in_dir(test_dir, "", files)
  files.sort_by(fn(a, b) { a.rel_path.compare(b.rel_path) })
  files
}

///|
fn missing_suite_message(test262_root : String) -> String {
  display_path(join_path(test262_root, "test")) +
  " does not exist; run `make test262-download` first"
}

///|
fn collect_suite_metadata(test262_root : String) -> SuiteMetadata raise {
  let test_root = join_path(test262_root, "test")
  guard @fs.path_exists(test_root) && @fs.is_dir(test_root) else {
    fail(missing_suite_message(test262_root))
  }

  let features = @set.Set::default()
  let flags = @set.Set::default()
  let paths : Array[String] = []
  let mut files_scanned = 0

  for file in collect_js_files(test_root) {
    files_scanned += 1
    paths.push(normalize_path(file.full_path))
    paths.push(join_path("test", normalize_path(file.rel_path)))

    let source = python_text_newlines(@fs.read_file_to_string(file.full_path))
    let data = @utils.parse_yaml_frontmatter(source)
    for feature in metadata_list_strings(data, "features") {
      features.add(feature)
    }
    for flag in metadata_list_strings(data, "flags") {
      flags.add(flag)
    }
  }

  { files_scanned, features, flags, paths }
}

///|
fn path_suffix_is_live(paths : Array[String], suffix : String) -> Bool {
  let normalized_suffix = normalize_path(suffix)
  paths.any(path => path.has_suffix(normalized_suffix))
}

///|
fn validate_skip_metadata(
  suite : SuiteMetadata,
  metadata : @metadata.SkipMetadata,
) -> Array[ValidationIssue] {
  let issues : Array[ValidationIssue] = []

  for feature in metadata.skip_feature_names() {
    if !suite.features.contains(feature) {
      issues.push({
        kind: "dead feature",
        entry: feature,
        detail: "no Test262 file declares this value in features metadata",
      })
    }
  }

  for flag in metadata.skip_flag_names() {
    if !suite.flags.contains(flag) {
      issues.push({
        kind: "dead flag",
        entry: flag,
        detail: "no Test262 file declares this value in flags metadata",
      })
    }
  }

  for entry in metadata.skip_path_suffix_entries() {
    let suffix = entry.0
    if !path_suffix_is_live(suite.paths, suffix) {
      issues.push({
        kind: "dead path suffix",
        entry: suffix,
        detail: "no Test262 file path matches this suffix",
      })
    }
  }

  issues
}

///|
fn render_validation_result(
  suite : SuiteMetadata,
  issues : Array[ValidationIssue],
) -> ToolRun {
  let stdout_lines : Array[String] = []
  if issues.length() > 0 {
    stdout_lines.push("Test262 skip metadata validation failed:")
    for issue in issues {
      stdout_lines.push(
        "- " + issue.kind + ": " + issue.entry + " (" + issue.detail + ")",
      )
    }
    stdout_lines.push("")
    stdout_lines.push("No conformance numbers were produced.")
    { stdout_lines, stderr_lines: [], code: 1 }
  } else {
    stdout_lines.push(
      "ok: shared Test262 skip metadata matches current Test262 metadata/path usage (" +
      suite.files_scanned.to_string() +
      " files scanned)",
    )
    stdout_lines.push("No conformance numbers were produced.")
    { stdout_lines, stderr_lines: [], code: 0 }
  }
}

///|
/// Shadow implementation of `scripts/validate-test262-skip-metadata.py`.
///
/// This only checks metadata coherence against a checked-out Test262 corpus; it
/// does not run tests or produce conformance numbers.
pub fn run_validate_skips(
  repo_root? : String = ".",
  test262_root? : String = "./test262",
) -> ToolRun raise {
  let metadata = @metadata.load_skip_metadata(root=repo_root)
  let test_root = join_path(test262_root, "test")
  guard @fs.path_exists(test_root) && @fs.is_dir(test_root) else {
    return {
      stdout_lines: [],
      stderr_lines: ["error: " + missing_suite_message(test262_root)],
      code: 2,
    }
  }
  let suite = collect_suite_metadata(test262_root)
  render_validation_result(suite, validate_skip_metadata(suite, metadata))
}

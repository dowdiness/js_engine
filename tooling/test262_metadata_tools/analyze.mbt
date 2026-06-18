///|
struct CategoryInfo {
  relevance : String
  notes : String
} derive(Debug)

///|
struct StaticAnalysis {
  path : String
  classification : String
  reason : String
  category : String
  complexity : String
  features_required : Array[String]
  flags : Array[String]
  uses_eval : Bool
  uses_try_catch : Bool
  uses_new : Bool
  uses_this : Bool
  uses_prototype : Bool
} derive(Debug)

///|
fn category_analysis() -> Map[String, CategoryInfo] {
  {
    "language/literals/null": {
      relevance: "high",
      notes: "Engine supports null literals",
    },
    "language/literals/boolean": {
      relevance: "high",
      notes: "Engine supports boolean literals",
    },
    "language/literals/numeric": {
      relevance: "high",
      notes: "Engine supports numeric literals (IEEE 754 doubles)",
    },
    "language/literals/string": {
      relevance: "medium",
      notes: "Engine supports basic string literals, but may not handle all escape sequences",
    },
    "language/expressions/addition": {
      relevance: "high",
      notes: "Engine supports + operator with type coercion",
    },
    "language/expressions/subtraction": {
      relevance: "high",
      notes: "Engine supports - operator",
    },
    "language/expressions/multiplication": {
      relevance: "high",
      notes: "Engine supports * operator",
    },
    "language/expressions/division": {
      relevance: "high",
      notes: "Engine supports / operator",
    },
    "language/expressions/modulus": {
      relevance: "high",
      notes: "Engine supports % operator",
    },
    "language/expressions/equals": {
      relevance: "high",
      notes: "Engine supports == with type coercion",
    },
    "language/expressions/strict-equals": {
      relevance: "high",
      notes: "Engine supports === strict equality",
    },
    "language/expressions/does-not-equals": {
      relevance: "high",
      notes: "Engine supports != operator",
    },
    "language/expressions/strict-does-not-equals": {
      relevance: "high",
      notes: "Engine supports !== operator",
    },
    "language/expressions/typeof": {
      relevance: "high",
      notes: "Engine supports typeof operator",
    },
    "language/expressions/logical-and": {
      relevance: "high",
      notes: "Engine supports && with short-circuit",
    },
    "language/expressions/logical-or": {
      relevance: "high",
      notes: "Engine supports || with short-circuit",
    },
    "language/expressions/logical-not": {
      relevance: "high",
      notes: "Engine supports ! operator",
    },
    "language/expressions/conditional": {
      relevance: "high",
      notes: "Engine supports ternary ?: operator",
    },
    "language/expressions/assignment": {
      relevance: "high",
      notes: "Engine supports = assignment",
    },
    "language/statements/if": {
      relevance: "high",
      notes: "Engine supports if/else statements",
    },
    "language/statements/while": {
      relevance: "high",
      notes: "Engine supports while loops",
    },
    "language/statements/for": {
      relevance: "high",
      notes: "Engine supports for loops",
    },
    "language/statements/break": {
      relevance: "high",
      notes: "Engine supports break statements",
    },
    "language/statements/continue": {
      relevance: "high",
      notes: "Engine supports continue statements",
    },
    "language/statements/return": {
      relevance: "high",
      notes: "Engine supports return statements",
    },
    "language/statements/variable": {
      relevance: "medium",
      notes: "Engine supports var/let/const but not all edge cases",
    },
    "language/statements/block": {
      relevance: "high",
      notes: "Engine supports block statements with scoping",
    },
    "language/function-code": {
      relevance: "medium",
      notes: "Engine supports functions but not all spec edge cases",
    },
    "language/types/null": {
      relevance: "high",
      notes: "Engine supports null type",
    },
    "language/types/undefined": {
      relevance: "high",
      notes: "Engine supports undefined type",
    },
    "language/types/boolean": {
      relevance: "high",
      notes: "Engine supports boolean type",
    },
    "language/types/number": {
      relevance: "high",
      notes: "Engine supports number type (IEEE 754)",
    },
    "language/types/string": {
      relevance: "high",
      notes: "Engine supports string type",
    },
    "language/comments": {
      relevance: "high",
      notes: "Engine supports single-line and multi-line comments",
    },
    "language/identifiers": {
      relevance: "medium",
      notes: "Engine supports basic identifiers",
    },
    "language/keywords": {
      relevance: "medium",
      notes: "Engine recognizes JS keywords",
    },
    "language/block-scope": {
      relevance: "medium",
      notes: "Engine supports block scoping with let/const",
    },
  }
}

///|
fn map_get_count(map : Map[String, Int], key : String) -> Int {
  match map.get(key) {
    Some(value) => value
    None => 0
  }
}

///|
fn increment_count(map : Map[String, Int], key : String) -> Unit {
  map[key] = map_get_count(map, key) + 1
}

///|
fn sorted_count_keys_desc(map : Map[String, Int]) -> Array[String] {
  let keys : Array[String] = []
  for key, _ in map {
    keys.push(key)
  }
  keys.sort_by(fn(a, b) {
    let by_count = map_get_count(map, b).compare(map_get_count(map, a))
    if by_count != 0 {
      by_count
    } else {
      a.compare(b)
    }
  })
  keys
}

///|
fn pad_left(value : String, width : Int) -> String {
  if value.length() >= width {
    value
  } else {
    " ".repeat(width - value.length()) + value
  }
}

///|
fn pad_left_zero(value : String, width : Int) -> String {
  if value.length() >= width {
    value
  } else {
    "0".repeat(width - value.length()) + value
  }
}

///|
fn pad_right(value : String, width : Int) -> String {
  if value.length() >= width {
    value
  } else {
    value + " ".repeat(width - value.length())
  }
}

///|
fn comma_int(value : Int) -> String {
  let raw = value.to_string()
  let len = raw.length()
  if len <= 3 {
    raw
  } else {
    let out = StringBuilder()
    for i in 0..<len {
      if i > 0 && (len - i) % 3 == 0 {
        out.write_char(',')
      }
      out.write_char(raw[i].unsafe_to_char())
    }
    out.to_string()
  }
}

///|
fn pow10(places : Int) -> Int {
  let mut out = 1
  for _ in 0..<places {
    out *= 10
  }
  out
}

///|
fn pct_string(numerator : Int, denominator : Int, places : Int) -> String {
  guard denominator > 0 else {
    if places == 0 {
      return "0"
    }
    return "0." + "0".repeat(places)
  }
  let scale = pow10(places)
  let scaled = (numerator * 100 * scale + denominator / 2) / denominator
  let whole = scaled / scale
  let frac = scaled % scale
  if places == 0 {
    whole.to_string()
  } else {
    whole.to_string() + "." + pad_left_zero(frac.to_string(), places)
  }
}

///|
fn json_int(value : Int) -> Json {
  Json::number(Double::from_int(value), repr=value.to_string())
}

///|
fn json_percent(numerator : Int, denominator : Int) -> Json {
  let repr = pct_string(numerator, denominator, 2)
  Json::number(0.0, repr~)
}

///|
fn category_from_rel_path(rel_path : String) -> String {
  let parts = @path_utils.path_components(@path_utils.normalize_path(rel_path))
  if parts.length() >= 2 {
    @path_utils.join_path(parts[0], parts[1])
  } else if parts.length() == 1 {
    parts[0]
  } else {
    ""
  }
}

///|
fn classify_static_test(
  filepath : String,
  features : Array[String],
  flags : Array[String],
  metadata : @metadata.SkipMetadata,
) -> (String, String) {
  match metadata.skip_reason(filepath, features, flags, None) {
    Some(reason) if reason == "fixture file" => ("skip_fixture", reason)
    Some(reason) if reason.has_prefix("unsupported flag:") =>
      ("skip_flag", reason)
    Some(reason) if reason.has_prefix("unsupported feature:") =>
      ("skip_feature", reason)
    _ => ("applicable", "")
  }
}

///|
fn contains_object_literal_marker(source : String) -> Bool {
  let len = source.length()
  let mut i = 0
  while i < len {
    if source[i] == '{' {
      let mut j = i + 1
      while j < len && source[j] != '}' {
        if source[j] == ':' {
          return true
        }
        j += 1
      }
      i = j
    }
    i += 1
  }
  false
}

///|
fn contains_regex_literal_marker(source : String) -> Bool {
  let len = source.length()
  let mut i = 0
  while i < len {
    if source[i] == '/' {
      let mut j = i + 1
      if j < len && source[j] != '/' && source[j] != '\n' {
        while j < len && source[j] != '/' && source[j] != '\n' {
          j += 1
        }
        if j < len && source[j] == '/' && j > i + 1 {
          return true
        }
      }
    }
    i += 1
  }
  false
}

///|
fn analysis_complexity(
  classification : String,
  uses_eval : Bool,
  uses_try_catch : Bool,
  uses_new : Bool,
  uses_object_literal : Bool,
  uses_array : Bool,
  uses_regex : Bool,
  uses_this : Bool,
  uses_prototype : Bool,
  uses_throw : Bool,
) -> String {
  if classification != "applicable" {
    return "simple"
  }
  let mut count = 0
  if uses_eval {
    count += 1
  }
  if uses_try_catch {
    count += 1
  }
  if uses_new {
    count += 1
  }
  if uses_object_literal {
    count += 1
  }
  if uses_array {
    count += 1
  }
  if uses_regex {
    count += 1
  }
  if uses_this {
    count += 1
  }
  if uses_prototype {
    count += 1
  }
  if uses_throw {
    count += 1
  }
  if count >= 3 {
    "complex"
  } else if count >= 1 {
    "moderate"
  } else {
    "simple"
  }
}

///|
fn analyze_test_file(
  file : TestFile,
  metadata : @metadata.SkipMetadata,
) -> StaticAnalysis {
  let source = python_text_newlines(@fs.read_file_to_string(file.full_path)) catch {
    err =>
      return {
        path: file.full_path,
        classification: "error",
        reason: "\{to_repr(err)}",
        category: "",
        complexity: "simple",
        features_required: [],
        flags: [],
        uses_eval: false,
        uses_try_catch: false,
        uses_new: false,
        uses_this: false,
        uses_prototype: false,
      }
  }
  let frontmatter = @utils.parse_yaml_frontmatter(source)
  let features = metadata_list_strings(frontmatter, "features")
  let flags = metadata_list_strings(frontmatter, "flags")
  let (classification, reason) = classify_static_test(
    file.full_path,
    features,
    flags,
    metadata,
  )
  let uses_eval = source.contains("eval(")
  let uses_try_catch = source.contains("try {") || source.contains("try{")
  let uses_new = source.contains("new ")
  let uses_object_literal = contains_object_literal_marker(source)
  let uses_array = source.contains("[") && source.contains("]")
  let uses_regex = contains_regex_literal_marker(source)
  let uses_this = source.contains("this")
  let uses_prototype = source.contains(".prototype")
  let uses_throw = source.contains("throw ")
  {
    path: @path_utils.normalize_path(file.rel_path),
    classification,
    reason,
    category: category_from_rel_path(@path_utils.normalize_path(file.rel_path)),
    complexity: analysis_complexity(
      classification, uses_eval, uses_try_catch, uses_new, uses_object_literal, uses_array,
      uses_regex, uses_this, uses_prototype, uses_throw,
    ),
    features_required: features,
    flags,
    uses_eval,
    uses_try_catch,
    uses_new,
    uses_this,
    uses_prototype,
  }
}

///|
fn collect_analyzer_files_in_dir(
  dir : String,
  rel_prefix : String,
  files : Array[TestFile],
) -> Unit raise {
  let entries = @fs.read_dir(dir)
  entries.sort()
  for entry in entries {
    let full_path = @path_utils.join_path(dir, entry)
    let rel_path = if rel_prefix == "" {
      entry
    } else {
      @path_utils.join_path(rel_prefix, entry)
    }
    if rel_path.has_prefix("intl402") {
      continue
    }
    if @fs.is_dir(full_path) {
      collect_analyzer_files_in_dir(full_path, rel_path, files)
    } else if @fs.is_file(full_path) && entry.has_suffix(".js") {
      files.push({ full_path, rel_path })
    }
  }
}

///|
fn discover_analyzer_tests(
  test262_root : String,
) -> (Array[TestFile], String) raise {
  let test_dir = @path_utils.join_path(test262_root, "test")
  let files : Array[TestFile] = []
  if @fs.path_exists(test_dir) && @fs.is_dir(test_dir) {
    collect_analyzer_files_in_dir(test_dir, "", files)
    files.sort_by(fn(a, b) { a.rel_path.compare(b.rel_path) })
  }
  (files, test_dir)
}

///|
fn append_analysis_counts(
  analysis : StaticAnalysis,
  metadata : @metadata.SkipMetadata,
  by_classification : Map[String, Int],
  by_complexity : Map[String, Int],
  applicable_by_category : Map[String, Int],
  total_by_category : Map[String, Int],
  feature_gaps : Map[String, Int],
) -> Unit {
  increment_count(by_classification, analysis.classification)
  increment_count(total_by_category, analysis.category)
  if analysis.classification == "applicable" {
    increment_count(by_complexity, analysis.complexity)
    increment_count(applicable_by_category, analysis.category)
  }
  if analysis.classification == "skip_feature" {
    for feature in analysis.features_required {
      if metadata.is_skip_feature(feature) {
        increment_count(feature_gaps, feature)
      }
    }
  }
}

///|
fn json_int_map(keys : Array[String], values : Map[String, Int]) -> Json {
  let out : Map[String, Json] = {}
  for key in keys {
    out[key] = json_int(map_get_count(values, key))
  }
  Json::object(out)
}

///|
fn analysis_json_report(
  total : Int,
  applicable : Int,
  skipped_feature : Int,
  skipped_flag : Int,
  skipped_fixture : Int,
  by_complexity : Map[String, Int],
  applicable_by_category : Map[String, Int],
  total_by_category : Map[String, Int],
  feature_gaps : Map[String, Int],
) -> Json {
  let summary : Map[String, Json] = {
    "total_tests": json_int(total),
    "applicable": json_int(applicable),
    "skipped_feature": json_int(skipped_feature),
    "skipped_flag": json_int(skipped_flag),
    "skipped_fixture": json_int(skipped_fixture),
    "applicable_pct": json_percent(applicable, total),
  }
  let complexity = json_int_map(
    ["simple", "moderate", "complex"],
    by_complexity,
  )
  let categories : Map[String, Json] = {}
  let cats = sorted_count_keys_desc(total_by_category)
  for cat in cats {
    let total_for_cat = map_get_count(total_by_category, cat)
    if total_for_cat >= 5 {
      let app = map_get_count(applicable_by_category, cat)
      categories[cat] = Json::object({
        "applicable": json_int(app),
        "total": json_int(total_for_cat),
        "applicable_pct": json_percent(app, total_for_cat),
      })
    }
  }
  let gap_keys = sorted_count_keys_desc(feature_gaps)
  let top_gap_keys : Array[String] = []
  for i, key in gap_keys {
    if i < 30 {
      top_gap_keys.push(key)
    }
  }
  Json::object({
    "engine": Json::string("moonbit-js-engine"),
    "analysis_type": Json::string("static"),
    "date": Json::string("moonbit-shadow"),
    "summary": Json::object(summary),
    "complexity": complexity,
    "categories": Json::object(categories),
    "feature_gaps": json_int_map(top_gap_keys, feature_gaps),
  })
}

///|
fn render_analysis_report(
  analyses : Array[StaticAnalysis],
  metadata : @metadata.SkipMetadata,
) -> (Array[String], Json) {
  let total = analyses.length()
  let by_classification : Map[String, Int] = {}
  let by_complexity : Map[String, Int] = {}
  let applicable_by_category : Map[String, Int] = {}
  let total_by_category : Map[String, Int] = {}
  let feature_gaps : Map[String, Int] = {}
  for analysis in analyses {
    append_analysis_counts(
      analysis, metadata, by_classification, by_complexity, applicable_by_category,
      total_by_category, feature_gaps,
    )
  }
  let applicable = map_get_count(by_classification, "applicable")
  let skipped_feature = map_get_count(by_classification, "skip_feature")
  let skipped_flag = map_get_count(by_classification, "skip_flag")
  let skipped_fixture = map_get_count(by_classification, "skip_fixture")
  let total_safe = if total > 0 { total } else { 1 }
  let lines : Array[String] = []
  lines.push("")
  lines.push(
    "============================================================================",
  )
  lines.push("  Test262 Static Metadata Analysis (non-authoritative)")
  lines.push("  Engine: MoonBit JS Engine (tree-walking interpreter)")
  lines.push("  Date: moonbit-shadow")
  lines.push(
    "============================================================================",
  )
  lines.push(
    "  Uses shared skip constants from scripts/test262_skip_metadata.py.",
  )
  lines.push("  Does not run the engine or produce conformance numbers.")
  lines.push("")
  lines.push("  Total test files analyzed:  " + pad_left(total.to_string(), 6))
  lines.push(
    "  Applicable (could run):    " +
    pad_left(applicable.to_string(), 6) +
    " (" +
    pct_string(applicable, total_safe, 1) +
    "%)",
  )
  lines.push(
    "  Skipped (unsupported feat):" +
    pad_left(skipped_feature.to_string(), 6) +
    " (" +
    pct_string(skipped_feature, total_safe, 1) +
    "%)",
  )
  lines.push(
    "  Skipped (unsupported flag):" +
    pad_left(skipped_flag.to_string(), 6) +
    " (" +
    pct_string(skipped_flag, total_safe, 1) +
    "%)",
  )
  lines.push(
    "  Skipped (fixture files):   " + pad_left(skipped_fixture.to_string(), 6),
  )
  lines.push("")
  lines.push("  Applicable test complexity breakdown:")
  for complexity in ["simple", "moderate", "complex"] {
    let count = map_get_count(by_complexity, complexity)
    let pct = if applicable > 0 {
      pct_string(count, applicable, 1)
    } else {
      "0.0"
    }
    lines.push(
      "    " +
      pad_right(complexity, 12) +
      " " +
      pad_left(count.to_string(), 6) +
      " (" +
      pct +
      "%)",
    )
  }
  lines.push("")
  lines.push(
    "────────────────────────────────────────────────────────────────────────────",
  )
  lines.push(
    "  " +
    pad_right("Category", 45) +
    " " +
    pad_left("Applicable", 10) +
    " " +
    pad_left("Total", 8) +
    " " +
    pad_left("%", 7),
  )
  lines.push(
    "────────────────────────────────────────────────────────────────────────────",
  )
  let categories = category_analysis()
  let cats = sorted_count_keys_desc(applicable_by_category)
  for cat in sorted_count_keys_desc(total_by_category) {
    if !applicable_by_category.contains(cat) {
      cats.push(cat)
    }
  }
  for cat in cats {
    let app = map_get_count(applicable_by_category, cat)
    let tot = map_get_count(total_by_category, cat)
    if tot >= 5 {
      let marker = match categories.get(cat) {
        Some(info) if info.relevance == "high" => " *"
        _ => ""
      }
      lines.push(
        "  " +
        pad_right(cat, 45) +
        " " +
        pad_left(app.to_string(), 10) +
        " " +
        pad_left(tot.to_string(), 8) +
        " " +
        pad_left(pct_string(app, tot, 1), 6) +
        "%" +
        marker,
      )
    }
  }
  lines.push(
    "────────────────────────────────────────────────────────────────────────────",
  )
  lines.push("  * = category note from static heuristics, not support status")
  lines.push("")
  lines.push("  Top 15 unsupported features (by test count):")
  lines.push(
    "────────────────────────────────────────────────────────────────────────────",
  )
  let gap_keys = sorted_count_keys_desc(feature_gaps)
  for i, feature in gap_keys {
    if i < 15 {
      lines.push(
        "    " +
        pad_right(feature, 40) +
        " " +
        pad_left(map_get_count(feature_gaps, feature).to_string(), 6) +
        " tests",
      )
    }
  }
  lines.push("")
  lines.push("  Static category notes:")
  lines.push(
    "────────────────────────────────────────────────────────────────────────────",
  )
  let category_keys : Array[String] = []
  for cat, _ in categories {
    category_keys.push(cat)
  }
  category_keys.sort()
  for cat in category_keys {
    let app = map_get_count(applicable_by_category, cat)
    let tot = map_get_count(total_by_category, cat)
    if tot > 0 {
      let info = categories[cat]
      lines.push(
        "  [" +
        pad_left(info.relevance, 6) +
        "] " +
        pad_right(cat, 36) +
        " " +
        pad_left(app.to_string(), 4) +
        "/" +
        pad_right(tot.to_string(), 4) +
        " applicable",
      )
      lines.push("           " + info.notes)
    }
  }
  lines.push("")
  lines.push(
    "============================================================================",
  )
  lines.push("  SUMMARY")
  lines.push(
    "============================================================================",
  )
  lines.push(
    "  Static metadata marked " +
    applicable.to_string() +
    " out of " +
    total.to_string() +
    " Test262 files",
  )
  lines.push(
    "  applicable (" +
    pct_string(applicable, total_safe, 1) +
    "% of the suite).",
  )
  lines.push("")
  lines.push("  Of the applicable tests:")
  lines.push(
    "    - " +
    map_get_count(by_complexity, "simple").to_string() +
    " are simple (basic language features only)",
  )
  lines.push(
    "    - " +
    map_get_count(by_complexity, "moderate").to_string() +
    " use moderate features (try/catch, objects, etc.)",
  )
  lines.push(
    "    - " +
    map_get_count(by_complexity, "complex").to_string() +
    " use complex features (eval, prototypes, etc.)",
  )
  lines.push("")
  lines.push(
    "  Note: 'Applicable' means the metadata did not match the runner's",
  )
  lines.push(
    "  skip constants. Actual pass/fail/timeout status is only known by",
  )
  lines.push("  running scripts/test262-runner.py or reading CI artifacts.")
  lines.push("")
  lines.push("  To run actual conformance tests:")
  lines.push("    make test262          # Full suite")
  lines.push("    make test262-quick    # Quick subset (language/literals)")
  lines.push(
    "============================================================================",
  )
  lines.push("")
  (
    lines,
    analysis_json_report(
      total, applicable, skipped_feature, skipped_flag, skipped_fixture, by_complexity,
      applicable_by_category, total_by_category, feature_gaps,
    ),
  )
}

///|
/// Shadow implementation of `scripts/test262-analyze.py`.
///
/// This scans Test262 metadata only. It does not run the engine and does not
/// produce authoritative conformance numbers.
pub fn run_analyze(
  repo_root? : String = ".",
  test262_root? : String = "./test262",
  output? : String = "test262-analysis.moonbit-shadow.json",
) -> ToolRun raise {
  let test262_dir = @path_utils.absolute_path(test262_root)
  guard @fs.path_exists(test262_root) && @fs.is_dir(test262_root) else {
    return {
      stdout_lines: [],
      stderr_lines: ["Error: test262 directory not found: " + test262_dir],
      code: 1,
    }
  }
  let metadata = @metadata.load_skip_metadata(root=repo_root)
  let (test_files, _test_dir) = discover_analyzer_tests(test262_root)
  let stdout_lines : Array[String] = []
  stdout_lines.push("Discovering tests in " + test262_dir + "...")
  stdout_lines.push("Found " + test_files.length().to_string() + " test files")
  stdout_lines.push("Analyzing tests...")
  let analyses : Array[StaticAnalysis] = []
  for i, file in test_files {
    analyses.push(analyze_test_file(file, metadata))
    let done = i + 1
    if done % 5000 == 0 {
      stdout_lines.push(
        "  Analyzed " +
        done.to_string() +
        "/" +
        test_files.length().to_string() +
        "...",
      )
    }
  }
  let (report_lines, report_json) = render_analysis_report(analyses, metadata)
  for line in report_lines {
    stdout_lines.push(line)
  }
  @fs.write_string_to_file(output, report_json.stringify(indent=2) + "\n")
  stdout_lines.push("  Results saved to: " + output)
  { stdout_lines, stderr_lines: [], code: 0 }
}

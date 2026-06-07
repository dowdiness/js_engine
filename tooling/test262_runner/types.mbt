///|
const ENGINE_NAME = "moonbit-js-engine"

///|
const DEFAULT_TEST262_DIR = "./test262"

///|
const DEFAULT_TIMEOUT_SECONDS = 5

///|
const DEFAULT_THREAD_COUNT = 4

///|
const HELPER_CODE_POINT_RANGE = "codePointRange"

///|
const PRINT_PREAMBLE = "function print() { var s = \"\"; for (var i = 0; i < arguments.length; i++) { if (i > 0) s += \" \"; s += String(arguments[i]); } console.log(s); }\n"

///|
const DONE_FALLBACK = "\nif (typeof $DONE === \"undefined\") {\n  var $DONE = function(error) {\n    if (error) {\n      if (typeof error === \"object\" && error !== null && \"stack\" in error) {\n        print(\"Test262:AsyncTestFailure:\" + error.stack);\n      } else {\n        print(\"Test262:AsyncTestFailure:\" + String(error));\n      }\n    } else {\n      print(\"Test262:AsyncTestComplete\");\n    }\n  };\n}\n"

///|
const CODE_POINT_RANGE_PREAMBLE = "\n// Opt-in Test262 host helper for RegExp-heavy harness utilities. If the\n// engine provides a native $262.codePointRange, keep it; otherwise install a\n// spec-equivalent JavaScript fallback so helper-enabled runs remain portable.\nif (typeof $262 !== \"undefined\" && typeof $262.codePointRange !== \"function\") {\n  $262.codePointRange = function(start, end) {\n    var CHUNK_SIZE = 10000;\n    var result = \"\";\n    var codePoints = [];\n    for (var length = 0, codePoint = start; codePoint <= end; codePoint++) {\n      codePoints[length++] = codePoint;\n      if (length === CHUNK_SIZE) {\n        result += String.fromCodePoint.apply(null, codePoints);\n        codePoints.length = length = 0;\n      }\n    }\n    return result + String.fromCodePoint.apply(null, codePoints);\n  };\n}\n"

///|
const REGEXP_UTILS_BUILD_STRING = "function buildString(args) {\n  // Use member expressions rather than destructuring `args` for improved\n  // compatibility with engines that only implement assignment patterns\n  // partially or not at all.\n  const loneCodePoints = args.loneCodePoints;\n  const ranges = args.ranges;\n  const CHUNK_SIZE = 10000;\n  let result = String.fromCodePoint.apply(null, loneCodePoints);\n  for (let i = 0; i < ranges.length; i++) {\n    let range = ranges[i];\n    let start = range[0];\n    let end = range[1];\n    let codePoints = [];\n    for (let length = 0, codePoint = start; codePoint <= end; codePoint++) {\n      codePoints[length++] = codePoint;\n      if (length === CHUNK_SIZE) {\n        result += String.fromCodePoint.apply(null, codePoints);\n        codePoints.length = length = 0;\n      }\n    }\n    result += String.fromCodePoint.apply(null, codePoints);\n  }\n  return result;\n}\n"

///|
const REGEXP_UTILS_BUILD_STRING_WITH_HELPER = "function buildString(args) {\n  // Use member expressions rather than destructuring `args` for improved\n  // compatibility with engines that only implement assignment patterns\n  // partially or not at all.\n  const loneCodePoints = args.loneCodePoints;\n  const ranges = args.ranges;\n  const CHUNK_SIZE = 10000;\n  let result = String.fromCodePoint.apply(null, loneCodePoints);\n  for (let i = 0; i < ranges.length; i++) {\n    let range = ranges[i];\n    let start = range[0];\n    let end = range[1];\n    if (typeof $262 !== \"undefined\" && typeof $262.codePointRange === \"function\") {\n      result += $262.codePointRange(start, end);\n      continue;\n    }\n    let codePoints = [];\n    for (let length = 0, codePoint = start; codePoint <= end; codePoint++) {\n      codePoints[length++] = codePoint;\n      if (length === CHUNK_SIZE) {\n        result += String.fromCodePoint.apply(null, codePoints);\n        codePoints.length = length = 0;\n      }\n    }\n    result += String.fromCodePoint.apply(null, codePoints);\n  }\n  return result;\n}\n"

///|
pub struct ToolRun {
  stdout : String
  stderr : String
  code : Int
} derive(Debug)

///|
struct ProcessCapture {
  code : Int
  stdout : String
  stderr : String
} derive(Debug)

///|
pub struct HarnessOptions {
  priv helpers : Array[String]
} derive(Debug)

///|
fn HarnessOptions::HarnessOptions(
  helpers? : Array[String] = [],
) -> HarnessOptions {
  { helpers, }
}

///|
pub fn HarnessOptions::from_cli(
  values : ArrayView[String],
) -> HarnessOptions raise {
  let selected : Array[String] = []
  for raw in values {
    for name in raw.split(",") {
      let helper = name.trim().to_owned()
      if helper == "" {
        continue
      }
      if helper != HELPER_CODE_POINT_RANGE {
        fail(
          "unknown harness helper '\{helper}' (supported: \{HELPER_CODE_POINT_RANGE})",
        )
      }
      if !selected.any(item => item == helper) {
        selected.push(helper)
      }
    }
  }
  HarnessOptions(helpers=selected)
}

///|
fn HarnessOptions::helper_names(self : HarnessOptions) -> Array[String] {
  let out : Array[String] = []
  for helper in self.helpers {
    out.push(helper)
  }
  out
}

///|
fn HarnessOptions::is_modified(self : HarnessOptions) -> Bool {
  self.helpers.length() > 0
}

///|
fn HarnessOptions::methodology_label(self : HarnessOptions) -> String {
  if self.helpers.length() == 0 {
    "default"
  } else {
    "modified harness (helpers: \{self.helpers.join(", ")})"
  }
}

///|
fn HarnessOptions::preamble(self : HarnessOptions) -> String {
  let parts : Array[String] = []
  for helper in self.helpers {
    if helper == HELPER_CODE_POINT_RANGE {
      parts.push(CODE_POINT_RANGE_PREAMBLE)
    }
  }
  parts.join("\n")
}

///|
fn HarnessOptions::methodology_json_record(self : HarnessOptions) -> Json? {
  guard self.is_modified() else { return None }
  let helper_json = self.helpers.map(helper => Json::string(helper))
  Some(
    Json::object({
      "label": Json::string(self.methodology_label()),
      "harness": Json::string("modified"),
      "harness_helpers": Json::array(helper_json),
    }),
  )
}

///|
fn HarnessOptions::transform_include(
  self : HarnessOptions,
  include_name : String,
  source : String,
) -> String {
  guard self.helpers.any(helper => helper == HELPER_CODE_POINT_RANGE) else {
    return source
  }
  guard include_name.has_suffix("regExpUtils.js") else { return source }
  source.replace(
    old=REGEXP_UTILS_BUILD_STRING,
    new=REGEXP_UTILS_BUILD_STRING_WITH_HELPER,
  )
}

///|
pub struct RunnerConfig {
  priv engine : String?
  priv test262 : String
  priv filter : String
  priv tests_file : String
  priv start : Int
  priv count : Int?
  priv shard : (Int, Int)?
  priv resume_from : String
  priv log : String
  priv merged_log : String
  priv timeout : Int
  priv threads : Int?
  priv output : String
  priv summary : Bool
  priv verbose : Bool
  priv mode : String
  priv harness_options : HarnessOptions
  priv repo_root : String
} derive(Debug)

///|
pub fn RunnerConfig::RunnerConfig(
  engine~ : String?,
  test262? : String = DEFAULT_TEST262_DIR,
  filter? : String = "",
  tests_file? : String = "",
  start? : Int = 0,
  count? : Int? = None,
  shard? : (Int, Int)? = None,
  resume_from? : String = "",
  log? : String = "",
  merged_log? : String = "",
  timeout? : Int = DEFAULT_TIMEOUT_SECONDS,
  threads? : Int? = None,
  output? : String = "",
  summary? : Bool = false,
  verbose? : Bool = false,
  mode? : String = "both",
  harness_options? : HarnessOptions = HarnessOptions(),
  repo_root? : String = ".",
) -> RunnerConfig {
  {
    engine,
    test262,
    filter,
    tests_file,
    start,
    count,
    shard,
    resume_from,
    log,
    merged_log,
    timeout,
    threads,
    output,
    summary,
    verbose,
    mode,
    harness_options,
    repo_root,
  }
}

///|
struct TestMetadata {
  description : String
  info : String
  features : Array[String]
  flags : Array[String]
  includes : Array[String]
  negative : Map[String, Json]?
  es5id : String
  es6id : String
  esid : String
  raw : Bool
} derive(Debug)

///|
struct TestResult {
  path : String
  status : String
  reason : String
  duration_ms : Double
  mode : String
} derive(Debug)

///|
fn TestResult::TestResult(
  path~ : String,
  status~ : String,
  reason? : String = "",
  duration_ms? : Double = 0.0,
  mode? : String = "non-strict",
) -> TestResult {
  { path, status, reason, duration_ms, mode }
}

///|
struct CategoryStats {
  mut total : Int
  mut passed : Int
  mut failed : Int
  mut skipped : Int
  mut timeout : Int
  mut error : Int
} derive(Debug)

///|
fn CategoryStats::CategoryStats() -> CategoryStats {
  { total: 0, passed: 0, failed: 0, skipped: 0, timeout: 0, error: 0 }
}

///|
fn CategoryStats::pass_rate(self : CategoryStats) -> Double {
  let executed = self.passed + self.failed
  if executed == 0 {
    0.0
  } else {
    self.passed.to_double() / executed.to_double() * 100.0
  }
}

///|
struct AggregatedResults {
  overall : CategoryStats
  categories : Map[String, CategoryStats]
} derive(Debug)

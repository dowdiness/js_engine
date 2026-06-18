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
const HELPER_ATOMICS_TIMEOUT_PROFILE = "atomicsTimeoutProfile"

///|
const ATOMICS_TIMEOUT_PROFILE_DEFAULT = "default"

///|
const ATOMICS_TIMEOUT_PROFILE_SHORT = "short"

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

// Opt-in timeout helper for local diagnosis of Atomics-heavy tests.
// The injected wait timeout cap keeps local investigations from stalling on
// long-hanging Atomics waits when the goal is to triage failures quickly.

///|
fn atomics_timeout_profile_preamble(profile : String) -> String {
  let ms = if profile == ATOMICS_TIMEOUT_PROFILE_SHORT { 100 } else { 0 }
  let out = StringBuilder()
  out.write_string(
    "\n// Modified-harness Atomics timeout profile for local runs only.\n",
  )
  out.write_string("var __TEST262_ATOMICS_TIMEOUT_PROFILE = \"")
  out.write_string(profile)
  out.write_string("\";\n")
  out.write_string("var __TEST262_ATOMICS_TIMEOUT_MS = ")
  out.write_string(ms.to_string())
  out.write_string(";\n")
  out.write_string(
    "var __TEST262_LIMITED_ATOMICS_TIMEOUT = function(timeout) {\n",
  )
  out.write_string("  if (__TEST262_ATOMICS_TIMEOUT_PROFILE == \"")
  out.write_string(ATOMICS_TIMEOUT_PROFILE_DEFAULT)
  out.write_string("\") {\n")
  out.write_string("    return timeout;\n")
  out.write_string("  }\n")
  out.write_string(
    "  var __TEST262_LIMITED_ATOMICS_TIMEOUT_NUM = Number(timeout);\n",
  )
  out.write_string(
    "  if (Number.isNaN(__TEST262_LIMITED_ATOMICS_TIMEOUT_NUM)) {\n",
  )
  out.write_string(
    "    __TEST262_LIMITED_ATOMICS_TIMEOUT_NUM = Number.POSITIVE_INFINITY;\n",
  )
  out.write_string("  }\n")
  out.write_string("  if (__TEST262_LIMITED_ATOMICS_TIMEOUT_NUM < 0) {\n")
  out.write_string("    return __TEST262_LIMITED_ATOMICS_TIMEOUT_NUM;\n")
  out.write_string("  }\n")
  out.write_string(
    "  return (__TEST262_LIMITED_ATOMICS_TIMEOUT_NUM > __TEST262_ATOMICS_TIMEOUT_MS) ? __TEST262_ATOMICS_TIMEOUT_MS : __TEST262_LIMITED_ATOMICS_TIMEOUT_NUM;\n",
  )
  out.write_string("};\n")
  out.write_string(
    "if (typeof Atomics === 'object' && Atomics !== null && typeof Atomics.wait === 'function') {\n",
  )
  out.write_string("  var __TEST262_ORIGINAL_ATOMICS_WAIT = Atomics.wait;\n")
  out.write_string(
    "  Atomics.wait = function(typedArray, index, value, timeout) {\n",
  )
  out.write_string(
    "    return __TEST262_ORIGINAL_ATOMICS_WAIT(typedArray, index, value, __TEST262_LIMITED_ATOMICS_TIMEOUT(timeout));\n",
  )
  out.write_string("  };\n")
  out.write_string("}\n")
  out.write_string(
    "if (typeof Atomics === 'object' && Atomics !== null && typeof Atomics.waitAsync === 'function') {\n",
  )
  out.write_string(
    "  var __TEST262_ORIGINAL_ATOMICS_WAIT_ASYNC = Atomics.waitAsync;\n",
  )
  out.write_string(
    "  Atomics.waitAsync = function(typedArray, index, value, timeout) {\n",
  )
  out.write_string(
    "    return __TEST262_ORIGINAL_ATOMICS_WAIT_ASYNC(typedArray, index, value, __TEST262_LIMITED_ATOMICS_TIMEOUT(timeout));\n",
  )
  out.write_string("  };\n")
  out.write_string("}\n")
  out.to_string()
}

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
  priv atomics_timeout_profile : String
} derive(Debug)

///|
fn HarnessOptions::HarnessOptions(
  helpers? : Array[String] = [],
  atomics_timeout_profile? : String = ATOMICS_TIMEOUT_PROFILE_DEFAULT,
) -> HarnessOptions {
  { helpers, atomics_timeout_profile }
}

///|
fn parse_timeout_profile_value(raw : String) -> String raise {
  let value = raw.trim().to_owned()
  if value == ATOMICS_TIMEOUT_PROFILE_DEFAULT ||
    value == ATOMICS_TIMEOUT_PROFILE_SHORT {
    value
  } else {
    fail(
      "unknown atomicsTimeoutProfile '\{value}' (supported: " +
      ATOMICS_TIMEOUT_PROFILE_DEFAULT +
      ", " +
      ATOMICS_TIMEOUT_PROFILE_SHORT +
      ")",
    )
  }
}

///|
pub fn HarnessOptions::from_cli(
  values : ArrayView[String],
) -> HarnessOptions raise {
  let selected : Array[String] = []
  let mut atomics_timeout_profile = ATOMICS_TIMEOUT_PROFILE_DEFAULT
  for raw in values {
    for item in raw.split(",") {
      let helper = item.trim().to_owned()
      if helper == "" {
        continue
      }
      if helper == HELPER_CODE_POINT_RANGE {
        if !selected.any(item => item == helper) {
          selected.push(helper)
        }
        continue
      }
      match helper.split_once("=") {
        Some((name, value)) => {
          let name = name.trim().to_owned()
          let value = value.trim().to_owned()
          if name == HELPER_ATOMICS_TIMEOUT_PROFILE {
            if atomics_timeout_profile != ATOMICS_TIMEOUT_PROFILE_DEFAULT {
              fail("duplicate atomicsTimeoutProfile helper values")
            }
            atomics_timeout_profile = parse_timeout_profile_value(value)
            continue
          }
          fail(
            "unknown harness helper '\{name}' (supported: " +
            HELPER_CODE_POINT_RANGE +
            ", " +
            HELPER_ATOMICS_TIMEOUT_PROFILE +
            "=<value>)",
          )
        }
        None =>
          fail(
            "unknown harness helper '\{helper}' (supported: " +
            HELPER_CODE_POINT_RANGE +
            ", " +
            HELPER_ATOMICS_TIMEOUT_PROFILE +
            "=<value>)",
          )
      }
    }
  }
  HarnessOptions(helpers=selected, atomics_timeout_profile~)
}

///|
fn HarnessOptions::helper_names(self : HarnessOptions) -> Array[String] {
  let out : Array[String] = []
  for helper in self.helpers {
    out.push(helper)
  }
  if self.atomics_timeout_profile != ATOMICS_TIMEOUT_PROFILE_DEFAULT {
    out.push(
      HELPER_ATOMICS_TIMEOUT_PROFILE + "=" + self.atomics_timeout_profile,
    )
  }
  out
}

///|
fn HarnessOptions::is_modified(self : HarnessOptions) -> Bool {
  self.helpers.length() > 0 ||
  self.atomics_timeout_profile != ATOMICS_TIMEOUT_PROFILE_DEFAULT
}

///|
fn HarnessOptions::methodology_label(self : HarnessOptions) -> String {
  let helper_names = self.helper_names()
  if helper_names.length() == 0 {
    "default"
  } else {
    "modified harness (helpers: \{helper_names.join(", ")})"
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
  if self.atomics_timeout_profile != ATOMICS_TIMEOUT_PROFILE_DEFAULT {
    parts.push(atomics_timeout_profile_preamble(self.atomics_timeout_profile))
  }
  parts.join("\n")
}

///|
fn HarnessOptions::methodology_json_record(self : HarnessOptions) -> Json? {
  guard self.is_modified() else { return None }
  let helper_json = self.helper_names().map(helper => Json::string(helper))
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

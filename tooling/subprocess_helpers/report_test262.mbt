///|
const REPORT_GH_TIMEOUT_MS = 120000

///|
const REPORT_CLASSIFIER_TIMEOUT_MS = 120000

///|
pub struct ReportConfig {
  priv run_id : Int64?
  priv repo : String?
  priv workflow : String
  priv keep_artifacts : String?
  priv with_editions : Bool
  priv format : String
  priv baseline : String
  priv no_baseline : Bool
  priv repo_root : String?
} derive(Debug)

///|
pub fn ReportConfig::ReportConfig(
  run_id~ : Int64?,
  repo~ : String?,
  workflow~ : String,
  keep_artifacts~ : String?,
  with_editions~ : Bool,
  format~ : String,
  baseline~ : String,
  no_baseline~ : Bool,
  repo_root? : String? = None,
) -> ReportConfig {
  {
    run_id,
    repo,
    workflow,
    keep_artifacts,
    with_editions,
    format,
    baseline,
    no_baseline,
    repo_root,
  }
}

///|
struct RunInfo {
  id : Int64
  sha : String
  created_at : String
  url : String
} derive(Debug)

///|
struct Test262Summary {
  total : Int
  passed : Int
  failed : Int
  skipped : Int
  timeout : Int
  error : Int
} derive(Debug)

///|
struct BaselineInfo {
  strict_min : Int
  nonstrict_min : Int
  updated : String
} derive(Debug)

///|
fn json_object(value : Json, context : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail(context + " must be a JSON object")
  }
}

///|
fn json_array(value : Json, context : String) -> Array[Json] raise {
  match value {
    Array(items) => items
    _ => fail(context + " must be a JSON array")
  }
}

///|
fn required_field(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Json raise {
  match fields.get(key) {
    Some(value) => value
    None => fail(context + " missing required field " + key)
  }
}

///|
fn json_string_field(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> String raise {
  @json.from_json(required_field(fields, key, context))
}

///|
fn json_int_field(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Int raise {
  @json.from_json(required_field(fields, key, context))
}

///|
fn json_int64_field(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Int64 raise {
  // `gh` emits numeric ids (e.g. `databaseId`) as JSON numbers, but
  // `Int64::from_json` expects a quoted string, so decode the number here.
  // Prefer the lossless source `repr` when present.
  match required_field(fields, key, context) {
    Number(value, repr~) =>
      match repr {
        Some(text) =>
          @string.parse_int64(text) catch {
            _ => fail(context + " field " + key + " is not an integer")
          }
        // `@json.parse` always populates `repr` for parsed numbers, so this
        // arm is only reached for programmatically built `Json`; ids fit in
        // an integral double, where `to_int64` is exact.
        None => value.to_int64()
      }
    String(text) =>
      @string.parse_int64(text) catch {
        _ => fail(context + " field " + key + " is not an integer")
      }
    _ => fail(context + " field " + key + " must be a number or numeric string")
  }
}

///|
fn json_int_default(
  fields : Map[String, Json],
  key : String,
  default : Int,
) -> Int raise {
  match fields.get(key) {
    Some(value) => @json.from_json(value)
    None => default
  }
}

///|
fn run_info_from_json(value : Json) -> RunInfo raise {
  let fields = json_object(value, "workflow run")
  {
    id: json_int64_field(fields, "databaseId", "workflow run"),
    sha: json_string_field(fields, "headSha", "workflow run"),
    created_at: json_string_field(fields, "createdAt", "workflow run"),
    url: json_string_field(fields, "url", "workflow run"),
  }
}

///|
fn summary_from_json(value : Json) -> Test262Summary raise {
  let fields = json_object(value, "summary")
  {
    total: json_int_field(fields, "total", "summary"),
    passed: json_int_field(fields, "passed", "summary"),
    failed: json_int_field(fields, "failed", "summary"),
    skipped: json_int_field(fields, "skipped", "summary"),
    timeout: json_int_default(fields, "timeout", 0),
    error: json_int_default(fields, "error", 0),
  }
}

///|
fn load_summary_text(text : String) -> Test262Summary raise {
  let root = json_object(@json.parse(text), "result artifact")
  summary_from_json(required_field(root, "summary", "result artifact"))
}

///|
fn load_summary(path : String) -> Test262Summary raise {
  load_summary_text(@fs.read_file_to_string(path))
}

///|
fn baseline_from_json(value : Json) -> BaselineInfo raise {
  let fields = json_object(value, "baseline")
  let strict = match fields.get("strict") {
    Some(value) => json_object(value, "baseline.strict")
    None => {}
  }
  let nonstrict = match fields.get("non-strict") {
    Some(value) => json_object(value, "baseline.non-strict")
    None => {}
  }
  let updated = match fields.get("updated") {
    Some(value) => @json.from_json(value)
    None => "unknown date"
  }
  {
    strict_min: json_int_default(strict, "passed_min", 0),
    nonstrict_min: json_int_default(nonstrict, "passed_min", 0),
    updated,
  }
}

///|
fn load_baseline(path : String) -> BaselineInfo? raise {
  if !@fs.path_exists(path) {
    None
  } else {
    Some(baseline_from_json(@json.parse(@fs.read_file_to_string(path))))
  }
}

///|
fn prefix(source : String, len : Int) -> String {
  if source.length() <= len {
    source
  } else {
    source[:len].to_owned()
  }
}

///|
fn format_int_grouped(value : Int) -> String {
  let negative = value < 0
  let digits = (if negative { -value } else { value }).to_string()
  let parts : Array[String] = []
  let first = digits.length() % 3
  let mut index = 0
  if first != 0 {
    parts.push(digits[:first].to_owned())
    index = first
  }
  while index < digits.length() {
    parts.push(digits[index:index + 3].to_owned())
    index += 3
  }
  (if negative { "-" } else { "" }) + parts.join(",")
}

///|
fn signed_grouped(value : Int) -> String {
  if value >= 0 {
    "+" + format_int_grouped(value)
  } else {
    format_int_grouped(value)
  }
}

///|
fn pct(num : Int, denom : Int) -> String {
  if denom == 0 {
    "—"
  } else {
    format_fixed(num.to_double() * 100.0 / denom.to_double(), 1) + "%"
  }
}

///|
fn report_numbers(summary : Test262Summary) -> (Int, Int, Int) {
  let passed = summary.passed
  let executed = summary.passed + summary.failed
  let discovered = summary.total
  (passed, executed, discovered)
}

///|
fn render_baseline_line(
  baseline : BaselineInfo,
  strict : Test262Summary,
  nonstrict : Test262Summary,
) -> String {
  let s_delta = strict.passed - baseline.strict_min
  let n_delta = nonstrict.passed - baseline.nonstrict_min
  let status = if s_delta < 0 || n_delta < 0 { " **REGRESSION**" } else { "" }
  "CI regression baseline: `test262-baseline.json` (min " +
  format_int_grouped(baseline.nonstrict_min) +
  " non-strict / " +
  format_int_grouped(baseline.strict_min) +
  " strict passed, updated " +
  baseline.updated +
  "; currently " +
  signed_grouped(n_delta) +
  " / " +
  signed_grouped(s_delta) +
  " above)." +
  status
}

///|
fn render_changelog(
  run : RunInfo,
  strict : Test262Summary,
  nonstrict : Test262Summary,
  baseline : BaselineInfo?,
) -> String {
  let (sp, se, sd) = report_numbers(strict)
  let (np, ne, nd) = report_numbers(nonstrict)
  let date = prefix(run.created_at, 10)
  let sha = prefix(run.sha, 7)
  let parts : Array[String] = [
    "test262 (each file run in both strict and non-strict modes,",
    "reported separately — summing would double-count files):",
    "",
    "- **Passed / Executed**: " +
    pct(sp, se) +
    " strict (" +
    format_int_grouped(sp) +
    " / " +
    format_int_grouped(se) +
    "),",
    "  " +
    pct(np, ne) +
    " non-strict (" +
    format_int_grouped(np) +
    " / " +
    format_int_grouped(ne) +
    "). Excludes ~40% of",
    "  discovered files skipped for unimplemented features.",
    "- **Passed / Discovered**: " + pct(sp, sd) + " strict, " + pct(np, nd),
    "  non-strict. Counts skipped files as un-passed.",
    "",
    "Measured on CI run " +
    run.id.to_string() +
    " (tip `" +
    sha +
    "`, " +
    date +
    ").",
  ]
  match baseline {
    Some(info) => {
      let s_delta = sp - info.strict_min
      let n_delta = np - info.nonstrict_min
      if s_delta >= 0 && n_delta >= 0 {
        parts.push(
          "Regression baseline: +" +
          format_int_grouped(n_delta) +
          " non-strict / +" +
          format_int_grouped(s_delta) +
          " strict vs `test262-baseline.json` (min " +
          format_int_grouped(info.nonstrict_min) +
          " / " +
          format_int_grouped(info.strict_min) +
          ").",
        )
      } else {
        parts.push(
          "Regression baseline: " +
          signed_grouped(n_delta) +
          " non-strict / " +
          signed_grouped(s_delta) +
          " strict vs `test262-baseline.json` (min " +
          format_int_grouped(info.nonstrict_min) +
          " / " +
          format_int_grouped(info.strict_min) +
          "). **REGRESSION**",
        )
      }
    }
    None => ()
  }
  parts.join("\n")
}

///|
fn append_mode_report_line(
  lines : Array[String],
  mode : String,
  summary : Test262Summary,
) -> Unit {
  let discovered = summary.total
  let skipped = summary.skipped
  let passed = summary.passed
  let failed = summary.failed
  let timeout = summary.timeout
  let executed = passed + failed
  lines.push(
    "| " +
    mode +
    " | " +
    format_int_grouped(discovered) +
    " | " +
    format_int_grouped(skipped) +
    " | " +
    format_int_grouped(executed) +
    " | " +
    format_int_grouped(passed) +
    " | " +
    format_int_grouped(failed) +
    " | " +
    format_int_grouped(timeout) +
    " | **" +
    pct(passed, executed) +
    "** | " +
    pct(passed, discovered) +
    " |",
  )
}

///|
fn render_report(
  run : RunInfo,
  strict : Test262Summary,
  nonstrict : Test262Summary,
  baseline : BaselineInfo?,
) -> String {
  let sha = prefix(run.sha, 7)
  let date = prefix(run.created_at, 10)
  let lines : Array[String] = [
    "**Test262** — CI run [" +
    run.id.to_string() +
    "](" +
    run.url +
    ") on tip `" +
    sha +
    "`, " +
    date +
    ". Each test file is run twice (strict + non-strict); the two " +
    "are reported separately because summing would double-count files.",
    "",
    "| Mode | Discovered | Skipped | Executed | Passed | Failed | Timeouts | Passed / Executed | Passed / Discovered |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
  ]
  append_mode_report_line(lines, "strict", strict)
  append_mode_report_line(lines, "non-strict", nonstrict)
  match baseline {
    Some(info) => {
      lines.push("")
      lines.push(render_baseline_line(info, strict, nonstrict))
    }
    None => ()
  }
  let errors = strict.error + nonstrict.error
  if errors != 0 {
    lines.push("")
    lines.push(
      "_Note: " +
      errors.to_string() +
      " runner error(s) excluded from the " +
      "Timeouts column; inspect results JSON for details._",
    )
  }
  lines.join("\n")
}

///|
async fn executable_exists(cmd : String) -> Bool {
  if cmd.contains("/") {
    return @afs.can_execute(cmd) catch { _ => false }
  } else {
    let path = match @env.get_env_var("PATH") {
      Some(value) => value
      None => ""
    }
    for dir in path.split(":") {
      let can_execute = @afs.can_execute(join_path(dir.to_owned(), cmd)) catch {
        _ => false
      }
      if can_execute {
        return true
      }
    }
    false
  }
}

///|
async fn collect_process_args(
  exe : String,
  args : Array[String],
  timeout_ms : Int,
) -> ProcessCapture {
  let result = @async.with_timeout_opt(timeout_ms, () => {
    @process.collect_output(exe, args)
  })
  match result {
    None => fail(exe + " timed out after " + timeout_ms.to_string() + " ms")
    Some((code, stdout, stderr)) =>
      { code, stdout: stdout.text(), stderr: stderr.text() }
  }
}

///|
async fn gh(args : Array[String]) -> String {
  let capture = collect_process_args("gh", args, REPORT_GH_TIMEOUT_MS)
  if capture.code != 0 {
    fail(
      "gh " +
      args.join(" ") +
      " failed with exit code " +
      capture.code.to_string() +
      (if capture.stderr == "" {
        ""
      } else {
        ": " + capture.stderr.trim().to_owned()
      }),
    )
  }
  capture.stdout.trim().to_owned()
}

///|
async fn resolve_run(
  repo : String?,
  workflow : String,
  run_id : Int64?,
) -> RunInfo {
  let repo_flag = match repo {
    Some(value) => ["-R", value]
    None => []
  }
  let fields = "databaseId,headSha,createdAt,url"
  match run_id {
    None => {
      let args = [
        "run", "list", "--workflow", workflow, "--branch", "main", "--status", "success",
        "--limit", "1", "--json", fields, ..repo_flag,
      ]
      let data = json_array(@json.parse(gh(args)), "gh run list output")
      guard data.length() > 0 else {
        fail("No successful run found for workflow=" + workflow + " on main.")
      }
      run_info_from_json(data[0])
    }
    Some(id) => {
      let args = ["run", "view", id.to_string(), "--json", fields, ..repo_flag]
      run_info_from_json(@json.parse(gh(args)))
    }
  }
}

///|
async fn download_artifacts(
  run_id : Int64,
  repo : String?,
  out_dir : String,
) -> Unit {
  if !@fs.path_exists(out_dir) {
    @afs.mkdir(out_dir, recursive=true)
  }
  let repo_flag = match repo {
    Some(value) => ["-R", value]
    None => []
  }
  let args = [
    "run",
    "download",
    run_id.to_string(),
    "-p",
    "test262-*-results",
    "-D",
    out_dir,
    ..repo_flag,
  ]
  ignore(gh(args))
}

///|
fn find_file_rec(dir : String, filename : String) -> String? raise {
  guard @fs.path_exists(dir) && @fs.is_dir(dir) else { return None }
  let entries = @fs.read_dir(dir)
  entries.sort()
  for entry in entries {
    let path = join_path(dir, entry)
    if @fs.is_dir(path) {
      match find_file_rec(path, filename) {
        Some(found) => return Some(found)
        None => ()
      }
    } else if @fs.is_file(path) && entry == filename {
      return Some(path)
    }
  }
  None
}

///|
fn find_results(artifact_dir : String) -> (String, String) raise {
  let strict = find_file_rec(artifact_dir, "test262-strict-results.json")
  let nonstrict = find_file_rec(artifact_dir, "test262-non-strict-results.json")
  match (strict, nonstrict) {
    (Some(s), Some(n)) => (s, n)
    _ =>
      fail(
        "Missing strict or non-strict results under " +
        artifact_dir +
        ". Did both CI jobs succeed?",
      )
  }
}

///|
fn validate_report_format(format : String) -> Unit raise {
  if format != "table" && format != "changelog" {
    fail(
      "error: argument --format: invalid choice: '" +
      format +
      "' (choose from 'table', 'changelog')",
    )
  }
}

///|
pub async fn run_report(config : ReportConfig) -> ToolRun {
  validate_report_format(config.format)
  if !executable_exists("gh") {
    fail("gh CLI not found; install from https://cli.github.com/")
  }

  let run = resolve_run(config.repo, config.workflow, config.run_id)
  let (art_dir, cleanup) = match config.keep_artifacts {
    Some(dir) => (dir, false)
    None => (@afs.tmpdir(prefix="test262-ci-"), true)
  }
  let mut stdout = ""
  let mut stderr = ""
  let mut code = 0
  try {
    download_artifacts(run.id, config.repo, art_dir)
    let (strict_path, nonstrict_path) = find_results(art_dir)
    let strict = load_summary(strict_path)
    let nonstrict = load_summary(nonstrict_path)
    let baseline = if config.no_baseline {
      None
    } else {
      load_baseline(config.baseline)
    }
    stdout = if config.format == "changelog" {
      render_changelog(run, strict, nonstrict, baseline) + "\n"
    } else {
      render_report(run, strict, nonstrict, baseline) + "\n"
    }
    if config.format == "table" && config.with_editions {
      stdout += "\n"
      let repo_root = match config.repo_root {
        Some(root) => root
        None => current_dir_or_dot()
      }
      let classifier = join_path(
        repo_root,
        "_build/native/debug/build/cmd/classify_by_edition/classify_by_edition.exe",
      )
      let capture = collect_process_args(
        classifier,
        ["--markdown", strict_path, nonstrict_path],
        REPORT_CLASSIFIER_TIMEOUT_MS,
      )
      stdout += capture.stdout
      stderr += capture.stderr
      if capture.code != 0 {
        code = capture.code
      }
    }
  } catch {
    err => {
      if cleanup {
        @afs.rmdir(art_dir, recursive=true) catch {
          _ => ()
        }
      }
      raise err
    }
  }
  if cleanup {
    @afs.rmdir(art_dir, recursive=true) catch {
      _ => ()
    }
  }
  { stdout, stderr, code }
}

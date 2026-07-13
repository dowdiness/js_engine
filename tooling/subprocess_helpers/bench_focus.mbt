///|
const CSV_HEADER_TEXT = "name,category,stage,warmup,iterations,group_size,mean_ms,min_ms,max_ms,stddev_ms,cv_pct,noisy"

///|
pub const DEFAULT_BENCH_COMMAND = "moon run benchmarks --target js -- --all --csv"

///|
const DEFAULT_PROCESS_TIMEOUT_MS = 3600000

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
pub struct BenchConfig {
  priv runs : Int
  priv rows : Array[String]
  priv command : String
  priv output_root : String
  priv timestamp : String?
  priv fail_on_missing : Bool
  priv command_timeout_ms : Int
} derive(Debug)

///|
pub fn BenchConfig::BenchConfig(
  runs~ : Int,
  rows~ : Array[String],
  command~ : String,
  output_root~ : String,
  timestamp~ : String?,
  fail_on_missing~ : Bool,
  command_timeout_ms? : Int = DEFAULT_PROCESS_TIMEOUT_MS,
) -> BenchConfig {
  {
    runs,
    rows,
    command,
    output_root,
    timestamp,
    fail_on_missing,
    command_timeout_ms,
  }
}

///|
struct BenchSummary {
  name : String
  runs : Int
  median_ms : Double
  mean_ms : Double
  min_ms : Double
  max_ms : Double
  run_cv_pct : Double
  median_in_run_cv_pct : Double
} derive(Debug)

///|
pub fn default_bench_rows() -> Array[String] {
  [
    "isolate/bytecode/runtime_helpers", "isolate/bytecode/property_get", "isolate/bytecode/property_set",
    "isolate/bytecode/method_call", "pipeline/bytecode/evaluate",
  ]
}

///|
fn normalize_newlines(source : String) -> String {
  source.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
fn splitlines(source : String) -> Array[String] {
  let lines = normalize_newlines(source)
    .split("\n")
    .map(line => line.to_owned())
    .to_array()
  if lines.last() == Some("") {
    ignore(lines.pop())
  }
  lines
}

///|
fn pad_int(value : Int, width : Int) -> String {
  value.to_string().pad_start(width, '0')
}

///|
fn civil_from_days(days_since_epoch : Int) -> (Int, Int, Int) {
  let z = days_since_epoch + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = mp + (if mp < 10 { 3 } else { -9 })
  let year = y + (if month <= 2 { 1 } else { 0 })
  (year, month, day)
}

///|
fn utc_timestamp() -> String {
  let total_seconds = (@env.now().to_double() / 1000.0).floor().to_int()
  let days = total_seconds / 86400
  let mut second_of_day = total_seconds % 86400
  if second_of_day < 0 {
    second_of_day += 86400
  }
  let hour = second_of_day / 3600
  let minute = second_of_day % 3600 / 60
  let second = second_of_day % 60
  let (year, month, day) = civil_from_days(days)
  pad_int(year, 4) +
  pad_int(month, 2) +
  pad_int(day, 2) +
  "T" +
  pad_int(hour, 2) +
  pad_int(minute, 2) +
  pad_int(second, 2) +
  "Z"
}

///|
fn bench_output_dir(root : String, timestamp : String?) -> String {
  @path_utils.join_path(
    root,
    match timestamp {
      Some(value) => value
      None => utc_timestamp()
    },
  )
}

///|
pub fn row_names(raw : String) -> Array[String] raise {
  let names : Array[String] = []
  for part in raw.split(",") {
    let name = part.trim().to_owned()
    if name != "" {
      names.push(name)
    }
  }
  if names.is_empty() {
    fail("error: --rows must select at least one benchmark row")
  }
  names
}

///|
async fn collect_command(
  command : String,
  timeout_ms? : Int = DEFAULT_PROCESS_TIMEOUT_MS,
) -> ProcessCapture {
  let argv = tokenize_command(command)
  guard argv.length() > 0 else { fail("error: benchmark command is empty") }
  let exe = argv[0]
  let args = argv[1:]
  let result = @async.with_timeout_opt(timeout_ms, () => {
    @process.collect_output(exe, args)
  })
  match result {
    None => fail("benchmark command timed out after \{timeout_ms} ms")
    Some((code, stdout, stderr)) =>
      { code, stdout: stdout.text(), stderr: stderr.text() }
  }
}

///|
fn csv_text_from_stdout(stdout : String) -> String raise {
  let lines = splitlines(stdout)
  for i, line in lines {
    if line == CSV_HEADER_TEXT {
      return lines[i:].join("\n") + "\n"
    }
  }
  fail("benchmark output did not contain the expected CSV header")
}

///|
fn parse_csv_record(line : String) -> Array[String] raise {
  let fields : Array[String] = []
  let buf = StringBuilder()
  let chars = line.to_array()
  let mut i = 0
  let mut in_quotes = false
  while i < chars.length() {
    let ch = chars[i]
    if in_quotes {
      if ch == '"' {
        if i + 1 < chars.length() && chars[i + 1] == '"' {
          buf.write_char('"')
          i += 1
        } else {
          in_quotes = false
        }
      } else {
        buf.write_char(ch)
      }
    } else if ch == ',' {
      fields.push(buf.to_string())
      buf.reset()
    } else if ch == '"' && buf.is_empty() {
      in_quotes = true
    } else {
      buf.write_char(ch)
    }
    i += 1
  }
  if in_quotes {
    fail("unterminated quoted CSV field")
  }
  fields.push(buf.to_string())
  fields
}

///|
fn parse_rows(csv_text : String) -> Map[String, Map[String, String]] raise {
  let lines = splitlines(csv_text)
  let rows : Map[String, Map[String, String]] = {}
  guard lines.length() > 0 else { return rows }
  let header = parse_csv_record(lines[0])
  for line in lines[1:] {
    if line == "" {
      continue
    }
    let values = parse_csv_record(line)
    let row : Map[String, String] = {}
    for i, key in header {
      match values.get(i) {
        Some(value) => row[key] = value
        None => row[key] = ""
      }
    }
    match row.get("name") {
      Some(name) => rows[name] = row
      None => ()
    }
  }
  rows
}

///|
fn parse_double_field(row : Map[String, String], key : String) -> Double raise {
  match row.get(key) {
    Some(value) => @string.parse_double(value)
    None => fail("missing CSV field: " + key)
  }
}

///|
fn median(values : Array[Double]) -> Double {
  let sorted = values.copy()
  sorted.sort()
  let n = sorted.length()
  if n == 0 {
    0.0
  } else if n % 2 == 1 {
    sorted[n / 2]
  } else {
    (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
  }
}

///|
fn mean(values : Array[Double]) -> Double {
  if values.is_empty() {
    0.0
  } else {
    let mut total = 0.0
    for value in values {
      total += value
    }
    total / values.length().to_double()
  }
}

///|
fn sample_stdev(values : Array[Double]) -> Double {
  if values.length() <= 1 {
    0.0
  } else {
    let avg = mean(values)
    let mut total = 0.0
    for value in values {
      let delta = value - avg
      total += delta * delta
    }
    (total / (values.length() - 1).to_double()).sqrt()
  }
}

///|
fn summarize_row(
  name : String,
  rows_by_run : Array[Map[String, Map[String, String]]],
) -> BenchSummary raise {
  let means : Array[Double] = []
  let cvs : Array[Double] = []
  for rows in rows_by_run {
    match rows.get(name) {
      Some(row) => {
        means.push(parse_double_field(row, "mean_ms"))
        cvs.push(parse_double_field(row, "cv_pct"))
      }
      None => ()
    }
  }
  if means.is_empty() {
    {
      name,
      runs: 0,
      median_ms: 0.0,
      mean_ms: 0.0,
      min_ms: 0.0,
      max_ms: 0.0,
      run_cv_pct: 0.0,
      median_in_run_cv_pct: 0.0,
    }
  } else {
    let avg = mean(means)
    let spread = sample_stdev(means)
    let sorted = means.copy()
    sorted.sort()
    {
      name,
      runs: means.length(),
      median_ms: median(means),
      mean_ms: avg,
      min_ms: sorted[0],
      max_ms: sorted[sorted.length() - 1],
      run_cv_pct: if avg > 0.0 {
        spread / avg * 100.0
      } else {
        0.0
      },
      median_in_run_cv_pct: median(cvs),
    }
  }
}

///|
fn pow10(places : Int) -> Int {
  let mut value = 1
  for _ in 0..<places {
    value *= 10
  }
  value
}

///|
fn format_fixed(value : Double, places : Int) -> String {
  let scale = pow10(places)
  let mut scaled = (value * scale.to_double()).round().to_int()
  let negative = scaled < 0
  if negative {
    scaled = -scaled
  }
  let whole = scaled / scale
  let frac = scaled % scale
  let prefix = if negative { "-" } else { "" }
  prefix + whole.to_string() + "." + frac.to_string().pad_start(places, '0')
}

///|
fn fmt_ms(value : Double) -> String {
  format_fixed(value, 3) + " ms"
}

///|
fn fmt_pct(value : Double) -> String {
  format_fixed(value, 1) + "%"
}

///|
fn render_bench_table(
  summaries : Array[BenchSummary],
  total_runs : Int,
) -> String {
  let lines : Array[String] = [
    "| benchmark | runs | median | mean | min | max | across-run CV | median in-run CV |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ]
  for summary in summaries {
    if summary.runs == 0 {
      lines.push(
        "| `" +
        summary.name +
        "` | 0/" +
        total_runs.to_string() +
        " | — | — | — | — | — | — |",
      )
    } else {
      lines.push(
        "| `" +
        summary.name +
        "` | " +
        summary.runs.to_string() +
        "/" +
        total_runs.to_string() +
        " | " +
        fmt_ms(summary.median_ms) +
        " | " +
        fmt_ms(summary.mean_ms) +
        " | " +
        fmt_ms(summary.min_ms) +
        " | " +
        fmt_ms(summary.max_ms) +
        " | " +
        fmt_pct(summary.run_cv_pct) +
        " | " +
        fmt_pct(summary.median_in_run_cv_pct) +
        " |",
      )
    }
  }
  lines.join("\n")
}

///|
fn csv_path(out_dir : String, run : Int) -> String {
  @path_utils.join_path(
    out_dir,
    "run-" + run.to_string().pad_start(2, '0') + ".csv",
  )
}

///|
pub async fn run_bench_focus(config : BenchConfig) -> ToolRun {
  if config.runs <= 0 {
    fail("error: --runs must be positive")
  }
  if config.rows.is_empty() {
    fail("error: --rows must select at least one benchmark row")
  }
  let out_dir = bench_output_dir(config.output_root, config.timestamp)
  @afs.mkdir(out_dir, recursive=true)

  let stdout = StringBuilder()
  let stderr = StringBuilder()
  stdout.write_string("Command: " + config.command + "\n")
  stdout.write_string("Runs: " + config.runs.to_string() + "\n")
  stdout.write_string("Rows: " + config.rows.join(", ") + "\n")
  stdout.write_string("Raw CSV output: " + out_dir + "\n")
  stdout.write_string("\n")

  let rows_by_run : Array[Map[String, Map[String, String]]] = []
  for run in 1..<=config.runs {
    stdout.write_string(
      "[" +
      run.to_string() +
      "/" +
      config.runs.to_string() +
      "] running benchmark command...\n",
    )
    let capture = collect_command(
      config.command,
      timeout_ms=config.command_timeout_ms,
    )
    if capture.code != 0 {
      stdout.write_string(capture.stdout)
      stderr.write_string(capture.stderr)
      stderr.write_string(
        "benchmark command failed with exit code " +
        capture.code.to_string() +
        "\n",
      )
      return { stdout: stdout.to_string(), stderr: stderr.to_string(), code: 1 }
    }
    if capture.stderr != "" {
      stderr.write_string(capture.stderr)
    }
    let csv_text = csv_text_from_stdout(capture.stdout)
    @afs.write_file(
      csv_path(out_dir, run),
      csv_text,
      create_mode=CreateOrTruncate,
    )
    rows_by_run.push(parse_rows(csv_text))
  }

  let summaries : Array[BenchSummary] = []
  for name in config.rows {
    summaries.push(summarize_row(name, rows_by_run))
  }
  stdout.write_string("\n")
  stdout.write_string(render_bench_table(summaries, config.runs))
  stdout.write_string("\n")

  let missing : Array[String] = []
  for summary in summaries {
    if summary.runs != config.runs {
      missing.push(summary.name)
    }
  }
  let mut code = 0
  if !missing.is_empty() {
    stderr.write_string("\n")
    stderr.write_string(
      "warning: missing selected rows in at least one run: " +
      missing.join(", ") +
      "\n",
    )
    if config.fail_on_missing {
      code = 1
    }
  }
  { stdout: stdout.to_string(), stderr: stderr.to_string(), code }
}

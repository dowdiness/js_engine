///|
fn category_for_path(path : String, test262_dir : String) -> String {
  let rel = normalize_test262_path(path, test262_dir~)
  let parts = rel.split("/").map(part => part.to_owned()).to_array()
  if parts.length() >= 2 {
    parts[0] + "/" + parts[1]
  } else if parts.length() == 1 {
    parts[0]
  } else {
    ""
  }
}

///|
fn increment_status(stats : CategoryStats, status : String) -> Unit {
  stats.total += 1
  match status {
    "pass" => stats.passed += 1
    "fail" => stats.failed += 1
    "skip" => stats.skipped += 1
    "timeout" => stats.timeout += 1
    _ => stats.error += 1
  }
}

///|
fn aggregate_results(
  results : Array[TestResult],
  test262_dir~ : String,
) -> AggregatedResults {
  let categories : Map[String, CategoryStats] = {}
  let overall = CategoryStats()
  for result in results {
    let cat = category_for_path(result.path, test262_dir)
    if !categories.contains(cat) {
      categories[cat] = CategoryStats()
    }
    increment_status(categories[cat], result.status)
    increment_status(overall, result.status)
  }
  { overall, categories }
}

///|
fn pow10(places : Int) -> Int {
  let mut scale = 1
  for _ in 0..<places {
    scale *= 10
  }
  scale
}

///|
fn pad_left_zero(value : String, width : Int) -> String {
  let buf = StringBuilder()
  for _ in value.length()..<width {
    buf.write_char('0')
  }
  buf.write_string(value)
  buf.to_string()
}

///|
fn format_decimal(value : Double, places : Int) -> String {
  let scale = pow10(places)
  let mut scaled = (value * scale.to_double()).round().to_int()
  let sign = if scaled < 0 {
    scaled = -scaled
    "-"
  } else {
    ""
  }
  let whole = scaled / scale
  let frac = scaled % scale
  if places == 0 {
    sign + whole.to_string()
  } else {
    sign + whole.to_string() + "." + pad_left_zero(frac.to_string(), places)
  }
}

///|
fn rounded_double(value : Double, places : Int) -> Double {
  let scale = pow10(places)
  (value * scale.to_double()).round() / scale.to_double()
}

///|
fn json_int(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn json_double(value : Double, places : Int) -> Json {
  Json::number(
    rounded_double(value, places),
    repr=format_decimal(value, places),
  )
}

///|
fn result_json_record(result : TestResult) -> Json {
  Json::object({
    "path": Json::string(relative_path(result.path, current_dir_or_dot())),
    "status": Json::string(result.status),
    "reason": Json::string(result.reason),
    "duration_ms": json_double(result.duration_ms, 1),
    "mode": Json::string(result.mode),
  })
}

///|
fn[V] sorted_keys(map : Map[String, V]) -> Array[String] {
  let keys : Array[String] = []
  for key, _ in map {
    keys.push(key)
  }
  keys.sort()
  keys
}

///|
fn results_artifact(
  results : Array[TestResult],
  agg : AggregatedResults,
  harness_options? : HarnessOptions = HarnessOptions(),
) -> Json {
  let overall = agg.overall
  let summary : Map[String, Json] = {
    "total": json_int(overall.total),
    "passed": json_int(overall.passed),
    "failed": json_int(overall.failed),
    "skipped": json_int(overall.skipped),
    "timeout": json_int(overall.timeout),
    "error": json_int(overall.error),
    "pass_rate": json_double(overall.pass_rate(), 2),
  }
  match harness_options.methodology_json_record() {
    Some(Json::Object(methodology)) =>
      summary["methodology"] = methodology["label"]
    _ => ()
  }
  let categories : Map[String, Json] = {}
  for cat in sorted_keys(agg.categories) {
    let stats = agg.categories[cat]
    categories[cat] = Json::object({
      "total": json_int(stats.total),
      "passed": json_int(stats.passed),
      "failed": json_int(stats.failed),
      "skipped": json_int(stats.skipped),
      "pass_rate": json_double(stats.pass_rate(), 2),
    })
  }
  let result_records = results.map(result => result_json_record(result))
  let data : Map[String, Json] = {
    "engine": Json::string(ENGINE_NAME),
    "date": Json::string("1970-01-01T00:00:00Z"),
    "summary": Json::object(summary),
    "categories": Json::object(categories),
    "results": Json::array(result_records),
  }
  match harness_options.methodology_json_record() {
    Some(methodology) => data["methodology"] = methodology
    None => ()
  }
  Json::object(data)
}

///|
fn save_results(
  results : Array[TestResult],
  agg : AggregatedResults,
  output_file : String,
  harness_options? : HarnessOptions = HarnessOptions(),
) -> Unit raise {
  ensure_parent_dir(output_file)
  let data = results_artifact(results, agg, harness_options~)
  @fs.write_string_to_file(output_file, data.stringify(indent=2) + "\n")
}

///|
fn result_log_line(result : TestResult) -> String {
  result_json_record(result).stringify()
}

///|
async fn initialize_result_logs(
  progress_log : String,
  merged_log : String,
) -> Unit {
  if progress_log != "" {
    ensure_parent_dir(progress_log)
    @fs.write_string_to_file(progress_log, "")
  }
  if merged_log != "" {
    ensure_parent_dir(merged_log)
    let file = @afs.open(
      merged_log,
      mode=WriteOnly,
      create_mode=OpenOrCreate,
      append=true,
    )
    file.close()
  }
}

///|
async fn append_result_log_line(path : String, result : TestResult) -> Unit {
  guard path != "" else { return }
  @afs.write_file(
    path,
    result_log_line(result) + "\n",
    create_mode=OpenOrCreate,
    append=true,
  )
}

///|
async fn write_result_logs(
  progress_log : String,
  merged_log : String,
  result : TestResult,
) -> Unit {
  append_result_log_line(progress_log, result)
  if result.status == "fail" ||
    result.status == "timeout" ||
    result.status == "error" {
    append_result_log_line(merged_log, result)
  }
}

///|
fn pad_right(value : String, width : Int) -> String {
  if value.length() >= width {
    value
  } else {
    let buf = StringBuilder()
    buf.write_string(value)
    for _ in value.length()..<width {
      buf.write_char(' ')
    }
    buf.to_string()
  }
}

///|
fn pad_left(value : String, width : Int) -> String {
  if value.length() >= width {
    value
  } else {
    let buf = StringBuilder()
    for _ in value.length()..<width {
      buf.write_char(' ')
    }
    buf.write_string(value)
    buf.to_string()
  }
}

///|
fn print_report_text(
  agg : AggregatedResults,
  results : Array[TestResult],
  summary_only : Bool,
  methodology_label : String,
) -> String {
  let out = StringBuilder()
  let overall = agg.overall
  let executed = overall.passed + overall.failed
  out.write_string(
    "\n" +
    "========================================================================" +
    "\n",
  )
  out.write_string("  Test262 ECMAScript Conformance Report\n")
  out.write_string("  Engine: MoonBit JS Engine\n")
  out.write_string("  Date: 1970-01-01 00:00:00\n")
  if methodology_label != "default" {
    out.write_string("  Methodology: \{methodology_label}\n")
  }
  out.write_string(
    "========================================================================\n",
  )
  out.write_string("\n  Total tests discovered: \{overall.total}\n")
  out.write_string("  Skipped:               \{overall.skipped}\n")
  out.write_string("  Executed:              \{executed}\n")
  out.write_string("  Passed:                \{overall.passed}\n")
  out.write_string("  Failed:                \{overall.failed}\n")
  out.write_string("  Timeouts:              \{overall.timeout}\n")
  out.write_string("  Errors:                \{overall.error}\n")
  if executed > 0 {
    out.write_string(
      "\n  Pass rate:             \{format_decimal(overall.pass_rate(), 1)}% (\{overall.passed}/\{executed})\n",
    )
  }
  out.write_string(
    "\n────────────────────────────────────────────────────────────────────────\n",
  )
  out.write_string(
    "  " +
    pad_right("Category", 40) +
    pad_left("Pass", 6) +
    pad_left("Fail", 6) +
    pad_left("Skip", 6) +
    pad_left("Rate", 8) +
    "\n",
  )
  out.write_string(
    "────────────────────────────────────────────────────────────────────────\n",
  )
  for cat in sorted_keys(agg.categories) {
    let stats = agg.categories[cat]
    let ex = stats.passed + stats.failed
    let rate = if ex > 0 {
      format_decimal(stats.pass_rate(), 1) + "%"
    } else {
      "N/A"
    }
    out.write_string(
      "  " +
      pad_right(cat, 40) +
      pad_left(stats.passed.to_string(), 6) +
      pad_left(stats.failed.to_string(), 6) +
      pad_left(stats.skipped.to_string(), 6) +
      pad_left(rate, 8) +
      "\n",
    )
  }
  out.write_string(
    "────────────────────────────────────────────────────────────────────────\n",
  )
  if !summary_only {
    let failures = results.filter(result => result.status == "fail")
    if failures.length() > 0 {
      out.write_string("\n  Failed tests (\{failures.length()}):\n")
      out.write_string(
        "────────────────────────────────────────────────────────────────────────\n",
      )
      let limit = if failures.length() < 50 { failures.length() } else { 50 }
      for i in 0..<limit {
        let result = failures[i]
        out.write_string(
          "  FAIL: \{relative_path(result.path, current_dir_or_dot())}\n",
        )
        if result.reason != "" {
          let reason_short = truncate_reason(result.reason).replace_all(
            old="\n",
            new=" ",
          )
          out.write_string("        \{reason_short}\n")
        }
      }
      if failures.length() > 50 {
        out.write_string("  ... and \{failures.length() - 50} more\n")
      }
    }
  }
  out.write_string("\n")
  out.to_string()
}

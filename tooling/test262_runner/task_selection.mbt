///|
fn parse_metadata(source : String) -> TestMetadata {
  match @utils.parse_yaml_frontmatter(source) {
    None =>
      {
        description: "",
        info: "",
        features: [],
        flags: [],
        includes: [],
        negative: None,
        es5id: "",
        es6id: "",
        esid: "",
        raw: false,
      }
    Some(data) => {
      let flags = json_list_field(data, "flags")
      let negative = match data.get("negative") {
        Some(Json::Object(value)) => Some(value)
        _ => None
      }
      {
        description: json_string_field(data, "description"),
        info: json_string_field(data, "info"),
        features: json_list_field(data, "features"),
        flags,
        includes: json_list_field(data, "includes"),
        negative,
        es5id: json_string_field(data, "es5id"),
        es6id: json_string_field(data, "es6id"),
        esid: json_string_field(data, "esid"),
        raw: flags.any(flag => flag == "raw"),
      }
    }
  }
}

///|
fn parse_tests_file_contents(contents : String) -> Array[String] {
  let entries : Array[String] = []
  for raw_line in contents.split("\n") {
    let mut line = raw_line.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    match line.find("#") {
      Some(index) => line = line[:index].trim_end().to_owned()
      None => ()
    }
    if line != "" {
      entries.push(line)
    }
  }
  entries
}

///|
fn resolve_test_entry(entry : String, test262_dir : String) -> String raise {
  let entry = entry.trim().to_owned()
  guard entry != "" else { fail("empty Test262 test entry") }
  if entry.has_prefix("/") {
    return normalize_path(entry)
  }
  let normalized = normalize_path(entry)
  if normalized.has_prefix("test262/test/") {
    return absolute_path(
      join_path(
        test262_dir,
        "test/" + normalized["test262/test/".length():].to_owned(),
      ),
    )
  }
  if normalized.has_prefix("test/") {
    return absolute_path(join_path(test262_dir, normalized))
  }
  absolute_path(join_path(join_path(test262_dir, "test"), normalized))
}

///|
fn load_tests_file(
  tests_file : String,
  test262_dir : String,
) -> Array[String] raise {
  let contents = @fs.read_file_to_string(tests_file)
  parse_tests_file_contents(contents).map(entry => {
    resolve_test_entry(entry, test262_dir)
  })
}

///|
fn slice_tasks(
  tasks : Array[(String, String)],
  start? : Int = 0,
  count? : Int? = None,
) -> Array[(String, String)] raise {
  if start < 0 {
    fail("task slice start must be >= 0")
  }
  match count {
    Some(value) if value < 0 => fail("task slice count must be >= 0")
    _ => ()
  }
  let end = match count {
    Some(value) => start + value
    None => tasks.length()
  }
  let actual_start = if start > tasks.length() { tasks.length() } else { start }
  let actual_end = if end > tasks.length() { tasks.length() } else { end }
  let out : Array[(String, String)] = []
  for i in actual_start..<actual_end {
    out.push(tasks[i])
  }
  out
}

///|
pub fn parse_shard_spec(spec : String) -> (Int, Int) raise {
  let parts = spec.split("/").map(part => part.trim().to_owned()).to_array()
  guard parts.length() == 2 else {
    fail("shard must use i/n syntax, for example 2/8")
  }
  let shard_index = @string.parse_int(parts[0]) catch {
    _ => fail("shard must use i/n syntax, for example 2/8")
  }
  let shard_total = @string.parse_int(parts[1]) catch {
    _ => fail("shard must use i/n syntax, for example 2/8")
  }
  if shard_total <= 0 {
    fail("shard total must be > 0")
  }
  if shard_index <= 0 || shard_index > shard_total {
    fail("shard index must be between 1 and shard total")
  }
  (shard_index, shard_total)
}

///|
fn shard_bounds(
  total_tasks : Int,
  shard_index : Int,
  shard_total : Int,
) -> (Int, Int) raise {
  if total_tasks < 0 {
    fail("total task count must be >= 0")
  }
  if shard_total <= 0 {
    fail("shard total must be > 0")
  }
  if shard_index <= 0 || shard_index > shard_total {
    fail("shard index must be between 1 and shard total")
  }
  let base = total_tasks / shard_total
  let remainder = total_tasks % shard_total
  let smaller = if shard_index - 1 < remainder {
    shard_index - 1
  } else {
    remainder
  }
  let start = (shard_index - 1) * base + smaller
  let extra = if shard_index <= remainder { 1 } else { 0 }
  let end = start + base + extra
  (start, end)
}

///|
fn shard_tasks(
  tasks : Array[(String, String)],
  shard_index : Int,
  shard_total : Int,
) -> Array[(String, String)] raise {
  let (start, end) = shard_bounds(tasks.length(), shard_index, shard_total)
  slice_tasks(tasks, start~, count=Some(end - start))
}

///|
fn normalize_test262_path(path : String, test262_dir? : String = "") -> String {
  let raw = path.trim().to_owned()
  if raw == "" {
    return ""
  }
  if test262_dir != "" {
    let test_root = absolute_path(join_path(test262_dir, "test"))
    let candidate = if raw.has_prefix("/") { raw } else { absolute_path(raw) }
    let rel = relative_path(candidate, test_root)
    if rel != ".." && !rel.has_prefix("../") {
      return rel.replace_all(old="\\", new="/")
    }
  }
  let mut normalized = normalize_path(raw).replace_all(old="\\", new="/")
  if normalized.has_prefix("./") {
    normalized = normalized[2:].to_owned()
  }
  for prefix in ["test262/test/", "test/"] {
    if normalized.has_prefix(prefix) {
      return normalized[prefix.length():].to_owned()
    }
  }
  let marker = "/test262/test/"
  match normalized.find(marker) {
    Some(index) => normalized[index + marker.length():].to_owned()
    None => normalized
  }
}

///|
fn task_key(task : (String, String), test262_dir : String) -> (String, String) {
  (normalize_test262_path(task.0, test262_dir~), task.1)
}

///|
fn load_completed_task_keys(
  results_file : String,
  test262_dir? : String = "",
) -> @set.Set[String] raise {
  let raw = @json.parse(@fs.read_file_to_string(results_file))
  let root : Map[String, Json] = @json.from_json(raw) catch { _ => {} }
  let completed = @set.Set::default()
  let finished = @set.Set(["pass", "fail", "skip", "timeout", "error"])
  let records : Array[Json] = match root.get("results") {
    Some(Json::Array(items)) => items
    _ => []
  }
  for item in records {
    match item {
      Json::Object(record) => {
        let status = json_string_field(record, "status")
        guard finished.contains(status) else { continue }
        let path = json_string_field(record, "path")
        guard path != "" else { continue }
        let mode = match record.get("mode") {
          Some(value) => json_to_string(value)
          None => "non-strict"
        }
        completed.add(
          normalize_test262_path(path, test262_dir~) + "\u0000" + mode,
        )
      }
      _ => ()
    }
  }
  completed
}

///|
fn filter_completed_tasks(
  tasks : Array[(String, String)],
  completed_keys : @set.Set[String],
  test262_dir? : String = "",
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for task in tasks {
    let key = task_key(task, test262_dir)
    if !completed_keys.contains(key.0 + "\u0000" + key.1) {
      out.push(task)
    }
  }
  out
}

///|
fn default_modes_for_run_mode(run_mode : String) -> Array[String] {
  let modes : Array[String] = []
  if run_mode == "both" || run_mode == "non-strict" {
    modes.push("non-strict")
  }
  if run_mode == "both" || run_mode == "strict" {
    modes.push("strict")
  }
  modes
}

///|
fn modes_for_metadata_flags(
  flags : Array[String],
  run_mode : String,
) -> Array[String] {
  if flags.any(flag => flag == "raw") || flags.any(flag => flag == "module") {
    if run_mode != "strict" {
      ["non-strict"]
    } else {
      []
    }
  } else if flags.any(flag => flag == "onlyStrict") {
    if run_mode != "non-strict" {
      ["strict"]
    } else {
      []
    }
  } else if flags.any(flag => flag == "noStrict") {
    if run_mode != "strict" {
      ["non-strict"]
    } else {
      []
    }
  } else {
    default_modes_for_run_mode(run_mode)
  }
}

///|
fn metadata_flags_for_test(test_file : String) -> Array[String] raise {
  let source = @fs.read_file_to_string(test_file)
  match @utils.parse_yaml_frontmatter(source) {
    None => []
    Some(data) => json_list_field(data, "flags")
  }
}

///|
fn build_test_tasks(
  test_files : Array[String],
  run_mode : String,
) -> Array[(String, String)] {
  let test_tasks : Array[(String, String)] = []
  for test_file in test_files {
    let flags_result = try? metadata_flags_for_test(test_file)
    let modes = match flags_result {
      Ok(flags) => modes_for_metadata_flags(flags, run_mode)
      Err(_) => default_modes_for_run_mode(run_mode)
    }
    for mode in modes {
      test_tasks.push((test_file, mode))
    }
  }
  test_tasks
}

///|
fn apply_task_selection(
  test_tasks : Array[(String, String)],
  shard_spec? : (Int, Int)? = None,
  start? : Int = 0,
  count? : Int? = None,
  resume_from? : String = "",
  test262_dir? : String = "",
) -> (Array[(String, String)], Array[String]) raise {
  let mut selected_tasks = test_tasks
  let messages : Array[String] = []
  match shard_spec {
    Some((shard_index, shard_total)) => {
      let (slice_start, slice_end) = shard_bounds(
        selected_tasks.length(),
        shard_index,
        shard_total,
      )
      let before_count = selected_tasks.length()
      selected_tasks = shard_tasks(selected_tasks, shard_index, shard_total)
      messages.push(
        "Selected shard \{shard_index}/\{shard_total}: tasks \{slice_start}:\{slice_end} (\{selected_tasks.length()}/\{before_count})",
      )
    }
    None =>
      if start != 0 || count is Some(_) {
        let before_count = selected_tasks.length()
        selected_tasks = slice_tasks(selected_tasks, start~, count~)
        let count_label = match count {
          Some(value) => value.to_string()
          None => "remaining"
        }
        messages.push(
          "Selected task slice: start=\{start}, count=\{count_label} (\{selected_tasks.length()}/\{before_count})",
        )
      }
  }
  if resume_from != "" {
    let completed_keys = load_completed_task_keys(resume_from, test262_dir~)
    let before_count = selected_tasks.length()
    selected_tasks = filter_completed_tasks(
      selected_tasks,
      completed_keys,
      test262_dir~,
    )
    messages.push(
      "Resume: skipped \{before_count - selected_tasks.length()} completed task(s) from \{resume_from}",
    )
  }
  (selected_tasks, messages)
}

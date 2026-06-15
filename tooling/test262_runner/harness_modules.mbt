///|
fn load_harness_file(
  harness_dir : String,
  include_name : String,
  harness_options : HarnessOptions,
) -> String {
  let path = join_path(harness_dir, include_name)
  if is_readable_file(path) {
    let source = @fs.read_file_to_string(path) catch { _ => "" }
    harness_options.transform_include(include_name, source)
  } else {
    ""
  }
}

///|
fn load_harness(
  test262_dir : String,
  includes : Array[String],
  is_raw : Bool,
  is_async? : Bool = false,
  harness_options? : HarnessOptions = HarnessOptions(),
) -> String {
  guard !is_raw else { return "" }
  let harness_dir = join_path(test262_dir, "harness")
  let parts : Array[String] = [PRINT_PREAMBLE]
  let helper_source = harness_options.preamble()
  if helper_source != "" {
    parts.push(helper_source)
  }
  for default_file in ["sta.js", "assert.js"] {
    let source = load_harness_file(harness_dir, default_file, harness_options)
    if source != "" {
      parts.push(source)
    }
  }
  for inc in includes {
    let source = load_harness_file(harness_dir, inc, harness_options)
    if source != "" {
      parts.push(source)
    }
  }
  if is_async {
    parts.push(DONE_FALLBACK)
  }
  parts.join("\n")
}

///|
fn is_space_code(ch : UInt16) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

///|
fn collect_import_after_keyword(
  source : String,
  keyword : String,
  specs : Array[(Int, String)],
) -> Unit {
  let mut offset = 0
  let keyword_len = keyword.length()
  while offset < source.length() {
    match source[offset:].find(keyword) {
      None => return
      Some(relative_index) => {
        let index = offset + relative_index
        let mut j = index + keyword_len
        let mut had_space = false
        while j < source.length() && is_space_code(source[j]) {
          had_space = true
          j += 1
        }
        if had_space &&
          j < source.length() &&
          (source[j] == '"' || source[j] == '\'') {
          let quote = source[j]
          let spec_start = j + 1
          j += 1
          while j < source.length() && source[j] != quote {
            j += 1
          }
          if j < source.length() {
            let spec = source[spec_start:j].to_owned()
            if spec.has_prefix("./") || spec.has_prefix("../") {
              specs.push((index, spec))
            }
          }
        }
        offset = index + keyword_len
      }
    }
  }
}

///|
fn import_relative_specifiers(source : String) -> Array[String] {
  let matches : Array[(Int, String)] = []
  collect_import_after_keyword(source, "from", matches)
  collect_import_after_keyword(source, "import", matches)
  matches.sort_by(fn(a, b) { a.0.compare(b.0) })
  matches.map(item => item.1)
}

///|
fn visit_fixture(
  spec : String,
  importer_dir : String,
  test_abs : String,
  visited : Map[String, (String, String)],
  stack : @set.Set[String],
  order : Array[String],
) -> Unit raise {
  let abs_path = normalize_path(join_path(importer_dir, spec))
  guard abs_path != test_abs &&
    !visited.contains(abs_path) &&
    !stack.contains(abs_path) else {
    return
  }
  guard is_readable_file(abs_path) else { return }
  let fixture_src = @fs.read_file_to_string(abs_path) catch {
    err => fail("Failed to read fixture \{abs_path}: \{@debug.to_string(err)}")
  }
  stack.add(abs_path)
  for nested_spec in import_relative_specifiers(fixture_src) {
    visit_fixture(
      nested_spec,
      dirname(abs_path),
      test_abs,
      visited,
      stack,
      order,
    )
  }
  stack.remove(abs_path)
  visited[abs_path] = (spec, fixture_src)
  order.push(abs_path)
}

///|
fn resolve_fixtures(
  test_path : String,
  source : String,
) -> Array[(String, String)] raise {
  let test_abs = absolute_path(test_path)
  let test_dir = dirname(test_abs)
  let visited : Map[String, (String, String)] = {}
  let stack = @set.Set::default()
  let order : Array[String] = []
  for spec in import_relative_specifiers(source) {
    visit_fixture(spec, test_dir, test_abs, visited, stack, order)
  }
  order.map(path => visited[path])
}

///|
fn copy_args(args : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for arg in args {
    out.push(arg)
  }
  out
}

///|
fn append_engine_flags(
  engine_cmd : Array[String],
  test_path : String,
  source : String,
  is_module : Bool,
  is_annex_b : Bool,
) -> Array[String] raise {
  let cmd = copy_args(engine_cmd)
  if is_module {
    let main_specifier = "./" + basename(test_path)
    cmd.push("--module")
    cmd.push("--module-specifier")
    cmd.push(main_specifier)
    for fixture in resolve_fixtures(test_path, source) {
      cmd.push("--fixture")
      cmd.push(fixture.0)
      cmd.push(fixture.1)
    }
  }
  if is_annex_b {
    cmd.push("--annex-b")
  }
  cmd
}

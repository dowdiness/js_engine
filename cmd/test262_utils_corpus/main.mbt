///|
fn program_args(args : Array[String]) -> ArrayView[String] {
  if args.length() >= 1 {
    args[1:]
  } else {
    args[0:]
  }
}

///|
#borrow(message)
extern "c" fn stderr_write_bytes(message : Bytes) -> Unit = "moonbit_test262_utils_corpus_stderr_write"

///|
fn exit_with_error() -> Unit {
  @sys.exit(1)
}

///|
fn eprintln(line : String) -> Unit {
  stderr_write_bytes(@utf8.encode(line + "\n"))
}

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
fn resolve_test_dir(test262_root : String) -> String raise {
  let test_dir = join_path(test262_root, "test")
  guard @fs.path_exists(test_dir) && @fs.is_dir(test_dir) else {
    guard @fs.path_exists(test262_root) && @fs.is_dir(test262_root) else {
      fail("Test262 test directory not found under: \{test262_root}")
    }
    return test262_root
  }
  test_dir
}

///|
fn collect_js_files_in_dir(
  dir : String,
  rel_prefix : String,
  files : Array[String],
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
      files.push(rel_path)
    }
  }
}

///|
fn collect_js_files(test_dir : String) -> Array[String] raise {
  let files : Array[String] = []
  collect_js_files_in_dir(test_dir, "", files)
  files.sort()
  files
}

///|
fn parsed_frontmatter_to_json(value : Map[String, Json]?) -> Json {
  match value {
    Some(data) => Json::object(data)
    None => Json::null()
  }
}

///|
fn parsed_field(value : Map[String, Json]?, key : String) -> Json? {
  match value {
    Some(data) => data.get(key)
    None => None
  }
}

///|
fn parsed_list_field(value : Map[String, Json]?, key : String) -> Json {
  Json::array(@utils.as_list(parsed_field(value, key)))
}

///|
fn corpus_record(test_dir : String, rel_path : String) -> Json raise {
  let source = @fs.read_file_to_string(join_path(test_dir, rel_path))
  let parsed = @utils.parse_yaml_frontmatter(source)
  let record : Map[String, Json] = {
    "path": Json::string(rel_path),
    "frontmatter": parsed_frontmatter_to_json(parsed),
    "features": parsed_list_field(parsed, "features"),
    "flags": parsed_list_field(parsed, "flags"),
    "includes": parsed_list_field(parsed, "includes"),
  }
  Json::object(record)
}

///|
fn build_corpus_artifact(test262_root : String) -> Json raise {
  let test_dir = resolve_test_dir(test262_root)
  let records : Array[Json] = []
  for rel_path in collect_js_files(test_dir) {
    records.push(corpus_record(test_dir, rel_path))
  }
  let artifact : Map[String, Json] = {
    "schema_version": Json::number(1.0, repr="1"),
    "kind": Json::string("test262-utils-corpus"),
    "yaml_mode": Json::string("fallback"),
    "files": Json::array(records),
  }
  Json::object(artifact)
}

///|
fn main {
  let cmd = @argparse.Command(
    "test262-utils-corpus",
    options=[
      @argparse.OptionArg(
        "test262",
        default_values=["./test262"],
        about="Test262 checkout root, or its test directory (default: ./test262)",
      ),
      @argparse.OptionArg(
        "output",
        required=true,
        about="Path where the deterministic JSON artifact should be written",
      ),
    ],
    about="Emit the non-authoritative MoonBit shadow artifact for Test262 utility corpus parity.",
  )
  let matches = cmd.parse(argv=program_args(@env.args()), env={}) catch {
    err => {
      eprintln("\{err}")
      exit_with_error()
      return
    }
  }
  let test262_root = match matches.values.get("test262") {
    Some(values) if values.length() > 0 => values[0]
    _ => "./test262"
  }
  let output_path = match matches.values.get("output") {
    Some(values) if values.length() > 0 => values[0]
    _ => {
      eprintln("missing required --output")
      exit_with_error()
      return
    }
  }
  let artifact = build_corpus_artifact(test262_root) catch {
    err => {
      eprintln("Error: \{err}")
      exit_with_error()
      return
    }
  }
  @fs.write_string_to_file(output_path, artifact.stringify(indent=2) + "\n") catch {
    err => {
      eprintln("Error: \{to_repr(err)}")
      exit_with_error()
      return
    }
  }
}

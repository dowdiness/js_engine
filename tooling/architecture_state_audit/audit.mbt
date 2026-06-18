///|
fn scan_dirs() -> Array[String] {
  ["interpreter/runtime", "interpreter/stdlib"]
}

///|
fn mutable_type_constructors() -> Array[String] {
  ["Ref", "Map", "Array"]
}

///|
struct MutableBinding {
  key : String
  path : String
  line : Int
  name : String
  type_name : String
  is_public : Bool
  is_unannotated : Bool
} derive(Debug)

///|
fn is_identifier_start(ch : UInt16) -> Bool {
  (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_'
}

///|
fn is_identifier_part(ch : UInt16) -> Bool {
  is_identifier_start(ch) || (ch >= '0' && ch <= '9')
}

///|
fn is_type_token_part(ch : UInt16) -> Bool {
  is_identifier_part(ch) || ch == '@' || ch == '/' || ch == '-' || ch == '.'
}

///|
fn remove_ascii_whitespace(s : String) -> String {
  let out = StringBuilder()
  for ch in s {
    if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn last_segment(s : String) -> String {
  match s.rev_find(".") {
    Some(index) => s[index + 1:].to_owned()
    None => s
  }
}

///|
fn is_known_mutable_constructor(name : String) -> Bool {
  mutable_type_constructors().any(type_constructor => type_constructor == name)
}

///|
fn is_mutable_type(type_name : String) -> Bool {
  let normalized = remove_ascii_whitespace(type_name)
  let len = normalized.length()
  let mut i = 0
  while i < len {
    if normalized[i] == '[' {
      let mut start = i - 1
      while start >= 0 && is_type_token_part(normalized[start]) {
        start -= 1
      }
      let type_constructor = normalized[start + 1:i].to_owned()
      if type_constructor.length() > 0 &&
        is_known_mutable_constructor(last_segment(type_constructor)) {
        return true
      }
    }
    i += 1
  }
  false
}

///|
fn parse_module_let_start(line : String) -> (Bool, String, String)? {
  let len = line.length()
  let mut is_public = false
  let mut index = 0
  if line.has_prefix("let ") {
    index = 4
  } else if line.has_prefix("pub ") {
    is_public = true
    guard line[4:].has_prefix("let ") else { return None }
    index = 8
  } else if line.has_prefix("pub(") {
    guard line.find(")") is Some(close_index) else { return None }
    guard close_index + 1 < len && line[close_index + 1] == ' ' else {
      return None
    }
    index = close_index + 2
    guard line[index:].has_prefix("let ") else { return None }
    is_public = true
    index += 4
  } else {
    return None
  }

  guard index < len && is_identifier_start(line[index]) else { return None }
  let name_start = index
  while index < len && is_identifier_part(line[index]) {
    index += 1
  }
  Some((is_public, line[name_start:index].to_owned(), line[index:].to_owned()))
}

///|
fn parse_module_let(lines : Array[String], start : Int) -> MutableBinding? {
  guard start >= 0 && start < lines.length() else { return None }
  guard parse_module_let_start(lines[start]) is Some((is_public, name, rest)) else {
    return None
  }

  let mut declaration = rest
  let mut end = start
  while !declaration.contains("=") && end + 1 < lines.length() {
    end += 1
    declaration = declaration + "\n" + lines[end]
  }

  let before_initializer = match declaration.split_once("=") {
    Some((before, _)) => before.to_owned()
    None => declaration
  }
  let (type_name, is_unannotated) = match before_initializer.split_once(":") {
    Some((_, raw_type)) => (raw_type.trim().to_owned(), false)
    None => ("<unannotated>", true)
  }

  if !is_unannotated && !is_mutable_type(type_name) {
    return None
  }

  Some({
    key: "",
    path: "",
    line: start + 1,
    name,
    type_name,
    is_public,
    is_unannotated,
  })
}

///|

///|
fn source_lines(source : String) -> Array[String] {
  source.split("\n").map(line => line.to_owned()).to_array()
}

///|
fn discover_mutable_bindings(repo_root : String) -> Array[MutableBinding] raise {
  let bindings : Array[MutableBinding] = []
  for scan_dir in scan_dirs() {
    let root = @path_utils.join_path(repo_root, scan_dir)
    if @fs.path_exists(root) {
      let entries = @fs.read_dir(root)
      entries.sort()
      for entry in entries {
        if entry.has_suffix(".mbt") {
          let rel_path = @path_utils.join_path(scan_dir, entry)
          let full_path = @path_utils.join_path(repo_root, rel_path)
          if @fs.is_file(full_path) {
            let lines = source_lines(@fs.read_file_to_string(full_path))
            for index in 0..<lines.length() {
              match parse_module_let(lines, index) {
                Some(binding) =>
                  bindings.push({
                    key: rel_path + ":" + binding.name,
                    path: rel_path,
                    line: binding.line,
                    name: binding.name,
                    type_name: binding.type_name,
                    is_public: binding.is_public,
                    is_unannotated: binding.is_unannotated,
                  })
                None => ()
              }
            }
          }
        }
      }
    }
  }
  bindings
}

///|
fn load_classified_mutable_state(
  repo_root : String,
) -> Map[String, String] raise {
  let metadata_path = @path_utils.join_path(
    repo_root, "scripts/architecture_state_classified_mutable_state.json",
  )
  if !@fs.path_exists(metadata_path) {
    return {}
  }
  let json = @json.parse(@fs.read_file_to_string(metadata_path))
  @json.from_json(json)
}

///|
fn classified_reason(classified : Map[String, String], key : String) -> String? {
  classified.get(key)
}

///|
fn public_prefix(binding : MutableBinding) -> String {
  if binding.is_public {
    "pub "
  } else {
    ""
  }
}

///|
fn inventory_line(
  classified : Map[String, String],
  binding : MutableBinding,
) -> String {
  let reason = match classified_reason(classified, binding.key) {
    Some(reason) => reason
    None => "UNCLASSIFIED"
  }
  "\{binding.path}:\{binding.line}: \{public_prefix(binding)}\{binding.name}: \{binding.type_name} -- \{reason}"
}

///|
fn render_report(
  bindings : Array[MutableBinding],
  classified : Map[String, String],
  list~ : Bool,
) -> (Array[String], Array[String], Int) {
  let stdout_lines : Array[String] = []
  let stderr_lines : Array[String] = []
  if list {
    for binding in bindings {
      stdout_lines.push(inventory_line(classified, binding))
    }
  }

  let unannotated = bindings.filter(binding => binding.is_unannotated)
  let unclassified = bindings.filter(binding => {
    !binding.is_unannotated &&
    classified_reason(classified, binding.key) is None
  })
  let found = @set.Set::default()
  for binding in bindings {
    found.add(binding.key)
  }
  let stale : Array[String] = []
  for key, _reason in classified {
    if !found.contains(key) {
      stale.push(key)
    }
  }
  stale.sort()

  if unannotated.length() > 0 || unclassified.length() > 0 || stale.length() > 0 {
    stderr_lines.push("architecture state audit failed:")
    if unannotated.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("unannotated module-level let bindings:")
      for binding in unannotated {
        stderr_lines.push(
          "- \{binding.path}:\{binding.line}: \{public_prefix(binding)}\{binding.name}",
        )
      }
      stderr_lines.push(
        "  Use const for fixed values, or add an explicit type so mutable state cannot be hidden by inference.",
      )
    }
    if unclassified.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("unclassified module-level mutable state:")
      for binding in unclassified {
        stderr_lines.push(
          "- \{binding.path}:\{binding.line}: \{public_prefix(binding)}\{binding.name}: \{binding.type_name}",
        )
      }
    }
    if stale.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("stale classified entries:")
      for key in stale {
        stderr_lines.push("- \{key}")
      }
    }
    stderr_lines.push("")
    stderr_lines.push(
      "Classify intentionally retained state in CLASSIFIED_MUTABLE_STATE, or move it behind Interpreter/HostEnv/RealmState ownership.",
    )
    (stdout_lines, stderr_lines, 1)
  } else {
    stdout_lines.push(
      "ok: runtime/stdlib module-level mutable state matches the Stage 0 migration inventory (\{bindings.length()} classified bindings)",
    )
    (stdout_lines, stderr_lines, 0)
  }
}

///|
pub fn run(
  root~ : String,
  list~ : Bool,
) -> (Array[String], Array[String], Int) raise {
  let bindings = discover_mutable_bindings(root)
  let classified = load_classified_mutable_state(root)
  render_report(bindings, classified, list~)
}

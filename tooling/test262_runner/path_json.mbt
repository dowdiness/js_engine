///|
fn join_path(left : String, right : String) -> String {
  if right.has_prefix("/") {
    normalize_path(right)
  } else if left == "" || left == "." {
    normalize_path(right)
  } else if left.has_suffix("/") {
    normalize_path(left + right)
  } else {
    normalize_path(left + "/" + right)
  }
}

///|
fn normalize_path(path : String) -> String {
  let slash_path = path.replace_all(old="\\", new="/")
  let absolute = slash_path.has_prefix("/")
  let parts : Array[String] = []
  for raw in slash_path.split("/") {
    let part = raw.to_owned()
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 && parts[parts.length() - 1] != ".." {
        ignore(parts.pop())
      } else if !absolute {
        parts.push(part)
      }
    } else {
      parts.push(part)
    }
  }
  let joined = parts.join("/")
  if absolute {
    if joined == "" {
      "/"
    } else {
      "/" + joined
    }
  } else if joined == "" {
    "."
  } else {
    joined
  }
}

///|
fn current_dir_or_dot() -> String {
  match @env.current_dir() {
    Some(cwd) => normalize_path(cwd)
    None => "."
  }
}

///|
fn absolute_path(path : String) -> String {
  if path.has_prefix("/") {
    normalize_path(path)
  } else {
    normalize_path(join_path(current_dir_or_dot(), path))
  }
}

///|
fn path_components(path : String) -> Array[String] {
  let normalized = normalize_path(path)
  let trimmed = if normalized.has_prefix("/") {
    normalized[1:].to_owned()
  } else {
    normalized
  }
  if trimmed == "" || trimmed == "." {
    []
  } else {
    trimmed.split("/").map(part => part.to_owned()).to_array()
  }
}

///|
fn relative_path(path : String, start : String) -> String {
  let target_parts = path_components(absolute_path(path))
  let start_parts = path_components(absolute_path(start))
  let mut common = 0
  while common < target_parts.length() &&
        common < start_parts.length() &&
        target_parts[common] == start_parts[common] {
    common += 1
  }
  let out : Array[String] = []
  for _ in common..<start_parts.length() {
    out.push("..")
  }
  for i in common..<target_parts.length() {
    out.push(target_parts[i])
  }
  if out.length() == 0 {
    "."
  } else {
    out.join("/")
  }
}

///|
fn dirname(path : String) -> String {
  let normalized = normalize_path(path)
  match normalized.rev_find("/") {
    Some(0) => "/"
    Some(index) => normalized[:index].to_owned()
    None => "."
  }
}

///|
fn basename(path : String) -> String {
  let normalized = normalize_path(path)
  match normalized.rev_find("/") {
    Some(index) => normalized[index + 1:].to_owned()
    None => normalized
  }
}

///|
fn is_readable_dir(path : String) -> Bool {
  @fs.path_exists(path) && (@fs.is_dir(path) catch { _ => false })
}

///|
fn is_readable_file(path : String) -> Bool {
  @fs.path_exists(path) && (@fs.is_file(path) catch { _ => false })
}

///|
fn ensure_dir(path : String) -> Unit raise {
  if path == "" || path == "." || path == "/" {
    return
  }
  if @fs.path_exists(path) {
    return
  }
  ensure_dir(dirname(path))
  @fs.create_dir(path)
}

///|
fn ensure_parent_dir(path : String) -> Unit raise {
  let parent = dirname(path)
  if parent != "." && parent != "" {
    ensure_dir(parent)
  }
}

///|
fn json_to_string(value : Json) -> String {
  match value {
    Json::String(s) => s
    Json::Number(_, repr=Some(repr)) => repr
    Json::Number(n, repr=None) => n.to_string()
    Json::True => "True"
    Json::False => "False"
    Json::Null => "None"
    _ => value.stringify()
  }
}

///|
fn json_string_field(data : Map[String, Json], key : String) -> String {
  match data.get(key) {
    Some(value) => json_to_string(value)
    None => ""
  }
}

///|
fn json_list_field(data : Map[String, Json], key : String) -> Array[String] {
  let out : Array[String] = []
  for item in @utils.as_list(data.get(key)) {
    out.push(json_to_string(item))
  }
  out
}

///| 
/// Shared path helpers used across tooling packages.

///|
pub fn normalize_path(path : String) -> String {
  @path.Path::normalize(path).to_string().replace_all(old="\\", new="/")
}

///|
pub fn join_path(left : String, right : String) -> String {
  if left == "" || left == "." {
    normalize_path(right)
  } else {
    normalize_path(@path.Path::join(left, right).to_string())
  }
}

///|
pub fn current_dir_or_dot() -> String {
  normalize_path(@env.current_dir().unwrap_or("."))
}

///|
pub fn absolute_path(path : String) -> String {
  let normalized = normalize_path(path)
  if @path.Path::is_absolute(normalized) {
    normalized
  } else {
    join_path(current_dir_or_dot(), normalized)
  }
}

///|
pub fn parent_dir(path : String) -> String? {
  let dirname = @path.Path::dirname(normalize_path(path)).to_string()
  if dirname == "." || dirname == "" {
    None
  } else {
    Some(dirname.replace_all(old="\\", new="/"))
  }
}

///|
pub fn dirname(path : String) -> String {
  @path.Path::dirname(normalize_path(path))
  .to_string()
  .replace_all(old="\\", new="/")
}

///|
pub fn basename(path : String) -> String {
  @path.Path::basename(normalize_path(path)).to_owned()
}

///|
pub fn path_components(path : String) -> Array[String] {
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
pub fn relative_path(path : String, start : String) -> String {
  let start_abs = absolute_path(start)
  let path_abs = absolute_path(path)
  let rel = @path.Path::relative(path_abs, base=start_abs)
    .to_string()
    .replace_all(old="\\", new="/")
  if rel == "" {
    if path_abs == start_abs {
      "."
    } else {
      path
    }
  } else {
    rel
  }
}

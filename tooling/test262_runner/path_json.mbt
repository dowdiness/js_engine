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
  ensure_dir(@path_utils.dirname(path))
  @fs.create_dir(path)
}

///|
fn ensure_parent_dir(path : String) -> Unit raise {
  let parent = @path_utils.dirname(path)
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

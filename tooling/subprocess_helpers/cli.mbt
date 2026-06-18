///|
pub fn cli_error_message(err : Error) -> String {
  let text = "\{err}"
  match text.split_once("FAILED: ") {
    Some((_, rest)) => {
      let message = rest.to_owned()
      if message.has_suffix(")") {
        message[:message.length() - 1].to_owned()
      } else {
        message
      }
    }
    None => text
  }
}

///|
fn executable_dir(argv0 : String) -> String? {
  if argv0.contains("/") {
    @path_utils.parent_dir(@path_utils.absolute_path(argv0))
  } else {
    None
  }
}

///|
fn is_repo_root(dir : String) -> Bool {
  @fs.path_exists(@path_utils.join_path(dir, "moon.mod")) &&
  @fs.path_exists(@path_utils.join_path(dir, "scripts")) &&
  @fs.path_exists(@path_utils.join_path(dir, "lexer"))
}

///|
fn find_repo_root_from(start : String) -> String? {
  let mut dir = @path_utils.normalize_path(start)
  while true {
    if is_repo_root(dir) {
      return Some(dir)
    }
    match @path_utils.parent_dir(dir) {
      Some(parent) if parent != dir => dir = parent
      _ => return None
    }
  }
  None
}

///|
pub fn resolve_repo_root(argv0 : String) -> String {
  match executable_dir(argv0) {
    Some(dir) =>
      match find_repo_root_from(dir) {
        Some(root) => return root
        None => ()
      }
    None => ()
  }
  match find_repo_root_from(@path_utils.current_dir_or_dot()) {
    Some(root) => root
    None => @path_utils.current_dir_or_dot()
  }
}

///|
pub fn repo_default_path(argv0 : String, rel_path : String) -> String {
  @path_utils.join_path(resolve_repo_root(argv0), rel_path)
}

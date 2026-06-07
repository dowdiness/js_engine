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
fn strip_trailing_slashes(path : String) -> String {
  let mut end = path.length()
  while end > 1 && path[end - 1] == '/' {
    end -= 1
  }
  path[:end].to_owned()
}

///|
fn parent_dir(path : String) -> String? {
  let normalized = strip_trailing_slashes(path)
  match normalized.rev_find("/") {
    Some(0) => Some("/")
    Some(index) => Some(normalized[:index].to_owned())
    None => None
  }
}

///|
fn current_dir_or_dot() -> String {
  match @env.current_dir() {
    Some(cwd) => cwd
    None => "."
  }
}

///|
fn absolute_path(path : String) -> String {
  if path.has_prefix("/") {
    path
  } else {
    join_path(current_dir_or_dot(), path)
  }
}

///|
fn executable_dir(argv0 : String) -> String? {
  if argv0.contains("/") {
    parent_dir(absolute_path(argv0))
  } else {
    None
  }
}

///|
fn is_repo_root(dir : String) -> Bool {
  @fs.path_exists(join_path(dir, "moon.mod")) &&
  @fs.path_exists(join_path(dir, "scripts")) &&
  @fs.path_exists(join_path(dir, "lexer"))
}

///|
fn find_repo_root_from(start : String) -> String? {
  let mut dir = strip_trailing_slashes(start)
  while true {
    if is_repo_root(dir) {
      return Some(dir)
    }
    match parent_dir(dir) {
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
  match find_repo_root_from(current_dir_or_dot()) {
    Some(root) => root
    None => current_dir_or_dot()
  }
}

///|
pub fn repo_default_path(argv0 : String, rel_path : String) -> String {
  join_path(resolve_repo_root(argv0), rel_path)
}

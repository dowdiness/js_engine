///|
/// WASM target: args = ["program", ...]
fn parse_args(args : Array[String]) -> (Bool, String?) {
  if args.length() < 2 {
    return (false, None)
  }
  if args[1] == "--module" {
    if args.length() < 3 {
      (true, None)
    } else {
      (true, Some(args[2]))
    }
  } else {
    (false, Some(args[1]))
  }
}

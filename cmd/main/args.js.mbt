///| JS target: process.argv = ["node", "script.js", ...]
fn parse_args(args : Array[String]) -> (Bool, String?) {
  // JS target has 2 extra prefix args: ["node", "script.js", ...]
  if args.length() < 3 {
    return (false, None)
  }
  if args[2] == "--module" {
    if args.length() < 4 {
      (true, None)
    } else {
      (true, Some(args[3]))
    }
  } else {
    (false, Some(args[2]))
  }
}

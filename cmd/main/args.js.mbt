///| JS target: process.argv = ["node", "script.js", source, ...]
fn get_source_arg() -> String? {
  let args = @env.args()
  if args.length() < 3 {
    None
  } else {
    Some(args[2])
  }
}

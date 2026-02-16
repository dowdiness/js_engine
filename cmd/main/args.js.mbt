///|
/// JS target: process.argv = ["node", "script.js", ...]
fn parse_args(args : Array[String]) -> (Bool, Bool, String?) {
  // JS target has 2 extra prefix args: ["node", "script.js", ...]
  let mut is_module = false
  let mut annex_b = false
  let mut source : String? = None
  for i = 2; i < args.length(); i = i + 1 {
    if args[i] == "--module" {
      is_module = true
    } else if args[i] == "--annex-b" {
      annex_b = true
    } else if source is None {
      source = Some(args[i])
    }
  }
  (is_module, annex_b, source)
}

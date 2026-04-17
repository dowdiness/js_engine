///|
/// Exit the process with a non-zero exit code (JS target)
fn exit_with_error() -> Unit {
  js_process_exit(1)
}

///|
extern "js" fn js_process_exit(code : Int) -> Unit =
  #|(code) => { process.exit(code); }

///|
/// JS target: process.argv = ["node", "script.js", ...]
fn parse_args(
  args : Array[String],
) -> (Bool, Bool, Array[(String, String)], String?) {
  // JS target has 2 extra prefix args: ["node", "script.js", ...]
  let mut is_module = false
  let mut annex_b = false
  let fixtures : Array[(String, String)] = []
  let mut source : String? = None
  let mut i = 2
  while i < args.length() {
    if args[i] == "--module" {
      is_module = true
      i = i + 1
    } else if args[i] == "--annex-b" {
      annex_b = true
      i = i + 1
    } else if args[i] == "--fixture" && i + 2 < args.length() {
      // --fixture <specifier> <source>
      fixtures.push((args[i + 1], args[i + 2]))
      i = i + 3
    } else if source is None {
      source = Some(args[i])
      i = i + 1
    } else {
      i = i + 1
    }
  }
  (is_module, annex_b, fixtures, source)
}

///|
/// Exit the process with a non-zero exit code (JS target)
fn exit_with_error() -> Unit {
  js_process_exit(1)
}

///|
extern "js" fn js_process_exit(code : Int) -> Unit =
  #|(code) => { process.exit(code); }

///|
/// JS target: process.argv = ["node", "script.js", ...] — drop the first two.
fn program_args(args : Array[String]) -> ArrayView[String] {
  if args.length() >= 2 {
    args[2:]
  } else {
    args[args.length():]
  }
}

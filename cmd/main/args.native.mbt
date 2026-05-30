///|
/// Native target: args = ["program", ...] — drop the program name.
fn program_args(args : Array[String]) -> ArrayView[String] {
  if args.length() >= 1 {
    args[1:]
  } else {
    args[0:]
  }
}

///|
extern "c" fn native_exit(code : Int) -> Unit = "exit"

///|
/// Exit the process with a non-zero exit code (native target).
fn exit_with_error() -> Unit {
  native_exit(1)
}

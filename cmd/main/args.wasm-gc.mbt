///|
/// WASM-GC target: args = ["program", ...] — drop the program name.
fn program_args(args : Array[String]) -> ArrayView[String] {
  if args.length() >= 1 {
    args[1:]
  } else {
    args[0:]
  }
}

///|
/// Exit the process with a non-zero exit code (WASM-GC target)
fn exit_with_error() -> Unit {
  abort("exit_with_error")
}

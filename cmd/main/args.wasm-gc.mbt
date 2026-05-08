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
fn wasm_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
/// Exit the process with a non-zero exit code (WASM-GC target).
/// Uses the moonrun host exit FFI (same hook argparse uses for --help) so
/// callers see a clean exit code instead of a `RuntimeError: unreachable`
/// trap from `abort`.
fn exit_with_error() -> Unit {
  wasm_exit(1)
}

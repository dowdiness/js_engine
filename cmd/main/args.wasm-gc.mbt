///|
/// WASM-GC target: args = ["program", ...]
fn parse_args(
  args : Array[String],
) -> (Bool, Bool, Array[(String, String)], String?) {
  let mut is_module = false
  let mut annex_b = false
  let fixtures : Array[(String, String)] = []
  let mut source : String? = None
  let mut i = 1
  while i < args.length() {
    if args[i] == "--module" {
      is_module = true
      i = i + 1
    } else if args[i] == "--annex-b" {
      annex_b = true
      i = i + 1
    } else if args[i] == "--fixture" && i + 2 < args.length() {
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

///|
/// Exit the process with a non-zero exit code (WASM-GC target)
fn exit_with_error() -> Unit {
  // WASM-GC: no process.exit; use abort to signal error
  abort("exit_with_error")
}

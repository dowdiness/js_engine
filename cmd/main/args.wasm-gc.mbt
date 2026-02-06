///| WASM-GC target: args = ["program", source, ...]
fn get_source_arg() -> String? {
  let args = @env.args()
  if args.length() < 2 {
    None
  } else {
    Some(args[1])
  }
}

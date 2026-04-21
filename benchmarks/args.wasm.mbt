///|
pub struct BenchArgs {
  run_all : Bool
  csv : Bool
  list_only : Bool
}

///|
/// Parse CLI arguments for the WASM backend.
/// Args start at index 1 (no Node.js prefix).
///
/// Note: timing returns 0.0 on WASM (see timer.wasm.mbt).
/// Run with --target js for meaningful results.
pub fn parse_bench_args() -> BenchArgs {
  let args = @env.args()
  let mut run_all = false
  let mut csv = false
  let mut list_only = false
  for i = 1; i < args.length(); i = i + 1 {
    match args[i] {
      "--all" => run_all = true
      "--csv" => csv = true
      "--list" => list_only = true
      _ => ()
    }
  }
  { run_all, csv, list_only }
}

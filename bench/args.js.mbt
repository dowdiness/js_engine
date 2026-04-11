///|
/// Command-line argument record.
pub struct BenchArgs {
  /// Run all three categories (regression + component + workflow).
  /// Default: regression only.
  run_all : Bool
  /// Emit CSV rows (with header) instead of human-readable output.
  csv : Bool
  /// Print the list of available benchmarks and exit without running.
  list_only : Bool
}

///|
/// Parse CLI arguments for the JS backend.
/// Node.js prepends ["node", "<script>"] so user args start at index 2.
pub fn parse_bench_args() -> BenchArgs {
  let args = @env.args()
  let mut run_all = false
  let mut csv = false
  let mut list_only = false
  for i = 2; i < args.length(); i = i + 1 {
    match args[i] {
      "--all" => run_all = true
      "--csv" => csv = true
      "--list" => list_only = true
      _ => ()
    }
  }
  { run_all, csv, list_only }
}

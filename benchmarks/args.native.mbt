///|
pub struct BenchArgs {
  run_all : Bool
  csv : Bool
  list_only : Bool
}

///|
/// Parse CLI arguments for the native backend.
/// Args start at index 1 (the executable path is argv[0]).
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
      flag => {
        println("error: unknown benchmark flag: \{flag}")
        abort("unknown benchmark flag")
      }
    }
  }
  { run_all, csv, list_only }
}

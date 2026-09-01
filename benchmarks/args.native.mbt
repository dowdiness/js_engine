///|
/// Parse CLI arguments for the native backend.
/// Args start at index 1 (the executable path is argv[0]).
pub fn parse_bench_args() -> BenchArgs raise {
  parse_bench_arg_values(@env.args()[1:])
}

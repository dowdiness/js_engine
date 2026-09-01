///|
/// Parse CLI arguments for the JS backend.
/// Node.js prepends ["node", "<script>"] so user args start at index 2.
pub fn parse_bench_args() -> BenchArgs raise {
  parse_bench_arg_values(@env.args()[2:])
}

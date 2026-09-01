///|
/// Parse CLI arguments for the WASM backend.
/// Args start at index 1 (no Node.js prefix).
///
/// Note: timing returns 0.0 on WASM (see timer.wasm.mbt).
/// Run with --target js for meaningful results.
pub fn parse_bench_args() -> BenchArgs raise {
  parse_bench_arg_values(@env.args()[1:])
}

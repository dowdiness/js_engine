///|
/// Timer stub for the WASM target.
///
/// Accurate benchmarking requires the JS backend where `performance.now()`
/// is available. On this target all timing returns 0.0, making results
/// meaningless. Run benchmarks with:
///
///   moon run bench/main --target js
pub fn now_ms() -> Double {
  0.0
}

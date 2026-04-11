///|
/// Timer stub for the WASM-GC target.
///
/// Accurate benchmarking requires the JS backend where `performance.now()`
/// is available. On this target all timing returns 0.0, making results
/// meaningless. Run benchmarks with:
///
///   moon run bench/main --target js
pub fn now_ms() -> Double {
  0.0
}

///|
/// Returns false: timing is unsupported on WASM-GC. Use --target js.
pub fn timer_supported() -> Bool {
  false
}

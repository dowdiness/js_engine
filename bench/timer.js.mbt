///|
/// High-resolution monotonic timer for the JS backend.
///
/// Uses `performance.now()` which provides sub-millisecond precision.
/// Available in Node.js ≥ 10 (via the `perf_hooks` global) and all
/// modern browsers. The timer is monotonic, not wall-clock, so it is
/// unaffected by system time adjustments.
///
/// Precision: typically ≥ 0.1 µs on V8/Node.js in non-cross-origin
/// contexts. The Web spec allows coarser rounding; Node.js does not.
extern "js" fn _perf_now() -> Double =
  #|() => performance.now()

///|
/// Return the current time in milliseconds.
/// Use two calls bracketing a block to measure its duration.
pub fn now_ms() -> Double {
  _perf_now()
}

///|
/// Returns true: performance.now() is available on the JS target.
pub fn timer_supported() -> Bool {
  true
}

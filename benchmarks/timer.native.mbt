///|
/// Millisecond timer for the native backend.
///
/// Uses the core environment clock. This is wall-clock time, but sufficient for
/// the CLI benchmark runner on native builds.
pub fn now_ms() -> Double {
  @env.now().to_double()
}

///|
/// Returns true: a millisecond timer is available on the native target.
pub fn timer_supported() -> Bool {
  true
}

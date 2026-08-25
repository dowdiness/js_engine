///|
// Compatibility and differential-oracle fixtures opt out of the Bytecode
// default through this build-time virtual implementation.
pub fn candidate_mode_enabled() -> Bool {
  false
}

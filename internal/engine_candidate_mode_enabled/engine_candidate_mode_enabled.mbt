///|
// Candidate external-consumer fixtures replace the virtual default at build
// time; runtime code never reads a mutable environment switch.
pub fn candidate_mode_enabled() -> Bool {
  true
}

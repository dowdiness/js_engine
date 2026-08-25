///|
// The stable facade reads this build-time policy once at the Engine shell.
// Verified eligible activations use Bytecode; unsupported activations select
// the Tree-walker before they start.
pub fn candidate_mode_enabled() -> Bool {
  true
}

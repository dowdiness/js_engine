///|
// The stable facade reads this build-time policy once at the Engine shell.
// The default distribution intentionally retains the legacy Tree-walker path.
pub fn candidate_mode_enabled() -> Bool {
  false
}

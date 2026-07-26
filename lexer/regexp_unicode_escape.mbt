///|
/// Validate Unicode-mode escape syntax while a `/u` literal is still source text.
/// Constructor strings deliberately bypass this function and remain runtime
/// errors when RegExp construction is evaluated.
fn validate_regexp_literal_unicode_escapes(
  pattern : String,
  flags : String,
) -> Unit raise Error {
  guard flags.contains("u") else { return }
  @regexp_syntax.validate_unicode_mode_regexp_escapes(pattern.to_array())
}

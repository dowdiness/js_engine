///|
/// Validate Unicode escape syntax while a `/u` literal is still source text.
/// Constructor strings deliberately bypass this function and remain runtime
/// errors when RegExp construction is evaluated.
fn validate_regexp_literal_unicode_escapes(
  pattern : String,
  flags : String,
) -> Unit raise Error {
  guard flags.contains("u") else { return }
  let chars = pattern.to_array()
  let mut position = 0
  while position < chars.length() {
    if chars[position] == '\\' && position + 1 < chars.length() {
      if chars[position + 1] == 'u' {
        let (_, next) = @regexp_syntax.parse_unicode_escape(chars, position + 2)
        position = next
      } else {
        // The escaped character cannot start a second escape sequence.
        position += 2
      }
    } else {
      position += 1
    }
  }
}

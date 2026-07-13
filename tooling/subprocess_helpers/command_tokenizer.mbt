///|
/// Tokenize a command string into argv words without invoking a shell.
///
/// Contract:
/// 1. Spaces, tabs, and newlines separate unquoted words.
/// 2. Empty quoted segments (`''`, `""`) contribute nothing; adjacent quoted and
///    unquoted segments concatenate into one word.
/// 3. Inside single quotes, every character is literal (backslashes included).
/// 4. Inside double quotes, backslash escapes only `"`, `\`, `$`, backtick, and
///    newline; other backslashes are preserved literally.
/// 5. Outside quotes, backslash escapes the next character when present.
/// 6. A trailing backslash with no following character is kept literally.
/// 7. Unclosed quotes raise a catchable failure (`No closing quotation`).
/// 8. No shell expansion: variables, globs, command substitution, redirection,
///    and pipelines are not interpreted.
pub fn tokenize_command(command : String) -> Array[String] raise {
  let args : Array[String] = []
  let buf = StringBuilder()
  let chars = command.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut token_started = false
  while i < chars.length() {
    let ch = chars[i]
    match quote {
      Some(q) =>
        if ch == q {
          quote = None
          token_started = true
        } else if q == '"' && ch == '\\' && i + 1 < chars.length() {
          let next = chars[i + 1]
          if next == '"' ||
            next == '\\' ||
            next == '$' ||
            next == '`' ||
            next == '\n' {
            buf.write_char(next)
            i += 1
          } else {
            buf.write_char(ch)
          }
        } else {
          buf.write_char(ch)
        }
      None =>
        if ch == ' ' || ch == '\t' || ch == '\n' {
          if token_started || !buf.is_empty() {
            args.push(buf.to_string())
            buf.reset()
            token_started = false
          }
        } else if ch == '\'' || ch == '"' {
          quote = Some(ch)
          token_started = true
        } else if ch == '\\' {
          if i + 1 < chars.length() {
            i += 1
            buf.write_char(chars[i])
            token_started = true
          } else {
            buf.write_char(ch)
            token_started = true
          }
        } else {
          buf.write_char(ch)
          token_started = true
        }
    }
    i += 1
  }
  if quote is Some(_) {
    fail("No closing quotation")
  }
  if token_started || !buf.is_empty() {
    args.push(buf.to_string())
  }
  args
}

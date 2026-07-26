///|
fn regexp_hex_digit_value(char : Char) -> Int {
  if char >= '0' && char <= '9' {
    char.to_int() - '0'.to_int()
  } else if char >= 'a' && char <= 'f' {
    char.to_int() - 'a'.to_int() + 10
  } else if char >= 'A' && char <= 'F' {
    char.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn is_regexp_hex_digit(char : Char) -> Bool {
  regexp_hex_digit_value(char) >= 0
}

///|
/// Whether `start` begins an exactly four-digit Unicode escape payload.
pub fn regexp_has_fixed_unicode_escape(
  pattern : Array[Char],
  start : Int,
) -> Bool {
  guard start >= 0 && start + 3 < pattern.length() else { return false }
  for index in start..<(start + 4) {
    if !is_regexp_hex_digit(pattern[index]) {
      return false
    }
  }
  true
}

///|
/// Decode one RegExp Unicode escape payload beginning immediately after `\\u`.
///
/// This is a deterministic syntax-core operation shared by literal early-error
/// validation and runtime RegExp construction. The returned index points to the
/// first unconsumed pattern character.
pub fn parse_regexp_unicode_escape(
  pattern : Array[Char],
  start : Int,
  allow_braced? : Bool = true,
  combine_surrogate_pair? : Bool = true,
) -> (Char, Int) raise Error {
  guard start >= 0 else {
    raise @errors.SyntaxError(message="Invalid regex: invalid Unicode escape")
  }
  if allow_braced && start < pattern.length() && pattern[start] == '{' {
    let mut position = start + 1
    let mut code_point = 0
    let mut digit_count = 0
    while position < pattern.length() && is_regexp_hex_digit(pattern[position]) {
      // Keep consuming after an overflow is certain without multiplying again.
      // This accepts arbitrary leading zeroes without risking Int overflow.
      if code_point <= 0x10FFFF {
        code_point = code_point * 16 + regexp_hex_digit_value(pattern[position])
      }
      position += 1
      digit_count += 1
    }
    if digit_count == 0 ||
      position >= pattern.length() ||
      pattern[position] != '}' {
      raise @errors.SyntaxError(message="Invalid regex: invalid Unicode escape")
    }
    if code_point > 0x10FFFF {
      raise @errors.SyntaxError(
        message="Invalid regex: Unicode code point out of range",
      )
    }
    (code_point.unsafe_to_char(), position + 1)
  } else {
    guard regexp_has_fixed_unicode_escape(pattern, start) else {
      raise @errors.SyntaxError(message="Invalid regex: invalid Unicode escape")
    }
    let mut code_point = 0
    for index in start..<(start + 4) {
      code_point = code_point * 16 + regexp_hex_digit_value(pattern[index])
    }
    let next = start + 4
    if combine_surrogate_pair &&
      code_point >= 0xD800 &&
      code_point <= 0xDBFF &&
      next + 5 < pattern.length() &&
      pattern[next] == '\\' &&
      pattern[next + 1] == 'u' &&
      regexp_has_fixed_unicode_escape(pattern, next + 2) {
      let mut low = 0
      for index in (next + 2)..<(next + 6) {
        low = low * 16 + regexp_hex_digit_value(pattern[index])
      }
      if low >= 0xDC00 && low <= 0xDFFF {
        let combined = (code_point - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000
        return (combined.unsafe_to_char(), next + 6)
      }
    }
    (code_point.unsafe_to_char(), next)
  }
}

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
        let (_, next) = parse_regexp_unicode_escape(chars, position + 2)
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

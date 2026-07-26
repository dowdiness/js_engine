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
fn is_regexp_decimal_digit(char : Char) -> Bool {
  char >= '0' && char <= '9'
}

///|
fn is_regexp_ascii_letter(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
}

///|
fn is_regexp_syntax_character(char : Char) -> Bool {
  match char {
    '^'
    | '$'
    | '\\'
    | '.'
    | '*'
    | '+'
    | '?'
    | '('
    | ')'
    | '['
    | ']'
    | '{'
    | '}'
    | '|' => true
    _ => false
  }
}

///|
fn unicode_mode_capturing_group_count(pattern : Array[Char]) -> Int {
  let mut count = 0
  let mut position = 0
  let mut in_character_class = false
  while position < pattern.length() {
    let char = pattern[position]
    if char == '\\' {
      // An escaped character cannot affect group or character-class structure.
      position += 2
      continue
    }
    if in_character_class {
      if char == ']' {
        in_character_class = false
      }
      position += 1
      continue
    }
    if char == '[' {
      in_character_class = true
    } else if char == '(' {
      if position + 1 >= pattern.length() || pattern[position + 1] != '?' {
        count += 1
      } else if position + 3 < pattern.length() &&
        pattern[position + 2] == '<' &&
        pattern[position + 3] != '=' &&
        pattern[position + 3] != '!' {
        count += 1
      }
    }
    position += 1
  }
  count
}

///|
/// Parse a Unicode-mode DecimalEscape beginning at its first non-zero digit.
/// The returned index points to the first unconsumed pattern character.
pub fn parse_unicode_mode_decimal_escape(
  pattern : Array[Char],
  start : Int,
) -> (Int, Int) raise Error {
  guard start >= 0 &&
    start < pattern.length() &&
    pattern[start] >= '1' &&
    pattern[start] <= '9' else {
    raise @errors.SyntaxError(
      message="Invalid regex: invalid numeric backreference in Unicode mode",
    )
  }
  let mut position = start
  let mut value = 0
  let largest_meaningful_value = pattern.length()
  while position < pattern.length() &&
        is_regexp_decimal_digit(pattern[position]) {
    let digit = pattern[position].to_int() - '0'.to_int()
    // A pattern cannot contain as many captures as code points. Once the
    // decimal value reaches that bound, its exact value is irrelevant and
    // keeping it capped avoids integer overflow while consuming all digits.
    if value < largest_meaningful_value {
      if value > largest_meaningful_value / 10 ||
        (
          value == largest_meaningful_value / 10 &&
          digit > largest_meaningful_value % 10
        ) {
        value = largest_meaningful_value
      } else {
        value = value * 10 + digit
      }
    }
    position += 1
  }
  (value, position)
}

///|
fn validate_unicode_mode_escape(
  pattern : Array[Char],
  start : Int,
  in_character_class : Bool,
  capturing_group_count : Int,
) -> Int raise Error {
  guard start < pattern.length() else {
    raise @errors.SyntaxError(message="Invalid regex: trailing backslash")
  }
  let escaped = pattern[start]
  let next = start + 1
  match escaped {
    'd' | 'D' | 's' | 'S' | 'w' | 'W' => next
    'b' => next
    'B' =>
      if in_character_class {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid character class escape in Unicode mode",
        )
      } else {
        next
      }
    '1'..='9' =>
      if in_character_class {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid decimal escape in character class",
        )
      } else {
        let (value, position) = parse_unicode_mode_decimal_escape(
          pattern, start,
        )
        guard value <= capturing_group_count else {
          raise @errors.SyntaxError(
            message="Invalid regex: invalid numeric backreference in Unicode mode",
          )
        }
        position
      }
    'k' => {
      guard !in_character_class &&
        next < pattern.length() &&
        pattern[next] == '<' else {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid named backreference in Unicode mode",
        )
      }
      next
    }
    'p' | 'P' =>
      raise @errors.SyntaxError(
        message="Invalid regex: Unicode property escapes are not supported",
      )
    _ => {
      let (_, position) = parse_unicode_mode_character_escape(
        pattern,
        start,
        in_character_class~,
      )
      position
    }
  }
}

///|
fn validate_unicode_mode_character_class(
  pattern : Array[Char],
  start : Int,
  capturing_group_count : Int,
) -> Int raise Error {
  let mut position = start
  if position < pattern.length() && pattern[position] == '^' {
    position += 1
  }
  while position < pattern.length() && pattern[position] != ']' {
    let mut start_is_character_class_escape = false
    if pattern[position] == '\\' {
      guard position + 1 < pattern.length() else {
        raise @errors.SyntaxError(
          message="Invalid regex: unterminated character class escape",
        )
      }
      start_is_character_class_escape = match pattern[position + 1] {
        'd' | 'D' | 's' | 'S' | 'w' | 'W' => true
        _ => false
      }
      position = validate_unicode_mode_escape(
        pattern,
        position + 1,
        true,
        capturing_group_count,
      )
    } else {
      position += 1
    }
    if position < pattern.length() &&
      pattern[position] == '-' &&
      position + 1 < pattern.length() &&
      pattern[position + 1] != ']' {
      guard !start_is_character_class_escape else {
        raise @errors.SyntaxError(
          message="Invalid regex: character class escape cannot start a range in Unicode mode",
        )
      }
      position += 1
      if pattern[position] == '\\' {
        guard position + 1 < pattern.length() else {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated character class range",
          )
        }
        let end_is_character_class_escape = match pattern[position + 1] {
          'd' | 'D' | 's' | 'S' | 'w' | 'W' => true
          _ => false
        }
        guard !end_is_character_class_escape else {
          raise @errors.SyntaxError(
            message="Invalid regex: character class escape cannot end a range in Unicode mode",
          )
        }
        position = validate_unicode_mode_escape(
          pattern,
          position + 1,
          true,
          capturing_group_count,
        )
      } else {
        position += 1
      }
    }
  }
  guard position < pattern.length() && pattern[position] == ']' else {
    raise @errors.SyntaxError(
      message="Invalid regex: unterminated character class",
    )
  }
  position + 1
}

///|
/// Validate every escape in a Unicode-mode RegExp pattern.
///
/// This pure grammar pass is shared by RegExp literals and the RegExp
/// constructor so both entry points accept the same escape language while
/// retaining their respective parse-time and evaluation-time error phases.
pub fn validate_unicode_mode_regexp_escapes(
  pattern : Array[Char],
) -> Unit raise Error {
  let capturing_group_count = unicode_mode_capturing_group_count(pattern)
  let mut position = 0
  while position < pattern.length() {
    let char = pattern[position]
    if char == '\\' {
      position = validate_unicode_mode_escape(
        pattern,
        position + 1,
        false,
        capturing_group_count,
      )
      continue
    }
    if char == '[' {
      position = validate_unicode_mode_character_class(
        pattern,
        position + 1,
        capturing_group_count,
      )
      continue
    }
    position += 1
  }
}

///|
/// Whether `start` begins an exactly four-digit Unicode escape payload.
pub fn has_fixed_unicode_escape(pattern : Array[Char], start : Int) -> Bool {
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
/// The returned index points to the first unconsumed pattern character.
pub fn parse_unicode_escape(
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
    guard has_fixed_unicode_escape(pattern, start) else {
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
      has_fixed_unicode_escape(pattern, next + 2) {
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
/// Decode one Unicode-mode `CharacterEscape`, starting at the character after
/// the backslash. Character-class-only `\b` and `\-` forms are enabled by the
/// context flag; assertions and CharacterClassEscape forms stay with callers.
pub fn parse_unicode_mode_character_escape(
  pattern : Array[Char],
  start : Int,
  in_character_class? : Bool = false,
) -> (Char, Int) raise Error {
  guard start >= 0 && start < pattern.length() else {
    raise @errors.SyntaxError(message="Invalid regex: trailing backslash")
  }
  let escaped = pattern[start]
  let next = start + 1
  match escaped {
    'f' => ('\u{000C}', next)
    'n' => ('\n', next)
    'r' => ('\r', next)
    't' => ('\t', next)
    'v' => ('\u{000B}', next)
    'b' if in_character_class => ('\u{0008}', next)
    'c' => {
      guard next < pattern.length() && is_regexp_ascii_letter(pattern[next]) else {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid control escape in Unicode mode",
        )
      }
      ((pattern[next].to_int() % 32).unsafe_to_char(), next + 1)
    }
    '0' => {
      guard next >= pattern.length() || !is_regexp_decimal_digit(pattern[next]) else {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid decimal escape in Unicode mode",
        )
      }
      ('\u{0000}', next)
    }
    'x' => {
      guard next + 1 < pattern.length() &&
        is_regexp_hex_digit(pattern[next]) &&
        is_regexp_hex_digit(pattern[next + 1]) else {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid hexadecimal escape in Unicode mode",
        )
      }
      let value = regexp_hex_digit_value(pattern[next]) * 16 +
        regexp_hex_digit_value(pattern[next + 1])
      (value.unsafe_to_char(), next + 2)
    }
    'u' => parse_unicode_escape(pattern, next)
    _ => {
      guard is_regexp_syntax_character(escaped) ||
        escaped == '/' ||
        (in_character_class && escaped == '-') else {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid identity escape in Unicode mode",
        )
      }
      (escaped, next)
    }
  }
}

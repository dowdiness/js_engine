///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_hex_digit(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn parse_hex(s : String) -> Double {
  let chars = s.to_array()
  let mut result = 0.0
  for c in chars {
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - 48
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 87
    } else {
      c.to_int() - 55
    }
    result = result * 16.0 + digit.to_double()
  }
  result
}

///|
fn parse_radix_literal(s : String, base : Double) -> Double {
  let chars = s.to_array()
  let mut result = 0.0
  for c in chars {
    result = result * base + (c.to_int() - 48).to_double()
  }
  result
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$'
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
fn is_js_whitespace(c : Char) -> Bool {
  // NOTE: \r (0x0D) is a LineTerminator, NOT whitespace — handled separately
  let cp = c.to_int()
  cp == 0x20 ||
  cp == 0x09 ||
  cp == 0x0B ||
  cp == 0x0C ||
  is_unicode_space_cp(cp)
}

///|
fn is_unicode_space_cp(cp : Int) -> Bool {
  cp == 0x00A0 || // No-Break Space
  cp == 0xFEFF || // Zero Width No-Break Space (BOM)
  cp == 0x1680 || // OGHAM SPACE MARK
  (cp >= 0x2000 && cp <= 0x200A) || // EN QUAD through HAIR SPACE
  cp == 0x202F || // NARROW NO-BREAK SPACE
  cp == 0x205F || // MEDIUM MATHEMATICAL SPACE
  cp == 0x3000 // IDEOGRAPHIC SPACE
}

///|
/// ECMAScript LineTerminator check: \n, \r, U+2028, U+2029
fn is_line_terminator(c : Char) -> Bool {
  let cp = c.to_int()
  c == '\n' || c == '\r' || cp == 0x2028 || cp == 0x2029
}

///|
fn is_id_start_cp(cp : Int) -> Bool {
  // ES262 §11.6 IdentifierStartChar = UnicodeIDStart | $ | _.
  // ASCII fast path covers letters + `$` + `_`; non-ASCII delegates to the
  // generated `ID_Start` table (Unicode 17.0, see lexer/unicode_id.mbt).
  if cp < 128 {
    is_alpha(cp.unsafe_to_char())
  } else {
    is_id_start(cp)
  }
}

///|
fn is_id_continue_cp(cp : Int) -> Bool {
  // ES262 §11.6 IdentifierPartChar = UnicodeIDContinue | $ | <ZWNJ> | <ZWJ>.
  // ZWNJ (U+200C) and ZWJ (U+200D) are themselves in `ID_Continue`, so the
  // generated table covers them directly.
  if cp < 128 {
    is_alnum(cp.unsafe_to_char())
  } else {
    is_id_continue(cp)
  }
}

///|
fn write_code_point(buf : StringBuilder, cp : Int) -> Unit {
  if cp <= 0xFFFF {
    buf.write_char(cp.unsafe_to_char())
  } else {
    // Supplementary plane: encode as UTF-16 surrogate pair.
    // Use unsafe_to_char because surrogates are not valid Unicode scalar values
    // and Char::from_int rejects them.
    let cp2 = cp - 0x10000
    let high = 0xD800 + (cp2 >> 10)
    let low = 0xDC00 + (cp2 & 0x3FF)
    buf.write_char(high.unsafe_to_char())
    buf.write_char(low.unsafe_to_char())
  }
}

///|
fn resolve_keyword(s : String) -> @token.TokenKind {
  match s {
    "let" => Let
    "const" => Const
    "var" => Var
    "function" => Function
    "return" => Return
    "if" => If
    "else" => Else
    "while" => While
    "for" => For
    "break" => Break
    "continue" => Continue
    "true" => True
    "false" => False
    "null" => Null
    "undefined" => Undefined
    "typeof" => Typeof
    "throw" => Throw
    "try" => Try
    "catch" => Catch
    "finally" => Finally
    "new" => New
    "this" => This
    "switch" => Switch
    "case" => Case
    "default" => Default
    "void" => Void
    "delete" => Delete
    "do" => Do
    "in" => In
    "instanceof" => Instanceof
    "of" => Of
    "class" => Class
    "extends" => Extends
    "super" => Super
    "static" => Static
    "get" => Get
    "set" => Set
    "import" => Import
    "export" => Export
    "from" => From
    "as" => As
    "yield" => Yield
    _ => Ident(s)
  }
}

///|
pub fn tokenize(source : String) -> Array[@token.Token] raise Error {
  let tokens : Array[@token.Token] = []
  let mut line = 1
  let mut col = 1
  let mut offset = 0
  let chars = source.to_array()
  let len = chars.length()
  let template_depth_stack : Array[Int] = []
  // Track whether each open paren was preceded by a control-flow keyword
  // (if/while/for/switch/with). When the matching ) is emitted, it should
  // trigger regex context (a / after it starts a regex, not division).
  let paren_is_control_flow : Array[Bool] = []
  let mut last_rparen_is_control_flow = false
  fn make_loc() -> @token.Loc {
    { line, col, offset }
  }

  fn char_at(i : Int) -> Char {
    chars[i]
  }

  // Parse unicode escape after \u has been consumed.
  // offset should point at '{' or first hex digit.
  // Returns the code point as Int.
  fn parse_unicode_escape() -> Int raise Error {
    if offset < len && char_at(offset) == '{' {
      // \u{XXXXX} extended form
      offset += 1
      col += 1
      let hex_buf = StringBuilder::new()
      while offset < len && is_hex_digit(char_at(offset)) {
        hex_buf.write_char(char_at(offset))
        offset += 1
        col += 1
      }
      let hex_str = hex_buf.to_string()
      if hex_str.length() == 0 || hex_str.length() > 6 {
        raise @errors.SyntaxError(
          message="Invalid Unicode escape sequence at line \{line}, col \{col}",
        )
      }
      if offset >= len || char_at(offset) != '}' {
        raise @errors.SyntaxError(
          message="Invalid Unicode escape sequence at line \{line}, col \{col}",
        )
      }
      offset += 1 // skip }
      col += 1
      let cp = parse_hex(hex_str).to_int()
      if cp > 0x10FFFF {
        raise @errors.SyntaxError(
          message="Undefined Unicode code-point at line \{line}, col \{col}",
        )
      }
      cp
    } else {
      // \uXXXX - exactly 4 hex digits
      let hex_buf = StringBuilder::new()
      let mut count = 0
      while count < 4 {
        if offset >= len || !is_hex_digit(char_at(offset)) {
          raise @errors.SyntaxError(
            message="Invalid Unicode escape sequence at line \{line}, col \{col}",
          )
        }
        hex_buf.write_char(char_at(offset))
        offset += 1
        col += 1
        count += 1
      }
      parse_hex(hex_buf.to_string()).to_int()
    }
  }

  // Scan a contiguous run of digits matched by `is_valid`, writing each to `buf`.
  // Supports numeric separators (_) between digits per ES2021.
  // Raises SyntaxError for consecutive or trailing separators, or for an empty run.
  fn scan_digit_seq(
    is_valid : (Char) -> Bool,
    missing_msg : String,
    buf : StringBuilder,
  ) -> Unit raise Error {
    let mut has_digits = false
    let mut prev_underscore = true // prevents a leading underscore
    while offset < len {
      let ch = char_at(offset)
      if is_valid(ch) {
        buf.write_char(ch)
        offset += 1
        col += 1
        has_digits = true
        prev_underscore = false
      } else if ch == '_' {
        if prev_underscore {
          raise @errors.SyntaxError(
            message="Numeric separator cannot appear consecutively at line \{line}, col \{col}",
          )
        }
        prev_underscore = true
        offset += 1
        col += 1
      } else {
        break
      }
    }
    if !has_digits {
      raise @errors.SyntaxError(message=missing_msg)
    }
    if prev_underscore && buf.to_string().length() > 0 {
      raise @errors.SyntaxError(
        message="Numeric separator cannot appear at the end at line \{line}, col \{col - 1}",
      )
    }
  }

  fn scan_template_string() -> (String, Bool) raise Error {
    let buf = StringBuilder::new()
    while offset < len {
      let tc = char_at(offset)
      if tc == '`' {
        offset += 1
        col += 1
        return (buf.to_string(), false)
      }
      if tc == '$' && offset + 1 < len && char_at(offset + 1) == '{' {
        offset += 2
        col += 2
        return (buf.to_string(), true)
      }
      if tc == '\\' && offset + 1 < len {
        offset += 1
        col += 1
        let esc = char_at(offset)
        match esc {
          'n' => buf.write_char('\n')
          't' => buf.write_char('\t')
          'r' => buf.write_char('\r')
          'b' => write_code_point(buf, 8) // backspace
          'v' => write_code_point(buf, 11) // vertical tab
          'f' => write_code_point(buf, 12) // form feed
          '0' => {
            // \0 is NUL only when NOT followed by a decimal digit (ES spec)
            if offset + 1 < len && is_digit(char_at(offset + 1)) {
              raise @errors.SyntaxError(
                message="Invalid escape sequence at line \{line}, col \{col}",
              )
            }
            write_code_point(buf, 0)
          }
          '\\' => buf.write_char('\\')
          '`' => buf.write_char('`')
          '$' => buf.write_char('$')
          'x' => {
            // \xHH hex escape — parse exactly 2 hex digits
            offset += 1
            col += 1
            if offset + 1 < len &&
              is_hex_digit(char_at(offset)) &&
              is_hex_digit(char_at(offset + 1)) {
              let hex_str = String::make(1, char_at(offset)) +
                String::make(1, char_at(offset + 1))
              let cp = parse_hex(hex_str).to_int()
              buf.write_char(cp.unsafe_to_char())
              offset += 2
              col += 2
            } else {
              raise @errors.SyntaxError(
                message="Invalid hexadecimal escape sequence at line \{line}, col \{col}",
              )
            }
            continue
          }
          'u' => {
            offset += 1 // skip 'u'
            col += 1
            let cp = parse_unicode_escape()
            write_code_point(buf, cp)
            continue
          }
          // LineContinuation in template literal: \ followed by any LineTerminator
          _ if is_line_terminator(esc) => {
            if esc == '\r' {
              offset += 1
              if offset < len && char_at(offset) == '\n' {
                offset += 1
              }
            } else {
              offset += 1
            }
            line += 1
            col = 1
            continue
          }
          _ => {
            buf.write_char('\\')
            buf.write_char(esc)
          }
        }
        offset += 1
        col += 1
      } else {
        // Unescaped characters in template — \u2028/\u2029 are allowed (unlike strings)
        if is_line_terminator(tc) {
          // \r\n counts as one line terminator; normalize to \n in the value
          if tc == '\r' {
            if offset + 1 < len && char_at(offset + 1) == '\n' {
              offset += 1 // skip \r, \n will be written below
            }
            buf.write_char('\n')
          } else {
            buf.write_char(tc)
          }
          line += 1
          col = 1
        } else {
          col += 1
          buf.write_char(tc)
        }
        offset += 1
      }
    }
    raise @errors.SyntaxError(
      message="Unterminated template literal at line \{line}, col \{col}",
    )
  }

  while offset < len {
    let c = char_at(offset)
    // Skip whitespace
    if is_js_whitespace(c) {
      offset += 1
      col += 1
      continue
    }
    // ECMAScript LineTerminators: \n, \r, U+2028, U+2029
    if is_line_terminator(c) {
      offset += 1
      // \r\n is a single line terminator sequence
      if c == '\r' && offset < len && char_at(offset) == '\n' {
        offset += 1
      }
      line += 1
      col = 1
      continue
    }
    // Comments and regex literals
    if c == '/' && offset + 1 < len {
      let next = char_at(offset + 1)
      if next == '/' {
        // Single-line comment — terminates at any LineTerminator
        offset += 2
        col += 2
        while offset < len && !is_line_terminator(char_at(offset)) {
          offset += 1
          col += 1
        }
        continue
      }
      if next == '*' {
        // Multi-line comment — count all LineTerminators
        offset += 2
        col += 2
        while offset + 1 < len {
          if char_at(offset) == '*' && char_at(offset + 1) == '/' {
            offset += 2
            col += 2
            break
          }
          if is_line_terminator(char_at(offset)) {
            // \r\n counts as a single line terminator
            if char_at(offset) == '\r' &&
              offset + 1 < len &&
              char_at(offset + 1) == '\n' {
              offset += 1 // skip past \r, the loop increment skips \n
            }
            line += 1
            col = 1
          } else {
            col += 1
          }
          offset += 1
        }
        continue
      }
      // Check if / is a regex literal (context-dependent)
      if next != '=' {
        // Determine if this is a regex based on the last token
        let is_regex = if tokens.length() == 0 {
          true
        } else {
          let last_kind = tokens[tokens.length() - 1].kind
          match last_kind {
            // After these tokens, / starts a regex
            Assign
            | EqEq
            | EqEqEq
            | BangEq
            | BangEqEq
            | LParen
            | LBracket
            | LBrace
            | Comma
            | Semicolon
            | Colon
            | Question
            | QuestionQuestion
            | QuestionDot
            | And
            | Or
            | Bang
            | Plus
            | Minus
            | Star
            | StarStar
            | Slash
            | Percent
            | Lt
            | Gt
            | LtEq
            | GtEq
            | Return
            | Typeof
            | Throw
            | New
            | Delete
            | Void
            | In
            | Instanceof
            | PlusAssign
            | MinusAssign
            | StarAssign
            | StarStarAssign
            | SlashAssign
            | PercentAssign
            | BitAnd
            | BitOr
            | BitXor
            | Tilde
            | LShift
            | RShift
            | URShift
            | BitAndAssign
            | BitOrAssign
            | BitXorAssign
            | LShiftAssign
            | RShiftAssign
            | URShiftAssign
            | Case
            | Arrow
            | Yield => true
            // RParen after control-flow keyword (if/while/for/switch) starts regex
            RParen => last_rparen_is_control_flow
            _ => false
          }
        }
        if is_regex {
          let rloc = make_loc()
          offset += 1 // skip opening /
          col += 1
          let pattern_buf = StringBuilder::new()
          let mut in_class = false // inside [...]
          while offset < len {
            let rc = char_at(offset)
            if rc == '/' && !in_class {
              break
            }
            // Line terminators are not allowed in regex literals
            if is_line_terminator(rc) {
              raise @errors.SyntaxError(
                message="Unterminated regex literal at line \{rloc.line}, col \{rloc.col}",
              )
            }
            if rc == '[' {
              in_class = true
            }
            if rc == ']' {
              in_class = false
            }
            if rc == '\\' && offset + 1 < len {
              pattern_buf.write_char(rc)
              offset += 1
              col += 1
              pattern_buf.write_char(char_at(offset))
              offset += 1
              col += 1
              continue
            }
            pattern_buf.write_char(rc)
            offset += 1
            col += 1
          }
          if offset >= len {
            raise @errors.SyntaxError(
              message="Unterminated regex literal at line \{rloc.line}, col \{rloc.col}",
            )
          }
          offset += 1 // skip closing /
          col += 1
          // Read flags
          let flags_buf = StringBuilder::new()
          while offset < len && is_alpha(char_at(offset)) {
            flags_buf.write_char(char_at(offset))
            offset += 1
            col += 1
          }
          tokens.push({
            kind: Regex(pattern_buf.to_string(), flags_buf.to_string()),
            loc: rloc,
            raw: "",
            lex_form: LexNormal,
          })
          continue
        }
      }
    }
    let loc = make_loc()
    // Numbers (supports numeric separators, hex, binary, octal, exponent)
    if is_digit(c) {
      let start = offset
      let buf = StringBuilder::new()
      let mut is_non_octal_decimal_int = false
      // Check for hex (0x), binary (0b), octal (0o)
      if c == '0' && offset + 1 < len {
        let next = char_at(offset + 1)
        if next == 'x' || next == 'X' {
          // Hex number
          offset += 2
          col += 2
          scan_digit_seq(
            is_hex_digit,
            "Missing hex digits after '0x' at line \{loc.line}, col \{loc.col}",
            buf,
          )
          let hex_str = buf.to_string()
          let value = parse_hex(hex_str)
          // BigInt literal suffix support for compatibility paths where tests
          // use `0n` as a non-callable sentinel. We currently parse BigInt
          // numeric value as Number.
          if offset < len && char_at(offset) == 'n' {
            offset += 1
            col += 1
          }
          let raw = source.view()[start:offset].to_owned()
          tokens.push({ kind: Number(value), loc, raw, lex_form: LexNormal })
          continue
        } else if next == 'b' || next == 'B' {
          // Binary number
          offset += 2
          col += 2
          scan_digit_seq(
            fn(ch) { ch == '0' || ch == '1' },
            "Missing binary digits after '0b' at line \{loc.line}, col \{loc.col}",
            buf,
          )
          let bin_str = buf.to_string()
          let value = parse_radix_literal(bin_str, 2.0)
          if offset < len && char_at(offset) == 'n' {
            offset += 1
            col += 1
          }
          let raw = source.view()[start:offset].to_owned()
          tokens.push({ kind: Number(value), loc, raw, lex_form: LexNormal })
          continue
        } else if next == 'o' || next == 'O' {
          // Octal number
          offset += 2
          col += 2
          scan_digit_seq(
            fn(ch) { ch >= '0' && ch <= '7' },
            "Missing octal digits after '0o' at line \{loc.line}, col \{loc.col}",
            buf,
          )
          let oct_str = buf.to_string()
          let value = parse_radix_literal(oct_str, 8.0)
          if offset < len && char_at(offset) == 'n' {
            offset += 1
            col += 1
          }
          let raw = source.view()[start:offset].to_owned()
          tokens.push({ kind: Number(value), loc, raw, lex_form: LexNormal })
          continue
        } else if next == '8' || next == '9' {
          // 08 / 09 — NonOctalDecimalIntegerLiteral (Annex B)
          is_non_octal_decimal_int = true
        } else if next >= '0' && next <= '7' {
          // Legacy octal number (e.g. 070 = 56)
          // Only valid in non-strict mode, but we parse it and let the
          // interpreter/parser reject it in strict mode
          let mut is_legacy_octal = true
          // Peek ahead to check if all digits are octal
          let mut peek = offset + 1
          while peek < len {
            let pch = char_at(peek)
            if pch >= '0' && pch <= '7' {
              peek += 1
            } else if pch == '8' || pch == '9' {
              // Contains 8 or 9, not octal - treat as decimal (Annex B NonOctalDecimalIntegerLiteral)
              is_legacy_octal = false
              is_non_octal_decimal_int = true
              break
            } else {
              break
            }
          }
          if is_legacy_octal {
            offset += 1 // skip leading '0'
            col += 1
            while offset < len {
              let ch = char_at(offset)
              if ch >= '0' && ch <= '7' {
                buf.write_char(ch)
                offset += 1
                col += 1
              } else {
                break
              }
            }
            // Per ES262 §12.8.3 + Annex B §B.1.1, LegacyOctalIntegerLiteral
            // cannot extend into a fractional or exponent part — `01.2`,
            // `01e2`, `07.5` etc. match no production and are SyntaxErrors
            // in every mode (matches V8).
            //
            // The `.` case must distinguish fractional continuation from
            // member access: `01.toString()` is valid sloppy code (member
            // access on `Number(1)`), so we only reject `.<DecimalDigit>`.
            // `e`/`E` immediately after the digit is unambiguously the
            // exponent grammar entry, which legacy-octal cannot satisfy
            // (V8 errors on `01e2`, `01eFoo`, `01e` alike).
            if offset < len {
              let ch = char_at(offset)
              if ch == '.' && offset + 1 < len && is_digit(char_at(offset + 1)) {
                raise @errors.SyntaxError(
                  message="Invalid number literal at line \{loc.line}, col \{loc.col}: leading-zero octal-style integer cannot be followed by a fractional part",
                )
              } else if ch == 'e' || ch == 'E' {
                raise @errors.SyntaxError(
                  message="Invalid number literal at line \{loc.line}, col \{loc.col}: leading-zero octal-style integer cannot be followed by an exponent",
                )
              }
            }
            let oct_str = buf.to_string()
            let value = parse_radix_literal(oct_str, 8.0)
            if offset < len && char_at(offset) == 'n' {
              offset += 1
              col += 1
            }
            let raw = source.view()[start:offset].to_owned()
            tokens.push({
              kind: Number(value),
              loc,
              raw,
              lex_form: NumberLegacyOctalInt,
            })
            continue
          }
        }
      }
      // Decimal number with optional numeric separators
      let mut prev_underscore = true // Prevent leading underscore
      while offset < len {
        let ch = char_at(offset)
        if is_digit(ch) {
          buf.write_char(ch)
          offset += 1
          col += 1
          prev_underscore = false
        } else if ch == '_' {
          if prev_underscore {
            raise @errors.SyntaxError(
              message="Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
            )
          }
          prev_underscore = true
          offset += 1
          col += 1
        } else {
          break
        }
      }
      // Check for trailing underscore before decimal point
      if prev_underscore && buf.to_string().length() > 0 {
        // Peek if next is not a decimal point
        if offset >= len || char_at(offset) != '.' {
          raise @errors.SyntaxError(
            message="Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
          )
        }
      }
      // Decimal part
      if offset < len && char_at(offset) == '.' {
        // Trailing underscore before '.' is actually invalid
        if prev_underscore && buf.to_string().length() > 0 {
          raise @errors.SyntaxError(
            message="Numeric separator cannot appear before decimal point at line \{loc.line}, col \{col - 1}",
          )
        }
        // Per Annex B §B.1.1, NonOctalDecimalIntegerLiteral participates in
        // DecimalIntegerLiteral, so `08.1` parses but is forbidden in strict.
        // Keep the lex_form so the early-error walker rejects it under
        // "use strict" (matches V8).
        buf.write_char('.')
        offset += 1
        col += 1
        prev_underscore = true // Prevent underscore right after '.'
        while offset < len {
          let ch = char_at(offset)
          if is_digit(ch) {
            buf.write_char(ch)
            offset += 1
            col += 1
            prev_underscore = false
          } else if ch == '_' {
            if prev_underscore {
              raise @errors.SyntaxError(
                message="Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
              )
            }
            prev_underscore = true
            offset += 1
            col += 1
          } else {
            break
          }
        }
        // Check trailing underscore after decimal part
        // (but not if the last char is '.', which means no decimal digits yet - e.g. "0.e1")
        if prev_underscore {
          let num_str_so_far = buf.to_string()
          let last_is_dot = num_str_so_far.length() > 0 &&
            num_str_so_far.to_array()[num_str_so_far.length() - 1] == '.'
          if !last_is_dot {
            raise @errors.SyntaxError(
              message="Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
            )
          }
          // Reset prev_underscore since '.' is not actually a separator
          prev_underscore = false
        }
      }
      // Exponent part
      if offset < len && (char_at(offset) == 'e' || char_at(offset) == 'E') {
        // Check for trailing underscore before 'e'
        if prev_underscore && buf.to_string().length() > 0 {
          raise @errors.SyntaxError(
            message="Numeric separator cannot appear before exponent at line \{loc.line}, col \{col - 1}",
          )
        }
        // Annex B §B.1.1 again: `08e2` parses via DecimalLiteral but the
        // NonOctalDecimalIntegerLiteral integer part is a strict-mode early
        // error. Preserve the lex_form for the walker.
        buf.write_char('e')
        offset += 1
        col += 1
        if offset < len && (char_at(offset) == '+' || char_at(offset) == '-') {
          buf.write_char(char_at(offset))
          offset += 1
          col += 1
        }
        let mut has_exp_digits = false
        prev_underscore = true // Prevent underscore right after e/e+/e-
        while offset < len {
          let ch = char_at(offset)
          if is_digit(ch) {
            buf.write_char(ch)
            offset += 1
            col += 1
            has_exp_digits = true
            prev_underscore = false
          } else if ch == '_' {
            if prev_underscore {
              raise @errors.SyntaxError(
                message="Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
              )
            }
            prev_underscore = true
            offset += 1
            col += 1
          } else {
            break
          }
        }
        if !has_exp_digits {
          raise @errors.SyntaxError(
            message="Missing exponent digits at line \{loc.line}, col \{col}",
          )
        }
        if prev_underscore {
          raise @errors.SyntaxError(
            message="Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
          )
        }
      }
      let num_str = buf.to_string()
      if offset < len && char_at(offset) == 'n' {
        offset += 1
        col += 1
      }
      let raw = source.view()[start:offset].to_owned()
      let value = @string.parse_double(num_str)
      let lex_form : @token.LexForm = if is_non_octal_decimal_int {
        NumberNonOctalDecimalInt
      } else {
        LexNormal
      }
      tokens.push({ kind: Number(value), loc, raw, lex_form })
      continue
    }
    // Identifiers / Keywords (including \uXXXX and \u{XXXXX} escapes)
    if is_id_start_cp(c.to_int()) ||
      (c == '\\' && offset + 1 < len && char_at(offset + 1) == 'u') {
      let ident_buf = StringBuilder::new()
      let mut has_escape = false
      if c == '\\' {
        // Unicode escape at identifier start
        has_escape = true
        offset += 2 // skip \ and u
        col += 2
        let cp = parse_unicode_escape()
        if !is_id_start_cp(cp) {
          raise @errors.SyntaxError(
            message="Invalid Unicode escape sequence at line \{line}, col \{col}",
          )
        }
        write_code_point(ident_buf, cp)
      } else {
        ident_buf.write_char(c)
        offset += 1
        col += 1
      }
      while offset < len {
        let ch = char_at(offset)
        if is_id_continue_cp(ch.to_int()) {
          ident_buf.write_char(ch)
          offset += 1
          col += 1
        } else if ch == '\\' && offset + 1 < len && char_at(offset + 1) == 'u' {
          has_escape = true
          offset += 2 // skip \ and u
          col += 2
          let cp = parse_unicode_escape()
          if !is_id_continue_cp(cp) {
            raise @errors.SyntaxError(
              message="Invalid Unicode escape sequence at line \{line}, col \{col}",
            )
          }
          write_code_point(ident_buf, cp)
        } else {
          break
        }
      }
      let decoded = ident_buf.to_string()
      // Per spec: identifiers formed with unicode escapes must not be
      // treated as keywords. Escaped reserved words are valid as IdentifierName
      // (property keys, member access) but invalid as Identifier (bindings).
      // Emit as Ident and let the parser enforce binding restrictions.
      let kind : @token.TokenKind = if has_escape {
        @token.TokenKind::Ident(decoded)
      } else {
        resolve_keyword(decoded)
      }
      tokens.push({ kind, loc, raw: decoded, lex_form: LexNormal })
      continue
    }
    // Strings
    if c == '"' || c == '\'' {
      let quote = c
      let start = offset
      offset += 1
      col += 1
      let buf = StringBuilder::new()
      let mut has_legacy_octal_escape = false
      while offset < len && char_at(offset) != quote {
        if char_at(offset) == '\\' && offset + 1 < len {
          offset += 1
          col += 1
          let esc = char_at(offset)
          match esc {
            'n' => buf.write_char('\n')
            't' => buf.write_char('\t')
            'r' => buf.write_char('\r')
            'b' => write_code_point(buf, 8) // backspace
            'v' => write_code_point(buf, 11) // vertical tab
            'f' => write_code_point(buf, 12) // form feed
            '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' => {
              // Tag this string token with legacy-octal-escape provenance.
              // \0 followed by a non-decimal-digit is the spec-allowed exception (NUL).
              // All other cases (\\1..\\7 always; \\0 followed by 0-9) are legacy.
              if esc == '0' {
                let next_is_decimal_digit = offset + 1 < len &&
                  char_at(offset + 1) >= '0' &&
                  char_at(offset + 1) <= '9'
                if next_is_decimal_digit {
                  has_legacy_octal_escape = true
                }
              } else {
                // \\1..\\7 always tag
                has_legacy_octal_escape = true
              }
              // Legacy octal escape (Annex B, non-strict). Parse 1-3 octal digits.
              let d1 = esc.to_int() - 48
              let next_is_octal = offset + 1 < len &&
                char_at(offset + 1) >= '0' &&
                char_at(offset + 1) <= '7'
              if !next_is_octal {
                write_code_point(buf, d1)
              } else if d1 <= 3 {
                // 0-3: up to two more octal digits
                offset += 1
                col += 1
                let d2 = char_at(offset).to_int() - 48
                let next2_is_octal = offset + 1 < len &&
                  char_at(offset + 1) >= '0' &&
                  char_at(offset + 1) <= '7'
                if next2_is_octal {
                  offset += 1
                  col += 1
                  let d3 = char_at(offset).to_int() - 48
                  write_code_point(buf, d1 * 64 + d2 * 8 + d3)
                } else {
                  write_code_point(buf, d1 * 8 + d2)
                }
              } else {
                // 4-7: exactly one more octal digit
                offset += 1
                col += 1
                let d2 = char_at(offset).to_int() - 48
                write_code_point(buf, d1 * 8 + d2)
              }
            }
            '\\' => buf.write_char('\\')
            '\'' => buf.write_char('\'')
            '"' => buf.write_char('"')
            'x' => {
              // \xHH hex escape — parse exactly 2 hex digits
              offset += 1
              col += 1
              if offset + 1 < len &&
                is_hex_digit(char_at(offset)) &&
                is_hex_digit(char_at(offset + 1)) {
                let hex_str = String::make(1, char_at(offset)) +
                  String::make(1, char_at(offset + 1))
                let cp = parse_hex(hex_str).to_int()
                buf.write_char(cp.unsafe_to_char())
                offset += 2
                col += 2
              } else {
                raise @errors.SyntaxError(
                  message="Invalid hexadecimal escape sequence at line \{line}, col \{col}",
                )
              }
              continue
            }
            'u' => {
              offset += 1 // skip 'u'
              col += 1
              let cp = parse_unicode_escape()
              write_code_point(buf, cp)
              continue
            }
            '8' | '9' => {
              // NonOctalDecimalEscapeSequence (Annex B). In non-strict, the backslash
              // is dropped and the digit is preserved. In strict, this is a SyntaxError
              // (handled by the strict-mode validator via the lex_form tag).
              has_legacy_octal_escape = true
              buf.write_char(esc)
            }
            // LineContinuation: \ followed by any LineTerminator (\n, \r, U+2028, U+2029)
            // The backslash and the line terminator are consumed but NOT added to the string value
            _ if is_line_terminator(esc) => {
              if esc == '\r' {
                offset += 1
                if offset < len && char_at(offset) == '\n' {
                  offset += 1 // skip the LF in CRLF
                }
              } else {
                offset += 1
              }
              line += 1
              col = 1
              continue
            }
            _ =>
              // NonEscapeCharacter: the backslash is consumed; the char itself is the value.
              buf.write_char(esc)
          }
          offset += 1
          col += 1
        } else {
          // Only \n (0x0A) and \r (0x0D) terminate string literals.
          // U+2028 and U+2029 are allowed per ES2019 json-superset (§12.9.4).
          let raw_cp = char_at(offset).to_int()
          if raw_cp == 0x0A || raw_cp == 0x0D {
            raise @errors.SyntaxError(
              message="Unterminated string at line \{line}, col \{col}",
            )
          }
          col += 1
          buf.write_char(char_at(offset))
          offset += 1
        }
      }
      if offset >= len {
        raise @errors.SyntaxError(
          message="Unterminated string at line \{loc.line}, col \{loc.col}",
        )
      }
      offset += 1 // skip closing quote
      col += 1
      let raw = source.view()[start:offset].to_owned()
      let lex_form : @token.LexForm = if has_legacy_octal_escape {
        StringLegacyOctalEscape
      } else {
        LexNormal
      }
      tokens.push({ kind: String_(buf.to_string()), loc, raw, lex_form })
      continue
    }
    // Template literals (backtick)
    if c == '`' {
      let tloc = make_loc()
      offset += 1
      col += 1
      let (text, has_expr) = scan_template_string()
      if has_expr {
        template_depth_stack.push(1)
        tokens.push({
          kind: TemplateHead(text),
          loc: tloc,
          raw: "",
          lex_form: LexNormal,
        })
      } else {
        tokens.push({
          kind: NoSubTemplate(text),
          loc: tloc,
          raw: "",
          lex_form: LexNormal,
        })
      }
      continue
    }
    // Multi-character operators (longest match first)
    // 4-char
    if c == '>' &&
      offset + 3 < len &&
      char_at(offset + 1) == '>' &&
      char_at(offset + 2) == '>' &&
      char_at(offset + 3) == '=' {
      tokens.push({ kind: URShiftAssign, loc, raw: ">>>=", lex_form: LexNormal })
      offset += 4
      col += 4
      continue
    }
    // 3-char
    if c == '=' &&
      offset + 2 < len &&
      char_at(offset + 1) == '=' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: EqEqEq, loc, raw: "===", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    if c == '!' &&
      offset + 2 < len &&
      char_at(offset + 1) == '=' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: BangEqEq, loc, raw: "!==", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    if c == '>' &&
      offset + 2 < len &&
      char_at(offset + 1) == '>' &&
      char_at(offset + 2) == '>' {
      tokens.push({ kind: URShift, loc, raw: ">>>", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    if c == '>' &&
      offset + 2 < len &&
      char_at(offset + 1) == '>' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: RShiftAssign, loc, raw: ">>=", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    if c == '<' &&
      offset + 2 < len &&
      char_at(offset + 1) == '<' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: LShiftAssign, loc, raw: "<<=", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    // 2-char
    if c == '=' && offset + 1 < len && char_at(offset + 1) == '>' {
      tokens.push({ kind: Arrow, loc, raw: "=>", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '=' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: EqEq, loc, raw: "==", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '!' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BangEq, loc, raw: "!=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '>' && offset + 1 < len && char_at(offset + 1) == '>' {
      tokens.push({ kind: RShift, loc, raw: ">>", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '>' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: GtEq, loc, raw: ">=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '<' && offset + 1 < len && char_at(offset + 1) == '<' {
      tokens.push({ kind: LShift, loc, raw: "<<", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '<' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: LtEq, loc, raw: "<=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '+' && offset + 1 < len && char_at(offset + 1) == '+' {
      tokens.push({ kind: PlusPlus, loc, raw: "++", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '+' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: PlusAssign, loc, raw: "+=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '-' && offset + 1 < len && char_at(offset + 1) == '-' {
      tokens.push({ kind: MinusMinus, loc, raw: "--", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '-' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: MinusAssign, loc, raw: "-=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '*' && offset + 1 < len && char_at(offset + 1) == '*' {
      if offset + 2 < len && char_at(offset + 2) == '=' {
        tokens.push({
          kind: StarStarAssign,
          loc,
          raw: "**=",
          lex_form: LexNormal,
        })
        offset += 3
        col += 3
        continue
      }
      tokens.push({ kind: StarStar, loc, raw: "**", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '*' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: StarAssign, loc, raw: "*=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '/' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: SlashAssign, loc, raw: "/=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '%' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: PercentAssign, loc, raw: "%=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    // Logical assignment operators (3-char, must check before 2-char)
    if c == '&' &&
      offset + 2 < len &&
      char_at(offset + 1) == '&' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: AndAssign, loc, raw: "&&=", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    if c == '&' && offset + 1 < len && char_at(offset + 1) == '&' {
      tokens.push({ kind: And, loc, raw: "&&", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '&' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BitAndAssign, loc, raw: "&=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '|' &&
      offset + 2 < len &&
      char_at(offset + 1) == '|' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: OrAssign, loc, raw: "||=", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    if c == '|' && offset + 1 < len && char_at(offset + 1) == '|' {
      tokens.push({ kind: Or, loc, raw: "||", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '|' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BitOrAssign, loc, raw: "|=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    if c == '^' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BitXorAssign, loc, raw: "^=", lex_form: LexNormal })
      offset += 2
      col += 2
      continue
    }
    // Optional chaining (?.) and nullish coalescing (??) and nullish assignment (??=)
    if c == '?' &&
      offset + 2 < len &&
      char_at(offset + 1) == '?' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: NullishAssign, loc, raw: "??=", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    if c == '?' && offset + 1 < len && char_at(offset + 1) == '?' {
      tokens.push({
        kind: QuestionQuestion,
        loc,
        raw: "??",
        lex_form: LexNormal,
      })
      offset += 2
      col += 2
      continue
    }
    if c == '?' && offset + 1 < len && char_at(offset + 1) == '.' {
      // Distinguish from ternary with number: x ? .5 : y
      // ?. is optional chaining only if NOT followed by a digit
      if offset + 2 >= len || !is_digit(char_at(offset + 2)) {
        tokens.push({ kind: QuestionDot, loc, raw: "?.", lex_form: LexNormal })
        offset += 2
        col += 2
        continue
      }
    }
    // Handle } specially for template literal brace-depth tracking
    if c == '}' && template_depth_stack.length() > 0 {
      let top = template_depth_stack.length() - 1
      template_depth_stack[top] = template_depth_stack[top] - 1
      if template_depth_stack[top] == 0 {
        let _ = template_depth_stack.pop()
        let tloc = make_loc()
        offset += 1
        col += 1
        let (text, has_expr) = scan_template_string()
        if has_expr {
          template_depth_stack.push(1)
          tokens.push({
            kind: TemplateMiddle(text),
            loc: tloc,
            raw: "",
            lex_form: LexNormal,
          })
        } else {
          tokens.push({
            kind: TemplateTail(text),
            loc: tloc,
            raw: "",
            lex_form: LexNormal,
          })
        }
        continue
      }
    }
    // Handle { specially for template literal brace-depth tracking
    if c == '{' && template_depth_stack.length() > 0 {
      let top = template_depth_stack.length() - 1
      template_depth_stack[top] = template_depth_stack[top] + 1
    }
    // .5 style number literals (leading decimal point)
    if c == '.' && offset + 1 < len && is_digit(char_at(offset + 1)) {
      let num_start = offset
      offset += 1 // skip '.'
      col += 1
      while offset < len &&
            (is_digit(char_at(offset)) || char_at(offset) == '_') {
        if char_at(offset) == '_' {
          // Numeric separator must be between digits
          if offset + 1 >= len || !is_digit(char_at(offset + 1)) {
            raise @errors.SyntaxError(
              message="Numeric separators are not allowed at the end of numeric literals at line \{line}, col \{col}",
            )
          }
        }
        offset += 1
        col += 1
      }
      // Handle exponent part: e.g., .5e10
      if offset < len && (char_at(offset) == 'e' || char_at(offset) == 'E') {
        offset += 1
        col += 1
        if offset < len && (char_at(offset) == '+' || char_at(offset) == '-') {
          offset += 1
          col += 1
        }
        let digit_start = offset
        while offset < len &&
              (is_digit(char_at(offset)) || char_at(offset) == '_') {
          if char_at(offset) == '_' {
            if offset + 1 >= len || !is_digit(char_at(offset + 1)) {
              raise @errors.SyntaxError(
                message="Numeric separators are not allowed at the end of numeric literals at line \{line}, col \{col}",
              )
            }
          }
          offset += 1
          col += 1
        }
        // Exponent must have at least one digit
        if offset == digit_start {
          raise @errors.SyntaxError(
            message="Invalid or unexpected token at line \{line}, col \{col}",
          )
        }
      }
      let raw_str = source.view()[num_start:offset].to_owned()
      // Remove numeric separators for parsing
      let buf = StringBuilder::new()
      for ch in raw_str {
        if ch != '_' {
          buf.write_char(ch)
        }
      }
      let num_str = buf.to_string()
      let value = @string.parse_double(num_str) catch {
        _ =>
          raise @errors.SyntaxError(
            message="Invalid or unexpected token at line \{line}, col \{col}",
          )
      }
      tokens.push({
        kind: Number(value),
        loc,
        raw: num_str,
        lex_form: LexNormal,
      })
      continue
    }
    // ... (spread/rest)
    if c == '.' &&
      offset + 2 < len &&
      char_at(offset + 1) == '.' &&
      char_at(offset + 2) == '.' {
      tokens.push({ kind: DotDotDot, loc, raw: "...", lex_form: LexNormal })
      offset += 3
      col += 3
      continue
    }
    // Single-character tokens
    let (kind, raw) : (@token.TokenKind, String) = match c {
      '+' => (Plus, "+")
      '-' => (Minus, "-")
      '*' => (Star, "*")
      '/' => (Slash, "/")
      '%' => (Percent, "%")
      '=' => (Assign, "=")
      '!' => (Bang, "!")
      '<' => (Lt, "<")
      '>' => (Gt, ">")
      '&' => (BitAnd, "&")
      '|' => (BitOr, "|")
      '^' => (BitXor, "^")
      '~' => (Tilde, "~")
      '(' => (LParen, "(")
      ')' => (RParen, ")")
      '{' => (LBrace, "{")
      '}' => (RBrace, "}")
      '[' => (LBracket, "[")
      ']' => (RBracket, "]")
      ',' => (Comma, ",")
      ';' => (Semicolon, ";")
      '.' => (Dot, ".")
      ':' => (Colon, ":")
      '?' => (Question, "?")
      _ =>
        raise @errors.SyntaxError(
          message="Unexpected character '\{c}' at line \{loc.line}, col \{loc.col}",
        )
    }
    tokens.push({ kind, loc, raw, lex_form: LexNormal })
    // Track control-flow parens for regex disambiguation
    match kind {
      LParen => {
        // Check if the token before ( is a control-flow keyword
        let is_cf = if tokens.length() >= 2 {
          let prev = tokens[tokens.length() - 2].kind
          match prev {
            If | While | For | Switch => true
            _ => false
          }
        } else {
          false
        }
        paren_is_control_flow.push(is_cf)
      }
      RParen =>
        last_rparen_is_control_flow = if paren_is_control_flow.length() > 0 {
          match paren_is_control_flow.pop() {
            Some(v) => v
            None => false
          }
        } else {
          false
        }
      _ => ()
    }
    offset += 1
    col += 1
  }
  let eof_loc = make_loc()
  tokens.push(@token.Token::eof(eof_loc))
  tokens
}

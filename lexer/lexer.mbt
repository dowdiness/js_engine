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
fn parse_binary(s : String) -> Double {
  let chars = s.to_array()
  let mut result = 0.0
  for c in chars {
    let digit = c.to_int() - 48
    result = result * 2.0 + digit.to_double()
  }
  result
}

///|
fn parse_octal(s : String) -> Double {
  let chars = s.to_array()
  let mut result = 0.0
  for c in chars {
    let digit = c.to_int() - 48
    result = result * 8.0 + digit.to_double()
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
          '\\' => buf.write_char('\\')
          '`' => buf.write_char('`')
          '$' => buf.write_char('$')
          _ => {
            buf.write_char('\\')
            buf.write_char(esc)
          }
        }
        offset += 1
        col += 1
      } else {
        if tc == '\n' {
          line += 1
          col = 1
        } else {
          col += 1
        }
        buf.write_char(tc)
        offset += 1
      }
    }
    raise Failure::Failure(
      "Unterminated template literal at line \{line}, col \{col}",
    )
  }

  while offset < len {
    let c = char_at(offset)
    // Skip whitespace
    if c == ' ' || c == '\t' || c == '\r' {
      offset += 1
      col += 1
      continue
    }
    if c == '\n' {
      offset += 1
      line += 1
      col = 1
      continue
    }
    // Comments and regex literals
    if c == '/' && offset + 1 < len {
      let next = char_at(offset + 1)
      if next == '/' {
        // Single-line comment
        offset += 2
        col += 2
        while offset < len && char_at(offset) != '\n' {
          offset += 1
          col += 1
        }
        continue
      }
      if next == '*' {
        // Multi-line comment
        offset += 2
        col += 2
        while offset + 1 < len {
          if char_at(offset) == '*' && char_at(offset + 1) == '/' {
            offset += 2
            col += 2
            break
          }
          if char_at(offset) == '\n' {
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
            Assign | EqEq | EqEqEq | BangEq | BangEqEq | LParen | LBracket | LBrace | Comma | Semicolon | Colon | Question | QuestionQuestion | QuestionDot | And | Or | Bang | Plus | Minus | Star | StarStar | Slash | Percent | Lt | Gt | LtEq | GtEq | Return | Typeof | Throw | New | Delete | Void | In | Instanceof | PlusAssign | MinusAssign | StarAssign | StarStarAssign | SlashAssign | PercentAssign | BitAnd | BitOr | BitXor | Tilde | LShift | RShift | URShift | BitAndAssign | BitOrAssign | BitXorAssign | LShiftAssign | RShiftAssign | URShiftAssign | Case | Arrow => true
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
            if rc == '/' && not(in_class) {
              break
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
            raise Failure::Failure(
              "Unterminated regex literal at line \{rloc.line}, col \{rloc.col}",
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
      // Check for hex (0x), binary (0b), octal (0o)
      if c == '0' && offset + 1 < len {
        let next = char_at(offset + 1)
        if next == 'x' || next == 'X' {
          // Hex number
          offset += 2
          col += 2
          let mut has_digits = false
          let mut prev_underscore = true // Treat start as "after underscore" to prevent leading _
          while offset < len {
            let ch = char_at(offset)
            if is_hex_digit(ch) {
              buf.write_char(ch)
              offset += 1
              col += 1
              has_digits = true
              prev_underscore = false
            } else if ch == '_' {
              if prev_underscore {
                raise Failure::Failure(
                  "Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
                )
              }
              prev_underscore = true
              offset += 1
              col += 1
            } else {
              break
            }
          }
          if not(has_digits) {
            raise Failure::Failure(
              "Missing hex digits after '0x' at line \{loc.line}, col \{loc.col}",
            )
          }
          if prev_underscore && buf.to_string().length() > 0 {
            raise Failure::Failure(
              "Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
            )
          }
          let hex_str = buf.to_string()
          let value = parse_hex(hex_str)
          let raw = source.view()[start:offset].to_string()
          tokens.push({ kind: Number(value), loc, raw })
          continue
        } else if next == 'b' || next == 'B' {
          // Binary number
          offset += 2
          col += 2
          let mut has_digits = false
          let mut prev_underscore = true
          while offset < len {
            let ch = char_at(offset)
            if ch == '0' || ch == '1' {
              buf.write_char(ch)
              offset += 1
              col += 1
              has_digits = true
              prev_underscore = false
            } else if ch == '_' {
              if prev_underscore {
                raise Failure::Failure(
                  "Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
                )
              }
              prev_underscore = true
              offset += 1
              col += 1
            } else {
              break
            }
          }
          if not(has_digits) {
            raise Failure::Failure(
              "Missing binary digits after '0b' at line \{loc.line}, col \{loc.col}",
            )
          }
          if prev_underscore && buf.to_string().length() > 0 {
            raise Failure::Failure(
              "Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
            )
          }
          let bin_str = buf.to_string()
          let value = parse_binary(bin_str)
          let raw = source.view()[start:offset].to_string()
          tokens.push({ kind: Number(value), loc, raw })
          continue
        } else if next == 'o' || next == 'O' {
          // Octal number
          offset += 2
          col += 2
          let mut has_digits = false
          let mut prev_underscore = true
          while offset < len {
            let ch = char_at(offset)
            if ch >= '0' && ch <= '7' {
              buf.write_char(ch)
              offset += 1
              col += 1
              has_digits = true
              prev_underscore = false
            } else if ch == '_' {
              if prev_underscore {
                raise Failure::Failure(
                  "Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
                )
              }
              prev_underscore = true
              offset += 1
              col += 1
            } else {
              break
            }
          }
          if not(has_digits) {
            raise Failure::Failure(
              "Missing octal digits after '0o' at line \{loc.line}, col \{loc.col}",
            )
          }
          if prev_underscore && buf.to_string().length() > 0 {
            raise Failure::Failure(
              "Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
            )
          }
          let oct_str = buf.to_string()
          let value = parse_octal(oct_str)
          let raw = source.view()[start:offset].to_string()
          tokens.push({ kind: Number(value), loc, raw })
          continue
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
            raise Failure::Failure(
              "Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
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
          raise Failure::Failure(
            "Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
          )
        }
      }
      // Decimal part
      if offset < len && char_at(offset) == '.' {
        // Trailing underscore before '.' is actually invalid
        if prev_underscore && buf.to_string().length() > 0 {
          raise Failure::Failure(
            "Numeric separator cannot appear before decimal point at line \{loc.line}, col \{col - 1}",
          )
        }
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
              raise Failure::Failure(
                "Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
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
        if prev_underscore {
          let num_str_so_far = buf.to_string()
          if num_str_so_far.length() > 0 &&
            num_str_so_far.to_array()[num_str_so_far.length() - 1] != '.' {
            raise Failure::Failure(
              "Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
            )
          }
        }
      }
      // Exponent part
      if offset < len && (char_at(offset) == 'e' || char_at(offset) == 'E') {
        // Check for trailing underscore before 'e'
        if prev_underscore && buf.to_string().length() > 0 {
          raise Failure::Failure(
            "Numeric separator cannot appear before exponent at line \{loc.line}, col \{col - 1}",
          )
        }
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
              raise Failure::Failure(
                "Numeric separator cannot appear consecutively at line \{loc.line}, col \{col}",
              )
            }
            prev_underscore = true
            offset += 1
            col += 1
          } else {
            break
          }
        }
        if not(has_exp_digits) {
          raise Failure::Failure(
            "Missing exponent digits at line \{loc.line}, col \{col}",
          )
        }
        if prev_underscore {
          raise Failure::Failure(
            "Numeric separator cannot appear at the end at line \{loc.line}, col \{col - 1}",
          )
        }
      }
      let num_str = buf.to_string()
      let raw = source.view()[start:offset].to_string()
      let value = @strconv.parse_double(num_str)
      tokens.push({ kind: Number(value), loc, raw })
      continue
    }
    // Identifiers / Keywords
    if is_alpha(c) {
      let start = offset
      while offset < len && is_alnum(char_at(offset)) {
        offset += 1
        col += 1
      }
      let raw = source.view()[start:offset].to_string()
      let kind = resolve_keyword(raw)
      tokens.push({ kind, loc, raw })
      continue
    }
    // Strings
    if c == '"' || c == '\'' {
      let quote = c
      let start = offset
      offset += 1
      col += 1
      let buf = StringBuilder::new()
      while offset < len && char_at(offset) != quote {
        if char_at(offset) == '\\' && offset + 1 < len {
          offset += 1
          col += 1
          let esc = char_at(offset)
          match esc {
            'n' => buf.write_char('\n')
            't' => buf.write_char('\t')
            '\\' => buf.write_char('\\')
            '\'' => buf.write_char('\'')
            '"' => buf.write_char('"')
            _ => {
              buf.write_char('\\')
              buf.write_char(esc)
            }
          }
          offset += 1
          col += 1
        } else {
          if char_at(offset) == '\n' {
            line += 1
            col = 1
          } else {
            col += 1
          }
          buf.write_char(char_at(offset))
          offset += 1
        }
      }
      if offset >= len {
        raise Failure::Failure(
          "Unterminated string at line \{loc.line}, col \{loc.col}",
        )
      }
      offset += 1 // skip closing quote
      col += 1
      let raw = source.view()[start:offset].to_string()
      tokens.push({ kind: String_(buf.to_string()), loc, raw })
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
        tokens.push({ kind: TemplateHead(text), loc: tloc, raw: "" })
      } else {
        tokens.push({ kind: NoSubTemplate(text), loc: tloc, raw: "" })
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
      tokens.push({ kind: URShiftAssign, loc, raw: ">>>=" })
      offset += 4
      col += 4
      continue
    }
    // 3-char
    if c == '=' &&
      offset + 2 < len &&
      char_at(offset + 1) == '=' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: EqEqEq, loc, raw: "===" })
      offset += 3
      col += 3
      continue
    }
    if c == '!' &&
      offset + 2 < len &&
      char_at(offset + 1) == '=' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: BangEqEq, loc, raw: "!==" })
      offset += 3
      col += 3
      continue
    }
    if c == '>' &&
      offset + 2 < len &&
      char_at(offset + 1) == '>' &&
      char_at(offset + 2) == '>' {
      tokens.push({ kind: URShift, loc, raw: ">>>" })
      offset += 3
      col += 3
      continue
    }
    if c == '>' &&
      offset + 2 < len &&
      char_at(offset + 1) == '>' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: RShiftAssign, loc, raw: ">>=" })
      offset += 3
      col += 3
      continue
    }
    if c == '<' &&
      offset + 2 < len &&
      char_at(offset + 1) == '<' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: LShiftAssign, loc, raw: "<<=" })
      offset += 3
      col += 3
      continue
    }
    // 2-char
    if c == '=' && offset + 1 < len && char_at(offset + 1) == '>' {
      tokens.push({ kind: Arrow, loc, raw: "=>" })
      offset += 2
      col += 2
      continue
    }
    if c == '=' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: EqEq, loc, raw: "==" })
      offset += 2
      col += 2
      continue
    }
    if c == '!' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BangEq, loc, raw: "!=" })
      offset += 2
      col += 2
      continue
    }
    if c == '>' && offset + 1 < len && char_at(offset + 1) == '>' {
      tokens.push({ kind: RShift, loc, raw: ">>" })
      offset += 2
      col += 2
      continue
    }
    if c == '>' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: GtEq, loc, raw: ">=" })
      offset += 2
      col += 2
      continue
    }
    if c == '<' && offset + 1 < len && char_at(offset + 1) == '<' {
      tokens.push({ kind: LShift, loc, raw: "<<" })
      offset += 2
      col += 2
      continue
    }
    if c == '<' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: LtEq, loc, raw: "<=" })
      offset += 2
      col += 2
      continue
    }
    if c == '+' && offset + 1 < len && char_at(offset + 1) == '+' {
      tokens.push({ kind: PlusPlus, loc, raw: "++" })
      offset += 2
      col += 2
      continue
    }
    if c == '+' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: PlusAssign, loc, raw: "+=" })
      offset += 2
      col += 2
      continue
    }
    if c == '-' && offset + 1 < len && char_at(offset + 1) == '-' {
      tokens.push({ kind: MinusMinus, loc, raw: "--" })
      offset += 2
      col += 2
      continue
    }
    if c == '-' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: MinusAssign, loc, raw: "-=" })
      offset += 2
      col += 2
      continue
    }
    if c == '*' && offset + 1 < len && char_at(offset + 1) == '*' {
      if offset + 2 < len && char_at(offset + 2) == '=' {
        tokens.push({ kind: StarStarAssign, loc, raw: "**=" })
        offset += 3
        col += 3
        continue
      }
      tokens.push({ kind: StarStar, loc, raw: "**" })
      offset += 2
      col += 2
      continue
    }
    if c == '*' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: StarAssign, loc, raw: "*=" })
      offset += 2
      col += 2
      continue
    }
    if c == '/' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: SlashAssign, loc, raw: "/=" })
      offset += 2
      col += 2
      continue
    }
    if c == '%' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: PercentAssign, loc, raw: "%=" })
      offset += 2
      col += 2
      continue
    }
    // Logical assignment operators (3-char, must check before 2-char)
    if c == '&' &&
      offset + 2 < len &&
      char_at(offset + 1) == '&' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: AndAssign, loc, raw: "&&=" })
      offset += 3
      col += 3
      continue
    }
    if c == '&' && offset + 1 < len && char_at(offset + 1) == '&' {
      tokens.push({ kind: And, loc, raw: "&&" })
      offset += 2
      col += 2
      continue
    }
    if c == '&' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BitAndAssign, loc, raw: "&=" })
      offset += 2
      col += 2
      continue
    }
    if c == '|' &&
      offset + 2 < len &&
      char_at(offset + 1) == '|' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: OrAssign, loc, raw: "||=" })
      offset += 3
      col += 3
      continue
    }
    if c == '|' && offset + 1 < len && char_at(offset + 1) == '|' {
      tokens.push({ kind: Or, loc, raw: "||" })
      offset += 2
      col += 2
      continue
    }
    if c == '|' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BitOrAssign, loc, raw: "|=" })
      offset += 2
      col += 2
      continue
    }
    if c == '^' && offset + 1 < len && char_at(offset + 1) == '=' {
      tokens.push({ kind: BitXorAssign, loc, raw: "^=" })
      offset += 2
      col += 2
      continue
    }
    // Optional chaining (?.) and nullish coalescing (??) and nullish assignment (??=)
    if c == '?' &&
      offset + 2 < len &&
      char_at(offset + 1) == '?' &&
      char_at(offset + 2) == '=' {
      tokens.push({ kind: NullishAssign, loc, raw: "??=" })
      offset += 3
      col += 3
      continue
    }
    if c == '?' && offset + 1 < len && char_at(offset + 1) == '?' {
      tokens.push({ kind: QuestionQuestion, loc, raw: "??" })
      offset += 2
      col += 2
      continue
    }
    if c == '?' && offset + 1 < len && char_at(offset + 1) == '.' {
      // Distinguish from ternary with number: x ? .5 : y
      // ?. is optional chaining only if NOT followed by a digit
      if offset + 2 >= len || not(is_digit(char_at(offset + 2))) {
        tokens.push({ kind: QuestionDot, loc, raw: "?." })
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
          tokens.push({ kind: TemplateMiddle(text), loc: tloc, raw: "" })
        } else {
          tokens.push({ kind: TemplateTail(text), loc: tloc, raw: "" })
        }
        continue
      }
    }
    // Handle { specially for template literal brace-depth tracking
    if c == '{' && template_depth_stack.length() > 0 {
      let top = template_depth_stack.length() - 1
      template_depth_stack[top] = template_depth_stack[top] + 1
    }
    // ... (spread/rest)
    if c == '.' &&
      offset + 2 < len &&
      char_at(offset + 1) == '.' &&
      char_at(offset + 2) == '.' {
      tokens.push({ kind: DotDotDot, loc, raw: "..." })
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
        raise Failure::Failure(
          "Unexpected character '\{c}' at line \{loc.line}, col \{loc.col}",
        )
    }
    tokens.push({ kind, loc, raw })
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

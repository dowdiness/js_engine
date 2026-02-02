///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
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
    // Comments
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
    }
    let loc = make_loc()
    // Numbers
    if is_digit(c) {
      let start = offset
      while offset < len && is_digit(char_at(offset)) {
        offset += 1
        col += 1
      }
      if offset < len && char_at(offset) == '.' {
        offset += 1
        col += 1
        while offset < len && is_digit(char_at(offset)) {
          offset += 1
          col += 1
        }
      }
      let raw = source.view()[start:offset].to_string()
      let value = @strconv.parse_double(raw)
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
    offset += 1
    col += 1
  }
  let eof_loc = make_loc()
  tokens.push(@token.Token::eof(eof_loc))
  tokens
}

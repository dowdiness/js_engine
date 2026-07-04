///| Basic regex engine for JS RegExp support
/// Supports: literals, ., *, +, ?, ^, $, \d, \w, \s, \D, \W, \S, \b, \B,
/// character classes [...], [^...], grouping (...), alternation |, {n}, {n,}, {n,m},
/// lookahead (?=...), negative lookahead (?!...), sticky (y) flag, unicode (u) flag,
/// dotAll (s) flag, backreferences \1-\9

// ---- Regex AST ----

///|
priv enum RegexNode {
  Literal(Char)
  Dot // matches any char except newline (or any char with dotAll flag)
  CharClass(Array[(Char, Char)], Bool) // ranges, negated
  Anchor(AnchorKind)
  Quantified(RegexNode, Int, Int?, Bool) // node, min, max(None=infinity), greedy
  Group(Array[RegexNode], Int, String?) // children, group_index, name
  Alternation(Array[RegexNode], Array[RegexNode]) // left, right
  Sequence(Array[RegexNode])
  WordBoundary(Bool) // true = \b, false = \B
  Lookahead(Array[RegexNode], Bool) // children, positive (true=(?=...), false=(?!...))
  Backreference(Int) // group number (1-based)
  NamedBackreference(String) // group name before post-parse resolution
  DuplicateNamedBackreference(Array[Int]) // duplicate-name group indices
}

///|
priv enum AnchorKind {
  Start // ^
  End // $
}

// ---- Regex Parser ----

///|
priv struct RegexParser {
  pattern : Array[Char]
  mut pos : Int
  mut group_count : Int
  unicode : Bool
  group_names : Map[String, Int]
  group_name_entries : Array[(String, Int)]
  mut has_unterminated_k_backref : Bool
  mut has_bare_k : Bool
}

///|
fn RegexParser::new(pattern : String, unicode? : Bool = false) -> RegexParser {
  {
    pattern: pattern.to_array(),
    pos: 0,
    group_count: 0,
    unicode,
    group_names: {},
    group_name_entries: [],
    has_unterminated_k_backref: false,
    has_bare_k: false,
  }
}

///|
/// Annex B: When no named groups exist in the pattern, convert
/// NamedBackreference("name") nodes to literal char sequences
/// matching the text "k<name>" (the backslash was already consumed).
fn desugar_named_backrefs_to_literals(node : RegexNode) -> RegexNode {
  match node {
    NamedBackreference(name) => {
      // \k<name> or \k<> — literal "k<name>" or "k<>"
      let chars : Array[RegexNode] = [Literal('k'), Literal('<')]
      let name_chars = name.to_array()
      for c in name_chars {
        chars.push(Literal(c))
      }
      chars.push(Literal('>'))
      Sequence(chars)
    }
    Group(children, idx, name) => {
      let resolved = children.map(child => {
        desugar_named_backrefs_to_literals(child)
      })
      Group(resolved, idx, name)
    }
    Sequence(nodes) => {
      let resolved = nodes.map(child => {
        desugar_named_backrefs_to_literals(child)
      })
      Sequence(resolved)
    }
    Alternation(left, right) => {
      let resolved_left = left.map(child => {
        desugar_named_backrefs_to_literals(child)
      })
      let resolved_right = right.map(child => {
        desugar_named_backrefs_to_literals(child)
      })
      Alternation(resolved_left, resolved_right)
    }
    Quantified(inner, min, max, greedy) => {
      let resolved = desugar_named_backrefs_to_literals(inner)
      Quantified(resolved, min, max, greedy)
    }
    Lookahead(children, positive) => {
      let resolved = children.map(child => {
        desugar_named_backrefs_to_literals(child)
      })
      Lookahead(resolved, positive)
    }
    Literal(_)
    | Dot
    | CharClass(_, _)
    | Anchor(_)
    | WordBoundary(_)
    | Backreference(_)
    | DuplicateNamedBackreference(_) => node
  }
}

///|
fn regex_named_group_indices(
  group_name_entries : Array[(String, Int)],
) -> Map[String, Array[Int]] {
  let indices : Map[String, Array[Int]] = {}
  for entry in group_name_entries {
    let (name, idx) = entry
    match indices.get(name) {
      Some(existing) => existing.push(idx)
      None => indices[name] = [idx]
    }
  }
  indices
}

///|
fn resolve_named_backreferences(
  node : RegexNode,
  group_names : Map[String, Array[Int]],
) -> RegexNode raise Error {
  match node {
    NamedBackreference(name) =>
      match group_names.get(name) {
        Some(indices) =>
          if indices.length() == 1 {
            Backreference(indices[0])
          } else {
            DuplicateNamedBackreference(indices.copy())
          }
        None =>
          raise @errors.SyntaxError(
            message="Invalid regex: undefined named backreference \\k<" +
              name +
              ">",
          )
      }
    Group(children, idx, name) => {
      let resolved = children.map(child => {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Group(resolved, idx, name)
    }
    Sequence(nodes) => {
      let resolved = nodes.map(child => {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Sequence(resolved)
    }
    Alternation(left, right) => {
      let resolved_left = left.map(child => {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      let resolved_right = right.map(child => {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Alternation(resolved_left, resolved_right)
    }
    Quantified(inner, min, max, greedy) => {
      let resolved = resolve_named_backreferences(inner, group_names)
      Quantified(resolved, min, max, greedy)
    }
    Lookahead(children, positive) => {
      let resolved = children.map(child => {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Lookahead(resolved, positive)
    }
    // Leaf nodes
    Literal(_)
    | Dot
    | CharClass(_, _)
    | Anchor(_)
    | WordBoundary(_)
    | Backreference(_)
    | DuplicateNamedBackreference(_) => node
  }
}

///|
fn validate_numeric_backreferences(
  node : RegexNode,
  group_count : Int,
) -> Unit raise Error {
  match node {
    Backreference(idx) =>
      if idx > group_count {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid numeric backreference",
        )
      }
    Group(children, _, _) | Sequence(children) | Lookahead(children, _) =>
      for child in children {
        validate_numeric_backreferences(child, group_count)
      }
    Alternation(left, right) => {
      for child in left {
        validate_numeric_backreferences(child, group_count)
      }
      for child in right {
        validate_numeric_backreferences(child, group_count)
      }
    }
    Quantified(inner, _, _, _) =>
      validate_numeric_backreferences(inner, group_count)
    Literal(_)
    | Dot
    | CharClass(_, _)
    | Anchor(_)
    | WordBoundary(_)
    | NamedBackreference(_)
    | DuplicateNamedBackreference(_) => ()
  }
}

///|
fn RegexParser::parse(self : RegexParser) -> RegexNode raise Error {
  let result = self.parse_alternation()
  let named_group_indices = regex_named_group_indices(self.group_name_entries)
  let resolved = if !self.group_names.is_empty() {
    // Pattern has named groups — reject malformed \k forms
    if self.has_unterminated_k_backref {
      raise @errors.SyntaxError(
        message="Invalid regex: unterminated named backreference in pattern with named groups",
      )
    }
    if self.has_bare_k {
      raise @errors.SyntaxError(
        message="Invalid regex: invalid escape \\k in pattern with named groups",
      )
    }
    // Resolve \k<name> to a static index or duplicate-name dynamic lookup.
    resolve_named_backreferences(result, named_group_indices)
  } else if !self.unicode {
    // Annex B: convert \k<name> to literal chars in non-unicode mode
    desugar_named_backrefs_to_literals(result)
  } else {
    // Unicode mode with no named groups: any \k<name> is invalid
    resolve_named_backreferences(result, named_group_indices)
  }
  validate_duplicate_named_group_names(resolved)
  if self.unicode {
    validate_numeric_backreferences(resolved, self.group_count)
  }
  resolved
}

///|
fn RegexParser::parse_alternation(self : RegexParser) -> RegexNode raise Error {
  let left = self.parse_sequence()
  if self.pos < self.pattern.length() && self.pattern[self.pos] == '|' {
    self.pos += 1
    let right = self.parse_alternation()
    let left_nodes = match left {
      Sequence(nodes) => nodes
      _ => [left]
    }
    let right_nodes = match right {
      Sequence(nodes) => nodes
      _ => [right]
    }
    return Alternation(left_nodes, right_nodes)
  }
  left
}

///|
fn RegexParser::parse_sequence(self : RegexParser) -> RegexNode raise Error {
  let nodes : Array[RegexNode] = []
  while self.pos < self.pattern.length() {
    let ch = self.pattern[self.pos]
    if ch == ')' || ch == '|' {
      break
    }
    let node = self.parse_atom()
    let quantified = self.parse_quantifier(node)
    // Check for double quantifier (e.g., a**  a++  a{1}{1,})
    match quantified {
      Quantified(_, _, _, _) =>
        if self.pos < self.pattern.length() {
          let next = self.pattern[self.pos]
          if next == '*' || next == '+' || next == '?' || next == '{' {
            raise @errors.SyntaxError(
              message="Invalid regex: nothing to repeat",
            )
          }
        }
      _ => ()
    }
    nodes.push(quantified)
  }
  if nodes.length() == 1 {
    return nodes[0]
  }
  Sequence(nodes)
}

///|
fn RegexParser::parse_atom(self : RegexParser) -> RegexNode raise Error {
  let ch = self.pattern[self.pos]
  match ch {
    '.' => {
      self.pos += 1
      Dot
    }
    '^' => {
      self.pos += 1
      Anchor(Start)
    }
    '$' => {
      self.pos += 1
      Anchor(End)
    }
    '[' => self.parse_char_class()
    '(' => self.parse_group()
    '\\' => self.parse_escape()
    '*' | '+' | '?' =>
      raise @errors.SyntaxError(message="Invalid regex: nothing to repeat")
    '{' if self.unicode =>
      raise @errors.SyntaxError(message="Invalid regex: incomplete quantifier")
    _ => {
      self.pos += 1
      Literal(ch)
    }
  }
}

///|
fn RegexParser::parse_escape(self : RegexParser) -> RegexNode raise Error {
  self.pos += 1 // skip backslash
  if self.pos >= self.pattern.length() {
    raise @errors.SyntaxError(message="Invalid regex: trailing backslash")
  }
  let ch = self.pattern[self.pos]
  self.pos += 1
  match ch {
    'd' => CharClass([('0', '9')], false)
    'D' => CharClass([('0', '9')], true)
    'w' => CharClass([('a', 'z'), ('A', 'Z'), ('0', '9'), ('_', '_')], false)
    'W' => CharClass([('a', 'z'), ('A', 'Z'), ('0', '9'), ('_', '_')], true)
    's' =>
      CharClass(
        [
          (' ', ' '),
          ('\t', '\t'),
          ('\n', '\n'),
          ('\r', '\r'),
          ('\u000B', '\u000B'),
          ('\u000C', '\u000C'),
          ('\u00A0', '\u00A0'),
          ('\u1680', '\u1680'),
          ('\u2000', '\u200A'),
          ('\u2028', '\u2029'),
          ('\u202F', '\u202F'),
          ('\u205F', '\u205F'),
          ('\u3000', '\u3000'),
          ('\uFEFF', '\uFEFF'),
        ],
        false,
      )
    'S' =>
      CharClass(
        [
          (' ', ' '),
          ('\t', '\t'),
          ('\n', '\n'),
          ('\r', '\r'),
          ('\u000B', '\u000B'),
          ('\u000C', '\u000C'),
          ('\u00A0', '\u00A0'),
          ('\u1680', '\u1680'),
          ('\u2000', '\u200A'),
          ('\u2028', '\u2029'),
          ('\u202F', '\u202F'),
          ('\u205F', '\u205F'),
          ('\u3000', '\u3000'),
          ('\uFEFF', '\uFEFF'),
        ],
        true,
      )
    'b' => WordBoundary(true)
    'B' => WordBoundary(false)
    'n' => Literal('\n')
    'r' => Literal('\r')
    't' => Literal('\t')
    'f' => Literal('\u000C') // form feed
    'v' => Literal('\u000B') // vertical tab
    '0' => Literal('\u0000') // null
    'k' =>
      if self.pos < self.pattern.length() && self.pattern[self.pos] == '<' {
        // Named backreference \k<name> — interpret \u escapes in name
        let saved_pos = self.pos
        self.pos += 1 // skip '<'
        let name_buf = StringBuilder::new()
        let mut valid = true
        // Try to parse the name with Unicode escape interpretation
        while self.pos < self.pattern.length() && self.pattern[self.pos] != '>' {
          if self.pattern[self.pos] == '\\' &&
            self.pos + 1 < self.pattern.length() &&
            self.pattern[self.pos + 1] == 'u' {
            let escape_pos = self.pos
            self.pos += 2 // skip \u
            try {
              let c = self.parse_unicode_escape_in_name()
              name_buf.write_char(c)
            } catch {
              _ => {
                // Invalid escape — can't parse this name
                valid = false
                self.pos = escape_pos
                break
              }
            }
          } else {
            name_buf.write_char(self.pattern[self.pos])
            self.pos += 1
          }
        }
        if !valid || self.pos >= self.pattern.length() {
          // No closing '>' or invalid escape in name
          if self.unicode {
            raise @errors.SyntaxError(
              message="Invalid regex: unterminated named backreference",
            )
          } else {
            // Annex B: backtrack and treat \k as literal 'k'.
            // Record for post-parse validation — if named groups exist,
            // unterminated \k< is a SyntaxError.
            self.has_unterminated_k_backref = true
            self.pos = saved_pos
            Literal('k')
          }
        } else {
          self.pos += 1 // skip '>'
          NamedBackreference(name_buf.to_string())
        }
      } else if self.unicode {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid escape in unicode mode",
        )
      } else {
        // Annex B: \k without < — literal 'k' in non-unicode mode.
        // Record for post-parse: if named groups exist, this is a SyntaxError.
        self.has_bare_k = true
        Literal('k')
      }
    _ =>
      if ch >= '1' && ch <= '9' {
        // Backreference \1-\9
        let group_num = ch.to_int() - '0'.to_int()
        Backreference(group_num)
      } else {
        Literal(ch) // literal escape (e.g., \., \*, etc.)
      }
  }
}

///|
/// Parse a single escaped character atom inside a character class `[...]`,
/// called after `\` and the escape letter have both been consumed from pos.
/// Does NOT handle shorthand classes (\d \w \s \D \W \S) — those are handled
/// by the caller before reaching this function.
fn RegexParser::parse_class_single_escape(
  self : RegexParser,
  escaped : Char,
) -> Char raise Error {
  match escaped {
    'u' =>
      if self.unicode {
        self.parse_unicode_escape_in_name()
      } else {
        // Annex B: parse exactly 4 hex digits, no {…} form, no surrogate-pair folding.
        // In non-unicode char classes, \uD83D and \uDE00 are separate code-unit atoms —
        // combining them into a scalar would remove both surrogates from the class.
        let saved = self.pos
        let mut cp = 0
        let mut ok = true
        for i = 0; i < 4; i = i + 1 {
          if self.pos >= self.pattern.length() ||
            !is_hex_digit(self.pattern[self.pos]) {
            ok = false
            break
          }
          cp = cp * 16 + hex_digit_value(self.pattern[self.pos])
          self.pos += 1
        }
        if ok {
          cp.unsafe_to_char()
        } else {
          self.pos = saved
          'u'
        }
      }
    'x' => {
      // Lookahead: both hex digits must be present before consuming any
      let has_2_hex = self.pos + 1 < self.pattern.length() &&
        is_hex_digit(self.pattern[self.pos]) &&
        is_hex_digit(self.pattern[self.pos + 1])
      if !has_2_hex {
        if self.unicode {
          raise @errors.SyntaxError(
            message="Invalid regex: invalid hex escape in character class",
          )
        }
        // Annex B: identity escape — return 'x' without consuming anything
        'x'
      } else {
        let cp = hex_digit_value(self.pattern[self.pos]) * 16 +
          hex_digit_value(self.pattern[self.pos + 1])
        self.pos += 2
        cp.unsafe_to_char()
      }
    }
    'n' => '\n'
    'r' => '\r'
    't' => '\t'
    'f' => '\u{000C}' // form feed
    'v' => '\u{000B}' // vertical tab
    '0' => {
      // Check for a decimal digit following \0
      let next_is_decimal = self.pos < self.pattern.length() &&
        self.pattern[self.pos] >= '0' &&
        self.pattern[self.pos] <= '9'
      if next_is_decimal {
        if self.unicode {
          raise @errors.SyntaxError(
            message="Invalid regex: invalid decimal escape in character class",
          )
        }
        // Annex B legacy octal: \0 followed by 8 or 9 → NUL (don't consume non-octal digit)
        // \0 followed by 0-7 → parse as 2- or 3-digit octal
        if self.pattern[self.pos] >= '8' {
          '\u{0000}' // NUL; 8/9 left as separate class char
        } else {
          let d1 = self.pattern[self.pos].to_int() - '0'.to_int()
          self.pos += 1
          // Leading digit 0 is in range 0-3, so up to 2 additional octal digits allowed
          let val = if self.pos < self.pattern.length() &&
            self.pattern[self.pos] >= '0' &&
            self.pattern[self.pos] <= '7' {
            let d2 = self.pattern[self.pos].to_int() - '0'.to_int()
            self.pos += 1
            d1 * 8 + d2 // 3-digit octal: \0 d1 d2
          } else {
            d1 // 2-digit octal: \0 d1
          }
          val.unsafe_to_char()
        }
      } else {
        '\u{0000}' // plain \0 = NUL
      }
    }
    'b' => '\u{0008}' // backspace (\b inside [] means backspace, not word boundary)
    _ => escaped
  }
}

///|
fn RegexParser::parse_char_class(self : RegexParser) -> RegexNode raise Error {
  self.pos += 1 // skip '['
  let negated = if self.pos < self.pattern.length() &&
    self.pattern[self.pos] == '^' {
    self.pos += 1
    true
  } else {
    false
  }
  let ranges : Array[(Char, Char)] = []
  while self.pos < self.pattern.length() && self.pattern[self.pos] != ']' {
    let ch = self.pattern[self.pos]
    let start = if ch == '\\' {
      self.pos += 1
      if self.pos >= self.pattern.length() {
        raise @errors.SyntaxError(
          message="Invalid regex: unterminated character class",
        )
      }
      let escaped = self.pattern[self.pos]
      self.pos += 1
      // Handle character class shortcuts inside []
      match escaped {
        'd' => {
          ranges.push(('0', '9'))
          continue
        }
        'w' => {
          ranges.push(('a', 'z'))
          ranges.push(('A', 'Z'))
          ranges.push(('0', '9'))
          ranges.push(('_', '_'))
          continue
        }
        's' => {
          ranges.push((' ', ' '))
          ranges.push(('\t', '\t'))
          ranges.push(('\n', '\n'))
          ranges.push(('\r', '\r'))
          continue
        }
        _ => self.parse_class_single_escape(escaped)
      }
    } else {
      self.pos += 1
      ch
    }
    // Check for range (e.g., a-z)
    if self.pos + 1 < self.pattern.length() &&
      self.pattern[self.pos] == '-' &&
      self.pattern[self.pos + 1] != ']' {
      self.pos += 1 // skip '-'
      let end_ch = if self.pattern[self.pos] == '\\' {
        self.pos += 1
        if self.pos >= self.pattern.length() {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated character class",
          )
        }
        let esc = self.pattern[self.pos]
        self.pos += 1
        self.parse_class_single_escape(esc)
      } else {
        let c = self.pattern[self.pos]
        self.pos += 1
        c
      }
      if start > end_ch {
        raise @errors.SyntaxError(
          message="Invalid regex: range out of order in character class",
        )
      }
      ranges.push((start, end_ch))
    } else {
      ranges.push((start, start))
    }
  }
  if self.pos < self.pattern.length() {
    self.pos += 1 // skip ']'
  } else {
    raise @errors.SyntaxError(
      message="Invalid regex: unterminated character class",
    )
  }
  CharClass(ranges, negated)
}

///|
fn hex_digit_value(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn is_hex_digit(c : Char) -> Bool {
  hex_digit_value(c) >= 0
}

///|
/// Parse a Unicode escape sequence (\uXXXX or \u{XXXXX}) from self.pattern
/// starting at self.pos (which should point just past the 'u').
/// Returns the decoded character and advances self.pos past the escape.
fn RegexParser::parse_unicode_escape_in_name(
  self : RegexParser,
) -> Char raise Error {
  if self.pos < self.pattern.length() && self.pattern[self.pos] == '{' {
    // \u{XXXXX} extended form
    self.pos += 1
    let mut cp = 0
    let mut count = 0
    while self.pos < self.pattern.length() &&
          is_hex_digit(self.pattern[self.pos]) {
      cp = cp * 16 + hex_digit_value(self.pattern[self.pos])
      self.pos += 1
      count += 1
    }
    if count == 0 ||
      count > 6 ||
      self.pos >= self.pattern.length() ||
      self.pattern[self.pos] != '}' {
      raise @errors.SyntaxError(
        message="Invalid regex: invalid Unicode escape in group name",
      )
    }
    self.pos += 1 // skip '}'
    if cp > 0x10FFFF {
      raise @errors.SyntaxError(
        message="Invalid regex: Unicode code point out of range in group name",
      )
    }
    cp.unsafe_to_char()
  } else {
    // \uXXXX — exactly 4 hex digits
    let mut cp = 0
    for i = 0; i < 4; i = i + 1 {
      if self.pos >= self.pattern.length() ||
        !is_hex_digit(self.pattern[self.pos]) {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid Unicode escape in group name",
        )
      }
      cp = cp * 16 + hex_digit_value(self.pattern[self.pos])
      self.pos += 1
    }
    // Surrogate pair: if high surrogate, check for \uDCxx low surrogate
    if cp >= 0xD800 && cp <= 0xDBFF {
      if self.pos + 5 < self.pattern.length() &&
        self.pattern[self.pos] == '\\' &&
        self.pattern[self.pos + 1] == 'u' {
        let saved = self.pos
        self.pos += 2 // skip \u
        let mut low = 0
        let mut ok = true
        for i = 0; i < 4; i = i + 1 {
          if self.pos >= self.pattern.length() ||
            !is_hex_digit(self.pattern[self.pos]) {
            ok = false
            break
          }
          low = low * 16 + hex_digit_value(self.pattern[self.pos])
          self.pos += 1
        }
        if ok && low >= 0xDC00 && low <= 0xDFFF {
          // Valid surrogate pair — combine
          let combined = (cp - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000
          combined.unsafe_to_char()
        } else {
          // Not a valid low surrogate — backtrack
          self.pos = saved
          cp.unsafe_to_char()
        }
      } else {
        cp.unsafe_to_char()
      }
    } else {
      cp.unsafe_to_char()
    }
  }
}

///|
/// Check if a code point is in a known non-identifier Unicode range
/// (symbols, punctuation, emoji, control, formatting, surrogates).
fn is_non_identifier_codepoint(cp : Int) -> Bool {
  // ASCII non-identifier (handled separately by callers for $, _)
  (cp >= 0x00 && cp <= 0x23) || // Control + space + !"#
  (cp == 0x25 || cp == 0x26) || // %, &
  (cp >= 0x28 && cp <= 0x2F) || // ()*+,-./
  (cp >= 0x3A && cp <= 0x40) || // :;<=>?@
  (cp >= 0x5B && cp <= 0x5E) || // [\]^
  cp == 0x60 || // `
  (cp >= 0x7B && cp <= 0x7F) || // {|}~ DEL
  // C1 controls + Latin-1 punctuation/symbols
  (cp >= 0x80 && cp <= 0xBF) ||
  // General punctuation, super/subscripts, currency, combining marks for symbols
  (cp >= 0x2000 && cp <= 0x20CF) ||
  // Letterlike symbols — mixed; reject the block (overly conservative for ℝ etc.)
  (cp >= 0x2100 && cp <= 0x214F) ||
  // Number forms
  (cp >= 0x2150 && cp <= 0x218F) ||
  // Arrows, math operators, misc technical, control pictures, box drawing,
  // block elements, geometric shapes, misc symbols, dingbats
  (cp >= 0x2190 && cp <= 0x27BF) ||
  // Braille, supplemental arrows, misc math, CJK symbols
  (cp >= 0x2800 && cp <= 0x2BFF) ||
  // Supplemental punctuation
  (cp >= 0x2E00 && cp <= 0x2E7F) ||
  // CJK symbols and punctuation
  (cp >= 0x3000 && cp <= 0x303F) ||
  // Variation selectors
  (cp >= 0xFE00 && cp <= 0xFE0F) ||
  // Half/fullwidth forms (symbols portion)
  (cp >= 0xFF01 && cp <= 0xFF0F) ||
  (cp >= 0xFF1A && cp <= 0xFF20) ||
  (cp >= 0xFF3B && cp <= 0xFF40) ||
  (cp >= 0xFF5B && cp <= 0xFF65) ||
  // Specials
  (cp >= 0xFFF0 && cp <= 0xFFFF) ||
  // Surrogates (invalid as identifiers)
  (cp >= 0xD800 && cp <= 0xDFFF) ||
  // Supplementary: emoji and symbols (U+1F000-1FFFF), except math alphanumerics
  (cp >= 0x1F000 && cp <= 0x1F9FF) ||
  (cp >= 0x1FA00 && cp <= 0x1FFFF) ||
  // Musical symbols, playing cards, mahjong
  (cp >= 0x1F000 && cp <= 0x1F02F) ||
  // Tags
  (cp >= 0xE0000 && cp <= 0xE007F)
}

///|
/// Check if a code point is a combining mark or modifier — valid in
/// ID_Continue but NOT in ID_Start position.
fn is_combining_or_modifier(cp : Int) -> Bool {
  (cp >= 0x0300 && cp <= 0x036F) || // Combining Diacritical Marks
  (cp >= 0x0483 && cp <= 0x0489) || // Cyrillic combining marks
  (
    cp >= 0x0591 &&
    cp <= 0x05C7 &&
    cp != 0x05BF &&
    cp != 0x05C1 &&
    cp != 0x05C2 &&
    cp != 0x05C4 &&
    cp != 0x05C5
  ) || // Hebrew marks (subset)
  (cp >= 0x0610 && cp <= 0x061A) || // Arabic combining
  (cp >= 0x064B && cp <= 0x065F) || // Arabic marks
  (cp >= 0x0670 && cp == 0x0670) || // Arabic superscript alef
  (cp >= 0x06D6 && cp <= 0x06ED) || // Arabic marks
  (cp >= 0x0730 && cp <= 0x074A) || // Syriac marks
  (cp >= 0x07A6 && cp <= 0x07B0) || // Thaana marks
  (cp >= 0x07EB && cp <= 0x07F3) || // NKo combining
  (cp >= 0x0816 && cp <= 0x0823) || // Samaritan marks
  (cp >= 0x0825 && cp <= 0x0827) || // Samaritan marks
  (cp >= 0x0829 && cp <= 0x082D) || // Samaritan marks
  (cp >= 0x0859 && cp <= 0x085B) || // Mandaic marks
  (cp >= 0x0900 && cp <= 0x0903) || // Devanagari marks
  (cp >= 0x093A && cp <= 0x094F) || // Devanagari vowel marks
  (cp >= 0x0951 && cp <= 0x0957) || // Devanagari stress marks
  (cp >= 0x0962 && cp <= 0x0963) || // Devanagari vowel signs
  (cp >= 0x0981 && cp <= 0x0983) || // Bengali marks
  (cp >= 0x09BE && cp <= 0x09CD) || // Bengali vowel marks
  (cp >= 0x0A01 && cp <= 0x0A03) || // Gurmukhi marks
  (cp >= 0x0A3C && cp <= 0x0A4D) || // Gurmukhi marks
  (cp >= 0x0B01 && cp <= 0x0B03) || // Oriya marks
  (cp >= 0x0B3C && cp <= 0x0B4D) || // Oriya marks
  (cp >= 0x0B82 && cp == 0x0B82) || // Tamil mark
  (cp >= 0x0BBE && cp <= 0x0BCD) || // Tamil vowel marks
  (cp >= 0x0C00 && cp <= 0x0C04) || // Telugu marks
  (cp >= 0x0C3E && cp <= 0x0C4D) || // Telugu vowel marks
  (cp >= 0x0C82 && cp <= 0x0C83) || // Kannada marks
  (cp >= 0x0CBC && cp <= 0x0CCD) || // Kannada marks
  (cp >= 0x0D00 && cp <= 0x0D03) || // Malayalam marks
  (cp >= 0x0D3B && cp <= 0x0D4D) || // Malayalam vowel marks
  (cp >= 0x0DCA && cp <= 0x0DDF) || // Sinhala marks
  (cp >= 0x0E31 && cp == 0x0E31) || // Thai mark
  (cp >= 0x0E34 && cp <= 0x0E3A) || // Thai vowel marks
  (cp >= 0x0E47 && cp <= 0x0E4E) || // Thai marks
  (cp >= 0x0EB1 && cp == 0x0EB1) || // Lao mark
  (cp >= 0x0EB4 && cp <= 0x0EBC) || // Lao vowel marks
  (cp >= 0x0EC8 && cp <= 0x0ECD) || // Lao marks
  (cp >= 0x0F18 && cp <= 0x0F19) || // Tibetan marks
  (cp >= 0x0F35 && cp <= 0x0F39) || // Tibetan marks
  (cp >= 0x0F71 && cp <= 0x0F84) || // Tibetan vowel marks
  (cp >= 0x0F86 && cp <= 0x0F87) || // Tibetan marks
  (cp >= 0x0F8D && cp <= 0x0FBC) || // Tibetan subjoined
  (cp >= 0x102B && cp <= 0x103E) || // Myanmar combining
  (cp >= 0x1056 && cp <= 0x1059) || // Myanmar marks
  (cp >= 0x105E && cp <= 0x1060) || // Myanmar marks
  (cp >= 0x1062 && cp <= 0x1064) || // Myanmar marks
  (cp >= 0x1067 && cp <= 0x106D) || // Myanmar marks
  (cp >= 0x1071 && cp <= 0x1074) || // Myanmar marks
  (cp >= 0x1082 && cp <= 0x108D) || // Myanmar marks
  (cp >= 0x135D && cp <= 0x135F) || // Ethiopic combining
  (cp >= 0x1712 && cp <= 0x1714) || // Tagalog marks
  (cp >= 0x1732 && cp <= 0x1734) || // Hanunoo marks
  (cp >= 0x17B4 && cp <= 0x17D3) || // Khmer marks
  (cp >= 0x180B && cp <= 0x180D) || // Mongolian marks
  (cp >= 0x1920 && cp <= 0x192B) || // Limbu marks
  (cp >= 0x1930 && cp <= 0x193B) || // Limbu marks
  (cp >= 0x1A17 && cp <= 0x1A1B) || // Buginese marks
  (cp >= 0x1A55 && cp <= 0x1A5E) || // Tai Tham marks
  (cp >= 0x1A60 && cp <= 0x1A7C) || // Tai Tham marks
  (cp >= 0x1AB0 && cp <= 0x1ACE) || // Combining Diacritical Marks Extended
  (cp >= 0x1B00 && cp <= 0x1B04) || // Balinese marks
  (cp >= 0x1B34 && cp <= 0x1B44) || // Balinese marks
  (cp >= 0x1B80 && cp <= 0x1B82) || // Sundanese marks
  (cp >= 0x1BA1 && cp <= 0x1BAD) || // Sundanese marks
  (cp >= 0x1BE6 && cp <= 0x1BF3) || // Batak marks
  (cp >= 0x1C24 && cp <= 0x1C37) || // Lepcha marks
  (cp >= 0x1CD0 && cp <= 0x1CE8) || // Vedic extensions
  (cp >= 0x1CF7 && cp <= 0x1CF9) || // Vedic marks
  (cp >= 0x1DC0 && cp <= 0x1DFF) || // Combining Diacritical Marks Supplement
  (cp >= 0x20D0 && cp <= 0x20F0) || // Combining Marks for Symbols
  (cp >= 0xFE20 && cp <= 0xFE2F) // Combining Half Marks
}

///|
/// Approximate Unicode ID_Start check for regex group names.
/// Uses a blocklist approach: accepts $, _, ASCII letters, and any Unicode
/// code point not in known non-identifier or combining-mark ranges.
fn is_id_start_char(c : Char) -> Bool {
  let cp = c.to_int()
  c == '_' ||
  c == '$' ||
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (
    cp >= 0xC0 &&
    !is_non_identifier_codepoint(cp) &&
    !is_combining_or_modifier(cp)
  )
}

///|
/// Approximate Unicode ID_Continue check for regex group names.
/// Same as ID_Start plus digits, combining marks, and ZWNJ/ZWJ.
fn is_id_continue_char(c : Char) -> Bool {
  let cp = c.to_int()
  is_id_start_char(c) ||
  (c >= '0' && c <= '9') ||
  is_combining_or_modifier(cp) ||
  cp == 0x200C || // ZWNJ
  cp == 0x200D // ZWJ
}

///|
priv struct RegexNameSummary {
  names : @set.Set[String]
}

///|
fn RegexNameSummary::RegexNameSummary() -> RegexNameSummary {
  { names: @set.Set::default() }
}

///|
fn regex_name_summary_intersects(
  left : RegexNameSummary,
  right : RegexNameSummary,
) -> Bool {
  !left.names.is_disjoint(right.names)
}

///|
fn regex_name_summary_union_into(
  target : RegexNameSummary,
  source : RegexNameSummary,
) -> Unit {
  for name in source.names {
    target.names.add(name)
  }
}

///|
fn regex_raise_duplicate_group_name() -> Unit raise Error {
  raise @errors.SyntaxError(message="Invalid regex: duplicate group name")
}

///|
fn regex_name_summary_for_sequence(
  nodes : Array[RegexNode],
) -> RegexNameSummary raise Error {
  let summary = RegexNameSummary()
  for node in nodes {
    let child = regex_name_summary_for_node(node)
    if regex_name_summary_intersects(summary, child) {
      regex_raise_duplicate_group_name()
    }
    regex_name_summary_union_into(summary, child)
  }
  summary
}

///|
fn regex_name_summary_for_node(
  node : RegexNode,
) -> RegexNameSummary raise Error {
  match node {
    Group(children, _, Some(name)) => {
      let summary = regex_name_summary_for_sequence(children)
      if summary.names.contains(name) {
        regex_raise_duplicate_group_name()
      }
      summary.names.add(name)
      summary
    }
    Group(children, _, None) | Lookahead(children, _) =>
      regex_name_summary_for_sequence(children)
    Sequence(nodes) => regex_name_summary_for_sequence(nodes)
    Alternation(left, right) => {
      let summary = RegexNameSummary()
      regex_name_summary_union_into(
        summary,
        regex_name_summary_for_sequence(left),
      )
      regex_name_summary_union_into(
        summary,
        regex_name_summary_for_sequence(right),
      )
      summary
    }
    Quantified(inner, _, _, _) => regex_name_summary_for_node(inner)
    Literal(_)
    | Dot
    | CharClass(_, _)
    | Anchor(_)
    | WordBoundary(_)
    | Backreference(_)
    | NamedBackreference(_)
    | DuplicateNamedBackreference(_) => RegexNameSummary()
  }
}

///|
fn validate_duplicate_named_group_names(node : RegexNode) -> Unit raise Error {
  ignore(regex_name_summary_for_node(node))
}

///|
fn RegexParser::parse_group(self : RegexParser) -> RegexNode raise Error {
  self.pos += 1 // skip '('
  // Check for special group syntax
  if self.pos < self.pattern.length() && self.pattern[self.pos] == '?' {
    if self.pos + 1 < self.pattern.length() {
      let next = self.pattern[self.pos + 1]
      if next == ':' {
        // Non-capturing group (?:...)
        self.pos += 2
        let inner = self.parse_alternation()
        if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
          self.pos += 1
        } else {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated non-capturing group",
          )
        }
        let children = match inner {
          Sequence(nodes) => nodes
          _ => [inner]
        }
        return Group(children, 0, None)
      } else if next == '<' {
        // Named capture group (?<name>...) or lookbehind (not supported)
        if self.pos + 2 < self.pattern.length() {
          let after_lt = self.pattern[self.pos + 2]
          if after_lt == '=' || after_lt == '!' {
            raise @errors.SyntaxError(
              message="Invalid regex: lookbehind assertions are not supported",
            )
          }
        }
        // Parse group name, interpreting \uXXXX / \u{XXXXX} escapes
        self.pos += 2 // skip '?<'
        if self.pos >= self.pattern.length() {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated group name",
          )
        }
        let name_buf = StringBuilder::new()
        // First char: must be ID_Start (or \u escape that resolves to ID_Start)
        let first = if self.pattern[self.pos] == '\\' &&
          self.pos + 1 < self.pattern.length() &&
          self.pattern[self.pos + 1] == 'u' {
          self.pos += 2 // skip \u
          self.parse_unicode_escape_in_name()
        } else {
          let c = self.pattern[self.pos]
          self.pos += 1
          c
        }
        if !is_id_start_char(first) {
          raise @errors.SyntaxError(message="Invalid regex: invalid group name")
        }
        name_buf.write_char(first)
        // Subsequent chars: ID_Continue or \u escape
        while self.pos < self.pattern.length() && self.pattern[self.pos] != '>' {
          let c = if self.pattern[self.pos] == '\\' &&
            self.pos + 1 < self.pattern.length() &&
            self.pattern[self.pos + 1] == 'u' {
            self.pos += 2 // skip \u
            self.parse_unicode_escape_in_name()
          } else {
            let ch = self.pattern[self.pos]
            self.pos += 1
            ch
          }
          if is_id_continue_char(c) {
            name_buf.write_char(c)
          } else {
            raise @errors.SyntaxError(
              message="Invalid regex: invalid group name",
            )
          }
        }
        if self.pos >= self.pattern.length() || self.pattern[self.pos] != '>' {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated group name",
          )
        }
        let name = name_buf.to_string()
        self.pos += 1 // skip '>'
        self.group_count += 1
        let group_idx = self.group_count
        if !self.group_names.contains(name) {
          self.group_names[name] = group_idx
        }
        self.group_name_entries.push((name, group_idx))
        let inner = self.parse_alternation()
        if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
          self.pos += 1
        } else {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated named capture group",
          )
        }
        let children = match inner {
          Sequence(nodes) => nodes
          _ => [inner]
        }
        return Group(children, group_idx, Some(name))
      } else if next == '=' {
        // Positive lookahead (?=...)
        self.pos += 2
        let inner = self.parse_alternation()
        if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
          self.pos += 1
        } else {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated lookahead",
          )
        }
        let children = match inner {
          Sequence(nodes) => nodes
          _ => [inner]
        }
        return Lookahead(children, true)
      } else if next == '!' {
        // Negative lookahead (?!...)
        self.pos += 2
        let inner = self.parse_alternation()
        if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
          self.pos += 1
        } else {
          raise @errors.SyntaxError(
            message="Invalid regex: unterminated lookahead",
          )
        }
        let children = match inner {
          Sequence(nodes) => nodes
          _ => [inner]
        }
        return Lookahead(children, false)
      }
    }
  }
  // Capturing group
  self.group_count += 1
  let group_idx = self.group_count
  let inner = self.parse_alternation()
  if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
    self.pos += 1
  } else {
    raise @errors.SyntaxError(
      message="Invalid regex: unterminated capturing group",
    )
  }
  let children = match inner {
    Sequence(nodes) => nodes
    _ => [inner]
  }
  Group(children, group_idx, None)
}

///|
fn RegexParser::parse_quantifier(
  self : RegexParser,
  node : RegexNode,
) -> RegexNode raise Error {
  if self.pos >= self.pattern.length() {
    return node
  }
  // Don't apply quantifiers to anchors or word boundaries
  match node {
    Anchor(_) | WordBoundary(_) => return node
    _ => ()
  }
  let ch = self.pattern[self.pos]
  match ch {
    '*' => {
      self.pos += 1
      let greedy = self.check_greedy()
      Quantified(node, 0, None, greedy)
    }
    '+' => {
      self.pos += 1
      let greedy = self.check_greedy()
      Quantified(node, 1, None, greedy)
    }
    '?' => {
      self.pos += 1
      let greedy = self.check_greedy()
      Quantified(node, 0, Some(1), greedy)
    }
    '{' => {
      let saved = self.pos
      self.pos += 1
      let min = self.parse_int()
      match min {
        Some(n) =>
          if self.pos < self.pattern.length() && self.pattern[self.pos] == '}' {
            self.pos += 1
            let greedy = self.check_greedy()
            Quantified(node, n, Some(n), greedy)
          } else if self.pos < self.pattern.length() &&
            self.pattern[self.pos] == ',' {
            self.pos += 1
            if self.pos < self.pattern.length() && self.pattern[self.pos] == '}' {
              self.pos += 1
              let greedy = self.check_greedy()
              Quantified(node, n, None, greedy)
            } else {
              let max = self.parse_int()
              match max {
                Some(m) =>
                  if self.pos < self.pattern.length() &&
                    self.pattern[self.pos] == '}' {
                    if m < n {
                      raise @errors.SyntaxError(
                        message="Invalid regex: numbers out of order in quantifier",
                      )
                    }
                    self.pos += 1
                    let greedy = self.check_greedy()
                    Quantified(node, n, Some(m), greedy)
                  } else {
                    self.pos = saved
                    node
                  }
                None => {
                  self.pos = saved
                  node
                }
              }
            }
          } else {
            self.pos = saved
            node
          }
        None => {
          self.pos = saved
          node
        }
      }
    }
    _ => node
  }
}

///|
fn RegexParser::check_greedy(self : RegexParser) -> Bool {
  if self.pos < self.pattern.length() && self.pattern[self.pos] == '?' {
    self.pos += 1
    false
  } else {
    true
  }
}

///|
fn RegexParser::parse_int(self : RegexParser) -> Int? {
  let start = self.pos
  while self.pos < self.pattern.length() &&
        self.pattern[self.pos] >= '0' &&
        self.pattern[self.pos] <= '9' {
    self.pos += 1
  }
  if self.pos == start {
    return None
  }
  let mut result = 0
  for i = start; i < self.pos; i = i + 1 {
    result = result * 10 + (self.pattern[i].to_int() - '0'.to_int())
  }
  Some(result)
}

// ---- Regex Matcher ----

///|
struct RegexMatch {
  start : Int
  end_ : Int
  captures : Array[String?]
  capture_versions : Array[Int]
  group_names : Array[(String, Int)]
}

///|
priv struct RegexStateSnapshot {
  captures : Array[String?]
  capture_versions : Array[Int]
  capture_epoch : Int
}

///|
priv struct RegexExecState {
  captures : Array[String?]
  capture_versions : Array[Int]
  mut capture_epoch : Int
}

///|
priv struct QuantifiedMatchState {
  pos : Int
  snapshot : RegexStateSnapshot
}

///|
fn RegexExecState::RegexExecState(num_groups : Int) -> RegexExecState {
  {
    captures: Array::make(num_groups, None),
    capture_versions: Array::make(num_groups, 0),
    capture_epoch: 0,
  }
}

///|
fn RegexExecState::snapshot(self : RegexExecState) -> RegexStateSnapshot {
  {
    captures: self.captures.copy(),
    capture_versions: self.capture_versions.copy(),
    capture_epoch: self.capture_epoch,
  }
}

///|
fn RegexExecState::restore(
  self : RegexExecState,
  saved : RegexStateSnapshot,
) -> Unit {
  for i in 0..<self.captures.length() {
    self.captures[i] = saved.captures[i]
  }
  for i in 0..<self.capture_versions.length() {
    self.capture_versions[i] = saved.capture_versions[i]
  }
  self.capture_epoch = saved.capture_epoch
}

///|
fn RegexExecState::set_capture(
  self : RegexExecState,
  group_idx : Int,
  captured : String,
) -> Unit {
  if group_idx > 0 && group_idx <= self.captures.length() {
    self.capture_epoch += 1
    self.captures[group_idx - 1] = Some(captured)
    self.capture_versions[group_idx - 1] = self.capture_epoch
  }
}

///|
fn RegexExecState::clear_capture(
  self : RegexExecState,
  group_idx : Int,
) -> Unit {
  if group_idx > 0 && group_idx <= self.captures.length() {
    self.captures[group_idx - 1] = None
    self.capture_versions[group_idx - 1] = 0
  }
}

///|
fn is_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// ES spec line terminators: LF, CR, LS (U+2028), PS (U+2029)
fn is_line_terminator(c : Char) -> Bool {
  c == '\n' || c == '\r' || c.to_int() == 0x2028 || c.to_int() == 0x2029
}

///|
fn char_eq_icase(a : Char, b : Char, icase : Bool) -> Bool {
  if a == b {
    return true
  }
  if !icase {
    return false
  }
  // Compare lowercased
  let al = if a >= 'A' && a <= 'Z' {
    (a.to_int() + 32).unsafe_to_char()
  } else {
    a
  }
  let bl = if b >= 'A' && b <= 'Z' {
    (b.to_int() + 32).unsafe_to_char()
  } else {
    b
  }
  al == bl
}

///|
fn match_char_class_icase(
  ch : Char,
  ranges : Array[(Char, Char)],
  negated : Bool,
  icase : Bool,
) -> Bool {
  let c = if icase {
    // Lowercase for range comparison
    if ch >= 'A' && ch <= 'Z' {
      (ch.to_int() + 32).unsafe_to_char()
    } else {
      ch
    }
  } else {
    ch
  }
  let mut matched = false
  for range in ranges {
    let (lo, hi) = range
    let lo2 = if icase && lo >= 'A' && lo <= 'Z' {
      (lo.to_int() + 32).unsafe_to_char()
    } else {
      lo
    }
    let hi2 = if icase && hi >= 'A' && hi <= 'Z' {
      (hi.to_int() + 32).unsafe_to_char()
    } else {
      hi
    }
    if c.to_int() >= lo2.to_int() && c.to_int() <= hi2.to_int() {
      matched = true
      break
    }
    // Also check original (non-lowered) char against original range for non-alpha ranges
    if icase && ch.to_int() >= lo.to_int() && ch.to_int() <= hi.to_int() {
      matched = true
      break
    }
  }
  if negated {
    !matched
  } else {
    matched
  }
}

///|
/// Regex flags struct for passing multiple flags through the matcher
priv struct RegexFlags {
  icase : Bool
  multiline : Bool
  dot_all : Bool
  sticky : Bool
}

///|
fn match_backreference_capture(
  captured : String,
  input : Array[Char],
  pos : Int,
  flags : RegexFlags,
) -> Int? {
  let cap_chars = captured.to_array()
  if pos + cap_chars.length() > input.length() {
    return None
  }
  for i = 0; i < cap_chars.length(); i = i + 1 {
    if !char_eq_icase(input[pos + i], cap_chars[i], flags.icase) {
      return None
    }
  }
  Some(pos + cap_chars.length())
}

///|
fn match_duplicate_named_backreference(
  indices : Array[Int],
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  flags : RegexFlags,
) -> Int? {
  let mut selected_idx = -1
  let mut selected_version = -1
  for group_num in indices {
    let cap_idx = group_num - 1
    if cap_idx >= 0 && cap_idx < state.captures.length() {
      match state.captures[cap_idx] {
        Some(_) => {
          let version = state.capture_versions[cap_idx]
          if version > selected_version {
            selected_version = version
            selected_idx = cap_idx
          }
        }
        None => ()
      }
    }
  }
  if selected_idx >= 0 {
    match state.captures[selected_idx] {
      Some(captured) => match_backreference_capture(captured, input, pos, flags)
      None => Some(pos)
    }
  } else {
    Some(pos)
  }
}

///|
fn regex_exec_single(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  flags : RegexFlags,
) -> Int? {
  // Match a single non-sequence node
  match node {
    Literal(ch) =>
      if pos < input.length() && char_eq_icase(input[pos], ch, flags.icase) {
        Some(pos + 1)
      } else {
        None
      }
    Dot =>
      if pos < input.length() {
        if flags.dot_all || !is_line_terminator(input[pos]) {
          Some(pos + 1)
        } else {
          None
        }
      } else {
        None
      }
    CharClass(ranges, negated) =>
      if pos < input.length() &&
        match_char_class_icase(input[pos], ranges, negated, flags.icase) {
        Some(pos + 1)
      } else {
        None
      }
    Anchor(kind) =>
      match kind {
        Start =>
          if pos == 0 {
            Some(pos)
          } else if flags.multiline &&
            pos > 0 &&
            is_line_terminator(input[pos - 1]) &&
            // CRLF is a single line terminator — ^ matches after \n, not between \r and \n
            !(input[pos - 1] == '\r' &&
            pos < input.length() &&
            input[pos] == '\n') {
            Some(pos)
          } else {
            None
          }
        End =>
          if pos == input.length() {
            Some(pos)
          } else if flags.multiline &&
            pos < input.length() &&
            is_line_terminator(input[pos]) &&
            // CRLF is a single line terminator — $ matches before \r, not between \r and \n
            !(input[pos] == '\n' && pos > 0 && input[pos - 1] == '\r') {
            Some(pos)
          } else {
            None
          }
      }
    WordBoundary(is_boundary) => {
      let left_word = pos > 0 && is_word_char(input[pos - 1])
      let right_word = pos < input.length() && is_word_char(input[pos])
      let at_boundary = left_word != right_word
      if is_boundary == at_boundary {
        Some(pos)
      } else {
        None
      }
    }
    Group(children, group_idx, _) => {
      let result = match_sequence(children, 0, input, pos, state, flags)
      match result {
        Some(end_pos) => {
          if group_idx > 0 && group_idx <= state.captures.length() {
            let buf = StringBuilder::new()
            for i = pos; i < end_pos; i = i + 1 {
              buf.write_char(input[i])
            }
            state.set_capture(group_idx, buf.to_string())
          }
          Some(end_pos)
        }
        None => None
      }
    }
    Alternation(left, right) => {
      let saved = state.snapshot()
      let left_result = match_sequence(left, 0, input, pos, state, flags)
      match left_result {
        Some(_) => left_result
        None => {
          state.restore(saved)
          let right_result = match_sequence(right, 0, input, pos, state, flags)
          match right_result {
            Some(_) => right_result
            None => {
              state.restore(saved)
              None
            }
          }
        }
      }
    }
    Sequence(nodes) => match_sequence(nodes, 0, input, pos, state, flags)
    Quantified(inner, min, max, greedy) => {
      // Standalone quantified without continuation — just match max
      let saved = state.snapshot()
      let states = collect_quantified_states(
        inner, input, pos, state, max, flags,
      )
      if states.length() - 1 < min {
        state.restore(saved)
        return None
      }
      let selected = if greedy {
        states[states.length() - 1]
      } else {
        states[min]
      }
      state.restore(selected.snapshot)
      Some(selected.pos)
    }
    Lookahead(children, positive) => {
      let result = match_sequence(children, 0, input, pos, state, flags)
      match (result, positive) {
        (Some(_), true) => Some(pos) // Positive lookahead: matched, don't consume
        (None, false) => Some(pos) // Negative lookahead: didn't match, success
        _ => None
      }
    }
    Backreference(group_num) =>
      if group_num - 1 < state.captures.length() {
        match state.captures[group_num - 1] {
          Some(captured) =>
            match_backreference_capture(captured, input, pos, flags)
          None => Some(pos) // Unmatched group: matches empty string
        }
      } else {
        Some(pos) // Invalid group: matches empty string
      }
    DuplicateNamedBackreference(indices) =>
      match_duplicate_named_backreference(indices, input, pos, state, flags)
    NamedBackreference(_) => None // Should be resolved before execution
  }
}

///|
fn regex_exec(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  flags : RegexFlags,
) -> Int? {
  match node {
    Sequence(nodes) => match_sequence(nodes, 0, input, pos, state, flags)
    _ => regex_exec_single(node, input, pos, state, flags)
  }
}

///|
fn clear_captures_for_node(node : RegexNode, state : RegexExecState) -> Unit {
  match node {
    Group(children, group_idx, _) => {
      state.clear_capture(group_idx)
      for child in children {
        clear_captures_for_node(child, state)
      }
    }
    Sequence(nodes) | Lookahead(nodes, _) =>
      for child in nodes {
        clear_captures_for_node(child, state)
      }
    Alternation(left, right) => {
      for child in left {
        clear_captures_for_node(child, state)
      }
      for child in right {
        clear_captures_for_node(child, state)
      }
    }
    Quantified(inner, _, _, _) => clear_captures_for_node(inner, state)
    Literal(_)
    | Dot
    | CharClass(_, _)
    | Anchor(_)
    | WordBoundary(_)
    | Backreference(_)
    | NamedBackreference(_)
    | DuplicateNamedBackreference(_) => ()
  }
}

///|
/// Check if a regex node is a simple leaf that always advances exactly 1 char
/// and never sets captures. Used for fast-path quantified matching.
fn is_simple_quantified_inner(node : RegexNode) -> Bool {
  match node {
    Literal(_) | Dot | CharClass(_, _) => true
    _ => false
  }
}

///|
/// Returns true if the first character of this node is statically bounded
/// (we can predict which chars can match and skip non-matching positions).
fn has_first_char_bound(node : RegexNode) -> Bool {
  match node {
    Literal(_) | CharClass(_, false) => true
    Dot | CharClass(_, true) => false
    Anchor(_)
    | WordBoundary(_)
    | Backreference(_)
    | NamedBackreference(_)
    | DuplicateNamedBackreference(_) => false
    Quantified(inner, min, _, _) => min > 0 && has_first_char_bound(inner)
    Group(children, _, _) | Lookahead(children, _) =>
      children.length() > 0 && has_first_char_bound(children[0])
    Sequence(nodes) => nodes.length() > 0 && has_first_char_bound(nodes[0])
    Alternation(_, _) => false
  }
}

///|
/// Scan forward from `pos` to find the next position where `node`'s first
/// character could match. Only valid when has_first_char_bound(node) is true.
/// Returns input.length() when no candidate is found.
fn advance_to_candidate(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  flags : RegexFlags,
) -> Int {
  match node {
    Literal(ch) => {
      let mut i = pos
      while i < input.length() {
        if char_eq_icase(input[i], ch, flags.icase) {
          return i
        }
        i += 1
      }
      i
    }
    CharClass(ranges, false) => {
      let mut i = pos
      while i < input.length() {
        let ch = input[i]
        for k in 0..<ranges.length() {
          let (lo, hi) = ranges[k]
          if ch.to_int() >= lo.to_int() && ch.to_int() <= hi.to_int() {
            return i
          }
          if flags.icase {
            let lowered = if ch >= 'A' && ch <= 'Z' {
              (ch.to_int() + 32).unsafe_to_char()
            } else {
              ch
            }
            let lowered_lo = if lo >= 'A' && lo <= 'Z' {
              (lo.to_int() + 32).unsafe_to_char()
            } else {
              lo
            }
            let lowered_hi = if hi >= 'A' && hi <= 'Z' {
              (hi.to_int() + 32).unsafe_to_char()
            } else {
              hi
            }
            if lowered.to_int() >= lowered_lo.to_int() &&
              lowered.to_int() <= lowered_hi.to_int() {
              return i
            }
          }
        }
        i += 1
      }
      i
    }
    Group(children, _, _) | Lookahead(children, _) =>
      advance_to_candidate(children[0], input, pos, flags)
    Sequence(nodes) => advance_to_candidate(nodes[0], input, pos, flags)
    Quantified(inner, _, _, _) => advance_to_candidate(inner, input, pos, flags)
    _ => pos
  }
}

///|
/// Count consecutive matches of a simple quantified inner node starting from pos.
/// Does NOT allocate intermediate state arrays (unlike collect_quantified_states).
/// Returns the number of consecutive matches found.
fn quantified_match_count(
  inner : RegexNode,
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  max : Int?,
  flags : RegexFlags,
) -> Int {
  let mut current = pos
  let mut count = 0
  while true {
    match max {
      Some(m) => if count >= m { break }
      None => ()
    }
    match regex_exec_single(inner, input, current, state, flags) {
      Some(next) => {
        if next == current {
          break
        }
        count += 1
        current = next
      }
      None => break
    }
  }
  count
}

///|
fn collect_quantified_states(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  max : Int?,
  flags : RegexFlags,
) -> Array[QuantifiedMatchState] {
  let states : Array[QuantifiedMatchState] = [
    { pos, snapshot: state.snapshot() },
  ]
  let mut current = pos
  let mut count = 0
  while true {
    match max {
      Some(m) => if count >= m { break }
      None => ()
    }
    let before = state.snapshot()
    clear_captures_for_node(node, state)
    match regex_exec_single(node, input, current, state, flags) {
      Some(next) => {
        if next == current {
          states[states.length() - 1] = {
            pos: current,
            snapshot: state.snapshot(),
          }
          break
        }
        count += 1
        current = next
        states.push({ pos: current, snapshot: state.snapshot() })
      }
      None => {
        state.restore(before)
        break
      }
    }
  }
  states
}

///|
fn match_sequence_candidates(
  nodes : Array[RegexNode],
  idx : Int,
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  flags : RegexFlags,
) -> Array[QuantifiedMatchState] {
  if idx >= nodes.length() {
    return [{ pos, snapshot: state.snapshot() }]
  }
  let saved = state.snapshot()
  // Fast-path for Quantified with simple inner node (Literal, Dot, CharClass).
  // These always advance exactly 1 char per match and never set captures.
  // Scan forward once to find max match count, then try positions in order
  // without allocating large intermediate state arrays.
  match nodes[idx] {
    Quantified(inner, min, max, greedy) if is_simple_quantified_inner(inner) => {
      let count = quantified_match_count(inner, input, pos, state, max, flags)
      if count < min {
        state.restore(saved)
        return []
      }
      let results : Array[QuantifiedMatchState] = []
      if greedy {
        for i = count; i >= min; i = i - 1 {
          let rest = match_sequence_candidates(
            nodes,
            idx + 1,
            input,
            pos + i,
            state,
            flags,
          )
          if !rest.is_empty() {
            for r in rest {
              results.push(r)
            }
            break
          }
        }
      } else {
        for i = min; i <= count; i = i + 1 {
          let rest = match_sequence_candidates(
            nodes,
            idx + 1,
            input,
            pos + i,
            state,
            flags,
          )
          if !rest.is_empty() {
            for r in rest {
              results.push(r)
            }
            break
          }
        }
      }
      state.restore(saved)
      return results
    }
    _ => ()
  }
  let candidates = match_node_candidates(nodes[idx], input, pos, state, flags)
  let results : Array[QuantifiedMatchState] = []
  for candidate in candidates {
    state.restore(candidate.snapshot)
    let rest = match_sequence_candidates(
      nodes,
      idx + 1,
      input,
      candidate.pos,
      state,
      flags,
    )
    for result in rest {
      results.push(result)
    }
    state.restore(saved)
  }
  state.restore(saved)
  results
}

///|
fn match_node_candidates(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  flags : RegexFlags,
) -> Array[QuantifiedMatchState] {
  let saved = state.snapshot()
  let results : Array[QuantifiedMatchState] = []
  match node {
    Group(children, group_idx, _) => {
      let inner_candidates = match_sequence_candidates(
        children, 0, input, pos, state, flags,
      )
      for candidate in inner_candidates {
        state.restore(candidate.snapshot)
        if group_idx > 0 && group_idx <= state.captures.length() {
          let buf = StringBuilder::new()
          for i = pos; i < candidate.pos; i = i + 1 {
            buf.write_char(input[i])
          }
          state.set_capture(group_idx, buf.to_string())
        }
        results.push({ pos: candidate.pos, snapshot: state.snapshot() })
        state.restore(saved)
      }
    }
    Alternation(left, right) => {
      let left_candidates = match_sequence_candidates(
        left, 0, input, pos, state, flags,
      )
      for candidate in left_candidates {
        results.push(candidate)
      }
      state.restore(saved)
      let right_candidates = match_sequence_candidates(
        right, 0, input, pos, state, flags,
      )
      for candidate in right_candidates {
        results.push(candidate)
      }
    }
    Sequence(children) => {
      let child_candidates = match_sequence_candidates(
        children, 0, input, pos, state, flags,
      )
      for candidate in child_candidates {
        results.push(candidate)
      }
    }
    Quantified(inner, min, max, greedy) => {
      let states = collect_quantified_states(
        inner, input, pos, state, max, flags,
      )
      if states.length() - 1 >= min {
        if greedy {
          for i = states.length() - 1; i >= min; i = i - 1 {
            results.push(states[i])
          }
        } else {
          for i = min; i < states.length(); i = i + 1 {
            results.push(states[i])
          }
        }
      }
    }
    Lookahead(children, positive) => {
      // Lookahead assertions are atomic with respect to the outer sequence:
      // once a positive assertion succeeds, later atoms must not backtrack
      // into the assertion to try another internal alternative. Captures from
      // the first assertion success are still visible to following atoms.
      let assertion_result = match_sequence(
        children, 0, input, pos, state, flags,
      )
      match (assertion_result, positive) {
        (Some(_), true) => results.push({ pos, snapshot: state.snapshot() })
        (None, false) => results.push({ pos, snapshot: saved })
        _ => ()
      }
    }
    Literal(_)
    | Dot
    | CharClass(_, _)
    | Anchor(_)
    | WordBoundary(_)
    | Backreference(_)
    | NamedBackreference(_)
    | DuplicateNamedBackreference(_) =>
      match regex_exec_single(node, input, pos, state, flags) {
        Some(next) => results.push({ pos: next, snapshot: state.snapshot() })
        None => ()
      }
  }
  state.restore(saved)
  results
}

///|
fn match_sequence(
  nodes : Array[RegexNode],
  idx : Int,
  input : Array[Char],
  pos : Int,
  state : RegexExecState,
  flags : RegexFlags,
) -> Int? {
  let saved = state.snapshot()
  let candidates = match_sequence_candidates(
    nodes, idx, input, pos, state, flags,
  )
  if candidates.length() > 0 {
    let candidate = candidates[0]
    state.restore(candidate.snapshot)
    Some(candidate.pos)
  } else {
    state.restore(saved)
    None
  }
}

///|
fn count_groups(node : RegexNode) -> Int {
  match node {
    Literal(_)
    | Dot
    | CharClass(_, _)
    | Anchor(_)
    | WordBoundary(_)
    | Backreference(_)
    | NamedBackreference(_)
    | DuplicateNamedBackreference(_) => 0
    Lookahead(children, _) =>
      children.fold(init=0, fn(acc, child) {
        let cg = count_groups(child)
        if cg > acc {
          cg
        } else {
          acc
        }
      })
    Quantified(inner, _, _, _) => count_groups(inner)
    Group(children, group_idx, _) => {
      let max_child = children.fold(init=0, fn(acc, child) {
        let cg = count_groups(child)
        if cg > acc {
          cg
        } else {
          acc
        }
      })
      if group_idx > max_child {
        group_idx
      } else {
        max_child
      }
    }
    Alternation(left, right) => {
      let lg = left.fold(init=0, fn(acc, n) {
        let g = count_groups(n)
        if g > acc {
          g
        } else {
          acc
        }
      })
      let rg = right.fold(init=0, fn(acc, n) {
        let g = count_groups(n)
        if g > acc {
          g
        } else {
          acc
        }
      })
      if lg > rg {
        lg
      } else {
        rg
      }
    }
    Sequence(nodes) =>
      nodes.fold(init=0, fn(acc, n) {
        let g = count_groups(n)
        if g > acc {
          g
        } else {
          acc
        }
      })
  }
}

// ---- Public API ----

///|
priv struct ParsedRegex {
  node : RegexNode
  num_groups : Int
  group_names : Array[(String, Int)]
}

///|
fn parse_regex(
  pattern : String,
  unicode? : Bool = false,
) -> ParsedRegex raise Error {
  let parser = RegexParser::new(pattern, unicode~)
  let node = parser.parse()
  let num_groups = count_groups(node)
  let names = parser.group_name_entries.copy()
  names.sort_by(fn(a, b) { a.1.compare(b.1) })
  { node, num_groups, group_names: names }
}

///|
fn make_regex_flags(flags : String) -> RegexFlags {
  {
    icase: flags.contains("i"),
    multiline: flags.contains("m"),
    dot_all: flags.contains("s"),
    sticky: flags.contains("y"),
  }
}

///|
pub fn regex_match_at(
  pattern : String,
  flags : String,
  input : String,
  start_pos : Int,
) -> RegexMatch? raise Error {
  let parsed = parse_regex(pattern, unicode=flags.contains("u"))
  let input_chars = input.to_array()
  let rflags = make_regex_flags(flags)
  let state = RegexExecState(parsed.num_groups)
  match regex_exec(parsed.node, input_chars, start_pos, state, rflags) {
    Some(end_pos) =>
      Some({
        start: start_pos,
        end_: end_pos,
        captures: state.captures.copy(),
        capture_versions: state.capture_versions.copy(),
        group_names: parsed.group_names,
      })
    None => None
  }
}

///|
pub fn regex_search(
  pattern : String,
  flags : String,
  input : String,
  start_pos? : Int = 0,
) -> RegexMatch? raise Error {
  let parsed = parse_regex(pattern, unicode=flags.contains("u"))
  let input_chars = input.to_array()
  let rflags = make_regex_flags(flags)
  let is_sticky = flags.contains("y")
  if is_sticky {
    // Sticky flag: only match at the given start_pos (lastIndex)
    if start_pos > input_chars.length() {
      return None
    }
    let state = RegexExecState(parsed.num_groups)
    match regex_exec(parsed.node, input_chars, start_pos, state, rflags) {
      Some(end_pos) =>
        return Some({
          start: start_pos,
          end_: end_pos,
          captures: state.captures.copy(),
          capture_versions: state.capture_versions.copy(),
          group_names: parsed.group_names,
        })
      None => return None
    }
  }
  if has_first_char_bound(parsed.node) {
    let state = RegexExecState(parsed.num_groups)
    let mut i = start_pos
    while i < input_chars.length() {
      i = advance_to_candidate(parsed.node, input_chars, i, rflags)
      if i >= input_chars.length() {
        break
      }
      match regex_exec(parsed.node, input_chars, i, state, rflags) {
        Some(end_pos) =>
          return Some({
            start: i,
            end_: end_pos,
            captures: state.captures.copy(),
            capture_versions: state.capture_versions.copy(),
            group_names: parsed.group_names,
          })
        None => i += 1
      }
    }
    None
  } else {
    let state = RegexExecState(parsed.num_groups)
    for i = start_pos; i <= input_chars.length(); i = i + 1 {
      match regex_exec(parsed.node, input_chars, i, state, rflags) {
        Some(end_pos) =>
          return Some({
            start: i,
            end_: end_pos,
            captures: state.captures.copy(),
            capture_versions: state.capture_versions.copy(),
            group_names: parsed.group_names,
          })
        None => continue
      }
    }
    None
  }
}

///|
pub fn regex_search_all(
  pattern : String,
  flags : String,
  input : String,
) -> Array[RegexMatch] raise Error {
  let parsed = parse_regex(pattern, unicode=flags.contains("u"))
  let input_chars = input.to_array()
  let rflags = make_regex_flags(flags)
  let results : Array[RegexMatch] = []
  if has_first_char_bound(parsed.node) && !rflags.sticky {
    let mut i = 0
    while i <= input_chars.length() {
      i = advance_to_candidate(parsed.node, input_chars, i, rflags)
      if i >= input_chars.length() {
        break
      }
      let state = RegexExecState(parsed.num_groups)
      match regex_exec(parsed.node, input_chars, i, state, rflags) {
        Some(end_pos) => {
          results.push({
            start: i,
            end_: end_pos,
            captures: state.captures.copy(),
            capture_versions: state.capture_versions.copy(),
            group_names: parsed.group_names,
          })
          if end_pos == i {
            i += 1
          } else {
            i = end_pos
          }
        }
        None => i += 1
      }
    }
  } else {
    let mut i = 0
    while i <= input_chars.length() {
      let state = RegexExecState(parsed.num_groups)
      match regex_exec(parsed.node, input_chars, i, state, rflags) {
        Some(end_pos) => {
          results.push({
            start: i,
            end_: end_pos,
            captures: state.captures.copy(),
            capture_versions: state.capture_versions.copy(),
            group_names: parsed.group_names,
          })
          if end_pos == i {
            i += 1
          } else {
            i = end_pos
          }
        }
        None => {
          // With sticky flag, stop on first failed match position
          if rflags.sticky {
            break
          }
          i += 1
        }
      }
    }
  }
  results
}

///|
fn regex_match_named_capture(m : RegexMatch, name : String) -> Value {
  let mut selected : Value = Undefined
  let mut selected_version = -1
  for pair in m.group_names {
    let (gname, gidx) = pair
    if gname == name {
      let cap_idx = gidx - 1
      if cap_idx >= 0 && cap_idx < m.captures.length() {
        match m.captures[cap_idx] {
          Some(s) => {
            let version = if cap_idx < m.capture_versions.length() {
              m.capture_versions[cap_idx]
            } else {
              0
            }
            if version > selected_version {
              selected = Value::String_(s)
              selected_version = version
            }
          }
          None => ()
        }
      }
    }
  }
  selected
}

///|
/// Create an Array value with index, input, and groups properties for RegExp match results
pub fn make_regex_match_array(m : RegexMatch, input : String) -> Value {
  let input_chars = input.to_array()
  let elements : Array[Value] = []
  // First element: full match
  let buf = StringBuilder::new()
  for i = m.start; i < m.end_; i = i + 1 {
    buf.write_char(input_chars[i])
  }
  elements.push(Value::String_(buf.to_string()))
  // Capture groups
  for cap in m.captures {
    match cap {
      Some(s) => elements.push(Value::String_(s))
      None => elements.push(Undefined)
    }
  }
  let arr_data : ArrayData = {
    elements,
    bag: @runtime.PropertyBag(),
    length_writable: true,
    holes: {},
    extensible: true,
  }
  // Set named properties on the result
  @runtime.set_array_named_prop(
    arr_data,
    "index",
    Value::Number(m.start.to_double()),
  )
  @runtime.set_array_named_prop(arr_data, "input", Value::String_(input))
  // Build groups object if named groups exist
  let groups_val : Value = if m.group_names.length() > 0 {
    let groups_props : Map[String, Value] = {}
    let groups_descs : Map[String, PropDescriptor] = {}
    for pair in m.group_names {
      let (name, _) = pair
      if !groups_descs.contains(name) {
        groups_props[name] = regex_match_named_capture(m, name)
        groups_descs[name] = {
          writable: true,
          enumerable: true,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        }
      }
    }
    Object({
      bag: {
        properties: groups_props,
        symbol_properties: {},
        descriptors: groups_descs,
        symbol_descriptors: {},
        internal_slots: {},
      },
      prototype: Null,
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    })
  } else {
    Undefined
  }
  @runtime.set_array_named_prop(arr_data, "groups", groups_val)
  Array(arr_data)
}

///|
const REGEXP_ORIGINAL_SOURCE_SYMBOL_ID = -120

///|
const REGEXP_ORIGINAL_FLAGS_SYMBOL_ID = -121

///|
const REGEXP_INTRINSIC_CONSTRUCTOR_SYMBOL_ID = -122

///|
// Engine-private negative symbol IDs for RegExp String Iterator internal slots.
// See docs/development.md hidden metadata reservation guidance.
const REGEXP_STRING_ITERATOR_BRAND_SYMBOL_ID = -123

///|
const REGEXP_STRING_ITERATOR_REGEXP_SYMBOL_ID = -124

///|
const REGEXP_STRING_ITERATOR_STRING_SYMBOL_ID = -125

///|
const REGEXP_STRING_ITERATOR_GLOBAL_SYMBOL_ID = -126

///|
const REGEXP_STRING_ITERATOR_UNICODE_SYMBOL_ID = -127

///|
const REGEXP_STRING_ITERATOR_DONE_SYMBOL_ID = -128

///|
fn regexp_original_source_from_data(data : ObjectData) -> String? {
  match data.bag.symbol_properties.get(REGEXP_ORIGINAL_SOURCE_SYMBOL_ID) {
    Some(Value::String_(s)) => Some(s)
    _ =>
      // Compatibility with older in-package construction paths while the
      // RegExp representation is migrating from visible data properties to
      // hidden internal-slot storage.
      match data.bag.properties.get("source") {
        Some(Value::String_(s)) => Some(s)
        _ => None
      }
  }
}

///|
fn regexp_original_flags_from_data(data : ObjectData) -> String? {
  match data.bag.symbol_properties.get(REGEXP_ORIGINAL_FLAGS_SYMBOL_ID) {
    Some(Value::String_(s)) => Some(s)
    _ =>
      match data.bag.properties.get("flags") {
        Some(Value::String_(s)) => Some(s)
        _ => None
      }
  }
}

///|
fn regexp_original_source(val : Value) -> String? {
  match val {
    Object(data) if data.class_name == "RegExp" =>
      regexp_original_source_from_data(data)
    _ => None
  }
}

///|
fn regexp_original_flags(val : Value) -> String? {
  match val {
    Object(data) if data.class_name == "RegExp" =>
      regexp_original_flags_from_data(data)
    _ => None
  }
}

///|
fn normalize_regexp_flags(flags : String) -> String raise Error {
  let valid_flags = "gimsuy"
  let seen_flags : Map[Char, Bool] = {}
  for ch in flags {
    if !valid_flags.contains(ch.to_string()) {
      raise @errors.SyntaxError(
        message="Invalid regular expression flags: " + flags,
      )
    }
    if seen_flags.contains(ch) {
      raise @errors.SyntaxError(
        message="Invalid regular expression flags: " + flags,
      )
    }
    seen_flags[ch] = true
  }
  let buf = StringBuilder::new()
  if flags.contains("g") {
    buf.write_string("g")
  }
  if flags.contains("i") {
    buf.write_string("i")
  }
  if flags.contains("m") {
    buf.write_string("m")
  }
  if flags.contains("s") {
    buf.write_string("s")
  }
  if flags.contains("u") {
    buf.write_string("u")
  }
  if flags.contains("y") {
    buf.write_string("y")
  }
  buf.to_string()
}

///|
fn validate_regexp_pattern(
  pattern : String,
  flags : String,
) -> Unit raise Error {
  let _valid : Unit = try {
    let _parsed = RegexParser::new(pattern, unicode=flags.contains("u")).parse()
  } catch {
    @errors.SyntaxError(message=msg) =>
      raise @errors.SyntaxError(
        message="Invalid regular expression: /" + pattern + "/: " + msg,
      )
    e =>
      raise @errors.SyntaxError(
        message="Invalid regular expression: /" +
          pattern +
          "/: " +
          e.to_string(),
      )
  }
  _valid
}

///|
fn normalize_and_validate_regexp(
  pattern : String,
  flags : String,
) -> String raise Error {
  let sorted_flags = normalize_regexp_flags(flags)
  validate_regexp_pattern(pattern, sorted_flags)
  sorted_flags
}

///|
fn regexp_internal_slot_descriptor() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn set_regexp_internal_slot_descriptors(data : ObjectData) -> Unit {
  data.bag.symbol_descriptors[REGEXP_ORIGINAL_SOURCE_SYMBOL_ID] = regexp_internal_slot_descriptor()
  data.bag.symbol_descriptors[REGEXP_ORIGINAL_FLAGS_SYMBOL_ID] = regexp_internal_slot_descriptor()
}

///|
fn set_regexp_intrinsic_constructor_slot(
  symbol_properties : Map[Int, Value],
  symbol_descriptors : Map[Int, PropDescriptor],
  ctor : Value,
) -> Unit {
  symbol_properties[REGEXP_INTRINSIC_CONSTRUCTOR_SYMBOL_ID] = ctor
  symbol_descriptors[REGEXP_INTRINSIC_CONSTRUCTOR_SYMBOL_ID] = regexp_internal_slot_descriptor()
}

///|
fn set_regexp_original_source_flags(
  data : ObjectData,
  source : String,
  flags : String,
) -> Unit raise Error {
  let sorted_flags = normalize_and_validate_regexp(source, flags)
  data.bag.symbol_properties[REGEXP_ORIGINAL_SOURCE_SYMBOL_ID] = Value::String_(
    source,
  )
  data.bag.symbol_properties[REGEXP_ORIGINAL_FLAGS_SYMBOL_ID] = Value::String_(
    sorted_flags,
  )
  set_regexp_internal_slot_descriptors(data)
}

///|
fn escape_regexp_source(source : String) -> String {
  if source == "" {
    return "(?:)"
  }
  let buf = StringBuilder::new()
  for ch in source {
    match ch {
      '/' => buf.write_string("\\/")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\u{2028}' => buf.write_string("\\u2028")
      '\u{2029}' => buf.write_string("\\u2029")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// Extract source pattern and flags from a RegExp value
fn extract_regexp_source_flags(val : Value) -> (String, String) {
  match val {
    Object(data) if data.class_name == "RegExp" => {
      let pat = match regexp_original_source_from_data(data) {
        Some(s) => s
        None => ""
      }
      let fl = match regexp_original_flags_from_data(data) {
        Some(s) => s
        None => ""
      }
      (pat, fl)
    }
    _ => ("", "")
  }
}

///|
fn regexp_this_is_object(value : Value) -> Bool {
  match value {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    _ => false
  }
}

///|
fn regexp_has_internal_matcher(value : Value) -> Bool {
  match value {
    Object(data) if data.class_name == "RegExp" =>
      regexp_original_source_from_data(data) is Some(_)
    _ => false
  }
}

///|
fn regexp_is_regexp(interp : Interpreter, value : Value) -> Bool raise Error {
  if !regexp_this_is_object(value) {
    return false
  }
  let loc = @token.Loc::default()
  let match_sym = interp.realm_state.well_known_symbols.match_sym
  let matcher = interp.get_computed_property(value, Symbol(match_sym), loc)
  match matcher {
    Undefined => regexp_has_internal_matcher(value)
    _ => @runtime.is_truthy(matcher)
  }
}

///|
fn regexp_constructor_args(args : Array[Value]) -> (Value, Value) {
  match args {
    [pattern, flags, ..] => (pattern, flags)
    [pattern] => (pattern, Undefined)
    [] => (Undefined, Undefined)
  }
}

///|
fn regexp_constructor_string(
  interp : Interpreter,
  value : Value,
) -> String raise Error {
  match value {
    Undefined => ""
    _ => interp.to_js_string(value)
  }
}

///|
fn regexp_constructor_call(
  interp : Interpreter,
  context : @runtime.CallContext,
  args : Array[Value],
  realm_state : @runtime.RealmState,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let (pattern_arg, flags_arg) = regexp_constructor_args(args)
  let pattern_is_regexp = regexp_is_regexp(interp, pattern_arg)
  if !context.is_constructing() && pattern_is_regexp && flags_arg is Undefined {
    let pattern_ctor = interp.get_property(pattern_arg, "constructor", loc)
    if same_value(pattern_ctor, regexp_default_constructor(realm_state)) {
      return pattern_arg
    }
  }
  let has_internal_matcher = regexp_has_internal_matcher(pattern_arg)
  let pattern_source = if has_internal_matcher {
    match regexp_original_source(pattern_arg) {
      Some(source) => Value::String_(source)
      None => pattern_arg
    }
  } else if pattern_is_regexp {
    interp.get_property(pattern_arg, "source", loc)
  } else {
    pattern_arg
  }
  let flags_value = if flags_arg is Undefined {
    if has_internal_matcher {
      match regexp_original_flags(pattern_arg) {
        Some(flags) => Value::String_(flags)
        None => Undefined
      }
    } else if pattern_is_regexp {
      interp.get_property(pattern_arg, "flags", loc)
    } else {
      Undefined
    }
  } else {
    flags_arg
  }
  let pattern = regexp_constructor_string(interp, pattern_source)
  let flags = regexp_constructor_string(interp, flags_value)
  make_regexp_object_with_realm_state(pattern, flags, realm_state)
}

///|
fn make_regexp_constructor(
  realm_state : @runtime.RealmState,
  name_length_desc : PropDescriptor,
) -> Value {
  Value::Object({
    bag: {
      properties: {
        "name": Value::String_("RegExp"),
        "length": Value::Number(2.0),
      },
      symbol_properties: {},
      descriptors: { "name": name_length_desc, "length": name_length_desc },
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: Null,
    callable: Some(
      InterpreterCallableWithContext("RegExp", fn(
        interp,
        context,
        _this_val,
        args,
      ) raise {
        regexp_constructor_call(interp, context, args, realm_state)
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn is_regexp_prototype_value(
  realm_state : @runtime.RealmState,
  value : Value,
) -> Bool {
  match realm_state.regexp_prototype.val {
    Some(proto) => @runtime.strict_equal(value, proto)
    None => false
  }
}

///|
fn regexp_proto_incompatible(method_name : String) -> Value raise Error {
  raise @errors.TypeError(
    message="Method " + method_name + " called on incompatible receiver",
  )
}

///|
fn make_regexp_compile_method(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_interp_method_func(
    name="compile",
    length=2,
    realm_state=Some(realm_state),
    fn(interp, this_val, args) raise {
      match this_val {
        Object(data) => {
          if data.class_name != "RegExp" ||
            regexp_original_source_from_data(data) is None {
            return regexp_proto_incompatible("RegExp.prototype.compile")
          }
          let pattern_arg = if args.length() > 0 { args[0] } else { Undefined }
          let flags_arg = if args.length() > 1 { args[1] } else { Undefined }
          let (source, flags) : (String, String) = match pattern_arg {
            Object(_) =>
              if regexp_has_internal_matcher(pattern_arg) {
                // If pattern is a RegExp and flags is not undefined, throw TypeError
                if !(flags_arg is Undefined) {
                  raise @errors.TypeError(
                    message="Cannot supply flags when constructing one RegExp from another",
                  )
                }
                let source = match regexp_original_source(pattern_arg) {
                  Some(s) => s
                  None => ""
                }
                let flags = match regexp_original_flags(pattern_arg) {
                  Some(f) => f
                  None => ""
                }
                (source, flags)
              } else {
                let source = interp.to_js_string(pattern_arg)
                let flags = if flags_arg is Undefined {
                  ""
                } else {
                  interp.to_js_string(flags_arg)
                }
                (source, flags)
              }
            Undefined => {
              let flags = if flags_arg is Undefined {
                ""
              } else {
                interp.to_js_string(flags_arg)
              }
              ("", flags)
            }
            _ => {
              let source = interp.to_js_string(pattern_arg)
              let flags = if flags_arg is Undefined {
                ""
              } else {
                interp.to_js_string(flags_arg)
              }
              (source, flags)
            }
          }
          set_regexp_original_source_flags(data, source, flags)
          let _ = interp.set_property(
            this_val,
            "lastIndex",
            Value::Number(0.0),
            @token.Loc::default(),
            strict=true,
          )
          this_val
        }
        _ => regexp_proto_incompatible("RegExp.prototype.compile")
      }
    },
  )
}

///|
fn make_regexp_to_string_method(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_interp_method_func(
    name="toString",
    length=0,
    realm_state=Some(realm_state),
    fn(interp, this_val, _args) raise {
      if !regexp_this_is_object(this_val) {
        return regexp_proto_incompatible("RegExp.prototype.toString")
      }
      let source = interp.to_js_string(
        interp.get_property(this_val, "source", @token.Loc::default()),
      )
      let flags = interp.to_js_string(
        interp.get_property(this_val, "flags", @token.Loc::default()),
      )
      Value::String_("/" + source + "/" + flags)
    },
  )
}

///|
fn regexp_flag_code(flag_name : String) -> String {
  match flag_name {
    "global" => "g"
    "ignoreCase" => "i"
    "multiline" => "m"
    "dotAll" => "s"
    "unicode" => "u"
    "sticky" => "y"
    "unicodeSets" => "v"
    "hasIndices" => "d"
    _ => ""
  }
}

///|
fn make_regexp_flag_getter(
  flag_name : String,
  realm_state : @runtime.RealmState,
) -> Value {
  let flag_code = regexp_flag_code(flag_name)
  @runtime.make_method_func(
    name="get " + flag_name,
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) raise {
      if !regexp_this_is_object(this_val) {
        return regexp_proto_incompatible("get RegExp.prototype." + flag_name)
      }
      match regexp_original_flags(this_val) {
        Some(flags_str) => Bool(flags_str.contains(flag_code))
        None =>
          if is_regexp_prototype_value(realm_state, this_val) {
            Undefined
          } else {
            regexp_proto_incompatible("get RegExp.prototype." + flag_name)
          }
      }
    },
  )
}

///|
fn append_regexp_flag_if_truthy(
  interp : Interpreter,
  this_val : Value,
  property : String,
  flag : String,
  buf : StringBuilder,
) -> Unit raise Error {
  if @runtime.is_truthy(
      interp.get_property(this_val, property, @token.Loc::default()),
    ) {
    buf.write_string(flag)
  }
}

///|
fn make_regexp_flags_getter(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_interp_method_func(
    name="get flags",
    length=0,
    realm_state=Some(realm_state),
    fn(interp, this_val, _args) raise {
      if !regexp_this_is_object(this_val) {
        return regexp_proto_incompatible("get RegExp.prototype.flags")
      }
      let result = StringBuilder::new()
      let flag_props = [
        ("hasIndices", "d"),
        ("global", "g"),
        ("ignoreCase", "i"),
        ("multiline", "m"),
        ("dotAll", "s"),
        ("unicode", "u"),
        ("unicodeSets", "v"),
        ("sticky", "y"),
      ]
      for pair in flag_props {
        let (property, flag) = pair
        append_regexp_flag_if_truthy(interp, this_val, property, flag, result)
      }
      Value::String_(result.to_string())
    },
  )
}

///|
fn make_regexp_source_getter(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_method_func(
    name="get source",
    length=0,
    realm_state=Some(realm_state),
    fn(this_val, _args) raise {
      if !regexp_this_is_object(this_val) {
        return regexp_proto_incompatible("get RegExp.prototype.source")
      }
      match regexp_original_source(this_val) {
        Some(s) => Value::String_(escape_regexp_source(s))
        None =>
          if is_regexp_prototype_value(realm_state, this_val) {
            Value::String_("(?:)")
          } else {
            regexp_proto_incompatible("get RegExp.prototype.source")
          }
      }
    },
  )
}

///|
fn regexp_accessor_descriptor(getter : Value) -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(getter),
    setter: None,
    is_accessor: true,
  }
}

///|
fn install_regexp_prototype_accessors(
  regexp_proto_props : Map[String, Value],
  regexp_proto_descs : Map[String, PropDescriptor],
  realm_state : @runtime.RealmState,
) -> Unit {
  let flag_names = [
    "global", "ignoreCase", "multiline", "dotAll", "unicode", "sticky", "unicodeSets",
    "hasIndices",
  ]
  for flag_name in flag_names {
    let getter = make_regexp_flag_getter(flag_name, realm_state)
    regexp_proto_props[flag_name] = Undefined
    regexp_proto_descs[flag_name] = regexp_accessor_descriptor(getter)
  }
  let flags_getter = make_regexp_flags_getter(realm_state)
  regexp_proto_props["flags"] = Undefined
  regexp_proto_descs["flags"] = regexp_accessor_descriptor(flags_getter)
  let source_getter = make_regexp_source_getter(realm_state)
  regexp_proto_props["source"] = Undefined
  regexp_proto_descs["source"] = regexp_accessor_descriptor(source_getter)
}

// ---- RegExp Object Creation ----

///|
fn make_regexp_object_with_proto(
  pattern : String,
  flags : String,
  prototype : Value,
) -> Value raise Error {
  let sorted_flags = normalize_and_validate_regexp(pattern, flags)
  let props : Map[String, Value] = {}
  props["lastIndex"] = Value::Number(0.0)
  // RegExp instance state is stored as hidden internal slots. Public accessors
  // live on RegExp.prototype and compute from these slots.
  let sym_props : Map[Int, Value] = {}
  sym_props[REGEXP_ORIGINAL_SOURCE_SYMBOL_ID] = Value::String_(pattern)
  sym_props[REGEXP_ORIGINAL_FLAGS_SYMBOL_ID] = Value::String_(sorted_flags)

  // Create descriptor map for the only RegExp instance own property.
  let re_descs : Map[String, PropDescriptor] = {}
  // lastIndex per spec: writable but NOT enumerable and NOT configurable
  re_descs["lastIndex"] = {
    writable: true,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  let re_sym_descs : Map[Int, PropDescriptor] = {}
  re_sym_descs[REGEXP_ORIGINAL_SOURCE_SYMBOL_ID] = regexp_internal_slot_descriptor()
  re_sym_descs[REGEXP_ORIGINAL_FLAGS_SYMBOL_ID] = regexp_internal_slot_descriptor()

  Value::Object({
    bag: {
      properties: props,
      symbol_properties: sym_props,
      descriptors: re_descs,
      symbol_descriptors: re_sym_descs,
      internal_slots: {},
    },
    prototype,
    callable: None,
    class_name: "RegExp",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
pub fn make_regexp_object(
  pattern : String,
  flags : String,
) -> Value raise Error {
  make_regexp_object_with_proto(pattern, flags, Null)
}

///|
pub fn make_regexp_object_with_realm_state(
  pattern : String,
  flags : String,
  realm_state : @runtime.RealmState,
) -> Value raise Error {
  let prototype = match realm_state.regexp_prototype.val {
    Some(p) => p
    None => Null
  }
  make_regexp_object_with_proto(pattern, flags, prototype)
}

///|
pub fn substring(chars : Array[Char], start : Int, end_ : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end_; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
priv struct RegExpReplaceMatch {
  matched : String
  captures : Array[Value]
  position : Int
  match_length : Int
  named_captures : Value
}

///|
const REGEXP_MAX_SAFE_LENGTH = 9007199254740991.0

///|
fn regexp_to_length(value : Value, interp : Interpreter) -> Double raise Error {
  let n = @runtime.to_number(value, interp=Some(interp))
  if n.is_nan() || n <= 0.0 {
    0.0
  } else if n >= REGEXP_MAX_SAFE_LENGTH {
    REGEXP_MAX_SAFE_LENGTH
  } else {
    n.floor()
  }
}

///|
fn regexp_to_length_int(value : Value, interp : Interpreter) -> Int raise Error {
  let len = regexp_to_length(value, interp)
  if len > 100000.0 {
    100000
  } else {
    len.to_int()
  }
}

///|
fn regexp_clamp_position(
  value : Value,
  max_len : Int,
  interp : Interpreter,
) -> Int raise Error {
  let n = @runtime.to_number(value, interp=Some(interp))
  if n.is_nan() || n <= 0.0 {
    0
  } else if n >= max_len.to_double() {
    max_len
  } else {
    n.floor().to_int()
  }
}

///|
fn regexp_advance_string_index(
  input : String,
  index : Double,
  unicode : Bool,
) -> Double {
  if !unicode {
    return index + 1.0
  }
  let i = index.to_int()
  if i < 0 || i + 1 >= input.length() {
    return index + 1.0
  }
  let first = input[i].to_int()
  if first < 0xD800 || first > 0xDBFF {
    return index + 1.0
  }
  let second = input[i + 1].to_int()
  if second < 0xDC00 || second > 0xDFFF {
    return index + 1.0
  }
  index + 2.0
}

///|
fn regexp_char_index_to_code_unit_index(
  input : String,
  char_index : Int,
) -> Int {
  let chars = input.to_array()
  let end_ = if char_index > chars.length() {
    chars.length()
  } else {
    char_index
  }
  let mut code_unit_index = 0
  for i in 0..<end_ {
    if chars[i].to_int() > 0xFFFF {
      code_unit_index += 2
    } else {
      code_unit_index += 1
    }
  }
  code_unit_index
}

///|
fn regexp_builtin_exec(
  interp : Interpreter,
  rx : Value,
  input : String,
  loc : @token.Loc,
) -> Value raise Error {
  let (pat, fl) = match rx {
    Object(data) if data.class_name == "RegExp" => {
      let pat = match regexp_original_source_from_data(data) {
        Some(s) => s
        None =>
          raise @errors.TypeError(
            message="RegExp method called on incompatible receiver",
          )
      }
      let fl = match regexp_original_flags_from_data(data) {
        Some(s) => s
        None => ""
      }
      (pat, fl)
    }
    _ =>
      raise @errors.TypeError(
        message="RegExp method called on incompatible receiver",
      )
  }
  let has_global = fl.contains("g")
  let has_sticky = fl.contains("y")
  let last_index = regexp_to_length(
    interp.get_property(rx, "lastIndex", loc),
    interp,
  )
  if (has_global || has_sticky) && last_index > input.length().to_double() {
    let _ = interp.set_property(
      rx,
      "lastIndex",
      Value::Number(0.0),
      loc,
      strict=true,
    )
    return Null
  }
  let start = if has_global || has_sticky { last_index.to_int() } else { 0 }
  match regex_search(pat, fl, input, start_pos=start) {
    Some(m) => {
      if has_global || has_sticky {
        let last_index = if fl.contains("u") || fl.contains("v") {
          regexp_char_index_to_code_unit_index(input, m.end_)
        } else {
          m.end_
        }
        let _ = interp.set_property(
          rx,
          "lastIndex",
          Value::Number(last_index.to_double()),
          loc,
          strict=true,
        )
      }
      make_regex_match_array(m, input)
    }
    None => {
      if has_global || has_sticky {
        let _ = interp.set_property(
          rx,
          "lastIndex",
          Value::Number(0.0),
          loc,
          strict=true,
        )
      }
      Null
    }
  }
}

///|
fn regexp_exec_for_symbol_method(
  interp : Interpreter,
  rx : Value,
  input : String,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let exec = interp.get_property(rx, "exec", loc)
  if @runtime.is_callable(exec) {
    let result = @runtime.call_callable_direct(
      exec,
      rx,
      [Value::String_(input)],
      interp=Some(interp),
    )
    match result {
      Null | Object(_) | Array(_) => result
      _ =>
        raise @errors.TypeError(
          message="RegExp exec method returned neither object nor null",
        )
    }
  } else {
    regexp_builtin_exec(interp, rx, input, loc)
  }
}

///|
fn regexp_string_iterator_has_slots(data : ObjectData) -> Bool {
  let slots = data.bag.symbol_properties
  slots.contains(REGEXP_STRING_ITERATOR_BRAND_SYMBOL_ID) &&
  slots.contains(REGEXP_STRING_ITERATOR_REGEXP_SYMBOL_ID) &&
  slots.contains(REGEXP_STRING_ITERATOR_STRING_SYMBOL_ID) &&
  slots.contains(REGEXP_STRING_ITERATOR_GLOBAL_SYMBOL_ID) &&
  slots.contains(REGEXP_STRING_ITERATOR_UNICODE_SYMBOL_ID) &&
  slots.contains(REGEXP_STRING_ITERATOR_DONE_SYMBOL_ID)
}

///|
fn regexp_string_iterator_slot_type_error() -> Value raise Error {
  raise @errors.TypeError(
    message="RegExp String Iterator.prototype.next requires that |this| be a RegExp String Iterator",
  )
}

///|
fn regexp_string_iterator_set_done(data : ObjectData, done : Bool) -> Unit {
  data.bag.symbol_properties[REGEXP_STRING_ITERATOR_DONE_SYMBOL_ID] = Bool(done)
}

///|
fn regexp_string_iterator_next(
  interp : Interpreter,
  this_val : Value,
) -> Value raise Error {
  let data = match this_val {
    Object(data) => data
    _ => return regexp_string_iterator_slot_type_error()
  }
  if !regexp_string_iterator_has_slots(data) {
    return regexp_string_iterator_slot_type_error()
  }
  let slots = data.bag.symbol_properties
  match slots.get(REGEXP_STRING_ITERATOR_DONE_SYMBOL_ID) {
    Some(Bool(true)) => return @runtime.create_iter_result(Undefined, true)
    _ => ()
  }
  let regexp = match slots.get(REGEXP_STRING_ITERATOR_REGEXP_SYMBOL_ID) {
    Some(value) => value
    None => return regexp_string_iterator_slot_type_error()
  }
  let input = match slots.get(REGEXP_STRING_ITERATOR_STRING_SYMBOL_ID) {
    Some(String_(s)) => s
    _ => return regexp_string_iterator_slot_type_error()
  }
  let global = match slots.get(REGEXP_STRING_ITERATOR_GLOBAL_SYMBOL_ID) {
    Some(Bool(value)) => value
    _ => return regexp_string_iterator_slot_type_error()
  }
  let full_unicode = match slots.get(REGEXP_STRING_ITERATOR_UNICODE_SYMBOL_ID) {
    Some(Bool(value)) => value
    _ => return regexp_string_iterator_slot_type_error()
  }
  let loc = @token.Loc::default()
  let match_value = regexp_exec_for_symbol_method(interp, regexp, input)
  match match_value {
    Null => {
      regexp_string_iterator_set_done(data, true)
      @runtime.create_iter_result(Undefined, true)
    }
    _ => {
      if !global {
        regexp_string_iterator_set_done(data, true)
        return @runtime.create_iter_result(match_value, false)
      }
      let match_str = interp.to_js_string(
        interp.get_property(match_value, "0", loc),
      )
      if match_str == "" {
        let this_index = regexp_to_length(
          interp.get_property(regexp, "lastIndex", loc),
          interp,
        )
        let next_index = regexp_advance_string_index(
          input, this_index, full_unicode,
        )
        let _ = interp.set_property(
          regexp,
          "lastIndex",
          Value::Number(next_index),
          loc,
          strict=true,
        )
      }
      @runtime.create_iter_result(match_value, false)
    }
  }
}

///|
fn regexp_create_string_iterator(
  realm_state : @runtime.RealmState,
  regexp : Value,
  input : String,
  global : Bool,
  full_unicode : Bool,
) -> Value {
  let sym_props : Map[Int, Value] = {}
  sym_props[REGEXP_STRING_ITERATOR_BRAND_SYMBOL_ID] = Bool(true)
  sym_props[REGEXP_STRING_ITERATOR_REGEXP_SYMBOL_ID] = regexp
  sym_props[REGEXP_STRING_ITERATOR_STRING_SYMBOL_ID] = String_(input)
  sym_props[REGEXP_STRING_ITERATOR_GLOBAL_SYMBOL_ID] = Bool(global)
  sym_props[REGEXP_STRING_ITERATOR_UNICODE_SYMBOL_ID] = Bool(full_unicode)
  sym_props[REGEXP_STRING_ITERATOR_DONE_SYMBOL_ID] = Bool(false)
  let sym_descs : Map[Int, PropDescriptor] = {}
  let slot_desc = regexp_internal_slot_descriptor()
  sym_descs[REGEXP_STRING_ITERATOR_BRAND_SYMBOL_ID] = slot_desc
  sym_descs[REGEXP_STRING_ITERATOR_REGEXP_SYMBOL_ID] = slot_desc
  sym_descs[REGEXP_STRING_ITERATOR_STRING_SYMBOL_ID] = slot_desc
  sym_descs[REGEXP_STRING_ITERATOR_GLOBAL_SYMBOL_ID] = slot_desc
  sym_descs[REGEXP_STRING_ITERATOR_UNICODE_SYMBOL_ID] = slot_desc
  sym_descs[REGEXP_STRING_ITERATOR_DONE_SYMBOL_ID] = slot_desc
  Value::Object({
    bag: {
      properties: {},
      symbol_properties: sym_props,
      descriptors: {},
      symbol_descriptors: sym_descs,
      internal_slots: {},
    },
    prototype: get_regexp_string_iterator_proto(realm_state),
    callable: None,
    class_name: "RegExp String Iterator",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn regexp_replace_match_from_result(
  interp : Interpreter,
  result : Value,
  input : String,
) -> RegExpReplaceMatch raise Error {
  let loc = @token.Loc::default()
  let length = regexp_to_length_int(
    interp.get_property(result, "length", loc),
    interp,
  )
  let captures_len = if length > 0 { length - 1 } else { 0 }
  let matched = interp.to_js_string(interp.get_property(result, "0", loc))
  let position = regexp_clamp_position(
    interp.get_property(result, "index", loc),
    input.length(),
    interp,
  )
  let captures : Array[Value] = []
  for i in 1..<=captures_len {
    let capture = interp.get_property(result, i.to_string(), loc)
    match capture {
      Undefined => captures.push(Undefined)
      _ => captures.push(Value::String_(interp.to_js_string(capture)))
    }
  }
  let named_captures = interp.get_property(result, "groups", loc)
  {
    matched,
    captures,
    position,
    match_length: matched.length(),
    named_captures,
  }
}

///|
fn regexp_named_captures_for_substitution(value : Value) -> Value raise Error {
  match value {
    Undefined => Undefined
    Null =>
      raise @errors.TypeError(
        message="Cannot convert undefined or null to object",
      )
    _ => value
  }
}

///|
fn regexp_get_substitution(
  matched : String,
  input : String,
  position : Int,
  captures : Array[Value],
  named_captures : Value,
  replacement : String,
  interp : Interpreter,
) -> String raise Error {
  let input_chars = input.to_array()
  let repl_chars = replacement.to_array()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < repl_chars.length() {
    if repl_chars[i] == '$' && i + 1 < repl_chars.length() {
      let next = repl_chars[i + 1]
      if next == '&' {
        buf.write_string(matched)
        i += 2
        continue
      } else if next == '`' {
        for j = 0; j < position && j < input_chars.length(); j = j + 1 {
          buf.write_char(input_chars[j])
        }
        i += 2
        continue
      } else if next == '\'' {
        let start = position + matched.to_array().length()
        for j = start; j < input_chars.length(); j = j + 1 {
          buf.write_char(input_chars[j])
        }
        i += 2
        continue
      } else if next >= '0' && next <= '9' {
        let group_idx = next.to_int() - '0'.to_int()
        if i + 2 < repl_chars.length() &&
          repl_chars[i + 2] >= '0' &&
          repl_chars[i + 2] <= '9' {
          let two_digit = group_idx * 10 +
            (repl_chars[i + 2].to_int() - '0'.to_int())
          if two_digit > 0 && two_digit - 1 < captures.length() {
            match captures[two_digit - 1] {
              Value::String_(s) => buf.write_string(s)
              Undefined => ()
              _ => ()
            }
            i += 3
            continue
          } else {
            buf.write_char('$')
            buf.write_char(next)
            buf.write_char(repl_chars[i + 2])
            i += 3
            continue
          }
        }
        if group_idx > 0 && group_idx - 1 < captures.length() {
          match captures[group_idx - 1] {
            Value::String_(s) => buf.write_string(s)
            Undefined => ()
            _ => ()
          }
        } else {
          buf.write_char('$')
          buf.write_char(next)
        }
        i += 2
        continue
      } else if next == '<' {
        if named_captures is Undefined {
          buf.write_char('$')
          buf.write_char('<')
          i += 2
          continue
        }
        let name_buf = StringBuilder::new()
        let mut j = i + 2
        while j < repl_chars.length() && repl_chars[j] != '>' {
          name_buf.write_char(repl_chars[j])
          j += 1
        }
        if j >= repl_chars.length() {
          buf.write_char('$')
          buf.write_char('<')
          i += 2
          continue
        }
        let capture = interp.get_property(
          named_captures,
          name_buf.to_string(),
          @token.Loc::default(),
        )
        match capture {
          Undefined => ()
          _ => buf.write_string(interp.to_js_string(capture))
        }
        i = j + 1
        continue
      } else if next == '$' {
        buf.write_char('$')
        i += 2
        continue
      }
    }
    buf.write_char(repl_chars[i])
    i += 1
  }
  buf.to_string()
}

///|
fn regexp_replace_append(
  input_chars : Array[Char],
  state : (StringBuilder, Int),
  item : RegExpReplaceMatch,
  replacement : String,
) -> (StringBuilder, Int) {
  let (buf, next_source_position) = state
  if item.position >= next_source_position {
    for i = next_source_position
        i < item.position && i < input_chars.length()
        i = i + 1 {
      buf.write_char(input_chars[i])
    }
    buf.write_string(replacement)
    (buf, item.position + item.match_length)
  } else {
    (buf, next_source_position)
  }
}

///|
fn regexp_symbol_replace(
  interp : Interpreter,
  this_val : Value,
  args : Array[Value],
) -> Value raise Error {
  if !regexp_this_is_object(this_val) {
    return regexp_proto_incompatible("RegExp.prototype[Symbol.replace]")
  }
  let loc = @token.Loc::default()
  let input = if args.length() > 0 { interp.to_js_string(args[0]) } else { "" }
  let replace_value = if args.length() > 1 { args[1] } else { Undefined }
  let functional_replace = @runtime.is_callable(replace_value)
  let replacement = if functional_replace {
    ""
  } else {
    interp.to_js_string(replace_value)
  }
  let flags = interp.to_js_string(interp.get_property(this_val, "flags", loc))
  let global = flags.contains("g")
  let full_unicode = flags.contains("u") || flags.contains("v")
  if global {
    let _ = interp.set_property(
      this_val,
      "lastIndex",
      Value::Number(0.0),
      loc,
      strict=true,
    )
  }
  let results : Array[Value] = []
  let mut done = false
  while !done {
    let result = regexp_exec_for_symbol_method(interp, this_val, input)
    match result {
      Null => done = true
      _ => {
        results.push(result)
        if !global {
          done = true
        } else {
          let match_str = interp.to_js_string(
            interp.get_property(result, "0", loc),
          )
          if match_str == "" {
            let this_index = regexp_to_length(
              interp.get_property(this_val, "lastIndex", loc),
              interp,
            )
            let next_index = regexp_advance_string_index(
              input, this_index, full_unicode,
            )
            let _ = interp.set_property(
              this_val,
              "lastIndex",
              Value::Number(next_index),
              loc,
              strict=true,
            )
          }
        }
      }
    }
  }
  let input_chars = input.to_array()
  let buf = StringBuilder::new()
  let mut next_source_position = 0
  for result in results {
    let item = regexp_replace_match_from_result(interp, result, input)
    let actual_replacement = if functional_replace {
      let replacer_args : Array[Value] = [Value::String_(item.matched)]
      for capture in item.captures {
        replacer_args.push(capture)
      }
      replacer_args.push(Value::Number(item.position.to_double()))
      replacer_args.push(Value::String_(input))
      if !(item.named_captures is Undefined) {
        replacer_args.push(item.named_captures)
      }
      let repl_value = @runtime.call_callable_direct(
        replace_value,
        Undefined,
        replacer_args,
        interp=Some(interp),
      )
      interp.to_js_string(repl_value)
    } else {
      regexp_get_substitution(
        item.matched,
        input,
        item.position,
        item.captures,
        regexp_named_captures_for_substitution(item.named_captures),
        replacement,
        interp,
      )
    }
    let (same_buf, next_pos) = regexp_replace_append(
      input_chars,
      (buf, next_source_position),
      item,
      actual_replacement,
    )
    ignore(same_buf)
    next_source_position = next_pos
  }
  for i = next_source_position; i < input_chars.length(); i = i + 1 {
    buf.write_char(input_chars[i])
  }
  Value::String_(buf.to_string())
}

///|
fn make_regexp_replace_method(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_interp_method_func(
    name="[Symbol.replace]",
    length=2,
    realm_state=Some(realm_state),
    fn(interp, this_val, args) raise {
      regexp_symbol_replace(interp, this_val, args)
    },
  )
}

///|
fn regexp_symbol_match(
  interp : Interpreter,
  this_val : Value,
  args : Array[Value],
) -> Value raise Error {
  if !regexp_this_is_object(this_val) {
    return regexp_proto_incompatible("RegExp.prototype[Symbol.match]")
  }
  let loc = @token.Loc::default()
  let input = if args.length() > 0 { interp.to_js_string(args[0]) } else { "" }
  let flags = interp.to_js_string(interp.get_property(this_val, "flags", loc))
  let global = flags.contains("g")
  if !global {
    return regexp_exec_for_symbol_method(interp, this_val, input)
  }
  let full_unicode = flags.contains("u") || flags.contains("v")
  let _ = interp.set_property(
    this_val,
    "lastIndex",
    Value::Number(0.0),
    loc,
    strict=true,
  )
  let matches : Array[Value] = []
  while true {
    let result = regexp_exec_for_symbol_method(interp, this_val, input)
    match result {
      Null =>
        if matches.length() == 0 {
          return Null
        } else {
          return @runtime.make_array(matches)
        }
      _ => {
        let match_str = interp.to_js_string(
          interp.get_property(result, "0", loc),
        )
        matches.push(Value::String_(match_str))
        if match_str == "" {
          let this_index = regexp_to_length(
            interp.get_property(this_val, "lastIndex", loc),
            interp,
          )
          let next_index = regexp_advance_string_index(
            input, this_index, full_unicode,
          )
          let _ = interp.set_property(
            this_val,
            "lastIndex",
            Value::Number(next_index),
            loc,
            strict=true,
          )
        }
      }
    }
  }
  Null
}

///|
fn make_regexp_match_method(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_interp_method_func(
    name="[Symbol.match]",
    length=1,
    realm_state=Some(realm_state),
    fn(interp, this_val, args) raise {
      regexp_symbol_match(interp, this_val, args)
    },
  )
}

///|
fn regexp_symbol_match_all(
  interp : Interpreter,
  this_val : Value,
  args : Array[Value],
  realm_state : @runtime.RealmState,
) -> Value raise Error {
  if !regexp_this_is_object(this_val) {
    return regexp_proto_incompatible("RegExp.prototype[Symbol.matchAll]")
  }
  let loc = @token.Loc::default()
  let input = interp.to_js_string(
    if args.length() > 0 {
      args[0]
    } else {
      Undefined
    },
  )
  let species_ctor = regexp_species_constructor(interp, this_val, realm_state)
  let flags = interp.to_js_string(interp.get_property(this_val, "flags", loc))
  let matcher = interp.construct_value(
    species_ctor,
    [this_val, Value::String_(flags)],
    loc,
  )
  let last_index = regexp_to_length(
    interp.get_property(this_val, "lastIndex", loc),
    interp,
  )
  let _ = interp.set_property(
    matcher,
    "lastIndex",
    Value::Number(last_index),
    loc,
    strict=true,
  )
  let global = flags.contains("g")
  let full_unicode = flags.contains("u") || flags.contains("v")
  regexp_create_string_iterator(
    realm_state, matcher, input, global, full_unicode,
  )
}

///|
fn make_regexp_match_all_method(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_interp_method_func(
    name="[Symbol.matchAll]",
    length=1,
    realm_state=Some(realm_state),
    fn(interp, this_val, args) raise {
      regexp_symbol_match_all(interp, this_val, args, realm_state)
    },
  )
}

///|
fn regexp_to_uint32(value : Value, interp : Interpreter) -> Int64 raise Error {
  let n = @runtime.to_number(value, interp=Some(interp))
  if n.is_nan() || n.is_inf() || n == 0.0 {
    return 0L
  }
  let two32 = 4294967296.0
  let sign = if n < 0.0 { -1.0 } else { 1.0 }
  let truncated = n.abs().floor() * sign
  let remainder = truncated % two32
  let pos_mod = if remainder < 0.0 { remainder + two32 } else { remainder }
  pos_mod.to_int64()
}

///|
fn regexp_default_constructor(realm_state : @runtime.RealmState) -> Value {
  match realm_state.regexp_prototype.val {
    Some(Object(data)) =>
      match
        data.bag.symbol_properties.get(REGEXP_INTRINSIC_CONSTRUCTOR_SYMBOL_ID) {
        Some(ctor) => ctor
        None => Undefined
      }
    _ => Undefined
  }
}

///|
fn regexp_species_constructor(
  interp : Interpreter,
  rx : Value,
  realm_state : @runtime.RealmState,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let default_ctor = regexp_default_constructor(realm_state)
  let c = interp.get_property(rx, "constructor", loc)
  if c is Undefined {
    return default_ctor
  }
  if !@runtime.is_object_value(c) {
    raise @errors.TypeError(message="RegExp constructor is not an object")
  }
  let species_sym = interp.realm_state.well_known_symbols.species
  let s = interp.get_computed_property(c, Symbol(species_sym), loc)
  match s {
    Undefined | Null => default_ctor
    _ =>
      if @runtime.is_constructor_value(s) {
        s
      } else {
        raise @errors.TypeError(message="RegExp species is not a constructor")
      }
  }
}

///|
fn regexp_string_slice(input : String, start : Int, end_ : Int) -> String {
  let buf = StringBuilder::new()
  for i in start..<end_ {
    let unit = input[i].to_int()
    buf.write_char(unit.unsafe_to_char())
  }
  buf.to_string()
}

///|
fn regexp_split_last_index(
  interp : Interpreter,
  splitter : Value,
  input : String,
  loc : @token.Loc,
) -> Int raise Error {
  let input_size = input.length()
  let e = regexp_to_length(
    interp.get_property(splitter, "lastIndex", loc),
    interp,
  )
  if e > input_size.to_double() {
    input_size
  } else {
    e.to_int()
  }
}

///|
fn regexp_symbol_split(
  interp : Interpreter,
  this_val : Value,
  args : Array[Value],
  realm_state : @runtime.RealmState,
) -> Value raise Error {
  if !regexp_this_is_object(this_val) {
    return regexp_proto_incompatible("RegExp.prototype[Symbol.split]")
  }
  let loc = @token.Loc::default()
  let input = if args.length() > 0 { interp.to_js_string(args[0]) } else { "" }
  let c = regexp_species_constructor(interp, this_val, realm_state)
  let flags = interp.to_js_string(interp.get_property(this_val, "flags", loc))
  let unicode_matching = flags.contains("u") || flags.contains("v")
  let new_flags = if flags.contains("y") { flags } else { flags + "y" }
  let splitter = interp.construct_value(
    c,
    [this_val, Value::String_(new_flags)],
    loc,
  )
  let limit = if args.length() > 1 {
    match args[1] {
      Undefined => 4294967295L
      _ => regexp_to_uint32(args[1], interp)
    }
  } else {
    4294967295L
  }
  let results : Array[Value] = []
  if limit == 0L {
    return @runtime.make_array(results)
  }
  let size = input.length()
  if size == 0 {
    let z = regexp_exec_for_symbol_method(interp, splitter, input)
    return match z {
      Null => @runtime.make_array([Value::String_(input)])
      _ => @runtime.make_array(results)
    }
  }
  let mut p = 0
  let mut q = 0
  while q < size {
    let _ = interp.set_property(
      splitter,
      "lastIndex",
      Value::Number(q.to_double()),
      loc,
      strict=true,
    )
    let z = regexp_exec_for_symbol_method(interp, splitter, input)
    match z {
      Null =>
        q = regexp_advance_string_index(input, q.to_double(), unicode_matching).to_int()
      _ => {
        let e = regexp_split_last_index(interp, splitter, input, loc)
        if e == p {
          q = regexp_advance_string_index(
            input,
            q.to_double(),
            unicode_matching,
          ).to_int()
        } else {
          results.push(Value::String_(regexp_string_slice(input, p, q)))
          if results.length().to_int64() == limit {
            return @runtime.make_array(results)
          }
          p = e
          let captures_len = regexp_to_length_int(
            interp.get_property(z, "length", loc),
            interp,
          )
          let number_of_captures = if captures_len > 0 {
            captures_len - 1
          } else {
            0
          }
          for i in 1..<=number_of_captures {
            results.push(interp.get_property(z, i.to_string(), loc))
            if results.length().to_int64() == limit {
              return @runtime.make_array(results)
            }
          }
          q = p
        }
      }
    }
  }
  results.push(Value::String_(regexp_string_slice(input, p, size)))
  @runtime.make_array(results)
}

///|
fn make_regexp_split_method(realm_state : @runtime.RealmState) -> Value {
  @runtime.make_interp_method_func(
    name="[Symbol.split]",
    length=2,
    realm_state=Some(realm_state),
    fn(interp, this_val, args) raise {
      regexp_symbol_split(interp, this_val, args, realm_state)
    },
  )
}

// ---- String Regex Methods ----

///|
pub fn string_match_regex(
  s : String,
  pattern : String,
  flags : String,
) -> Value {
  if flags.contains("g") {
    // Global match: return array of all matches
    let matches = regex_search_all(pattern, flags, s) catch { _ => [] }
    let input_chars = s.to_array()
    let elements : Array[Value] = []
    for m in matches {
      elements.push(Value::String_(substring(input_chars, m.start, m.end_)))
    }
    if elements.length() == 0 {
      return Null
    }
    @runtime.make_array(elements)
  } else {
    // Non-global: return first match with captures (includes index, input, groups)
    let result = regex_search(pattern, flags, s) catch { _ => None }
    match result {
      Some(m) => make_regex_match_array(m, s)
      None => Null
    }
  }
}

///|
pub fn string_search_regex(
  s : String,
  pattern : String,
  flags : String,
) -> Value {
  let result = regex_search(pattern, flags, s) catch { _ => None }
  match result {
    Some(m) => Value::Number(m.start.to_double())
    None => Value::Number(-1.0)
  }
}

///|
pub fn string_replace_regex(
  s : String,
  pattern : String,
  flags : String,
  replacement : String,
) -> Value {
  let input_chars = s.to_array()
  if flags.contains("g") {
    // Replace all matches
    let matches = regex_search_all(pattern, flags, s) catch { _ => [] }
    if matches.length() == 0 {
      return Value::String_(s)
    }
    let buf = StringBuilder::new()
    let mut last_end = 0
    for m in matches {
      // Add text before this match
      for i = last_end; i < m.start; i = i + 1 {
        buf.write_char(input_chars[i])
      }
      // Process replacement string (handle $1, $2, etc.)
      let repl = process_replacement(replacement, input_chars, m)
      buf.write_string(repl)
      last_end = m.end_
    }
    // Add remaining text
    for i = last_end; i < input_chars.length(); i = i + 1 {
      buf.write_char(input_chars[i])
    }
    Value::String_(buf.to_string())
  } else {
    // Replace first match only
    let result = regex_search(pattern, flags, s) catch { _ => None }
    match result {
      Some(m) => {
        let buf = StringBuilder::new()
        for i = 0; i < m.start; i = i + 1 {
          buf.write_char(input_chars[i])
        }
        let repl = process_replacement(replacement, input_chars, m)
        buf.write_string(repl)
        for i = m.end_; i < input_chars.length(); i = i + 1 {
          buf.write_char(input_chars[i])
        }
        Value::String_(buf.to_string())
      }
      None => Value::String_(s)
    }
  }
}

///|
/// Replace regex matches using a callback function per ES spec
/// Callback receives: (match, ...captures, offset, string, groups?)
pub fn string_replace_regex_func(
  s : String,
  pattern : String,
  flags : String,
  replace_fn : Value,
) -> Value raise {
  string_replace_regex_func_impl(s, pattern, flags, replace_fn, interp=None)
}

///|
fn string_replace_regex_func_impl(
  s : String,
  pattern : String,
  flags : String,
  replace_fn : Value,
  interp? : Interpreter? = None,
) -> Value raise {
  let input_chars = s.to_array()
  if flags.contains("g") {
    // Replace all matches
    let matches = regex_search_all(pattern, flags, s) catch { _ => [] }
    if matches.length() == 0 {
      return Value::String_(s)
    }
    let buf = StringBuilder::new()
    let mut last_end = 0
    for m in matches {
      for i = last_end; i < m.start; i = i + 1 {
        buf.write_char(input_chars[i])
      }
      let repl = call_replace_fn(replace_fn, m, input_chars, s, interp~)
      buf.write_string(repl)
      last_end = m.end_
    }
    for i = last_end; i < input_chars.length(); i = i + 1 {
      buf.write_char(input_chars[i])
    }
    Value::String_(buf.to_string())
  } else {
    // Replace first match only
    let result = regex_search(pattern, flags, s) catch { _ => None }
    match result {
      Some(m) => {
        let buf = StringBuilder::new()
        for i = 0; i < m.start; i = i + 1 {
          buf.write_char(input_chars[i])
        }
        let repl = call_replace_fn(replace_fn, m, input_chars, s, interp~)
        buf.write_string(repl)
        for i = m.end_; i < input_chars.length(); i = i + 1 {
          buf.write_char(input_chars[i])
        }
        Value::String_(buf.to_string())
      }
      None => Value::String_(s)
    }
  }
}

///|
/// Call the replacement function with (match, ...captures, offset, string, groups?)
fn call_replace_fn(
  replace_fn : Value,
  m : RegexMatch,
  input_chars : Array[Char],
  input : String,
  interp? : Interpreter? = None,
) -> String raise {
  let args : Array[Value] = []
  // First arg: full match string
  args.push(Value::String_(substring(input_chars, m.start, m.end_)))
  // Capture groups
  for cap in m.captures {
    match cap {
      Some(c) => args.push(Value::String_(c))
      None => args.push(Undefined)
    }
  }
  // offset (index of match)
  args.push(Value::Number(m.start.to_double()))
  // input string
  args.push(Value::String_(input))
  // groups object (if named groups exist)
  if m.group_names.length() > 0 {
    let groups_props : Map[String, Value] = {}
    for pair in m.group_names {
      let (name, _) = pair
      if !groups_props.contains(name) {
        groups_props[name] = regex_match_named_capture(m, name)
      }
    }
    args.push(
      Value::Object({
        bag: {
          properties: groups_props,
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {},
        },
        prototype: Null,
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
      }),
    )
  }
  let result = @runtime.call_callable_direct(
    replace_fn,
    Undefined,
    args,
    interp~,
  )
  @runtime.to_js_string(result, interp~)
}

///|
fn process_replacement(
  replacement : String,
  input_chars : Array[Char],
  m : RegexMatch,
) -> String {
  let repl_chars = replacement.to_array()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < repl_chars.length() {
    if repl_chars[i] == '$' && i + 1 < repl_chars.length() {
      let next = repl_chars[i + 1]
      if next == '&' {
        // $& = full match
        for j = m.start; j < m.end_; j = j + 1 {
          buf.write_char(input_chars[j])
        }
        i += 2
        continue
      } else if next == '`' {
        // $` = portion before match
        for j = 0; j < m.start; j = j + 1 {
          buf.write_char(input_chars[j])
        }
        i += 2
        continue
      } else if next == '\'' {
        // $' = portion after match
        for j = m.end_; j < input_chars.length(); j = j + 1 {
          buf.write_char(input_chars[j])
        }
        i += 2
        continue
      } else if next >= '0' && next <= '9' {
        // Check for one- and two-digit group references ($1-$99).
        let group_idx = next.to_int() - '0'.to_int()
        if i + 2 < repl_chars.length() &&
          repl_chars[i + 2] >= '0' &&
          repl_chars[i + 2] <= '9' {
          let two_digit = group_idx * 10 +
            (repl_chars[i + 2].to_int() - '0'.to_int())
          if two_digit > 0 && two_digit - 1 < m.captures.length() {
            match m.captures[two_digit - 1] {
              Some(s) => buf.write_string(s)
              None => ()
            }
            i += 3
            continue
          } else {
            buf.write_char('$')
            buf.write_char(next)
            buf.write_char(repl_chars[i + 2])
            i += 3
            continue
          }
        }
        if group_idx > 0 && group_idx - 1 < m.captures.length() {
          match m.captures[group_idx - 1] {
            Some(s) => buf.write_string(s)
            None => ()
          }
        } else {
          buf.write_char('$')
          buf.write_char(next)
        }
        i += 2
        continue
      } else if next == '<' {
        // $<name> - named group substitution
        if m.group_names.length() == 0 {
          // No named groups: $< is literal
          buf.write_char('$')
          buf.write_char('<')
          i += 2
          continue
        }
        // Parse name until '>'
        let name_buf = StringBuilder::new()
        let mut j = i + 2
        while j < repl_chars.length() && repl_chars[j] != '>' {
          name_buf.write_char(repl_chars[j])
          j += 1
        }
        if j >= repl_chars.length() {
          // No closing '>' — treat $< as literal
          buf.write_char('$')
          buf.write_char('<')
          i += 2
          continue
        }
        // Found '>' — look up name and substitute
        let name = name_buf.to_string()
        match regex_match_named_capture(m, name) {
          Value::String_(s) => buf.write_string(s)
          _ => ()
        }
        i = j + 1 // skip past '>'
        continue
      } else if next == '$' {
        buf.write_char('$')
        i += 2
        continue
      }
    }
    buf.write_char(repl_chars[i])
    i += 1
  }
  buf.to_string()
}

///|
/// Get or create the realm-owned %RegExpStringIteratorPrototype%
pub fn get_regexp_string_iterator_proto(
  realm_state : @runtime.RealmState,
) -> Value {
  let well_known_symbols = realm_state.well_known_symbols
  match
    realm_state.runtime_iterator_prototypes.regexp_string_iterator_proto.val {
    Some(proto) => proto
    None => {
      let iterator_sym = well_known_symbols.iterator
      let tostringtag_sym = well_known_symbols.to_string_tag
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[tostringtag_sym.id] = Value::String_(
        "RegExp String Iterator",
      )
      let proto_props : Map[String, Value] = {}
      let proto_sym_descs : Map[Int, PropDescriptor] = {}
      proto_sym_descs[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      // Add [Symbol.iterator] that returns the iterator itself
      proto_sym_props[iterator_sym.id] = @runtime.make_method_func(
        name="[Symbol.iterator]",
        length=0,
        realm_state=Some(realm_state),
        fn(this_val, _args) { this_val },
      )
      proto_props["next"] = @runtime.make_interp_method_func(
        name="next",
        length=0,
        realm_state=Some(realm_state),
        fn(interp, this_val, _args) raise {
          regexp_string_iterator_next(interp, this_val)
        },
      )
      let proto_descs : Map[String, PropDescriptor] = {}
      proto_descs["next"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      let proto : Value = Value::Object({
        bag: {
          properties: proto_props,
          symbol_properties: proto_sym_props,
          descriptors: proto_descs,
          symbol_descriptors: proto_sym_descs,
          internal_slots: {},
        },
        prototype: realm_state.get_iterator_proto(),
        callable: None,
        class_name: "RegExp String Iterator",
        extensible: true,
        arraybuffer_state: None,
      })
      realm_state.runtime_iterator_prototypes.regexp_string_iterator_proto.val = Some(
        proto,
      )
      proto
    }
  }
}

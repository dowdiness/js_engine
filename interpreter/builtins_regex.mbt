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
  Group(Array[RegexNode], Int) // children, group_index
  Alternation(Array[RegexNode], Array[RegexNode]) // left, right
  Sequence(Array[RegexNode])
  WordBoundary(Bool) // true = \b, false = \B
  Lookahead(Array[RegexNode], Bool) // children, positive (true=(?=...), false=(?!...))
  Backreference(Int) // group number (1-based)
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
}

///|
fn RegexParser::new(pattern : String) -> RegexParser {
  { pattern: pattern.to_array(), pos: 0, group_count: 0 }
}

///|
fn RegexParser::parse(self : RegexParser) -> RegexNode raise Error {
  let result = self.parse_alternation()
  result
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
        'n' => '\n'
        'r' => '\r'
        't' => '\t'
        _ => escaped
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
        esc
      } else {
        let c = self.pattern[self.pos]
        self.pos += 1
        c
      }
      ranges.push((start, end_ch))
    } else {
      ranges.push((start, start))
    }
  }
  if self.pos < self.pattern.length() {
    self.pos += 1 // skip ']'
  }
  CharClass(ranges, negated)
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
        }
        let children = match inner {
          Sequence(nodes) => nodes
          _ => [inner]
        }
        return Group(children, 0)
      } else if next == '=' {
        // Positive lookahead (?=...)
        self.pos += 2
        let inner = self.parse_alternation()
        if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
          self.pos += 1
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
  }
  let children = match inner {
    Sequence(nodes) => nodes
    _ => [inner]
  }
  Group(children, group_idx)
}

///|
fn RegexParser::parse_quantifier(
  self : RegexParser,
  node : RegexNode,
) -> RegexNode {
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
  if not(icase) {
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
    not(matched)
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
fn regex_exec_single(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  captures : Array[String?],
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
        if flags.dot_all || not(is_line_terminator(input[pos])) {
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
          } else if flags.multiline && pos > 0 && is_line_terminator(input[pos - 1]) {
            Some(pos)
          } else {
            None
          }
        End =>
          if pos == input.length() {
            Some(pos)
          } else if flags.multiline &&
            pos < input.length() &&
            is_line_terminator(input[pos]) {
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
    Group(children, group_idx) => {
      let result = match_sequence(children, 0, input, pos, captures, flags)
      match result {
        Some(end_pos) => {
          if group_idx > 0 && group_idx <= captures.length() {
            let buf = StringBuilder::new()
            for i = pos; i < end_pos; i = i + 1 {
              buf.write_char(input[i])
            }
            captures[group_idx - 1] = Some(buf.to_string())
          }
          Some(end_pos)
        }
        None => None
      }
    }
    Alternation(left, right) => {
      let left_result = match_sequence(left, 0, input, pos, captures, flags)
      match left_result {
        Some(_) => left_result
        None => match_sequence(right, 0, input, pos, captures, flags)
      }
    }
    Sequence(nodes) => match_sequence(nodes, 0, input, pos, captures, flags)
    Quantified(inner, min, max, greedy) => {
      // Standalone quantified without continuation — just match max
      let positions = collect_quantified_positions(
        inner, input, pos, captures, max, flags,
      )
      if positions.length() - 1 < min {
        return None
      }
      if greedy {
        Some(positions[positions.length() - 1])
      } else {
        Some(positions[min])
      }
    }
    Lookahead(children, positive) => {
      let result = match_sequence(children, 0, input, pos, captures, flags)
      match (result, positive) {
        (Some(_), true) => Some(pos) // Positive lookahead: matched, don't consume
        (None, false) => Some(pos) // Negative lookahead: didn't match, success
        _ => None
      }
    }
    Backreference(group_num) =>
      if group_num - 1 < captures.length() {
        match captures[group_num - 1] {
          Some(captured) => {
            let cap_chars = captured.to_array()
            if pos + cap_chars.length() <= input.length() {
              let mut matches = true
              for i = 0; i < cap_chars.length(); i = i + 1 {
                if not(
                  char_eq_icase(input[pos + i], cap_chars[i], flags.icase),
                ) {
                  matches = false
                  break
                }
              }
              if matches {
                Some(pos + cap_chars.length())
              } else {
                None
              }
            } else {
              None
            }
          }
          None => Some(pos) // Unmatched group: matches empty string
        }
      } else {
        Some(pos) // Invalid group: matches empty string
      }
  }
}

///|
fn regex_exec(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  captures : Array[String?],
  flags : RegexFlags,
) -> Int? {
  match node {
    Sequence(nodes) => match_sequence(nodes, 0, input, pos, captures, flags)
    _ => regex_exec_single(node, input, pos, captures, flags)
  }
}

///|
fn collect_quantified_positions(
  node : RegexNode,
  input : Array[Char],
  pos : Int,
  captures : Array[String?],
  max : Int?,
  flags : RegexFlags,
) -> Array[Int] {
  let positions : Array[Int] = [pos]
  let mut current = pos
  let mut count = 0
  while true {
    match max {
      Some(m) => if count >= m { break }
      None => ()
    }
    match regex_exec_single(node, input, current, captures, flags) {
      Some(next) => {
        if next == current {
          break
        }
        count += 1
        current = next
        positions.push(current)
      }
      None => break
    }
  }
  positions
}

///|
fn match_sequence(
  nodes : Array[RegexNode],
  idx : Int,
  input : Array[Char],
  pos : Int,
  captures : Array[String?],
  flags : RegexFlags,
) -> Int? {
  if idx >= nodes.length() {
    return Some(pos)
  }
  let node = nodes[idx]
  match node {
    Quantified(inner, min, max, greedy) => {
      // Collect all possible match positions for the quantified node
      let positions = collect_quantified_positions(
        inner, input, pos, captures, max, flags,
      )
      if positions.length() - 1 < min {
        return None
      }
      if greedy {
        // Try from most matches down to minimum
        for i = positions.length() - 1; i >= min; i = i - 1 {
          let result = match_sequence(
            nodes,
            idx + 1,
            input,
            positions[i],
            captures,
            flags,
          )
          match result {
            Some(_) => return result
            None => continue
          }
        }
        None
      } else {
        // Non-greedy: try from minimum up
        for i = min; i < positions.length(); i = i + 1 {
          let result = match_sequence(
            nodes,
            idx + 1,
            input,
            positions[i],
            captures,
            flags,
          )
          match result {
            Some(_) => return result
            None => continue
          }
        }
        None
      }
    }
    _ =>
      match regex_exec_single(node, input, pos, captures, flags) {
        Some(next) =>
          match_sequence(nodes, idx + 1, input, next, captures, flags)
        None => None
      }
  }
}

///|
fn count_groups(node : RegexNode) -> Int {
  match node {
    Literal(_) | Dot | CharClass(_, _) | Anchor(_) | WordBoundary(_) |
    Backreference(_) => 0
    Lookahead(children, _) =>
      children.fold(init=0, fn(acc, child) {
        let cg = count_groups(child)
        if cg > acc { cg } else { acc }
      })
    Quantified(inner, _, _, _) => count_groups(inner)
    Group(children, group_idx) => {
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
  let node = RegexParser::new(pattern).parse()
  let input_chars = input.to_array()
  let num_groups = count_groups(node)
  let rflags = make_regex_flags(flags)
  let captures : Array[String?] = Array::make(num_groups, None)
  match regex_exec(node, input_chars, start_pos, captures, rflags) {
    Some(end_pos) => Some({ start: start_pos, end_: end_pos, captures })
    None => None
  }
}

///|
pub fn regex_search(
  pattern : String,
  flags : String,
  input : String,
  start_pos~ : Int = 0,
) -> RegexMatch? raise Error {
  let node = RegexParser::new(pattern).parse()
  let input_chars = input.to_array()
  let num_groups = count_groups(node)
  let rflags = make_regex_flags(flags)
  let is_sticky = flags.contains("y")
  if is_sticky {
    // Sticky flag: only match at the given start_pos (lastIndex)
    if start_pos > input_chars.length() {
      return None
    }
    let captures : Array[String?] = Array::make(num_groups, None)
    match regex_exec(node, input_chars, start_pos, captures, rflags) {
      Some(end_pos) =>
        return Some({ start: start_pos, end_: end_pos, captures })
      None => return None
    }
  }
  for i = start_pos; i <= input_chars.length(); i = i + 1 {
    let captures : Array[String?] = Array::make(num_groups, None)
    match regex_exec(node, input_chars, i, captures, rflags) {
      Some(end_pos) => return Some({ start: i, end_: end_pos, captures })
      None => continue
    }
  }
  None
}

///|
pub fn regex_search_all(
  pattern : String,
  flags : String,
  input : String,
) -> Array[RegexMatch] raise Error {
  let node = RegexParser::new(pattern).parse()
  let input_chars = input.to_array()
  let num_groups = count_groups(node)
  let rflags = make_regex_flags(flags)
  let results : Array[RegexMatch] = []
  let mut i = 0
  while i <= input_chars.length() {
    let captures : Array[String?] = Array::make(num_groups, None)
    match regex_exec(node, input_chars, i, captures, rflags) {
      Some(end_pos) => {
        results.push({ start: i, end_: end_pos, captures })
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
  results
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
  elements.push(String_(buf.to_string()))
  // Capture groups
  for cap in m.captures {
    match cap {
      Some(s) => elements.push(String_(s))
      None => elements.push(Undefined)
    }
  }
  let arr_data : ArrayData = { elements, }
  // Set named properties on the result
  set_array_named_prop(arr_data, "index", Number(m.start.to_double()))
  set_array_named_prop(arr_data, "input", String_(input))
  set_array_named_prop(arr_data, "groups", Undefined)
  Array(arr_data)
}

// ---- RegExp Object Creation ----

///|
pub fn make_regexp_object(pattern : String, flags : String) -> Value {
  let has_global = flags.contains("g")
  let has_ignore_case = flags.contains("i")
  let has_multiline = flags.contains("m")
  let has_sticky = flags.contains("y")
  let has_unicode = flags.contains("u")
  let has_dotall = flags.contains("s")
  let props : Map[String, Value] = {}
  props["source"] = String_(pattern)
  props["flags"] = String_(flags)
  props["global"] = Bool(has_global)
  props["ignoreCase"] = Bool(has_ignore_case)
  props["multiline"] = Bool(has_multiline)
  props["sticky"] = Bool(has_sticky)
  props["unicode"] = Bool(has_unicode)
  props["dotAll"] = Bool(has_dotall)
  props["lastIndex"] = Number(0.0)
  // test method
  props["test"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("test", fn(this_val, args) {
        let str = if args.length() > 0 { args[0].to_string() } else { "" }
        let start = if has_sticky || has_global {
          match this_val {
            Object(d) =>
              match d.properties.get("lastIndex") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
            _ => 0
          }
        } else {
          0
        }
        let result = regex_search(pattern, flags, str, start_pos=start) catch {
          _ => None
        }
        match result {
          Some(m) => {
            if has_sticky || has_global {
              match this_val {
                Object(d) =>
                  d.properties["lastIndex"] = Number(m.end_.to_double())
                _ => ()
              }
            }
            Bool(true)
          }
          None => {
            if has_sticky || has_global {
              match this_val {
                Object(d) => d.properties["lastIndex"] = Number(0.0)
                _ => ()
              }
            }
            Bool(false)
          }
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  // exec method
  props["exec"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("exec", fn(this_val, args) {
        let str = if args.length() > 0 { args[0].to_string() } else { "" }
        let start = if has_sticky || has_global {
          match this_val {
            Object(d) =>
              match d.properties.get("lastIndex") {
                Some(Number(n)) => n.to_int()
                _ => 0
              }
            _ => 0
          }
        } else {
          0
        }
        let result = regex_search(pattern, flags, str, start_pos=start) catch {
          _ => None
        }
        match result {
          Some(m) => {
            if has_sticky || has_global {
              match this_val {
                Object(d) =>
                  d.properties["lastIndex"] = Number(m.end_.to_double())
                _ => ()
              }
            }
            make_regex_match_array(m, str)
          }
          None => {
            if has_sticky || has_global {
              match this_val {
                Object(d) => d.properties["lastIndex"] = Number(0.0)
                _ => ()
              }
            }
            Null
          }
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  Object({
    properties: props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "RegExp",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
fn substring(chars : Array[Char], start : Int, end_ : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end_; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
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
      elements.push(String_(substring(input_chars, m.start, m.end_)))
    }
    if elements.length() == 0 {
      return Null
    }
    Array({ elements, })
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
    Some(m) => Number(m.start.to_double())
    None => Number(-1.0)
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
      return String_(s)
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
    String_(buf.to_string())
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
        String_(buf.to_string())
      }
      None => String_(s)
    }
  }
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
      } else if next >= '1' && next <= '9' {
        let group_idx = next.to_int() - '0'.to_int()
        if group_idx - 1 < m.captures.length() {
          match m.captures[group_idx - 1] {
            Some(s) => buf.write_string(s)
            None => ()
          }
        }
        i += 2
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

///| Shared %RegExpStringIteratorPrototype% - lazily initialized
let regexp_string_iterator_proto_ref : Ref[Value?] = { val: None }

///|
/// Get or create the shared %RegExpStringIteratorPrototype%
pub fn get_regexp_string_iterator_proto() -> Value {
  match regexp_string_iterator_proto_ref.val {
    Some(proto) => proto
    None => {
      let iterator_sym = get_iterator_symbol()
      let tostringtag_sym = get_tostringtag_symbol()
      let proto_sym_props : Map[Int, Value] = {}
      proto_sym_props[tostringtag_sym.id] = String_("RegExp String Iterator")
      let proto_props : Map[String, Value] = {}
      let proto_sym_descs : Map[Int, PropDescriptor] = {}
      proto_sym_descs[tostringtag_sym.id] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      // Add [Symbol.iterator] that returns the iterator itself
      proto_sym_props[iterator_sym.id] = Object({
        properties: {},
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("[Symbol.iterator]", fn(this_val, _args) { this_val }),
        ),
        class_name: "Function",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
      // Add a placeholder next method with correct name/length on prototype
      proto_props["next"] = Object({
        properties: { "length": Number(0.0), "name": String_("next") },
        symbol_properties: {},
        prototype: Null,
        callable: Some(
          MethodCallable("next", fn(_this_val, _args) raise {
            raise @errors.TypeError(
              message="RegExp String Iterator.prototype.next requires that |this| be a RegExp String Iterator",
            )
          }),
        ),
        class_name: "Function",
        descriptors: {
          "length": {
            writable: false,
            enumerable: false,
            configurable: true,
            getter: None,
            setter: None,
          },
          "name": {
            writable: false,
            enumerable: false,
            configurable: true,
            getter: None,
            setter: None,
          },
        },
        symbol_descriptors: {},
        extensible: true,
      })
      let proto_descs : Map[String, PropDescriptor] = {}
      proto_descs["next"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
      let proto : Value = Object({
        properties: proto_props,
        symbol_properties: proto_sym_props,
        prototype: get_iterator_proto(),
        callable: None,
        class_name: "RegExp String Iterator",
        descriptors: proto_descs,
        symbol_descriptors: proto_sym_descs,
        extensible: true,
      })
      regexp_string_iterator_proto_ref.val = Some(proto)
      proto
    }
  }
}

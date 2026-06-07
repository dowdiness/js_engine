///|
/// MoonBit shadow of `scripts/test262_utils.py` for Test262 frontmatter helpers.
///
/// Python remains authoritative. This package intentionally mirrors the
/// lightweight fallback parser used when PyYAML is unavailable; callers should
/// use it only for parity checks until the tooling migration promotes a
/// MoonBit implementation.

///|
fn split_lines(text : String) -> Array[String] {
  if text == "" {
    return []
  }
  let lines : Array[String] = []
  let chars = text.to_array()
  let current = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\n' {
      lines.push(current.to_string())
      current.reset()
      i += 1
    } else if chars[i] == '\r' {
      lines.push(current.to_string())
      current.reset()
      if i + 1 < chars.length() && chars[i + 1] == '\n' {
        i += 2
      } else {
        i += 1
      }
    } else {
      current.write_char(chars[i])
      i += 1
    }
  }
  if chars[chars.length() - 1] != '\n' && chars[chars.length() - 1] != '\r' {
    lines.push(current.to_string())
  }
  lines
}

///|
fn leading_spaces(line : String) -> Int {
  let mut count = 0
  for ch in line {
    if ch == ' ' {
      count += 1
    } else {
      return count
    }
  }
  count
}

///|
fn is_space_or_tab(ch : Char) -> Bool {
  ch == ' ' || ch == '\t'
}

///|
fn string_from_chars(chars : ArrayView[Char]) -> String {
  String::from_array(chars)
}

///|
fn suffix_from_or_empty(s : String, start : Int) -> String {
  if start >= s.length() {
    ""
  } else {
    s[start:].to_owned()
  }
}

///|
fn double_quote_escape(ch : Char) -> Char? {
  match ch {
    '\\' => Some('\\')
    '"' => Some('"')
    '\'' => Some('\'')
    'n' => Some('\n')
    't' => Some('\t')
    'r' => Some('\r')
    '0' => Some('\u0000')
    'a' => Some('\u0007')
    'b' => Some('\u0008')
    'v' => Some('\u000B')
    'e' => Some('\u001B')
    '/' => Some('/')
    ' ' => Some(' ')
    _ => None
  }
}

///|
fn hex_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - '0'.to_int())
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn parse_hex_digits(chars : Array[Char], start : Int, count : Int) -> Int? {
  let mut value = 0
  for offset in 0..<count {
    match hex_digit_value(chars[start + offset]) {
      Some(digit) => value = value * 16 + digit
      None => return None
    }
  }
  Some(value)
}

///|
fn unescape_double_quoted(s : String) -> String {
  let chars = s.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\\' && i + 1 < chars.length() {
      let nxt = chars[i + 1]
      match double_quote_escape(nxt) {
        Some(replacement) => {
          out.write_char(replacement)
          i += 2
          continue
        }
        None => ()
      }
      if nxt == 'x' && i + 3 < chars.length() {
        match parse_hex_digits(chars, i + 2, 2) {
          Some(code) =>
            match code.to_char() {
              Some(ch) => {
                out.write_char(ch)
                i += 4
                continue
              }
              None => ()
            }
          None => ()
        }
      } else if nxt == 'u' && i + 5 < chars.length() {
        match parse_hex_digits(chars, i + 2, 4) {
          Some(code) =>
            match code.to_char() {
              Some(ch) => {
                out.write_char(ch)
                i += 6
                continue
              }
              None => ()
            }
          None => ()
        }
      }
      out.write_char(chars[i])
      i += 1
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  out.to_string()
}

///|
fn parse_yaml_scalar(value : String) -> Json {
  let value = value.trim().to_owned()
  if value == "" {
    return Json::string("")
  }
  if value.length() >= 2 {
    let first = value[0]
    let last = value[value.length() - 1]
    if first == last && (first == '\'' || first == '"') {
      let inner = value[1:value.length() - 1].to_owned()
      if first == '"' {
        return Json::string(unescape_double_quoted(inner))
      }
      return Json::string(inner.replace_all(old="''", new="'"))
    }
  }
  match value.to_lower() {
    "true" => Json::boolean(true)
    "false" => Json::boolean(false)
    "null" | "none" | "~" => Json::null()
    _ => Json::string(value)
  }
}

///|
fn split_top_level_csv(text : String) -> Array[String] {
  let parts : Array[String] = []
  let current = StringBuilder()
  let mut quote : Char? = None
  let mut depth = 0
  let mut escaped = false
  for ch in text {
    if escaped {
      current.write_char(ch)
      escaped = false
      continue
    }
    match quote {
      Some(_) if ch == '\\' => {
        escaped = true
        current.write_char(ch)
        continue
      }
      _ => ()
    }
    match quote {
      Some(q) => {
        current.write_char(ch)
        if ch == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if ch == '\'' || ch == '"' {
      quote = Some(ch)
      current.write_char(ch)
      continue
    }
    if ch == '[' || ch == '{' || ch == '(' {
      depth += 1
      current.write_char(ch)
      continue
    }
    if ch == ']' || ch == '}' || ch == ')' {
      if depth > 0 {
        depth -= 1
      }
      current.write_char(ch)
      continue
    }
    if ch == ',' && depth == 0 {
      let part = current.to_string().trim().to_owned()
      if part != "" {
        parts.push(part)
      }
      current.reset()
      continue
    }
    current.write_char(ch)
  }
  let part = current.to_string().trim().to_owned()
  if part != "" {
    parts.push(part)
  }
  parts
}

///|
fn strip_inline_comment(text : String) -> String {
  let chars = text.to_array()
  let mut quote : Char? = None
  let mut depth = 0
  let mut escaped = false
  let mut prev_is_space = true
  for i, ch in chars {
    if escaped {
      escaped = false
      continue
    }
    match quote {
      Some('"') if ch == '\\' => {
        escaped = true
        continue
      }
      _ => ()
    }
    match quote {
      Some(q) => {
        if ch == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if ch == '\'' || ch == '"' {
      quote = Some(ch)
      prev_is_space = false
      continue
    }
    if ch == '[' || ch == '{' || ch == '(' {
      depth += 1
      prev_is_space = false
      continue
    }
    if ch == ']' || ch == '}' || ch == ')' {
      if depth > 0 {
        depth -= 1
      }
      prev_is_space = false
      continue
    }
    if ch == '#' && depth == 0 && prev_is_space {
      return string_from_chars(chars[0:i])
    }
    prev_is_space = is_space_or_tab(ch)
  }
  text
}

///|
fn parse_inline_list(value : String) -> Array[Json]? {
  let value = value.trim().to_owned()
  guard value.has_prefix("[") && value.has_suffix("]") else { return None }
  let inner = value[1:value.length() - 1].to_owned().trim().to_owned()
  if inner == "" {
    return Some([])
  }
  let out : Array[Json] = []
  for item in split_top_level_csv(inner) {
    out.push(parse_yaml_scalar(item))
  }
  Some(out)
}

///|
fn parse_inline_dict(value : String) -> Map[String, Json]? {
  let value = value.trim().to_owned()
  guard value.has_prefix("{") && value.has_suffix("}") else { return None }
  let inner = value[1:value.length() - 1].to_owned().trim().to_owned()
  let out : Map[String, Json] = {}
  if inner == "" {
    return Some(out)
  }
  for item in split_top_level_csv(inner) {
    match item.split_once(":") {
      Some((key, raw_val)) =>
        out[key.trim().to_owned()] = parse_yaml_scalar(raw_val.to_owned())
      None => ()
    }
  }
  Some(out)
}

///|
fn parse_block_scalar(
  lines : Array[String],
  start : Int,
  parent_indent : Int,
  folded : Bool,
) -> (Json, Int) {
  let block_lines : Array[String] = []
  let mut block_indent = -1
  let mut j = start
  while j < lines.length() {
    let next_line = lines[j]
    if next_line.trim().is_empty() {
      block_lines.push("")
      j += 1
      continue
    }
    let next_indent = leading_spaces(next_line)
    if next_indent <= parent_indent {
      break
    }
    if block_indent < 0 {
      block_indent = next_indent
    }
    block_lines.push(suffix_from_or_empty(next_line, block_indent))
    j += 1
  }
  if folded {
    let paragraphs : Array[String] = []
    let current_para : Array[String] = []
    for bl in block_lines {
      if bl == "" {
        if current_para.length() > 0 {
          paragraphs.push(current_para.join(" "))
          current_para.clear()
        }
        paragraphs.push("")
      } else {
        current_para.push(bl)
      }
    }
    if current_para.length() > 0 {
      paragraphs.push(current_para.join(" "))
    }
    (Json::string(paragraphs.join("\n").trim_end(chars="\n").to_owned()), j)
  } else {
    (Json::string(block_lines.join("\n").trim_end(chars="\n").to_owned()), j)
  }
}

///|
fn parse_indented_block(
  lines : Array[String],
  start : Int,
  parent_indent : Int,
) -> (Json, Int) {
  let block_lines : Array[String] = []
  let mut j = start
  while j < lines.length() {
    let next_line = lines[j]
    if next_line.trim().is_empty() {
      block_lines.push("")
      j += 1
      continue
    }
    let next_indent = leading_spaces(next_line)
    if next_indent <= parent_indent {
      break
    }
    block_lines.push(next_line)
    j += 1
  }

  let meaningful = block_lines.filter(bl => !bl.trim().is_empty())
  if meaningful.length() == 0 {
    return (Json::null(), j)
  }

  let first = meaningful[0].trim().to_owned()
  if first.has_prefix("- ") {
    let out : Array[Json] = []
    for raw in block_lines {
      if raw.trim().is_empty() {
        continue
      }
      let raw_strip = raw.trim().to_owned()
      if raw_strip.has_prefix("- ") {
        out.push(parse_yaml_scalar(raw_strip[2:].to_owned()))
      }
    }
    (Json::array(out), j)
  } else {
    let out : Map[String, Json] = {}
    for raw in block_lines {
      if raw.trim().is_empty() {
        continue
      }
      let raw_strip = raw.trim().to_owned()
      match raw_strip.split_once(":") {
        Some((child_key, child_val)) =>
          out[child_key.trim().to_owned()] = parse_yaml_scalar(
            child_val.to_owned(),
          )
        None => ()
      }
    }
    (Json::object(out), j)
  }
}

///|
fn parse_remainder_value(
  lines : Array[String],
  line_index : Int,
  indent : Int,
  remainder : String,
) -> (Json, Int?) {
  match parse_inline_list(remainder) {
    Some(values) => (Json::array(values), None)
    None =>
      match parse_inline_dict(remainder) {
        Some(values) => (Json::object(values), None)
        None =>
          if remainder == "|" || remainder == ">" {
            let (value, next_index) = parse_block_scalar(
              lines,
              line_index + 1,
              indent,
              remainder == ">",
            )
            (value, Some(next_index))
          } else {
            (parse_yaml_scalar(remainder), None)
          }
      }
  }
}

///|
fn parse_frontmatter_fallback(frontmatter : String) -> Map[String, Json] {
  let data : Map[String, Json] = {}
  let lines = split_lines(frontmatter)
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if line.trim().is_empty() || line.trim_start().has_prefix("#") {
      i += 1
      continue
    }
    let indent = leading_spaces(line)
    let stripped = line.trim().to_owned()
    match stripped.split_once(":") {
      None => {
        i += 1
        continue
      }
      Some((raw_key, raw_remainder)) => {
        let key = raw_key.trim().to_owned()
        let remainder = strip_inline_comment(raw_remainder.to_owned())
          .trim()
          .to_owned()
        if remainder != "" {
          let (value, next_index) = parse_remainder_value(
            lines, i, indent, remainder,
          )
          data[key] = value
          match next_index {
            Some(next_index) => i = next_index
            None => i += 1
          }
          continue
        }

        let (value, next_index) = parse_indented_block(lines, i + 1, indent)
        data[key] = value
        i = next_index
      }
    }
  }
  data
}

///|
/// Extract and parse Test262 YAML frontmatter from a source file.
///
/// Returns `None` when no `/*--- ... ---*/` block exists. The returned values
/// use JSON as a portable representation of the Python helper's strings,
/// booleans, nulls, arrays, and dictionaries.
pub fn parse_yaml_frontmatter(source : String) -> Map[String, Json]? {
  match source.find("/*---") {
    None => None
    Some(start) => {
      let content_start = start + "/*---".length()
      match source[content_start:].find("---*/") {
        None => None
        Some(relative_end) =>
          Some(
            parse_frontmatter_fallback(
              source[content_start:content_start + relative_end].to_owned(),
            ),
          )
      }
    }
  }
}

///|
/// Coerce a JSON value to a list using `scripts/test262_utils.py` semantics.
///
/// Arrays pass through, `None`/JSON null become an empty array, and all other
/// values become a singleton array.
pub fn as_list(value : Json?) -> Array[Json] {
  match value {
    None => []
    Some(Json::Array(items)) => items
    Some(Json::Null) => []
    Some(item) => [item]
  }
}

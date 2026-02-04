///|
pub fn get_string_method(s : String, prop : String) -> Value {
  let chars = s.to_array()
  match prop {
    "charAt" =>
      make_native_func("charAt", fn(args) {
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if idx >= 0 && idx < chars.length() {
          let buf = StringBuilder::new()
          buf.write_char(chars[idx])
          String_(buf.to_string())
        } else {
          String_("")
        }
      })
    "charCodeAt" =>
      make_native_func("charCodeAt", fn(args) {
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if idx >= 0 && idx < chars.length() {
          Number(chars[idx].to_int().to_double())
        } else {
          Number(0.0 / 0.0)
        }
      })
    "at" =>
      make_native_func("at", fn(args) {
        // String.prototype.at() - access character at index (supports negative)
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let len = chars.length()
        let actual_idx = if idx < 0 { len + idx } else { idx }
        if actual_idx >= 0 && actual_idx < len {
          let buf = StringBuilder::new()
          buf.write_char(chars[actual_idx])
          String_(buf.to_string())
        } else {
          Undefined
        }
      })
    "codePointAt" =>
      make_native_func("codePointAt", fn(args) {
        // String.prototype.codePointAt() - get code point at index
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if idx >= 0 && idx < chars.length() {
          let code = chars[idx].to_int()
          // Check for high surrogate
          if code >= 0xD800 && code <= 0xDBFF && idx + 1 < chars.length() {
            let next = chars[idx + 1].to_int()
            // Check for low surrogate
            if next >= 0xDC00 && next <= 0xDFFF {
              // Combine surrogate pair to get code point
              let cp = (code - 0xD800) * 0x400 + (next - 0xDC00) + 0x10000
              return Number(cp.to_double())
            }
          }
          Number(code.to_double())
        } else {
          Undefined
        }
      })
    "concat" => {
      let str = s
      make_native_func("concat", fn(args) {
        let buf = StringBuilder::new()
        buf.write_string(str)
        for arg in args {
          buf.write_string(arg.to_string())
        }
        String_(buf.to_string())
      })
    }
    "indexOf" => {
      let str = s
      make_native_func("indexOf", fn(args) {
        let search = if args.length() > 0 {
          args[0].to_string()
        } else {
          "undefined"
        }
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let start = if from_idx < 0 { 0 } else { from_idx }
        let slen = str.length()
        let search_len = search.length()
        if search_len == 0 {
          let empty_result = if start > slen { slen } else { start }
          return Number(empty_result.to_double())
        }
        let s_chars = str.to_array()
        let search_chars = search.to_array()
        for i = start; i <= slen - search_len; i = i + 1 {
          let mut found = true
          for j = 0; j < search_len; j = j + 1 {
            if s_chars[i + j] != search_chars[j] {
              found = false
              break
            }
          }
          if found {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      })
    }
    "lastIndexOf" => {
      let str = s
      make_native_func("lastIndexOf", fn(args) {
        let search = if args.length() > 0 {
          args[0].to_string()
        } else {
          "undefined"
        }
        let slen = str.length()
        let search_len = search.length()
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          slen
        }
        let from = if from_idx < 0 {
          0
        } else if from_idx > slen {
          slen
        } else {
          from_idx
        }
        if search_len == 0 {
          return Number(from.to_double())
        }
        let max_start = slen - search_len
        if max_start < 0 {
          return Number(-1.0)
        }
        let start = if from > max_start { max_start } else { from }
        let s_chars = str.to_array()
        let search_chars = search.to_array()
        for i = start; i >= 0; i = i - 1 {
          let mut found = true
          for j = 0; j < search_len; j = j + 1 {
            if i + j >= slen || s_chars[i + j] != search_chars[j] {
              found = false
              break
            }
          }
          if found {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      })
    }
    "includes" => {
      let str = s
      make_native_func("includes", fn(args) {
        let search = if args.length() > 0 {
          args[0].to_string()
        } else {
          "undefined"
        }
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let start = if from_idx < 0 { 0 } else { from_idx }
        let slen = str.length()
        let search_len = search.length()
        if search_len == 0 {
          return Bool(true)
        }
        let s_chars = str.to_array()
        let search_chars = search.to_array()
        for i = start; i <= slen - search_len; i = i + 1 {
          let mut found = true
          for j = 0; j < search_len; j = j + 1 {
            if s_chars[i + j] != search_chars[j] {
              found = false
              break
            }
          }
          if found {
            return Bool(true)
          }
        }
        Bool(false)
      })
    }
    "slice" => {
      let str = s
      make_native_func("slice", fn(args) {
        let slen = str.length()
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 1 {
          match args[1] {
            Undefined => slen
            _ => to_number(args[1]).to_int()
          }
        } else {
          slen
        }
        if start < 0 {
          start = slen + start
          if start < 0 {
            start = 0
          }
        }
        if end < 0 {
          end = slen + end
          if end < 0 {
            end = 0
          }
        }
        if end > slen {
          end = slen
        }
        if start >= end {
          return String_("")
        }
        let s_chars = str.to_array()
        let buf = StringBuilder::new()
        for i = start; i < end; i = i + 1 {
          buf.write_char(s_chars[i])
        }
        String_(buf.to_string())
      })
    }
    "substring" => {
      let str = s
      make_native_func("substring", fn(args) {
        let slen = str.length()
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 1 {
          match args[1] {
            Undefined => slen
            _ => to_number(args[1]).to_int()
          }
        } else {
          slen
        }
        if start < 0 {
          start = 0
        }
        if end < 0 {
          end = 0
        }
        if start > slen {
          start = slen
        }
        if end > slen {
          end = slen
        }
        if start > end {
          let tmp = start
          start = end
          end = tmp
        }
        let s_chars = str.to_array()
        let buf = StringBuilder::new()
        for i = start; i < end; i = i + 1 {
          buf.write_char(s_chars[i])
        }
        String_(buf.to_string())
      })
    }
    "toLowerCase" => {
      let str = s
      make_native_func("toLowerCase", fn(_args) {
        let s_chars = str.to_array()
        let buf = StringBuilder::new()
        for c in s_chars {
          let code = c.to_int()
          if code >= 65 && code <= 90 {
            buf.write_char((code + 32).unsafe_to_char())
          } else {
            buf.write_char(c)
          }
        }
        String_(buf.to_string())
      })
    }
    "toUpperCase" => {
      let str = s
      make_native_func("toUpperCase", fn(_args) {
        let s_chars = str.to_array()
        let buf = StringBuilder::new()
        for c in s_chars {
          let code = c.to_int()
          if code >= 97 && code <= 122 {
            buf.write_char((code - 32).unsafe_to_char())
          } else {
            buf.write_char(c)
          }
        }
        String_(buf.to_string())
      })
    }
    "trim" => {
      let str = s
      make_native_func("trim", fn(_args) { String_(string_trim(str)) })
    }
    "trimStart" => {
      let str = s
      make_native_func("trimStart", fn(_args) { String_(trim_start(str)) })
    }
    "trimEnd" => {
      let str = s
      make_native_func("trimEnd", fn(_args) { String_(string_trim_end(str)) })
    }
    "split" => {
      let str = s
      make_native_func("split", fn(args) {
        // Handle undefined separator - return array with whole string
        if args.length() == 0 {
          return Array({ elements: [String_(str)] })
        }
        match args[0] {
          Undefined => return Array({ elements: [String_(str)] })
          _ => ()
        }
        // Get limit parameter (default: 2^32 - 1 per ES spec)
        let limit : Int64 = if args.length() > 1 {
          match args[1] {
            Undefined => 4294967295L // 2^32 - 1
            _ => {
              let lim = to_number(args[1]).to_int64()
              if lim < 0L { 0L } else { lim }
            }
          }
        } else {
          4294967295L
        }
        // If limit is 0, return empty array
        if limit == 0L {
          return Array({ elements: [] })
        }
        let sep = args[0].to_string()
        // Empty separator splits into individual characters
        if sep.length() == 0 {
          let result : Array[Value] = []
          let chars = str.to_array()
          let chars_len = chars.length().to_int64()
          let count = if chars_len < limit { chars.length() } else { limit.to_int() }
          for i = 0; i < count; i = i + 1 {
            let buf = StringBuilder::new()
            buf.write_char(chars[i])
            result.push(String_(buf.to_string()))
          }
          return Array({ elements: result })
        }
        let result : Array[Value] = []
        let s_chars = str.to_array()
        let sep_chars = sep.to_array()
        let slen = str.length()
        let sep_len = sep.length()
        let mut last = 0
        let mut i = 0
        while i <= slen - sep_len {
          // Check if we've hit the limit (need to leave room for final piece)
          if result.length().to_int64() >= limit - 1L {
            break
          }
          let mut matched = true
          for j = 0; j < sep_len; j = j + 1 {
            if s_chars[i + j] != sep_chars[j] {
              matched = false
              break
            }
          }
          if matched {
            let buf = StringBuilder::new()
            for k = last; k < i; k = k + 1 {
              buf.write_char(s_chars[k])
            }
            result.push(String_(buf.to_string()))
            last = i + sep_len
            i = i + sep_len
          } else {
            i = i + 1
          }
        }
        // Add remaining part if we haven't hit the limit
        if result.length().to_int64() < limit {
          let buf = StringBuilder::new()
          for k = last; k < slen; k = k + 1 {
            buf.write_char(s_chars[k])
          }
          result.push(String_(buf.to_string()))
        }
        Array({ elements: result })
      })
    }
    "replace" => {
      let str = s
      make_native_func("replace", fn(args) {
        if args.length() == 0 {
          return String_(str)
        }
        // Check if first arg is RegExp
        match args[0] {
          Object(data) =>
            if data.class_name == "RegExp" {
              let pattern = match data.properties.get("source") {
                Some(String_(s)) => s
                _ => ""
              }
              let flags = match data.properties.get("flags") {
                Some(String_(s)) => s
                _ => ""
              }
              let replacement = if args.length() > 1 {
                args[1].to_string()
              } else {
                "undefined"
              }
              return string_replace_regex(str, pattern, flags, replacement)
            }
          _ => ()
        }
        let search = args[0].to_string()
        let replacement = if args.length() > 1 {
          args[1].to_string()
        } else {
          "undefined"
        }
        let slen = str.length()
        let search_len = search.length()
        if search_len == 0 {
          return String_(replacement + str)
        }
        let s_chars = str.to_array()
        let search_chars = search.to_array()
        // Find first occurrence
        for i = 0; i <= slen - search_len; i = i + 1 {
          let mut matched = true
          for j = 0; j < search_len; j = j + 1 {
            if s_chars[i + j] != search_chars[j] {
              matched = false
              break
            }
          }
          if matched {
            let buf = StringBuilder::new()
            for k = 0; k < i; k = k + 1 {
              buf.write_char(s_chars[k])
            }
            buf.write_string(replacement)
            for k = i + search_len; k < slen; k = k + 1 {
              buf.write_char(s_chars[k])
            }
            return String_(buf.to_string())
          }
        }
        String_(str)
      })
    }
    "match" => {
      let str = s
      make_native_func("match", fn(args) {
        if args.length() == 0 {
          return Null
        }
        match args[0] {
          Object(data) =>
            if data.class_name == "RegExp" {
              let pattern = match data.properties.get("source") {
                Some(String_(s)) => s
                _ => ""
              }
              let flags = match data.properties.get("flags") {
                Some(String_(s)) => s
                _ => ""
              }
              return string_match_regex(str, pattern, flags)
            }
          _ => ()
        }
        // If not a RegExp, treat as string pattern
        let pattern = args[0].to_string()
        string_match_regex(str, pattern, "")
      })
    }
    "search" => {
      let str = s
      make_native_func("search", fn(args) {
        if args.length() == 0 {
          return Number(0.0)
        }
        match args[0] {
          Object(data) =>
            if data.class_name == "RegExp" {
              let pattern = match data.properties.get("source") {
                Some(String_(s)) => s
                _ => ""
              }
              let flags = match data.properties.get("flags") {
                Some(String_(s)) => s
                _ => ""
              }
              return string_search_regex(str, pattern, flags)
            }
          _ => ()
        }
        let pattern = args[0].to_string()
        string_search_regex(str, pattern, "")
      })
    }
    "startsWith" => {
      let str = s
      make_native_func("startsWith", fn(args) {
        let search = if args.length() > 0 {
          args[0].to_string()
        } else {
          "undefined"
        }
        let raw_pos = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let slen = str.length()
        let pos = if raw_pos < 0 {
          0
        } else if raw_pos > slen {
          slen
        } else {
          raw_pos
        }
        let search_chars = search.to_array()
        let s_chars = str.to_array()
        if pos + search_chars.length() > s_chars.length() {
          return Bool(false)
        }
        for i = 0; i < search_chars.length(); i = i + 1 {
          if s_chars[pos + i] != search_chars[i] {
            return Bool(false)
          }
        }
        Bool(true)
      })
    }
    "endsWith" => {
      let str = s
      make_native_func("endsWith", fn(args) {
        let search = if args.length() > 0 {
          args[0].to_string()
        } else {
          "undefined"
        }
        let slen = str.length()
        let raw_end = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          slen
        }
        let end_pos = if raw_end < 0 {
          0
        } else if raw_end > slen {
          slen
        } else {
          raw_end
        }
        let search_len = search.length()
        let start = end_pos - search_len
        if start < 0 {
          return Bool(false)
        }
        let s_chars = str.to_array()
        let search_chars = search.to_array()
        for i = 0; i < search_len; i = i + 1 {
          if s_chars[start + i] != search_chars[i] {
            return Bool(false)
          }
        }
        Bool(true)
      })
    }
    "repeat" => {
      let str = s
      make_native_func("repeat", fn(args) {
        let count = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        if count <= 0 {
          return String_("")
        }
        let buf = StringBuilder::new()
        for _i = 0; _i < count; _i = _i + 1 {
          buf.write_string(str)
        }
        String_(buf.to_string())
      })
    }
    "padStart" => {
      let str = s
      make_native_func("padStart", fn(args) {
        let target_len = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let pad_str = if args.length() > 1 { args[1].to_string() } else { " " }
        let slen = str.length()
        if slen >= target_len || pad_str.length() == 0 {
          return String_(str)
        }
        let buf = StringBuilder::new()
        let pad_chars = pad_str.to_array()
        let mut filled = 0
        let needed = target_len - slen
        while filled < needed {
          buf.write_char(pad_chars[filled % pad_chars.length()])
          filled = filled + 1
        }
        buf.write_string(str)
        String_(buf.to_string())
      })
    }
    "padEnd" => {
      let str = s
      make_native_func("padEnd", fn(args) {
        let target_len = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let pad_str = if args.length() > 1 { args[1].to_string() } else { " " }
        let slen = str.length()
        if slen >= target_len || pad_str.length() == 0 {
          return String_(str)
        }
        let buf = StringBuilder::new()
        buf.write_string(str)
        let pad_chars = pad_str.to_array()
        let mut filled = 0
        let needed = target_len - slen
        while filled < needed {
          buf.write_char(pad_chars[filled % pad_chars.length()])
          filled = filled + 1
        }
        String_(buf.to_string())
      })
    }
    "toString" | "valueOf" => {
      let str = s
      make_native_func(prop, fn(_args) { String_(str) })
    }
    "replaceAll" => {
      let str = s
      make_native_func("replaceAll", fn(args) {
        if args.length() == 0 {
          return String_(str)
        }
        // Check if first arg is RegExp
        match args[0] {
          Object(data) =>
            if data.class_name == "RegExp" {
              // RegExp must have global flag for replaceAll
              let flags = match data.properties.get("flags") {
                Some(String_(f)) => f
                _ => ""
              }
              if not(flags.to_array().contains('g')) {
                raise @errors.TypeError(message=
                  "replaceAll must be called with a global RegExp",
                )
              }
              let pattern = match data.properties.get("source") {
                Some(String_(s)) => s
                _ => ""
              }
              let replacement = if args.length() > 1 {
                args[1].to_string()
              } else {
                "undefined"
              }
              return string_replace_regex(str, pattern, flags, replacement)
            }
          _ => ()
        }
        let search = args[0].to_string()
        let replacement = if args.length() > 1 {
          args[1].to_string()
        } else {
          "undefined"
        }
        let slen = str.length()
        let search_len = search.length()
        if search_len == 0 {
          // Empty string: insert replacement before each char and at end
          let buf = StringBuilder::new()
          let s_chars = str.to_array()
          for c in s_chars {
            buf.write_string(replacement)
            buf.write_char(c)
          }
          buf.write_string(replacement)
          return String_(buf.to_string())
        }
        let s_chars = str.to_array()
        let search_chars = search.to_array()
        let buf = StringBuilder::new()
        let mut i = 0
        while i < slen {
          if i <= slen - search_len {
            let mut matched = true
            for j = 0; j < search_len; j = j + 1 {
              if s_chars[i + j] != search_chars[j] {
                matched = false
                break
              }
            }
            if matched {
              buf.write_string(replacement)
              i = i + search_len
              continue
            }
          }
          buf.write_char(s_chars[i])
          i = i + 1
        }
        String_(buf.to_string())
      })
    }
    "localeCompare" => {
      let str = s
      make_native_func("localeCompare", fn(args) {
        // Basic lexicographic comparison (no locale support)
        let other = if args.length() > 0 {
          args[0].to_string()
        } else {
          "undefined"
        }
        if str < other {
          Number(-1.0)
        } else if str > other {
          Number(1.0)
        } else {
          Number(0.0)
        }
      })
    }
    "normalize" => {
      let str = s
      make_native_func("normalize", fn(_args) {
        // STUB: Unicode normalization (NFC, NFD, NFKC, NFKD) is not implemented.
        // Returns the input string unchanged. Full implementation requires
        // Unicode normalization tables and algorithms.
        String_(str)
      })
    }
    "isWellFormed" => {
      let str = s
      make_native_func("isWellFormed", fn(_args) {
        // Check if string is well-formed UTF-16 (no lone surrogates)
        let c = str.to_array()
        let mut i = 0
        while i < c.length() {
          let code = c[i].to_int()
          if code >= 0xD800 && code <= 0xDBFF {
            // High surrogate - must be followed by low surrogate
            if i + 1 >= c.length() {
              return Bool(false)
            }
            let next = c[i + 1].to_int()
            if next < 0xDC00 || next > 0xDFFF {
              return Bool(false)
            }
            // Valid surrogate pair - skip the low surrogate
            i = i + 2
            continue
          } else if code >= 0xDC00 && code <= 0xDFFF {
            // Lone low surrogate
            return Bool(false)
          }
          i = i + 1
        }
        Bool(true)
      })
    }
    "toWellFormed" => {
      let str = s
      make_native_func("toWellFormed", fn(_args) {
        // Replace lone surrogates with U+FFFD
        let c = str.to_array()
        let buf = StringBuilder::new()
        let mut i = 0
        while i < c.length() {
          let code = c[i].to_int()
          if code >= 0xD800 && code <= 0xDBFF {
            if i + 1 < c.length() {
              let next = c[i + 1].to_int()
              if next >= 0xDC00 && next <= 0xDFFF {
                // Valid surrogate pair - write both and skip ahead
                buf.write_char(c[i])
                buf.write_char(c[i + 1])
                i = i + 2
                continue
              } else {
                buf.write_char('\u{FFFD}')
              }
            } else {
              buf.write_char('\u{FFFD}')
            }
          } else if code >= 0xDC00 && code <= 0xDFFF {
            buf.write_char('\u{FFFD}')
          } else {
            buf.write_char(c[i])
          }
          i = i + 1
        }
        String_(buf.to_string())
      })
    }
    _ => Undefined
  }
}

///|
fn string_trim(s : String) -> String {
  let trimmed_left = trim_start(s)
  string_trim_end(trimmed_left)
}

///|
fn string_trim_end(s : String) -> String {
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 {
    let c = chars[end - 1]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      end = end - 1
    } else {
      break
    }
  }
  if end == chars.length() {
    return s
  }
  let buf = StringBuilder::new()
  for i = 0; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

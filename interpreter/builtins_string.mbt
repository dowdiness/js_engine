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
        let sep = if args.length() > 0 {
          args[0].to_string()
        } else {
          return Array({ elements: [String_(str)] })
        }
        if sep.length() == 0 {
          let result : Array[Value] = str
            .to_array()
            .map(fn(c) {
              let buf = StringBuilder::new()
              buf.write_char(c)
              String_(buf.to_string())
            })
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
        // Remaining
        let buf = StringBuilder::new()
        for k = last; k < slen; k = k + 1 {
          buf.write_char(s_chars[k])
        }
        result.push(String_(buf.to_string()))
        Array({ elements: result })
      })
    }
    "replace" => {
      let str = s
      make_native_func("replace", fn(args) {
        let search = if args.length() > 0 {
          args[0].to_string()
        } else {
          return String_(str)
        }
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

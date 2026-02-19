///|
pub fn get_string_method(
  s : String,
  prop : String,
  annex_b? : Bool = false,
) -> Value {
  let chars = s.to_array()
  match prop {
    "charAt" =>
      make_native_func("charAt", fn(args) raise {
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
      make_native_func("charCodeAt", fn(args) raise {
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
      make_native_func("at", fn(args) raise {
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
      make_native_func("codePointAt", fn(args) raise {
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
      make_native_func("indexOf", fn(args) raise {
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
      make_native_func("lastIndexOf", fn(args) raise {
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
      make_native_func("includes", fn(args) raise {
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
      make_native_func("slice", fn(args) raise {
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
      make_native_func("substring", fn(args) raise {
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
          let lower = unicode_to_lower(code)
          buf.write_char(lower.unsafe_to_char())
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
          let upper = unicode_to_upper(code)
          buf.write_char(upper.unsafe_to_char())
        }
        String_(buf.to_string())
      })
    }
    "toLocaleLowerCase" => {
      // Locale-specific lowercase (currently uses same Unicode mapping)
      let str = s
      make_native_func("toLocaleLowerCase", fn(_args) {
        let s_chars = str.to_array()
        let buf = StringBuilder::new()
        for c in s_chars {
          let code = c.to_int()
          let lower = unicode_to_lower(code)
          buf.write_char(lower.unsafe_to_char())
        }
        String_(buf.to_string())
      })
    }
    "toLocaleUpperCase" => {
      // Locale-specific uppercase (currently uses same Unicode mapping)
      let str = s
      make_native_func("toLocaleUpperCase", fn(_args) {
        let s_chars = str.to_array()
        let buf = StringBuilder::new()
        for c in s_chars {
          let code = c.to_int()
          let upper = unicode_to_upper(code)
          buf.write_char(upper.unsafe_to_char())
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
    "trimLeft" => {
      let str = s
      make_native_func("trimLeft", fn(_args) { String_(trim_start(str)) })
    }
    "trimRight" => {
      let str = s
      make_native_func("trimRight", fn(_args) { String_(string_trim_end(str)) })
    }
    "toLocaleString" => {
      let str = s
      make_native_func("toLocaleString", fn(_args) { String_(str) })
    }
    "split" => {
      let str = s
      make_native_func("split", fn(args) raise {
        // Handle undefined separator - return array with whole string
        if args.length() == 0 {
          return Array({ elements: [String_(str)] })
        }
        match args[0] {
          Undefined => return Array({ elements: [String_(str)] })
          _ => ()
        }
        // Per spec: check for [Symbol.split] method on the argument
        match args[0] {
          Object(data) => {
            let split_sym = get_split_symbol()
            match data.symbol_properties.get(split_sym.id) {
              Some(Object(fn_data)) =>
                match fn_data.callable {
                  Some(MethodCallable(_, f)) => {
                    let limit = if args.length() > 1 {
                      args[1]
                    } else {
                      Undefined
                    }
                    return f(args[0], [String_(str), limit])
                  }
                  Some(NativeCallable(_, f)) => {
                    let limit = if args.length() > 1 {
                      args[1]
                    } else {
                      Undefined
                    }
                    return f([String_(str), limit])
                  }
                  _ => ()
                }
              _ => ()
            }
          }
          _ => ()
        }
        // Get limit parameter (default: 2^32 - 1 per ES spec)
        let limit : Int64 = if args.length() > 1 {
          match args[1] {
            Undefined => 4294967295L // 2^32 - 1
            _ => {
              let lim = to_number(args[1]).to_int64()
              if lim < 0L {
                0L
              } else {
                lim
              }
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
          let count = if chars_len < limit {
            chars.length()
          } else {
            limit.to_int()
          }
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
            // Per spec: if we've reached the limit, return immediately
            if result.length().to_int64() >= limit {
              return Array({ elements: result })
            }
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
      make_native_func("replace", fn(args) raise {
        if args.length() == 0 {
          return String_(str)
        }
        // Per spec: check for [Symbol.replace] method on the argument
        match args[0] {
          Object(data) => {
            let replace_sym = get_replace_symbol()
            match data.symbol_properties.get(replace_sym.id) {
              Some(Object(fn_data)) =>
                match fn_data.callable {
                  Some(MethodCallable(_, f)) => {
                    let rep = if args.length() > 1 {
                      args[1]
                    } else {
                      Undefined
                    }
                    return f(args[0], [String_(str), rep])
                  }
                  Some(NativeCallable(_, f)) => {
                    let rep = if args.length() > 1 {
                      args[1]
                    } else {
                      Undefined
                    }
                    return f([String_(str), rep])
                  }
                  _ => ()
                }
              _ => ()
            }
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
      make_native_func("match", fn(args) raise {
        if args.length() == 0 {
          return Null
        }
        // Per spec: check for [Symbol.match] method on the argument
        match args[0] {
          Object(data) => {
            let match_sym = get_match_symbol()
            match data.symbol_properties.get(match_sym.id) {
              Some(Object(fn_data)) =>
                match fn_data.callable {
                  Some(MethodCallable(_, f)) =>
                    return f(args[0], [String_(str)])
                  Some(NativeCallable(_, f)) => return f([String_(str)])
                  _ => ()
                }
              _ => ()
            }
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
          }
          _ => ()
        }
        // If not a RegExp, treat as string pattern
        let pattern = args[0].to_string()
        string_match_regex(str, pattern, "")
      })
    }
    "matchAll" => {
      let str = s
      make_native_func("matchAll", fn(args) raise {
        if args.length() == 0 {
          raise @errors.TypeError(message="matchAll requires a RegExp argument")
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
              // matchAll requires global flag
              if not(flags.contains("g")) {
                raise @errors.TypeError(
                  message="matchAll requires a RegExp with global flag",
                )
              }
              // Get all matches
              let matches = regex_search_all(pattern, flags, str) catch {
                _ => []
              }
              let input_chars = str.to_array()
              let index_ref : Ref[Int] = { val: 0 }
              // Create iterator with next() method
              let next_method = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  NativeCallable("next", fn(_args) {
                    let idx = index_ref.val
                    if idx < matches.length() {
                      let m = matches[idx]
                      index_ref.val = idx + 1
                      // Create match array with captures (like non-global match())
                      let elements : Array[Value] = []
                      elements.push(
                        String_(substring(input_chars, m.start, m.end_)),
                      )
                      for cap in m.captures {
                        match cap {
                          Some(c) => elements.push(String_(c))
                          None => elements.push(Undefined)
                        }
                      }
                      // TODO: Add index and input properties when ArrayData supports it
                      let match_array = Array({ elements, })
                      // Return {value: match_array, done: false}
                      let result_props : Map[String, Value] = {}
                      result_props["value"] = match_array
                      result_props["done"] = Bool(false)
                      Object({
                        properties: result_props,
                        symbol_properties: {},
                        prototype: Null,
                        callable: None,
                        class_name: "Object",
                        descriptors: {},
                        symbol_descriptors: {},
                        extensible: true,
                      })
                    } else {
                      // Return {value: undefined, done: true}
                      let result_props : Map[String, Value] = {}
                      result_props["value"] = Undefined
                      result_props["done"] = Bool(true)
                      Object({
                        properties: result_props,
                        symbol_properties: {},
                        prototype: Null,
                        callable: None,
                        class_name: "Object",
                        descriptors: {},
                        symbol_descriptors: {},
                        extensible: true,
                      })
                    }
                  }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              // Create iterator object with proper prototype
              let iter_props : Map[String, Value] = {}
              iter_props["next"] = next_method
              Object({
                properties: iter_props,
                symbol_properties: {},
                prototype: get_regexp_string_iterator_proto(),
                callable: None,
                class_name: "RegExp String Iterator",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
            } else {
              raise @errors.TypeError(
                message="matchAll requires a RegExp argument",
              )
            }
          _ =>
            raise @errors.TypeError(
              message="matchAll requires a RegExp argument",
            )
        }
      })
    }
    "search" => {
      let str = s
      make_native_func("search", fn(args) raise {
        if args.length() == 0 {
          return Number(0.0)
        }
        // Per spec: check for [Symbol.search] method on the argument
        match args[0] {
          Object(data) => {
            let search_sym = get_search_symbol()
            match data.symbol_properties.get(search_sym.id) {
              Some(Object(fn_data)) =>
                match fn_data.callable {
                  Some(MethodCallable(_, f)) =>
                    return f(args[0], [String_(str)])
                  Some(NativeCallable(_, f)) => return f([String_(str)])
                  _ => ()
                }
              _ => ()
            }
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
          }
          _ => ()
        }
        let pattern = args[0].to_string()
        string_search_regex(str, pattern, "")
      })
    }
    "startsWith" => {
      let str = s
      make_native_func("startsWith", fn(args) raise {
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
      make_native_func("endsWith", fn(args) raise {
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
      make_native_func("repeat", fn(args) raise {
        let count_num = if args.length() > 0 { to_number(args[0]) } else { 0.0 }
        // Check for negative or infinite count
        if count_num < 0.0 || count_num.is_inf() {
          raise @errors.RangeError(message="Invalid repeat count")
        }
        let count = count_num.to_int()
        if count == 0 {
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
      make_native_func("padStart", fn(args) raise {
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
      make_native_func("padEnd", fn(args) raise {
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
      make_native_func("replaceAll", fn(args) raise {
        if args.length() == 0 {
          return String_(str)
        }
        // Per spec §22.1.3.19: if searchValue is a RegExp, require global flag FIRST
        match args[0] {
          Object(data) =>
            if data.class_name == "RegExp" {
              let flags = match data.properties.get("flags") {
                Some(String_(f)) => f
                _ => ""
              }
              if not(flags.to_array().contains('g')) {
                raise @errors.TypeError(
                  message="replaceAll must be called with a global RegExp",
                )
              }
            }
          _ => ()
        }
        // Per spec: check for [Symbol.replace] method on the argument
        match args[0] {
          Object(data) => {
            let replace_sym = get_replace_symbol()
            match data.symbol_properties.get(replace_sym.id) {
              Some(Object(fn_data)) =>
                match fn_data.callable {
                  Some(MethodCallable(_, f)) => {
                    let rep = if args.length() > 1 {
                      args[1]
                    } else {
                      Undefined
                    }
                    return f(args[0], [String_(str), rep])
                  }
                  Some(NativeCallable(_, f)) => {
                    let rep = if args.length() > 1 {
                      args[1]
                    } else {
                      Undefined
                    }
                    return f([String_(str), rep])
                  }
                  _ => ()
                }
              _ => ()
            }
          }
          _ => ()
        }
        // Fallback for RegExp without Symbol.replace
        match args[0] {
          Object(data) =>
            if data.class_name == "RegExp" {
              let flags = match data.properties.get("flags") {
                Some(String_(f)) => f
                _ => ""
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
    // Annex B HTML string methods (B.2.2.2 - B.2.2.14) — only when --annex-b
    "anchor"
    | "big"
    | "blink"
    | "bold"
    | "fixed"
    | "fontcolor"
    | "fontsize"
    | "italics"
    | "link"
    | "small"
    | "strike"
    | "sub"
    | "sup" =>
      if not(annex_b) {
        Undefined
      } else {
        match prop {
          "anchor" =>
            make_native_func("anchor", fn(args) {
              let name = if args.length() > 0 {
                args[0].to_string()
              } else {
                "undefined"
              }
              String_(
                "<a name=\"" + escape_html_attr(name) + "\">" + s + "</a>",
              )
            })
          "big" =>
            make_native_func("big", fn(_args) {
              String_("<big>" + s + "</big>")
            })
          "blink" =>
            make_native_func("blink", fn(_args) {
              String_("<blink>" + s + "</blink>")
            })
          "bold" =>
            make_native_func("bold", fn(_args) { String_("<b>" + s + "</b>") })
          "fixed" =>
            make_native_func("fixed", fn(_args) {
              String_("<tt>" + s + "</tt>")
            })
          "fontcolor" =>
            make_native_func("fontcolor", fn(args) {
              let color = if args.length() > 0 {
                args[0].to_string()
              } else {
                "undefined"
              }
              String_(
                "<font color=\"" +
                escape_html_attr(color) +
                "\">" +
                s +
                "</font>",
              )
            })
          "fontsize" =>
            make_native_func("fontsize", fn(args) {
              let size = if args.length() > 0 {
                args[0].to_string()
              } else {
                "undefined"
              }
              String_(
                "<font size=\"" + escape_html_attr(size) + "\">" + s + "</font>",
              )
            })
          "italics" =>
            make_native_func("italics", fn(_args) {
              String_("<i>" + s + "</i>")
            })
          "link" =>
            make_native_func("link", fn(args) {
              let url = if args.length() > 0 {
                args[0].to_string()
              } else {
                "undefined"
              }
              String_("<a href=\"" + escape_html_attr(url) + "\">" + s + "</a>")
            })
          "small" =>
            make_native_func("small", fn(_args) {
              String_("<small>" + s + "</small>")
            })
          "strike" =>
            make_native_func("strike", fn(_args) {
              String_("<strike>" + s + "</strike>")
            })
          "sub" =>
            make_native_func("sub", fn(_args) {
              String_("<sub>" + s + "</sub>")
            })
          "sup" =>
            make_native_func("sup", fn(_args) {
              String_("<sup>" + s + "</sup>")
            })
          _ => Undefined
        }
      }
    _ => Undefined
  }
}

///|
/// Escape double-quotes in attribute values per CreateHTML (ECMA-262 Annex B)
fn escape_html_attr(value : String) -> String {
  let chars = value.to_array()
  let buf = StringBuilder::new()
  for c in chars {
    if c == '"' {
      buf.write_string("&quot;")
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Unicode-aware character to lowercase conversion
fn unicode_to_lower(code : Int) -> Int {
  // ASCII uppercase (A-Z)
  if code >= 65 && code <= 90 {
    return code + 32
  }
  // Latin-1 Supplement (U+00C0-U+00DE, excluding U+00D7 multiplication sign)
  if code >= 0xC0 && code <= 0xDE && code != 0xD7 {
    return code + 32
  }
  // Latin Extended-A (U+0100-U+017F) - even codes are uppercase
  if code >= 0x100 && code <= 0x12E {
    if (code & 1) == 0 {
      return code + 1
    }
  }
  if code >= 0x132 && code <= 0x136 {
    if (code & 1) == 0 {
      return code + 1
    }
  }
  if code >= 0x139 && code <= 0x147 {
    if (code & 1) == 1 {
      return code + 1
    }
  }
  if code >= 0x14A && code <= 0x176 {
    if (code & 1) == 0 {
      return code + 1
    }
  }
  // Greek uppercase (U+0391-U+03A9, U+03AA-U+03AB)
  if code >= 0x391 && code <= 0x3A9 {
    return code + 32
  }
  if code >= 0x3AA && code <= 0x3AB {
    return code + 32
  }
  // Cyrillic uppercase (U+0410-U+042F)
  if code >= 0x410 && code <= 0x42F {
    return code + 32
  }
  // Special cases
  match code {
    0x178 => 0xFF // Ÿ -> ÿ
    0x179 => 0x17A // Ź -> ź
    0x17B => 0x17C // Ż -> ż
    0x17D => 0x17E // Ž -> ž
    0x181 => 0x253 // Ɓ -> ɓ
    0x186 => 0x254 // Ɔ -> ɔ
    0x189 => 0x256 // Ɖ -> ɖ
    0x18A => 0x257 // Ɗ -> ɗ
    0x18E => 0x1DD // Ǝ -> ǝ
    0x18F => 0x259 // Ə -> ə
    0x190 => 0x25B // Ɛ -> ɛ
    0x193 => 0x260 // Ɠ -> ɠ
    0x194 => 0x263 // Ɣ -> ɣ
    0x197 => 0x268 // Ɨ -> ɨ
    0x196 => 0x269 // Ɩ -> ɩ
    0x19C => 0x26F // Ɯ -> ɯ
    0x19D => 0x272 // Ɲ -> ɲ
    0x19F => 0x275 // Ɵ -> ɵ
    _ => code
  }
}

///|
/// Unicode-aware character to uppercase conversion
fn unicode_to_upper(code : Int) -> Int {
  // ASCII lowercase (a-z)
  if code >= 97 && code <= 122 {
    return code - 32
  }
  // Latin-1 Supplement lowercase (U+00E0-U+00FE, excluding U+00F7 division sign)
  if code >= 0xE0 && code <= 0xFE && code != 0xF7 {
    return code - 32
  }
  // Latin Extended-A (U+0100-U+017F) - odd codes are lowercase
  if code >= 0x101 && code <= 0x12F {
    if (code & 1) == 1 {
      return code - 1
    }
  }
  if code >= 0x133 && code <= 0x137 {
    if (code & 1) == 1 {
      return code - 1
    }
  }
  if code >= 0x13A && code <= 0x148 {
    if (code & 1) == 0 {
      return code - 1
    }
  }
  if code >= 0x14B && code <= 0x177 {
    if (code & 1) == 1 {
      return code - 1
    }
  }
  // Greek lowercase (U+03B1-U+03C9, U+03CA-U+03CB)
  if code >= 0x3B1 && code <= 0x3C9 {
    return code - 32
  }
  if code >= 0x3CA && code <= 0x3CB {
    return code - 32
  }
  // Cyrillic lowercase (U+0430-U+044F)
  if code >= 0x430 && code <= 0x44F {
    return code - 32
  }
  // Special cases
  match code {
    0xFF => 0x178 // ÿ -> Ÿ
    0x17A => 0x179 // ź -> Ź
    0x17C => 0x17B // ż -> Ż
    0x17E => 0x17D // ž -> Ž
    0x253 => 0x181 // ɓ -> Ɓ
    0x254 => 0x186 // ɔ -> Ɔ
    0x256 => 0x189 // ɖ -> Ɖ
    0x257 => 0x18A // ɗ -> Ɗ
    0x1DD => 0x18E // ǝ -> Ǝ
    0x259 => 0x18F // ə -> Ə
    0x25B => 0x190 // ɛ -> Ɛ
    0x260 => 0x193 // ɠ -> Ɠ
    0x263 => 0x194 // ɣ -> Ɣ
    0x268 => 0x197 // ɨ -> Ɨ
    0x269 => 0x196 // ɩ -> Ɩ
    0x26F => 0x19C // ɯ -> Ɯ
    0x272 => 0x19D // ɲ -> Ɲ
    0x275 => 0x19F // ɵ -> Ɵ
    _ => code
  }
}

///|
fn string_trim(s : String) -> String {
  let trimmed_left = trim_start(s)
  string_trim_end(trimmed_left)
}

///|
/// Extract string from a this value (for String.prototype methods called via .call())
pub fn this_to_string(this_val : Value) -> String raise Error {
  match this_val {
    String_(s) => s
    Number(n) => n.to_string()
    Bool(b) => if b { "true" } else { "false" }
    Null =>
      raise @errors.TypeError(message="String.prototype method called on null")
    Undefined =>
      raise @errors.TypeError(
        message="String.prototype method called on undefined",
      )
    Symbol(_) =>
      raise @errors.TypeError(
        message="Cannot convert a Symbol value to a string",
      )
    Object(data) =>
      // Check if it's a boxed String wrapper object
      if data.class_name == "String" {
        match data.properties.get("[[StringData]]") {
          Some(String_(s)) => s
          _ => this_val.to_string()
        }
      } else {
        this_val.to_string()
      }
    _ => this_val.to_string()
  }
}

///|
/// Populate String.prototype with all string methods
pub fn setup_string_prototype(
  string_proto : Value,
  annex_b? : Bool = false,
) -> Unit {
  match string_proto {
    Object(data) => {
      let methods : Array[String] = [
        "charAt", "charCodeAt", "at", "codePointAt", "indexOf", "lastIndexOf", "includes",
        "startsWith", "endsWith", "slice", "substring", "toUpperCase", "toLowerCase",
        "trim", "trimStart", "trimEnd", "trimLeft", "trimRight", "padStart", "padEnd",
        "repeat", "replace", "replaceAll", "split", "search", "match", "matchAll",
        "concat", "normalize", "isWellFormed", "toWellFormed", "localeCompare", "toLocaleString",
        "toString", "valueOf",
      ]
      // Annex B HTML string methods — only when --annex-b is enabled
      if annex_b {
        let annex_b_methods = [
          "anchor", "big", "blink", "bold", "fixed", "fontcolor", "fontsize", "italics",
          "link", "small", "strike", "sub", "sup",
        ]
        for m in annex_b_methods {
          methods.push(m)
        }
      }
      for method_name in methods {
        let mname = method_name
        data.properties[mname] = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            MethodCallable(mname, fn(this_val, args) raise {
              let s = this_to_string(this_val)
              let meth_val = get_string_method(s, mname, annex_b~)
              match meth_val {
                Object(fdata) =>
                  match fdata.callable {
                    Some(NativeCallable(_, f)) => f(args)
                    _ => Undefined
                  }
                _ => Undefined
              }
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        // Make methods non-enumerable
        data.descriptors[mname] = {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
        }
      }
      // Add constructor back-reference placeholder
      data.properties["constructor"] = Undefined
    }
    _ => ()
  }
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

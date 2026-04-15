///|
fn setup_json_builtins(env : Environment) -> Unit {
  let json_props : Map[String, Value] = {}
  let json_descs : Map[String, PropDescriptor] = {}
  let ne_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  json_props["parse"] = @runtime.make_interp_static_func_with_length(
    "parse",
    2,
    fn(interp, args) raise {
      let str = if args.length() > 0 {
        @runtime.to_js_string(args[0])
      } else {
        ""
      }
      let result = json_parse(str)
      // Handle reviver
      if args.length() > 1 && @runtime.is_callable(args[1]) {
        // Wrap in a root holder object
        let root_props : Map[String, Value] = {}
        root_props[""] = result
        let root : Value = Value::Object({
          properties: root_props,
          symbol_properties: {},
          prototype: Null,
          callable: None,
          class_name: "Object",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        return json_internalize(root, "", args[1], interp)
      }
      result
    },
  )
  json_descs["parse"] = ne_desc
  json_props["stringify"] = @runtime.make_interp_method_func("stringify", 3, fn(
    interp,
    _this,
    args,
  ) raise {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    let indent = if args.length() > 2 {
      // Per spec: unwrap Number/String objects, cap at 10
      let space_arg = match args[2] {
        Object(data) =>
          if data.class_name == "Number" {
            match data.properties.get("[[NumberData]]") {
              Some(n) => n
              None => args[2]
            }
          } else if data.class_name == "String" {
            match data.properties.get("[[StringData]]") {
              Some(s) => s
              None => args[2]
            }
          } else {
            args[2]
          }
        _ => args[2]
      }
      match space_arg {
        Value::Number(n) => {
          let spaces = if n.to_int() > 10 { 10 } else { n.to_int() }
          if spaces > 0 {
            let buf = StringBuilder::new()
            for _i = 0; _i < spaces; _i = _i + 1 {
              buf.write_char(' ')
            }
            Some(buf.to_string())
          } else {
            None
          }
        }
        Value::String_(s) =>
          if s.length() > 10 {
            Some(s[:10].to_string())
          } else if s.length() > 0 {
            Some(s)
          } else {
            None
          }
        _ => None
      }
    } else {
      None
    }
    let replacer : Value? = if args.length() > 1 &&
      @runtime.is_callable(args[1]) {
      Some(args[1])
    } else {
      None
    }
    // Handle replacer array (property list filter)
    let property_list : Array[String]? = if args.length() > 1 {
      match args[1] {
        Value::Array(arr) => {
          let keys : Array[String] = []
          for elem in arr.elements {
            match elem {
              Value::String_(s) => keys.push(s)
              Value::Number(n) => keys.push(n.to_string())
              _ => ()
            }
          }
          Some(keys)
        }
        _ => None
      }
    } else {
      None
    }
    // Wrap value in root holder for replacer
    let root_props : Map[String, Value] = {}
    root_props[""] = val
    let root : Value = Value::Object({
      properties: root_props,
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "Object",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })
    let seen : Array[Value] = []
    json_stringify_value(
      val,
      seen,
      indent,
      0,
      Some(interp),
      replacer~,
      holder=root,
      key="",
      property_list~,
    )
  })
  json_descs["stringify"] = ne_desc
  // Symbol.toStringTag = "JSON"
  let tostringtag_sym = @runtime.get_tostringtag_symbol()
  let json_sym_props : Map[Int, Value] = {}
  let json_sym_descs : Map[Int, PropDescriptor] = {}
  json_sym_props[tostringtag_sym.id] = Value::String_("JSON")
  json_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let obj_proto = match env.bindings.get("[[ObjectPrototype]]") {
    Some(b) => b.value
    None => Null
  }
  env.def_builtin(
    "JSON",
    Value::Object({
      properties: json_props,
      symbol_properties: json_sym_props,
      prototype: obj_proto,
      callable: None,
      class_name: "JSON",
      descriptors: json_descs,
      symbol_descriptors: json_sym_descs,
      extensible: true,
    }),
  )
}

///|
fn json_parse(input : String) -> Value raise Error {
  let chars = input.to_array()
  let len = chars.length()
  let pos : Array[Int] = [0] // mutable position
  fn skip_ws() -> Unit {
    while pos[0] < len {
      let c = chars[pos[0]]
      if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
        pos[0] += 1
      } else {
        break
      }
    }
  }

  letrec parse_value = fn() -> Value raise Error {
    skip_ws()
    if pos[0] >= len {
      raise @errors.SyntaxError(message="Unexpected end of JSON input")
    }
    let c = chars[pos[0]]
    if c == '"' {
      parse_string()
    } else if c == '{' {
      parse_object()
    } else if c == '[' {
      parse_array()
    } else if c == 't' {
      if pos[0] + 4 <= len &&
        chars[pos[0] + 1] == 'r' &&
        chars[pos[0] + 2] == 'u' &&
        chars[pos[0] + 3] == 'e' {
        pos[0] += 4
        Value::Bool(true)
      } else {
        raise @errors.SyntaxError(
          message="Unexpected token in JSON at position \{pos[0]}",
        )
      }
    } else if c == 'f' {
      if pos[0] + 5 <= len &&
        chars[pos[0] + 1] == 'a' &&
        chars[pos[0] + 2] == 'l' &&
        chars[pos[0] + 3] == 's' &&
        chars[pos[0] + 4] == 'e' {
        pos[0] += 5
        Value::Bool(false)
      } else {
        raise @errors.SyntaxError(
          message="Unexpected token in JSON at position \{pos[0]}",
        )
      }
    } else if c == 'n' {
      if pos[0] + 4 <= len &&
        chars[pos[0] + 1] == 'u' &&
        chars[pos[0] + 2] == 'l' &&
        chars[pos[0] + 3] == 'l' {
        pos[0] += 4
        Null
      } else {
        raise @errors.SyntaxError(
          message="Unexpected token in JSON at position \{pos[0]}",
        )
      }
    } else if c == '-' || (c >= '0' && c <= '9') {
      parse_number()
    } else {
      raise @errors.SyntaxError(
        message="Unexpected token in JSON at position \{pos[0]}",
      )
    }
  }
  and parse_string = fn() -> Value raise Error {
    pos[0] += 1 // skip opening "
    let buf = StringBuilder::new()
    while pos[0] < len {
      let ch = chars[pos[0]]
      if ch == '"' {
        pos[0] += 1
        return Value::String_(buf.to_string())
      }
      if ch == '\\' {
        pos[0] += 1
        if pos[0] >= len {
          raise @errors.SyntaxError(message="Unexpected end of JSON input")
        }
        let esc = chars[pos[0]]
        match esc {
          '"' => buf.write_char('"')
          '\\' => buf.write_char('\\')
          '/' => buf.write_char('/')
          'b' => buf.write_char('\u0008')
          'f' => buf.write_char('\u000C')
          'n' => buf.write_char('\n')
          'r' => buf.write_char('\r')
          't' => buf.write_char('\t')
          'u' =>
            if pos[0] + 4 < len {
              let mut code = 0
              for _j = 0; _j < 4; _j = _j + 1 {
                pos[0] += 1
                let hex_c = chars[pos[0]]
                let d = char_to_digit(hex_c, 16)
                if d < 0 {
                  raise @errors.SyntaxError(
                    message="Invalid unicode escape in JSON",
                  )
                }
                code = code * 16 + d
              }
              buf.write_char(code.unsafe_to_char())
            } else {
              raise @errors.SyntaxError(
                message="Invalid unicode escape in JSON",
              )
            }
          _ =>
            raise @errors.SyntaxError(
              message="Invalid escape character in JSON",
            )
        }
      } else {
        if ch.to_int() < 32 {
          raise @errors.SyntaxError(
            message="Unexpected control character in JSON",
          )
        }
        buf.write_char(ch)
      }
      pos[0] += 1
    }
    raise @errors.SyntaxError(message="Unterminated string in JSON")
  }
  and parse_number = fn() -> Value raise Error {
    let start = pos[0]
    if pos[0] < len && chars[pos[0]] == '-' {
      pos[0] += 1
    }
    while pos[0] < len && chars[pos[0]] >= '0' && chars[pos[0]] <= '9' {
      pos[0] += 1
    }
    if pos[0] < len && chars[pos[0]] == '.' {
      pos[0] += 1
      while pos[0] < len && chars[pos[0]] >= '0' && chars[pos[0]] <= '9' {
        pos[0] += 1
      }
    }
    if pos[0] < len && (chars[pos[0]] == 'e' || chars[pos[0]] == 'E') {
      pos[0] += 1
      if pos[0] < len && (chars[pos[0]] == '+' || chars[pos[0]] == '-') {
        pos[0] += 1
      }
      while pos[0] < len && chars[pos[0]] >= '0' && chars[pos[0]] <= '9' {
        pos[0] += 1
      }
    }
    let buf = StringBuilder::new()
    for i = start; i < pos[0]; i = i + 1 {
      buf.write_char(chars[i])
    }
    let n = @string.parse_double(buf.to_string()) catch {
      _ => raise @errors.SyntaxError(message="Invalid number in JSON")
    }
    Value::Number(n)
  }
  and parse_object = fn() -> Value raise Error {
    pos[0] += 1 // skip {
    let properties : Map[String, Value] = {}
    skip_ws()
    if pos[0] < len && chars[pos[0]] == '}' {
      pos[0] += 1
      return Value::Object({
        properties,
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Object",
        descriptors: {},
        symbol_descriptors: {},
        extensible: true,
      })
    }
    while true {
      skip_ws()
      if pos[0] >= len || chars[pos[0]] != '"' {
        raise @errors.SyntaxError(
          message="Expected property name in JSON at position \{pos[0]}",
        )
      }
      let key = match parse_string() {
        Value::String_(s) => s
        _ => ""
      }
      skip_ws()
      if pos[0] >= len || chars[pos[0]] != ':' {
        raise @errors.SyntaxError(
          message="Expected ':' in JSON at position \{pos[0]}",
        )
      }
      pos[0] += 1
      let value = parse_value()
      properties[key] = value
      skip_ws()
      if pos[0] < len && chars[pos[0]] == ',' {
        pos[0] += 1
      } else {
        break
      }
    }
    skip_ws()
    if pos[0] >= len || chars[pos[0]] != '}' {
      raise @errors.SyntaxError(
        message="Expected '}' in JSON at position \{pos[0]}",
      )
    }
    pos[0] += 1
    Value::Object({
      properties,
      symbol_properties: {},
      prototype: Null,
      callable: None,
      class_name: "Object",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    })
  }
  and parse_array = fn() -> Value raise Error {
    pos[0] += 1 // skip [
    let elements : Array[Value] = []
    skip_ws()
    if pos[0] < len && chars[pos[0]] == ']' {
      pos[0] += 1
      return Value::Array({ elements, })
    }
    while true {
      let val = parse_value()
      elements.push(val)
      skip_ws()
      if pos[0] < len && chars[pos[0]] == ',' {
        pos[0] += 1
      } else {
        break
      }
    }
    skip_ws()
    if pos[0] >= len || chars[pos[0]] != ']' {
      raise @errors.SyntaxError(
        message="Expected ']' in JSON at position \{pos[0]}",
      )
    }
    pos[0] += 1
    Value::Array({ elements, })
  }

  let result = parse_value()
  skip_ws()
  if pos[0] < len {
    raise @errors.SyntaxError(
      message="Unexpected non-whitespace character after JSON at position \{pos[0]}",
    )
  }
  result
}

///|
/// InternalizeJSONProperty - walks the parsed value and calls the reviver
fn json_internalize(
  holder : Value,
  name : String,
  reviver : Value,
  interp : Interpreter,
) -> Value raise Error {
  let val = match holder {
    Object(data) =>
      match data.properties.get(name) {
        Some(v) => v
        None => Undefined
      }
    Array(arr_data) => {
      let idx = @string.parse_int(name) catch { _ => -1 }
      if idx >= 0 && idx < arr_data.elements.length() {
        arr_data.elements[idx]
      } else {
        Undefined
      }
    }
    _ => Undefined
  }
  // Recurse into objects and arrays
  match val {
    Object(data) => {
      let keys : Array[String] = []
      for key, _ in data.properties {
        keys.push(key)
      }
      for key in keys {
        let new_val = json_internalize(val, key, reviver, interp)
        match new_val {
          Undefined =>
            // Delete the property
            data.properties.remove(key)
          _ => data.properties[key] = new_val
        }
      }
    }
    Array(arr_data) =>
      for i = 0; i < arr_data.elements.length(); i = i + 1 {
        let new_val = json_internalize(val, i.to_string(), reviver, interp)
        match new_val {
          Undefined => arr_data.elements[i] = Undefined
          _ => arr_data.elements[i] = new_val
        }
      }
    _ => ()
  }
  // Call reviver with (holder, name, val)
  interp.call_value(
    reviver,
    holder,
    [Value::String_(name), val],
    @token.Loc::default(),
  )
}

///|
fn json_stringify_value(
  val : Value,
  seen : Array[Value],
  indent : String?,
  depth : Int,
  interp : Interpreter?,
  replacer? : Value? = None,
  holder? : Value = Undefined,
  key? : String = "",
  property_list? : Array[String]? = None,
) -> Value raise Error {
  // Step 1: Apply replacer function if provided
  let val = match replacer {
    Some(replacer_fn) =>
      match interp {
        Some(ip) =>
          ip.call_value(
            replacer_fn,
            holder,
            [Value::String_(key), val],
            @token.Loc::default(),
          )
        None => val
      }
    None => val
  }
  match val {
    Undefined => Undefined
    Null => Value::String_("null")
    Value::Bool(b) => Value::String_(b.to_string())
    Value::Number(n) =>
      if n.is_nan() || n.is_inf() {
        Value::String_("null")
      } else {
        Value::String_(val.to_string())
      }
    Value::String_(s) => Value::String_(json_escape_string(s))
    Symbol(_) => Undefined // Symbols are omitted from JSON
    Map(_) => Value::String_("{}") // Maps serialize as empty objects
    Set(_) => Value::String_("{}") // Sets serialize as empty objects
    Promise(_) => Value::String_("{}") // Promises serialize as empty objects
    Value::Proxy(proxy_data) =>
      // Unwrap proxy to its target and serialize that
      match proxy_data.target {
        Some(target) =>
          json_stringify_value(
            target,
            seen,
            indent,
            depth,
            interp,
            replacer~,
            property_list~,
          )
        None => Value::String_("{}")
      }
    Value::Array(data) => {
      // Cycle detection
      for s in seen {
        match s {
          Array(sd) =>
            if physical_equal(sd, data) {
              raise @errors.TypeError(
                message="Converting circular structure to JSON",
              )
            }
          _ => ()
        }
      }
      seen.push(val)
      let new_depth = depth + 1
      let buf = StringBuilder::new()
      buf.write_char('[')
      let mut first = true
      for idx, el in data.elements {
        let stringified = json_stringify_value(
          el,
          seen,
          indent,
          new_depth,
          interp,
          replacer~,
          holder=val,
          key=idx.to_string(),
          property_list~,
        )
        match stringified {
          Undefined => {
            if !first {
              buf.write_char(',')
              match indent {
                Some(_) => ()
                None => ()
              }
            }
            first = false
            match indent {
              Some(ind) => {
                buf.write_char('\n')
                for _i = 0; _i < new_depth; _i = _i + 1 {
                  buf.write_string(ind)
                }
              }
              None => ()
            }
            buf.write_string("null")
          }
          Value::String_(s) => {
            if !first {
              buf.write_char(',')
            }
            first = false
            match indent {
              Some(ind) => {
                buf.write_char('\n')
                for _i = 0; _i < new_depth; _i = _i + 1 {
                  buf.write_string(ind)
                }
              }
              None => ()
            }
            buf.write_string(s)
          }
          _ => ()
        }
      }
      match indent {
        Some(ind) =>
          if data.elements.length() > 0 {
            buf.write_char('\n')
            for _i = 0; _i < depth; _i = _i + 1 {
              buf.write_string(ind)
            }
          }
        None => ()
      }
      buf.write_char(']')
      let _ = seen.pop()
      Value::String_(buf.to_string())
    }
    Object(data) =>
      match data.callable {
        Some(_) => Undefined // Functions are not serialized
        None => {
          // Unwrap boxed primitives per spec (SerializeJSONProperty step 4)
          if data.class_name == "Number" {
            match data.properties.get("[[NumberData]]") {
              Some(Value::Number(n)) =>
                return if n.is_nan() || n.is_inf() {
                  Value::String_("null")
                } else {
                  Value::String_(Value::Number(n).to_string())
                }
              _ => ()
            }
          } else if data.class_name == "String" {
            match data.properties.get("[[StringData]]") {
              Some(Value::String_(s)) =>
                return Value::String_(json_escape_string(s))
              _ => ()
            }
          } else if data.class_name == "Boolean" {
            match data.properties.get("[[BooleanData]]") {
              Some(Value::Bool(b)) => return Value::String_(b.to_string())
              _ => ()
            }
          }
          // Check for toJSON method by walking the full prototype chain
          let mut to_json_fn : Value? = None
          let mut cur : Value? = Some(val)
          while to_json_fn is None {
            match cur {
              Some(Object(obj_data)) =>
                match obj_data.properties.get("toJSON") {
                  Some(v) => to_json_fn = Some(v)
                  None => cur = Some(obj_data.prototype)
                }
              _ => break
            }
          }
          match to_json_fn {
            Some(Object(to_json_data)) =>
              match to_json_data.callable {
                Some(_) => {
                  let to_json_obj : Value = Object(to_json_data)
                  let json_val : Value? = match interp {
                    Some(ip) =>
                      Some(
                        ip.call_value(
                          to_json_obj,
                          val,
                          [],
                          @token.Loc::default(),
                        ),
                      )
                    None =>
                      // Fallback for calls without interpreter access
                      match to_json_data.callable {
                        Some(MethodCallable(_, func)) => Some(func(val, []))
                        Some(NativeCallable(_, func)) => Some(func([]))
                        Some(NonConstructableCallable(_, func)) =>
                          Some(func([]))
                        _ => None // cannot call without interpreter, skip
                      }
                  }
                  match json_val {
                    Some(v) =>
                      return json_stringify_value(
                        v,
                        seen,
                        indent,
                        depth,
                        interp,
                        replacer~,
                        property_list~,
                      )
                    None => ()
                  }
                }
                None => ()
              }
            _ => ()
          }
          // Cycle detection
          for s in seen {
            match s {
              Object(sd) =>
                if physical_equal(sd, data) {
                  raise @errors.TypeError(
                    message="Converting circular structure to JSON",
                  )
                }
              _ => ()
            }
          }
          seen.push(val)
          let new_depth = depth + 1
          let buf = StringBuilder::new()
          buf.write_char('{')
          let mut first = true
          // Use property list (from replacer array) or sorted keys
          let keys_to_iterate : Array[String] = match property_list {
            Some(pl) => pl
            None => {
              let sorted = @runtime.sort_property_keys(data.properties)
              let filtered : Array[String] = []
              for k in sorted {
                // Skip non-enumerable properties
                let enumerable = match data.descriptors.get(k) {
                  Some(d) => d.enumerable
                  None => true
                }
                if enumerable {
                  filtered.push(k)
                }
              }
              filtered
            }
          }
          for k in keys_to_iterate {
            let v = match data.properties.get(k) {
              Some(v) => v
              None => continue
            }
            let stringified = json_stringify_value(
              v,
              seen,
              indent,
              new_depth,
              interp,
              replacer~,
              holder=val,
              key=k,
              property_list~,
            )
            match stringified {
              Undefined => () // Skip undefined values
              Value::String_(s) => {
                if !first {
                  buf.write_char(',')
                }
                first = false
                match indent {
                  Some(ind) => {
                    buf.write_char('\n')
                    for _i = 0; _i < new_depth; _i = _i + 1 {
                      buf.write_string(ind)
                    }
                  }
                  None => ()
                }
                buf.write_string(json_escape_string(k))
                buf.write_char(':')
                match indent {
                  Some(_) => buf.write_char(' ')
                  None => ()
                }
                buf.write_string(s)
              }
              _ => ()
            }
          }
          match indent {
            Some(ind) =>
              if !first {
                buf.write_char('\n')
                for _i = 0; _i < depth; _i = _i + 1 {
                  buf.write_string(ind)
                }
              }
            None => ()
          }
          buf.write_char('}')
          let _ = seen.pop()
          Value::String_(buf.to_string())
        }
      }
  }
}

///|
fn json_escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  let chars = s.to_array()
  for c in chars {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ if c.to_int() == 0x08 => buf.write_string("\\b")
      _ if c.to_int() == 0x0C => buf.write_string("\\f")
      _ =>
        if c.to_int() < 32 {
          buf.write_string("\\u")
          let code = c.to_int()
          let hex_digits = "0123456789abcdef"
          let hd = hex_digits.to_array()
          buf.write_char(hd[(code >> 12) & 0xf])
          buf.write_char(hd[(code >> 8) & 0xf])
          buf.write_char(hd[(code >> 4) & 0xf])
          buf.write_char(hd[code & 0xf])
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

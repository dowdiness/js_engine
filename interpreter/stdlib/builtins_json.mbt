///|
fn setup_json_builtins(
  env : Environment,
  well_known_symbols : @runtime.WellKnownSymbols,
) -> Unit {
  let json_props : Map[String, Value] = {}
  let json_descs : Map[String, PropDescriptor] = {}
  let ne_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  json_props["parse"] = @runtime.make_interp_static_func(
    name="parse",
    length=2,
    fn(interp, args) raise {
      let str = if args.length() > 0 {
        interp.to_js_string(args[0])
      } else {
        ""
      }
      let result = json_parse(str, interp)
      // Handle reviver
      if args.length() > 1 && @runtime.is_callable(args[1]) {
        // Wrap in a root holder object with Object.prototype as prototype
        // and the parsed value as a data property (CreateDataPropertyOrThrow
        // semantics: writable/enumerable/configurable).
        let root_props : Map[String, Value] = {}
        root_props[""] = result
        let root_descs : Map[String, PropDescriptor] = {}
        root_descs[""] = {
          writable: true,
          enumerable: true,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        }
        let root : Value = Value::Object({
          bag: {
            properties: root_props,
            symbol_properties: {},
            descriptors: root_descs,
            symbol_descriptors: {},
            internal_slots: {},
            host_slots: {},
          },
          prototype: interp.realm_state.get_obj_proto(),
          callable: None,
          class_name: "Object",
          extensible: true,
          arraybuffer_state: None,
        })
        return json_internalize(root, "", args[1], interp)
      }
      result
    },
  )
  json_descs["parse"] = ne_desc
  json_props["stringify"] = @runtime.make_interp_method_func(
    name="stringify",
    length=3,
    fn(interp, _this, args) raise {
      let val = if args.length() > 0 { args[0] } else { Undefined }
      let indent = if args.length() > 2 {
        // Per spec: unwrap Number/String objects, cap at 10
        let space_arg = match args[2] {
          Object(data) =>
            if data.class_name == "Number" {
              match data.bag.internal_slots.get(@runtime.NumberData) {
                Some(n) => n
                None => args[2]
              }
            } else if data.class_name == "String" {
              match data.bag.internal_slots.get(@runtime.StringData) {
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
              Some(s[:10].to_owned())
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
      // Handle replacer array (property list filter).
      // Per spec §7.2.2, IsArray on a Proxy exotic object checks the ProxyHandler;
      // if null (revoked), throw TypeError. Otherwise, inspect the target.
      // Must also extract string elements from Proxy-wrapped arrays via [[Get]].
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
          Value::Proxy(proxy_data) =>
            // Check handler revocation (IsArray step 3.a)
            match proxy_data.handler {
              None =>
                raise @errors.TypeError(
                  message="Cannot use a revoked proxy as a replacer array",
                )
              Some(_) =>
                // IsArray through Proxy chains
                if json_is_array_like(args[1]) {
                  let loc = @token.Loc::default()
                  let len_val = interp.get_property(args[1], "length", loc)
                  let len = match len_val {
                    Number(n) => n.to_int()
                    _ => 0
                  }
                  let keys : Array[String] = []
                  for i in 0..<len {
                    let elem = interp.get_property(args[1], i.to_string(), loc)
                    match elem {
                      Value::String_(s) => keys.push(s)
                      Value::Number(n) => keys.push(n.to_string())
                      _ => ()
                    }
                  }
                  Some(keys)
                } else {
                  None
                }
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
        bag: {
          properties: root_props,
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {},
          host_slots: {},
        },
        prototype: Null,
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
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
    },
  )
  json_descs["stringify"] = ne_desc
  // Symbol.toStringTag = "JSON"
  let tostringtag_sym = well_known_symbols.to_string_tag
  let json_sym_props : Map[Int, Value] = {}
  let json_sym_descs : Map[Int, PropDescriptor] = {}
  json_sym_props[tostringtag_sym.id] = Value::String_("JSON")
  json_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let obj_proto = match env.bindings.get("[[ObjectPrototype]]") {
    Some(b) => b.value
    None => Null
  }
  env.def_builtin(
    "JSON",
    Value::Object({
      bag: {
        properties: json_props,
        symbol_properties: json_sym_props,
        descriptors: json_descs,
        symbol_descriptors: json_sym_descs,
        internal_slots: {},
        host_slots: {},
      },
      prototype: obj_proto,
      callable: None,
      class_name: "JSON",
      extensible: true,
      arraybuffer_state: None,
    }),
  )
}

///|
fn json_parse(input : String, interp : Interpreter) -> Value raise Error {
  let obj_proto = interp.realm_state.get_obj_proto()
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
        bag: {
          properties,
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {},
          host_slots: {},
        },
        prototype: obj_proto,
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
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
      bag: {
        properties,
        symbol_properties: {},
        descriptors: {},
        symbol_descriptors: {},
        internal_slots: {},
        host_slots: {},
      },
      prototype: obj_proto,
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    })
  }
  and parse_array = fn() -> Value raise Error {
    pos[0] += 1 // skip [
    let elements : Array[Value] = []
    skip_ws()
    if pos[0] < len && chars[pos[0]] == ']' {
      pos[0] += 1
      return @runtime.make_array(elements)
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
    @runtime.make_array(elements)
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
/// §7.2.2 IsArray check that sees through Proxy chains.
fn json_is_array_like(val : Value) -> Bool {
  match val {
    Array(_) => true
    Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) => json_is_array_like(target)
        None => false
      }
    _ => false
  }
}

///|
/// InternalizeJSONProperty — walks the parsed (or reviver-returned) value
/// using the full abstract operations so that Proxy traps fire correctly.
fn json_internalize(
  holder : Value,
  name : String,
  reviver : Value,
  interp : Interpreter,
) -> Value raise Error {
  let loc = @token.Loc::default()
  // Step 1: Let val be ? Get(holder, name) — handles accessor getters and
  // Proxy get traps.
  let val = interp.get_property(holder, name, loc)
  // Step 2: Recurse into object-typed values (including Proxies).
  if @runtime.is_object_value(val) {
    if json_is_array_like(val) {
      // Array branch: ? ToLength(? Get(val, "length")), then for each index:
      // delete or CreateDataProperty via [[DefineOwnProperty]].
      let len = @runtime.to_array_like_length_interp(val, interp)
      for i = 0L; i < len; i = i + 1L {
        let idx = i.to_string()
        let new_val = json_internalize(val, idx, reviver, interp)
        match new_val {
          Undefined =>
            // ? val.[[Delete]](ToString(I)) — non-strict: silent false return
            // for non-configurable properties, TypeError only on revoked Proxy.
            interp.delete_property_key(val, String_(idx)) |> ignore
          _ =>
            // ? CreateDataProperty(val, ToString(I), newElement)
            interp.define_own_property(
              val,
              String_(idx),
              @runtime.PartialDescriptor::data_default(new_val),
              loc,
            )
            |> ignore
        }
      }
    } else {
      // Object branch: ? EnumerableOwnPropertyNames(val, "key"), then for each:
      // delete or CreateDataProperty. Proxy ownKeys/getOwnPropertyDescriptor
      // traps fire through object_keys.
      let keys_val = @runtime.object_keys(interp, val)
      let keys : Array[String] = []
      match keys_val {
        Array(arr) =>
          for k in arr.elements {
            match k {
              String_(s) => keys.push(s)
              _ => ()
            }
          }
        _ => ()
      }
      for key in keys {
        let new_val = json_internalize(val, key, reviver, interp)
        match new_val {
          Undefined => interp.delete_property_key(val, String_(key)) |> ignore
          _ =>
            interp.define_own_property(
              val,
              String_(key),
              @runtime.PartialDescriptor::data_default(new_val),
              loc,
            )
            |> ignore
        }
      }
    }
  }
  // Step 3: Call reviver(holder, name, val).
  interp.call_value(reviver, holder, [Value::String_(name), val], loc)
}

///
///
/// Write comma separator and indentation before the next element in a JSON
/// array or object. Returns `false` (the next `first` value).
fn json_write_element_separator(
  buf : StringBuilder,
  first : Bool,
  indent : String?,
  depth : Int,
) -> Bool {
  if !first {
    buf.write_char(',')
  }
  match indent {
    Some(ind) => {
      buf.write_char('\n')
      for _i = 0; _i < depth; _i = _i + 1 {
        buf.write_string(ind)
      }
    }
    None => ()
  }
  false
}
///
/// Write closing indentation (newline + indent at the shallower depth)
/// before the closing bracket/brace, when the container has content.
fn json_write_close_indent(
  buf : StringBuilder,
  indent : String?,
  has_content : Bool,
  depth : Int,
) -> Unit {
  match indent {
    Some(ind) =>
      if has_content {
        buf.write_char('\n')
        for _i = 0; _i < depth; _i = _i + 1 {
          buf.write_string(ind)
        }
      }
    None => ()
  }
}
///
fn json_stringify_proxy_array(
  ip : Interpreter,
  val : Value,
  _proxy_data : ProxyData,
  seen : Array[Value],
  indent : String?,
  depth : Int,
  replacer? : Value? = None,
  property_list? : Array[String]? = None,
) -> Value raise Error {
  let loc = @token.Loc::default()
  // Cycle detection
  for s in seen {
    if physical_equal(s, val) {
      raise @errors.TypeError(message="Converting circular structure to JSON")
    }
  }
  seen.push(val)
  let len_val = ip.get_property(val, "length", loc)
  let new_depth = depth + 1
  let len = match len_val {
    Number(n) => n.to_int()
    _ => 0
  }
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for idx in 0..<len {
    let element_val = ip.get_property(val, idx.to_string(), loc)
    let stringified = json_stringify_value(
      element_val,
      seen,
      indent,
      new_depth,
      Some(ip),
      replacer~,
      holder=val,
      key=idx.to_string(),
      property_list~,
    )
    match stringified {
      Undefined => {
        first = json_write_element_separator(buf, first, indent, new_depth)
        buf.write_string("null")
      }
      Value::String_(s) => {
        first = json_write_element_separator(buf, first, indent, new_depth)
        buf.write_string(s)
      }
      _ => ()
    }
  }
  json_write_close_indent(buf, indent, len > 0, depth)
  buf.write_char(']')
  let _ = seen.pop()
  Value::String_(buf.to_string())
}

///|
/// Serialize a Proxy wrapping an Object as JSON object, using interpreter-aware
/// abstract operations so [[Get]], [[OwnPropertyKeys]], and [[GetOwnProperty]]
/// traps fire via the Proxy handler.
fn json_stringify_proxy_object(
  ip : Interpreter,
  val : Value,
  _proxy_data : ProxyData,
  seen : Array[Value],
  indent : String?,
  depth : Int,
  replacer? : Value? = None,
  property_list? : Array[String]? = None,
) -> Value raise Error {
  let loc = @token.Loc::default()
  // Cycle detection
  for s in seen {
    if physical_equal(s, val) {
      raise @errors.TypeError(message="Converting circular structure to JSON")
    }
  }
  seen.push(val)
  let new_depth = depth + 1
  let buf = StringBuilder::new()
  buf.write_char('{')
  let mut first = true
  // Key enumeration: property_list (from replacer array) wins over own enumerable
  // keys. When no property_list, use object_keys which fires ownKeys +
  // getOwnPropertyDescriptor traps.
  let keys : Array[String] = match property_list {
    Some(pl) => pl
    None => {
      let keys_val = @runtime.object_keys(ip, val)
      match keys_val {
        Value::Array(arr) =>
          arr.elements.filter_map(fn(v) {
            match v {
              Value::String_(s) => Some(s)
              _ => None
            }
          })
        _ => []
      }
    }
  }
  for k in keys {
    let v = ip.get_property(val, k, loc)
    let stringified = json_stringify_value(
      v,
      seen,
      indent,
      new_depth,
      Some(ip),
      replacer~,
      holder=val,
      key=k,
      property_list~,
    )
    match stringified {
      Undefined => () // Skip undefined values
      Value::String_(s) => {
        first = json_write_element_separator(buf, first, indent, new_depth)
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
  json_write_close_indent(buf, indent, !first, depth)
  buf.write_char('}')
  let _ = seen.pop()
  Value::String_(buf.to_string())
}
///

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
  // Step 1: Check toJSON for Object values per SerializeJSONProperty §25.5.8.1 step 2.
  // This fires Proxy [[Get]] traps and must precede the replacer call (step 2c).
  let val = if @runtime.is_object_value(val) {
    match interp {
      Some(ip) => {
        let loc = @token.Loc::default()
        let to_json_fn = ip.get_property(val, "toJSON", loc)
        match to_json_fn {
          Object(data) =>
            match data.callable {
              Some(_) =>
                ip.call_value(to_json_fn, val, [Value::String_(key)], loc)
              None => val
            }
          _ => val
        }
      }
      None => val
    }
  } else {
    val
  }
  // Step 2: Apply replacer function if provided (step 2c)
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
      match interp {
        Some(ip) =>
          // Determine if Proxy wraps an array via IsArray (per spec, IsArray
          // recursively unwraps Proxy chains to inspect the target, not via a
          // handler trap). If array-like, use interpreter ops to serialize so
          // [[Get]] and [[OwnPropertyKeys]] traps fire via the handler.
          if json_is_array_like(val) {
            json_stringify_proxy_array(
              ip,
              val,
              proxy_data,
              seen,
              indent,
              depth,
              replacer~,
              property_list~,
            )
          } else {
            json_stringify_proxy_object(
              ip,
              val,
              proxy_data,
              seen,
              indent,
              depth,
              replacer~,
              property_list~,
            )
          }
        None =>
          // Without interpreter, best effort: unwrap to target
          match proxy_data.target {
            Some(target) =>
              json_stringify_value(
                target,
                seen,
                indent,
                depth,
                None,
                replacer~,
                property_list~,
              )
            None => Value::String_("{}")
          }
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
            first = json_write_element_separator(buf, first, indent, new_depth)
            buf.write_string("null")
          }
          Value::String_(s) => {
            first = json_write_element_separator(buf, first, indent, new_depth)
            buf.write_string(s)
          }
          _ => ()
        }
      }
      json_write_close_indent(buf, indent, data.elements.length() > 0, depth)
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
            match data.bag.internal_slots.get(@runtime.NumberData) {
              Some(Value::Number(n)) =>
                return if n.is_nan() || n.is_inf() {
                  Value::String_("null")
                } else {
                  Value::String_(Value::Number(n).to_string())
                }
              _ => ()
            }
          } else if data.class_name == "String" {
            match data.bag.internal_slots.get(@runtime.StringData) {
              Some(Value::String_(s)) =>
                return Value::String_(json_escape_string(s))
              _ => ()
            }
          } else if data.class_name == "Boolean" {
            match data.bag.internal_slots.get(@runtime.BooleanData) {
              Some(Value::Bool(b)) => return Value::String_(b.to_string())
              _ => ()
            }
          }
          // toJSON is handled by the shared prelude when interp is available.
          // For headless calls (interp=None), fall back to direct bag walk.
          match interp {
            None => {
              let mut to_json_fn : Value? = None
              let mut cur : Value? = Some(val)
              while to_json_fn is None {
                match cur {
                  Some(Object(obj_data)) =>
                    match obj_data.bag.properties.get("toJSON") {
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
                          match to_json_data.callable {
                            Some(MethodCallable(_, func)) => Some(func(val, []))
                            Some(NativeCallable(_, func)) => Some(func([]))
                            Some(NativeCallableWithContext(_, func)) =>
                              Some(func(Call, []))
                            Some(NonConstructableCallable(_, func)) =>
                              Some(func([]))
                            _ => None
                          }
                      }
                      match json_val {
                        Some(v) =>
                          return json_stringify_value(
                            v,
                            seen,
                            indent,
                            depth,
                            None,
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
            }
            Some(_) => ()
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
              let sorted = @runtime.sort_property_keys(data.bag.properties)
              let filtered : Array[String] = []
              for k in sorted {
                // Skip non-enumerable properties
                let enumerable = match data.bag.descriptors.get(k) {
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
            let v = match data.bag.properties.get(k) {
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
                first = json_write_element_separator(buf, first, indent, new_depth)
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
          json_write_close_indent(buf, indent, !first, depth)
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

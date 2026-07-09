///|
fn setup_array_builtins(
  env : Environment,
  realm_state : @runtime.RealmState,
  nf_desc : PropDescriptor,
  obj_proto : Value,
  obj_method_desc : PropDescriptor,
) -> Unit {
  // Create Array.prototype with all array methods
  let array_proto_props : Map[String, Value] = {}
  let array_proto_descs : Map[String, PropDescriptor] = {}
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  // Non-callback methods (using MethodCallable for this-aware dispatch)
  array_proto_props["push"] = @runtime.make_interp_method_func(
    name="push",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      array_push_indexed_properties(interp, o, args)
    },
  )
  array_proto_props["pop"] = @runtime.make_interp_method_func(
    name="pop",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      array_pop_indexed_properties(interp, o)
    },
  )
  array_proto_props["shift"] = @runtime.make_interp_method_func(
    name="shift",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      array_shift_indexed_properties(interp, o)
    },
  )
  array_proto_props["unshift"] = @runtime.make_interp_method_func(
    name="unshift",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      array_unshift_indexed_properties(interp, o, args)
    },
  )
  array_proto_props["join"] = @runtime.make_interp_method_func(
    name="join",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let sep = if args.length() > 0 {
        match args[0] {
          Undefined => ","
          v => interp.to_js_string(v)
        }
      } else {
        ","
      }
      let parts : Array[String] = []
      for i = 0L; i < len; i = i + 1L {
        let v = @runtime.get_array_like_element_interp(interp, o, i)
        match v {
          Null | Undefined => parts.push("")
          _ => parts.push(interp.to_js_string(v))
        }
      }
      Value::String_(parts.join(sep))
    },
  )
  array_proto_props["indexOf"] = @runtime.make_interp_method_func(
    name="indexOf",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      if len == 0L {
        return Value::Number(-1.0)
      }
      let search = if args.length() > 0 { args[0] } else { Undefined }
      let from_idx = if args.length() > 1 {
        array_mutator_to_integer_index(interp, args[1])
      } else {
        0L
      }
      let start = if from_idx < 0L {
        let s = len + from_idx
        if s < 0L {
          0L
        } else {
          s
        }
      } else {
        from_idx
      }
      for i = start; i < len; i = i + 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          if strict_equal_val(
              @runtime.get_array_like_element_interp(interp, o, i),
              search,
            ) {
            return Value::Number(i.to_double())
          }
        }
      }
      Value::Number(-1.0)
    },
  )
  array_proto_props["lastIndexOf"] = @runtime.make_interp_method_func(
    name="lastIndexOf",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      if len == 0L {
        return Value::Number(-1.0)
      }
      let search = if args.length() > 0 { args[0] } else { Undefined }
      let start = if args.length() > 1 {
        array_mutator_to_integer_index(interp, args[1])
      } else {
        len - 1L
      }
      let from = if start < 0L {
        len + start
      } else if start >= len {
        len - 1L
      } else {
        start
      }
      for i = from; i >= 0L; i = i - 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          if strict_equal_val(
              @runtime.get_array_like_element_interp(interp, o, i),
              search,
            ) {
            return Value::Number(i.to_double())
          }
        }
      }
      Value::Number(-1.0)
    },
  )
  array_proto_props["includes"] = @runtime.make_interp_method_func(
    name="includes",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      // §22.1.3.11 step 3: ToInteger(fromIndex) is NOT called when len is 0.
      guard len != 0L else { return Value::Bool(false) }
      let (search, from_idx) = match args {
        [s, fi, ..] => (s, array_mutator_to_integer_index(interp, fi))
        [s] => (s, 0L)
        [] => (Undefined, 0L)
      }
      let start = if from_idx < 0L {
        let s = len + from_idx
        if s < 0L {
          0L
        } else {
          s
        }
      } else {
        from_idx
      }
      for i = start; i < len; i = i + 1L {
        if same_value_zero(
            @runtime.get_array_like_element_interp(interp, o, i),
            search,
          ) {
          return Value::Bool(true)
        }
      }
      Value::Bool(false)
    },
  )
  array_proto_props["slice"] = @runtime.make_interp_method_func(
    name="slice",
    length=2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let alen = @runtime.to_array_like_length_interp(o, interp)
      let mut start = if args.length() > 0 {
        array_mutator_to_integer_index(interp, args[0])
      } else {
        0L
      }
      let mut end = if args.length() > 1 {
        match args[1] {
          Undefined => alen
          _ => array_mutator_to_integer_index(interp, args[1])
        }
      } else {
        alen
      }
      if start < 0 {
        start = alen + start
        if start < 0 {
          start = 0
        }
      }
      if end < 0 {
        end = alen + end
        if end < 0 {
          end = 0
        }
      }
      if end > alen {
        end = alen
      }
      let count = if end > start { end - start } else { 0L }
      let a = @runtime.array_species_create(interp, o, count)
      let mut n = 0L
      for i = start; i < end; i = i + 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          @runtime.create_data_property_or_throw(
            interp,
            a,
            n,
            @runtime.get_array_like_element_interp(interp, o, i),
          )
        }
        n += 1L
      }
      @runtime.set_array_like_length(a, n)
      a
    },
  )
  array_proto_props["concat"] = @runtime.make_interp_method_func(
    name="concat",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let a = @runtime.array_species_create(interp, o, 0L)
      let mut n = 0L
      let concat_sym_id = interp.realm_state.well_known_symbols.is_concat_spreadable.id
      // Process this value and each argument per ES2015 concat spec
      let items : Array[Value] = [o]
      for arg in args {
        items.push(arg)
      }
      for item in items {
        // Determine spreadability: check @@isConcatSpreadable
        let spreadable = match item {
          Object(data) => {
            // Check own symbol property, then walk prototype chain
            let sym_val = match data.bag.symbol_properties.get(concat_sym_id) {
              Some(v) => v
              None => {
                let mut found : Value = Undefined
                let mut cur = data.prototype
                while true {
                  match cur {
                    Object(pd) =>
                      match pd.bag.symbol_properties.get(concat_sym_id) {
                        Some(v) => {
                          found = v
                          break
                        }
                        None => cur = pd.prototype
                      }
                    _ => break
                  }
                }
                found
              }
            }
            match sym_val {
              Undefined => data.class_name == "Array"
              _ => @runtime.is_truthy(sym_val)
            }
          }
          Array(arr_data) =>
            match @runtime.get_array_symbol_prop(arr_data, concat_sym_id) {
              Some(v) =>
                match v {
                  Undefined => true // default: arrays are spreadable
                  _ => @runtime.is_truthy(v)
                }
              None => true // default: arrays are spreadable
            }
          _ => false
        }
        if spreadable {
          let len = @runtime.to_array_like_length_interp(item, interp)
          for i = 0L; i < len; i = i + 1L {
            if @runtime.has_array_like_element(interp, item, i) {
              @runtime.create_data_property_or_throw(
                interp,
                a,
                n,
                @runtime.get_array_like_element_interp(interp, item, i),
              )
            }
            n += 1
          }
        } else {
          @runtime.create_data_property_or_throw(interp, a, n, item)
          n += 1
        }
      }
      @runtime.set_array_like_length(a, n)
      a
    },
  )
  array_proto_props["reverse"] = @runtime.make_interp_method_func(
    name="reverse",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      array_reverse_indexed_properties(interp, o)
    },
  )
  array_proto_props["fill"] = @runtime.make_interp_method_func(
    name="fill",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      array_fill_indexed_properties(interp, o, args)
    },
  )
  let object_proto_to_string = match obj_proto {
    Object(data) => data.bag.properties.get("toString").unwrap_or(Undefined)
    _ => Undefined
  }
  array_proto_props["toString"] = @runtime.make_interp_method_func(
    name="toString",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      let loc = @token.Loc::default()
      // Per spec, toString calls join if available, otherwise the intrinsic
      // Object.prototype.toString.
      let join_fn = interp.get_property(o, "join", loc)
      if @runtime.is_callable(join_fn) {
        interp.call_value(join_fn, o, [], loc)
      } else if @runtime.is_callable(object_proto_to_string) {
        interp.call_value(object_proto_to_string, o, [], loc)
      } else {
        Value::String_("[object Object]")
      }
    },
  )
  array_proto_props["at"] = @runtime.make_interp_method_func(
    name="at",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let idx = if args.length() > 0 {
        array_mutator_to_integer_index(interp, args[0])
      } else {
        0L
      }
      let actual_idx = if idx < 0L { len + idx } else { idx }
      if actual_idx >= 0L && actual_idx < len {
        @runtime.get_array_like_element_interp(interp, o, actual_idx)
      } else {
        Undefined
      }
    },
  )
  array_proto_props["toLocaleString"] = @runtime.make_interp_method_func(
    name="toLocaleString",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let parts : Array[String] = []
      for i = 0L; i < len; i = i + 1L {
        let v = @runtime.get_array_like_element_interp(interp, o, i)
        match v {
          Null | Undefined => parts.push("")
          _ => {
            // Per spec, call toLocaleString on each element
            let tls = interp.get_property(
              v,
              "toLocaleString",
              @token.Loc::default(),
            )
            if @runtime.is_callable(tls) {
              let result = interp.call_value(tls, v, [], @token.Loc::default())
              parts.push(interp.to_js_string(result))
            } else {
              parts.push(v.to_string())
            }
          }
        }
      }
      Value::String_(parts.join(","))
    },
  )

  // Callback-requiring methods (using InterpreterCallable)
  array_proto_props["forEach"] = @runtime.make_interp_method_func(
    name="forEach",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      for i = 0L; i < len; i = i + 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          let _ = interp.call_value(
            callback,
            this_arg,
            [
              @runtime.get_array_like_element_interp(interp, o, i),
              Value::Number(i.to_double()),
              o,
            ],
            loc,
          )
        }
      }
      Undefined
    },
  )
  array_proto_props["map"] = @runtime.make_interp_method_func(
    name="map",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let a = @runtime.array_species_create(interp, o, len)
      for i = 0L; i < len; i = i + 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          let val = interp.call_value(
            callback,
            this_arg,
            [
              @runtime.get_array_like_element_interp(interp, o, i),
              Value::Number(i.to_double()),
              o,
            ],
            loc,
          )
          @runtime.create_data_property_or_throw(interp, a, i, val)
        }
      }
      @runtime.set_array_like_length(a, len)
      a
    },
  )
  array_proto_props["filter"] = @runtime.make_interp_method_func(
    name="filter",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let a = @runtime.array_species_create(interp, o, 0L)
      let mut to = 0L
      for i = 0L; i < len; i = i + 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          let el = @runtime.get_array_like_element_interp(interp, o, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Value::Number(i.to_double()), o],
            loc,
          )
          if @runtime.is_truthy(val) {
            @runtime.create_data_property_or_throw(interp, a, to, el)
            to += 1L
          }
        }
      }
      a
    },
  )
  array_proto_props["reduce"] = @runtime.make_interp_method_func(
    name="reduce",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let loc = @token.Loc::default()
      let mut acc : Value = Undefined
      let mut k = 0L
      if args.length() > 1 {
        acc = args[1]
      } else {
        // Per spec: find first present element as initial value
        let mut k_present = false
        while k < len {
          if @runtime.has_array_like_element(interp, o, k) {
            acc = @runtime.get_array_like_element_interp(interp, o, k)
            k = k + 1L
            k_present = true
            break
          }
          k = k + 1L
        }
        if !k_present {
          raise @errors.TypeError(
            message="Reduce of empty array with no initial value",
          )
        }
      }
      while k < len {
        if @runtime.has_array_like_element(interp, o, k) {
          acc = interp.call_value(
            callback,
            Undefined,
            [
              acc,
              @runtime.get_array_like_element_interp(interp, o, k),
              Value::Number(k.to_double()),
              o,
            ],
            loc,
          )
        }
        k = k + 1L
      }
      acc
    },
  )
  array_proto_props["reduceRight"] = @runtime.make_interp_method_func(
    name="reduceRight",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let loc = @token.Loc::default()
      let mut acc : Value = Undefined
      let mut k = len - 1L
      if args.length() > 1 {
        acc = args[1]
      } else {
        // Per spec: find last present element as initial value (searching right to left)
        let mut k_present = false
        while k >= 0L {
          if @runtime.has_array_like_element(interp, o, k) {
            acc = @runtime.get_array_like_element_interp(interp, o, k)
            k = k - 1L
            k_present = true
            break
          }
          k = k - 1L
        }
        if !k_present {
          raise @errors.TypeError(
            message="Reduce of empty array with no initial value",
          )
        }
      }
      while k >= 0L {
        if @runtime.has_array_like_element(interp, o, k) {
          acc = interp.call_value(
            callback,
            Undefined,
            [
              acc,
              @runtime.get_array_like_element_interp(interp, o, k),
              Value::Number(k.to_double()),
              o,
            ],
            loc,
          )
        }
        k = k - 1L
      }
      acc
    },
  )
  array_proto_props["find"] = @runtime.make_interp_method_func(
    name="find",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      for i = 0L; i < len; i = i + 1L {
        let el = @runtime.get_array_like_element_interp(interp, o, i)
        let val = interp.call_value(
          callback,
          this_arg,
          [el, Value::Number(i.to_double()), o],
          loc,
        )
        if @runtime.is_truthy(val) {
          return el
        }
      }
      Undefined
    },
  )
  array_proto_props["findIndex"] = @runtime.make_interp_method_func(
    name="findIndex",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      for i = 0L; i < len; i = i + 1L {
        let el = @runtime.get_array_like_element_interp(interp, o, i)
        let val = interp.call_value(
          callback,
          this_arg,
          [el, Value::Number(i.to_double()), o],
          loc,
        )
        if @runtime.is_truthy(val) {
          return Value::Number(i.to_double())
        }
      }
      Value::Number(-1.0)
    },
  )
  array_proto_props["findLast"] = @runtime.make_interp_method_func(
    name="findLast",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      for i = len - 1L; i >= 0L; i = i - 1L {
        let el = @runtime.get_array_like_element_interp(interp, o, i)
        let val = interp.call_value(
          callback,
          this_arg,
          [el, Value::Number(i.to_double()), o],
          loc,
        )
        if @runtime.is_truthy(val) {
          return el
        }
      }
      Undefined
    },
  )
  array_proto_props["findLastIndex"] = @runtime.make_interp_method_func(
    name="findLastIndex",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      for i = len - 1L; i >= 0L; i = i - 1L {
        let el = @runtime.get_array_like_element_interp(interp, o, i)
        let val = interp.call_value(
          callback,
          this_arg,
          [el, Value::Number(i.to_double()), o],
          loc,
        )
        if @runtime.is_truthy(val) {
          return Value::Number(i.to_double())
        }
      }
      Value::Number(-1.0)
    },
  )
  array_proto_props["every"] = @runtime.make_interp_method_func(
    name="every",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      for i = 0L; i < len; i = i + 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          let val = interp.call_value(
            callback,
            this_arg,
            [
              @runtime.get_array_like_element_interp(interp, o, i),
              Value::Number(i.to_double()),
              o,
            ],
            loc,
          )
          if !@runtime.is_truthy(val) {
            return Value::Bool(false)
          }
        }
      }
      Value::Bool(true)
    },
  )
  array_proto_props["some"] = @runtime.make_interp_method_func(
    name="some",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      for i = 0L; i < len; i = i + 1L {
        if @runtime.has_array_like_element(interp, o, i) {
          let val = interp.call_value(
            callback,
            this_arg,
            [
              @runtime.get_array_like_element_interp(interp, o, i),
              Value::Number(i.to_double()),
              o,
            ],
            loc,
          )
          if @runtime.is_truthy(val) {
            return Value::Bool(true)
          }
        }
      }
      Value::Bool(false)
    },
  )
  array_proto_props["sort"] = @runtime.make_interp_method_func(
    name="sort",
    length=1,
    fn(interp, this_val, args) raise {
      let comparefn = array_sort_validate_comparefn(args)
      let o = to_object(this_val, interp)
      array_sort_indexed_properties(interp, o, comparefn)
    },
  )
  array_proto_props["flat"] = @runtime.make_interp_method_func(
    name="flat",
    length=0,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let depth = if args.length() > 0 {
        match args[0] {
          Undefined => 1
          _ => interp.to_number(args[0]).to_int()
        }
      } else {
        1
      }
      let elements = @runtime.to_array_like_elements(o)
      let flat_result : Array[Value] = []
      @runtime.flatten_array_val(elements, depth, flat_result)
      let a = @runtime.array_species_create(interp, o, 0L)
      for i, val in flat_result {
        @runtime.create_data_property_or_throw(interp, a, i.to_int64(), val)
      }
      @runtime.set_array_like_length(a, flat_result.length().to_int64())
      a
    },
  )
  array_proto_props["flatMap"] = @runtime.make_interp_method_func(
    name="flatMap",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let a = @runtime.array_species_create(interp, o, 0L)
      let mut n = 0L
      for i = 0L; i < len; i = i + 1L {
        let el = @runtime.get_array_like_element_interp(interp, o, i)
        let val = interp.call_value(
          callback,
          this_arg,
          [el, Value::Number(i.to_double()), o],
          loc,
        )
        match val {
          Array(inner) =>
            for item in inner.elements {
              @runtime.create_data_property_or_throw(interp, a, n, item)
              n += 1L
            }
          _ => {
            @runtime.create_data_property_or_throw(interp, a, n, val)
            n += 1L
          }
        }
      }
      @runtime.set_array_like_length(a, n)
      a
    },
  )
  array_proto_props["splice"] = @runtime.make_interp_method_func(
    name="splice",
    length=2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      array_splice_indexed_properties(interp, o, args)
    },
  )
  array_proto_props["copyWithin"] = @runtime.make_interp_method_func(
    name="copyWithin",
    length=2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      array_copy_within_indexed_properties(interp, o, args)
    },
  )
  array_proto_props["entries"] = make_array_entries_iterator_method(realm_state)
  array_proto_props["keys"] = make_array_keys_iterator_method(realm_state)
  array_proto_props["values"] = make_array_values_iterator_method(realm_state)
  array_proto_props["toReversed"] = @runtime.make_interp_method_func(
    name="toReversed",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      array_mutator_require_array_create_length(len)
      let result : Array[Value] = []
      for i = len - 1L; i >= 0L; i = i - 1L {
        result.push(@runtime.get_array_like_element_interp(interp, o, i))
      }
      @runtime.make_array(result)
    },
  )
  array_proto_props["toSorted"] = @runtime.make_interp_method_func(
    name="toSorted",
    length=1,
    fn(interp, this_val, args) raise {
      // Step 1: Validate comparefn
      if args.length() > 0 {
        let comparefn = args[0]
        match comparefn {
          Undefined => ()
          _ =>
            if !@runtime.is_callable(comparefn) {
              raise @errors.TypeError(
                message=@runtime.to_js_string(comparefn) + " is not a function",
              )
            }
        }
      }
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      array_mutator_require_array_create_length(len)
      let result : Array[Value] = []
      for i = 0L; i < len; i = i + 1L {
        result.push(@runtime.get_array_like_element_interp(interp, o, i))
      }
      if args.length() > 0 {
        match args[0] {
          Undefined =>
            result.sort_by(fn(a, b) {
              if a is Undefined && b is Undefined {
                return 0
              }
              if a is Undefined {
                return 1
              }
              if b is Undefined {
                return -1
              }
              let sa = a.to_string()
              let sb = b.to_string()
              if sa < sb {
                -1
              } else if sa > sb {
                1
              } else {
                0
              }
            })
          _ => {
            let comparefn = args[0]
            let loc = @token.Loc::default()
            let mut caught_error : Error? = None
            result.sort_by(fn(a, b) {
              if a is Undefined && b is Undefined {
                return 0
              }
              if a is Undefined {
                return 1
              }
              if b is Undefined {
                return -1
              }
              if caught_error is Some(_) {
                return 0
              }
              let cmp_result = interp.call_value(
                comparefn,
                Undefined,
                [a, b],
                loc,
              ) catch {
                e => {
                  caught_error = Some(e)
                  return 0
                }
              }
              let cmp = interp.to_number(cmp_result) catch {
                e => {
                  caught_error = Some(e)
                  return 0
                }
              }
              if cmp.is_nan() {
                0
              } else if cmp < 0.0 {
                -1
              } else if cmp > 0.0 {
                1
              } else {
                0
              }
            })
            match caught_error {
              Some(e) => raise e
              None => ()
            }
          }
        }
      } else {
        result.sort_by(fn(a, b) {
          if a is Undefined && b is Undefined {
            return 0
          }
          if a is Undefined {
            return 1
          }
          if b is Undefined {
            return -1
          }
          let sa = a.to_string()
          let sb = b.to_string()
          if sa < sb {
            -1
          } else if sa > sb {
            1
          } else {
            0
          }
        })
      }
      @runtime.make_array(result)
    },
  )
  array_proto_props["toSpliced"] = @runtime.make_interp_method_func(
    name="toSpliced",
    length=2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let mut start = if args.length() > 0 {
        array_mutator_to_integer_index(interp, args[0])
      } else {
        0L
      }
      if start < 0L {
        start = len + start
        if start < 0L {
          start = 0L
        }
      }
      if start > len {
        start = len
      }
      let del_count = if args.length() > 1 {
        let d = array_mutator_to_integer_index(interp, args[1])
        if d < 0L {
          0L
        } else if d > len - start {
          len - start
        } else {
          d
        }
      } else {
        len - start
      }
      let insert_count = if args.length() > 2 {
        (args.length() - 2).to_int64()
      } else {
        0L
      }
      let new_len = len - del_count + insert_count
      if new_len > ARRAY_MAX_SAFE_LENGTH_I64 {
        raise @errors.TypeError(message="Invalid array length")
      }
      array_mutator_require_array_create_length(new_len)
      let result : Array[Value] = []
      for i = 0L; i < start; i = i + 1L {
        result.push(@runtime.get_array_like_element_interp(interp, o, i))
      }
      for i = 2; i < args.length(); i = i + 1 {
        result.push(args[i])
      }
      for i = start + del_count; i < len; i = i + 1L {
        result.push(@runtime.get_array_like_element_interp(interp, o, i))
      }
      @runtime.make_array(result)
    },
  )
  array_proto_props["with"] = @runtime.make_interp_method_func(
    name="with",
    length=2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let idx = if args.length() > 0 {
        array_mutator_to_integer_index(interp, args[0])
      } else {
        0L
      }
      let value = if args.length() > 1 { args[1] } else { Undefined }
      let len = @runtime.to_array_like_length_interp(o, interp)
      let actual_idx = if idx < 0L { len + idx } else { idx }
      if actual_idx < 0L || actual_idx >= len {
        raise @errors.RangeError(message="Invalid index")
      }
      array_mutator_require_array_create_length(len)
      let result : Array[Value] = []
      for i = 0L; i < len; i = i + 1L {
        if i == actual_idx {
          result.push(value)
        } else {
          result.push(@runtime.get_array_like_element_interp(interp, o, i))
        }
      }
      @runtime.make_array(result)
    },
  )
  array_proto_descs["push"] = method_desc
  array_proto_descs["pop"] = method_desc
  array_proto_descs["shift"] = method_desc
  array_proto_descs["unshift"] = method_desc
  array_proto_descs["join"] = method_desc
  array_proto_descs["indexOf"] = method_desc
  array_proto_descs["lastIndexOf"] = method_desc
  array_proto_descs["includes"] = method_desc
  array_proto_descs["slice"] = method_desc
  array_proto_descs["concat"] = method_desc
  array_proto_descs["reverse"] = method_desc
  array_proto_descs["fill"] = method_desc
  array_proto_descs["toString"] = method_desc
  array_proto_descs["at"] = method_desc
  array_proto_descs["toLocaleString"] = method_desc
  array_proto_descs["forEach"] = method_desc
  array_proto_descs["map"] = method_desc
  array_proto_descs["filter"] = method_desc
  array_proto_descs["reduce"] = method_desc
  array_proto_descs["reduceRight"] = method_desc
  array_proto_descs["find"] = method_desc
  array_proto_descs["findIndex"] = method_desc
  array_proto_descs["findLast"] = method_desc
  array_proto_descs["findLastIndex"] = method_desc
  array_proto_descs["every"] = method_desc
  array_proto_descs["some"] = method_desc
  array_proto_descs["sort"] = method_desc
  array_proto_descs["flat"] = method_desc
  array_proto_descs["flatMap"] = method_desc
  array_proto_descs["splice"] = method_desc
  array_proto_descs["copyWithin"] = method_desc
  array_proto_descs["entries"] = method_desc
  array_proto_descs["keys"] = method_desc
  array_proto_descs["values"] = method_desc
  array_proto_descs["toReversed"] = method_desc
  array_proto_descs["toSorted"] = method_desc
  array_proto_descs["toSpliced"] = method_desc
  array_proto_descs["with"] = method_desc
  // Array.prototype.length = 0 (per spec, Array.prototype is an Array with length 0)
  array_proto_props["length"] = Value::Number(0.0)
  array_proto_descs["length"] = {
    writable: true,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let array_proto : Value = Value::Object({
    bag: {
      properties: array_proto_props,
      symbol_properties: {},
      descriptors: array_proto_descs,
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: obj_proto,
    callable: None,
    class_name: "Array",
    extensible: true,
    arraybuffer_state: None,
  })
  realm_state.array_prototype.val = Some(array_proto)

  // Array constructor with Array.isArray, Array.from, Array.of
  let array_props : Map[String, Value] = {}
  array_props["prototype"] = array_proto
  array_props["name"] = Value::String_("Array")
  array_props["length"] = Value::Number(1.0)
  array_props["isArray"] = @runtime.make_native_func(name="isArray", length=1, fn(
    args,
  ) {
    let val = if args.length() > 0 { args[0] } else { Undefined }
    // Spec: Array.isArray unwraps proxies recursively
    let mut current = val
    while true {
      match current {
        Array(_) => return Value::Bool(true)
        Object(data) =>
          // Array.prototype is an Object with class_name "Array"
          if data.class_name == "Array" {
            return Value::Bool(true)
          } else {
            return Value::Bool(false)
          }
        Value::Proxy(proxy_data) =>
          match proxy_data.target {
            Some(target) => current = target
            None => return Value::Bool(false)
          }
        _ => return Value::Bool(false)
      }
    }
    Value::Bool(false)
  })
  array_props["of"] = @runtime.make_native_func(name="of", fn(args) {
    // Array.of() - creates array from arguments
    @runtime.make_array(args)
  })
  // Array.from with mapFn support using InterpreterCallable
  array_props["from"] = @runtime.make_interp_method_func(
    name="from",
    length=1,
    fn(interp, this_val, args) raise {
      let source = if args.length() > 0 { args[0] } else { Undefined }
      // Per spec, items must not be null/undefined
      if source is (Null | Undefined) {
        raise @errors.TypeError(
          message="Cannot read properties of " +
            @runtime.to_js_string(source) +
            " (reading 'Symbol(Symbol.iterator)')",
        )
      }
      let map_fn = if args.length() > 1 {
        match args[1] {
          Undefined => None
          fn_val => {
            if !@runtime.is_callable(fn_val) {
              raise @errors.TypeError(
                message=@runtime.to_js_string(fn_val) + " is not a function",
              )
            }
            Some(fn_val)
          }
        }
      } else {
        None
      }
      let this_arg = if args.length() > 2 { args[2] } else { Undefined }
      let loc = @token.Loc::default()
      let elements : Array[Value] = []
      // Per spec: first try Symbol.iterator (iterable protocol)
      let iterator_sym = interp.realm_state.well_known_symbols.iterator
      let mut used_iterator = false
      let mut constructed_result : Value? = None
      let iterator_method = interp.get_computed_property(
        source,
        Symbol(iterator_sym),
        loc,
      )
      if @runtime.is_callable(iterator_method) {
        used_iterator = true
        if @runtime.is_constructor_value(this_val) {
          constructed_result = Some(interp.construct_value(this_val, [], loc))
        }
        let iterator = interp.call_value(iterator_method, source, [], loc)
        let next_method = interp.get_iterator_next_method(iterator, loc)
        let mut k = 0L
        while true {
          let iter_result = match
            interp.iterator_step_result(iterator, next_method, loc) {
            None => break
            Some(result) => result
          }
          let value = interp.iterator_result_value(iter_result, loc)
          let mapped = match map_fn {
            Some(fn_val) =>
              interp.call_value(
                fn_val,
                this_arg,
                [value, Value::Number(k.to_double())],
                loc,
              ) catch {
                e => {
                  interp.iterator_close_throw(iterator, loc)
                  raise e
                }
              }
            None => value
          }
          elements.push(mapped)
          k = k + 1L
        }
      }
      if !used_iterator {
        // Fallback: array-like behavior
        match source {
          Value::Array(data) =>
            for i = 0; i < data.elements.length(); i = i + 1 {
              let el = data.elements[i]
              let mapped = match map_fn {
                Some(fn_val) =>
                  interp.call_value(
                    fn_val,
                    this_arg,
                    [el, Value::Number(i.to_double())],
                    loc,
                  )
                None => el
              }
              elements.push(mapped)
            }
          Value::String_(s) => {
            let chars = s.to_array()
            for i = 0; i < chars.length(); i = i + 1 {
              let el = Value::String_(chars[i].to_string())
              let mapped = match map_fn {
                Some(fn_val) =>
                  interp.call_value(
                    fn_val,
                    this_arg,
                    [el, Value::Number(i.to_double())],
                    loc,
                  )
                None => el
              }
              elements.push(mapped)
            }
          }
          _ => {
            let o = to_object(source, interp)
            let len = @runtime.to_array_like_length_interp(o, interp)
            for i = 0L; i < len; i = i + 1L {
              let el = interp.get_property(o, i.to_string(), loc)
              let mapped = match map_fn {
                Some(fn_val) =>
                  interp.call_value(
                    fn_val,
                    this_arg,
                    [el, Value::Number(i.to_double())],
                    loc,
                  )
                None => el
              }
              elements.push(mapped)
            }
          }
        }
      }
      // Per ES §23.1.2.1 step 3–4: if `this` is a constructor, construct through
      // it so that subclasses (class MyArray extends Array) work correctly.
      // Otherwise fall back to a plain array.
      let n = elements.length()
      if @runtime.is_constructor_value(this_val) {
        let result = match constructed_result {
          Some(value) => value
          None =>
            interp.construct_value(
              this_val,
              [Value::Number(n.to_double())],
              loc,
            )
        }
        for i = 0; i < n; i = i + 1 {
          let _ = interp.set_property(
            result,
            i.to_string(),
            elements[i],
            loc,
            strict=true,
          )
        }
        let _ = interp.set_property(
          result,
          "length",
          Value::Number(n.to_double()),
          loc,
          strict=true,
        )
        result
      } else {
        @runtime.make_array(elements)
      }
    },
  )
  env.def_builtin(
    "Array",
    Value::Object({
      bag: {
        properties: array_props,
        symbol_properties: {},
        descriptors: {
          "name": nf_desc,
          "length": nf_desc,
          "prototype": {
            writable: false,
            enumerable: false,
            configurable: false,
            getter: None,
            setter: None,
            is_accessor: false,
          },
          "isArray": obj_method_desc,
          "from": obj_method_desc,
          "of": obj_method_desc,
        },
        symbol_descriptors: {},
        internal_slots: {},
      },
      prototype: Null,
      callable: Some(
        NativeCallable("Array", fn(args) raise {
          // Array constructor behavior
          if args.length() == 1 {
            match args[0] {
              Value::Number(n) => {
                // Array(n) creates an array with the given length.
                // Validate using double to avoid int32 overflow
                if n < 0.0 ||
                  n > 4294967295.0 ||
                  n != @math.floor(n) ||
                  n.is_nan() {
                  raise @errors.RangeError(message="Invalid array length")
                }
                let len64 = n.to_int64()
                // Use Array::make for a fast single allocation. Cap at 10M to
                // avoid OOM for pathological inputs; lengths above the cap are
                // tracked in ArrayData.bag so arr.length still
                // reports the correct value.
                let elements : Array[Value] = if len64 <=
                  ARRAY_DENSE_MATERIALIZE_LIMIT_I64 {
                  Array::make(len64.to_int(), Undefined)
                } else {
                  []
                }
                let arr_data : ArrayData = {
                  elements,
                  bag: @runtime.PropertyBag(),
                  length_writable: true,
                  holes: {},
                  extensible: true,
                }
                // Mark materialized indices as holes — Array(n) creates an exotic
                // array of length n with no own properties (§22.1.1.1 step 5.c).
                for i in 0..<arr_data.elements.length() {
                  arr_data.holes[i] = ()
                }
                if len64 > arr_data.elements.length().to_int64() {
                  @runtime.set_array_length_override(arr_data, len64)
                }
                Value::Array(arr_data)
              }
              _ => @runtime.make_array(args)
            }
          } else {
            @runtime.make_array(args)
          }
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
  )
  // Set Array.prototype.constructor = Array
  match array_proto {
    Object(data) =>
      @runtime.install_builtin_method(
        data,
        "constructor",
        env.get("Array") catch {
          _ => Undefined
        },
      )
    _ => ()
  }
}

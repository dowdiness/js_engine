///|
fn setup_array_builtins(
  env : Environment,
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
  }

  // Non-callback methods (using MethodCallable for this-aware dispatch)
  array_proto_props["push"] = @runtime.make_interp_method_func(
    name="push",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      match o {
        Value::Array(arr) => {
          for arg in args {
            arr.elements.push(arg)
          }
          Value::Number(arr.elements.length().to_double())
        }
        _ => {
          let mut len = @runtime.to_array_like_length_interp(o, interp)
          for arg in args {
            @runtime.set_array_like_element(o, len, arg)
            len = len + 1
          }
          @runtime.set_array_like_length(o, len)
          Value::Number(len.to_double())
        }
      }
    },
  )
  array_proto_props["pop"] = @runtime.make_interp_method_func(
    name="pop",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      match o {
        Value::Array(arr) =>
          if arr.elements.length() == 0 {
            Undefined
          } else {
            arr.elements.pop() |> Option::unwrap
          }
        _ => {
          let len = @runtime.to_array_like_length_interp(o, interp)
          if len == 0 {
            @runtime.set_array_like_length(o, 0)
            Undefined
          } else {
            let new_len = len - 1
            let val = @runtime.get_array_like_element_interp(interp, o, new_len)
            @runtime.delete_array_like_element(o, new_len)
            @runtime.set_array_like_length(o, new_len)
            val
          }
        }
      }
    },
  )
  array_proto_props["shift"] = @runtime.make_interp_method_func(
    name="shift",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      match o {
        Value::Array(arr) => {
          if arr.elements.length() == 0 {
            return Undefined
          }
          let first = arr.elements[0]
          let new_elems : Array[Value] = []
          for i = 1; i < arr.elements.length(); i = i + 1 {
            new_elems.push(arr.elements[i])
          }
          while arr.elements.length() > 0 {
            let _ = arr.elements.pop()
          }
          for el in new_elems {
            arr.elements.push(el)
          }
          first
        }
        _ => {
          let len = @runtime.to_array_like_length_interp(o, interp)
          if len == 0 {
            @runtime.set_array_like_length(o, 0)
            return Undefined
          }
          let first = @runtime.get_array_like_element_interp(interp, o, 0)
          for i = 1; i < len; i = i + 1 {
            @runtime.set_array_like_element(
              o,
              i - 1,
              @runtime.get_array_like_element_interp(interp, o, i),
            )
          }
          @runtime.delete_array_like_element(o, len - 1)
          @runtime.set_array_like_length(o, len - 1)
          first
        }
      }
    },
  )
  array_proto_props["unshift"] = @runtime.make_interp_method_func(
    name="unshift",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      match o {
        Value::Array(arr) => {
          let old : Array[Value] = []
          for el in arr.elements {
            old.push(el)
          }
          while arr.elements.length() > 0 {
            let _ = arr.elements.pop()
          }
          for arg in args {
            arr.elements.push(arg)
          }
          for el in old {
            arr.elements.push(el)
          }
          Value::Number(arr.elements.length().to_double())
        }
        _ => {
          let len = @runtime.to_array_like_length_interp(o, interp)
          let argc = args.length()
          // Shift existing elements up by argc
          for i = len - 1; i >= 0; i = i - 1 {
            @runtime.set_array_like_element(
              o,
              i + argc,
              @runtime.get_array_like_element_interp(interp, o, i),
            )
          }
          // Insert new elements at the beginning
          for i = 0; i < argc; i = i + 1 {
            @runtime.set_array_like_element(o, i, args[i])
          }
          let new_len = len + argc
          @runtime.set_array_like_length(o, new_len)
          Value::Number(new_len.to_double())
        }
      }
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
          v => v.to_string()
        }
      } else {
        ","
      }
      let parts : Array[String] = []
      for i = 0; i < len; i = i + 1 {
        let v = @runtime.get_array_like_element_interp(interp, o, i)
        match v {
          Null | Undefined => parts.push("")
          _ => parts.push(v.to_string())
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
      let search = if args.length() > 0 { args[0] } else { Undefined }
      let from_idx = if args.length() > 1 {
        @runtime.to_number(args[1]).to_int()
      } else {
        0
      }
      let start = if from_idx < 0 {
        let s = len + from_idx
        if s < 0 {
          0
        } else {
          s
        }
      } else {
        from_idx
      }
      for i = start; i < len; i = i + 1 {
        if @runtime.has_array_like_element(o, i) {
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
      let search = if args.length() > 0 { args[0] } else { Undefined }
      let start = if args.length() > 1 {
        @runtime.to_number(args[1]).to_int()
      } else {
        len - 1
      }
      let from = if start < 0 {
        len + start
      } else if start >= len {
        len - 1
      } else {
        start
      }
      for i = from; i >= 0; i = i - 1 {
        if @runtime.has_array_like_element(o, i) {
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
      let search = if args.length() > 0 { args[0] } else { Undefined }
      let from_idx = if args.length() > 1 {
        @runtime.to_number(args[1]).to_int()
      } else {
        0
      }
      let start = if from_idx < 0 {
        let s = len + from_idx
        if s < 0 {
          0
        } else {
          s
        }
      } else {
        from_idx
      }
      for i = start; i < len; i = i + 1 {
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
        @runtime.to_number(args[0]).to_int()
      } else {
        0
      }
      let mut end = if args.length() > 1 {
        match args[1] {
          Undefined => alen
          _ => @runtime.to_number(args[1]).to_int()
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
      let count = if end > start { end - start } else { 0 }
      let a = @runtime.array_species_create(interp, o, count)
      let mut n = 0
      for i = start; i < end; i = i + 1 {
        if @runtime.has_array_like_element(o, i) {
          @runtime.create_data_property_or_throw(
            interp,
            a,
            n,
            @runtime.get_array_like_element_interp(interp, o, i),
          )
        }
        n += 1
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
      let a = @runtime.array_species_create(interp, o, 0)
      let mut n = 0
      let concat_sym_id = @runtime.get_isconcatspreadable_symbol().id
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
          for i = 0; i < len; i = i + 1 {
            if @runtime.has_array_like_element(item, i) {
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
      match o {
        Value::Array(arr) => {
          arr.elements.rev_in_place()
          Value::Array(arr)
        }
        _ => {
          let len = @runtime.to_array_like_length_interp(o, interp)
          let mut lower = 0
          let mut upper = len - 1
          while lower < upper {
            let lower_val = @runtime.get_array_like_element_interp(
              interp, o, lower,
            )
            let upper_val = @runtime.get_array_like_element_interp(
              interp, o, upper,
            )
            @runtime.set_array_like_element(o, lower, upper_val)
            @runtime.set_array_like_element(o, upper, lower_val)
            lower = lower + 1
            upper = upper - 1
          }
          o
        }
      }
    },
  )
  array_proto_props["fill"] = @runtime.make_interp_method_func(
    name="fill",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let fill_val = if args.length() > 0 { args[0] } else { Undefined }
      let alen = @runtime.to_array_like_length_interp(o, interp)
      let mut start = if args.length() > 1 {
        @runtime.to_number(args[1]).to_int()
      } else {
        0
      }
      let mut end = if args.length() > 2 {
        match args[2] {
          Undefined => alen
          _ => @runtime.to_number(args[2]).to_int()
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
      if start > alen {
        start = alen
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
      for i = start; i < end; i = i + 1 {
        @runtime.set_array_like_element(o, i, fill_val)
      }
      o
    },
  )
  array_proto_props["toString"] = @runtime.make_interp_method_func(
    name="toString",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      // Per spec, toString calls join if available, otherwise Object.prototype.toString
      let join_fn = interp.get_property(o, "join", @token.Loc::default())
      if @runtime.is_callable(join_fn) {
        interp.call_value(join_fn, o, [], @token.Loc::default())
      } else {
        let cls = match o {
          Object(d) => d.class_name
          _ => "Object"
        }
        Value::String_("[object " + cls + "]")
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
        @runtime.to_number(args[0]).to_int()
      } else {
        0
      }
      let actual_idx = if idx < 0 { len + idx } else { idx }
      if actual_idx >= 0 && actual_idx < len {
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
      for i = 0; i < len; i = i + 1 {
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
              parts.push(@runtime.to_js_string(result))
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      for i = 0; i < len; i = i + 1 {
        if @runtime.has_array_like_element(o, i) {
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      let a = @runtime.array_species_create(interp, o, len)
      for i = 0; i < len; i = i + 1 {
        if @runtime.has_array_like_element(o, i) {
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      let a = @runtime.array_species_create(interp, o, 0)
      let mut to = 0
      for i = 0; i < len; i = i + 1 {
        if @runtime.has_array_like_element(o, i) {
          let el = @runtime.get_array_like_element_interp(interp, o, i)
          let val = interp.call_value(
            callback,
            this_arg,
            [el, Value::Number(i.to_double()), o],
            loc,
          )
          if @runtime.is_truthy(val) {
            @runtime.create_data_property_or_throw(interp, a, to, el)
            to += 1
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      let mut acc : Value = Undefined
      let mut k = 0
      if args.length() > 1 {
        acc = args[1]
      } else {
        // Per spec: find first present element as initial value
        let mut k_present = false
        while k < len {
          if @runtime.has_array_like_element(o, k) {
            acc = @runtime.get_array_like_element_interp(interp, o, k)
            k = k + 1
            k_present = true
            break
          }
          k = k + 1
        }
        if !k_present {
          raise @errors.TypeError(
            message="Reduce of empty array with no initial value",
          )
        }
      }
      while k < len {
        if @runtime.has_array_like_element(o, k) {
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
        k = k + 1
      }
      acc
    },
  )
  array_proto_props["reduceRight"] = @runtime.make_interp_method_func(
    name="reduceRight",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      let mut acc : Value = Undefined
      let mut k = len - 1
      if args.length() > 1 {
        acc = args[1]
      } else {
        // Per spec: find last present element as initial value (searching right to left)
        let mut k_present = false
        while k >= 0 {
          if @runtime.has_array_like_element(o, k) {
            acc = @runtime.get_array_like_element_interp(interp, o, k)
            k = k - 1
            k_present = true
            break
          }
          k = k - 1
        }
        if !k_present {
          raise @errors.TypeError(
            message="Reduce of empty array with no initial value",
          )
        }
      }
      while k >= 0 {
        if @runtime.has_array_like_element(o, k) {
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
        k = k - 1
      }
      acc
    },
  )
  array_proto_props["find"] = @runtime.make_interp_method_func(
    name="find",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      for i = 0; i < len; i = i + 1 {
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      for i = 0; i < len; i = i + 1 {
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      for i = len - 1; i >= 0; i = i - 1 {
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      for i = len - 1; i >= 0; i = i - 1 {
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      for i = 0; i < len; i = i + 1 {
        if @runtime.has_array_like_element(o, i) {
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
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      for i = 0; i < len; i = i + 1 {
        if @runtime.has_array_like_element(o, i) {
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
      // Extract elements into a mutable array for sorting
      let elements : Array[Value] = match this_val {
        Value::Array(arr) => arr.elements
        _ => @runtime.to_array_like_elements(this_val)
      }
      if args.length() > 0 {
        match args[0] {
          Undefined =>
            elements.sort_by(fn(a, b) {
              // Per spec: undefined sorts to end
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
            elements.sort_by(fn(a, b) {
              // Per spec: undefined sorts to end even with comparefn
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
              let result = interp.call_value(comparefn, Undefined, [a, b], loc) catch {
                e => {
                  caught_error = Some(e)
                  return 0
                }
              }
              let cmp = @runtime.to_number(result) catch {
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
        elements.sort_by(fn(a, b) {
          // Per spec: undefined sorts to end
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
      // For non-array objects, write sorted elements back
      match this_val {
        Value::Array(arr) => Value::Array(arr)
        _ => {
          for i = 0; i < elements.length(); i = i + 1 {
            @runtime.set_array_like_element(this_val, i, elements[i])
          }
          this_val
        }
      }
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
          _ => @runtime.to_number(args[0]).to_int()
        }
      } else {
        1
      }
      let elements = @runtime.to_array_like_elements(o)
      let flat_result : Array[Value] = []
      @runtime.flatten_array_val(elements, depth, flat_result)
      let a = @runtime.array_species_create(interp, o, 0)
      for i, val in flat_result {
        @runtime.create_data_property_or_throw(interp, a, i, val)
      }
      @runtime.set_array_like_length(a, flat_result.length())
      a
    },
  )
  array_proto_props["flatMap"] = @runtime.make_interp_method_func(
    name="flatMap",
    length=1,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_callable(callback) {
        raise @errors.TypeError(
          message=@runtime.to_js_string(callback) + " is not a function",
        )
      }
      let this_arg = if args.length() > 1 { args[1] } else { Undefined }
      let loc = @token.Loc::default()
      let len = @runtime.to_array_like_length_interp(o, interp)
      let a = @runtime.array_species_create(interp, o, 0)
      let mut n = 0
      for i = 0; i < len; i = i + 1 {
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
              n += 1
            }
          _ => {
            @runtime.create_data_property_or_throw(interp, a, n, val)
            n += 1
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
      let alen = @runtime.to_array_like_length_interp(o, interp)
      let mut start = if args.length() > 0 {
        @runtime.to_number(args[0]).to_int()
      } else {
        0
      }
      if start < 0 {
        start = alen + start
        if start < 0 {
          start = 0
        }
      }
      if start > alen {
        start = alen
      }
      let del_count = if args.length() > 1 {
        let d_num = @runtime.to_number(args[1])
        if d_num.is_inf() || d_num >= (alen - start).to_double() {
          alen - start
        } else {
          let d = d_num.to_int()
          if d < 0 {
            0
          } else {
            d
          }
        }
      } else {
        alen - start
      }
      let removed = @runtime.array_species_create(interp, o, del_count)
      for i = 0; i < del_count; i = i + 1 {
        if @runtime.has_array_like_element(o, start + i) {
          @runtime.create_data_property_or_throw(
            interp,
            removed,
            i,
            @runtime.get_array_like_element_interp(interp, o, start + i),
          )
        }
      }
      @runtime.set_array_like_length(removed, del_count)
      let new_items : Array[Value] = []
      for i = 2; i < args.length(); i = i + 1 {
        new_items.push(args[i])
      }
      let items_count = new_items.length()
      // For Array type, use direct element manipulation
      match o {
        Value::Array(arr) => {
          let tail : Array[Value] = []
          for i = start + del_count; i < alen; i = i + 1 {
            tail.push(arr.elements[i])
          }
          while arr.elements.length() > start {
            let _ = arr.elements.pop()
          }
          for item in new_items {
            arr.elements.push(item)
          }
          for item in tail {
            arr.elements.push(item)
          }
        }
        _ => {
          // For objects: shift elements appropriately
          if items_count < del_count {
            // Shift left
            for i = start; i < alen - del_count; i = i + 1 {
              @runtime.set_array_like_element(
                o,
                i + items_count,
                @runtime.get_array_like_element_interp(interp, o, i + del_count),
              )
            }
            // Delete trailing elements
            let new_len = alen - del_count + items_count
            for i = new_len; i < alen; i = i + 1 {
              @runtime.delete_array_like_element(o, i)
            }
            @runtime.set_array_like_length(o, new_len)
          } else if items_count > del_count {
            // Shift right
            let new_len = alen - del_count + items_count
            for i = alen - 1; i >= start + del_count; i = i - 1 {
              @runtime.set_array_like_element(
                o,
                i + items_count - del_count,
                @runtime.get_array_like_element_interp(interp, o, i),
              )
            }
            @runtime.set_array_like_length(o, new_len)
          }
          // Insert new items
          for i = 0; i < items_count; i = i + 1 {
            @runtime.set_array_like_element(o, start + i, new_items[i])
          }
          if items_count == del_count {
            // Length stays the same, no need to change
            ()
          }
        }
      }
      removed
    },
  )
  array_proto_props["copyWithin"] = @runtime.make_interp_method_func(
    name="copyWithin",
    length=2,
    fn(interp, this_val, args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let mut target = if args.length() > 0 {
        @runtime.to_number(args[0]).to_int()
      } else {
        0
      }
      let mut start = if args.length() > 1 {
        @runtime.to_number(args[1]).to_int()
      } else {
        0
      }
      let mut end = if args.length() > 2 {
        match args[2] {
          Undefined => len
          _ => @runtime.to_number(args[2]).to_int()
        }
      } else {
        len
      }
      if target < 0 {
        target = len + target
        if target < 0 {
          target = 0
        }
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if end < 0 {
        end = len + end
        if end < 0 {
          end = 0
        }
      }
      if end > len {
        end = len
      }
      let count = if end - start < len - target {
        end - start
      } else {
        len - target
      }
      if count > 0 {
        let temp : Array[Value] = []
        for i = start; i < start + count; i = i + 1 {
          temp.push(@runtime.get_array_like_element_interp(interp, o, i))
        }
        for i = 0; i < count; i = i + 1 {
          if target + i < len {
            @runtime.set_array_like_element(o, target + i, temp[i])
          }
        }
      }
      o
    },
  )
  array_proto_props["entries"] = @runtime.make_interp_method_func(
    name="entries",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let result : Array[Value] = []
      for i = 0; i < len; i = i + 1 {
        result.push(
          @runtime.make_array([
            Value::Number(i.to_double()),
            @runtime.get_array_like_element_interp(interp, o, i),
          ]),
        )
      }
      @runtime.make_array_iterator_value({
        elements: result,
        bag: @runtime.PropertyBag::new(),
      })
    },
  )
  array_proto_props["keys"] = @runtime.make_interp_method_func(
    name="keys",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let result : Array[Value] = []
      for i = 0; i < len; i = i + 1 {
        result.push(Value::Number(i.to_double()))
      }
      @runtime.make_array_iterator_value({
        elements: result,
        bag: @runtime.PropertyBag::new(),
      })
    },
  )
  array_proto_props["values"] = @runtime.make_interp_method_func(
    name="values",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let result : Array[Value] = []
      for i = 0; i < len; i = i + 1 {
        result.push(@runtime.get_array_like_element_interp(interp, o, i))
      }
      @runtime.make_array_iterator_value({
        elements: result,
        bag: @runtime.PropertyBag::new(),
      })
    },
  )
  array_proto_props["toReversed"] = @runtime.make_interp_method_func(
    name="toReversed",
    length=0,
    fn(interp, this_val, _args) raise {
      let o = to_object(this_val, interp)
      let len = @runtime.to_array_like_length_interp(o, interp)
      let result : Array[Value] = []
      for i = len - 1; i >= 0; i = i - 1 {
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
      let result = @runtime.to_array_like_elements(this_val)
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
              let cmp = @runtime.to_number(cmp_result) catch {
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
        @runtime.to_number(args[0]).to_int()
      } else {
        0
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if start > len {
        start = len
      }
      let del_count = if args.length() > 1 {
        let d = @runtime.to_number(args[1]).to_int()
        if d < 0 {
          0
        } else if d > len - start {
          len - start
        } else {
          d
        }
      } else {
        len - start
      }
      let result : Array[Value] = []
      for i = 0; i < start; i = i + 1 {
        result.push(@runtime.get_array_like_element_interp(interp, o, i))
      }
      for i = 2; i < args.length(); i = i + 1 {
        result.push(args[i])
      }
      for i = start + del_count; i < len; i = i + 1 {
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
        @runtime.to_number(args[0]).to_int()
      } else {
        0
      }
      let value = if args.length() > 1 { args[1] } else { Undefined }
      let len = @runtime.to_array_like_length_interp(o, interp)
      let actual_idx = if idx < 0 { len + idx } else { idx }
      if actual_idx < 0 || actual_idx >= len {
        raise @errors.RangeError(message="Invalid index")
      }
      let result : Array[Value] = []
      for i = 0; i < len; i = i + 1 {
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
  }
  let array_proto : Value = Value::Object({
    bag: {
      properties: array_proto_props,
      symbol_properties: {},
      descriptors: array_proto_descs,
      symbol_descriptors: {},
    },
    prototype: obj_proto,
    callable: None,
    class_name: "Array",
    extensible: true,
  })

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
      let iterator_sym = @runtime.get_iterator_symbol()
      let mut used_iterator = false
      let iterator_method = interp.get_computed_property(
        source,
        Symbol(iterator_sym),
        loc,
      )
      if @runtime.is_callable(iterator_method) {
        used_iterator = true
        let iterator = interp.call_value(iterator_method, source, [], loc)
        let mut k = 0
        while true {
          let next_fn = interp.get_property(iterator, "next", loc)
          let next = interp.call_value(next_fn, iterator, [], loc)
          let done = match next {
            Object(d) =>
              match d.bag.properties.get("done") {
                Some(v) => @runtime.is_truthy(v)
                _ => false
              }
            _ => true
          }
          if done {
            break
          }
          let value = match next {
            Object(d) =>
              match d.bag.properties.get("value") {
                Some(v) => v
                None => Undefined
              }
            _ => Undefined
          }
          let mapped = match map_fn {
            Some(fn_val) =>
              interp.call_value(
                fn_val,
                this_arg,
                [value, Value::Number(k.to_double())],
                loc,
              )
            None => value
          }
          elements.push(mapped)
          k = k + 1
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
            for i = 0; i < len; i = i + 1 {
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
        let result = interp.construct_value(
          this_val,
          [Value::Number(n.to_double())],
          loc,
        )
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
          },
          "isArray": obj_method_desc,
          "from": obj_method_desc,
          "of": obj_method_desc,
        },
        symbol_descriptors: {},
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
                // tracked in the length-override side table so arr.length still
                // reports the correct value.
                let elements : Array[Value] = if len64 <= 10000000L {
                  Array::make(len64.to_int(), Undefined)
                } else {
                  []
                }
                let arr_data : ArrayData = {
                  elements,
                  bag: @runtime.PropertyBag::new(),
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
    }),
  )
  // Set Array.prototype.constructor = Array
  match array_proto {
    Object(data) => {
      let arr_ctor = env.get("Array") catch { _ => Undefined }
      data.bag.properties["constructor"] = arr_ctor
      data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
}

///|
pub fn get_array_method(
  data : ArrayData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match prop {
    "push" => {
      let arr = data
      @runtime.make_native_func(name="push", realm_state=Some(realm_state), fn(
        args,
      ) raise {
        // §23.1.3.20 step 6: Set(A, "length", newLen) — throws if length
        // is non-writable. We must reject BEFORE mutating elements.
        if args.length() > 0 && !arr.length_writable {
          raise @errors.TypeError(
            message="Cannot assign to read only property 'length' of array",
          )
        }
        for arg in args {
          arr.elements.push(arg)
        }
        Value::Number(arr.elements.length().to_double())
      })
    }
    "pop" => {
      let arr = data
      @runtime.make_native_func(name="pop", realm_state=Some(realm_state), fn(
        _args,
      ) raise {
        if arr.elements.length() == 0 {
          // §23.1.3.19 step 3.b.ii: even for an empty array, pop attempts
          // Set(A, "length", 0), which throws when length is non-writable.
          if !arr.length_writable {
            raise @errors.TypeError(
              message="Cannot assign to read only property 'length' of array",
            )
          }
          Undefined
        } else {
          if !arr.length_writable {
            raise @errors.TypeError(
              message="Cannot assign to read only property 'length' of array",
            )
          }
          arr.elements.pop() |> Option::unwrap
        }
      })
    }
    "shift" => {
      let arr = data
      @runtime.make_native_func(name="shift", realm_state=Some(realm_state), fn(
        _args,
      ) raise {
        array_direct_shift(arr)
      })
    }
    "unshift" => {
      let arr = data
      @runtime.make_native_func(name="unshift", realm_state=Some(realm_state), fn(
        args,
      ) raise {
        array_direct_unshift(arr, args)
      })
    }
    "join" => {
      let arr = data
      @runtime.make_native_func(name="join", realm_state=Some(realm_state), fn(
        args,
      ) {
        let sep = if args.length() > 0 {
          match args[0] {
            Undefined => ","
            v => v.to_string()
          }
        } else {
          ","
        }
        let parts : Array[String] = arr.elements.map(fn(v) {
          match v {
            Null | Undefined => ""
            _ => v.to_string()
          }
        })
        Value::String_(parts.join(sep))
      })
    }
    "indexOf" | "lastIndexOf" => Undefined // Delegated to Array.prototype (hole handling)
    "includes" => {
      let arr = data
      @runtime.make_native_func(
        name="includes",
        realm_state=Some(realm_state),
        fn(args) raise {
          let search = if args.length() > 0 { args[0] } else { Undefined }
          let from_idx = if args.length() > 1 {
            @runtime.to_number(args[1]).to_int()
          } else {
            0
          }
          let len = arr.elements.length()
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
            if same_value_zero(arr.elements[i], search) {
              return Value::Bool(true)
            }
          }
          Value::Bool(false)
        },
      )
    }
    "slice" | "concat" => Undefined // Delegated to Array.prototype (species support)
    "reverse" => {
      let arr = data
      @runtime.make_native_func(name="reverse", realm_state=Some(realm_state), fn(
        _args,
      ) {
        array_direct_reverse(arr)
      })
    }
    "fill" => {
      let arr = data
      @runtime.make_native_func(name="fill", realm_state=Some(realm_state), fn(
        args,
      ) raise {
        array_direct_fill(arr, args)
      })
    }
    "toString" => {
      let arr = data
      @runtime.make_native_func(
        name="toString",
        realm_state=Some(realm_state),
        fn(_args) {
          let parts : Array[String] = arr.elements.map(fn(v) {
            match v {
              Null | Undefined => ""
              _ => v.to_string()
            }
          })
          Value::String_(parts.join(","))
        },
      )
    }
    "at" => {
      let arr = data
      @runtime.make_native_func(name="at", realm_state=Some(realm_state), fn(
        args,
      ) raise {
        // Array.prototype.at() - access element at index (supports negative)
        let idx = if args.length() > 0 {
          @runtime.to_number(args[0]).to_int()
        } else {
          0
        }
        let len = arr.elements.length()
        let actual_idx = if idx < 0 { len + idx } else { idx }
        if actual_idx >= 0 && actual_idx < len {
          arr.elements[actual_idx]
        } else {
          Undefined
        }
      })
    }
    "copyWithin" => {
      let arr = data
      @runtime.make_native_func(
        name="copyWithin",
        realm_state=Some(realm_state),
        fn(args) raise { array_direct_copy_within(arr, args) },
      )
    }
    "entries" | "keys" | "values" => Undefined // Delegated to Array.prototype (iterator method overrides)
    "splice" => Undefined // Delegated to Array.prototype (species support)
    "sort" => {
      let arr = data
      @runtime.make_native_func(name="sort", realm_state=Some(realm_state), fn(
        _args,
      ) {
        array_direct_sort_default(arr)
      })
    }
    _ => Undefined
  }
}

///|
pub fn get_array_method_with_interp(
  data : ArrayData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match prop {
    "join" | "toString" => Undefined // Delegated to Array.prototype (live join)
    "includes" | "at" => Undefined // Delegated to Array.prototype (live indexed properties)
    "forEach" | "map" | "filter" => Undefined // Delegated to Array.prototype
    "reduce" | "reduceRight" => Undefined // Delegated to Array.prototype
    "find" | "findIndex" | "findLast" | "findLastIndex" => Undefined // Delegated to Array.prototype
    "every" | "some" => Undefined // Delegated to Array.prototype
    "shift" => {
      let arr = data
      @runtime.make_interp_method_func(
        name="shift",
        length=0,
        realm_state=Some(realm_state),
        fn(interp, this_val, _args) raise {
          let _ = this_val
          array_shift_indexed_properties(interp, Value::Array(arr))
        },
      )
    }
    "unshift" => {
      let arr = data
      @runtime.make_interp_method_func(
        name="unshift",
        length=1,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          let _ = this_val
          array_unshift_indexed_properties(interp, Value::Array(arr), args)
        },
      )
    }
    "reverse" => {
      let arr = data
      @runtime.make_interp_method_func(
        name="reverse",
        length=0,
        realm_state=Some(realm_state),
        fn(interp, this_val, _args) raise {
          let _ = this_val
          array_reverse_indexed_properties(interp, Value::Array(arr))
        },
      )
    }
    "fill" => {
      let arr = data
      @runtime.make_interp_method_func(
        name="fill",
        length=1,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          let _ = this_val
          array_fill_indexed_properties(interp, Value::Array(arr), args)
        },
      )
    }
    "copyWithin" => {
      let arr = data
      @runtime.make_interp_method_func(
        name="copyWithin",
        length=2,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          let _ = this_val
          array_copy_within_indexed_properties(interp, Value::Array(arr), args)
        },
      )
    }
    "toReversed" | "toSorted" | "toSpliced" | "with" => Undefined // Delegated to Array.prototype (copy-by-value methods)
    "flat" | "flatMap" => Undefined // Delegated to Array.prototype (species support)
    "sort" => {
      // Sort with optional compareFn needs InterpreterCallable
      let arr = data
      @runtime.make_interp_method_func(
        name="sort",
        length=1,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          let _ = this_val
          let comparefn = array_sort_validate_comparefn(args)
          array_sort_indexed_properties(interp, Value::Array(arr), comparefn)
        },
      )
    }
    "concat" => Undefined // Delegated to Array.prototype (species support)
    _ => get_array_method(data, prop, realm_state)
  }
}

///|
pub fn strict_equal_val(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Value::Number(a), Value::Number(b)) => a == b
    (Value::String_(a), Value::String_(b)) => a == b
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Null, Null) => true
    (Undefined, Undefined) => true
    (Object(a), Object(b)) => physical_equal(a, b)
    (Array(a), Array(b)) => physical_equal(a, b)
    (Symbol(a), Symbol(b)) => a.id == b.id // Symbols compare by identity
    (Promise(a), Promise(b)) => physical_equal(a, b) // Promises compare by reference
    (Proxy(a), Proxy(b)) => physical_equal(a, b) // Proxies compare by reference
    _ => false
  }
}

///|
pub fn same_value_zero(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Value::Number(a), Value::Number(b)) =>
      if a.is_nan() && b.is_nan() {
        true
      } else {
        a == b
      }
    _ => strict_equal_val(a, b)
  }
}

///|
pub fn same_value(a : Value, b : Value) -> Bool {
  // SameValue algorithm per ECMAScript spec
  // Differs from === in: NaN === NaN, and +0 !== -0
  match (a, b) {
    (Value::Number(x), Value::Number(y)) =>
      if x.is_nan() && y.is_nan() {
        true
      } else if x == 0.0 && y == 0.0 {
        // Check for +0 vs -0
        1.0 / x == 1.0 / y
      } else {
        x == y
      }
    _ => strict_equal_val(a, b)
  }
}

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
    "entries" => {
      let arr = data
      @runtime.make_method_func(
        name="entries",
        length=0,
        realm_state=Some(realm_state),
        fn(_this_val, _args) {
          let result : Array[Value] = []
          for i = 0; i < arr.elements.length(); i = i + 1 {
            result.push(
              @runtime.make_array([
                Value::Number(i.to_double()),
                arr.elements[i],
              ]),
            )
          }
          realm_state.make_array_iterator_value({
            elements: result,
            bag: @runtime.PropertyBag(),
            length_writable: true,
            holes: {},
            extensible: true,
          })
        },
      )
    }
    "keys" => {
      let arr = data
      @runtime.make_method_func(
        name="keys",
        length=0,
        realm_state=Some(realm_state),
        fn(_this_val, _args) {
          let result : Array[Value] = []
          for i = 0; i < arr.elements.length(); i = i + 1 {
            result.push(Value::Number(i.to_double()))
          }
          realm_state.make_array_iterator_value({
            elements: result,
            bag: @runtime.PropertyBag(),
            length_writable: true,
            holes: {},
            extensible: true,
          })
        },
      )
    }
    "values" => {
      let arr = data
      @runtime.make_method_func(
        name="values",
        length=0,
        realm_state=Some(realm_state),
        fn(_this_val, _args) { realm_state.make_array_iterator_value(arr) },
      )
    }
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
    "join" => Undefined // Delegated to Array.prototype (interpreter-aware ToString)
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
    "toReversed" => {
      let arr = data
      @runtime.make_native_func(
        name="toReversed",
        realm_state=Some(realm_state),
        fn(_args) {
          // Non-mutating reverse
          let result : Array[Value] = []
          for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
            result.push(arr.elements[i])
          }
          @runtime.make_array(result)
        },
      )
    }
    "toSorted" => {
      let arr = data
      @runtime.make_interp_method_func(
        name="toSorted",
        length=1,
        realm_state=Some(realm_state),
        fn(interp, this_val, args) raise {
          let _ = this_val
          // Create a copy of the array
          let result : Array[Value] = []
          for el in arr.elements {
            result.push(el)
          }
          // Sort the copy
          if args.length() > 0 {
            match args[0] {
              Undefined =>
                // Default sort: undefined goes to end
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
                // Store any exception to re-throw after sort (spec requires propagation)
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
                  // Skip comparisons if we already have an error
                  if caught_error is Some(_) {
                    return 0
                  }
                  let compare_result = interp.call_value(
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
                  // Use sign-based comparison to avoid truncating fractional values
                  let cmp = @runtime.to_number(compare_result) catch {
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
                // Re-throw any caught exception per spec
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
    }
    "toSpliced" => {
      let arr = data
      @runtime.make_native_func(
        name="toSpliced",
        realm_state=Some(realm_state),
        fn(args) raise {
          // Non-mutating splice
          let len = arr.elements.length()
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
          // Copy before start
          for i = 0; i < start; i = i + 1 {
            result.push(arr.elements[i])
          }
          // Add new items
          for i = 2; i < args.length(); i = i + 1 {
            result.push(args[i])
          }
          // Copy after deleted portion
          for i = start + del_count; i < len; i = i + 1 {
            result.push(arr.elements[i])
          }
          @runtime.make_array(result)
        },
      )
    }
    "with" => {
      let arr = data
      @runtime.make_native_func(name="with", realm_state=Some(realm_state), fn(
        args,
      ) raise {
        // Non-mutating element replacement
        let idx = if args.length() > 0 {
          @runtime.to_number(args[0]).to_int()
        } else {
          0
        }
        let value = if args.length() > 1 { args[1] } else { Undefined }
        let len = arr.elements.length()
        let actual_idx = if idx < 0 { len + idx } else { idx }
        if actual_idx < 0 || actual_idx >= len {
          raise @errors.RangeError(message="Invalid index")
        }
        let result : Array[Value] = []
        for i = 0; i < len; i = i + 1 {
          if i == actual_idx {
            result.push(value)
          } else {
            result.push(arr.elements[i])
          }
        }
        @runtime.make_array(result)
      })
    }
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

///|
pub fn get_array_method(data : ArrayData, prop : String) -> Value {
  match prop {
    "push" => {
      let arr = data
      @runtime.make_native_func("push", fn(args) {
        for arg in args {
          arr.elements.push(arg)
        }
        Value::Number(arr.elements.length().to_double())
      })
    }
    "pop" => {
      let arr = data
      @runtime.make_native_func("pop", fn(_args) {
        if arr.elements.length() == 0 {
          Undefined
        } else {
          arr.elements.pop() |> Option::unwrap
        }
      })
    }
    "shift" => {
      let arr = data
      @runtime.make_native_func("shift", fn(_args) {
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
      })
    }
    "unshift" => {
      let arr = data
      @runtime.make_native_func("unshift", fn(args) {
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
      })
    }
    "join" => {
      let arr = data
      @runtime.make_native_func("join", fn(args) {
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
      @runtime.make_native_func("includes", fn(args) raise {
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
      })
    }
    "slice" | "concat" => Undefined // Delegated to Array.prototype (species support)
    "reverse" => {
      let arr = data
      @runtime.make_native_func("reverse", fn(_args) {
        arr.elements.rev_in_place()
        Value::Array(arr)
      })
    }
    "fill" => {
      let arr = data
      @runtime.make_native_func("fill", fn(args) raise {
        let fill_val = if args.length() > 0 { args[0] } else { Undefined }
        let alen = arr.elements.length()
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
        // Normalize negative start
        if start < 0 {
          start = alen + start
          if start < 0 {
            start = 0
          }
        }
        // Clamp start to array length
        if start > alen {
          start = alen
        }
        // Normalize negative end
        if end < 0 {
          end = alen + end
          if end < 0 {
            end = 0
          }
        }
        // Clamp end to array length
        if end > alen {
          end = alen
        }
        for i = start; i < end; i = i + 1 {
          arr.elements[i] = fill_val
        }
        Value::Array(arr)
      })
    }
    "toString" => {
      let arr = data
      @runtime.make_native_func("toString", fn(_args) {
        let parts : Array[String] = arr.elements.map(fn(v) {
          match v {
            Null | Undefined => ""
            _ => v.to_string()
          }
        })
        Value::String_(parts.join(","))
      })
    }
    "at" => {
      let arr = data
      @runtime.make_native_func("at", fn(args) raise {
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
      @runtime.make_native_func("copyWithin", fn(args) raise {
        // Array.prototype.copyWithin(target, start, end?)
        let len = arr.elements.length()
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
        // Normalize negative indices
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
        // Copy elements
        let count = if end - start < len - target {
          end - start
        } else {
          len - target
        }
        if count > 0 {
          // Copy to temporary first to handle overlapping
          let temp : Array[Value] = []
          for i = start; i < start + count; i = i + 1 {
            temp.push(arr.elements[i])
          }
          for i = 0; i < count; i = i + 1 {
            if target + i < len {
              arr.elements[target + i] = temp[i]
            }
          }
        }
        Value::Array(arr)
      })
    }
    "entries" => {
      let arr = data
      @runtime.make_native_func("entries", fn(_args) {
        let result : Array[Value] = []
        for i = 0; i < arr.elements.length(); i = i + 1 {
          result.push(
            @runtime.make_array([Value::Number(i.to_double()), arr.elements[i]]),
          )
        }
        @runtime.make_array_iterator_value({
          elements: result,
          bag: @runtime.new_property_bag(),
        })
      })
    }
    "keys" => {
      let arr = data
      @runtime.make_native_func("keys", fn(_args) {
        let result : Array[Value] = []
        for i = 0; i < arr.elements.length(); i = i + 1 {
          result.push(Value::Number(i.to_double()))
        }
        @runtime.make_array_iterator_value({
          elements: result,
          bag: @runtime.new_property_bag(),
        })
      })
    }
    "values" => {
      let arr = data
      @runtime.make_native_func("values", fn(_args) {
        @runtime.make_array_iterator_value(arr)
      })
    }
    "splice" => Undefined // Delegated to Array.prototype (species support)
    "sort" => {
      let arr = data
      @runtime.make_native_func("sort", fn(_args) {
        // Default sort: undefined goes to end, then compare as strings
        arr.elements.sort_by(fn(a, b) {
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
        Value::Array(arr)
      })
    }
    _ => Undefined
  }
}

///|
pub fn get_array_method_with_interp(data : ArrayData, prop : String) -> Value {
  match prop {
    "forEach" | "map" | "filter" => Undefined // Delegated to Array.prototype
    "reduce" | "reduceRight" => Undefined // Delegated to Array.prototype
    "find" | "findIndex" | "findLast" | "findLastIndex" => Undefined // Delegated to Array.prototype
    "every" | "some" => Undefined // Delegated to Array.prototype
    "toReversed" => {
      let arr = data
      @runtime.make_native_func("toReversed", fn(_args) {
        // Non-mutating reverse
        let result : Array[Value] = []
        for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
          result.push(arr.elements[i])
        }
        @runtime.make_array(result)
      })
    }
    "toSorted" => {
      let arr = data
      @runtime.make_interp_method_func("toSorted", 1, fn(
        interp,
        this_val,
        args,
      ) raise {
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
      })
    }
    "toSpliced" => {
      let arr = data
      @runtime.make_native_func("toSpliced", fn(args) raise {
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
      })
    }
    "with" => {
      let arr = data
      @runtime.make_native_func("with", fn(args) raise {
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
      @runtime.make_interp_method_func("sort", 1, fn(
        interp,
        this_val,
        args,
      ) raise {
        let _ = this_val
        // Validate comparefn before sorting
        if args.length() > 0 {
          let comparefn = args[0]
          match comparefn {
            Undefined => ()
            _ =>
              if !@runtime.is_callable(comparefn) {
                raise @errors.TypeError(
                  message=@runtime.to_js_string(comparefn) +
                    " is not a function",
                )
              }
          }
        }
        if args.length() > 0 {
          match args[0] {
            Undefined =>
              // Default sort: undefined goes to end
              arr.elements.sort_by(fn(a, b) {
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
              arr.elements.sort_by(fn(a, b) {
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
                // Skip comparisons if we already have an error
                if caught_error is Some(_) {
                  return 0
                }
                let result = interp.call_value(
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
              // Re-throw any caught exception per spec
              match caught_error {
                Some(e) => raise e
                None => ()
              }
            }
          }
        } else {
          arr.elements.sort_by(fn(a, b) {
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
        Value::Array(arr)
      })
    }
    "concat" => Undefined // Delegated to Array.prototype (species support)
    _ => get_array_method(data, prop)
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

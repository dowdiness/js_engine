///|
pub fn get_array_method(data : ArrayData, prop : String) -> Value {
  match prop {
    "push" => {
      let arr = data
      make_native_func("push", fn(args) {
        for arg in args {
          arr.elements.push(arg)
        }
        Number(arr.elements.length().to_double())
      })
    }
    "pop" => {
      let arr = data
      make_native_func("pop", fn(_args) {
        if arr.elements.length() == 0 {
          Undefined
        } else {
          arr.elements.pop() |> Option::unwrap
        }
      })
    }
    "shift" => {
      let arr = data
      make_native_func("shift", fn(_args) {
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
      make_native_func("unshift", fn(args) {
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
        Number(arr.elements.length().to_double())
      })
    }
    "join" => {
      let arr = data
      make_native_func("join", fn(args) {
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
        String_(parts.join(sep))
      })
    }
    "indexOf" => {
      let arr = data
      make_native_func("indexOf", fn(args) raise {
        let search = if args.length() > 0 { args[0] } else { Undefined }
        let len = arr.elements.length()
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
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
        // If start >= length, return -1
        if start >= len {
          return Number(-1.0)
        }
        for i = start; i < len; i = i + 1 {
          if strict_equal_val(arr.elements[i], search) {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      })
    }
    "lastIndexOf" => {
      let arr = data
      make_native_func("lastIndexOf", fn(args) raise {
        let search = if args.length() > 0 { args[0] } else { Undefined }
        let start = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          arr.elements.length() - 1
        }
        let from = if start < 0 {
          arr.elements.length() + start
        } else if start >= arr.elements.length() {
          arr.elements.length() - 1
        } else {
          start
        }
        for i = from; i >= 0; i = i - 1 {
          if strict_equal_val(arr.elements[i], search) {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      })
    }
    "includes" => {
      let arr = data
      make_native_func("includes", fn(args) raise {
        let search = if args.length() > 0 { args[0] } else { Undefined }
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
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
            return Bool(true)
          }
        }
        Bool(false)
      })
    }
    "slice" => {
      let arr = data
      make_native_func("slice", fn(args) raise {
        let alen = arr.elements.length()
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 1 {
          match args[1] {
            Undefined => alen
            _ => to_number(args[1]).to_int()
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
        let result : Array[Value] = []
        for i = start; i < end; i = i + 1 {
          result.push(arr.elements[i])
        }
        Array({ elements: result })
      })
    }
    "concat" => {
      let arr = data
      make_native_func("concat", fn(args) {
        let result : Array[Value] = []
        for el in arr.elements {
          result.push(el)
        }
        for arg in args {
          match arg {
            Array(other) =>
              for el in other.elements {
                result.push(el)
              }
            _ => result.push(arg)
          }
        }
        Array({ elements: result })
      })
    }
    "reverse" => {
      let arr = data
      make_native_func("reverse", fn(_args) {
        arr.elements.rev_in_place()
        Array(arr)
      })
    }
    "fill" => {
      let arr = data
      make_native_func("fill", fn(args) raise {
        let fill_val = if args.length() > 0 { args[0] } else { Undefined }
        let alen = arr.elements.length()
        let mut start = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 2 {
          match args[2] {
            Undefined => alen
            _ => to_number(args[2]).to_int()
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
        Array(arr)
      })
    }
    "toString" => {
      let arr = data
      make_native_func("toString", fn(_args) {
        let parts : Array[String] = arr.elements.map(fn(v) {
          match v {
            Null | Undefined => ""
            _ => v.to_string()
          }
        })
        String_(parts.join(","))
      })
    }
    "at" => {
      let arr = data
      make_native_func("at", fn(args) raise {
        // Array.prototype.at() - access element at index (supports negative)
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
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
      make_native_func("copyWithin", fn(args) raise {
        // Array.prototype.copyWithin(target, start, end?)
        let len = arr.elements.length()
        let mut target = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          0
        }
        let mut start = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 2 {
          match args[2] {
            Undefined => len
            _ => to_number(args[2]).to_int()
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
        Array(arr)
      })
    }
    "entries" => {
      let arr = data
      make_native_func("entries", fn(_args) {
        // Returns array of [index, value] pairs (basic non-iterator version)
        let result : Array[Value] = []
        for i = 0; i < arr.elements.length(); i = i + 1 {
          result.push(
            Array({ elements: [Number(i.to_double()), arr.elements[i]] }),
          )
        }
        Array({ elements: result })
      })
    }
    "keys" => {
      let arr = data
      make_native_func("keys", fn(_args) {
        // Returns array of keys (basic non-iterator version)
        let result : Array[Value] = []
        for i = 0; i < arr.elements.length(); i = i + 1 {
          result.push(Number(i.to_double()))
        }
        Array({ elements: result })
      })
    }
    "values" => {
      let arr = data
      make_native_func("values", fn(_args) {
        // Returns array of values (basic non-iterator version)
        // Return a copy to prevent mutation of the original
        let result : Array[Value] = []
        for el in arr.elements {
          result.push(el)
        }
        Array({ elements: result })
      })
    }
    "splice" => {
      let arr = data
      make_native_func("splice", fn(args) raise {
        let alen = arr.elements.length()
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
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
          let d_num = to_number(args[1])
          // Handle Infinity and negative values
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
        let removed : Array[Value] = []
        for i = start; i < start + del_count; i = i + 1 {
          removed.push(arr.elements[i])
        }
        let new_items : Array[Value] = []
        for i = 2; i < args.length(); i = i + 1 {
          new_items.push(args[i])
        }
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
        Array({ elements: removed })
      })
    }
    "sort" => {
      let arr = data
      make_native_func("sort", fn(_args) {
        // Default sort: convert to strings and compare
        arr.elements.sort_by(fn(a, b) {
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
        Array(arr)
      })
    }
    _ => Undefined
  }
}

///|
pub fn get_array_method_with_interp(data : ArrayData, prop : String) -> Value {
  match prop {
    "forEach" => {
      let arr = data
      make_interp_method_func("forEach", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let _ = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
            }
            Undefined
          })
    }
    "map" => {
      let arr = data
      make_interp_method_func("map", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            let result : Array[Value] = []
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              result.push(val)
            }
            Array({ elements: result })
          })
    }
    "filter" => {
      let arr = data
      make_interp_method_func("filter", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            let result : Array[Value] = []
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              if is_truthy(val) {
                result.push(arr.elements[i])
              }
            }
            Array({ elements: result })
          })
    }
    "reduce" => {
      let arr = data
      make_interp_method_func("reduce", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let loc = @token.Loc::default()
            let mut acc : Value = Undefined
            let mut start = 0
            if args.length() > 1 {
              acc = args[1]
            } else {
              if arr.elements.length() == 0 {
                raise @errors.TypeError(
                  message="Reduce of empty array with no initial value",
                )
              }
              acc = arr.elements[0]
              start = 1
            }
            for i = start; i < arr.elements.length(); i = i + 1 {
              acc = interp.call_value(
                callback,
                Undefined,
                [acc, arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
            }
            acc
          })
    }
    "reduceRight" => {
      let arr = data
      make_interp_method_func("reduceRight", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let loc = @token.Loc::default()
            let mut acc : Value = Undefined
            let mut start = arr.elements.length() - 1
            if args.length() > 1 {
              acc = args[1]
            } else {
              if arr.elements.length() == 0 {
                raise @errors.TypeError(
                  message="Reduce of empty array with no initial value",
                )
              }
              acc = arr.elements[start]
              start = start - 1
            }
            for i = start; i >= 0; i = i - 1 {
              acc = interp.call_value(
                callback,
                Undefined,
                [acc, arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
            }
            acc
          })
    }
    "find" => {
      let arr = data
      make_interp_method_func("find", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              if is_truthy(val) {
                return arr.elements[i]
              }
            }
            Undefined
          })
    }
    "findIndex" => {
      let arr = data
      make_interp_method_func("findIndex", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              if is_truthy(val) {
                return Number(i.to_double())
              }
            }
            Number(-1.0)
          })
    }
    "every" => {
      let arr = data
      make_interp_method_func("every", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              if not(is_truthy(val)) {
                return Bool(false)
              }
            }
            Bool(true)
          })
    }
    "some" => {
      let arr = data
      make_interp_method_func("some", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              if is_truthy(val) {
                return Bool(true)
              }
            }
            Bool(false)
          })
    }
    "findLast" => {
      let arr = data
      make_interp_method_func("findLast", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              if is_truthy(val) {
                return arr.elements[i]
              }
            }
            Undefined
          })
    }
    "findLastIndex" => {
      let arr = data
      make_interp_method_func("findLastIndex", 1, fn(
            interp,
            this_val,
            args,
          ) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              if is_truthy(val) {
                return Number(i.to_double())
              }
            }
            Number(-1.0)
          })
    }
    "toReversed" => {
      let arr = data
      make_native_func("toReversed", fn(_args) {
        // Non-mutating reverse
        let result : Array[Value] = []
        for i = arr.elements.length() - 1; i >= 0; i = i - 1 {
          result.push(arr.elements[i])
        }
        Array({ elements: result })
      })
    }
    "toSorted" => {
      let arr = data
      make_interp_method_func("toSorted", 1, fn(interp, this_val, args) raise {
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
                  // Default sort
                  result.sort_by(fn(a, b) {
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
                    let cmp = to_number(compare_result) catch {
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
            Array({ elements: result })
          })
    }
    "toSpliced" => {
      let arr = data
      make_native_func("toSpliced", fn(args) raise {
        // Non-mutating splice
        let len = arr.elements.length()
        let mut start = if args.length() > 0 {
          to_number(args[0]).to_int()
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
          let d = to_number(args[1]).to_int()
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
        Array({ elements: result })
      })
    }
    "with" => {
      let arr = data
      make_native_func("with", fn(args) raise {
        // Non-mutating element replacement
        let idx = if args.length() > 0 {
          to_number(args[0]).to_int()
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
        Array({ elements: result })
      })
    }
    "flat" => {
      let arr = data
      make_native_func("flat", fn(args) raise {
        let depth = if args.length() > 0 {
          to_number(args[0]).to_int()
        } else {
          1
        }
        let result : Array[Value] = []
        flatten_array(arr.elements, depth, result)
        Array({ elements: result })
      })
    }
    "flatMap" => {
      let arr = data
      make_interp_method_func("flatMap", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            let callback = if args.length() > 0 { args[0] } else { Undefined }
            if not(is_callable(callback)) {
              raise @errors.TypeError(message=to_js_string(callback) + " is not a function")
            }
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let loc = @token.Loc::default()
            let result : Array[Value] = []
            for i = 0; i < arr.elements.length(); i = i + 1 {
              let val = interp.call_value(
                callback,
                this_arg,
                [arr.elements[i], Number(i.to_double()), Array(arr)],
                loc,
              )
              match val {
                Array(inner) =>
                  for el in inner.elements {
                    result.push(el)
                  }
                _ => result.push(val)
              }
            }
            Array({ elements: result })
          })
    }
    "sort" => {
      // Sort with optional compareFn needs InterpreterCallable
      let arr = data
      make_interp_method_func("sort", 1, fn(interp, this_val, args) raise {
            let _ = this_val
            // Validate comparefn before sorting
            if args.length() > 0 {
              let comparefn = args[0]
              match comparefn {
                Undefined => ()
                _ =>
                  if not(is_callable(comparefn)) {
                    raise @errors.TypeError(message=to_js_string(comparefn) + " is not a function")
                  }
              }
            }
            if args.length() > 0 {
              match args[0] {
                Undefined =>
                  // Default sort
                  arr.elements.sort_by(fn(a, b) {
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
                    let cmp = to_number(result) catch {
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
            Array(arr)
          })
    }
    _ => get_array_method(data, prop)
  }
}

///|
fn flatten_array(
  elements : Array[Value],
  depth : Int,
  result : Array[Value],
) -> Unit {
  for el in elements {
    match el {
      Array(inner) =>
        if depth > 0 {
          flatten_array(inner.elements, depth - 1, result)
        } else {
          result.push(el)
        }
      _ => result.push(el)
    }
  }
}

///|
pub fn strict_equal_val(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Number(a), Number(b)) => a == b
    (String_(a), String_(b)) => a == b
    (Bool(a), Bool(b)) => a == b
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
    (Number(a), Number(b)) =>
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
    (Number(x), Number(y)) =>
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

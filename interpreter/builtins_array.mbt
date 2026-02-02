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
      make_native_func("indexOf", fn(args) {
        let search = if args.length() > 0 { args[0] } else { Undefined }
        let from_idx = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let start = if from_idx < 0 {
          let s = arr.elements.length() + from_idx
          if s < 0 {
            0
          } else {
            s
          }
        } else {
          from_idx
        }
        for i = start; i < arr.elements.length(); i = i + 1 {
          if strict_equal_val(arr.elements[i], search) {
            return Number(i.to_double())
          }
        }
        Number(-1.0)
      })
    }
    "lastIndexOf" => {
      let arr = data
      make_native_func("lastIndexOf", fn(args) {
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
      make_native_func("includes", fn(args) {
        let search = if args.length() > 0 { args[0] } else { Undefined }
        for el in arr.elements {
          if same_value_zero(el, search) {
            return Bool(true)
          }
        }
        Bool(false)
      })
    }
    "slice" => {
      let arr = data
      make_native_func("slice", fn(args) {
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
      make_native_func("fill", fn(args) {
        let fill_val = if args.length() > 0 { args[0] } else { Undefined }
        let alen = arr.elements.length()
        let mut start = if args.length() > 1 {
          to_number(args[1]).to_int()
        } else {
          0
        }
        let mut end = if args.length() > 2 {
          to_number(args[2]).to_int()
        } else {
          alen
        }
        if start < 0 {
          start = alen + start
        }
        if end < 0 {
          end = alen + end
        }
        for i = start; i < end; i = i + 1 {
          if i >= 0 && i < alen {
            arr.elements[i] = fill_val
          }
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
    "splice" => {
      let arr = data
      make_native_func("splice", fn(args) {
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
          let d = to_number(args[1]).to_int()
          if d < 0 {
            0
          } else if d > alen - start {
            alen - start
          } else {
            d
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
fn strict_equal_val(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Number(a), Number(b)) => a == b
    (String_(a), String_(b)) => a == b
    (Bool(a), Bool(b)) => a == b
    (Null, Null) => true
    (Undefined, Undefined) => true
    (Object(a), Object(b)) => physical_equal(a, b)
    (Array(a), Array(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
fn same_value_zero(a : Value, b : Value) -> Bool {
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

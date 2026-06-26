///|
pub fn get_array_method(
  data : ArrayData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match prop {
    "push" | "pop" | "shift" | "unshift" => Undefined // Delegated to Array.prototype (overrides and indexed [[Set]]/[[Get]]/[[Delete]])
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
      @runtime.make_interp_method_func(
        name="includes",
        realm_state=Some(realm_state),
        fn(interp, _this_val, args) raise {
          let search = if args.length() > 0 { args[0] } else { Undefined }
          let from_idx = if args.length() > 1 {
            interp.to_number(args[1]).to_int()
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
    "reverse" | "fill" => Undefined // Delegated to Array.prototype (indexed [[Set]]/[[Delete]] + length-writable)
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
      @runtime.make_interp_method_func(
        name="at",
        realm_state=Some(realm_state),
        fn(interp, _this_val, args) raise {
          // Array.prototype.at() - access element at index (supports negative)
          let idx = if args.length() > 0 {
            interp.to_number(args[0]).to_int()
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
        },
      )
    }
    "copyWithin" | "sort" => Undefined // Delegated to Array.prototype (indexed [[Set]]/[[Delete]] + length-writable)
    "entries" | "keys" | "values" => Undefined // Delegated to Array.prototype (iterator method overrides)
    "splice" => Undefined // Delegated to Array.prototype (species support)
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
    "shift" | "unshift" => Undefined // Delegated to Array.prototype (overrides and indexed mutation semantics)
    "reverse" | "fill" | "copyWithin" | "sort" => Undefined // Delegated to Array.prototype (indexed [[Set]]/[[Delete]] + length-writable)
    "toReversed" | "toSorted" | "toSpliced" | "with" => Undefined // Delegated to Array.prototype (copy-by-value methods)
    "flat" | "flatMap" => Undefined // Delegated to Array.prototype (species support)
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

///|
pub fn get_array_method(
  _data : ArrayData,
  _prop : String,
  _realm_state : @runtime.RealmState,
) -> Value {
  Undefined // All methods delegated to Array.prototype
}

///|
pub fn get_array_method_with_interp(
  _data : ArrayData,
  prop : String,
  _realm_state : @runtime.RealmState,
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
    _ => Undefined
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

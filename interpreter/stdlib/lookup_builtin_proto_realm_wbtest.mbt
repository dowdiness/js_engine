///| Whitebox tests for `lookup_builtin_proto` dispatch by RealmState.
///
/// PR sibling to the boxed-primitive/Array routing PRs: this pins the
/// per-realm property-walk invariant for the 5 families dispatched from
/// `interpreter/runtime/property.mbt:lookup_builtin_proto`
/// (Array, String, Number, Boolean, Symbol).
///
/// The boxed-primitive identity tests already pin the cache-for-X equality
/// between `realm_state.{string,number,boolean,symbol}_prototype` and each
/// constructor's `.prototype` slot. These tests go one step further: they
/// install a marker property on each realm's prototype object and then
/// exercise the property-access fall-through path so that the assertion is
/// about actual *walked dispatch*, not just object-identity equality.
///
/// Regression this guards against: a future change that re-routes one
/// `lookup_builtin_proto` arm back through `interp.global.get(ctor)` or
/// hard-codes a non-realm-aware prototype source would still satisfy the
/// identity pin in a fresh realm but would observe the wrong prototype
/// after a per-realm mutation.

///|
fn install_marker(
  proto : Value,
  marker_name : String,
  marker_value : String,
) -> Unit raise Error {
  match proto {
    Object(pdata) =>
      pdata.bag.properties.set(marker_name, String_(marker_value))
    _ =>
      fail(
        "prototype is not an Object — cannot install marker on " + marker_name,
      )
  }
}

///|
fn install_symbol_marker(
  proto : Value,
  sym_id : Int,
  marker_value : String,
) -> Unit raise Error {
  match proto {
    Object(pdata) =>
      pdata.bag.symbol_properties.set(sym_id, String_(marker_value))
    _ => fail("prototype is not an Object — cannot install symbol marker")
  }
}

///|
fn make_realm_interp() -> @runtime.Interpreter {
  @runtime.Interpreter::new(setup_builtins=fn(env, args, rs, ab) {
    setup_builtins_with_realm_state(env, args, rs, annex_b=ab)
  })
}

///|
fn assert_marker(
  label : String,
  result : Value,
  expected : String,
) -> Unit raise Error {
  match result {
    String_(s) =>
      if s != expected {
        fail(label + ": expected marker \"" + expected + "\" got \"" + s + "\"")
      }
    _ => fail(label + ": expected String_ marker, got non-string value")
  }
}

///|
test "Array lookup_builtin_proto dispatches per realm" {
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  install_marker(
    realm_a.realm_state.get_array_proto(),
    "__lookup_proto_marker__",
    "A-array",
  )
  install_marker(
    realm_b.realm_state.get_array_proto(),
    "__lookup_proto_marker__",
    "B-array",
  )
  let arr : Value = @runtime.make_array([Number(1.0)])
  let result_a = realm_a.get_property(
    arr,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  let result_b = realm_b.get_property(
    arr,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  assert_marker("Array realm A", result_a, "A-array")
  assert_marker("Array realm B", result_b, "B-array")
}

///|
test "String lookup_builtin_proto dispatches per realm" {
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  install_marker(
    realm_a.realm_state.get_string_proto(),
    "__lookup_proto_marker__",
    "A-string",
  )
  install_marker(
    realm_b.realm_state.get_string_proto(),
    "__lookup_proto_marker__",
    "B-string",
  )
  let s : Value = String_("hello")
  let result_a = realm_a.get_property(
    s,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  let result_b = realm_b.get_property(
    s,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  assert_marker("String realm A", result_a, "A-string")
  assert_marker("String realm B", result_b, "B-string")
}

///|
test "Number lookup_builtin_proto dispatches per realm" {
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  install_marker(
    realm_a.realm_state.get_number_proto(),
    "__lookup_proto_marker__",
    "A-number",
  )
  install_marker(
    realm_b.realm_state.get_number_proto(),
    "__lookup_proto_marker__",
    "B-number",
  )
  let n : Value = Number(42.0)
  let result_a = realm_a.get_property(
    n,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  let result_b = realm_b.get_property(
    n,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  assert_marker("Number realm A", result_a, "A-number")
  assert_marker("Number realm B", result_b, "B-number")
}

///|
test "Boolean lookup_builtin_proto dispatches per realm" {
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  install_marker(
    realm_a.realm_state.get_boolean_proto(),
    "__lookup_proto_marker__",
    "A-bool",
  )
  install_marker(
    realm_b.realm_state.get_boolean_proto(),
    "__lookup_proto_marker__",
    "B-bool",
  )
  let b : Value = Bool(true)
  let result_a = realm_a.get_property(
    b,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  let result_b = realm_b.get_property(
    b,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  assert_marker("Boolean realm A", result_a, "A-bool")
  assert_marker("Boolean realm B", result_b, "B-bool")
}

///|
test "Array proto walk via Object-with-Array-prototype dispatches per realm" {
  // Pins property.mbt:387 (get_property_of_object Array branch fall-through
  // to Array.prototype). Constructs an Object whose [[Prototype]] is an
  // Array; named-property lookup walks Object → Array → site 387 → routes
  // through realm_state.get_array_proto() → next iter finds marker on
  // Array.prototype.
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  install_marker(
    realm_a.realm_state.get_array_proto(),
    "__array_chain_marker__",
    "A-array-chain",
  )
  install_marker(
    realm_b.realm_state.get_array_proto(),
    "__array_chain_marker__",
    "B-array-chain",
  )
  let arr_a : Value = @runtime.make_array([])
  let arr_b : Value = @runtime.make_array([])
  let obj_a : Value = @runtime.make_object({}, arr_a, None, "Object", {}, true)
  let obj_b : Value = @runtime.make_object({}, arr_b, None, "Object", {}, true)
  let result_a = realm_a.get_property(
    obj_a,
    "__array_chain_marker__",
    @token.Loc::default(),
  )
  let result_b = realm_b.get_property(
    obj_b,
    "__array_chain_marker__",
    @token.Loc::default(),
  )
  assert_marker("Array chain realm A", result_a, "A-array-chain")
  assert_marker("Array chain realm B", result_b, "B-array-chain")
}

///|
test "Array proto walk via computed-property on Object-with-Array-prototype dispatches per realm" {
  // Pins property.mbt:1115 (get_computed_property_impl Array branch
  // fall-through to Array.prototype). Same chain shape as the named-
  // property test but enters through computed access (obj[key]).
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  install_marker(
    realm_a.realm_state.get_array_proto(),
    "__array_computed_marker__",
    "A-array-computed",
  )
  install_marker(
    realm_b.realm_state.get_array_proto(),
    "__array_computed_marker__",
    "B-array-computed",
  )
  let arr_a : Value = @runtime.make_array([])
  let arr_b : Value = @runtime.make_array([])
  let obj_a : Value = @runtime.make_object({}, arr_a, None, "Object", {}, true)
  let obj_b : Value = @runtime.make_object({}, arr_b, None, "Object", {}, true)
  let result_a = realm_a.get_computed_property(
    obj_a,
    String_("__array_computed_marker__"),
    @token.Loc::default(),
  )
  let result_b = realm_b.get_computed_property(
    obj_b,
    String_("__array_computed_marker__"),
    @token.Loc::default(),
  )
  assert_marker("Array computed realm A", result_a, "A-array-computed")
  assert_marker("Array computed realm B", result_b, "B-array-computed")
}

///|
test "Array Symbol-keyed proto walk dispatches per realm" {
  // Pins property.mbt:901 (get_computed_property_impl Symbol-key Array
  // branch). Installs a Symbol-keyed marker on each realm's Array.prototype
  // and reads it via arr[Symbol].
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  let sym_a = realm_a.realm_state.symbols.new_symbol(
    Some("array-symbol-marker"),
  )
  let sym_b = realm_b.realm_state.symbols.new_symbol(
    Some("array-symbol-marker"),
  )
  install_symbol_marker(
    realm_a.realm_state.get_array_proto(),
    sym_a.id,
    "A-array-symbol",
  )
  install_symbol_marker(
    realm_b.realm_state.get_array_proto(),
    sym_b.id,
    "B-array-symbol",
  )
  let arr_a : Value = @runtime.make_array([Number(1.0)])
  let arr_b : Value = @runtime.make_array([Number(1.0)])
  let result_a = realm_a.get_computed_property(
    arr_a,
    Symbol(sym_a),
    @token.Loc::default(),
  )
  let result_b = realm_b.get_computed_property(
    arr_b,
    Symbol(sym_b),
    @token.Loc::default(),
  )
  assert_marker("Array symbol realm A", result_a, "A-array-symbol")
  assert_marker("Array symbol realm B", result_b, "B-array-symbol")
}

///|
test "Symbol lookup_builtin_proto dispatches per realm" {
  let realm_a = make_realm_interp()
  let realm_b = make_realm_interp()
  install_marker(
    realm_a.realm_state.get_symbol_proto(),
    "__lookup_proto_marker__",
    "A-symbol",
  )
  install_marker(
    realm_b.realm_state.get_symbol_proto(),
    "__lookup_proto_marker__",
    "B-symbol",
  )
  let sym_a : Value = Symbol(
    realm_a.realm_state.symbols.new_symbol(Some("test")),
  )
  let sym_b : Value = Symbol(
    realm_b.realm_state.symbols.new_symbol(Some("test")),
  )
  let result_a = realm_a.get_property(
    sym_a,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  let result_b = realm_b.get_property(
    sym_b,
    "__lookup_proto_marker__",
    @token.Loc::default(),
  )
  assert_marker("Symbol realm A", result_a, "A-symbol")
  assert_marker("Symbol realm B", result_b, "B-symbol")
}

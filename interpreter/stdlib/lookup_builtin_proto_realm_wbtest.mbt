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

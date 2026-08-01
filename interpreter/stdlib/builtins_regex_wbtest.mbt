///| White-box tests for the engine-private RegExp matcher capability.

///|
test "RegExp construction retains its private matcher capability" {
  let value = make_regexp_object("(a)", "gu")
  match value {
    Object(data) =>
      match data.bag.symbol_properties.get(-129) {
        Some(Object(_)) => ()
        Some(_) => fail("RegExp matcher slot must hold a callable object")
        None =>
          fail("RegExp construction must install the private matcher slot")
      }
    _ => fail("RegExp construction must return an object")
  }
}

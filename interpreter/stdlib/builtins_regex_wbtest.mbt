///| White-box tests for the engine-private RegExp matcher capability.

///|
test "RegExp construction retains its private matcher capability" {
  let value = make_regexp_object("(a)", "gu")
  match value {
    Object(data) =>
      match data.bag.symbol_properties.get(REGEXP_MATCHER_SYMBOL_ID) {
        Some(Object(_)) => ()
        Some(_) => fail("RegExp matcher slot must hold a callable object")
        None =>
          fail("RegExp construction must install the private matcher slot")
      }
    _ => fail("RegExp construction must return an object")
  }
}

///|
test "public regex_search keeps its historical scalar domain" {
  let result = regex_search(".", "g", "😀x", start_pos=1) catch { _ => None }
  match result {
    Some(m) => {
      assert_eq(m.start, 1)
      assert_eq(m.end_, 2)
      match make_regex_match_array(m, "😀x") {
        Array(data) =>
          match @runtime.get_array_named_prop(data, "index") {
            Some(Value::Number(index)) => assert_eq(index, 1.0)
            _ => fail("expected public match-array index")
          }
        _ => fail("expected public match array")
      }
    }
    None => fail("expected scalar-domain match")
  }
  let captured = regex_search("(.)", "g", "😀x", start_pos=1) catch {
    _ => None
  }
  match captured {
    Some(m) =>
      match m.captures[0] {
        Some(value) => assert_eq(value == "x", true)
        None => fail("expected scalar-domain capture")
      }
    None => fail("expected scalar-domain capture match")
  }
}

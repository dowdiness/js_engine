///|
// The private lookup result must retain the distinction between an observable
// property whose value is undefined and a genuinely absent property.
test "issue 940 String lookup distinguishes Found undefined from Absent" {
  let interp = Interpreter::new()
  let string_proto = make_object(Map([]), Null, None, "String", Map([]), true)
  interp.realm_state.string_prototype.val = Some(string_proto)
  match string_proto {
    Object(data) => data.bag.properties["toUpperCase"] = Undefined
    _ => fail("String.prototype must be an ordinary object")
  }
  let boxed = box_primitive_call_this(String_("hello"), interp.realm_state)
  match
    interp.get_property_key_with_receiver_result(
      boxed,
      String_("toUpperCase"),
      String_("hello"),
      @token.Loc::default(),
    ) {
    Found(Undefined) => ()
    Found(_) => fail("undefined property was not preserved as Found")
    Absent => fail("observable undefined property was treated as absent")
  }
  match
    interp.get_property_key_with_receiver_result(
      boxed,
      String_("issue940Absent"),
      String_("hello"),
      @token.Loc::default(),
    ) {
    Absent => ()
    Found(_) => fail("missing property was not classified as Absent")
  }
}

///|
test "issue 940 absent String property retains guarded builtin fallback" {
  let fallback_calls : Ref[Int] = { val: 0 }
  let hooks = {
    ..default_stdlib_hooks(),
    get_string_method: fn(s, prop, realm_state, _annex_b) {
      guard s == "hello" && prop == "toUpperCase" else { return Undefined }
      make_method_func(name="toUpperCase", realm_state=Some(realm_state), fn(
        this_value,
        _args,
      ) raise {
        fallback_calls.val += 1
        match this_value {
          String_(value) => assert_eq(value, "hello")
          _ => fail("fallback builtin lost the primitive receiver")
        }
        String_("HELLO")
      })
    },
  }
  let interp = Interpreter::new(stdlib_hooks=hooks)
  let empty_string_proto = make_object(
    Map([]),
    Null,
    None,
    "String",
    Map([]),
    true,
  )
  interp.realm_state.string_prototype.val = Some(empty_string_proto)
  let boxed = box_primitive_call_this(String_("hello"), interp.realm_state)
  match
    interp.get_property_key_with_receiver_result(
      boxed,
      String_("toUpperCase"),
      String_("hello"),
      @token.Loc::default(),
    ) {
    Absent => ()
    Found(_) => fail("empty String prototype lookup was not absent")
  }
  let builtin = interp.get_string_property(
    String_("hello"),
    "hello",
    "toUpperCase",
    @token.Loc::default(),
  )
  let result = interp.call_value(
    builtin,
    String_("hello"),
    [],
    @token.Loc::default(),
  )
  assert_eq(result.to_string(), "HELLO")
  assert_eq(fallback_calls.val, 1)
}

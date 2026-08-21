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

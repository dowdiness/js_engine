///|
fn locale_compare_observation_probe(observations : Ref[Int]) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-975-locale-compare-observer", fn(_args) {
        observations.val += 1
        Undefined
      }),
    ),
    "Function",
    Map([]),
    true,
  )
}

///|
fn call_locale_compare_with_observation_probe(
  value : String,
  other : String,
  observations : Ref[Int],
) -> Value raise Error {
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    locale_compare_observation_probe(observations),
    VarBinding,
  )
  let locale_compare = get_string_method(
    value,
    "localeCompare",
    interp.realm_state,
  )
  interp.call_value(
    locale_compare,
    String_(value),
    [String_(other)],
    @token.Loc::default(),
  )
}

///|
test "String.localeCompare observes before opaque comparison" {
  let observations : Ref[Int] = { val: 0 }
  match call_locale_compare_with_observation_probe("a", "b", observations) {
    Number(value) => inspect(value, content="-1")
    _ => fail("localeCompare must return a number")
  }
  inspect(observations.val, content="1")
}

///|
test "String.normalize remains the current bounded identity stub" {
  let observations : Ref[Int] = { val: 0 }
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    locale_compare_observation_probe(observations),
    VarBinding,
  )
  let normalize = get_string_method("abc", "normalize", interp.realm_state)
  match
    interp.call_value(normalize, String_("abc"), [], @token.Loc::default()) {
    String_(value) => inspect(value, content="abc")
    _ => fail("normalize stub must return its input string")
  }
  inspect(observations.val, content="0")
}

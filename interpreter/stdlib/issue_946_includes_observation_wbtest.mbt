///|
fn includes_observation_probe(observations : Ref[Int]) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-946-includes-observer", fn(_args) {
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
fn call_includes_with_observation_probe(
  value : String,
  search : String,
  observations : Ref[Int],
) -> Value raise Error {
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    includes_observation_probe(observations),
    VarBinding,
  )
  let includes = get_string_method(value, "includes", interp.realm_state)
  interp.call_value(
    includes,
    String_(value),
    [String_(search)],
    @token.Loc::default(),
  )
}

///|
test "String.includes observes each code-unit comparison" {
  let observations : Ref[Int] = { val: 0 }
  match call_includes_with_observation_probe("abc", "bc", observations) {
    Bool(value) => inspect(value, content="true")
    _ => fail("includes must return a boolean")
  }
  inspect(observations.val, content="3")
}

///|
test "String.includes empty search observes no comparisons" {
  let observations : Ref[Int] = { val: 0 }
  match call_includes_with_observation_probe("abc", "", observations) {
    Bool(value) => inspect(value, content="true")
    _ => fail("includes must return a boolean")
  }
  inspect(observations.val, content="0")
}

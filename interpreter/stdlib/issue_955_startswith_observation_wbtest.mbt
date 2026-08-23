///|
fn starts_with_observation_probe(observations : Ref[Int]) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-955-starts-with-observer", fn(_args) {
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
fn call_starts_with_with_observation_probe(
  value : String,
  search : String,
  observations : Ref[Int],
) -> Value raise Error {
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    starts_with_observation_probe(observations),
    VarBinding,
  )
  let starts_with = get_string_method(value, "startsWith", interp.realm_state)
  interp.call_value(
    starts_with,
    String_(value),
    [String_(search)],
    @token.Loc::default(),
  )
}

///|
test "String.startsWith observes each actual comparison" {
  let observations : Ref[Int] = { val: 0 }
  match call_starts_with_with_observation_probe("abc", "ab", observations) {
    Bool(value) => inspect(value, content="true")
    _ => fail("startsWith must return a boolean")
  }
  inspect(observations.val, content="2")
}

///|
test "String.startsWith observes the first mismatch before returning" {
  let observations : Ref[Int] = { val: 0 }
  match call_starts_with_with_observation_probe("abc", "z", observations) {
    Bool(value) => inspect(value, content="false")
    _ => fail("startsWith must return a boolean")
  }
  inspect(observations.val, content="1")
}

///|
test "String.startsWith empty search observes no comparisons" {
  let observations : Ref[Int] = { val: 0 }
  match call_starts_with_with_observation_probe("abc", "", observations) {
    Bool(value) => inspect(value, content="true")
    _ => fail("startsWith must return a boolean")
  }
  inspect(observations.val, content="0")
}

///|
test "String.startsWith impossible search observes no comparisons" {
  let observations : Ref[Int] = { val: 0 }
  match call_starts_with_with_observation_probe("abc", "abcd", observations) {
    Bool(value) => inspect(value, content="false")
    _ => fail("startsWith must return a boolean")
  }
  inspect(observations.val, content="0")
}

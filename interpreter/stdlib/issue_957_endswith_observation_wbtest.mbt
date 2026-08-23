///|
fn ends_with_observation_probe(observations : Ref[Int]) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-957-ends-with-observer", fn(_args) {
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
fn call_ends_with_with_observation_probe(
  value : String,
  search : String,
  observations : Ref[Int],
) -> Value raise Error {
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    ends_with_observation_probe(observations),
    VarBinding,
  )
  let ends_with = get_string_method(value, "endsWith", interp.realm_state)
  interp.call_value(
    ends_with,
    String_(value),
    [String_(search)],
    @token.Loc::default(),
  )
}

///|
fn call_ends_with_with_position_and_observation_probe(
  value : String,
  search : String,
  end_position : Value,
  observations : Ref[Int],
) -> Value raise Error {
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    ends_with_observation_probe(observations),
    VarBinding,
  )
  let ends_with = get_string_method(value, "endsWith", interp.realm_state)
  interp.call_value(
    ends_with,
    String_(value),
    [String_(search), end_position],
    @token.Loc::default(),
  )
}

///|
test "String.endsWith observes each actual comparison" {
  let observations : Ref[Int] = { val: 0 }
  match call_ends_with_with_observation_probe("abc", "bc", observations) {
    Bool(value) => inspect(value, content="true")
    _ => fail("endsWith must return a boolean")
  }
  inspect(observations.val, content="2")
}

///|
test "String.endsWith observes the first mismatch before returning" {
  let observations : Ref[Int] = { val: 0 }
  match call_ends_with_with_observation_probe("abc", "zc", observations) {
    Bool(value) => inspect(value, content="false")
    _ => fail("endsWith must return a boolean")
  }
  inspect(observations.val, content="1")
}

///|
test "String.endsWith empty search observes no comparisons" {
  let observations : Ref[Int] = { val: 0 }
  match call_ends_with_with_observation_probe("abc", "", observations) {
    Bool(value) => inspect(value, content="true")
    _ => fail("endsWith must return a boolean")
  }
  inspect(observations.val, content="0")
}

///|
test "String.endsWith impossible search observes no comparisons" {
  let observations : Ref[Int] = { val: 0 }
  match call_ends_with_with_observation_probe("abc", "abcd", observations) {
    Bool(value) => inspect(value, content="false")
    _ => fail("endsWith must return a boolean")
  }
  inspect(observations.val, content="0")
}

///|
test "String.endsWith compares UTF-16 code units" {
  let observations : Ref[Int] = { val: 0 }
  match call_ends_with_with_observation_probe("😀x", "😀", observations) {
    Bool(value) => inspect(value, content="false")
    _ => fail("endsWith must return a boolean")
  }
  inspect(observations.val, content="1")
  let observations : Ref[Int] = { val: 0 }
  match
    call_ends_with_with_position_and_observation_probe(
      "😀x",
      "😀",
      Number(2.0),
      observations,
    ) {
    Bool(value) => inspect(value, content="true")
    _ => fail("endsWith must return a boolean")
  }
  inspect(observations.val, content="2")
}

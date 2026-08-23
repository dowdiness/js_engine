///|
fn last_index_of_observation_probe(observations : Ref[Int]) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-950-last-index-of-observer", fn(_args) {
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
fn call_last_index_of_with_observation_probe(
  value : String,
  search : String,
  observations : Ref[Int],
) -> Value raise Error {
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    last_index_of_observation_probe(observations),
    VarBinding,
  )
  let last_index_of = get_string_method(
    value,
    "lastIndexOf",
    interp.realm_state,
  )
  interp.call_value(
    last_index_of,
    String_(value),
    [String_(search)],
    @token.Loc::default(),
  )
}

///|
test "String.lastIndexOf observes each reverse code-unit comparison" {
  let observations : Ref[Int] = { val: 0 }
  match call_last_index_of_with_observation_probe("abc", "z", observations) {
    Number(value) => inspect(value, content="-1")
    _ => fail("lastIndexOf must return a number")
  }
  inspect(observations.val, content="3")
}

///|
test "String.lastIndexOf empty search observes no comparisons" {
  let observations : Ref[Int] = { val: 0 }
  match call_last_index_of_with_observation_probe("abc", "", observations) {
    Number(value) => inspect(value, content="3")
    _ => fail("lastIndexOf must return a number")
  }
  inspect(observations.val, content="0")
}

///|
test "String.lastIndexOf impossible search observes no comparisons" {
  let observations : Ref[Int] = { val: 0 }
  match call_last_index_of_with_observation_probe("abc", "abcd", observations) {
    Number(value) => inspect(value, content="-1")
    _ => fail("lastIndexOf must return a number")
  }
  inspect(observations.val, content="0")
}

///|
test "String.lastIndexOf reports UTF-16 code-unit positions" {
  let observations : Ref[Int] = { val: 0 }
  match call_last_index_of_with_observation_probe("😀x", "x", observations) {
    Number(value) => inspect(value, content="2")
    _ => fail("lastIndexOf must return a number")
  }
  inspect(observations.val, content="1")
}

///|
fn repeat_observation_probe(observations : Ref[Int]) -> Value {
  @runtime.make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("issue-944-repeat-observer", fn(_args) {
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
fn call_repeat_with_observation_probe(
  repetitions : Int,
  observations : Ref[Int],
) -> Value raise Error {
  let interp = @runtime.Interpreter::new()
  interp.global.def(
    "[[ExecutionControl]]",
    repeat_observation_probe(observations),
    VarBinding,
  )
  let repeat = get_string_method("x", "repeat", interp.realm_state)
  interp.call_value(
    repeat,
    String_("x"),
    [Number(repetitions.to_double())],
    @token.Loc::default(),
  )
}

///|
test "String.repeat observes exactly one step per logical repetition" {
  let observations : Ref[Int] = { val: 0 }
  match call_repeat_with_observation_probe(3, observations) {
    String_(value) => inspect(value, content="xxx")
    _ => fail("repeat(3) must return the repeated string")
  }
  inspect(observations.val, content="3")
}

///|
test "String.repeat zero count observes no repetition step" {
  let observations : Ref[Int] = { val: 0 }
  match call_repeat_with_observation_probe(0, observations) {
    String_(value) => inspect(value, content="")
    _ => fail("repeat(0) must return the empty string")
  }
  inspect(observations.val, content="0")
}

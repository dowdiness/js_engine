///|
test "environment slot owns TDZ, initialization, assignment, and identity" {
  let env = Environment::new()
  env.def_tdz("x", LetBinding)
  let slot = match env.resolve_slot("x") {
    Some(slot) => slot
    None => fail("expected a slot for x")
  }
  let tdz_error : Error? = try {
    let _ = slot.read()
    None
  } catch {
    error => Some(error)
  }
  match tdz_error {
    Some(error) =>
      inspect(
        error.to_string(),
        content="ReferenceError: Cannot access 'x' before initialization",
      )
    None => fail("reading a TDZ slot must throw")
  }
  slot.initialize(Number(1.0))
  let sibling = match env.resolve_slot("x") {
    Some(slot) => slot
    None => fail("expected a second slot for x")
  }
  inspect(slot.read(), content="1")
  slot.assign(Number(2.0))
  inspect(sibling.read(), content="2")
}

///|
test "environment slot owns const rejection" {
  let env = Environment::new()
  env.def_tdz("constant", ConstBinding)
  let slot = match env.resolve_slot("constant") {
    Some(slot) => slot
    None => fail("expected a slot for constant")
  }
  slot.initialize(Number(1.0))
  let const_error : Error? = try {
    slot.assign(Number(2.0))
    None
  } catch {
    error => Some(error)
  }
  match const_error {
    Some(error) =>
      inspect(
        error.to_string(),
        content="TypeError: Assignment to constant variable 'constant'",
      )
    None => fail("assigning a const slot must throw")
  }
}

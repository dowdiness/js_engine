///|
test "class static fields and blocks execute in source order" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "var order = ''; class C { " +
      "static first = order += 'field1'; " +
      "static { order += 'block1'; } " +
      "static second = order += 'field2'; " +
      "static { order += 'block2'; } } order;",
    ).stmts,
  )
  assert_true(strict_equal(result, String_("field1block1field2block2")))
}

///|
test "class computed static names finish before initialization" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "var events = ''; " +
      "function key(name) { events += name; return name; } " +
      "class C { " +
      "static [key('a')] = events += 'field1'; " +
      "static { events += 'block1'; } " +
      "static [key('b')] = events += 'field2'; } events;",
    ).stmts,
  )
  assert_true(strict_equal(result, String_("abfield1block1field2")))
}

///|
test "throwing static block stops later class elements" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "var events = ''; " +
      "try { class C { " +
      "static first = events += 'field1'; " +
      "static { events += 'block1'; throw 'stop'; } " +
      "static second = events += 'field2'; " +
      "static { events += 'block2'; } } } " +
      "catch (error) { events += ':caught'; } events;",
    ).stmts,
  )
  assert_true(strict_equal(result, String_("field1block1:caught")))
}

///|
test "throwing static field stops later class elements" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "var events = ''; " +
      "function fail() { events += 'field2'; throw 'stop'; } " +
      "try { class C { " +
      "static first = events += 'field1'; " +
      "static { events += 'block1'; } " +
      "static second = fail(); " +
      "static { events += 'block2'; } } } " +
      "catch (error) { events += ':caught'; } events;",
    ).stmts,
  )
  assert_true(strict_equal(result, String_("field1block1field2:caught")))
}

///|
test "static blocks observe and mutate fields for later initializers" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "var seen = ''; class C { " +
      "static value = 1; " +
      "static { seen += this.value; this.value = 2; } " +
      "static result = this.value + 3; } " +
      "seen + ':' + C.value + ':' + C.result;",
    ).stmts,
  )
  assert_true(strict_equal(result, String_("1:2:5")))
}

///|
test "class static fields only retain initialization" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "class C { static first = 1; static second = 2; } C.first + C.second;",
    ).stmts,
  )
  assert_true(strict_equal(result, Number(3)))
}

///|
test "class static blocks only retain source order" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "class C { static { this.first = 1; } static { this.second = this.first + 1; } } C.second;",
    ).stmts,
  )
  assert_true(strict_equal(result, Number(2)))
}

///|
test "empty and instance-field classes retain construction behavior" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "class Empty {} class WithInstance { value = 4; } " +
      "Empty.name + ':' + new WithInstance().value;",
    ).stmts,
  )
  assert_true(strict_equal(result, String_("Empty:4")))
}

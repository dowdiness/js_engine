///|
test "has_use_strict: literal use strict with no escape" {
  let prog = @parser.parse("\"use strict\"; 1;")
  inspect(@static_semantics.has_use_strict(prog.stmts), content="true")
}

///|
test "has_use_strict: directive after non-string statement is not in prologue" {
  let prog = @parser.parse("1; \"use strict\";")
  inspect(@static_semantics.has_use_strict(prog.stmts), content="false")
}

///|
test "has_use_strict: empty body" {
  let prog = @parser.parse("")
  inspect(@static_semantics.has_use_strict(prog.stmts), content="false")
}

///|
test "has_use_strict: other string directive followed by use strict" {
  let prog = @parser.parse("\"prologue\"; \"use strict\"; 1;")
  inspect(@static_semantics.has_use_strict(prog.stmts), content="true")
}

///|
test "body_is_strict: inherited strict, no directive" {
  let prog = @parser.parse("1;")
  inspect(@static_semantics.body_is_strict(prog.stmts, true), content="true")
}

///|
test "body_is_strict: not inherited, has directive" {
  let prog = @parser.parse("\"use strict\"; 1;")
  inspect(@static_semantics.body_is_strict(prog.stmts, false), content="true")
}

///|
test "body_is_strict: neither inherited nor directive" {
  let prog = @parser.parse("1;")
  inspect(@static_semantics.body_is_strict(prog.stmts, false), content="false")
}

///|
test "collect_var_declared_names: var declaration" {
  let prog = @parser.parse("var x;")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("x"), content="true")
  inspect(names.length(), content="1")
}

///|
test "collect_var_declared_names: let and const are not collected" {
  let prog = @parser.parse("let x; const y = 1;")
  inspect(collect_var_declared_names(prog.stmts).length(), content="0")
}

///|
test "collect_var_declared_names: function decl at top level" {
  let prog = @parser.parse("function f() {}")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("f"), content="true")
}

///|
test "collect_var_declared_names: function decl excluded when include_funcs=false" {
  let prog = @parser.parse("function f() {}")
  let names = collect_var_declared_names(prog.stmts, include_funcs=false)
  inspect(names.length(), content="0")
}

///|
test "collect_var_declared_names: var in for-of loop" {
  let prog = @parser.parse("for (var x of arr) {}")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("x"), content="true")
}

///|
test "collect_var_declared_names: var inside try-catch" {
  let prog = @parser.parse("try { var x; } catch (e) { var y; }")
  let names = collect_var_declared_names(prog.stmts)
  inspect(names.contains("x"), content="true")
  inspect(names.contains("y"), content="true")
}

///|
test "collect_var_declared_names: function decl inside if is block-scoped (§B.3.4)" {
  let prog = @parser.parse("if (true) function f() {}")
  let names = collect_var_declared_names(prog.stmts)
  // TODO(human): inspect the result — should f be in names?
  // §B.3.4 says if (...) function f() {} parses as if (...) { function f() {} },
  // making f a lexical binding of the implicit block, not a var-declared name.
  ignore(names)
}

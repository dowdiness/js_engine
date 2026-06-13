///|
test "collect_var_declared_names: var declaration" {
  let prog = @parser.parse("var x;")
  json_inspect(collect_var_declared_names(prog.stmts), content=["x"])
}

///|
test "collect_var_declared_names: let and const are not collected" {
  let prog = @parser.parse("let x; const y = 1;")
  json_inspect(collect_var_declared_names(prog.stmts), content=[])
}

///|
test "collect_var_declared_names: function decl at top level" {
  let prog = @parser.parse("function f() {}")
  let names = collect_var_declared_names(prog.stmts)
  json_inspect(names, content=["f"])
}

///|
test "collect_var_declared_names: function decl excluded when include_funcs=false" {
  let prog = @parser.parse("function f() {}")
  json_inspect(
    collect_var_declared_names(prog.stmts, include_funcs=false),
    content=[],
  )
}

///|
test "collect_var_declared_names: var in for-of loop" {
  let prog = @parser.parse("for (var x of arr) {}")
  let names = collect_var_declared_names(prog.stmts)
  json_inspect(names, content=["x"])
}

///|
test "collect_var_declared_names: var in for-in loop" {
  let prog = @parser.parse("for (var k in obj) {}")
  let names = collect_var_declared_names(prog.stmts)
  json_inspect(names, content=["k"])
}

///|
test "collect_var_declared_names: non-var for-in loop not collected" {
  let prog = @parser.parse("for (let k in obj) {}")
  json_inspect(collect_var_declared_names(prog.stmts), content=[])
}

///|
test "collect_var_declared_names: var inside try-catch" {
  let prog = @parser.parse("try { var x; } catch (e) { var y; }")
  let names = collect_var_declared_names(prog.stmts)
  json_inspect(names, content=["x", "y"])
}

///|
test "collect_var_declared_names: function decl inside if is block-scoped (§B.3.4)" {
  let prog = @parser.parse("if (true) function f() {}")
  let names = collect_var_declared_names(prog.stmts)
  // §B.3.4: if (...) function f() {} treats f as a lexical binding of the
  // implicit block around the then-branch, not a var-declared name. The
  // IfStmt arm in collect_var_declared_names forces in_block=true, which
  // makes count_funcs false regardless of include_funcs.
  json_inspect(names, content=[])
}

///|
test "collect_var_declared_names: var inside while body" {
  let prog = @parser.parse("while (true) { var i; }")
  json_inspect(collect_var_declared_names(prog.stmts), content=["i"])
}

///|
test "collect_var_declared_names: function decl inside while is block-scoped" {
  let prog = @parser.parse("while (true) { function f() {} }")
  // WhileStmt forces in_block=true so nested FuncDecls are not var-declared.
  json_inspect(collect_var_declared_names(prog.stmts), content=[])
}

///|
test "collect_var_declared_names: var inside switch case" {
  let prog = @parser.parse("switch (x) { case 1: var y; break; }")
  json_inspect(collect_var_declared_names(prog.stmts), content=["y"])
}

///|
test "collect_var_declared_names: top-level labeled function decl is var-declared (§B.3.2)" {
  let prog = @parser.parse("label: function f() {}")
  let names = collect_var_declared_names(prog.stmts)
  // LabeledStmt mirrors the caller's in_block so a top-level labeled
  // FunctionDeclaration still participates in TopLevelVarDeclaredNames.
  json_inspect(names, content=["f"])
}

///|
test "collect_var_declared_names: var inside do-while" {
  let prog = @parser.parse("do { var i; } while (true);")
  json_inspect(collect_var_declared_names(prog.stmts), content=["i"])
}

///|
test "collect_var_declared_names: function body vars not leaked" {
  let prog = @parser.parse("function f() { var inner; } var outer;")
  // Variables declared inside a function body are scoped to that function.
  json_inspect(collect_var_declared_names(prog.stmts), content=["f", "outer"])
}

///|
test "collect_var_declared_names: multiple var declarations" {
  let prog = @parser.parse("var a; var b; var c;")
  json_inspect(collect_var_declared_names(prog.stmts), content=["a", "b", "c"])
}

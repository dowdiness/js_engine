///|
test "parse variable declaration" {
  let prog = @parser.parse("let x = 42;")
  inspect(
    prog.stmts[0],
    content="VarDecl(LetKind, \"x\", Some(NumberLit(42, {line: 1, col: 9, offset: 8})), {line: 1, col: 1, offset: 0})",
  )
}

///|
test "parse binary precedence" {
  let prog = @parser.parse("1 + 2 * 3")
  inspect(
    prog.stmts[0],
    content="ExprStmt(Binary(Add, NumberLit(1, {line: 1, col: 1, offset: 0}), Binary(Mul, NumberLit(2, {line: 1, col: 5, offset: 4}), NumberLit(3, {line: 1, col: 9, offset: 8}), {line: 1, col: 7, offset: 6}), {line: 1, col: 3, offset: 2}), {line: 1, col: 1, offset: 0})",
  )
}

///|
test "parse function declaration" {
  let prog = @parser.parse("function add(a, b) { return a + b; }")
  inspect(prog.stmts.length(), content="1")
  match prog.stmts[0] {
    FuncDecl(name, params, _, _) => {
      inspect(name, content="add")
      inspect(params, content="[\"a\", \"b\"]")
    }
    _ => fail("Expected FuncDecl")
  }
}

///|
test "parse if/else" {
  let prog = @parser.parse("if (x > 0) { 1; } else { 2; }")
  match prog.stmts[0] {
    IfStmt(_, _, else_branch, _) =>
      inspect(not(else_branch is None), content="true")
    _ => fail("Expected IfStmt")
  }
}

///|
test "parse for loop" {
  let prog = @parser.parse("for (let i = 0; i < 10; i = i + 1) { }")
  match prog.stmts[0] {
    ForStmt(init, cond, update, _, _) => {
      inspect(not(init is None), content="true")
      inspect(not(cond is None), content="true")
      inspect(not(update is None), content="true")
    }
    _ => fail("Expected ForStmt")
  }
}

///|
test "parse call expression" {
  let prog = @parser.parse("foo(1, 2)")
  match prog.stmts[0] {
    ExprStmt(Call(_, args, _), _) => inspect(args.length(), content="2")
    _ => fail("Expected Call")
  }
}

///|
test "parse member expression" {
  let prog = @parser.parse("console.log(x)")
  match prog.stmts[0] {
    ExprStmt(Call(Member(Ident(obj, _), prop, _), _, _), _) => {
      inspect(obj, content="console")
      inspect(prop, content="log")
    }
    _ => fail("Expected member call")
  }
}

///|
test "parse ternary" {
  let prog = @parser.parse("x ? 1 : 2")
  match prog.stmts[0] {
    ExprStmt(Ternary(_, _, _, _), _) => ()
    _ => fail("Expected Ternary")
  }
}

///|
test "parse function expression" {
  let prog = @parser.parse("let f = function(x) { return x; }")
  match prog.stmts[0] {
    VarDecl(_, _, Some(FuncExpr(_, params, _, _)), _) =>
      inspect(params, content="[\"x\"]")
    _ => fail("Expected FuncExpr in VarDecl")
  }
}

///|
test "parse unary minus" {
  let prog = @parser.parse("-5")
  match prog.stmts[0] {
    ExprStmt(Unary(Neg, _, _), _) => ()
    _ => fail("Expected unary neg")
  }
}

///|
test "parse typeof" {
  let prog = @parser.parse("typeof x")
  match prog.stmts[0] {
    ExprStmt(Unary(Typeof, _, _), _) => ()
    _ => fail("Expected typeof")
  }
}

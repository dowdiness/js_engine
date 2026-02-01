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

///|
test "parse switch statement" {
  let prog = @parser.parse(
    "switch (x) { case 1: break; case 2: break; default: break; }",
  )
  match prog.stmts[0] {
    SwitchStmt(_, cases, _) => inspect(cases.length(), content="3")
    _ => fail("Expected SwitchStmt")
  }
}

///|
test "parse do-while" {
  let prog = @parser.parse("do { x = x + 1; } while (x < 10);")
  match prog.stmts[0] {
    DoWhileStmt(_, _, _) => ()
    _ => fail("Expected DoWhileStmt")
  }
}

///|
test "parse for-in with var" {
  let prog = @parser.parse("for (let k in obj) { }")
  match prog.stmts[0] {
    ForInStmt(Some(LetKind), name, _, _, _) => inspect(name, content="k")
    _ => fail("Expected ForInStmt with let")
  }
}

///|
test "parse for-in bare" {
  let prog = @parser.parse("for (k in obj) { }")
  match prog.stmts[0] {
    ForInStmt(None, name, _, _, _) => inspect(name, content="k")
    _ => fail("Expected ForInStmt bare")
  }
}

///|
test "parse labeled statement" {
  let prog = @parser.parse("outer: for (let i = 0; i < 3; i = i + 1) { }")
  match prog.stmts[0] {
    LabeledStmt(label, _, _) => inspect(label, content="outer")
    _ => fail("Expected LabeledStmt")
  }
}

///|
test "parse object literal" {
  let prog = @parser.parse("let o = { a: 1, b: 2 };")
  match prog.stmts[0] {
    VarDecl(_, _, Some(ObjectLit(props, _)), _) =>
      inspect(props.length(), content="2")
    _ => fail("Expected ObjectLit")
  }
}

///|
test "parse array literal" {
  let prog = @parser.parse("let a = [1, 2, 3];")
  match prog.stmts[0] {
    VarDecl(_, _, Some(ArrayLit(elems, _)), _) =>
      inspect(elems.length(), content="3")
    _ => fail("Expected ArrayLit")
  }
}

///|
test "parse computed member" {
  let prog = @parser.parse("a[0]")
  match prog.stmts[0] {
    ExprStmt(ComputedMember(Ident(name, _), _, _), _) =>
      inspect(name, content="a")
    _ => fail("Expected ComputedMember")
  }
}

///|
test "parse new expression" {
  let prog = @parser.parse("new Foo(1, 2)")
  match prog.stmts[0] {
    ExprStmt(NewExpr(Ident(name, _), args, _), _) => {
      inspect(name, content="Foo")
      inspect(args.length(), content="2")
    }
    _ => fail("Expected NewExpr")
  }
}

///|
test "parse this expression" {
  let prog = @parser.parse("this.x")
  match prog.stmts[0] {
    ExprStmt(Member(ThisExpr(_), prop, _), _) => inspect(prop, content="x")
    _ => fail("Expected this.x")
  }
}

///|
test "parse prefix increment" {
  let prog = @parser.parse("++x")
  match prog.stmts[0] {
    ExprStmt(UpdateExpr(Increment, _, true, _), _) => ()
    _ => fail("Expected prefix increment")
  }
}

///|
test "parse postfix decrement" {
  let prog = @parser.parse("x--")
  match prog.stmts[0] {
    ExprStmt(UpdateExpr(Decrement, _, false, _), _) => ()
    _ => fail("Expected postfix decrement")
  }
}

///|
test "parse compound assignment" {
  let prog = @parser.parse("x += 5")
  match prog.stmts[0] {
    ExprStmt(CompoundAssign(AddAssign, _, _, _), _) => ()
    _ => fail("Expected CompoundAssign")
  }
}

///|
test "parse bitwise operators" {
  let prog = @parser.parse("a & b | c ^ d")
  match prog.stmts[0] {
    ExprStmt(Binary(BitOr, _, _, _), _) => ()
    _ => fail("Expected BitOr at top level")
  }
}

///|
test "parse shift operators" {
  let prog = @parser.parse("a << 2")
  match prog.stmts[0] {
    ExprStmt(Binary(LShift, _, _, _), _) => ()
    _ => fail("Expected LShift")
  }
}

///|
test "parse comma expression" {
  let prog = @parser.parse("a = 1, b = 2")
  match prog.stmts[0] {
    ExprStmt(Comma(_, _, _), _) => ()
    _ => fail("Expected Comma")
  }
}

///|
test "parse void expression" {
  let prog = @parser.parse("void 0")
  match prog.stmts[0] {
    ExprStmt(Unary(Void, _, _), _) => ()
    _ => fail("Expected void")
  }
}

///|
test "parse delete expression" {
  let prog = @parser.parse("delete obj.prop")
  match prog.stmts[0] {
    ExprStmt(Unary(Delete, _, _), _) => ()
    _ => fail("Expected delete")
  }
}

///|
test "parse bitwise not" {
  let prog = @parser.parse("~x")
  match prog.stmts[0] {
    ExprStmt(Unary(BitNot, _, _), _) => ()
    _ => fail("Expected BitNot")
  }
}

///|
test "parse member assign" {
  let prog = @parser.parse("obj.x = 5")
  match prog.stmts[0] {
    ExprStmt(MemberAssign(_, prop, _, _), _) => inspect(prop, content="x")
    _ => fail("Expected MemberAssign")
  }
}

///|
test "parse computed assign" {
  let prog = @parser.parse("arr[0] = 5")
  match prog.stmts[0] {
    ExprStmt(ComputedAssign(_, _, _, _), _) => ()
    _ => fail("Expected ComputedAssign")
  }
}

///|
test "parse instanceof" {
  let prog = @parser.parse("x instanceof Foo")
  match prog.stmts[0] {
    ExprStmt(Binary(Instanceof, _, _, _), _) => ()
    _ => fail("Expected instanceof")
  }
}

///|
test "parse in operator" {
  let prog = @parser.parse("\"x\" in obj")
  match prog.stmts[0] {
    ExprStmt(Binary(In, _, _, _), _) => ()
    _ => fail("Expected in operator")
  }
}

///|
fn expect_lex_form(
  actual : @token.LexForm,
  expected : @token.LexForm,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      "expected lex_form " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
test "parse variable declaration" {
  let prog = @parser.parse("let x = 42;")
  inspect(
    prog.stmts[0],
    content=(
      #|VarDecl(
      #|  LetKind,
      #|  "x",
      #|  Some(NumberLit(42, LexNormal, { line: 1, col: 9, offset: 8 })),
      #|  { line: 1, col: 1, offset: 0 },
      #|)
    ),
  )
}

///|
test "parse binary precedence" {
  let prog = @parser.parse("1 + 2 * 3")
  inspect(
    prog.stmts[0],
    content=(
      #|ExprStmt(
      #|  Binary(
      #|    Add,
      #|    NumberLit(1, LexNormal, { line: 1, col: 1, offset: 0 }),
      #|    Binary(
      #|      Mul,
      #|      NumberLit(2, LexNormal, { line: 1, col: 5, offset: 4 }),
      #|      NumberLit(3, LexNormal, { line: 1, col: 9, offset: 8 }),
      #|      { line: 1, col: 7, offset: 6 },
      #|    ),
      #|    { line: 1, col: 3, offset: 2 },
      #|  ),
      #|  { line: 1, col: 1, offset: 0 },
      #|)
    ),
  )
}

///|
test "parse function declaration" {
  let prog = @parser.parse("function add(a, b) { return a + b; }")
  inspect(
    prog.stmts.length(),
    content=(
      #|1
    ),
  )
  match prog.stmts[0] {
    FuncDecl(name, params, _, _) => {
      inspect(
        name,
        content=(
          #|add
        ),
      )
      json_inspect(params, content=["a", "b"])
    }
    _ => fail("Expected FuncDecl")
  }
}

///|
test "parse if/else" {
  let prog = @parser.parse("if (x > 0) { 1; } else { 2; }")
  match prog.stmts[0] {
    IfStmt(_, _, else_branch, _) =>
      inspect(
        !(else_branch is None),
        content=(
          #|true
        ),
      )
    _ => fail("Expected IfStmt")
  }
}

///|
test "parse for loop" {
  let prog = @parser.parse("for (let i = 0; i < 10; i = i + 1) { }")
  match prog.stmts[0] {
    ForStmt(init, cond, update, _, _) => {
      inspect(
        !(init is None),
        content=(
          #|true
        ),
      )
      inspect(
        !(cond is None),
        content=(
          #|true
        ),
      )
      inspect(
        !(update is None),
        content=(
          #|true
        ),
      )
    }
    _ => fail("Expected ForStmt")
  }
}

///|
test "parse call expression" {
  let prog = @parser.parse("foo(1, 2)")
  match prog.stmts[0] {
    ExprStmt(Call(_, args, _), _) =>
      inspect(
        args.length(),
        content=(
          #|2
        ),
      )
    _ => fail("Expected Call")
  }
}

///|
test "parse member expression" {
  let prog = @parser.parse("console.log(x)")
  match prog.stmts[0] {
    ExprStmt(Call(Member(Ident(obj, _), prop, _), _, _), _) => {
      inspect(
        obj,
        content=(
          #|console
        ),
      )
      inspect(
        prop,
        content=(
          #|log
        ),
      )
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
      json_inspect(params, content=["x"])
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
    SwitchStmt(_, cases, _) =>
      inspect(
        cases.length(),
        content=(
          #|3
        ),
      )
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
    ForInStmt(Some(LetKind), name, _, _, _) =>
      inspect(
        name,
        content=(
          #|k
        ),
      )
    _ => fail("Expected ForInStmt with let")
  }
}

///|
test "parse for-in bare" {
  let prog = @parser.parse("for (k in obj) { }")
  match prog.stmts[0] {
    ForInStmt(None, name, _, _, _) =>
      inspect(
        name,
        content=(
          #|k
        ),
      )
    _ => fail("Expected ForInStmt bare")
  }
}

///|
test "parse labeled statement" {
  let prog = @parser.parse("outer: for (let i = 0; i < 3; i = i + 1) { }")
  match prog.stmts[0] {
    LabeledStmt(label, _, _) =>
      inspect(
        label,
        content=(
          #|outer
        ),
      )
    _ => fail("Expected LabeledStmt")
  }
}

///|
test "parse break label only on same line" {
  let prog = @parser.parse("while (true) { break\nfoo(); }")
  match prog.stmts[0] {
    WhileStmt(_, Block(body, _), _) => {
      inspect(
        body.length(),
        content=(
          #|2
        ),
      )
      match body[0] {
        BreakStmt(None, _) => ()
        _ => fail("Expected unlabeled break")
      }
      match body[1] {
        ExprStmt(Call(Ident(name, _), _, _), _) =>
          inspect(
            name,
            content=(
              #|foo
            ),
          )
        _ => fail("Expected foo() call")
      }
    }
    _ => fail("Expected WhileStmt with block")
  }
}

///|
test "parse continue label only on same line" {
  let prog = @parser.parse("while (true) { continue\nfoo(); }")
  match prog.stmts[0] {
    WhileStmt(_, Block(body, _), _) => {
      inspect(
        body.length(),
        content=(
          #|2
        ),
      )
      match body[0] {
        ContinueStmt(None, _) => ()
        _ => fail("Expected unlabeled continue")
      }
      match body[1] {
        ExprStmt(Call(Ident(name, _), _, _), _) =>
          inspect(
            name,
            content=(
              #|foo
            ),
          )
        _ => fail("Expected foo() call")
      }
    }
    _ => fail("Expected WhileStmt with block")
  }
}

///|
test "parse object literal" {
  let prog = @parser.parse("let o = { a: 1, b: 2 };")
  match prog.stmts[0] {
    VarDecl(_, _, Some(ObjectLit(props, _)), _) =>
      inspect(
        props.length(),
        content=(
          #|2
        ),
      )
    _ => fail("Expected ObjectLit")
  }
}

///|
test "parse array literal" {
  let prog = @parser.parse("let a = [1, 2, 3];")
  match prog.stmts[0] {
    VarDecl(_, _, Some(ArrayLit(elems, _)), _) =>
      inspect(
        elems.length(),
        content=(
          #|3
        ),
      )
    _ => fail("Expected ArrayLit")
  }
}

///|
test "parse computed member" {
  let prog = @parser.parse("a[0]")
  match prog.stmts[0] {
    ExprStmt(ComputedMember(Ident(name, _), _, _), _) =>
      inspect(
        name,
        content=(
          #|a
        ),
      )
    _ => fail("Expected ComputedMember")
  }
}

///|
test "parse new expression" {
  let prog = @parser.parse("new Foo(1, 2)")
  match prog.stmts[0] {
    ExprStmt(NewExpr(Ident(name, _), args, _), _) => {
      inspect(
        name,
        content=(
          #|Foo
        ),
      )
      inspect(
        args.length(),
        content=(
          #|2
        ),
      )
    }
    _ => fail("Expected NewExpr")
  }
}

///|
test "parse this expression" {
  let prog = @parser.parse("this.x")
  match prog.stmts[0] {
    ExprStmt(Member(ThisExpr(_), prop, _), _) =>
      inspect(
        prop,
        content=(
          #|x
        ),
      )
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
    ExprStmt(MemberAssign(_, prop, _, _), _) =>
      inspect(
        prop,
        content=(
          #|x
        ),
      )
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

///|
test "parser propagates lex_form to StringLit" {
  let prog = @parser.parse("\"\\1\"")
  match prog.stmts[0] {
    ExprStmt(StringLit(_, _, lex_form, _), _) =>
      expect_lex_form(lex_form, @token.LexForm::StringLegacyOctalEscape)
    _ => fail("expected ExprStmt(StringLit(...))")
  }
}

///|
test "parser propagates lex_form for object property key" {
  let prog = @parser.parse("({ \"\\1\": 0 })")
  match prog.stmts[0] {
    ExprStmt(Grouping(ObjectLit(props, _), _), _) =>
      match props[0].key {
        StringLit(_, _, lex_form, _) =>
          expect_lex_form(lex_form, @token.LexForm::StringLegacyOctalEscape)
        _ => fail("expected StringLit key")
      }
    _ => fail("expected ExprStmt(Grouping(ObjectLit(...)))")
  }
}

///|
test "parser propagates lex_form to NumberLit" {
  let prog = @parser.parse("0777")
  match prog.stmts[0] {
    ExprStmt(NumberLit(_, lex_form, _), _) =>
      expect_lex_form(lex_form, @token.LexForm::NumberLegacyOctalInt)
    _ => fail("expected ExprStmt(NumberLit(...))")
  }
}

///|
test "parser propagates lex_form to numeric property key" {
  let prog = @parser.parse("({ 08: 1 })")
  // Numeric prop key normalizes to StringLit but carries Number's lex_form.
  match prog.stmts[0] {
    ExprStmt(Grouping(ObjectLit(props, _), _), _) =>
      match props[0].key {
        StringLit(_, _, lex_form, _) =>
          expect_lex_form(lex_form, @token.LexForm::NumberNonOctalDecimalInt)
        _ => fail("expected StringLit key")
      }
    _ => fail("expected ExprStmt(Grouping(ObjectLit(...)))")
  }
}

///|
test "object-pattern key carries lex_form" {
  let prog = @parser.parse("let { \"\\1\": x } = o;")
  match prog.stmts[0] {
    DestructureDecl(_, ObjectPat(props, _), _, _) =>
      expect_lex_form(
        props[0].key_lex_form,
        @token.LexForm::StringLegacyOctalEscape,
      )
    _ => fail("expected DestructureDecl with ObjectPat")
  }
}

///|
test "import side-effect propagates source_lex_form" {
  let prog = @parser.parse("import \"\\1\";")
  match prog.stmts[0] {
    ImportDecl(_, _, _, _, lex_form, _) =>
      expect_lex_form(lex_form, @token.LexForm::StringLegacyOctalEscape)
    _ => fail("expected ImportDecl")
  }
}

///|
test "import from-clause propagates source_lex_form" {
  let prog = @parser.parse("import x from \"\\1\";")
  match prog.stmts[0] {
    ImportDecl(_, _, _, _, lex_form, _) =>
      expect_lex_form(lex_form, @token.LexForm::StringLegacyOctalEscape)
    _ => fail("expected ImportDecl")
  }
}

///|
test "export-all propagates source_lex_form" {
  let prog = @parser.parse("export * from \"\\1\";")
  match prog.stmts[0] {
    ExportAllDecl(_, _, lex_form, _) =>
      expect_lex_form(lex_form, @token.LexForm::StringLegacyOctalEscape)
    _ => fail("expected ExportAllDecl")
  }
}

///|
test "export-named-from propagates source_lex_form" {
  let prog = @parser.parse("export {} from \"\\1\";")
  match prog.stmts[0] {
    ExportNamedDecl(_, _, _, lex_form, _) =>
      expect_lex_form(lex_form, @token.LexForm::StringLegacyOctalEscape)
    _ => fail("expected ExportNamedDecl")
  }
}

///|
test "trailing comma in named function params (single)" {
  let prog = @parser.parse("function f(a,) {}")
  match prog.stmts[0] {
    FuncDecl(name, params, _, _) => {
      inspect(name, content="f")
      json_inspect(params, content=["a"])
    }
    _ => fail("Expected FuncDecl")
  }
}

///|
test "trailing comma in named function params (multiple)" {
  let prog = @parser.parse("function f(a, b,) {}")
  match prog.stmts[0] {
    FuncDecl(name, params, _, _) => {
      inspect(name, content="f")
      json_inspect(params, content=["a", "b"])
    }
    _ => fail("Expected FuncDecl")
  }
}

///|
test "trailing comma in nameless function expression params" {
  let prog = @parser.parse("(function (a,) {})")
  inspect(prog.stmts.length(), content="1")
}

///|
test "trailing comma in generator params" {
  let prog = @parser.parse("function* g(a, b,) { yield a; }")
  match prog.stmts[0] {
    GeneratorDecl(name, params, _, _) => {
      inspect(name, content="g")
      json_inspect(params, content=["a", "b"])
    }
    _ => fail("Expected GeneratorDecl")
  }
}

///|
test "leading comma in params is SyntaxError" {
  let result = Ok(@parser.parse("function f(,) {}")) catch { _ => Err(()) }
  inspect(result, content="Err(())")
}

///|
test "double comma in params is SyntaxError" {
  let result = Ok(@parser.parse("function f(a,,) {}")) catch { _ => Err(()) }
  inspect(result, content="Err(())")
}

///|
test "trailing comma after rest param is SyntaxError" {
  let result = Ok(@parser.parse("function f(...rest,) {}")) catch {
    _ => Err(())
  }
  inspect(result, content="Err(())")
}

///|
test "trailing comma after rest param with leading param is SyntaxError" {
  let result = Ok(@parser.parse("function f(a, ...rest,) {}")) catch {
    _ => Err(())
  }
  inspect(result, content="Err(())")
}

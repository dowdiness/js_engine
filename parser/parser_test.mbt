///|
fn expect_int(actual : Int, expected : Int, label : String) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_double(
  actual : Double,
  expected : Double,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_string(
  actual : String,
  expected : String,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(label + ": expected " + expected + ", got " + actual)
  }
}

///|
fn expect_true(actual : Bool, label : String) -> Unit raise Error {
  guard actual else { fail(label) }
}

///|
fn expect_var_kind(
  actual : @ast.VarKind,
  expected : @ast.VarKind,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_bin_op(
  actual : @ast.BinOp,
  expected : @ast.BinOp,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_loc(
  actual : @token.Loc,
  line : Int,
  col : Int,
  offset : Int,
  label : String,
) -> Unit raise Error {
  expect_int(actual.line, line, label + " line")
  expect_int(actual.col, col, label + " col")
  expect_int(actual.offset, offset, label + " offset")
}

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
fn expect_number_lit(
  actual : @ast.Expr,
  expected : Double,
  line : Int,
  col : Int,
  offset : Int,
  label : String,
) -> Unit raise Error {
  match actual {
    NumberLit(value, lex_form, loc) => {
      expect_double(value, expected, label + " value")
      expect_lex_form(lex_form, @token.LexForm::LexNormal)
      expect_loc(loc, line, col, offset, label + " loc")
    }
    _ => fail(label + ": expected NumberLit")
  }
}

///|
fn[T] expect_err(result : Result[T, Unit]) -> Unit raise Error {
  match result {
    Ok(_) => fail("expected parser error")
    Err(_) => ()
  }
}

///|
test "parse variable declaration" {
  let prog = @parser.parse("let x = 42;")
  match prog.stmts[0] {
    VarDecl(kind, name, init, loc) => {
      expect_var_kind(kind, @ast.VarKind::LetKind, "declaration kind")
      expect_string(name, "x", "declaration name")
      expect_loc(loc, 1, 1, 0, "declaration loc")
      match init {
        Some(expr) => expect_number_lit(expr, 42.0, 1, 9, 8, "initializer")
        None => fail("Expected initializer")
      }
    }
    _ => fail("Expected VarDecl")
  }
}

///|
test "parse binary precedence" {
  let prog = @parser.parse("1 + 2 * 3")
  match prog.stmts[0] {
    ExprStmt(Binary(op, left, right, op_loc), stmt_loc) => {
      expect_bin_op(op, @ast.BinOp::Add, "outer operator")
      expect_number_lit(left, 1.0, 1, 1, 0, "left operand")
      expect_loc(op_loc, 1, 3, 2, "outer operator loc")
      expect_loc(stmt_loc, 1, 1, 0, "statement loc")
      match right {
        Binary(inner_op, inner_left, inner_right, inner_loc) => {
          expect_bin_op(inner_op, @ast.BinOp::Mul, "inner operator")
          expect_number_lit(inner_left, 2.0, 1, 5, 4, "inner left operand")
          expect_number_lit(inner_right, 3.0, 1, 9, 8, "inner right operand")
          expect_loc(inner_loc, 1, 7, 6, "inner operator loc")
        }
        _ => fail("Expected right operand Binary")
      }
    }
    _ => fail("Expected ExprStmt(Binary)")
  }
}

///|
test "parse function declaration" {
  let prog = @parser.parse("function add(a, b) { return a + b; }")
  expect_int(prog.stmts.length(), 1, "statement count")
  match prog.stmts[0] {
    FuncDecl(name, params, _, _, _) => {
      expect_string(name, "add", "function name")
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
      expect_true(!(else_branch is None), "expected else branch")
    _ => fail("Expected IfStmt")
  }
}

///|
test "parse for loop" {
  let prog = @parser.parse("for (let i = 0; i < 10; i = i + 1) { }")
  match prog.stmts[0] {
    ForStmt(init, cond, update, _, _) => {
      expect_true(!(init is None), "expected for initializer")
      expect_true(!(cond is None), "expected for condition")
      expect_true(!(update is None), "expected for update")
    }
    _ => fail("Expected ForStmt")
  }
}

///|
test "parse call expression" {
  let prog = @parser.parse("foo(1, 2)")
  match prog.stmts[0] {
    ExprStmt(Call(_, args, _), _) =>
      expect_int(args.length(), 2, "call argument count")
    _ => fail("Expected Call")
  }
}

///|
test "parse member expression" {
  let prog = @parser.parse("console.log(x)")
  match prog.stmts[0] {
    ExprStmt(Call(Member(Ident(obj, _), prop, _), _, _), _) => {
      expect_string(obj, "console", "member object")
      expect_string(prop, "log", "member property")
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
    VarDecl(_, _, Some(FuncExpr(_, params, _, _, _)), _) =>
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
      expect_int(cases.length(), 3, "switch case count")
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
      expect_string(name, "k", "for-in binding")
    _ => fail("Expected ForInStmt with let")
  }
}

///|
test "parse for-in bare" {
  let prog = @parser.parse("for (k in obj) { }")
  match prog.stmts[0] {
    ForInStmt(None, name, _, _, _) => expect_string(name, "k", "for-in binding")
    _ => fail("Expected ForInStmt bare")
  }
}

///|
test "parse parenthesized for-in/of assignment heads" {
  match @parser.parse("for ((k) of obj) { }").stmts[0] {
    ForOfStmt(None, name, _, _, _) => expect_string(name, "k", "for-of binding")
    _ => fail("Expected parenthesized identifier for-of head")
  }
  match @parser.parse("for ((target.x) in obj) { }").stmts[0] {
    ForInExpr(Member(Ident(base, _), prop, _), _, _, _) => {
      expect_string(base, "target", "for-in member base")
      expect_string(prop, "x", "for-in member prop")
    }
    _ => fail("Expected parenthesized member for-in head")
  }
}

///|
test "parenthesized destructuring for-in/of heads are SyntaxError" {
  let object_of = Ok(@parser.parse("for (({x}) of [{x: 1}]) { }")) catch {
    _ => Err(())
  }
  expect_err(object_of)
  let array_of = Ok(@parser.parse("for (([x]) of [[1]]) { }")) catch {
    _ => Err(())
  }
  expect_err(array_of)
  let object_in = Ok(@parser.parse("for (({x}) in obj) { }")) catch {
    _ => Err(())
  }
  expect_err(object_in)
  let array_in = Ok(@parser.parse("for (([x]) in obj) { }")) catch {
    _ => Err(())
  }
  expect_err(array_in)
}

///|
test "parse class accessors allow line terminator after keyword" {
  let prog = @parser.parse("class C { get\nx() { return 1; } set\ny(v) { } }")
  match prog.stmts[0] {
    ClassDecl(name, None, members, _, _) => {
      expect_string(name, "C", "class name")
      guard members.length() == 2 else { fail("expected two class members") }
      match members[0] {
        @ast.ClassMember::Method(m) => {
          guard m.kind == @ast.Get else { fail("expected getter") }
        }
        _ => fail("expected getter method")
      }
      match members[1] {
        @ast.ClassMember::Method(m) => {
          guard m.kind == @ast.Set else { fail("expected setter") }
        }
        _ => fail("expected setter method")
      }
    }
    _ => fail("Expected ClassDecl")
  }
}

///|
test "parse class field initializer does not inherit generator yield" {
  let result = Ok(
    @parser.parse("function* g() { class C { static x = yield 1; } }"),
  ) catch {
    _ => Err(())
  }
  expect_err(result)
}

///|
test "parse generator methods with yield regexp literal" {
  let _ = @parser.parse("class C { *g(){ yield /x/g; } }")
  let _ = @parser.parse("class C { m(){} *g(){ yield /x/g; } }")
  let _ = @parser.parse("class C { async *g(){ yield /x/g; } }")
  let _ = @parser.parse("({ *g(){ yield /x/g; } })")
  let _ = @parser.parse("({ async *g(){ yield /x/g; } })")
}

///|
test "parse labeled statement" {
  let prog = @parser.parse("outer: for (let i = 0; i < 3; i = i + 1) { }")
  match prog.stmts[0] {
    LabeledStmt(label, _, _) => expect_string(label, "outer", "label")
    _ => fail("Expected LabeledStmt")
  }
}

///|
test "parse break label only on same line" {
  let prog = @parser.parse("while (true) { break\nfoo(); }")
  match prog.stmts[0] {
    WhileStmt(_, Block(body, _), _) => {
      expect_int(body.length(), 2, "while body count")
      match body[0] {
        BreakStmt(None, _) => ()
        _ => fail("Expected unlabeled break")
      }
      match body[1] {
        ExprStmt(Call(Ident(name, _), _, _), _) =>
          expect_string(name, "foo", "call name")
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
      expect_int(body.length(), 2, "while body count")
      match body[0] {
        ContinueStmt(None, _) => ()
        _ => fail("Expected unlabeled continue")
      }
      match body[1] {
        ExprStmt(Call(Ident(name, _), _, _), _) =>
          expect_string(name, "foo", "call name")
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
      expect_int(props.length(), 2, "object property count")
    _ => fail("Expected ObjectLit")
  }
}

///|
test "parse array literal" {
  let prog = @parser.parse("let a = [1, 2, 3];")
  match prog.stmts[0] {
    VarDecl(_, _, Some(ArrayLit(elems, _)), _) =>
      expect_int(elems.length(), 3, "array element count")
    _ => fail("Expected ArrayLit")
  }
}

///|
test "parse computed member" {
  let prog = @parser.parse("a[0]")
  match prog.stmts[0] {
    ExprStmt(ComputedMember(Ident(name, _), _, _), _) =>
      expect_string(name, "a", "computed member object")
    _ => fail("Expected ComputedMember")
  }
}

///|
test "parse new expression" {
  let prog = @parser.parse("new Foo(1, 2)")
  match prog.stmts[0] {
    ExprStmt(NewExpr(Ident(name, _), args, _), _) => {
      expect_string(name, "Foo", "constructor name")
      expect_int(args.length(), 2, "constructor argument count")
    }
    _ => fail("Expected NewExpr")
  }
}

///|
test "parse this expression" {
  let prog = @parser.parse("this.x")
  match prog.stmts[0] {
    ExprStmt(Member(ThisExpr(_), prop, _), _) =>
      expect_string(prop, "x", "this member property")
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
      expect_string(prop, "x", "assigned member property")
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
    FuncDecl(name, params, _, _, _) => {
      expect_string(name, "f", "function name")
      json_inspect(params, content=["a"])
    }
    _ => fail("Expected FuncDecl")
  }
}

///|
test "trailing comma in named function params (multiple)" {
  let prog = @parser.parse("function f(a, b,) {}")
  match prog.stmts[0] {
    FuncDecl(name, params, _, _, _) => {
      expect_string(name, "f", "function name")
      json_inspect(params, content=["a", "b"])
    }
    _ => fail("Expected FuncDecl")
  }
}

///|
test "trailing comma in nameless function expression params" {
  let prog = @parser.parse("(function (a,) {})")
  expect_int(prog.stmts.length(), 1, "statement count")
}

///|
test "trailing comma in generator params" {
  let prog = @parser.parse("function* g(a, b,) { yield a; }")
  match prog.stmts[0] {
    GeneratorDecl(name, params, _, _, _) => {
      expect_string(name, "g", "generator name")
      json_inspect(params, content=["a", "b"])
    }
    _ => fail("Expected GeneratorDecl")
  }
}

///|
test "leading comma in params is SyntaxError" {
  let result = Ok(@parser.parse("function f(,) {}")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "double comma in params is SyntaxError" {
  let result = Ok(@parser.parse("function f(a,,) {}")) catch { _ => Err(()) }
  expect_err(result)
}

///|
test "trailing comma after rest param is SyntaxError" {
  let result = Ok(@parser.parse("function f(...rest,) {}")) catch {
    _ => Err(())
  }
  expect_err(result)
}

///|
test "trailing comma after rest param with leading param is SyntaxError" {
  let result = Ok(@parser.parse("function f(a, ...rest,) {}")) catch {
    _ => Err(())
  }
  expect_err(result)
}

///|
test "parse_tokens without source leaves source text absent" {
  let source = "function f() {} class C {}"
  let tokens = @lexer.tokenize(source)
  let prog = @parser.parse_tokens(tokens)
  match prog.stmts[0] {
    FuncDecl(_, _, _, _, None) => ()
    _ => fail("Expected FuncDecl without source text")
  }
  match prog.stmts[1] {
    ClassDecl(_, _, _, _, None) => ()
    _ => fail("Expected ClassDecl without source text")
  }
}

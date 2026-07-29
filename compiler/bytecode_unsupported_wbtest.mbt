///|
fn bytecode_unsupported_reason_matches(
  actual : BytecodeUnsupportedReason,
  expected : BytecodeUnsupportedReason,
) -> Bool {
  match expected {
    AsyncArrowFunction => actual is AsyncArrowFunction
    AsyncFunctionDeclaration => actual is AsyncFunctionDeclaration
    AsyncFunctionExpression => actual is AsyncFunctionExpression
    AsyncGeneratorDeclaration => actual is AsyncGeneratorDeclaration
    AsyncGeneratorExpression => actual is AsyncGeneratorExpression
    BlockFunctionDeclaration => actual is BlockFunctionDeclaration
    BlockLexicalDeclaration => actual is BlockLexicalDeclaration
    ClassDeclaration => actual is ClassDeclaration
    ClassExpression => actual is ClassExpression
    CompoundAssignmentTarget => actual is CompoundAssignmentTarget
    ControlFlowFunctionDeclaration => actual is ControlFlowFunctionDeclaration
    DefaultParameter => actual is DefaultParameter
    DeleteNonPropertyOperator => actual is DeleteNonPropertyOperator
    DestructuringDeclarationContext => actual is DestructuringDeclarationContext
    DestructuringDeclarationKind => actual is DestructuringDeclarationKind
    DestructuringParameter => actual is DestructuringParameter
    DestructuringPatternComputedKey => actual is DestructuringPatternComputedKey
    DestructuringPatternDefault => actual is DestructuringPatternDefault
    DestructuringPatternMemberTarget =>
      actual is DestructuringPatternMemberTarget
    ExportDeclaration => actual is ExportDeclaration
    ForInAssignmentTarget => actual is ForInAssignmentTarget
    ForInLexicalDeclaration => actual is ForInLexicalDeclaration
    ForInVarDeclaration => actual is ForInVarDeclaration
    ForLexicalInitializer => actual is ForLexicalInitializer
    ForOfStatement => actual is ForOfStatement
    GeneratorDeclaration => actual is GeneratorDeclaration
    GeneratorExpression => actual is GeneratorExpression
    ImportDeclaration => actual is ImportDeclaration
    ObjectLiteralAsyncGeneratorMethodProperty =>
      actual is ObjectLiteralAsyncGeneratorMethodProperty
    ObjectLiteralAsyncMethodProperty =>
      actual is ObjectLiteralAsyncMethodProperty
    ObjectLiteralDataPropertySuper => actual is ObjectLiteralDataPropertySuper
    ObjectLiteralGeneratorMethodProperty =>
      actual is ObjectLiteralGeneratorMethodProperty
    ObjectLiteralProtoMethodProperty =>
      actual is ObjectLiteralProtoMethodProperty
    PrivateClassElement => actual is PrivateClassElement
    SuperCall => actual is SuperCall
    SuperAssignment => actual is SuperAssignment
    SwitchLexicalDeclaration => actual is SwitchLexicalDeclaration
    TryCatchStatement => actual is TryCatchStatement
    UpdateTarget => actual is UpdateTarget
    WebCompatCallAssign => actual is WebCompatCallAssign
    WithStatement => actual is WithStatement
  }
}

///|
fn assert_bytecode_unsupported(
  src : String,
  expected_reason : BytecodeUnsupportedReason,
  expected_offset? : Int = -1,
) -> Unit raise Error {
  let prog = @parser.parse(src)
  match lower_script_to_bytecode(prog.stmts) {
    Ok(_) =>
      fail(
        "expected bytecode lowering to reject " + expected_reason.display_text(),
      )
    Err(unsupported) => {
      guard bytecode_unsupported_reason_matches(
        unsupported.reason,
        expected_reason,
      ) else {
        fail(
          "expected " +
          expected_reason.display_text() +
          ", got " +
          unsupported.reason.display_text(),
        )
      }
      assert_true(unsupported.loc.offset >= 0)
      assert_true(unsupported.loc.offset <= src.length())
      if expected_offset >= 0 {
        assert_eq(unsupported.loc.offset, expected_offset)
      }
    }
  }
}

///|
fn assert_bytecode_lowering_syntax_error(
  src : String,
  expected_message : String,
) -> Unit raise Error {
  let prog = @parser.parse(src)
  try {
    let _ = lower_script_to_bytecode(prog.stmts)
    fail("expected bytecode lowering SyntaxError")
  } catch {
    @errors.SyntaxError(message~) => assert_eq(message, expected_message)
    _ => fail("expected bytecode lowering SyntaxError")
  }
}

///|
test "equivalence harness: typed unsupported outcome" {
  assert_bytecode_unsupported(
    "for (var x of [1, 2]) {}",
    ForOfStatement,
    expected_offset=0,
  )
  assert_bytecode_unsupported("try {} catch (e) {}", TryCatchStatement)
  assert_bytecode_unsupported("class C {}", ClassDeclaration)
}

///|
test "bytecode rejects non-identifier non-property delete until reference semantics are shared" {
  let src =
    #|var x = 1;
    #|delete (x = 2);
  assert_bytecode_unsupported(src, DeleteNonPropertyOperator)
}

///|
test "bytecode rejects switch lexical and function declarations explicitly" {
  assert_bytecode_unsupported(
    "switch (1) { case 1: let x = 1; }",
    SwitchLexicalDeclaration,
  )
  assert_bytecode_unsupported(
    "switch (1) { case 1: function f() { return 1; } }",
    ControlFlowFunctionDeclaration,
  )
}

///|
test "bytecode preserves label-specific SyntaxError for unresolved control flow" {
  assert_bytecode_lowering_syntax_error(
    "while (true) { break label; }", "Undefined label 'label'",
  )
  assert_bytecode_lowering_syntax_error(
    "label: { continue label; }", "Illegal continue statement: 'label' does not denote an iteration statement",
  )
  assert_bytecode_lowering_syntax_error(
    "while (true) { continue missing; }", "Undefined label 'missing'",
  )
}

///|
test "bytecode rejects labeled function declarations until label semantics are implemented" {
  let src =
    #|label: {
    #|  function f() { return 1; }
    #|}
  assert_bytecode_unsupported(src, ControlFlowFunctionDeclaration)
}

///|
test "bytecode preserves SyntaxError for invalid compound assignment targets" {
  let src =
    #|var x = 1;
    #|var y = 2;
    #|(x + y) += 1;
  assert_bytecode_lowering_syntax_error(
    src, "Invalid compound assignment target at line 3, col 9",
  )
}

///|
test "bytecode rejects super calls explicitly" {
  assert_bytecode_unsupported("super();", SuperCall)
}

///|
test "bytecode rejects super inside object literal data property values explicitly" {
  let src =
    #|({
    #|  __proto__: { m: function() { return 1; } },
    #|  m: function() { return super.m(); }
    #|}).m();
  assert_bytecode_unsupported(src, ObjectLiteralDataPropertySuper)
}

///|
test "bytecode rejects __proto__ methods until object method semantics are settled" {
  assert_bytecode_unsupported(
    "({ __proto__() { return 7; } });",
    ObjectLiteralProtoMethodProperty,
  )
}

///|
test "bytecode rejects unsupported object literal method forms explicitly" {
  assert_bytecode_unsupported(
    "({ *m() { yield 1; } });",
    ObjectLiteralGeneratorMethodProperty,
  )
  assert_bytecode_unsupported(
    "({ async m() { return 1; } });",
    ObjectLiteralAsyncMethodProperty,
  )
  assert_bytecode_unsupported(
    "({ async *m() { yield 1; } });",
    ObjectLiteralAsyncGeneratorMethodProperty,
  )
}

///|
test "bytecode rejects unsupported arrow parameter forms explicitly" {
  assert_bytecode_unsupported("((x = 1) => x)();", DefaultParameter)
  assert_bytecode_unsupported(
    "(({ x }) => x)({ x: 1 });",
    DestructuringParameter,
  )
}

///|
test "bytecode rejects unsupported destructuring assignment patterns explicitly" {
  let default_src =
    #|var x = 0;
    #|[x = 1] = [undefined];
    #|x;
  assert_bytecode_unsupported(default_src, DestructuringPatternDefault)
  let computed_src =
    #|var key = "x";
    #|var x = 0;
    #|({ [key]: x } = { x: 1 });
  assert_bytecode_unsupported(computed_src, DestructuringPatternComputedKey)
  let member_target_src =
    #|var obj = {};
    #|[obj.x] = [1];
  assert_bytecode_unsupported(
    member_target_src,
    DestructuringPatternMemberTarget,
  )
}

///|
test "bytecode rejects for initializer var destructuring until loop binding semantics are shared" {
  let direct =
    #|for (var [i] = [0]; i < 1; i = i + 1) {
    #|}
  assert_bytecode_unsupported(direct, DestructuringDeclarationContext)
  let comma_decl =
    #|for (var i = 0, [x] = [1]; i < 1; i = i + 1) {
    #|}
  assert_bytecode_unsupported(comma_decl, DestructuringDeclarationContext)
}

///|
test "bytecode rejects unsupported destructuring declaration contexts and kinds" {
  let control_flow =
    #|if (true) {
    #|  var [x] = [1];
    #|}
  assert_bytecode_unsupported(control_flow, DestructuringDeclarationContext)
  let for_body =
    #|for (var i = 0; i < 1; i = i + 1) {
    #|  var [x] = [1];
    #|}
  assert_bytecode_unsupported(for_body, DestructuringDeclarationContext)
  assert_bytecode_unsupported("let [x] = [1];", DestructuringDeclarationKind)
}

///|
test "bytecode rejects var destructuring declaration defaults until pattern expressions are compiled" {
  let src =
    #|var [x = 1] = [undefined];
    #|x;
  assert_bytecode_unsupported(src, DestructuringPatternDefault)
}

///|
test "bytecode rejects block lexical declarations until block envs are implemented" {
  let src =
    #|var x = 1;
    #|{
    #|  let x = 2;
    #|}
    #|x;
  assert_bytecode_unsupported(src, BlockLexicalDeclaration)
}

///|
test "bytecode rejects for lexical initializers until loop scoping is implemented" {
  let src =
    #|for (let i = 0; i < 1; i = i + 1) {
    #|}
    #|i;
  assert_bytecode_unsupported(src, ForLexicalInitializer)
}

///|
test "bytecode rejects control-flow function declarations until block semantics are implemented" {
  let src =
    #|if (true) {
    #|  function f() { return 1; }
    #|}
    #|f();
  assert_bytecode_unsupported(src, ControlFlowFunctionDeclaration)
}

///|
test "bytecode rejects unsupported for-in destructuring assignment patterns" {
  let src =
    #|var x = 0;
    #|for ([x = 1] in { a: 1 }) {
    #|}
  assert_bytecode_unsupported(src, DestructuringPatternDefault)
}

///|
test "bytecode rejects for-in declarations until loop binding semantics are shared" {
  assert_bytecode_unsupported("for (var k in { a: 1 }) {}", ForInVarDeclaration)
  assert_bytecode_unsupported(
    "for (var [k] in { a: 1 }) {}",
    ForInVarDeclaration,
  )
  assert_bytecode_unsupported(
    "for (let k in { a: 1 }) {}",
    ForInLexicalDeclaration,
  )
  assert_bytecode_unsupported(
    "for (let [k] in { a: 1 }) {}",
    ForInLexicalDeclaration,
  )
}

///|
test "bytecode rejects for-of loops until iterator-close semantics are shared" {
  assert_bytecode_unsupported("var x; for (x of [1]) {}", ForOfStatement)
  assert_bytecode_unsupported(
    "for (var x of [1]) {}",
    ForOfStatement,
    expected_offset=0,
  )
  assert_bytecode_unsupported(
    "var target = {}; for (target.x of [1]) {}",
    ForOfStatement,
  )
}

///|
test "bytecode rejects class declarations and expressions explicitly" {
  assert_bytecode_unsupported("class C {}", ClassDeclaration)
  assert_bytecode_unsupported(
    "var C = class { method() { return 1; } };",
    ClassExpression,
  )
}

///|
test "bytecode rejects generator forms explicitly" {
  assert_bytecode_unsupported(
    "function* g() { yield 1; }",
    GeneratorDeclaration,
  )
  assert_bytecode_unsupported(
    "var g = function*() { yield 1; };",
    GeneratorExpression,
  )
}

///|
test "bytecode rejects async function forms explicitly" {
  assert_bytecode_unsupported(
    "async function f() { return 1; }",
    AsyncFunctionDeclaration,
  )
  assert_bytecode_unsupported(
    "var f = async function() { return 1; };",
    AsyncFunctionExpression,
  )
  assert_bytecode_unsupported("var f = async () => 1;", AsyncArrowFunction)
  assert_bytecode_unsupported(
    "async function* g() { yield 1; }",
    AsyncGeneratorDeclaration,
  )
  assert_bytecode_unsupported(
    "var g = async function*() { yield 1; };",
    AsyncGeneratorExpression,
  )
}

///|
test "bytecode rejects module declarations explicitly" {
  assert_bytecode_unsupported("import 'dep';", ImportDeclaration)
  assert_bytecode_unsupported("export { x };", ExportDeclaration)
  assert_bytecode_unsupported("export default 1;", ExportDeclaration)
  assert_bytecode_unsupported("export * from 'dep';", ExportDeclaration)
}

///|
test "bytecode rejects with statements explicitly" {
  let src =
    #|var obj = { x: 1 };
    #|with (obj) {
    #|  x;
    #|}
  assert_bytecode_unsupported(src, WithStatement)
}

///|
test "bytecode rejects try catch and finally statements explicitly" {
  assert_bytecode_unsupported(
    "try { throw 1; } catch (e) { e; }",
    TryCatchStatement,
  )
  assert_bytecode_unsupported("try { 1; } finally { 2; }", TryCatchStatement)
}

///|
using @runtime {type BindingKind, type Value}

///|
const CLOSURE_FACTORY_PROGRAM : String =
  #|function makeCounter(start) {
  #|  var count = start;
  #|  return function() {
  #|    count = count + 1;
  #|    return count;
  #|  };
  #|}
  #|var counters = [];
  #|for (var i = 0; i < 1000; i++) {
  #|  counters.push(makeCounter(i));
  #|}
  #|var total = 0;
  #|for (var i = 0; i < 1000; i++) {
  #|  total = total + counters[i]();
  #|}
  #|total;

///|
const PIPELINE_EXEC_PROGRAM : String =
  #|(function() {
  #|  function makeCounter(start) {
  #|    var count = start;
  #|    return function() {
  #|      count = count + 1;
  #|      return count;
  #|    };
  #|  }
  #|  var counters = [];
  #|  for (var i = 0; i < 1000; i++) {
  #|    counters.push(makeCounter(i));
  #|  }
  #|  var total = 0;
  #|  for (var i = 0; i < 1000; i++) {
  #|    total = total + counters[i]();
  #|  }
  #|  return total;
  #|})();

///|
fn default_ctx() -> @runtime.ExecContext {
  { strict: false, current_generator: None }
}

///|
fn strict_ctx() -> @runtime.ExecContext {
  { strict: true, current_generator: None }
}

///|
fn parse_expr(src : String) -> @ast.Expr raise Error {
  let prog = @parser.parse(src)
  if prog.stmts.length() != 1 {
    fail("expected one statement")
  }
  match prog.stmts[0] {
    ExprStmt(expr, _) => expr
    _ => fail("expected expression statement")
  }
}

///|
fn run_expr(
  src : String,
  interp : @runtime.Interpreter,
  env : @runtime.Environment,
) -> Value raise Error {
  run_expr_with_ctx(src, interp, default_ctx(), env)
}

///|
fn run_expr_with_ctx(
  src : String,
  interp : @runtime.Interpreter,
  ctx : @runtime.ExecContext,
  env : @runtime.Environment,
) -> Value raise Error {
  let compiled = compile_expr_to_closure(parse_expr(src))
  compiled(interp, ctx, env)
}

///|
fn run_program(src : String) -> Value raise Error {
  let prog = @parser.parse(src)
  let interp = @interpreter.new_interpreter()
  let compiled = compile_program_to_closure(prog.stmts)
  compiled(interp, default_ctx(), interp.global)
}

///|
fn run_script(src : String) -> Value raise Error {
  let prog = @parser.parse(src)
  let interp = @interpreter.new_interpreter()
  let compiled = compile_script_to_closure(prog.stmts)
  compiled(interp)
}

///|
fn run_interpreter_outcome(src : String) -> String {
  try {
    let prog = @parser.parse(src)
    let interp = @interpreter.new_interpreter()
    "value:" + interp.run(prog.stmts).to_string()
  } catch {
    @runtime.JsException(value) => "throw:" + value.to_string()
    err => "error:" + err.to_string()
  }
}

///|
fn run_script_outcome(src : String) -> String {
  try "value:" + run_script(src).to_string() catch {
    @runtime.JsException(value) => "throw:" + value.to_string()
    err => "error:" + err.to_string()
  }
}

///|
test "closure conversion evaluates identifiers and binary expressions" {
  let interp = @interpreter.new_interpreter()
  interp.global.def("x", Value::Number(41.0), BindingKind::VarBinding)
  let result = run_expr("x + 1", interp, interp.global)
  inspect(
    result,
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion captures function expression environment" {
  let interp = @interpreter.new_interpreter()
  interp.global.def("x", Value::Number(40.0), BindingKind::VarBinding)
  let fn_value = run_expr(
    "(function(y) { return x + y; })",
    interp,
    interp.global,
  )
  let result = interp.call_value(
    fn_value,
    Value::Undefined,
    [Value::Number(2.0)],
    @token.Loc::default(),
  )
  inspect(
    result,
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion executes compiled function bodies" {
  let interp = @interpreter.new_interpreter()
  let make_counter = run_expr(
    "(function(start) { var count = start; return function() { count = count + 1; return count; }; })",
    interp,
    interp.global,
  )
  let counter = interp.call_value(
    make_counter,
    Value::Undefined,
    [Value::Number(40.0)],
    @token.Loc::default(),
  )
  let first = interp.call_value(
    counter,
    Value::Undefined,
    [],
    @token.Loc::default(),
  )
  let second = interp.call_value(
    counter,
    Value::Undefined,
    [],
    @token.Loc::default(),
  )
  inspect(
    [first, second],
    content=(
      #|[41, 42]
    ),
  )
}

///|
test "closure conversion creates callable arrow functions" {
  let interp = @interpreter.new_interpreter()
  let fn_value = run_expr("(x => x + 1)", interp, interp.global)
  let result = interp.call_value(
    fn_value,
    Value::Undefined,
    [Value::Number(41.0)],
    @token.Loc::default(),
  )
  inspect(
    result,
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates bare calls" {
  let interp = @interpreter.new_interpreter()
  let result = run_expr(
    "(function(value) { return value + 1; })(41)",
    interp,
    interp.global,
  )
  inspect(
    result,
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion expands spread call arguments" {
  let interp = @interpreter.new_interpreter()
  interp.global.def(
    "sum",
    run_expr("(function(a, b) { return a + b; })", interp, interp.global),
    BindingKind::VarBinding,
  )
  interp.global.def(
    "args",
    @runtime.make_array([Value::Number(40.0), Value::Number(2.0)]),
    BindingKind::VarBinding,
  )
  let result = run_expr("sum(...args)", interp, interp.global)
  inspect(
    result,
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves direct eval lexical scope" {
  let interp = @interpreter.new_interpreter()
  interp.global.def("x", Value::Number(1.0), BindingKind::VarBinding)
  let lexical_env = @runtime.Environment::new(parent=Some(interp.global))
  lexical_env.def("x", Value::Number(42.0), BindingKind::VarBinding)
  let result = run_expr("eval(\"x\")", interp, lexical_env)
  inspect(
    result,
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves direct eval caller strictness" {
  let interp = @interpreter.new_interpreter()
  let result = run_expr_with_ctx(
    "eval(\"var arguments = 1;\")",
    interp,
    strict_ctx(),
    interp.global,
  ) catch {
    @errors.SyntaxError(_) => Value::String_("syntax")
    _ => Value::String_("other")
  }
  inspect(
    result,
    content=(
      #|syntax
    ),
  )
}

///|
test "closure conversion validates strict function signatures" {
  let interp = @interpreter.new_interpreter()
  let result = run_expr(
    "(function(a, a) { \"use strict\"; })",
    interp,
    interp.global,
  ) catch {
    @errors.SyntaxError(_) => Value::String_("syntax")
    _ => Value::String_("other")
  }
  inspect(
    result,
    content=(
      #|syntax
    ),
  )
}

///|
test "closure conversion handles proxy rhs for instanceof" {
  let interp = @interpreter.new_interpreter()
  let setup = @parser.parse(
    "function C() {} var proxyCtor = new Proxy(C, {}); var obj = new C();",
  )
  let _ = interp.run(setup.stmts)
  let result = run_expr("obj instanceof proxyCtor", interp, interp.global)
  inspect(
    result,
    content=(
      #|true
    ),
  )
}

///|
test "closure conversion evaluates basic object literals" {
  inspect(
    run_script("({ x: 41 }).x + 1;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates computed object keys" {
  inspect(
    run_script("({ [\"x\"]: 41 }).x + 1;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion binds this for object function properties" {
  inspect(
    run_script(
      "var obj = { x: 41, getX: function() { return this.x; } }; obj.getX() + 1;",
    ),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion binds this for object method shorthand" {
  inspect(
    run_script(
      "var obj = { x: 41, getX() { return this.x; } }; obj.getX() + 1;",
    ),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion reports unsupported object literal accessors" {
  inspect(
    run_script_outcome("({ get x() { return 1; } }).x;").contains(
      "object literal accessor property",
    ),
    content="true",
  )
}

///|
test "closure conversion reports unsupported object literal spread" {
  inspect(
    run_script_outcome("({ ...{ x: 1 } }).x;").contains(
      "object literal spread property",
    ),
    content="true",
  )
}

///|
test "closure conversion assigns member properties" {
  inspect(
    run_script("var o = { x: 1 }; o.x = 41; o.x + 1;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion assigns computed properties" {
  inspect(
    run_script("var o = {}; o[\"x\"] = 41; o.x + 1;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion updates member properties" {
  inspect(
    run_script("var o = { x: 41 }; o.x++; o.x;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves postfix member update result" {
  inspect(
    run_script("var o = { x: 41 }; var y = o.x++; y + o.x;"),
    content=(
      #|83
    ),
  )
}

///|
test "closure conversion updates computed properties" {
  inspect(
    run_script("var o = { x: 41 }; ++o[\"x\"];"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves numeric postfix result" {
  inspect(
    run_script("var x = \"41\"; var y = x++; y + x;"),
    content=(
      #|83
    ),
  )
}

///|
test "closure conversion routes strict member assignment through setters" {
  inspect(
    run_script_outcome(
      "\"use strict\"; var o = {}; Object.defineProperty(o, \"x\", { value: 1, writable: false }); o.x = 2;",
    ).contains("TypeError"),
    content="true",
  )
}

///|
test "closure conversion evaluates identifier compound assignment" {
  inspect(
    run_script("var x = 40; x += 2; x;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates member compound assignment" {
  inspect(
    run_script("var o = { x: 40 }; o.x += 2; o.x;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates computed compound assignment" {
  inspect(
    run_script("var o = { x: 40 }; o[\"x\"] += 2; o.x;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates logical assignment" {
  inspect(
    run_script("var x = 0; x ||= 42; x;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves logical assignment short circuit" {
  inspect(
    run_script("function fail() { throw \"no\"; } var x = 1; x ||= fail(); x;"),
    content=(
      #|1
    ),
  )
}

///|
test "closure conversion evaluates member nullish assignment" {
  inspect(
    run_script("var o = { x: null }; o.x ??= 42; o.x;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves computed logical assignment short circuit" {
  inspect(
    run_script(
      "function fail() { throw \"no\"; } var o = { x: 0 }; o[\"x\"] &&= fail(); o.x;",
    ),
    content=(
      #|0
    ),
  )
}

///|
test "closure conversion routes strict compound assignment through setters" {
  inspect(
    run_script_outcome(
      "\"use strict\"; var o = {}; Object.defineProperty(o, \"x\", { value: 1, writable: false }); o.x += 1;",
    ).contains("TypeError"),
    content="true",
  )
}

///|
test "closure conversion evaluates unary numeric expressions" {
  inspect(
    run_script("var x = 1; -x + 43;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates typeof missing" {
  inspect(
    run_script("typeof missing;"),
    content=(
      #|undefined
    ),
  )
}

///|
test "closure conversion evaluates void operand effects" {
  inspect(
    run_script("var x = 0; void (x = 42); x;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates ternary selected branch only" {
  inspect(
    run_script("function fail() { throw \"no\"; } var x = 0; x ? fail() : 42;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion evaluates comma expressions" {
  inspect(
    run_script("var x = 0; (x = 41, x + 1);"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion reports unsupported delete unary" {
  inspect(
    run_script_outcome("var o = { x: 1 }; delete o.x;").contains(
      "delete unary operator",
    ),
    content="true",
  )
}

///|
test "closure conversion constructs function declarations" {
  inspect(
    run_script("function C(x) { this.x = x; } var o = new C(41); o.x + 1;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion constructs function expressions" {
  inspect(
    run_script("var o = new (function C(x) { this.x = x; })(41); o.x + 1;"),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion constructs with spread arguments" {
  inspect(
    run_script(
      "function C(a, b) { this.x = a + b; } var args = [40, 1]; var o = new C(...args); o.x + 1;",
    ),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves constructor object return" {
  inspect(
    run_script(
      "function C() { this.x = 1; return { x: 41 }; } var o = new C(); o.x + 1;",
    ),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion preserves constructor primitive return" {
  inspect(
    run_script(
      "function C() { this.x = 41; return 1; } var o = new C(); o.x + 1;",
    ),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion keeps method shorthand non-constructable" {
  inspect(
    run_script_outcome("var o = { m() { return 1; } }; new o.m();").contains(
      "TypeError",
    ),
    content="true",
  )
}

///|
test "closure conversion reports non-constructor errors" {
  inspect(
    run_script_outcome("new Math();").contains("TypeError"),
    content="true",
  )
}

///|
test "closure conversion compiles closure factory program" {
  inspect(
    run_program(CLOSURE_FACTORY_PROGRAM),
    content=(
      #|500500
    ),
  )
}

///|
test "closure conversion compiles pipeline evaluate program" {
  inspect(
    run_program(PIPELINE_EXEC_PROGRAM),
    content=(
      #|500500
    ),
  )
}

///|
test "closure conversion script wrapper hoists function declarations" {
  let src = "var answer = f(); function f() { return 42; } answer;"
  inspect(
    [run_interpreter_outcome(src), run_script_outcome(src)],
    content=(
      #|["value:42", "value:42"]
    ),
  )
}

///|
test "closure conversion script wrapper preserves strict var hoisting" {
  let src = "\"use strict\"; answer = 41; var answer; answer + 1;"
  inspect(
    [run_interpreter_outcome(src), run_script_outcome(src)],
    content=(
      #|["value:42", "value:42"]
    ),
  )
}

///|
test "closure conversion script wrapper validates strict declarations" {
  let src = "\"use strict\"; function f(a, a) { return a; } f(1, 2);"
  inspect(
    run_script_outcome(src) == run_interpreter_outcome(src),
    content="true",
  )
}

///|
test "closure conversion script wrapper installs current interpreter" {
  let interp = @interpreter.new_interpreter()
  let value_of = run_expr("(function() { return 41; })", interp, interp.global)
  let obj = @runtime.make_plain_object()
  match obj {
    Value::Object(data) => data.bag.properties["valueOf"] = value_of
    _ => abort("plain object constructor returned non-object")
  }
  interp.global.def("obj", obj, BindingKind::VarBinding)
  let prog = @parser.parse("obj + 1;")
  let compiled = compile_script_to_closure(prog.stmts)
  inspect(
    compiled(interp),
    content=(
      #|42
    ),
  )
}

///|
test "closure conversion script wrapper wraps top-level engine errors" {
  inspect(
    run_script_outcome("missing;"),
    content=(
      #|throw:ReferenceError: missing is not defined
    ),
  )
}

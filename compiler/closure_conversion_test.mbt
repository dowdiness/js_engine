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
fn expect_string(
  actual : String,
  expected : String,
  label : String,
) -> Unit raise Error {
  if actual != expected {
    fail(label + ": expected " + expected + ", got " + actual)
  }
}

///|
fn expect_value(
  actual : Value,
  expected : String,
  label : String,
) -> Unit raise Error {
  expect_string(actual.to_string(), expected, label)
}

///|
fn expect_script_value(
  src : String,
  expected : String,
  label : String,
) -> Unit raise Error {
  expect_value(run_script(src), expected, label)
}

///|
fn expect_true(actual : Bool, label : String) -> Unit raise Error {
  if !actual {
    fail(label + ": expected true")
  }
}

///|
test "closure conversion evaluates identifiers and binary expressions" {
  let interp = @interpreter.new_interpreter()
  interp.global.def("x", Value::Number(41.0), BindingKind::VarBinding)
  let result = run_expr("x + 1", interp, interp.global)
  expect_value(result, "42", "identifier binary expression result")
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
  expect_value(result, "42", "captured function expression result")
}

///|
test "closure conversion direct function expressions use provided interpreter prototypes" {
  let interp = @interpreter.new_interpreter()
  let fn_value = run_expr("(function() {})", interp, interp.global)
  let function_proto = interp.global.get("[[FunctionPrototype]]")
  let object_proto = interp.global.get("[[ObjectPrototype]]")
  match fn_value {
    Object(data) => {
      expect_true(
        @runtime.strict_equal(data.prototype, function_proto),
        "compiled function [[Prototype]]",
      )
      match data.bag.properties.get("prototype") {
        Some(Object(proto_data)) =>
          expect_true(
            @runtime.strict_equal(proto_data.prototype, object_proto),
            "compiled function prototype object [[Prototype]]",
          )
        _ => fail("compiled function missing prototype object")
      }
    }
    _ => fail("compiled function expression did not produce function object")
  }
}

///|
test "closure conversion preserves callee realm for foreign compiled functions" {
  let foreign_interp = @interpreter.new_interpreter()
  let prog = @parser.parse("function outer() { return function inner() {}; }")
  let compiled = compile_script_to_closure(prog.stmts)
  let _ = compiled(foreign_interp)
  let outer = foreign_interp.global.get("outer")
  let local_interp = @interpreter.new_interpreter()
  let inner = local_interp.call_value(
    outer,
    Value::Undefined,
    [],
    @token.Loc::default(),
  )
  let foreign_function_proto = foreign_interp.global.get(
    "[[FunctionPrototype]]",
  )
  let foreign_object_proto = foreign_interp.global.get("[[ObjectPrototype]]")
  let local_function_proto = local_interp.global.get("[[FunctionPrototype]]")
  let local_object_proto = local_interp.global.get("[[ObjectPrototype]]")
  match inner {
    Object(data) => {
      expect_true(
        @runtime.strict_equal(data.prototype, foreign_function_proto),
        "foreign compiled function [[Prototype]]",
      )
      expect_true(
        !@runtime.strict_equal(data.prototype, local_function_proto),
        "foreign compiled function avoids caller [[Prototype]]",
      )
      match data.bag.properties.get("prototype") {
        Some(Object(proto_data)) => {
          expect_true(
            @runtime.strict_equal(proto_data.prototype, foreign_object_proto),
            "foreign compiled function prototype object [[Prototype]]",
          )
          expect_true(
            !@runtime.strict_equal(proto_data.prototype, local_object_proto),
            "foreign compiled function prototype object avoids caller realm",
          )
        }
        _ => fail("foreign compiled function missing prototype object")
      }
    }
    _ => fail("foreign compiled function did not return function object")
  }
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
  json_inspect([first.to_string(), second.to_string()], content=["41", "42"])
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
  expect_value(result, "42", "arrow function call result")
}

///|
test "closure conversion evaluates bare calls" {
  let interp = @interpreter.new_interpreter()
  let result = run_expr(
    "(function(value) { return value + 1; })(41)",
    interp,
    interp.global,
  )
  expect_value(result, "42", "bare call result")
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
  expect_value(result, "42", "spread call result")
}

///|
test "closure conversion preserves direct eval lexical scope" {
  let interp = @interpreter.new_interpreter()
  interp.global.def("x", Value::Number(1.0), BindingKind::VarBinding)
  let lexical_env = @runtime.Environment::new(parent=Some(interp.global))
  lexical_env.def("x", Value::Number(42.0), BindingKind::VarBinding)
  let result = run_expr("eval(\"x\")", interp, lexical_env)
  expect_value(result, "42", "direct eval lexical result")
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
  expect_value(result, "syntax", "direct eval strictness error")
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
  expect_value(result, "syntax", "strict function signature error")
}

///|
test "closure conversion preserves block lexical declarations" {
  expect_script_value(
    "var x = 1; { x = x + 41; } x;", "42", "non-lexical block assignment",
  )
  let parameter_redecl = "(function(x) { { var x = 2; } return x; })(1);"
  let interpreter = run_interpreter_outcome(parameter_redecl)
  expect_true(
    interpreter.contains("value:"),
    "parameter redeclaration interpreter completes",
  )
  expect_string(
    run_script_outcome(parameter_redecl),
    interpreter,
    "block var redeclaration of parameter",
  )
  expect_script_value(
    "var x = 1; { let x = 41; } x + 41;", "42", "lexical block shadowing",
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
  expect_value(result, "true", "proxy instanceof result")
}

///|
test "closure conversion evaluates basic object literals" {
  expect_script_value("({ x: 41 }).x + 1;", "42", "basic object literal")
}

///|
test "closure conversion evaluates computed object keys" {
  expect_script_value("({ [\"x\"]: 41 }).x + 1;", "42", "computed object key")
}

///|
test "closure conversion binds this for object function properties" {
  expect_script_value(
    "var obj = { x: 41, getX: function() { return this.x; } }; obj.getX() + 1;",
    "42", "object function property this binding",
  )
}

///|
test "closure conversion binds this for object method shorthand" {
  expect_script_value(
    "var obj = { x: 41, getX() { return this.x; } }; obj.getX() + 1;", "42", "object method shorthand this binding",
  )
}

///|
test "closure conversion reports unsupported object literal accessors" {
  expect_true(
    run_script_outcome("({ get x() { return 1; } }).x;").contains(
      "object literal accessor property",
    ),
    "object literal accessor diagnostic",
  )
}

///|
test "closure conversion reports unsupported object literal spread" {
  expect_true(
    run_script_outcome("({ ...{ x: 1 } }).x;").contains(
      "object literal spread property",
    ),
    "object literal spread diagnostic",
  )
}

///|
test "closure conversion assigns member properties" {
  expect_script_value(
    "var o = { x: 1 }; o.x = 41; o.x + 1;", "42", "member property assignment",
  )
}

///|
test "closure conversion assigns computed properties" {
  expect_script_value(
    "var o = {}; o[\"x\"] = 41; o.x + 1;", "42", "computed property assignment",
  )
}

///|
test "closure conversion updates member properties" {
  expect_script_value("var o = { x: 41 }; o.x++; o.x;", "42", "member update")
}

///|
test "closure conversion preserves postfix member update result" {
  expect_script_value(
    "var o = { x: 41 }; var y = o.x++; y + o.x;", "83", "postfix member update result",
  )
}

///|
test "closure conversion updates computed properties" {
  expect_script_value(
    "var o = { x: 41 }; ++o[\"x\"];", "42", "computed property update",
  )
}

///|
test "closure conversion preserves numeric postfix result" {
  expect_script_value(
    "var x = \"41\"; var y = x++; y + x;", "83", "numeric postfix result",
  )
}

///|
test "closure conversion routes strict member assignment through setters" {
  expect_true(
    run_script_outcome(
      "\"use strict\"; var o = {}; Object.defineProperty(o, \"x\", { value: 1, writable: false }); o.x = 2;",
    ).contains("TypeError"),
    "strict member assignment setter error",
  )
}

///|
test "closure conversion evaluates identifier compound assignment" {
  expect_script_value(
    "var x = 40; x += 2; x;", "42", "identifier compound assignment",
  )
}

///|
test "closure conversion evaluates member compound assignment" {
  expect_script_value(
    "var o = { x: 40 }; o.x += 2; o.x;", "42", "member compound assignment",
  )
}

///|
test "closure conversion evaluates computed compound assignment" {
  expect_script_value(
    "var o = { x: 40 }; o[\"x\"] += 2; o.x;", "42", "computed compound assignment",
  )
}

///|
test "closure conversion evaluates logical assignment" {
  expect_script_value("var x = 0; x ||= 42; x;", "42", "logical assignment")
}

///|
test "closure conversion preserves logical assignment short circuit" {
  expect_script_value(
    "function fail() { throw \"no\"; } var x = 1; x ||= fail(); x;", "1", "logical assignment short circuit",
  )
}

///|
test "closure conversion evaluates member nullish assignment" {
  expect_script_value(
    "var o = { x: null }; o.x ??= 42; o.x;", "42", "member nullish assignment",
  )
}

///|
test "closure conversion preserves computed logical assignment short circuit" {
  expect_script_value(
    "function fail() { throw \"no\"; } var o = { x: 0 }; o[\"x\"] &&= fail(); o.x;",
    "0", "computed logical assignment short circuit",
  )
}

///|
test "closure conversion routes strict compound assignment through setters" {
  expect_true(
    run_script_outcome(
      "\"use strict\"; var o = {}; Object.defineProperty(o, \"x\", { value: 1, writable: false }); o.x += 1;",
    ).contains("TypeError"),
    "strict compound assignment setter error",
  )
}

///|
test "closure conversion evaluates unary numeric expressions" {
  expect_script_value("var x = 1; -x + 43;", "42", "unary numeric expression")
}

///|
test "closure conversion evaluates typeof missing" {
  expect_script_value("typeof missing;", "undefined", "typeof missing")
}

///|
test "closure conversion evaluates void operand effects" {
  expect_script_value(
    "var x = 0; void (x = 42); x;", "42", "void operand effects",
  )
}

///|
test "closure conversion evaluates ternary selected branch only" {
  expect_script_value(
    "function fail() { throw \"no\"; } var x = 0; x ? fail() : 42;", "42", "ternary selected branch",
  )
}

///|
test "closure conversion evaluates comma expressions" {
  expect_script_value("var x = 0; (x = 41, x + 1);", "42", "comma expression")
}

///|
test "closure conversion reports unsupported delete unary" {
  expect_true(
    run_script_outcome("var o = { x: 1 }; delete o.x;").contains(
      "delete unary operator",
    ),
    "delete unary diagnostic",
  )
}

///|
test "closure conversion evaluates while break and continue" {
  expect_script_value(
    "var i = 0; var total = 0; while (i < 10) { i++; if (i % 2 === 0) { continue; } if (i > 7) { break; } total += i; } total;",
    "16", "while break continue",
  )
}

///|
test "closure conversion evaluates do while before condition" {
  expect_script_value(
    "var i = 0; do { i = i + 1; } while (false); i + 41;", "42", "do while before condition",
  )
}

///|
test "closure conversion propagates thrown values" {
  let src = "function fail() { throw \"boom\"; } fail();"
  expect_true(
    run_script_outcome(src) == run_interpreter_outcome(src),
    "thrown value outcome",
  )
}

///|
test "closure conversion constructs function declarations" {
  expect_script_value(
    "function C(x) { this.x = x; } var o = new C(41); o.x + 1;", "42", "function declaration construct",
  )
}

///|
test "closure conversion constructs function expressions" {
  expect_script_value(
    "var o = new (function C(x) { this.x = x; })(41); o.x + 1;", "42", "function expression construct",
  )
}

///|
test "closure conversion Reflect.construct uses newTarget prototype" {
  let src =
    #|function Base() {}
    #|function Other() {}
    #|var calls = 0;
    #|var proto = { marker: 42 };
    #|var NewTarget = new Proxy(Other, { get: function(target, prop, receiver) { if (prop === "prototype") { calls = calls + 1; return proto; } return Reflect.get(target, prop, receiver); } });
    #|var o = Reflect.construct(Base, [], NewTarget);
    #|var PrimitiveProto = new Proxy(Other, { get: function(target, prop, receiver) { if (prop === "prototype") { return 1; } return Reflect.get(target, prop, receiver); } });
    #|var fallback = Reflect.construct(Base, [], PrimitiveProto);
    #|calls + "," + o.marker + "," + (Object.getPrototypeOf(o) === proto) + "," + (Object.getPrototypeOf(fallback) === Object.prototype);
  json_inspect([run_interpreter_outcome(src), run_script_outcome(src)], content=[
    "value:1,42,true,true", "value:1,42,true,true",
  ])
}

///|
test "closure conversion constructs with spread arguments" {
  expect_script_value(
    "function C(a, b) { this.x = a + b; } var args = [40, 1]; var o = new C(...args); o.x + 1;",
    "42", "construct spread arguments",
  )
}

///|
test "closure conversion preserves constructor object return" {
  expect_script_value(
    "function C() { this.x = 1; return { x: 41 }; } var o = new C(); o.x + 1;", "42",
    "constructor object return",
  )
}

///|
test "closure conversion preserves constructor primitive return" {
  expect_script_value(
    "function C() { this.x = 41; return 1; } var o = new C(); o.x + 1;", "42", "constructor primitive return",
  )
}

///|
test "closure conversion keeps method shorthand non-constructable" {
  expect_true(
    run_script_outcome("var o = { m() { return 1; } }; new o.m();").contains(
      "TypeError",
    ),
    "method shorthand construct error",
  )
}

///|
test "closure conversion reports non-constructor errors" {
  expect_true(
    run_script_outcome("new Math();").contains("TypeError"),
    "non-constructor diagnostic",
  )
}

///|
test "closure conversion compiles closure factory program" {
  expect_value(
    run_program(CLOSURE_FACTORY_PROGRAM),
    "500500",
    "closure factory program",
  )
}

///|
test "closure conversion compiles pipeline evaluate program" {
  expect_value(
    run_program(PIPELINE_EXEC_PROGRAM),
    "500500",
    "pipeline evaluate program",
  )
}

///|
test "closure conversion script wrapper hoists function declarations" {
  let src = "var answer = f(); function f() { return 42; } answer;"
  json_inspect([run_interpreter_outcome(src), run_script_outcome(src)], content=[
    "value:42", "value:42",
  ])
}

///|
test "closure conversion script wrapper preserves strict var hoisting" {
  let src = "\"use strict\"; answer = 41; var answer; answer + 1;"
  json_inspect([run_interpreter_outcome(src), run_script_outcome(src)], content=[
    "value:42", "value:42",
  ])
}

///|
test "closure conversion script wrapper validates strict declarations" {
  let src = "\"use strict\"; function f(a, a) { return a; } f(1, 2);"
  expect_true(
    run_script_outcome(src) == run_interpreter_outcome(src),
    "script wrapper strict declaration outcome",
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
  expect_value(compiled(interp), "42", "script wrapper interpreter install")
}

///|
test "closure conversion script wrapper wraps top-level engine errors" {
  expect_string(
    run_script_outcome("missing;"),
    "throw:ReferenceError: missing is not defined",
    "script wrapper top-level error",
  )
}

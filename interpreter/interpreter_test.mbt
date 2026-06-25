///|
using @runtime {type Value}

///|
fn run_js(source : String) -> (Array[String], Value) raise Error {
  let interp = new_interpreter()
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  (interp.host.output, result)
}

///|
fn run_output(source : String) -> Array[String] raise Error {
  let (output, _) = run_js(source)
  output
}

///|
fn run_error_display(source : String) -> String {
  try {
    let _ = run_js(source)
    "no error"
  } catch {
    @runtime.JsException(val) => error_display(val)
    _ => "unexpected error"
  }
}

///|
fn run(source : String) -> Value raise Error {
  let (_, result) = run_js(source)
  result
}

///|
fn run_throws(source : String) -> String {
  try {
    let _ = run_js(source)
    "no error thrown"
  } catch {
    @runtime.JsException(val) => error_display(val)
    e => e.to_string()
  }
}

///|
fn run_output_annex_b(source : String) -> Array[String] raise Error {
  let interp = new_interpreter(annex_b=true)
  let prog = @parser.parse(source)
  let _ = interp.run(prog.stmts)
  interp.host.output
}

///|
/// Run a script and then drain the microtask queue so Promise reactions
/// (`.then` / `.catch` / `.finally`) observe their final state before the
/// test inspects `output`.
fn run_output_async(source : String) -> Array[String] raise Error {
  let interp = new_interpreter()
  let prog = @parser.parse(source)
  let _ = interp.run(prog.stmts)
  interp.run_microtasks()
  interp.host.output
}

///|
fn run_output_timers(source : String) -> Array[String] raise Error {
  let interp = new_interpreter()
  let prog = @parser.parse(source)
  let _ = interp.run(prog.stmts)
  interp.run_timers()
  interp.host.output
}

///|
test "realm_state symbols share legacy interpreter symbols compatibility field" {
  let interp = new_interpreter()
  let sym = interp.realm_state.symbols.new_symbol(Some("stage1"))
  match interp.symbols.get_symbol_by_id(sym.id) {
    Some(found) =>
      if found.description != Some("stage1") {
        fail("expected symbol visible through legacy Interpreter.symbols field")
      }
    None =>
      fail("expected legacy Interpreter.symbols to share RealmState symbols")
  }
}

///|
fn lookup_own_or_proto(val : Value, key : String) -> String {
  let mut cur = val
  for _ in 0..<16 {
    match cur {
      Object(data) =>
        match data.bag.properties.get(key) {
          Some(v) => return v.to_string()
          None => cur = data.prototype
        }
      _ => return ""
    }
  }
  ""
}

///|
fn error_display(val : Value) -> String {
  match val {
    Object(_) => {
      let name = lookup_own_or_proto(val, "name")
      let message = lookup_own_or_proto(val, "message")
      if name.length() > 0 {
        if message.length() > 0 {
          name + ": " + message
        } else {
          name
        }
      } else if message.length() > 0 {
        message
      } else {
        val.to_string()
      }
    }
    _ => val.to_string()
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
fn expect_value_string(
  actual : Value,
  expected : String,
  label : String,
) -> Unit raise Error {
  expect_string(actual.to_string(), expected, label)
}

///|
fn expect_result(actual : Value, expected : String) -> Unit raise Error {
  expect_value_string(actual, expected, "result")
}

///|
fn expect_function_object_prototype(
  label : String,
  value : Value,
  expected : Value,
) -> Unit raise Error {
  match value {
    Object(data) =>
      if !@runtime.strict_equal(data.prototype, expected) {
        fail(label)
      }
    _ => fail(label + " expected function object")
  }
}

///|
fn expect_error_message(actual : String, expected : String) -> Unit raise Error {
  expect_string(actual, expected, "error message")
}

///|
fn expect_error_display(source : String, expected : String) -> Unit raise Error {
  expect_string(run_error_display(source), expected, "error display")
}

///|
fn expect_throw_result(actual : String, expected : String) -> Unit raise Error {
  expect_string(actual, expected, "throw result")
}

///|
fn expect_throw(source : String, expected : String) -> Unit raise Error {
  expect_throw_result(run_throws(source), expected)
}

///|
test "optional chain continuation short-circuits on undefined only" {
  let src =
    #|var a = { b: null };
    #|var hit = 0;
    #|try {
    #|  a?.b.c(hit = 1);
    #|  "no error";
    #|} catch (e) {
    #|  e.message + "," + hit;
    #|}
  expect_result(run(src), "Cannot read properties of null (reading 'c'),0")
}

///|
test "optional chain continuation property null falls through" {
  let src =
    #|var a = { b: null };
    #|try { a?.b.c; } catch (e) { e.message; }
  expect_result(run(src), "Cannot read properties of null (reading 'c')")
}

///|
test "optional chain throws when intermediate property is undefined" {
  let src =
    #|var a = { b: undefined };
    #|try { a?.b.c; } catch (e) { e.message; }
  expect_result(run(src), "Cannot read properties of undefined (reading 'c')")
}

///|
test "optional chain computed key runs when intermediate property is undefined" {
  let src =
    #|var a = { b: undefined };
    #|var hit = 0;
    #|try { a?.b[(hit = 1, "c")]; } catch (e) { e.message + "," + hit; }
  expect_result(run(src), "Cannot read properties of undefined (reading 'c'),1")
}

///|
test "optional chain throws when continuation call returns undefined" {
  let src =
    #|var a = { b: function() {} };
    #|try { a?.b().c; } catch (e) { e.message; }
  expect_result(run(src), "Cannot read properties of undefined (reading 'c')")
}

///|
test "optional chain base short-circuits continuation after call" {
  let src =
    #|var a = null;
    #|a?.b().c;
  expect_result(run(src), "undefined")
}

///|
test "optional chain explicit optional continuation catches null" {
  let src =
    #|var a = { b: null };
    #|a?.b?.c;
  expect_result(run(src), "undefined")
}

///|
test "optional chain base short-circuits plain continuation" {
  let src =
    #|var a = null;
    #|a?.b.c;
  expect_result(run(src), "undefined")
}

///|
test "optional chain base short-circuits plain continuation call arguments" {
  let src =
    #|var a = null;
    #|var hit = 0;
    #|a?.b.c(hit = 1);
    #|hit;
  expect_result(run(src), "0")
}

///|
test "optional chain base short-circuits optional continuation" {
  let src =
    #|var a = null;
    #|a?.b?.c;
  expect_result(run(src), "undefined")
}

///|
test "optional chain continuation preserves object key order" {
  let src =
    #|var log = "";
    #|var xs = [{ x: 5 }];
    #|function obj() { log = log + "o"; return xs; }
    #|function key() { log = log + "k"; return 0; }
    #|var value = obj()?.[key()].x;
    #|log + ":" + value;
  expect_result(run(src), "ok:5")
}

///|
fn expect_first_output(
  output : Array[String],
  expected : String,
) -> Unit raise Error {
  match output {
    [first, ..] => expect_string(first, expected, "first output")
    [] => fail("first output: expected " + expected + ", got no output")
  }
}

///|
test "arithmetic" {
  let (_, result) = run_js("1 + 2 * 3")
  expect_value_string(result, "7", "arithmetic result")
}

///|
test "variables" {
  let (_, result) = run_js("let x = 10; let y = 20; x + y")
  expect_value_string(result, "30", "variables result")
}

///|
test "string concatenation" {
  let (_, result) = run_js("\"hello\" + \" \" + \"world\"")
  expect_value_string(result, "hello world", "string concatenation result")
}

///|
test "console.log" {
  let output = run_output("console.log(\"hello\"); console.log(1 + 2)")
  json_inspect(output, content=["hello", "3"])
}

///|
test "if/else true" {
  let (_, result) = run_js("let x = 10; if (x > 5) { 1 } else { 2 }")
  expect_value_string(result, "1", "if/else true result")
}

///|
test "if/else false" {
  let (_, result) = run_js("let x = 3; if (x > 5) { 1 } else { 2 }")
  expect_value_string(result, "2", "if/else false result")
}

///|
test "while loop" {
  let output = run_output(
    "let i = 0; while (i < 3) { console.log(i); i = i + 1 }",
  )
  json_inspect(output, content=["0", "1", "2"])
}

///|
test "for loop" {
  let output = run_output(
    "for (let i = 0; i < 3; i = i + 1) { console.log(i) }",
  )
  json_inspect(output, content=["0", "1", "2"])
}

///|
test "function declaration and call" {
  let (_, result) = run_js("function add(a, b) { return a + b; } add(3, 4)")
  expect_value_string(result, "7", "function declaration result")
}

///|
test "function body lexical bindings are in TDZ before declaration execution" {
  expect_throw(
    (
      #|var x = 2;
      #|function f() {
      #|  return x;
      #|  let x = 1;
      #|}
      #|f();
    ),
    "ReferenceError: Cannot access 'x' before initialization",
  )
}

///|
test "closure" {
  let src =
    #|function makeCounter() {
    #|  let count = 0;
    #|  return function() { count = count + 1; return count; };
    #|}
    #|let counter = makeCounter();
    #|console.log(counter());
    #|console.log(counter());
    #|console.log(counter());
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "3"])
}

///|
test "recursive fibonacci" {
  let src =
    #|function fib(n) {
    #|  if (n <= 1) { return n; }
    #|  return fib(n - 1) + fib(n - 2);
    #|}
    #|console.log(fib(10));
  let output = run_output(src)
  json_inspect(output, content=["55"])
}

///|
test "ternary expression" {
  let (_, result) = run_js("let x = 5; x > 3 ? \"big\" : \"small\"")
  expect_value_string(result, "big", "ternary expression result")
}

///|
test "typeof" {
  let output = run_output(
    "console.log(typeof 42); console.log(typeof \"hi\"); console.log(typeof true); console.log(typeof null); console.log(typeof undefined)",
  )
  json_inspect(output, content=[
    "number", "string", "boolean", "object", "undefined",
  ])
}

///|
test "break in while" {
  let src =
    #|let i = 0;
    #|while (true) {
    #|  if (i >= 3) { break; }
    #|  console.log(i);
    #|  i = i + 1;
    #|}
  let output = run_output(src)
  json_inspect(output, content=["0", "1", "2"])
}

///|
test "continue in for" {
  let src =
    #|for (let i = 0; i < 5; i = i + 1) {
    #|  if (i === 2 || i === 4) { continue; }
    #|  console.log(i);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["0", "1", "3"])
}

///|
test "const assignment error" {
  let mut err_msg = ""
  try {
    let _ = run_js("const x = 5; x = 10")
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_string(
    err_msg, "TypeError: Assignment to constant variable 'x'", "const assignment error",
  )
}

///|
test "strict equality" {
  let output = run_output(
    "console.log(1 === 1); console.log(1 === 2); console.log(null === undefined)",
  )
  json_inspect(output, content=["true", "false", "false"])
}

///|
test "loose equality null/undefined" {
  let output = run_output(
    "console.log(null == undefined); console.log(undefined == null)",
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "loose equality object valueOf returns primitive" {
  let src =
    #|console.log({valueOf: function() { return 1; }} == 1);
    #|console.log({valueOf: function() { return "hello"; }} == "hello");
    #|console.log(1 == {valueOf: function() { return 1; }});
  let output = run_output(src)
  json_inspect(output, content=["true", "true", "true"])
}

///|
test "loose equality object valueOf called exactly once" {
  let src =
    #|var count = 0;
    #|var obj = { valueOf: function() { count++; return 1; } };
    #|var result = obj == 1;
    #|console.log(result);
    #|console.log(count);
  let output = run_output(src)
  json_inspect(output, content=["true", "1"])
}

///|
test "loose equality toPrimitive throw propagates" {
  let src =
    #|var obj = {};
    #|obj[Symbol.toPrimitive] = function() { throw new Error("bang"); };
    #|try { var r = (obj == 1); console.log("no throw"); } catch(e) { console.log("threw:" + e.message); }
  let output = run_output(src)
  json_inspect(output, content=["threw:bang"])
}

///|
test "logical operators short-circuit" {
  let output = run_output(
    "console.log(false && 42); console.log(true || 42); console.log(0 || \"default\")",
  )
  json_inspect(output, content=["false", "true", "default"])
}

///|
test "unary not" {
  let (_, result) = run_js("!false")
  expect_value_string(result, "true", "unary not result")
}

///|
test "unary minus" {
  let (_, result) = run_js("-5 + 3")
  expect_value_string(result, "-2", "unary minus result")
}

///|
test "nested function scope" {
  let src =
    #|let x = "global";
    #|function outer() {
    #|  let x = "outer";
    #|  function inner() {
    #|    return x;
    #|  }
    #|  return inner();
    #|}
    #|console.log(outer());
  let output = run_output(src)
  json_inspect(output, content=["outer"])
}

///|
test "string and number concatenation" {
  let (_, result) = run_js("\"value: \" + 42")
  expect_value_string(result, "value: 42", "string and number concatenation")
}

///|
test "modulo operator" {
  let (_, result) = run_js("10 % 3")
  expect_value_string(result, "1", "modulo operator result")
}

///|
test "comparison operators" {
  let output = run_output(
    "console.log(1 < 2); console.log(2 > 1); console.log(1 <= 1); console.log(1 >= 2)",
  )
  json_inspect(output, content=["true", "true", "true", "false"])
}

///|
test "string comparison" {
  let output = run_output(
    "console.log(\"a\" < \"b\"); console.log(\"z\" > \"a\"); console.log(\"abc\" <= \"abd\"); console.log(\"x\" >= \"y\")",
  )
  json_inspect(output, content=["true", "true", "true", "false"])
}

///|
test "typeof function" {
  let output = run_output(
    "console.log(typeof function() {}); function foo() {} console.log(typeof foo)",
  )
  json_inspect(output, content=["function", "function"])
}

///|
test "fizzbuzz" {
  let src =
    #|for (let i = 1; i <= 15; i = i + 1) {
    #|  if (i % 15 === 0) { console.log("FizzBuzz"); }
    #|  else if (i % 3 === 0) { console.log("Fizz"); }
    #|  else if (i % 5 === 0) { console.log("Buzz"); }
    #|  else { console.log(i); }
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "1", "2", "Fizz", "4", "Buzz", "Fizz", "7", "8", "Fizz", "Buzz", "11", "Fizz",
    "13", "14", "FizzBuzz",
  ])
}

///|
test "throw/catch basic" {
  let src =
    #|try {
    #|  throw "oops";
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["oops"])
}

///|
test "throw/catch with number" {
  let src =
    #|try {
    #|  throw 42;
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "throw stops execution" {
  let src =
    #|try {
    #|  console.log("before");
    #|  throw "error";
    #|  console.log("after");
    #|} catch (e) {
    #|  console.log("caught: " + e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["before", "caught: error"])
}

///|
test "try/catch/finally" {
  let src =
    #|try {
    #|  throw "err";
    #|} catch (e) {
    #|  console.log("caught");
    #|} finally {
    #|  console.log("finally");
    #|}
  let output = run_output(src)
  json_inspect(output, content=["caught", "finally"])
}

///|
test "finally runs without exception" {
  let src =
    #|try {
    #|  console.log("try");
    #|} catch (e) {
    #|  console.log("catch");
    #|} finally {
    #|  console.log("finally");
    #|}
  let output = run_output(src)
  json_inspect(output, content=["try", "finally"])
}

///|
test "try/finally without catch" {
  let src =
    #|let x = "before";
    #|try {
    #|  x = "inside";
    #|} finally {
    #|  console.log("finally: " + x);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["finally: inside"])
}

///|
test "throw propagates through functions" {
  let src =
    #|function boom() { throw "bang"; }
    #|try {
    #|  boom();
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["bang"])
}

///|
test "nested try/catch" {
  let src =
    #|try {
    #|  try {
    #|    throw "inner";
    #|  } catch (e) {
    #|    console.log("inner: " + e);
    #|    throw "outer";
    #|  }
    #|} catch (e) {
    #|  console.log("outer: " + e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["inner: inner", "outer: outer"])
}

///|
test "uncaught throw is error" {
  let mut err_msg = ""
  try {
    let _ = run_js("throw \"uncaught\"")
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_string(err_msg, "uncaught", "uncaught throw error")
}

///|
test "object literal" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|console.log(o.x + o.y);
  let output = run_output(src)
  json_inspect(output, content=["3"])
}

///|
test "object property assignment" {
  let src =
    #|let o = { x: 1 };
    #|o.x = 42;
    #|console.log(o.x);
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "array literal" {
  let src =
    #|let a = [10, 20, 30];
    #|console.log(a[0]);
    #|console.log(a[1]);
    #|console.log(a[2]);
    #|console.log(a.length);
  let output = run_output(src)
  json_inspect(output, content=["10", "20", "30", "3"])
}

///|
test "array assignment" {
  let src =
    #|let a = [1, 2, 3];
    #|a[1] = 99;
    #|console.log(a[1]);
  let output = run_output(src)
  json_inspect(output, content=["99"])
}

///|
test "computed member access" {
  let src =
    #|let o = { a: 1, b: 2 };
    #|let key = "b";
    #|console.log(o[key]);
  let output = run_output(src)
  json_inspect(output, content=["2"])
}

///|
test "switch statement" {
  let src =
    #|let x = 2;
    #|switch (x) {
    #|  case 1:
    #|    console.log("one");
    #|    break;
    #|  case 2:
    #|    console.log("two");
    #|    break;
    #|  case 3:
    #|    console.log("three");
    #|    break;
    #|}
  let output = run_output(src)
  json_inspect(output, content=["two"])
}

///|
test "switch default" {
  let src =
    #|let x = 99;
    #|switch (x) {
    #|  case 1:
    #|    console.log("one");
    #|    break;
    #|  default:
    #|    console.log("other");
    #|    break;
    #|}
  let output = run_output(src)
  json_inspect(output, content=["other"])
}

///|
test "switch fall-through" {
  let src =
    #|let x = 1;
    #|switch (x) {
    #|  case 1:
    #|    console.log("one");
    #|  case 2:
    #|    console.log("two");
    #|    break;
    #|  case 3:
    #|    console.log("three");
    #|    break;
    #|}
  let output = run_output(src)
  json_inspect(output, content=["one", "two"])
}

///|
test "do-while loop" {
  let src =
    #|let i = 0;
    #|do {
    #|  console.log(i);
    #|  i = i + 1;
    #|} while (i < 3);
  let output = run_output(src)
  json_inspect(output, content=["0", "1", "2"])
}

///|
test "do-while executes at least once" {
  let src =
    #|let i = 10;
    #|do {
    #|  console.log(i);
    #|} while (i < 3);
  let output = run_output(src)
  json_inspect(output, content=["10"])
}

///|
test "for-in object" {
  let src =
    #|let o = { a: 1, b: 2, c: 3 };
    #|let keys = "";
    #|for (let k in o) {
    #|  keys = keys + k;
    #|}
    #|console.log(keys);
  let output = run_output(src)
  json_inspect(output, content=["abc"])
}

///|
test "prefix increment" {
  let src =
    #|let x = 5;
    #|console.log(++x);
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["6", "6"])
}

///|
test "postfix increment" {
  let src =
    #|let x = 5;
    #|console.log(x++);
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["5", "6"])
}

///|
test "prefix decrement" {
  let src =
    #|let x = 5;
    #|console.log(--x);
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["4", "4"])
}

///|
test "compound assignment +=" {
  let src =
    #|let x = 10;
    #|x += 5;
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["15"])
}

///|
test "compound assignment -=" {
  let src =
    #|let x = 10;
    #|x -= 3;
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["7"])
}

///|
test "compound assignment *=" {
  let src =
    #|let x = 4;
    #|x *= 3;
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["12"])
}

///|
test "logical and assign &&= truthy lhs assigns" {
  let output = run_output(
    (
      #|let a = 1;
      #|a &&= 2;
      #|console.log(a);
    ),
  )
  json_inspect(output, content=["2"])
}

///|
test "logical and assign &&= falsy lhs skips" {
  let output = run_output(
    (
      #|let b = 0;
      #|b &&= 2;
      #|console.log(b);
    ),
  )
  json_inspect(output, content=["0"])
}

///|
test "logical and assign &&= member" {
  let output = run_output(
    (
      #|const obj = { x: 10 };
      #|obj.x &&= 20;
      #|console.log(obj.x);
      #|const obj2 = { x: 0 };
      #|obj2.x &&= 20;
      #|console.log(obj2.x);
    ),
  )
  json_inspect(output, content=["20", "0"])
}

///|
test "logical or assign ||= falsy lhs assigns" {
  let output = run_output(
    (
      #|let a = 0;
      #|a ||= 2;
      #|console.log(a);
    ),
  )
  json_inspect(output, content=["2"])
}

///|
test "logical or assign ||= truthy lhs skips" {
  let output = run_output(
    (
      #|let b = 1;
      #|b ||= 2;
      #|console.log(b);
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "nullish assign ??= null lhs assigns" {
  let output = run_output(
    (
      #|let a = null;
      #|a ??= 42;
      #|console.log(a);
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "nullish assign ??= undefined lhs assigns" {
  let output = run_output(
    (
      #|let a = undefined;
      #|a ??= 42;
      #|console.log(a);
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "nullish assign ??= non-null lhs skips" {
  let output = run_output(
    (
      #|let a = 0;
      #|a ??= 42;
      #|console.log(a);
    ),
  )
  json_inspect(output, content=["0"])
}

///|
test "logical and assign computed member key evaluated once" {
  // Verifies ToPropertyKey is called exactly once per spec (not once for get
  // and again for set).
  let output = run_output(
    (
      #|var count = 0;
      #|var key = { toString: function() { count++; return 'x'; } };
      #|var obj = {};
      #|obj[key] = 10;
      #|obj[key] &&= 20;
      #|console.log(count);
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["2", "20"])
}

///|
test "logical or assign computed member key evaluated once" {
  let output = run_output(
    (
      #|var count = 0;
      #|var key = { toString: function() { count++; return 'x'; } };
      #|var obj = {};
      #|obj[key] = 0;
      #|obj[key] ||= 20;
      #|console.log(count);
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["2", "20"])
}

///|
test "nullish assign computed member key evaluated once" {
  let output = run_output(
    (
      #|var count = 0;
      #|var key = { toString: function() { count++; return 'x'; } };
      #|var obj = {};
      #|obj[key] = null;
      #|obj[key] ??= 20;
      #|console.log(count);
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["2", "20"])
}

///|
test "logical and assign computed member Symbol key" {
  // Verifies the Symbol branch of ToPropertyKey: a Symbol key passes through
  // as-is without string conversion.
  let output = run_output(
    (
      #|var sym = Symbol("k");
      #|var obj = {};
      #|obj[sym] = 10;
      #|obj[sym] &&= 20;
      #|console.log(obj[sym]);
    ),
  )
  json_inspect(output, content=["20"])
}

///|
test "bitwise AND" {
  let (_, result) = run_js("12 & 10")
  expect_value_string(result, "8", "bitwise AND result")
}

///|
test "bitwise OR" {
  let (_, result) = run_js("12 | 10")
  expect_value_string(result, "14", "bitwise OR result")
}

///|
test "bitwise XOR" {
  let (_, result) = run_js("12 ^ 10")
  expect_value_string(result, "6", "bitwise XOR result")
}

///|
test "bitwise NOT" {
  let (_, result) = run_js("~0")
  expect_value_string(result, "-1", "bitwise NOT result")
}

///|
test "left shift" {
  let (_, result) = run_js("1 << 4")
  expect_value_string(result, "16", "left shift result")
}

///|
test "right shift" {
  let (_, result) = run_js("-16 >> 2")
  expect_value_string(result, "-4", "right shift result")
}

///|
test "unsigned right shift" {
  let (_, result) = run_js("-1 >>> 0")
  expect_value_string(result, "4294967295", "unsigned right shift result")
}

///|
test "void operator" {
  let (_, result) = run_js("void 0")
  expect_value_string(result, "undefined", "void operator result")
}

///|
test "void expression" {
  let output = run_output("console.log(void 0 === undefined)")
  json_inspect(output, content=["true"])
}

///|
test "delete property" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|delete o.x;
    #|console.log(o.x);
  let output = run_output(src)
  json_inspect(output, content=["undefined"])
}

///|
test "in operator" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|console.log("x" in o);
    #|console.log("z" in o);
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "Stage B.3: Proxy has trap through in and Reflect.has" {
  let src =
    #|var seen = [];
    #|var target = {};
    #|var handler = {
    #|  has: function(t, prop) {
    #|    seen.push(this === handler);
    #|    seen.push(t === target);
    #|    seen.push(prop);
    #|    return prop === "x";
    #|  }
    #|};
    #|var p = new Proxy(target, handler);
    #|console.log("x" in p);
    #|console.log("y" in p);
    #|console.log(Reflect.has(p, "x"));
    #|console.log(seen.join(","));
  let output = run_output(src)
  json_inspect(output, content=[
    "true", "false", "true", "true,true,x,true,true,y,true,true,x",
  ])
}

///|
test "Stage B.3: Proxy has trap via prototype and with" {
  let src =
    #|var log = [];
    #|var target = {};
    #|var handler = {
    #|  has: function(t, prop) {
    #|    log.push(prop);
    #|    return prop === "1" || prop === "attr";
    #|  },
    #|  get: function(t, prop) {
    #|    if (prop === "attr") return 42;
    #|  }
    #|};
    #|var proxy = new Proxy(target, handler);
    #|var arr = [];
    #|Object.setPrototypeOf(arr, proxy);
    #|console.log(1 in arr);
    #|with (proxy) { console.log(attr); }
    #|console.log(log.join(","));
  let output = run_output(src)
  json_inspect(output, content=["true", "42", "1,attr"])
}

///|
test "Stage B.3: Proxy prototype ordinary get and with has abrupt completion" {
  let src =
    #|function f() {}
    #|console.log("call" in f);
    #|console.log(Reflect.has(f, "bind"));
    #|var target = { x: 1 };
    #|var p = new Proxy(target, {});
    #|var o = {};
    #|Object.setPrototypeOf(o, p);
    #|console.log(o.x);
    #|var a = [];
    #|var arrayProto = { x: 2 };
    #|Object.setPrototypeOf(a, arrayProto);
    #|console.log("x" in a);
    #|console.log(a.x);
    #|console.log(a.map === undefined);
    #|console.log(Object.getPrototypeOf(a) === arrayProto);
    #|console.log(Reflect.getPrototypeOf(a) === arrayProto);
    #|var reflectProto = { y: 3 };
    #|console.log(Reflect.setPrototypeOf(a, reflectProto));
    #|console.log(Object.getPrototypeOf(a) === reflectProto);
    #|console.log(a.y);
    #|var proxiedArray = new Proxy(a, {});
    #|console.log(Object.getPrototypeOf(proxiedArray) === reflectProto);
    #|var receiverProxy = new Proxy({}, {
    #|  get: function(t, prop, receiver) {
    #|    if (prop === "marker") return "target";
    #|    if (prop === "seen") return receiver.marker;
    #|  }
    #|});
    #|var child = { marker: "receiver" };
    #|Object.setPrototypeOf(child, receiverProxy);
    #|console.log(child.seen);
    #|var protoProxy = new Proxy({}, {
    #|  has: function(t, prop) { return prop === "inherited"; },
    #|  get: function(t, prop) {
    #|    if (prop === "inherited") return 9;
    #|  }
    #|});
    #|var withHost = {};
    #|Object.setPrototypeOf(withHost, protoProxy);
    #|with (withHost) {
    #|  console.log(typeof inherited);
    #|  console.log(inherited);
    #|}
    #|var throwing = new Proxy({}, {
    #|  has: function() { throw "boom"; }
    #|});
    #|try {
    #|  with (throwing) { console.log(typeof missing); }
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "true", "true", "1", "true", "2", "true", "true", "true", "true", "true", "3",
    "true", "receiver", "number", "9", "boom",
  ])
}

///|
// Reflect.ownKeys is defined for any object (§28.1.11, arg passes IsObject).
// Map, Set, and Promise are exotic objects: Reflect.ownKeys must return their
// own-key list, not reject with a TypeError. A fresh Map/Set and Promise have
// no own keys; own properties created by assignment or defineProperty surface
// in order.
test "Reflect.ownKeys on Map/Set/Promise instances" {
  let src =
    #|console.log(JSON.stringify(Reflect.ownKeys(new Map())));
    #|console.log(JSON.stringify(Reflect.ownKeys(new Set())));
    #|var p = Promise.resolve(1);
    #|console.log(JSON.stringify(Reflect.ownKeys(p)));
    #|console.log(JSON.stringify(Object.getOwnPropertyNames(p)));
    #|console.log(p.constructor === Promise);
    #|console.log(p.hasOwnProperty("constructor"));
    #|var m = new Map();
    #|m.extra = 1;
    #|console.log(m.extra);
    #|console.log(JSON.stringify(Reflect.ownKeys(m)));
    #|var s = new Set();
    #|s.extra = 1;
    #|console.log(s.extra);
    #|console.log(JSON.stringify(Reflect.ownKeys(s)));
    #|var m2 = new Map();
    #|Object.defineProperty(m2, "extra", { value: 1, enumerable: true });
    #|console.log(JSON.stringify(Reflect.ownKeys(m2)));
  let output = run_output(src)
  json_inspect(output, content=[
    "[]", "[]", "[]", "[]", "true", "false", "1", "[\"extra\"]", "1", "[\"extra\"]",
    "[\"extra\"]",
  ])
}

///|
test "Map/Set assignment respects inherited prototype property blockers" {
  let src =
    #|try {
    #|Object.defineProperty(Map.prototype, "__t447_getter", {
    #|  get: function() { return 1; },
    #|  configurable: true
    #|});
    #|var m = new Map();
    #|m.__t447_getter = 2;
    #|console.log(m.__t447_getter);
    #|console.log(JSON.stringify(Reflect.ownKeys(m)));
    #|var mBracket = new Map();
    #|mBracket["__t447_getter"] = 2;
    #|console.log(mBracket.__t447_getter);
    #|console.log(JSON.stringify(Reflect.ownKeys(mBracket)));
    #|try {
    #|  (function() { "use strict"; var sm = new Map(); sm.__t447_getter = 2; })();
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  (function() { "use strict"; var key = "__t447_getter"; var sm = new Map(); sm[key] = 2; })();
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|delete Map.prototype.__t447_getter;
    #|Object.defineProperty(Set.prototype, "__t447_data", {
    #|  value: 1,
    #|  writable: false,
    #|  configurable: true
    #|});
    #|var s = new Set();
    #|s.__t447_data = 2;
    #|console.log(s.__t447_data);
    #|console.log(JSON.stringify(Reflect.ownKeys(s)));
    #|var sBracket = new Set();
    #|sBracket["__t447_data"] = 2;
    #|console.log(sBracket.__t447_data);
    #|console.log(JSON.stringify(Reflect.ownKeys(sBracket)));
    #|try {
    #|  (function() { "use strict"; var ss = new Set(); ss.__t447_data = 2; })();
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  (function() { "use strict"; var key = "__t447_data"; var ss = new Set(); ss[key] = 2; })();
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|delete Set.prototype.__t447_data;
    #|var seen;
    #|Object.defineProperty(Map.prototype, "__t447_setter", {
    #|  set: function(v) { seen = this instanceof Map ? v : "bad"; },
    #|  configurable: true
    #|});
    #|var m2 = new Map();
    #|m2.__t447_setter = 9;
    #|console.log(seen);
    #|console.log(JSON.stringify(Reflect.ownKeys(m2)));
    #|var m3 = new Map();
    #|m3["__t447_setter"] = 10;
    #|console.log(seen);
    #|console.log(JSON.stringify(Reflect.ownKeys(m3)));
    #|} finally {
    #|  delete Map.prototype.__t447_getter;
    #|  delete Set.prototype.__t447_data;
    #|  delete Map.prototype.__t447_setter;
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "1", "[]", "1", "[]", "TypeError", "TypeError", "1", "[]", "1", "[]", "TypeError",
    "TypeError", "9", "[]", "10", "[]",
  ])
}

///|
test "Map/Set symbol Reflect.set respects target blockers before receiver landing" {
  let src =
    #|var mapSym = Symbol("map");
    #|var setSym = Symbol("set");
    #|var inheritedSym = Symbol("inherited");
    #|var receiver = {};
    #|
    #|var m = new Map();
    #|Object.defineProperty(m, mapSym, {
    #|  get: function() { return 1; },
    #|  configurable: true
    #|});
    #|console.log(Reflect.set(m, mapSym, 2, receiver));
    #|console.log(receiver[mapSym]);
    #|console.log(m[mapSym]);
    #|
    #|var s = new Set();
    #|Object.defineProperty(s, setSym, {
    #|  value: 1,
    #|  writable: false,
    #|  configurable: true
    #|});
    #|console.log(Reflect.set(s, setSym, 2, receiver));
    #|console.log(receiver[setSym]);
    #|console.log(s[setSym]);
    #|
    #|var proto = {};
    #|Object.defineProperty(proto, inheritedSym, {
    #|  get: function() { return 3; },
    #|  configurable: true
    #|});
    #|class M extends Map {}
    #|Object.setPrototypeOf(M.prototype, proto);
    #|var m2 = new M();
    #|console.log(Reflect.set(m2, inheritedSym, 4, receiver));
    #|console.log(receiver[inheritedSym]);
    #|console.log(m2[inheritedSym]);
  let output = run_output(src)
  json_inspect(output, content=[
    "false", "undefined", "1", "false", "undefined", "1", "false", "undefined", "undefined",
  ])
}

///|
test "Map/Set assignment stops at inherited array own descriptors" {
  let src =
    #|var hits = [];
    #|var higher = {};
    #|Object.defineProperty(higher, "0", {
    #|  set: function(v) { hits.push("zero:" + v); },
    #|  configurable: true
    #|});
    #|Object.defineProperty(higher, "length", {
    #|  set: function(v) { hits.push("length:" + v); },
    #|  configurable: true
    #|});
    #|var arrayProto = [42];
    #|Object.setPrototypeOf(arrayProto, higher);
    #|class M extends Map {}
    #|Object.setPrototypeOf(M.prototype, Object.create(arrayProto));
    #|var m = new M();
    #|m[0] = 7;
    #|m.length = 8;
    #|console.log(JSON.stringify(hits));
    #|console.log(m[0]);
    #|console.log(m.length);
    #|console.log(JSON.stringify(Reflect.ownKeys(m)));
    #|class S extends Set {}
    #|Object.setPrototypeOf(S.prototype, Object.create(arrayProto));
    #|var s = new S();
    #|s[0] = 9;
    #|s.length = 10;
    #|console.log(JSON.stringify(hits));
    #|console.log(s[0]);
    #|console.log(s.length);
    #|console.log(JSON.stringify(Reflect.ownKeys(s)));
  let output = run_output(src)
  json_inspect(output, content=[
    "[]", "7", "8", "[\"0\",\"length\"]", "[]", "9", "10", "[\"0\",\"length\"]",
  ])
}

///|
test "Map/Set assignment walks Promise prototype fallback" {
  let src =
    #|try {
    #|  var hits = [];
    #|  Object.defineProperty(Promise.prototype, "__t449_promise_setter", {
    #|    set: function(v) { hits.push(this === activeMap ? "map:" + v : "bad"); },
    #|    configurable: true
    #|  });
    #|  Object.defineProperty(Promise.prototype, "__t449_promise_blocker", {
    #|    get: function() { return 5; },
    #|    configurable: true
    #|  });
    #|  var promiseProto = Promise.resolve(0);
    #|  class M extends Map {}
    #|  Object.setPrototypeOf(M.prototype, Object.create(promiseProto));
    #|  var activeMap = new M();
    #|  activeMap.__t449_promise_setter = 7;
    #|  console.log(JSON.stringify(hits));
    #|  console.log(JSON.stringify(Reflect.ownKeys(activeMap)));
    #|
    #|  class S extends Set {}
    #|  Object.setPrototypeOf(S.prototype, Object.create(promiseProto));
    #|  var s = new S();
    #|  s.__t449_promise_blocker = 9;
    #|  console.log(JSON.stringify(Reflect.ownKeys(s)));
    #|  try {
    #|    (function() {
    #|      "use strict";
    #|      var strictSet = new S();
    #|      strictSet.__t449_promise_blocker = 10;
    #|    })();
    #|  } catch (e) {
    #|    console.log(e.name);
    #|  }
    #|} finally {
    #|  delete Promise.prototype.__t449_promise_setter;
    #|  delete Promise.prototype.__t449_promise_blocker;
    #|}
  let output = run_output(src)
  json_inspect(output, content=["[\"map:7\"]", "[]", "[]", "TypeError"])
}

///|
test "Annex B __proto__ setter ignores primitive prototype values" {
  let src =
    #|var obj = {};
    #|var original = Object.getPrototypeOf(obj);
    #|obj.__proto__ = 1;
    #|console.log(Object.getPrototypeOf(obj) === original);
    #|var setter = Object.getOwnPropertyDescriptor(Object.prototype, "__proto__").set;
    #|console.log(setter.call(obj, "x") === undefined);
    #|console.log(Object.getPrototypeOf(obj) === original);
    #|var trapCalled = false;
    #|var proxy = new Proxy({}, {
    #|  setPrototypeOf: function() {
    #|    trapCalled = true;
    #|    return false;
    #|  }
    #|});
    #|console.log(setter.call(proxy, 1) === undefined);
    #|console.log(trapCalled);
  let output = run_output(src)
  json_inspect(output, content=["true", "true", "true", "true", "false"])
}

///|
test "Annex B __proto__ setter updates Map and Set receivers" {
  let src =
    #|var mProto = { marker: 11 };
    #|var m = new Map();
    #|m.__proto__ = mProto;
    #|console.log(Object.getPrototypeOf(m) === mProto);
    #|console.log(m.marker);
    #|console.log(JSON.stringify(Reflect.ownKeys(m)));
    #|
    #|var sProto = { marker: 22 };
    #|var s = new Set();
    #|s["__proto__"] = sProto;
    #|console.log(Object.getPrototypeOf(s) === sProto);
    #|console.log(s.marker);
    #|console.log(JSON.stringify(Reflect.ownKeys(s)));
    #|
    #|var setter = Object.getOwnPropertyDescriptor(Object.prototype, "__proto__").set;
    #|var directProto = { marker: 33 };
    #|var direct = new Map();
    #|console.log(setter.call(direct, directProto) === undefined);
    #|console.log(Object.getPrototypeOf(direct) === directProto);
    #|console.log(direct.marker);
    #|
    #|var unchanged = Object.getPrototypeOf(new Set());
    #|var ignored = new Set();
    #|ignored.__proto__ = 1;
    #|console.log(Object.getPrototypeOf(ignored) === unchanged);
  let output = run_output(src)
  json_inspect(output, content=[
    "true", "11", "[]", "true", "22", "[]", "true", "true", "33", "true",
  ])
}

///|
test "comma expression" {
  let (_, result) = run_js("1, 2, 3")
  expect_value_string(result, "3", "comma expression result")
}

///|
test "typeof undeclared variable" {
  let (_, result) = run_js("typeof nonExistent")
  expect_value_string(result, "undefined", "typeof undeclared variable result")
}

///|
test "new expression" {
  let src =
    #|function Person(name) {
    #|  this.name = name;
    #|}
    #|let p = new Person("Alice");
    #|console.log(p.name);
  let output = run_output(src)
  json_inspect(output, content=["Alice"])
}

///|
test "new expression with method" {
  let src =
    #|function Counter(start) {
    #|  this.count = start;
    #|  this.inc = function() {
    #|    this.count = this.count + 1;
    #|    return this.count;
    #|  };
    #|}
    #|let c = new Counter(0);
    #|console.log(c.inc());
    #|console.log(c.inc());
  let output = run_output(src)
  json_inspect(output, content=["1", "2"])
}

///|
test "method call this binding" {
  let src =
    #|let obj = { x: 42, getX: function() { return this.x; } };
    #|console.log(obj.getX());
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "string length" {
  let (_, result) = run_js("\"hello\".length")
  expect_value_string(result, "5", "string length result")
}

///|
test "for loop with ++" {
  let src =
    #|for (let i = 0; i < 3; i++) {
    #|  console.log(i);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["0", "1", "2"])
}

///|
test "type coercion arithmetic" {
  let output = run_output(
    "console.log(true + 1); console.log(null + 1); console.log(false + false)",
  )
  json_inspect(output, content=["2", "1", "0"])
}

///|
test "neg coercion" {
  let (_, result) = run_js("-true")
  expect_value_string(result, "-1", "neg coercion result")
}

// ===== Task 1G: Built-in Globals =====

///|
test "NaN global" {
  let out = run_output("console.log(NaN)")
  expect_string(out[0], "NaN", "NaN global output")
}

///|
test "Infinity global" {
  let out = run_output("console.log(Infinity)")
  expect_string(out[0], "Infinity", "Infinity global output")
}

///|
test "undefined global" {
  let (_, result) = run_js("undefined")
  expect_value_string(result, "undefined", "undefined global result")
}

///|
test "isNaN true" {
  let (_, result) = run_js("isNaN(NaN)")
  expect_value_string(result, "true", "isNaN true result")
}

///|
test "isNaN false" {
  let (_, result) = run_js("isNaN(42)")
  expect_value_string(result, "false", "isNaN false result")
}

///|
test "isNaN string coercion" {
  let (_, result) = run_js("isNaN(\"hello\")")
  expect_value_string(result, "true", "isNaN string coercion result")
}

///|
test "isNaN numeric string" {
  let (_, result) = run_js("isNaN(\"123\")")
  expect_value_string(result, "false", "isNaN numeric string result")
}

///|
test "isFinite true" {
  let (_, result) = run_js("isFinite(42)")
  expect_value_string(result, "true", "isFinite true result")
}

///|
test "isFinite infinity" {
  let (_, result) = run_js("isFinite(Infinity)")
  expect_value_string(result, "false", "isFinite infinity result")
}

///|
test "isFinite NaN" {
  let (_, result) = run_js("isFinite(NaN)")
  expect_value_string(result, "false", "isFinite NaN result")
}

///|
test "parseInt basic" {
  let (_, result) = run_js("parseInt(\"42\")")
  expect_value_string(result, "42", "parseInt basic result")
}

///|
test "parseInt with leading text stops" {
  let (_, result) = run_js("parseInt(\"123abc\")")
  expect_value_string(result, "123", "parseInt with leading text stops result")
}

///|
test "parseInt hex" {
  let (_, result) = run_js("parseInt(\"0xFF\")")
  expect_value_string(result, "255", "parseInt hex result")
}

///|
test "parseInt radix" {
  let (_, result) = run_js("parseInt(\"111\", 2)")
  expect_value_string(result, "7", "parseInt radix result")
}

///|
test "parseInt negative" {
  let (_, result) = run_js("parseInt(\"-42\")")
  expect_value_string(result, "-42", "parseInt negative result")
}

///|
test "parseInt NaN for non-numeric" {
  let out = run_output("console.log(parseInt(\"hello\"))")
  expect_string(out[0], "NaN", "parseInt NaN for non-numeric output")
}

///|
test "parseInt empty string" {
  let out = run_output("console.log(parseInt(\"\"))")
  expect_string(out[0], "NaN", "parseInt empty string output")
}

///|
test "parseFloat basic" {
  let (_, result) = run_js("parseFloat(\"3.14\")")
  expect_value_string(result, "3.14", "parseFloat basic result")
}

///|
test "parseFloat integer" {
  let (_, result) = run_js("parseFloat(\"42\")")
  expect_value_string(result, "42", "parseFloat integer result")
}

///|
test "parseFloat with trailing text" {
  let (_, result) = run_js("parseFloat(\"3.14abc\")")
  expect_value_string(result, "3.14", "parseFloat with trailing text result")
}

///|
test "parseFloat NaN" {
  let out = run_output("console.log(parseFloat(\"hello\"))")
  expect_string(out[0], "NaN", "parseFloat NaN output")
}

///|
test "String conversion number" {
  let (_, result) = run_js("String(42)")
  expect_value_string(result, "42", "String conversion number result")
}

///|
test "String conversion bool" {
  let (_, result) = run_js("String(true)")
  expect_value_string(result, "true", "String conversion bool result")
}

///|
test "String conversion null" {
  let (_, result) = run_js("String(null)")
  expect_value_string(result, "null", "String conversion null result")
}

///|
test "String conversion undefined" {
  let (_, result) = run_js("String(undefined)")
  expect_value_string(result, "undefined", "String conversion undefined result")
}

///|
test "Number conversion string" {
  let (_, result) = run_js("Number(\"42\")")
  expect_value_string(result, "42", "Number conversion string result")
}

///|
test "Number conversion true" {
  let (_, result) = run_js("Number(true)")
  expect_value_string(result, "1", "Number conversion true result")
}

///|
test "Number conversion false" {
  let (_, result) = run_js("Number(false)")
  expect_value_string(result, "0", "Number conversion false result")
}

///|
test "Number conversion null" {
  let (_, result) = run_js("Number(null)")
  expect_value_string(result, "0", "Number conversion null result")
}

///|
test "Number conversion non-numeric string" {
  let out = run_output("console.log(Number(\"hello\"))")
  expect_string(out[0], "NaN", "Number conversion non-numeric string output")
}

///|
test "Boolean truthy" {
  let (_, result) = run_js("Boolean(1)")
  expect_value_string(result, "true", "Boolean truthy result")
}

///|
test "Boolean falsy zero" {
  let (_, result) = run_js("Boolean(0)")
  expect_value_string(result, "false", "Boolean falsy zero result")
}

///|
test "Boolean empty string" {
  let (_, result) = run_js("Boolean(\"\")")
  expect_value_string(result, "false", "Boolean empty string result")
}

///|
test "Boolean non-empty string" {
  let (_, result) = run_js("Boolean(\"hello\")")
  expect_value_string(result, "true", "Boolean non-empty string result")
}

///|
test "Boolean null" {
  let (_, result) = run_js("Boolean(null)")
  expect_value_string(result, "false", "Boolean null result")
}

///|
test "new Error" {
  let src =
    #|var e = new Error("something went wrong");
    #|console.log(e.message);
  let out = run_output(src)
  expect_string(out[0], "something went wrong", "new Error message")
}

///|
test "new TypeError" {
  let src =
    #|var e = new TypeError("bad type");
    #|console.log(e.name);
  let out = run_output(src)
  expect_string(out[0], "TypeError", "new TypeError name")
}

///|
test "new RangeError" {
  let src =
    #|var e = new RangeError("out of range");
    #|console.log(e.message);
  let out = run_output(src)
  expect_string(out[0], "out of range", "new RangeError message")
}

///|
test "throw and catch Error" {
  let src =
    #|try {
    #|  throw new Error("oops");
    #|} catch (e) {
    #|  console.log(e.message);
    #|}
  let out = run_output(src)
  expect_string(out[0], "oops", "throw and catch Error message")
}

///|
test "Error name property" {
  let src =
    #|var e = new Error("test");
    #|console.log(e.name);
  let out = run_output(src)
  expect_string(out[0], "Error", "Error name property")
}

///|
test "Error no args" {
  let src =
    #|var e = new Error();
    #|console.log(e.message);
  let out = run_output(src)
  expect_string(out[0], "", "Error no args message")
}

///|
test "parseInt with whitespace" {
  let (_, result) = run_js("parseInt(\"  42  \")")
  expect_value_string(result, "42", "parseInt with whitespace result")
}

///|
test "parseInt hex with radix 16" {
  let (_, result) = run_js("parseInt(\"ff\", 16)")
  expect_value_string(result, "255", "parseInt hex with radix 16 result")
}

///|
test "parseFloat negative" {
  let (_, result) = run_js("parseFloat(\"-3.14\")")
  expect_value_string(result, "-3.14", "parseFloat negative result")
}

///|
test "typeof NaN" {
  let (_, result) = run_js("typeof NaN")
  expect_value_string(result, "number", "typeof NaN result")
}

///|
test "typeof Infinity" {
  let (_, result) = run_js("typeof Infinity")
  expect_value_string(result, "number", "typeof Infinity result")
}

///|
test "NaN not equal to itself" {
  let (_, result) = run_js("NaN === NaN")
  expect_value_string(result, "false", "NaN not equal to itself result")
}

///|
test "Infinity arithmetic" {
  let out = run_output("console.log(Infinity + 1)")
  expect_string(out[0], "Infinity", "Infinity arithmetic output")
}

///|
test "negative Infinity" {
  let out = run_output("console.log(-Infinity)")
  expect_string(out[0], "-Infinity", "negative Infinity output")
}

// ===== Phase 1 Known Issue Fixes =====

// Issue 1: to_int32 spec compliance

///|
test "to_int32 wrapping large positive" {
  let (_, result) = run_js("2147483648 | 0")
  expect_value_string(result, "-2147483648", "to_int32 large positive result")
}

///|
test "to_int32 wrapping large negative" {
  let (_, result) = run_js("-2147483649 | 0")
  expect_value_string(result, "2147483647", "to_int32 large negative result")
}

///|
test "to_int32 wrapping 4294967296" {
  let (_, result) = run_js("4294967296 | 0")
  expect_value_string(result, "0", "to_int32 4294967296 result")
}

// Issue 5: parseFloat improvements

///|
test "parseFloat leading dot" {
  let (_, result) = run_js("parseFloat(\".5\")")
  expect_value_string(result, "0.5", "parseFloat leading dot result")
}

///|
test "parseFloat exponent" {
  let (_, result) = run_js("parseFloat(\"1e2\")")
  expect_value_string(result, "100", "parseFloat exponent result")
}

///|
test "parseFloat Infinity" {
  let (_, result) = run_js("parseFloat(\"Infinity\")")
  expect_value_string(result, "Infinity", "parseFloat Infinity result")
}

///|
test "parseFloat negative Infinity" {
  let (_, result) = run_js("parseFloat(\"-Infinity\")")
  expect_value_string(
    result, "-Infinity", "parseFloat negative Infinity result",
  )
}

// Issue 2: Error prototype chain (instanceof)

///|
test "new Error instanceof Error" {
  let (_, result) = run_js("new Error() instanceof Error")
  expect_value_string(result, "true", "new Error instanceof Error result")
}

///|
test "new TypeError instanceof TypeError" {
  let (_, result) = run_js("new TypeError(\"bad\") instanceof TypeError")
  expect_value_string(
    result, "true", "new TypeError instanceof TypeError result",
  )
}

// Issue 3: for-in prototype chain

///|
test "for-in prototype chain" {
  let src =
    #|function Base() { this.a = 1; }
    #|Base.prototype.b = 2;
    #|var obj = new Base();
    #|var keys = "";
    #|for (var k in obj) { keys = keys + k; }
    #|console.log(keys);
  let output = run_output(src)
  json_inspect(output, content=["ab"])
}

// Issue 6: double evaluation in update/compound-assign

///|
test "update member single evaluation" {
  let src =
    #|var counter = 0;
    #|function getSide() { counter++; return { x: 10 }; }
    #|var obj = getSide();
    #|obj.x++;
    #|console.log(counter);
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["1", "11"])
}

///|
test "compound assign member single evaluation" {
  let src =
    #|var obj = { x: 10 };
    #|obj.x += 5;
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["15"])
}

// Issue 4: labeled break/continue

///|
test "labeled break" {
  let src =
    #|var result = "";
    #|outer: for (var i = 0; i < 3; i++) {
    #|  for (var j = 0; j < 3; j++) {
    #|    if (j === 1) break outer;
    #|    result = result + i + "" + j + ",";
    #|  }
    #|}
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["00,"])
}

///|
test "labeled continue" {
  let src =
    #|var result = "";
    #|outer: for (var i = 0; i < 3; i++) {
    #|  for (var j = 0; j < 3; j++) {
    #|    if (j === 1) continue outer;
    #|    result = result + i + "" + j + ",";
    #|  }
    #|}
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["00,10,20,"])
}

// ====== Phase 2: Template Literals ======

///|
test "template literal no interpolation" {
  let (_, result) = run_js("`hello world`")
  expect_value_string(
    result, "hello world", "template literal no interpolation result",
  )
}

///|
test "template literal with interpolation" {
  let (_, result) = run_js("let x = 42; `the answer is ${x}`")
  expect_value_string(
    result, "the answer is 42", "template literal interpolation result",
  )
}

///|
test "template literal multiple interpolations" {
  let (_, result) = run_js("let a = 1; let b = 2; `${a} + ${b} = ${a + b}`")
  expect_value_string(
    result, "1 + 2 = 3", "template literal multiple interpolation result",
  )
}

///|
test "template literal with expressions" {
  let (_, result) = run_js("`result: ${2 * 3 + 1}`")
  expect_value_string(result, "result: 7", "template literal expression result")
}

///|
test "template literal nested braces" {
  let src =
    #|var obj = {a: 1};
    #|`value: ${obj.a}`
  let (_, result) = run_js(src)
  expect_value_string(
    result, "value: 1", "template literal nested braces result",
  )
}

///|
test "template literal escape sequences" {
  let (_, result) = run_js("`line1\\nline2`")
  expect_value_string(
    result, "line1\nline2", "template literal escape sequence result",
  )
}

///|
test "template literal empty" {
  let (_, result) = run_js("``")
  expect_value_string(result, "", "template literal empty result")
}

///|
test "template literal used in console.log" {
  let src =
    #|var name = "World";
    #|console.log(`Hello, ${name}!`);
  let output = run_output(src)
  json_inspect(output, content=["Hello, World!"])
}

///|
test "template literal invalid legacy octal escape throws SyntaxError" {
  expect_throw(
    "`\\1`", "SyntaxError: Invalid escape sequence in template literal at line 1, col 1",
  )
}

///|
test "template literal invalid escape throws SyntaxError in strict mode" {
  let src =
    #|"use strict";
    #|`\8`
  expect_throw(
    src, "SyntaxError: Invalid escape sequence in template literal at line 2, col 1",
  )
}

///|
test "invalid template in function parameter default throws SyntaxError" {
  let src =
    #|function f(a = `\1`) {}
  expect_throw(
    src, "SyntaxError: Invalid escape sequence in template literal at line 1, col 16",
  )
}

///|
test "invalid template in arrow function parameter default throws SyntaxError" {
  let src =
    #|(a = `\1`) => a;
  expect_throw(
    src, "SyntaxError: Invalid escape sequence in template literal at line 1, col 6",
  )
}

///|
test "invalid template in destructuring parameter default throws SyntaxError" {
  let src =
    #|function f({a = `\1`} = {}) {}
  expect_throw(
    src, "SyntaxError: Invalid escape sequence in template literal at line 1, col 17",
  )
}

///|
test "tagged template cooked is undefined for invalid escape" {
  let src =
    #|function tag(s) { return typeof s[0]; }
    #|tag`\1`;
  let (_, result) = run_js(src)
  expect_value_string(
    result, "undefined", "cooked of invalid escape should be undefined",
  )
}

///|
test "tagged template raw preserves backslash for invalid escape" {
  let src =
    #|function tag(s) { return s.raw[0]; }
    #|tag`\1`;
  let (_, result) = run_js(src)
  expect_value_string(result, "\\1", "raw should preserve literal \\1")
}

///|
test "tagged template raw and cooked for valid escape" {
  let src =
    #|function tag(s) { return s[0] + '|' + s.raw[0]; }
    #|tag`\n`;
  let (_, result) = run_js(src)
  expect_value_string(result, "\n|\\n", "cooked is newline, raw is backslash-n")
}

///|
test "tagged template raw preserves backslash in line continuation" {
  let src =
    #|function tag(s) { return s[0] + '|' + s.raw[0]; }
    #|tag`a\
    #|b`;
  let (_, result) = run_js(src)
  expect_value_string(
    result, "ab|a\\\nb", "cooked removes continuation, raw keeps backslash+newline",
  )
}

///|
test "tagged template raw preserves LS U+2028 in line continuation" {
  // U+2028 (LS) is a line terminator but does NOT normalize to \n in raw
  let src = "function tag(s) { return s[0] + '|' + s.raw[0]; }\ntag`a\\\u{2028}b`"
  let (_, result) = run_js(src)
  expect_value_string(
    result, "ab|a\\\u{2028}b", "raw: \\LS preserved as backslash+U+2028, not normalized to \\n",
  )
}

///|
test "nested untagged template with invalid escape throws SyntaxError" {
  let src =
    #|`${`\1`}`
  expect_throw(
    src, "SyntaxError: Invalid escape sequence in template literal at line 1, col 4",
  )
}

///|
test "untagged template with invalid escape inside tagged substitution throws SyntaxError" {
  let src =
    #|function tag(s) { return s[0]; }
    #|tag`${`\1`}`
  expect_throw(
    src, "SyntaxError: Invalid escape sequence in template literal at line 2, col 7",
  )
}

///|
test "tagged template invalid hex escape cooked undefined raw preserved" {
  let src =
    #|function tag(s) { return typeof s[0] + '|' + s.raw[0]; }
    #|tag`\xZZ`;
  let (_, result) = run_js(src)
  expect_value_string(
    result, "undefined|\\xZZ", "\\xZZ: cooked undefined, raw preserves",
  )
}

///|
test "tagged template invalid unicode escape cooked undefined raw preserved" {
  let src =
    #|function tag(s) { return typeof s[0] + '|' + s.raw[0]; }
    #|tag`\uZZZZ`;
  let (_, result) = run_js(src)
  expect_value_string(
    result, "undefined|\\uZZZZ", "\\uZZZZ: cooked undefined, raw preserves",
  )
}

///|
test "tagged template raw normalizes CRLF to LF" {
  let src = "function tag(s) { return s.raw[0]; }\ntag`line1\r\nline2`"
  let (_, result) = run_js(src)
  expect_value_string(result, "line1\nline2", "raw: \\r\\n normalized to \\n")
}

// ====== Phase 2: Arrow Functions ======

///|
test "arrow function expression body" {
  let src =
    #|var add = (a, b) => a + b;
    #|add(3, 4);
  let (_, result) = run_js(src)
  expect_value_string(result, "7", "arrow function expression body result")
}

///|
test "arrow function block body" {
  let src =
    #|var square = (x) => { return x * x; };
    #|square(5);
  let (_, result) = run_js(src)
  expect_value_string(result, "25", "arrow function block body result")
}

///|
test "arrow function single param no parens" {
  let src =
    #|var double = x => x * 2;
    #|double(7);
  let (_, result) = run_js(src)
  expect_value_string(
    result, "14", "arrow function single param no parens result",
  )
}

///|
test "arrow function zero params" {
  let src =
    #|var greet = () => "hello";
    #|greet();
  let (_, result) = run_js(src)
  expect_value_string(result, "hello", "arrow function zero params result")
}

///|
test "arrow function as callback" {
  let src =
    #|var arr = [3, 1, 2];
    #|var mapped = [];
    #|for (var i = 0; i < arr.length; i++) {
    #|  mapped.push(arr[i] * 2);
    #|}
    #|console.log(mapped.join(","));
  let output = run_output(src)
  json_inspect(output, content=["6,2,4"])
}

///|
test "arrow function closure" {
  let src =
    #|var make_adder = (n) => (x) => n + x;
    #|var add5 = make_adder(5);
    #|add5(3);
  let (_, result) = run_js(src)
  expect_value_string(result, "8", "arrow function closure result")
}

// ====== Phase 2: Prototype Chain ======

///|
test "prototype chain property lookup" {
  let src =
    #|var parent = {x: 10};
    #|var child = Object.create(parent);
    #|child.y = 20;
    #|console.log(child.x);
    #|console.log(child.y);
  let output = run_output(src)
  json_inspect(output, content=["10", "20"])
}

///|
test "prototype chain own property shadows" {
  let src =
    #|var parent = {x: 10};
    #|var child = Object.create(parent);
    #|child.x = 99;
    #|console.log(child.x);
  let output = run_output(src)
  json_inspect(output, content=["99"])
}

///|
test "hasOwnProperty" {
  let src =
    #|var obj = {a: 1};
    #|console.log(obj.hasOwnProperty("a"));
    #|console.log(obj.hasOwnProperty("b"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

// ====== Phase 2: Function.call / apply / bind ======

///|
test "function call method" {
  let src =
    #|function greet() { return "Hello, " + this.name; }
    #|var obj = { name: "Alice" };
    #|greet.call(obj);
  let (_, result) = run_js(src)
  expect_result(result, "Hello, Alice")
}

///|
test "function apply method" {
  let src =
    #|function sum(a, b) { return a + b; }
    #|sum.apply(null, [10, 20]);
  let (_, result) = run_js(src)
  expect_result(result, "30")
}

///|
test "function apply method with array-like object" {
  let src =
    #|function join3(a, b, c) { return a + ":" + b + ":" + c; }
    #|var arrayLike = {0: "x", 1: "y", 2: "z", length: 3};
    #|join3.apply(null, arrayLike);
  let (_, result) = run_js(src)
  expect_result(result, "x:y:z")
}

///|
test "function apply method with arguments object" {
  let src =
    #|function add2(a, b) { return a + b; }
    #|function forward() { return add2.apply(null, arguments); }
    #|forward(40, 2);
  let (_, result) = run_js(src)
  expect_result(result, "42")
}

///|
test "function apply method with array-like length 0" {
  let src =
    #|function count() { return arguments.length; }
    #|count.apply(null, {0: 99, length: 0});
  let (_, result) = run_js(src)
  expect_result(result, "0")
}

///|
test "function apply method with non-numeric length" {
  let src =
    #|function firstOrNone() {
    #|  if (arguments.length === 0) return "none";
    #|  return String(arguments[0]);
    #|}
    #|firstOrNone.apply(null, {0: "x", length: "foo"});
  let (_, result) = run_js(src)
  expect_result(result, "none")
}

///|
// §20.2.3.1 + §7.3.18: argArray must be Object (or null/undefined)
test "function apply throws TypeError for boolean argArray" {
  let src =
    #|function fn() {}
    #|try { fn.apply(null, true); } catch(e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "function apply throws TypeError for number argArray" {
  let src =
    #|function fn() {}
    #|try { fn.apply(null, 42); } catch(e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "function apply throws TypeError for string argArray" {
  let src =
    #|function fn() {}
    #|try { fn.apply(null, "str"); } catch(e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "function apply null argArray does not throw" {
  let src =
    #|function fn() { return arguments.length; }
    #|fn.apply(null, null);
  let (_, result) = run_js(src)
  expect_result(result, "0")
}

///|
test "function apply array argArray passes args to callee" {
  let src =
    #|function fn(a, b, c) { return a + b + c; }
    #|fn.apply(null, [1, 2, 3]);
  let (_, result) = run_js(src)
  expect_result(result, "6")
}

///|
test "function bind method" {
  let src =
    #|function greet() { return "Hi " + this.name; }
    #|var obj = { name: "Bob" };
    #|var bound = greet.bind(obj);
    #|bound();
  let (_, result) = run_js(src)
  expect_result(result, "Hi Bob")
}

// ====== Promise Constructor/Species Regression Tests ======

///|
test "Promise then/finally/reject honor species and receiver constructor" {
  let output = run_output(
    (
      #|class SubPromise extends Promise {}
      #|const p1 = SubPromise.resolve(1).then(function(v) { return v + 1; });
      #|console.log(p1.constructor === SubPromise);
      #|
      #|class ForceBasePromise extends Promise {
      #|  static get [Symbol.species]() { return Promise; }
      #|}
      #|const p2 = ForceBasePromise.resolve(1).then(function(v) { return v; });
      #|console.log(p2.constructor === Promise);
      #|
      #|const p3 = SubPromise.resolve(1).finally(function() {});
      #|console.log(p3.constructor === SubPromise);
      #|
      #|const p4 = SubPromise.reject(1);
      #|p4.catch(function() {});
      #|console.log(p4.constructor === SubPromise);
    ),
  )
  json_inspect(output, content=["true", "true", "true", "true"])
}

///|
test "Promise species invalid constructor throws TypeError" {
  let output = run_output(
    (
      #|class BadSpeciesPromise extends Promise {
      #|  static get [Symbol.species]() { return {}; }
      #|}
      #|const p = BadSpeciesPromise.resolve(1);
      #|try {
      #|  p.then(function(v) { return v; });
      #|  console.log("no throw then");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
      #|try {
      #|  p.finally(function() {});
      #|  console.log("no throw finally");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=[
    "true", "Promise species is not a constructor", "true", "Promise species is not a constructor",
  ])
}

///|
test "PR 214 review: Promise subclass prototypes are visible to bracket and in" {
  let output = run_output(
    (
      #|class P extends Promise { m() { return 7; } }
      #|var p = new P(function(resolve) { resolve(1); });
      #|console.log(typeof p.m);
      #|console.log(typeof p["m"]);
      #|console.log("m" in p);
      #|console.log(Object.getPrototypeOf(p) === P.prototype);
      #|console.log(p.__proto__ === P.prototype);
      #|console.log(P.prototype.isPrototypeOf(p));
    ),
  )
  json_inspect(output, content=[
    "function", "function", "true", "true", "true", "true",
  ])
}

///|
test "Promise then throws when constructor is not object" {
  let output = run_output(
    (
      #|const p = Promise.resolve(1);
      #|p.constructor = 1;
      #|try {
      #|  p.then();
      #|  console.log("no throw");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=["true", "Promise constructor is not an object"])
}

///|
test "Promise reaction callbacks create functions with active realm prototypes" {
  let output = run_output_async(
    (
      #|Promise.resolve().then(function() {
      #|  var f = function() {};
      #|  console.log(Object.getPrototypeOf(f) === Function.prototype);
      #|  console.log(Object.getPrototypeOf(f.prototype) === Object.prototype);
      #|});
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "timer callbacks create functions with active realm prototypes" {
  let output = run_output_timers(
    (
      #|setTimeout(function() {
      #|  var f = function() {};
      #|  console.log(Object.getPrototypeOf(f) === Function.prototype);
      #|  console.log(Object.getPrototypeOf(f.prototype) === Object.prototype);
      #|}, 0);
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
/// Equal-delay timers fire in registration (insertion) order.
/// This pins the tie-break-by-insertion_order invariant required by the
/// WHATWG timer spec and must survive any queue-structure migration.
test "timers with equal delay fire in registration order" {
  let output = run_output_timers(
    (
      #|var log = [];
      #|setTimeout(function() { log.push("a"); }, 0);
      #|setTimeout(function() { log.push("b"); }, 0);
      #|setTimeout(function() { log.push("c"); }, 0);
      #|setTimeout(function() { console.log(log.join(",")); }, 1);
    ),
  )
  json_inspect(output, content=["a,b,c"])
}

///|
/// clearTimeout with an ID that is not yet in the queue must be a no-op:
/// the first allocated ID must not inherit a stale cancellation entry.
test "clearTimeout with unknown id is a no-op" {
  let output = run_output_timers(
    (
      #|clearTimeout(0);
      #|setTimeout(function() { console.log("ran"); }, 0);
    ),
  )
  json_inspect(output, content=["ran"])
}

///|
/// clearTimeout before drain must prevent the callback from firing.
test "clearTimeout cancels timer before it fires" {
  let output = run_output_timers(
    (
      #|var fired = false;
      #|var id = setTimeout(function() { fired = true; }, 0);
      #|clearTimeout(id);
      #|setTimeout(function() { console.log(fired); }, 1);
    ),
  )
  json_inspect(output, content=["false"])
}

///|
/// clearInterval inside the callback fires the timer exactly N times.
test "clearInterval inside callback stops re-enqueue" {
  let output = run_output_timers(
    (
      #|var count = 0;
      #|var id = setInterval(function() {
      #|  count++;
      #|  if (count >= 3) { clearInterval(id); }
      #|}, 0);
      #|setTimeout(function() { console.log(count); }, 1);
    ),
  )
  json_inspect(output, content=["3"])
}

// ====== Phase 2: Array Methods ======

///|
test "array push pop" {
  let src =
    #|var arr = [1, 2, 3];
    #|arr.push(4);
    #|console.log(arr.length);
    #|var last = arr.pop();
    #|console.log(last);
    #|console.log(arr.length);
  let output = run_output(src)
  json_inspect(output, content=["4", "4", "3"])
}

///|
test "array push and pop observe prototype method overrides" {
  let src =
    #|var savedPush = Array.prototype.push;
    #|var savedPop = Array.prototype.pop;
    #|Array.prototype.push = function(a, b) { return "push:" + this.length + ":" + a + ":" + b; };
    #|Array.prototype.pop = function() { return "pop:" + this.length; };
    #|console.log([1, 2].push(3, 4));
    #|console.log([1, 2].pop());
    #|Array.prototype.push = savedPush;
    #|Array.prototype.pop = savedPop;
  let output = run_output(src)
  json_inspect(output, content=["push:2:3:4", "pop:2"])
}

///|
test "array push length set and inherited setter side effects" {
  let src =
    #|var empty = [];
    #|Object.defineProperty(empty, "length", { writable: false });
    #|try { empty.push(); console.log("empty:no throw"); }
    #|catch (e) { console.log("empty:" + (e instanceof TypeError)); }
    #|var array = [];
    #|var calls = 0;
    #|Object.defineProperty(Array.prototype, "0", {
    #|  configurable: true,
    #|  set: function(_value) {
    #|    calls = calls + 1;
    #|    Object.defineProperty(array, "length", { writable: false });
    #|  }
    #|});
    #|try { array.push(1); console.log("setter:no throw"); }
    #|catch (e) { console.log("setter:" + (e instanceof TypeError)); }
    #|console.log(array.hasOwnProperty("0"));
    #|console.log(array.length);
    #|console.log(calls);
    #|delete Array.prototype[0];
  let output = run_output(src)
  json_inspect(output, content=["empty:true", "setter:true", "false", "0", "1"])
}

///|
test "array push and pop preserve sparse large indices" {
  let src =
    #|var array = [];
    #|array.length = 2147483647;
    #|console.log(array.push("x"));
    #|console.log(array.length);
    #|console.log(array[2147483647]);
    #|console.log(array[0]);
    #|console.log(array.pop());
    #|console.log(array.length);
    #|console.log(array[2147483647]);
    #|var blocked = [];
    #|blocked.length = 2147483648;
    #|Object.defineProperty(blocked, "length", { writable: false });
    #|try { blocked.push("blocked"); console.log("blocked:no throw"); }
    #|catch (e) { console.log("blocked:" + (e instanceof TypeError)); }
    #|console.log(blocked.hasOwnProperty("2147483648"));
    #|console.log(blocked.length);
    #|var computedString = [];
    #|computedString["2147483648"] = "string";
    #|console.log(computedString.length);
    #|console.log(computedString["2147483648"]);
    #|var computedNumber = [];
    #|computedNumber[2147483648] = "number";
    #|console.log(computedNumber.length);
    #|console.log(computedNumber[2147483648]);
    #|var computedBlocked = [];
    #|computedBlocked.length = 2147483648;
    #|Object.defineProperty(computedBlocked, "length", { writable: false });
    #|(function() { "use strict"; try { computedBlocked["2147483648"] = "blocked"; console.log("computed:no throw"); }
    #|catch (e) { console.log("computed:" + (e instanceof TypeError)); } })();
    #|console.log(computedBlocked.hasOwnProperty("2147483648"));
    #|console.log(computedBlocked.length);
    #|var shrink = [];
    #|shrink[200000] = "sparse";
    #|shrink.length = 0;
    #|console.log(shrink.hasOwnProperty("200000"));
    #|console.log(shrink[200000]);
    #|console.log(shrink.length);
    #|var shrinkDefine = [];
    #|shrinkDefine[200000] = "sparse";
    #|Object.defineProperty(shrinkDefine, "length", { value: 0 });
    #|console.log(shrinkDefine.hasOwnProperty("200000"));
    #|console.log(shrinkDefine[200000]);
    #|console.log(shrinkDefine.length);
    #|var partial = [];
    #|partial.length = 3000000001;
    #|partial["3000000000"] = "deleted";
    #|Object.defineProperty(partial, "2500000000", { value: "fixed", configurable: false });
    #|try { partial.length = 0; console.log("partial:ok"); }
    #|catch (e) { console.log("partial:" + e.name); }
    #|console.log(partial.hasOwnProperty("3000000000"));
    #|console.log(partial["3000000000"]);
    #|console.log(partial.length);
    #|console.log(partial["2500000000"]);
    #|var partialDefine = [];
    #|partialDefine.length = 3000000001;
    #|partialDefine["3000000000"] = "deleted";
    #|Object.defineProperty(partialDefine, "2500000000", { value: "fixed", configurable: false });
    #|try { Object.defineProperty(partialDefine, "length", { value: 0 }); console.log("define:ok"); }
    #|catch (e) { console.log("define:" + e.name); }
    #|console.log(partialDefine.hasOwnProperty("3000000000"));
    #|console.log(partialDefine["3000000000"]);
    #|console.log(partialDefine.length);
    #|console.log(partialDefine["2500000000"]);
    #|var denseBlocked = [];
    #|denseBlocked.length = 200000;
    #|Object.defineProperty(denseBlocked, "5", { value: 1, configurable: false });
    #|denseBlocked.length = 0;
    #|console.log(denseBlocked.length);
    #|console.log(denseBlocked[5]);
    #|var denseBlockedDefine = [];
    #|denseBlockedDefine.length = 200000;
    #|Object.defineProperty(denseBlockedDefine, "5", { value: 1, configurable: false });
    #|try { Object.defineProperty(denseBlockedDefine, "length", { value: 0 }); console.log("denseDefine:ok"); }
    #|catch (e) { console.log("denseDefine:" + e.name); }
    #|console.log(denseBlockedDefine.length);
    #|console.log(denseBlockedDefine[5]);
    #|var extendSparse = [];
    #|extendSparse.length = 3000000000;
    #|extendSparse.length = 3000000001;
    #|console.log(extendSparse.length);
    #|console.log(extendSparse.hasOwnProperty("0"));
    #|Object.defineProperty(extendSparse, "length", { value: 3000000002 });
    #|console.log(extendSparse.length);
    #|console.log(extendSparse.hasOwnProperty("3000000001"));
    #|var methodSparse = [];
    #|methodSparse[200000] = "needle";
    #|console.log(methodSparse.indexOf("needle"));
    #|console.log(methodSparse.includes("needle"));
    #|console.log(Object.hasOwn(methodSparse, "200000"));
    #|var inheritedSparse = [];
    #|inheritedSparse.length = 100001;
    #|Array.prototype[100000] = "proto";
    #|console.log(inheritedSparse.indexOf("proto"));
    #|delete Array.prototype[100000];
    #|var holeOnly = [];
    #|holeOnly.length = 100001;
    #|console.log(holeOnly.join(",").length);
    #|var sparseAccessor = [];
    #|Object.defineProperty(sparseAccessor, "200000", { configurable: true, get: function() { return "accessor"; } });
    #|Object.freeze(sparseAccessor);
    #|var sparseDesc = Object.getOwnPropertyDescriptor(sparseAccessor, "200000");
    #|console.log(sparseDesc.configurable);
    #|console.log(sparseAccessor[200000]);
    #|var rematerialize = [];
    #|rematerialize.length = 99999;
    #|rematerialize[200000] = "x";
    #|rematerialize[150000] = "y";
    #|rematerialize[200000] = "z";
    #|var names = Object.getOwnPropertyNames(rematerialize);
    #|var nameCount = 0;
    #|for (var ni = 0; ni < names.length; ni = ni + 1) { if (names[ni] === "200000") nameCount = nameCount + 1; }
    #|console.log(nameCount);
    #|console.log(delete rematerialize[200000]);
    #|console.log(rematerialize.hasOwnProperty("200000"));
    #|console.log(rematerialize[200000]);
  let output = run_output(src)
  json_inspect(output, content=[
    "2147483648", "2147483648", "x", "undefined", "x", "2147483647", "undefined",
    "blocked:true", "false", "2147483648", "2147483649", "string", "2147483649",
    "number", "computed:true", "false", "2147483648", "false", "undefined", "0",
    "false", "undefined", "0", "partial:ok", "false", "undefined", "2500000001",
    "fixed", "define:TypeError", "false", "undefined", "2500000001", "fixed", "6",
    "1", "denseDefine:TypeError", "6", "1", "3000000001", "false", "3000000002",
    "false", "200000", "true", "true", "100000", "100000", "false", "accessor", "1",
    "true", "false", "undefined",
  ])
}

///|
test "array pop reads inherited elements before deleting and setting length" {
  let src =
    #|Array.prototype[1] = "inherited";
    #|var sparse = [0];
    #|sparse.length = 2;
    #|console.log(sparse.pop());
    #|console.log(sparse.length);
    #|console.log(sparse[1]);
    #|delete Array.prototype[1];
    #|var array = new Array(1);
    #|var calls = 0;
    #|Object.defineProperty(Array.prototype, "0", {
    #|  configurable: true,
    #|  get: function() {
    #|    calls = calls + 1;
    #|    Object.defineProperty(array, "length", { writable: false });
    #|    return "from getter";
    #|  }
    #|});
    #|try { array.pop(); console.log("getter:no throw"); }
    #|catch (e) { console.log("getter:" + (e instanceof TypeError)); }
    #|console.log(array.length);
    #|console.log(calls);
    #|delete Array.prototype[0];
  let output = run_output(src)
  json_inspect(output, content=[
    "inherited", "1", "inherited", "getter:true", "1", "1",
  ])
}

///|
test "array push and pop reject frozen array length sets" {
  let src =
    #|var pushArray = [];
    #|Object.freeze(pushArray);
    #|try { pushArray.push(); console.log("push:no throw"); }
    #|catch (e) { console.log("push:" + (e instanceof TypeError)); }
    #|var popArray = new Array(1);
    #|Object.freeze(popArray);
    #|try { popArray.pop(); console.log("pop:no throw"); }
    #|catch (e) { console.log("pop:" + (e instanceof TypeError)); }
    #|console.log(popArray.length);
  let output = run_output(src)
  json_inspect(output, content=["push:true", "pop:true", "1"])
}

///|
test "array shift unshift" {
  let src =
    #|var arr = [1, 2, 3];
    #|var first = arr.shift();
    #|console.log(first);
    #|arr.unshift(0);
    #|console.log(arr.join(","));
  let output = run_output(src)
  json_inspect(output, content=["1", "0,2,3"])
}

///|
test "array shift and unshift observe prototype method overrides" {
  let src =
    #|var savedShift = Array.prototype.shift;
    #|var savedUnshift = Array.prototype.unshift;
    #|Array.prototype.shift = function() { return "shift:" + this.length; };
    #|Array.prototype.unshift = function(a, b) { return "unshift:" + this.length + ":" + a + ":" + b; };
    #|console.log([1, 2].shift());
    #|console.log([1, 2].unshift("a", "b"));
    #|Array.prototype.shift = savedShift;
    #|Array.prototype.unshift = savedUnshift;
  let output = run_output(src)
  json_inspect(output, content=["shift:2", "unshift:2:a:b"])
}

///|
test "array shift and unshift observe inherited indexed properties" {
  let src =
    #|Array.prototype[1] = "inherited";
    #|var shifted = ["own"];
    #|shifted.length = 2;
    #|console.log(shifted.shift());
    #|console.log(shifted[0]);
    #|console.log(shifted.hasOwnProperty("0"));
    #|console.log(shifted[1]);
    #|delete Array.prototype[1];
    #|Array.prototype[0] = "proto0";
    #|var unshifted = [];
    #|unshifted.length = 1;
    #|console.log(unshifted.unshift("head"));
    #|console.log(unshifted[0]);
    #|console.log(unshifted[1]);
    #|console.log(unshifted.hasOwnProperty("1"));
    #|delete Array.prototype[0];
  let output = run_output(src)
  json_inspect(output, content=[
    "own", "inherited", "true", "inherited", "2", "head", "proto0", "true",
  ])
}

///|
test "array shift and unshift reject non-writable length" {
  let src =
    #|var empty = [];
    #|Object.defineProperty(empty, "length", { writable: false });
    #|try { empty.shift(); console.log("shift-empty:no throw"); }
    #|catch (e) { console.log("shift-empty:" + (e instanceof TypeError)); }
    #|var array = [1];
    #|Object.defineProperty(array, "length", { writable: false });
    #|try { array.shift(); console.log("shift:no throw"); }
    #|catch (e) { console.log("shift:" + (e instanceof TypeError)); }
    #|console.log(array.length);
    #|console.log(array[0]);
    #|var unshiftEmpty = [];
    #|Object.defineProperty(unshiftEmpty, "length", { writable: false });
    #|try { unshiftEmpty.unshift(); console.log("unshift-empty:no throw"); }
    #|catch (e) { console.log("unshift-empty:" + (e instanceof TypeError)); }
    #|try { unshiftEmpty.unshift(1); console.log("unshift-one:no throw"); }
    #|catch (e) { console.log("unshift-one:" + (e instanceof TypeError)); }
    #|console.log(unshiftEmpty.length);
  let output = run_output(src)
  json_inspect(output, content=[
    "shift-empty:true", "shift:true", "1", "undefined", "unshift-empty:true", "unshift-one:true",
    "0",
  ])
}

///|
test "array shift and unshift preserve sparse high-index length" {
  let src =
    #|var high = [];
    #|high.length = 2147483648;
    #|console.log(high.unshift());
    #|console.log(high.length);
    #|console.log(high.shift());
    #|console.log(high.length);
    #|var sparse = [];
    #|sparse[100001] = "tail";
    #|console.log(sparse.length);
    #|console.log(sparse.shift());
    #|console.log(sparse.length);
    #|console.log(sparse[100000]);
    #|console.log(Object.hasOwn(sparse, "100000"));
    #|console.log(Object.hasOwn(sparse, "100001"));
    #|var highSparse = [];
    #|highSparse[2147483648] = "high-tail";
    #|console.log(highSparse.length);
    #|console.log(highSparse.shift());
    #|console.log(highSparse.length);
    #|console.log(highSparse[2147483647]);
    #|console.log(Object.hasOwn(highSparse, "2147483648"));
    #|console.log(Object.hasOwn(highSparse, "2147483647"));
    #|var denseHigh = ["first"];
    #|denseHigh[2147483648] = "dense-tail";
    #|console.log(denseHigh.shift());
    #|console.log(denseHigh[0]);
    #|console.log(denseHigh[2147483647]);
    #|console.log(Object.hasOwn(denseHigh, "2147483648"));
    #|Array.prototype[2147483648] = "proto-tail";
    #|var inheritedHigh = [];
    #|inheritedHigh.length = 2147483649;
    #|console.log(inheritedHigh.shift());
    #|console.log(inheritedHigh.length);
    #|console.log(inheritedHigh[2147483647]);
    #|console.log(Object.hasOwn(inheritedHigh, "2147483647"));
    #|delete Array.prototype[2147483648];
    #|var unshiftSparse = [];
    #|unshiftSparse[2147483648] = "tail";
    #|console.log(unshiftSparse.unshift("head"));
    #|console.log(unshiftSparse[0]);
    #|console.log(unshiftSparse[2147483649]);
    #|console.log(Object.hasOwn(unshiftSparse, "2147483648"));
    #|console.log(Object.hasOwn(unshiftSparse, "2147483649"));
    #|Array.prototype[2147483648] = "proto-tail";
    #|var unshiftInheritedHigh = [];
    #|unshiftInheritedHigh.length = 2147483649;
    #|console.log(unshiftInheritedHigh.unshift("head"));
    #|console.log(unshiftInheritedHigh[0]);
    #|console.log(unshiftInheritedHigh[2147483649]);
    #|console.log(Object.hasOwn(unshiftInheritedHigh, "2147483649"));
    #|delete Array.prototype[2147483648];
    #|var accessorShift = [];
    #|Object.defineProperty(accessorShift, "2147483648", { configurable: true, get: function() { return "accessor-tail"; } });
    #|accessorShift.length = 2147483649;
    #|console.log(accessorShift.shift());
    #|console.log(accessorShift[2147483647]);
    #|console.log(Object.hasOwn(accessorShift, "2147483648"));
    #|console.log(Object.hasOwn(accessorShift, "2147483647"));
    #|var accessorUnshift = [];
    #|Object.defineProperty(accessorUnshift, "2147483648", { configurable: true, get: function() { return "accessor-tail"; } });
    #|accessorUnshift.length = 2147483649;
    #|console.log(accessorUnshift.unshift("head"));
    #|console.log(accessorUnshift[2147483649]);
    #|console.log(Object.hasOwn(accessorUnshift, "2147483648"));
    #|console.log(Object.hasOwn(accessorUnshift, "2147483649"));
  let output = run_output(src)
  json_inspect(output, content=[
    "2147483648", "2147483648", "undefined", "2147483647", "100002", "undefined",
    "100001", "tail", "true", "false", "2147483649", "undefined", "2147483648", "high-tail",
    "false", "true", "first", "undefined", "dense-tail", "false", "undefined", "2147483648",
    "proto-tail", "true", "2147483650", "head", "tail", "false", "true", "2147483650",
    "head", "proto-tail", "true", "undefined", "accessor-tail", "false", "true",
    "2147483650", "accessor-tail", "false", "true",
  ])
}

///|
test "array shift and unshift respect Object integrity" {
  let src =
    #|var frozenShift = [1];
    #|Object.freeze(frozenShift);
    #|try { frozenShift.shift(); console.log("frozen-shift:no throw"); }
    #|catch (e) { console.log("frozen-shift:" + (e instanceof TypeError)); }
    #|console.log(frozenShift.length);
    #|console.log(frozenShift[0]);
    #|var frozenUnshift = [];
    #|Object.freeze(frozenUnshift);
    #|try { frozenUnshift.unshift(1); console.log("frozen-unshift:no throw"); }
    #|catch (e) { console.log("frozen-unshift:" + (e instanceof TypeError)); }
    #|console.log(Object.hasOwn(frozenUnshift, "0"));
    #|console.log(frozenUnshift.length);
    #|var nonext = [];
    #|Object.preventExtensions(nonext);
    #|try { nonext.unshift(1); console.log("nonext-unshift:no throw"); }
    #|catch (e) { console.log("nonext-unshift:" + (e instanceof TypeError)); }
    #|console.log(Object.hasOwn(nonext, "0"));
    #|console.log(nonext.length);
    #|var highShift = [];
    #|highShift[2147483648] = "x";
    #|Object.preventExtensions(highShift);
    #|try { highShift.shift(); console.log("high-shift:no throw"); }
    #|catch (e) { console.log("high-shift:" + (e instanceof TypeError)); }
    #|console.log(Object.hasOwn(highShift, "2147483648"));
    #|console.log(Object.hasOwn(highShift, "2147483647"));
    #|var highUnshift = [];
    #|highUnshift[2147483648] = "x";
    #|Object.preventExtensions(highUnshift);
    #|try { highUnshift.unshift("head"); console.log("high-unshift:no throw"); }
    #|catch (e) { console.log("high-unshift:" + (e instanceof TypeError)); }
    #|console.log(Object.hasOwn(highUnshift, "2147483648"));
    #|console.log(Object.hasOwn(highUnshift, "2147483649"));
  let output = run_output(src)
  json_inspect(output, content=[
    "frozen-shift:true", "1", "1", "frozen-unshift:true", "false", "0", "nonext-unshift:true",
    "false", "0", "high-shift:true", "true", "false", "high-unshift:true", "true",
    "false",
  ])
}

///|
test "array join" {
  let src =
    #|var arr = [1, 2, 3];
    #|console.log(arr.join("-"));
    #|console.log(arr.join(""));
  let output = run_output(src)
  json_inspect(output, content=["1-2-3", "123"])
}

///|
test "array toString delegates to live join" {
  let src =
    #|var arr = [1, 2];
    #|arr.join = function() { return "custom"; };
    #|console.log(arr.toString());
    #|var fallback = [1];
    #|fallback.join = 1;
    #|console.log(fallback.toString());
    #|Array.prototype[1] = 1;
    #|var sparse = [0];
    #|sparse.length = 2;
    #|console.log(sparse.toString());
    #|delete Array.prototype[1];
  let output = run_output(src)
  json_inspect(output, content=["custom", "[object Array]", "0,1"])
}

///|
test "array indexOf includes" {
  let src =
    #|var arr = [10, 20, 30];
    #|console.log(arr.indexOf(20));
    #|console.log(arr.indexOf(99));
    #|console.log(arr.includes(30));
    #|console.log(arr.includes(99));
  let output = run_output(src)
  json_inspect(output, content=["1", "-1", "true", "false"])
}

///|
test "array includes and at observe inherited indexed properties" {
  let src =
    #|Array.prototype[0] = "inherited";
    #|var arr = [];
    #|arr.length = 1;
    #|console.log(arr.includes("inherited"));
    #|console.log(arr.at(0));
    #|delete Array.prototype[0];
  let output = run_output(src)
  json_inspect(output, content=["true", "inherited"])
}

///|
test "array includes fromIndex valueOf not called when length is zero" {
  let src =
    #|var calls = 0;
    #|var fi = { valueOf: function() { calls++; } };
    #|var r = [].includes(0, fi);
    #|console.log(r);
    #|console.log(calls);
  let output = run_output(src)
  json_inspect(output, content=["false", "0"])
}

///|
test "array includes fromIndex valueOf coercion with interpreter context" {
  let src =
    #|var obj = { valueOf: function() { return 1; } };
    #|var arr = [42, 43];
    #|console.log(arr.includes(42, obj));
    #|console.log(arr.includes(43, obj));
  let output = run_output(src)
  json_inspect(output, content=["false", "true"])
}

///|
test "array includes indexOf lastIndexOf use truncation toward zero for negative fractional fromIndex" {
  // ToIntegerOrInfinity = sign(n) * floor(abs(n)), which truncates toward zero.
  // -0.1 truncates to 0, not -1 (floor); so search starts at index max(len+0,0)=0.
  // With Math.floor, -0.1 → -1, k=len-1=1, and 'a' at index 0 would be missed.
  let src =
    #|var a = ['a', 'b'];
    #|console.log(a.indexOf('a', -0.1));
    #|console.log(a.indexOf('a', -0.9));
    #|console.log(a.includes('a', -0.1));
    #|// -1.5 truncates to -1, k=len+(-1)=1; lastIndexOf from index 1 finds at 1, not 0
    #|console.log([1, 1].lastIndexOf(1, -1.5));
  let output = run_output(src)
  json_inspect(output, content=["0", "0", "true", "1"])
}

///|
test "unary plus and minus call valueOf with interpreter context" {
  let src =
    #|var v = { valueOf: function() { return 3; } };
    #|console.log(+v);
    #|console.log(-v);
  let output = run_output(src)
  json_inspect(output, content=["3", "-3"])
}

///|
test "array copy methods observe prototype overrides" {
  let src =
    #|var saved = {
    #|  toReversed: Array.prototype.toReversed,
    #|  toSorted: Array.prototype.toSorted,
    #|  toSpliced: Array.prototype.toSpliced,
    #|  with: Array.prototype.with
    #|};
    #|Array.prototype.toReversed = function() { return "rev:" + this.length; };
    #|Array.prototype.toSorted = function() { return "sorted:" + this.length; };
    #|Array.prototype.toSpliced = function() { return "spliced:" + this.length; };
    #|Array.prototype.with = function() { return "with:" + this.length; };
    #|console.log([1, 2].toReversed());
    #|console.log([1, 2].toSorted());
    #|console.log([1, 2].toSpliced());
    #|console.log([1, 2].with(0, 9));
    #|Array.prototype.toReversed = saved.toReversed;
    #|Array.prototype.toSorted = saved.toSorted;
    #|Array.prototype.toSpliced = saved.toSpliced;
    #|Array.prototype.with = saved.with;
  let output = run_output(src)
  json_inspect(output, content=["rev:2", "sorted:2", "spliced:2", "with:2"])
}

///|
test "array copy methods observe inherited indexed properties" {
  let src =
    #|Array.prototype[1] = "inherited";
    #|var arr = ["own"];
    #|arr.length = 2;
    #|console.log(arr.toReversed().join("|"));
    #|console.log(arr.toSorted().join("|"));
    #|console.log(arr.toSpliced(1, 0, "inserted").join("|"));
    #|console.log(arr.with(0, "replaced").join("|"));
    #|delete Array.prototype[1];
  let output = run_output(src)
  json_inspect(output, content=[
    "inherited|own", "own|inherited", "own|inserted|inherited", "replaced|inherited",
  ])
}

///|
test "array iterator methods observe prototype overrides" {
  let src =
    #|var saved = {
    #|  entries: Array.prototype.entries,
    #|  keys: Array.prototype.keys,
    #|  values: Array.prototype.values,
    #|  iterator: Array.prototype[Symbol.iterator]
    #|};
    #|Array.prototype.entries = function() { return "entries:" + this.length; };
    #|Array.prototype.keys = function() { return "keys:" + this.length; };
    #|Array.prototype.values = function() { return "values:" + this.length; };
    #|Array.prototype[Symbol.iterator] = function() { return "iterator:" + this.length; };
    #|console.log([1, 2].entries());
    #|console.log([1, 2].keys());
    #|console.log([1, 2].values());
    #|console.log([1, 2][Symbol.iterator]());
    #|Array.prototype.entries = saved.entries;
    #|Array.prototype.keys = saved.keys;
    #|Array.prototype.values = saved.values;
    #|Array.prototype[Symbol.iterator] = saved.iterator;
  let output = run_output(src)
  json_inspect(output, content=["entries:2", "keys:2", "values:2", "iterator:2"])
}

///|
test "array iterators read live array state through prototype next" {
  let src =
    #|var arr = ["a"];
    #|var entries = arr.entries();
    #|var keys = arr.keys();
    #|var values = arr.values();
    #|var next = Object.getPrototypeOf(values).next;
    #|arr.push("b");
    #|var pair = next.call(entries).value;
    #|console.log(pair[0] + ":" + pair[1]);
    #|pair = next.call(entries).value;
    #|console.log(pair[0] + ":" + pair[1]);
    #|console.log(next.call(entries).done);
    #|console.log(next.call(keys).value);
    #|console.log(next.call(keys).value);
    #|console.log(next.call(keys).done);
    #|console.log(next.call(values).value);
    #|console.log(next.call(values).value);
    #|console.log(next.call(values).done);
  let output = run_output(src)
  json_inspect(output, content=[
    "0:a", "1:b", "true", "0", "1", "true", "a", "b", "true",
  ])
}

///|
test "array default iterator and for-of read live array state" {
  let src =
    #|console.log(Array.prototype.values === Array.prototype[Symbol.iterator]);
    #|var arr = ["a"];
    #|var iterator = arr[Symbol.iterator]();
    #|arr.push("b");
    #|console.log(iterator.next().value);
    #|console.log(iterator.next().value);
    #|console.log(iterator.next().done);
    #|var out = [];
    #|var loop = ["x"];
    #|for (var value of loop) {
    #|  out.push(value);
    #|  if (value === "x") loop.push("y");
    #|}
    #|console.log(out.join("|"));
  let output = run_output(src)
  json_inspect(output, content=["true", "a", "b", "true", "x|y"])
}

///|
test "array slice" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|console.log(arr.slice(1, 3).join(","));
    #|console.log(arr.slice(-2).join(","));
  let output = run_output(src)
  json_inspect(output, content=["2,3", "4,5"])
}

///|
test "array concat" {
  let (_, result) = run_js("[1, 2].concat([3, 4]).join(\",\")")
  expect_result(result, "1,2,3,4")
}

///|
test "array reverse" {
  let (_, result) = run_js("[1, 2, 3].reverse().join(\",\")")
  expect_result(result, "3,2,1")
}

///|
test "array splice" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|var removed = arr.splice(1, 2);
    #|console.log(removed.join(","));
    #|console.log(arr.join(","));
  let output = run_output(src)
  json_inspect(output, content=["2,3", "1,4,5"])
}

///|
test "array sort" {
  let (_, result) = run_js(
    "[\"banana\", \"apple\", \"cherry\"].sort().join(\",\")",
  )
  expect_result(result, "apple,banana,cherry")
}

///|
test "array isArray" {
  let src =
    #|console.log(Array.isArray([1, 2]));
    #|console.log(Array.isArray("hello"));
    #|console.log(Array.isArray(42));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "false"])
}

///|
test "array fill" {
  let (_, result) = run_js("[1, 2, 3, 4].fill(0, 1, 3).join(\",\")")
  expect_result(result, "1,0,0,4")
}

// ====== Phase 2: String Methods ======

///|
test "string charAt charCodeAt" {
  let src =
    #|var s = "hello";
    #|console.log(s.charAt(1));
    #|console.log(s.charCodeAt(0));
  let output = run_output(src)
  json_inspect(output, content=["e", "104"])
}

///|
test "string indexOf lastIndexOf" {
  let src =
    #|var s = "hello world hello";
    #|console.log(s.indexOf("hello"));
    #|console.log(s.lastIndexOf("hello"));
    #|console.log(s.indexOf("xyz"));
  let output = run_output(src)
  json_inspect(output, content=["0", "12", "-1"])
}

///|
test "string indexOf lastIndexOf empty needle clamping" {
  let src =
    #|console.log("abc".indexOf("", 10));
    #|console.log("abc".lastIndexOf("", -1));
    #|console.log("abc".lastIndexOf("", 99));
  let output = run_output(src)
  json_inspect(output, content=["3", "0", "3"])
}

///|
test "issue 203: string indexOf coercions call user code" {
  let output = run_output(
    (
      #|console.log("__foo__".indexOf({ [Symbol.toPrimitive]: function() { return "foo"; } }));
      #|console.log("aaaa".indexOf("aa", { valueOf: function() { return 1; }, toString: function() { throw new Error("unused"); } }));
      #|console.log("__foo__".lastIndexOf({ toString: function() { return "foo"; } }, { valueOf: function() { return 5; } }));
      #|console.log(String.prototype.indexOf.call("__bar__", { [Symbol.toPrimitive]: function() { return "bar"; } }));
      #|console.log(String.prototype.lastIndexOf.call(new String("__bar__"), { toString: function() { return "bar"; } }, { valueOf: function() { return 6; } }));
      #|try { "".indexOf("", { valueOf: function() { throw new Error("boom"); } }); } catch (e) { console.log(e.message); }
    ),
  )
  json_inspect(output, content=["2", "1", "2", "2", "2", "boom"])
}

///|
test "issue 203: remaining ES2015 coercions call user code" {
  let output = run_output(
    (
      #|var cpCalls = 0;
      #|console.log(String.fromCodePoint({ valueOf: function() { cpCalls += 1; return 65; } }), cpCalls);
      #|var sepCalls = 0;
      #|var sep = {};
      #|sep[Symbol.split] = null;
      #|sep.toString = function() { sepCalls += 1; return "2"; };
      #|console.log("a2b2c".split(sep).join("|"), sepCalls);
      #|var arr = [1, null, 3];
      #|var fromCalls = 0;
      #|var fromIndex = { valueOf: function() { fromCalls += 1; arr.length = 0; return 0; } };
      #|console.log(Array.prototype.indexOf.call(arr, 100, fromIndex), fromCalls);
      #|var log = [];
      #|var sourceKey = { toString: function() { log.push("sourceKey"); return "p"; } };
      #|var source = { get p() { log.push("get source"); return undefined; } };
      #|var env = new Proxy({}, { has: function(_target, key) { log.push("binding::" + key); return false; } });
      #|var defaultValue = 0;
      #|var varTarget;
      #|with (env) { var { [sourceKey]: varTarget = defaultValue } = source; }
      #|console.log(log.join("|"));
      #|var sym = Symbol("k");
      #|var symCalls = 0;
      #|var keyObj = { [Symbol.toPrimitive]: function(hint) { symCalls += 1; return sym; } };
      #|var symSource = {};
      #|symSource[sym] = 42;
      #|var { [keyObj]: symTarget, ...symRest } = symSource;
      #|console.log(symTarget, symRest[sym]);
      #|var assignedSymTarget = 0;
      #|({ [keyObj]: assignedSymTarget } = symSource);
      #|console.log(assignedSymTarget, symCalls);
    ),
  )
  json_inspect(output, content=[
    "A 1", "a|b|c 1", "-1 1", "binding::source|binding::sourceKey|sourceKey|binding::varTarget|get source|binding::defaultValue",
    "42 undefined", "42 2",
  ])
}

///|
test "issue 203: array indexOf lastIndexOf empty arrays skip fromIndex coercion" {
  let output = run_output(
    (
      #|var calls = 0;
      #|var fromIndex = { valueOf: function() { calls += 1; throw new Error("boom"); } };
      #|console.log([].indexOf(1, fromIndex), [].lastIndexOf(1, fromIndex), calls);
    ),
  )
  json_inspect(output, content=["-1 -1 0"])
}

///|
test "issue 203: object and date coercions call user code" {
  let output = run_output(
    (
      #|var dateArg = {};
      #|var dateCount = 0;
      #|var dateThis = false;
      #|var dateHint = "";
      #|dateArg[Symbol.toPrimitive] = function(hint) { dateCount += 1; dateThis = this === dateArg; dateHint = hint; return 0; };
      #|var d = new Date(dateArg);
      #|console.log(dateCount, dateThis, dateHint, d.valueOf());
      #|var original = new Date(1234);
      #|var clonePrimitiveCalls = 0;
      #|original[Symbol.toPrimitive] = function() { clonePrimitiveCalls += 1; return 0; };
      #|var clone = new Date(original);
      #|console.log(clone.valueOf(), clonePrimitiveCalls);
      #|var obj = {};
      #|var sym = Symbol();
      #|var keyCalls = 0;
      #|var wrapper = { toString: function() { keyCalls += 1; return sym; }, valueOf: function() { throw new Error("unused"); } };
      #|obj[sym] = 0;
      #|console.log(obj.propertyIsEnumerable(wrapper), keyCalls);
      #|try { Object.prototype.propertyIsEnumerable.call(null, { toString: function() { throw new Error("key first"); } }); }
      #|catch (e) { console.log(e.message); }
    ),
  )
  json_inspect(output, content=[
    "1 true default 0", "1234 0", "true 1", "key first",
  ])
}

///|
test "string includes" {
  let src =
    #|console.log("foobar".includes("bar"));
    #|console.log("foobar".includes("baz"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "string slice" {
  let src =
    #|console.log("hello world".slice(6));
    #|console.log("hello world".slice(0, 5));
    #|console.log("hello world".slice(-5));
  let output = run_output(src)
  json_inspect(output, content=["world", "hello", "world"])
}

///|
test "string toUpperCase toLowerCase" {
  let src =
    #|console.log("Hello".toUpperCase());
    #|console.log("Hello".toLowerCase());
  let output = run_output(src)
  json_inspect(output, content=["HELLO", "hello"])
}

///|
test "string trim" {
  let (_, result) = run_js("\"  hello  \".trim()")
  expect_result(result, "hello")
}

///|
test "string split" {
  let src =
    #|var parts = "a,b,c".split(",");
    #|console.log(parts.length);
    #|console.log(parts.join("|"));
  let output = run_output(src)
  json_inspect(output, content=["3", "a|b|c"])
}

///|
test "RegExp exec observes lastIndex coercion and strict writes" {
  let src =
    #|var reads = 0;
    #|var counter = { valueOf: function() { reads++; return 0; } };
    #|var plain = /a/;
    #|plain.lastIndex = counter;
    #|console.log(plain.exec("nbc"));
    #|console.log(plain.lastIndex === counter);
    #|console.log(reads);
    #|var global = /./g;
    #|global.lastIndex = Infinity;
    #|console.log(global.exec("test"));
    #|console.log(global.lastIndex);
    #|var sticky = /c/y;
    #|Object.defineProperty(sticky, "lastIndex", { writable: false });
    #|try { sticky.exec("abc"); } catch (e) { console.log(e instanceof TypeError); }
    #|try { /[a-z]/.exec({ toString: function() { throw "intostr"; } }); } catch (e) { console.log(e); }
  let output = run_output(src)
  json_inspect(output, content=[
    "null", "true", "1", "null", "0", "true", "intostr",
  ])
}

///|
test "RegExp Symbol.search saves lastIndex and honors custom exec" {
  let src =
    #|var duringExec;
    #|var fakeRe = {
    #|  lastIndex: 34,
    #|  exec: function() { duringExec = this.lastIndex; return { index: 86 }; }
    #|};
    #|console.log(RegExp.prototype[Symbol.search].call(fakeRe, "abc"));
    #|console.log(duringExec);
    #|console.log(fakeRe.lastIndex);
    #|var badRe = { lastIndex: 0, exec: function() { return 1; } };
    #|try { RegExp.prototype[Symbol.search].call(badRe, "abc"); } catch (e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["86", "0", "34", "true"])
}

///|
test "RegExp Symbol.split uses captures, limit, and unicode advance" {
  let src =
    #|var parts = /(\d)/[Symbol.split]("a1b2", 4);
    #|console.log(parts.length);
    #|console.log(parts.join("|"));
    #|var borrowed = String.prototype.split.call("a1b", /(\d)/);
    #|console.log(borrowed.join("|"));
    #|var astral = /./u[Symbol.split]("\uD834\uDF06");
    #|console.log(astral.length);
    #|console.log(astral[0]);
    #|console.log(astral[1]);
    #|RegExp.prototype.constructor = {};
    #|console.log(/,/[Symbol.split]("a,b").join("|"));
    #|delete RegExp.prototype.constructor;
    #|console.log(/,/[Symbol.split]("c,d").join("|"));
    #|var firstCustomExec = true;
    #|var fakeSplitter = {
    #|  set lastIndex(value) { this._lastIndex = value; },
    #|  get lastIndex() { return this._lastIndex; },
    #|  exec: function() {
    #|    if (firstCustomExec) {
    #|      firstCustomExec = false;
    #|      this._lastIndex = 1;
    #|      return [];
    #|    }
    #|    return null;
    #|  }
    #|};
    #|var customRx = { flags: "u", constructor: function() {} };
    #|customRx.constructor[Symbol.species] = function() { return fakeSplitter; };
    #|var customParts = RegExp.prototype[Symbol.split].call(customRx, "\uD834\uDF06x");
    #|console.log(customParts.length);
    #|console.log(customParts[0].length);
    #|console.log(customParts[1].length);
    #|console.log(customParts[1].charCodeAt(0));
    #|console.log(customParts[1].charCodeAt(1));
  let output = run_output(src)
  json_inspect(output, content=[
    "4", "a|1|b|2", "a|1|b", "2", "", "", "a|b", "c|d", "2", "0", "2", "57094", "120",
  ])
}

///|
test "string replace" {
  let (_, result) = run_js("\"hello world\".replace(\"world\", \"there\")")
  expect_result(result, "hello there")
}

///|
test "string startsWith endsWith" {
  let src =
    #|console.log("hello".startsWith("hel"));
    #|console.log("hello".endsWith("llo"));
    #|console.log("hello".startsWith("llo"));
  let output = run_output(src)
  json_inspect(output, content=["true", "true", "false"])
}

///|
test "string repeat" {
  let (_, result) = run_js("\"ab\".repeat(3)")
  expect_result(result, "ababab")
}

///|
test "string padStart padEnd" {
  let src =
    #|console.log("5".padStart(3, "0"));
    #|console.log("hi".padEnd(5, "!"));
  let output = run_output(src)
  json_inspect(output, content=["005", "hi!!!"])
}

///|
test "string substring" {
  let (_, result) = run_js("\"hello\".substring(1, 4)")
  expect_result(result, "ell")
}

// ====== Phase 2: Object Methods ======

///|
test "object keys values entries" {
  let src =
    #|var obj = {a: 1, b: 2};
    #|console.log(Object.keys(obj).join(","));
    #|console.log(Object.values(obj).join(","));
  let output = run_output(src)
  json_inspect(output, content=["a,b", "1,2"])
}

///|
test "object assign" {
  let src =
    #|var target = {a: 1};
    #|Object.assign(target, {b: 2, c: 3});
    #|console.log(Object.keys(target).join(","));
  let output = run_output(src)
  json_inspect(output, content=["a,b,c"])
}

///|
test "object create" {
  let src =
    #|var proto = {greet: function() { return "hello"; }};
    #|var obj = Object.create(proto);
    #|console.log(obj.greet());
  let output = run_output(src)
  json_inspect(output, content=["hello"])
}

///|
test "object getPrototypeOf" {
  let src =
    #|var proto = {x: 1};
    #|var obj = Object.create(proto);
    #|var p = Object.getPrototypeOf(obj);
    #|console.log(p.x);
  let output = run_output(src)
  json_inspect(output, content=["1"])
}

///|
test "object getOwnPropertyNames" {
  let src =
    #|var obj = {a: 1, b: 2};
    #|console.log(Object.getOwnPropertyNames(obj).join(","));
  let output = run_output(src)
  json_inspect(output, content=["a,b"])
}

// ====== Phase 2: Math Object ======

///|
test "math constants" {
  let src =
    #|console.log(Math.PI > 3.14);
    #|console.log(Math.E > 2.71);
  let output = run_output(src)
  json_inspect(output, content=["true", "true"])
}

///|
test "math abs floor ceil round" {
  let src =
    #|console.log(Math.abs(-5));
    #|console.log(Math.floor(3.7));
    #|console.log(Math.ceil(3.2));
    #|console.log(Math.round(3.5));
  let output = run_output(src)
  json_inspect(output, content=["5", "3", "4", "4"])
}

///|
test "math round preserves negative zero" {
  let src =
    #|console.log(1 / Math.round(-0.1));
    #|console.log(1 / Math.round(-0.5));
    #|console.log(1 / Math.round(0.1));
  let output = run_output(src)
  json_inspect(output, content=["-Infinity", "-Infinity", "Infinity"])
}

///|
test "math sqrt pow" {
  let src =
    #|console.log(Math.sqrt(16));
    #|console.log(Math.pow(2, 10));
  let output = run_output(src)
  json_inspect(output, content=["4", "1024"])
}

///|
test "math min max" {
  let src =
    #|console.log(Math.min(3, 1, 2));
    #|console.log(Math.max(3, 1, 2));
  let output = run_output(src)
  json_inspect(output, content=["1", "3"])
}

///|
test "math trunc sign" {
  let src =
    #|console.log(Math.trunc(3.7));
    #|console.log(Math.trunc(-3.7));
    #|console.log(Math.sign(-5));
    #|console.log(Math.sign(0));
    #|console.log(Math.sign(3));
  let output = run_output(src)
  json_inspect(output, content=["3", "-3", "-1", "0", "1"])
}

///|
test "math log" {
  let src =
    #|console.log(Math.log(1));
    #|console.log(Math.log2(8));
    #|console.log(Math.log10(1000));
  let output = run_output(src)
  json_inspect(output, content=["0", "3", "3"])
}

// ====== Regression: .call/.apply/.bind dispatch only for callables ======

///|
test "object with own call method" {
  let src =
    #|var obj = { call: function() { return 1; } };
    #|console.log(obj.call());
  let output = run_output(src)
  json_inspect(output, content=["1"])
}

///|
test "object with own apply method" {
  let src =
    #|var obj = { apply: function(a) { return a + 1; } };
    #|console.log(obj.apply(10));
  let output = run_output(src)
  json_inspect(output, content=["11"])
}

///|
test "object with own bind method" {
  let src =
    #|var obj = { bind: function() { return "custom"; } };
    #|console.log(obj.bind());
  let output = run_output(src)
  json_inspect(output, content=["custom"])
}

// ====== Regression: bound function propagates errors ======

///|
test "bound function propagates throw" {
  let src =
    #|function explode() { throw "boom"; }
    #|var b = explode.bind(null);
    #|try {
    #|  b();
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["boom"])
}

///|
test "bound function propagates runtime error" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      "function bad() { return null.x; } var b = bad.bind(null); b();",
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "other error"
  }
  guard !err_msg.contains("Cannot read property") else {
    fail("error message unexpectedly contained Cannot read property")
  }
}

// ====== Regression: hasOwnProperty on inherited objects ======

///|
test "hasOwnProperty via Object.create" {
  let src =
    #|var proto = { inherited: 1 };
    #|var child = Object.create(proto);
    #|child.own = 2;
    #|console.log(child.hasOwnProperty("own"));
    #|console.log(child.hasOwnProperty("inherited"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "hasOwnProperty coerces key before null receiver check" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var touched = "";
    #|var key = {
    #|  get toString() {
    #|    touched = "toString";
    #|    throw new MyError();
    #|  }
    #|};
    #|try {
    #|  Object.prototype.hasOwnProperty.call(null, key);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(touched);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError", "toString"])
}

///|
test "startsWith negative position" {
  let src =
    #|console.log("abc".startsWith("a", -1));
    #|console.log("abc".startsWith("abc", -100));
  let output = run_output(src)
  json_inspect(output, content=["true", "true"])
}

///|
test "startsWith empty string with large position" {
  let src =
    #|console.log("abc".startsWith("", 100));
    #|console.log("abc".startsWith("", -1));
  let output = run_output(src)
  json_inspect(output, content=["true", "true"])
}

///|
test "startsWith position edge cases" {
  let src =
    #|console.log("abc".startsWith("a", -999));
    #|console.log("abc".startsWith("a", 999));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "indexOf lastIndexOf more edge cases" {
  let src =
    #|console.log("abc".indexOf("", -5));
    #|console.log("abc".lastIndexOf("", 2));
  let output = run_output(src)
  json_inspect(output, content=["0", "2"])
}

///|
test "hasOwnProperty missing argument" {
  let src =
    #|var obj = { "undefined": 1 };
    #|console.log(obj.hasOwnProperty());
    #|var obj2 = { a: 1 };
    #|console.log(obj2.hasOwnProperty());
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "callable with own call property" {
  let src =
    #|function f() { return "original"; }
    #|f.call = function(t) { return "overridden"; };
    #|console.log(f.call(null));
  let output = run_output(src)
  json_inspect(output, content=["overridden"])
}

///|
test "array includes NaN" {
  let src =
    #|var arr = [1, NaN, 3];
    #|console.log(arr.includes(NaN));
    #|console.log(arr.includes(2));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "endsWith large end position" {
  let src =
    #|console.log("abc".endsWith("c", 100));
    #|console.log("abc".endsWith("c", 3));
    #|console.log("abc".endsWith("a", 1));
    #|console.log("abc".endsWith("c", 0));
  let output = run_output(src)
  json_inspect(output, content=["true", "true", "true", "false"])
}

///|
test "computed hasOwnProperty" {
  let src =
    #|var obj = { a: 1 };
    #|console.log(obj["hasOwnProperty"]("a"));
    #|console.log(obj["hasOwnProperty"]("b"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "computed call apply bind" {
  let src =
    #|function greet(x) { return this.name + x; }
    #|var obj = { name: "hi" };
    #|console.log(greet["call"](obj, "!"));
    #|console.log(greet["apply"](obj, ["?"]));
    #|var bound = greet["bind"](obj);
    #|console.log(bound("."));
  let output = run_output(src)
  json_inspect(output, content=["hi!", "hi?", "hi."])
}

///|
test "math random non-deterministic" {
  let src =
    #|var a = Math.random();
    #|var b = Math.random();
    #|console.log(a >= 0 && a < 1);
    #|console.log(b >= 0 && b < 1);
    #|console.log(a !== b);
  let output = run_output(src)
  json_inspect(output, content=["true", "true", "true"])
}

///|
test "f.call is a function" {
  let src =
    #|function f() {}
    #|console.log(typeof f.call);
    #|console.log(typeof f.apply);
    #|console.log(typeof f.bind);
  let output = run_output(src)
  json_inspect(output, content=["function", "function", "function"])
}

///|
test "stored call method throws TypeError" {
  // Detached .call: `c` is Function.prototype.call, but called with this=undefined
  // which means .call tries to invoke undefined as a function → TypeError
  let src =
    #|function add(x) { return this.val + x; }
    #|var c = add.call;
    #|var obj = { val: 10 };
    #|try { c(obj, 5); } catch(e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "stored bind method throws TypeError" {
  // Detached .bind: `b` is Function.prototype.bind, but called with this=undefined
  // which is not callable → TypeError
  let src =
    #|function greet() { return this.msg; }
    #|var b = greet.bind;
    #|try { b({ msg: "hello" }); } catch(e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "hasOwnProperty method borrowing" {
  let src =
    #|var a = { x: 1 };
    #|var b = { y: 2 };
    #|var hop = a.hasOwnProperty;
    #|console.log(hop.call(b, "y"));
    #|console.log(hop.call(b, "x"));
    #|console.log(hop.call(a, "x"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "true"])
}

// ====== Phase 3A: Arguments Object ======

///|
test "arguments object basic" {
  let src =
    #|function f() {
    #|  return arguments.length;
    #|}
    #|console.log(f(1, 2, 3));
  let output = run_output(src)
  json_inspect(output, content=["3"])
}

///|
test "arguments object index access" {
  let src =
    #|function f() {
    #|  return arguments[0] + arguments[1];
    #|}
    #|console.log(f(10, 20));
  let output = run_output(src)
  json_inspect(output, content=["30"])
}

///|
test "arguments object callee" {
  let src =
    #|function factorial(n) {
    #|  if (n <= 1) return 1;
    #|  return n * arguments.callee(n - 1);
    #|}
    #|console.log(factorial(5));
  let output = run_output(src)
  json_inspect(output, content=["120"])
}

///|
test "arguments not in arrow functions" {
  let src =
    #|function outer() {
    #|  var arrow = () => arguments.length;
    #|  return arrow();
    #|}
    #|console.log(outer(1, 2, 3));
  let output = run_output(src)
  json_inspect(output, content=["3"])
}

// ====== Phase 3A: Hoisting ======

///|
test "var hoisting" {
  let src =
    #|console.log(x);
    #|var x = 5;
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["undefined", "5"])
}

///|
test "function hoisting" {
  let src =
    #|console.log(f());
    #|function f() { return 42; }
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "var hoisting in function" {
  let src =
    #|function test() {
    #|  console.log(x);
    #|  var x = 10;
    #|  console.log(x);
    #|}
    #|test();
  let output = run_output(src)
  json_inspect(output, content=["undefined", "10"])
}

///|
test "var hoisting does not overwrite" {
  let src =
    #|var x = 1;
    #|var x = 2;
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["2"])
}

// ====== Phase 3A: String.fromCharCode ======

///|
test "String.fromCharCode basic" {
  let (_, result) = run_js("String.fromCharCode(72, 101, 108, 108, 111)")
  expect_result(result, "Hello")
}

///|
test "String.fromCharCode single" {
  let (_, result) = run_js("String.fromCharCode(65)")
  expect_result(result, "A")
}

// ====== Phase 3A: Number builtins ======

///|
test "Number.isNaN" {
  let src =
    #|console.log(Number.isNaN(NaN));
    #|console.log(Number.isNaN(42));
    #|console.log(Number.isNaN("hello"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "false"])
}

///|
test "Number.isFinite" {
  let src =
    #|console.log(Number.isFinite(42));
    #|console.log(Number.isFinite(Infinity));
    #|console.log(Number.isFinite("42"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "false"])
}

///|
test "Number.isInteger" {
  let src =
    #|console.log(Number.isInteger(42));
    #|console.log(Number.isInteger(42.5));
    #|console.log(Number.isInteger("42"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "false"])
}

///|
test "Number.MAX_SAFE_INTEGER" {
  let (_, result) = run_js("Number.MAX_SAFE_INTEGER")
  expect_result(result, "9007199254740991")
}

///|
test "Number.EPSILON" {
  let output = run_output("console.log(Number.EPSILON < 1)")
  json_inspect(output, content=["true"])
}

///|
test "number toFixed" {
  let src =
    #|var n = 3.14159;
    #|console.log(n.toFixed(2));
    #|console.log(n.toFixed(0));
  let output = run_output(src)
  json_inspect(output, content=["3.14", "3"])
}

///|
test "number toString radix" {
  let src =
    #|var n = 255;
    #|console.log(n.toString(16));
    #|console.log(n.toString(2));
  let output = run_output(src)
  json_inspect(output, content=["ff", "11111111"])
}

///|
test "number toString formats negative zero as zero" {
  let src =
    #|console.log((-0).toString());
    #|console.log(new Number(-0).toString());
    #|console.log(Number.prototype.toString.call(-0));
  let output = run_output(src)
  json_inspect(output, content=["0", "0", "0"])
}

///|
test "Number.parseInt parseFloat" {
  let src =
    #|console.log(Number.parseInt("42"));
    #|console.log(Number.parseFloat("3.14"));
  let output = run_output(src)
  json_inspect(output, content=["42", "3.14"])
}

// ====== Phase 3A: Error hierarchy polish ======

///|
test "Error has stack property" {
  let src =
    #|var e = new Error("test");
    #|console.log(typeof e.stack);
  let output = run_output(src)
  json_inspect(output, content=["string"])
}

///|
test "Error.prototype.toString" {
  let src =
    #|var e = new Error("test");
    #|console.log(e.name);
    #|console.log(e.message);
  let output = run_output(src)
  json_inspect(output, content=["Error", "test"])
}

// ====== Phase 3A: JSON ======

///|
test "JSON.parse basic" {
  let src =
    #|var obj = JSON.parse('{"a":1,"b":"hello"}');
    #|console.log(obj.a);
    #|console.log(obj.b);
  let output = run_output(src)
  json_inspect(output, content=["1", "hello"])
}

///|
test "JSON.parse array" {
  let src =
    #|var arr = JSON.parse('[1, 2, 3]');
    #|console.log(arr.length);
    #|console.log(arr[0]);
  let output = run_output(src)
  json_inspect(output, content=["3", "1"])
}

///|
test "JSON.parse nested" {
  let src =
    #|var obj = JSON.parse('{"a":{"b":42}}');
    #|console.log(obj.a.b);
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "JSON.parse booleans null" {
  let src =
    #|var obj = JSON.parse('{"t":true,"f":false,"n":null}');
    #|console.log(obj.t);
    #|console.log(obj.f);
    #|console.log(obj.n);
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "null"])
}

///|
test "JSON.parse parsed object has Object.prototype" {
  let src =
    #|var x = JSON.parse('{"a":1}');
    #|console.log(Object.getPrototypeOf(x) === Object.prototype);
    #|console.log(x.hasOwnProperty('a'));
  let output = run_output(src)
  json_inspect(output, content=["true", "true"])
}

///|
test "JSON.parse reviver accessor getter error propagates" {
  let src =
    #|var err = null;
    #|try {
    #|  JSON.parse('[0,1]', function() {
    #|    Object.defineProperty(this, '1', { get: function() { throw new Error('trap'); } });
    #|  });
    #|} catch(e) { err = e.message; }
    #|console.log(err);
  let output = run_output(src)
  json_inspect(output, content=["trap"])
}

///|
test "JSON.parse reviver Proxy deleteProperty trap error propagates" {
  let src =
    #|var err = null;
    #|try {
    #|  JSON.parse('[0,1]', function() {
    #|    this[1] = new Proxy([0], { deleteProperty: function() { throw new Error('del'); } });
    #|  });
    #|} catch(e) { err = e.message; }
    #|console.log(err);
  let output = run_output(src)
  json_inspect(output, content=["del"])
}

///|
test "JSON.parse reviver Proxy ownKeys trap error propagates" {
  let src =
    #|var err = null;
    #|try {
    #|  JSON.parse('[0,1]', function() {
    #|    this[1] = new Proxy({}, { ownKeys: function() { throw new Error('keys'); } });
    #|  });
    #|} catch(e) { err = e.message; }
    #|console.log(err);
  let output = run_output(src)
  json_inspect(output, content=["keys"])
}

///|
test "JSON.stringify basic" {
  let src =
    #|var obj = {a: 1, b: "hello"};
    #|console.log(JSON.stringify(obj));
  let output = run_output(src)
  expect_first_output(output, "{\"a\":1,\"b\":\"hello\"}")
}

///|
test "JSON.stringify array" {
  let src =
    #|console.log(JSON.stringify([1, 2, 3]));
  let output = run_output(src)
  json_inspect(output, content=["[1,2,3]"])
}

///|
test "JSON.stringify null undefined" {
  let src =
    #|console.log(JSON.stringify(null));
    #|console.log(JSON.stringify(42));
    #|console.log(JSON.stringify("hello"));
    #|console.log(JSON.stringify(true));
  let output = run_output(src)
  json_inspect(output, content=["null", "42", "\"hello\"", "true"])
}

///|
test "JSON.stringify skips functions" {
  let src =
    #|var obj = {a: 1, b: function() {}};
    #|console.log(JSON.stringify(obj));
  let output = run_output(src)
  expect_first_output(output, "{\"a\":1}")
}

// ====== Phase 3B: Array Higher-Order Functions ======

///|
test "array map" {
  let src =
    #|var arr = [1, 2, 3];
    #|var result = arr.map(function(x) { return x * 2; });
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["2,4,6"])
}

///|
test "array map with arrow" {
  let src =
    #|var arr = [1, 2, 3];
    #|var result = arr.map(x => x * x);
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["1,4,9"])
}

///|
test "array filter" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|var result = arr.filter(x => x % 2 === 0);
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["2,4"])
}

///|
test "array reduce" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|var sum = arr.reduce(function(acc, x) { return acc + x; }, 0);
    #|console.log(sum);
  let output = run_output(src)
  json_inspect(output, content=["10"])
}

///|
test "array reduce no initial" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|var sum = arr.reduce(function(acc, x) { return acc + x; });
    #|console.log(sum);
  let output = run_output(src)
  json_inspect(output, content=["10"])
}

///|
test "array forEach" {
  let src =
    #|var result = [];
    #|[1, 2, 3].forEach(function(x) { result.push(x * 10); });
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["10,20,30"])
}

///|
test "array find" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|console.log(arr.find(x => x > 2));
    #|console.log(arr.find(x => x > 10));
  let output = run_output(src)
  json_inspect(output, content=["3", "undefined"])
}

///|
test "array findIndex" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|console.log(arr.findIndex(x => x > 2));
    #|console.log(arr.findIndex(x => x > 10));
  let output = run_output(src)
  json_inspect(output, content=["2", "-1"])
}

///|
test "array every" {
  let src =
    #|console.log([2, 4, 6].every(x => x % 2 === 0));
    #|console.log([2, 3, 6].every(x => x % 2 === 0));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "array some" {
  let src =
    #|console.log([1, 3, 5].some(x => x % 2 === 0));
    #|console.log([1, 2, 5].some(x => x % 2 === 0));
  let output = run_output(src)
  json_inspect(output, content=["false", "true"])
}

///|
test "array flat" {
  let src =
    #|var arr = [1, [2, 3], [4, [5]]];
    #|console.log(arr.flat().join(","));
  let output = run_output(src)
  json_inspect(output, content=["1,2,3,4,5"])
}

///|
test "array flatMap" {
  let src =
    #|var arr = [1, 2, 3];
    #|var result = arr.flatMap(x => [x, x * 2]);
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["1,2,2,4,3,6"])
}

///|
test "array sort with compareFn" {
  let src =
    #|var arr = [3, 1, 4, 1, 5];
    #|arr.sort(function(a, b) { return a - b; });
    #|console.log(arr.join(","));
  let output = run_output(src)
  json_inspect(output, content=["1,1,3,4,5"])
}

///|
test "array reduceRight" {
  let src =
    #|var arr = ["a", "b", "c"];
    #|var result = arr.reduceRight(function(acc, x) { return acc + x; });
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["cba"])
}

///|
test "array map with index" {
  let src =
    #|var arr = ["a", "b", "c"];
    #|var result = arr.map(function(val, idx) { return idx + ":" + val; });
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["0:a,1:b,2:c"])
}

///|
test "JSON.parse then stringify roundtrip" {
  let src =
    #|var str = '{"x":1,"y":[2,3]}';
    #|var obj = JSON.parse(str);
    #|console.log(JSON.stringify(obj));
  let output = run_output(src)
  expect_first_output(output, "{\"x\":1,\"y\":[2,3]}")
}

// ============================================================
// Phase 3C: for-of, spread, default params, rest params
// ============================================================

///|
test "for-of array" {
  let src =
    #|var arr = [10, 20, 30];
    #|var sum = 0;
    #|for (var x of arr) { sum += x; }
    #|console.log(sum);
  let output = run_output(src)
  json_inspect(output, content=["60"])
}

///|
test "for-of array iterator observes live length" {
  let src =
    #|var growing = [1];
    #|var growOut = [];
    #|for (var x of growing) {
    #|  growOut.push(x);
    #|  if (x === 1) growing.push(2);
    #|}
    #|console.log(growOut.join(","));
    #|var shrinking = [1, 2];
    #|var shrinkOut = [];
    #|for (var y of shrinking) {
    #|  shrinkOut.push(y);
    #|  shrinking.length = 1;
    #|}
    #|console.log(shrinkOut.join(","));
  let output = run_output(src)
  json_inspect(output, content=["1,2", "1"])
}

///|
test "for-of with let" {
  let src =
    #|var arr = ["a", "b", "c"];
    #|var result = "";
    #|for (let x of arr) { result += x; }
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["abc"])
}

///|
test "for-of string" {
  let src =
    #|var result = [];
    #|for (var ch of "hello") { result.push(ch); }
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["h,e,l,l,o"])
}

///|
test "for-of with break" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|var sum = 0;
    #|for (var x of arr) {
    #|  if (x === 4) break;
    #|  sum += x;
    #|}
    #|console.log(sum);
  let output = run_output(src)
  json_inspect(output, content=["6"])
}

///|
test "for-of with continue" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|var sum = 0;
    #|for (var x of arr) {
    #|  if (x % 2 === 0) continue;
    #|  sum += x;
    #|}
    #|console.log(sum);
  let output = run_output(src)
  json_inspect(output, content=["9"])
}

///|
test "arguments object Symbol.iterator" {
  let src =
    #|function collect() {
    #|  var out = [];
    #|  for (var value of arguments) { out.push(value); }
    #|  return out.join(",");
    #|}
    #|function C() {
    #|  var out = [];
    #|  for (var value of arguments) { out.push(value); }
    #|  this.value = out.join("-");
    #|}
    #|console.log(collect("a", "b", "c"));
    #|console.log(new C(1, 2).value);
  let output = run_output(src)
  json_inspect(output, content=["a,b,c", "1-2"])
}

///|
test "spread in array literal" {
  let src =
    #|var a = [1, 2, 3];
    #|var b = [0, ...a, 4];
    #|console.log(b.join(","));
  let output = run_output(src)
  json_inspect(output, content=["0,1,2,3,4"])
}

///|
test "spread in function call" {
  let src =
    #|function add(a, b, c) { return a + b + c; }
    #|var args = [1, 2, 3];
    #|console.log(add(...args));
  let output = run_output(src)
  json_inspect(output, content=["6"])
}

///|
test "spread with concat" {
  let src =
    #|var a = [1, 2];
    #|var b = [3, 4];
    #|var c = [...a, ...b];
    #|console.log(c.join(","));
  let output = run_output(src)
  json_inspect(output, content=["1,2,3,4"])
}

///|
test "spread string in array" {
  let src =
    #|var arr = [..."abc"];
    #|console.log(arr.join(","));
  let output = run_output(src)
  json_inspect(output, content=["a,b,c"])
}

///|
test "default parameter" {
  let src =
    #|function greet(name = "world") {
    #|  return "Hello, " + name + "!";
    #|}
    #|console.log(greet());
    #|console.log(greet("Alice"));
  let output = run_output(src)
  json_inspect(output, content=["Hello, world!", "Hello, Alice!"])
}

///|
test "default parameter with expression" {
  let src =
    #|function add(a, b = a * 2) {
    #|  return a + b;
    #|}
    #|console.log(add(3));
    #|console.log(add(3, 5));
  let output = run_output(src)
  json_inspect(output, content=["9", "8"])
}

///|
test "default parameter undefined triggers default" {
  let src =
    #|function f(x = 10) { return x; }
    #|console.log(f(undefined));
    #|console.log(f(null));
    #|console.log(f(0));
  let output = run_output(src)
  json_inspect(output, content=["10", "null", "0"])
}

///|
test "rest parameter" {
  let src =
    #|function sum(...nums) {
    #|  var total = 0;
    #|  for (var i = 0; i < nums.length; i++) {
    #|    total += nums[i];
    #|  }
    #|  return total;
    #|}
    #|console.log(sum(1, 2, 3, 4));
  let output = run_output(src)
  json_inspect(output, content=["10"])
}

///|
test "rest parameter with leading params" {
  let src =
    #|function first_and_rest(first, ...rest) {
    #|  return first + ":" + rest.join(",");
    #|}
    #|console.log(first_and_rest("a", "b", "c", "d"));
  let output = run_output(src)
  json_inspect(output, content=["a:b,c,d"])
}

///|
test "rest parameter empty" {
  let src =
    #|function f(a, ...rest) {
    #|  return rest.length;
    #|}
    #|console.log(f(1));
  let output = run_output(src)
  json_inspect(output, content=["0"])
}

///|
test "default and rest combined" {
  let src =
    #|function f(a = 1, b = 2, ...rest) {
    #|  return a + "," + b + "," + rest.join(";");
    #|}
    #|console.log(f());
    #|console.log(f(10));
    #|console.log(f(10, 20, 30, 40));
  let output = run_output(src)
  json_inspect(output, content=["1,2,", "10,2,", "10,20,30;40"])
}

///|
test "arrow function with default param" {
  let src =
    #|var greet = (name = "world") => "Hello, " + name;
    #|console.log(greet());
    #|console.log(greet("Bob"));
  let output = run_output(src)
  json_inspect(output, content=["Hello, world", "Hello, Bob"])
}

///|
test "arrow function with rest param" {
  let src =
    #|var sum = (...args) => {
    #|  var total = 0;
    #|  for (var i = 0; i < args.length; i++) total += args[i];
    #|  return total;
    #|};
    #|console.log(sum(1, 2, 3));
  let output = run_output(src)
  json_inspect(output, content=["6"])
}

///|
test "function expression with default" {
  let src =
    #|var f = function(x = 5) { return x * 2; };
    #|console.log(f());
    #|console.log(f(3));
  let output = run_output(src)
  json_inspect(output, content=["10", "6"])
}

///|
test "function expression with rest" {
  let src =
    #|var f = function(first, ...rest) { return rest; };
    #|var result = f(1, 2, 3);
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["2,3"])
}

///|
test "function without return yields undefined" {
  let src =
    #|function f() {
    #|  1 + 2;
    #|}
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["undefined"])
}

///|
test "array map callback without return yields undefined" {
  let src =
    #|var result = [1].map(function(x) { x + 1; });
    #|console.log(result[0]);
  let output = run_output(src)
  json_inspect(output, content=["undefined"])
}

///|
test "spread in new expression" {
  let src =
    #|function Point(x, y) {
    #|  this.x = x;
    #|  this.y = y;
    #|}
    #|var coords = [10, 20];
    #|var p = new Point(...coords);
    #|console.log(p.x + "," + p.y);
  let output = run_output(src)
  json_inspect(output, content=["10,20"])
}

///|
test "for-of bare identifier" {
  let src =
    #|var arr = [1, 2, 3];
    #|var sum = 0;
    #|var x;
    #|for (x of arr) { sum += x; }
    #|console.log(sum);
  let output = run_output(src)
  json_inspect(output, content=["6"])
}

///|
test "for-of with const" {
  let src =
    #|var result = [];
    #|for (const item of [10, 20, 30]) {
    #|  result.push(item);
    #|}
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["10,20,30"])
}

///|
test "spread copies array" {
  let src =
    #|var a = [1, 2, 3];
    #|var b = [...a];
    #|b[0] = 99;
    #|console.log(a[0]);
    #|console.log(b[0]);
  let output = run_output(src)
  json_inspect(output, content=["1", "99"])
}

///|
test "default param with function call" {
  let src =
    #|function getDefault() { return 42; }
    #|function f(x = getDefault()) { return x; }
    #|console.log(f());
    #|console.log(f(10));
  let output = run_output(src)
  json_inspect(output, content=["42", "10"])
}

///|
test "multiple default params" {
  let src =
    #|function f(a = 1, b = 2, c = 3) {
    #|  return a + b + c;
    #|}
    #|console.log(f());
    #|console.log(f(10));
    #|console.log(f(10, 20));
    #|console.log(f(10, 20, 30));
  let output = run_output(src)
  json_inspect(output, content=["6", "15", "33", "60"])
}

///|
test "for-of return from function" {
  let src =
    #|function findFirst(arr) {
    #|  for (var x of arr) {
    #|    if (x > 3) return x;
    #|  }
    #|  return -1;
    #|}
    #|console.log(findFirst([1, 2, 5, 3]));
  let output = run_output(src)
  json_inspect(output, content=["5"])
}

///|
test "spread in middle of array" {
  let src =
    #|var mid = [3, 4];
    #|var arr = [1, 2, ...mid, 5, 6];
    #|console.log(arr.length);
    #|console.log(arr.join(","));
  let output = run_output(src)
  json_inspect(output, content=["6", "1,2,3,4,5,6"])
}

///|
test "rest with array methods" {
  let src =
    #|function tail(...args) {
    #|  return args.slice(1);
    #|}
    #|var result = tail(1, 2, 3, 4);
    #|console.log(result.join(","));
  let output = run_output(src)
  json_inspect(output, content=["2,3,4"])
}

///|
test "spread function call with extra args" {
  let src =
    #|function f(a, b, c, d) { return a + b + c + d; }
    #|var arr = [1, 2];
    #|console.log(f(...arr, 3, 4));
  let output = run_output(src)
  json_inspect(output, content=["10"])
}

// ============================================================
// Phase 3D: Destructuring
// ============================================================

///|
test "array destructuring basic" {
  let src =
    #|var [a, b, c] = [1, 2, 3];
    #|console.log(a + "," + b + "," + c);
  let output = run_output(src)
  json_inspect(output, content=["1,2,3"])
}

///|
test "array destructuring with rest" {
  let src =
    #|let [first, ...rest] = [1, 2, 3, 4, 5];
    #|console.log(first);
    #|console.log(rest.join(","));
  let output = run_output(src)
  json_inspect(output, content=["1", "2,3,4,5"])
}

///|
test "array destructuring with holes" {
  let src =
    #|var [a, , b] = [1, 2, 3];
    #|console.log(a + "," + b);
  let output = run_output(src)
  json_inspect(output, content=["1,3"])
}

///|
test "array destructuring fewer elements" {
  let src =
    #|var [a, b, c] = [1, 2];
    #|console.log(a);
    #|console.log(b);
    #|console.log(c);
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "undefined"])
}

///|
test "object destructuring basic" {
  let src =
    #|var {x, y} = {x: 10, y: 20};
    #|console.log(x + "," + y);
  let output = run_output(src)
  json_inspect(output, content=["10,20"])
}

///|
test "object destructuring with alias" {
  let src =
    #|var {name: n, age: a} = {name: "Alice", age: 30};
    #|console.log(n + " is " + a);
  let output = run_output(src)
  json_inspect(output, content=["Alice is 30"])
}

///|
test "object destructuring with default" {
  let src =
    #|var {x, y = 5} = {x: 10};
    #|console.log(x + "," + y);
  let output = run_output(src)
  json_inspect(output, content=["10,5"])
}

///|
test "object destructuring with rest" {
  let src =
    #|var {a, ...rest} = {a: 1, b: 2, c: 3};
    #|console.log(a);
    #|console.log(rest.b);
    #|console.log(rest.c);
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "3"])
}

///|
test "nested array destructuring" {
  let src =
    #|var [a, [b, c]] = [1, [2, 3]];
    #|console.log(a + "," + b + "," + c);
  let output = run_output(src)
  json_inspect(output, content=["1,2,3"])
}

///|
test "nested object destructuring" {
  let src =
    #|var {a, b: {c, d}} = {a: 1, b: {c: 2, d: 3}};
    #|console.log(a + "," + c + "," + d);
  let output = run_output(src)
  json_inspect(output, content=["1,2,3"])
}

///|
test "destructuring in let" {
  let src =
    #|let [x, y] = [100, 200];
    #|console.log(x + y);
  let output = run_output(src)
  json_inspect(output, content=["300"])
}

///|
test "destructuring in const" {
  let src =
    #|const {PI, E} = {PI: 3.14, E: 2.72};
    #|console.log(PI);
    #|console.log(E);
  let output = run_output(src)
  json_inspect(output, content=["3.14", "2.72"])
}

///|
test "array destructuring with rest empty" {
  let src =
    #|var [a, b, ...rest] = [1, 2];
    #|console.log(a);
    #|console.log(b);
    #|console.log(rest.length);
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "0"])
}

///|
test "object destructuring alias with default" {
  let src =
    #|var {name: n = "unknown", age: a = 0} = {name: "Bob"};
    #|console.log(n);
    #|console.log(a);
  let output = run_output(src)
  json_inspect(output, content=["Bob", "0"])
}

///|
test "destructuring from function return" {
  let src =
    #|function getPoint() { return {x: 10, y: 20}; }
    #|var {x, y} = getPoint();
    #|console.log(x + "," + y);
  let output = run_output(src)
  json_inspect(output, content=["10,20"])
}

///|
test "array destructuring from function return" {
  let src =
    #|function getCoords() { return [3, 4]; }
    #|var [x, y] = getCoords();
    #|console.log(x + "," + y);
  let output = run_output(src)
  json_inspect(output, content=["3,4"])
}

///|
test "swap with array destructuring" {
  let src =
    #|var a = 1;
    #|var b = 2;
    #|var [c, d] = [b, a];
    #|console.log(c + "," + d);
  let output = run_output(src)
  json_inspect(output, content=["2,1"])
}

///|
test "destructuring with computed property from array" {
  let src =
    #|var arr = [10, 20, 30, 40, 50];
    #|var [, second, , fourth] = arr;
    #|console.log(second + "," + fourth);
  let output = run_output(src)
  json_inspect(output, content=["20,40"])
}

///|
test "object destructuring missing key" {
  let src =
    #|var {a, b, c} = {a: 1};
    #|console.log(a);
    #|console.log(b);
    #|console.log(c);
  let output = run_output(src)
  json_inspect(output, content=["1", "undefined", "undefined"])
}

///|
test "mixed nested destructuring" {
  let src =
    #|var {data: [first, second], count} = {data: [10, 20], count: 2};
    #|console.log(first + "," + second + "," + count);
  let output = run_output(src)
  json_inspect(output, content=["10,20,2"])
}

// ============================================================
// Phase 3E: Property Descriptors + Object.freeze/seal
// ============================================================

///|
test "Object.defineProperty basic" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 42 });
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "Object.defineProperty non-writable" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 42, writable: false });
    #|obj.x = 100;
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "Object.defineProperty non-enumerable" {
  let src =
    #|var obj = {a: 1, b: 2};
    #|Object.defineProperty(obj, "c", { value: 3, enumerable: false });
    #|console.log(Object.keys(obj).join(","));
    #|console.log(obj.c);
  let output = run_output(src)
  json_inspect(output, content=["a,b", "3"])
}

///|
test "Object.defineProperty non-configurable cannot delete" {
  let src =
    #|var obj = {x: 1};
    #|Object.defineProperty(obj, "x", { configurable: false });
    #|var result = delete obj.x;
    #|console.log(result);
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["false", "1"])
}

///|
test "Object.getOwnPropertyDescriptor" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 5, writable: false, enumerable: true, configurable: false });
    #|var desc = Object.getOwnPropertyDescriptor(obj, "x");
    #|console.log(desc.value);
    #|console.log(desc.writable);
    #|console.log(desc.enumerable);
    #|console.log(desc.configurable);
  let output = run_output(src)
  json_inspect(output, content=["5", "false", "true", "false"])
}

///|
test "Object.freeze" {
  let src =
    #|var obj = {x: 1, y: 2};
    #|Object.freeze(obj);
    #|obj.x = 100;
    #|obj.z = 3;
    #|console.log(obj.x);
    #|console.log(obj.z);
    #|console.log(Object.isFrozen(obj));
  let output = run_output(src)
  json_inspect(output, content=["1", "undefined", "true"])
}

///|
test "Object.seal" {
  let src =
    #|var obj = {x: 1, y: 2};
    #|Object.seal(obj);
    #|obj.x = 100;
    #|obj.z = 3;
    #|var result = delete obj.x;
    #|console.log(obj.x);
    #|console.log(obj.z);
    #|console.log(result);
    #|console.log(Object.isSealed(obj));
  let output = run_output(src)
  json_inspect(output, content=["100", "undefined", "false", "true"])
}

///|
test "Object.preventExtensions" {
  let src =
    #|var obj = {x: 1};
    #|Object.preventExtensions(obj);
    #|obj.y = 2;
    #|console.log(obj.x);
    #|console.log(obj.y);
    #|console.log(Object.isExtensible(obj));
  let output = run_output(src)
  json_inspect(output, content=["1", "undefined", "false"])
}

///|
test "Object.isFrozen on non-frozen object" {
  let src =
    #|var obj = {x: 1};
    #|console.log(Object.isFrozen(obj));
  let output = run_output(src)
  json_inspect(output, content=["false"])
}

///|
test "Object.isSealed on non-sealed object" {
  let src =
    #|var obj = {x: 1};
    #|console.log(Object.isSealed(obj));
  let output = run_output(src)
  json_inspect(output, content=["false"])
}

///|
test "Object.isExtensible on regular object" {
  let src =
    #|var obj = {};
    #|console.log(Object.isExtensible(obj));
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "Object.defineProperty with value update" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 1, writable: true, configurable: true });
    #|console.log(obj.x);
    #|Object.defineProperty(obj, "x", { value: 2 });
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["1", "2"])
}

///|
test "Object.freeze prevents delete" {
  let src =
    #|var obj = {x: 1};
    #|Object.freeze(obj);
    #|var result = delete obj.x;
    #|console.log(result);
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["false", "1"])
}

///|
test "non-enumerable not in for-in" {
  let src =
    #|var obj = {a: 1, b: 2};
    #|Object.defineProperty(obj, "c", { value: 3, enumerable: false });
    #|var keys = [];
    #|for (var k in obj) { keys.push(k); }
    #|console.log(keys.join(","));
  let output = run_output(src)
  json_inspect(output, content=["a,b"])
}

///|
test "Object.defineProperties" {
  let src =
    #|var obj = {};
    #|Object.defineProperties(obj, {
    #|  x: { value: 10, writable: false },
    #|  y: { value: 20, writable: true }
    #|});
    #|obj.x = 99;
    #|obj.y = 99;
    #|console.log(obj.x);
    #|console.log(obj.y);
  let output = run_output(src)
  json_inspect(output, content=["10", "99"])
}

///|
test "getOwnPropertyDescriptor missing prop" {
  let src =
    #|var obj = {x: 1};
    #|var desc = Object.getOwnPropertyDescriptor(obj, "y");
    #|console.log(desc);
  let output = run_output(src)
  json_inspect(output, content=["undefined"])
}

///|
test "freeze with Object.keys" {
  let src =
    #|var obj = {a: 1, b: 2, c: 3};
    #|Object.freeze(obj);
    #|console.log(Object.keys(obj).join(","));
  let output = run_output(src)
  json_inspect(output, content=["a,b,c"])
}

// ============================================================
// Phase 3F: Strict Mode
// ============================================================

///|
test "use strict: this is undefined in function call" {
  let src =
    #|"use strict";
    #|function getThis() { return this; }
    #|var result = getThis();
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["undefined"])
}

///|
test "use strict: assignment to read-only throws" {
  let src =
    #|"use strict";
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 42, writable: false });
    #|try {
    #|  obj.x = 100;
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot assign to read only property 'x'",
  ])
}

///|
test "use strict: assignment to frozen object throws" {
  let src =
    #|"use strict";
    #|var obj = {x: 1};
    #|Object.freeze(obj);
    #|try {
    #|  obj.x = 100;
    #|} catch(e) {
    #|  console.log(e);
    #|}
    #|try {
    #|  obj.y = 2;
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot assign to read only property 'x'", "TypeError: Cannot add property y, object is not extensible",
  ])
}

///|
test "use strict: delete non-configurable throws" {
  let src =
    #|"use strict";
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 1, configurable: false });
    #|try {
    #|  delete obj.x;
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError: Cannot delete property 'x'"])
}

///|
test "use strict: no arguments.callee" {
  let src =
    #|"use strict";
    #|function f() {
    #|  try { arguments.callee; return "no error"; }
    #|  catch(e) { return e instanceof TypeError; }
    #|}
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "function-level use strict" {
  let src =
    #|function f() {
    #|  "use strict";
    #|  return this;
    #|}
    #|var result = f();
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["undefined"])
}

///|
test "non-strict mode: this is not undefined" {
  let src =
    #|function getThis() { return typeof this; }
    #|console.log(getThis());
  let output = run_output(src)
  json_inspect(output, content=["object"])
}

///|
test "strict mode: sloppy function has arguments.callee" {
  let src =
    #|function f() {
    #|  return typeof arguments.callee;
    #|}
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["function"])
}

///|
test "use strict in global scope" {
  let src =
    #|"use strict";
    #|var x = 10;
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["10"])
}

///|
test "strict mode: non-writable silent in sloppy" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 42, writable: false });
    #|obj.x = 100;
    #|console.log(obj.x);
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

// ---- Phase 3G: RegExp tests ----

///|
test "regex literal test method" {
  let src =
    #|var re = /hello/;
    #|console.log(re.test("hello world"));
    #|console.log(re.test("goodbye"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "regex literal with flags" {
  let src =
    #|var re = /hello/i;
    #|console.log(re.test("Hello World"));
    #|console.log(re.flags);
    #|console.log(re.ignoreCase);
  let output = run_output(src)
  json_inspect(output, content=["true", "i", "true"])
}

///|
test "regex exec method" {
  let src =
    #|var re = /(\d+)/;
    #|var result = re.exec("abc 123 def");
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  json_inspect(output, content=["123", "123"])
}

///|
test "regex exec returns null on no match" {
  let src =
    #|var re = /xyz/;
    #|var result = re.exec("hello world");
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["null"])
}

///|
test "regex source and flags properties" {
  let src =
    #|var re = /abc/gi;
    #|console.log(re.source);
    #|console.log(re.flags);
    #|console.log(re.global);
    #|console.log(re.ignoreCase);
  let output = run_output(src)
  json_inspect(output, content=["abc", "gi", "true", "true"])
}

///|
test "RegExp.prototype accessors use internal slots and generic flags Get" {
  let src =
    #|var flagsGet = Object.getOwnPropertyDescriptor(RegExp.prototype, "flags").get;
    #|var flagLog = "";
    #|var generic = {
    #|  get hasIndices() { flagLog += "d"; return 0; },
    #|  get global() { flagLog += "g"; return "yes"; },
    #|  get ignoreCase() { flagLog += "i"; return false; },
    #|  get multiline() { flagLog += "m"; return 1; },
    #|  get dotAll() { flagLog += "s"; return null; },
    #|  get unicode() { flagLog += "u"; return {}; },
    #|  get unicodeSets() { flagLog += "v"; return 0; },
    #|  get sticky() { flagLog += "y"; return true; }
    #|};
    #|console.log(flagsGet.call(generic));
    #|console.log(flagLog);
    #|var globalGet = Object.getOwnPropertyDescriptor(RegExp.prototype, "global").get;
    #|try { globalGet.call({}); } catch (e) { console.log(e.name); }
    #|var re = /abc/g;
    #|re.global = false;
    #|console.log(re.hasOwnProperty("global"));
    #|console.log(re.global);
    #|var first = /first/g;
    #|var second = /second/i;
    #|Object.assign(first, second);
    #|console.log(first.source);
    #|console.log(first.flags);
  let output = run_output(src)
  json_inspect(output, content=[
    "gmuy", "dgimsuvy", "TypeError", "false", "true", "first", "g",
  ])
}

///|
test "RegExp.prototype source and toString follow accessor algorithms" {
  let src =
    #|console.log(new RegExp("").source);
    #|console.log(new RegExp("/").source);
    #|var toString = RegExp.prototype.toString;
    #|try { toString(); } catch (e) { console.log(e.name); }
    #|console.log(toString.call({ source: { toString: function() { return "x"; } }, flags: "g" }));
    #|var re = /a/;
    #|re.compile("b", "i");
    #|console.log(re.source);
    #|console.log(re.flags);
    #|console.log(re.test("B"));
  let output = run_output(src)
  json_inspect(output, content=[
    "(?:)", "\\/", "TypeError", "/x/g", "b", "i", "true",
  ])
}

///|
test "RegExp duplicate named backrefs use the matched alternative" {
  let src =
    #|var re = /(?:(?<a>x)|(?<a>y))\k<a>/;
    #|console.log(re.exec("xx")[0]);
    #|console.log(re.exec("yy")[0]);
    #|console.log(re.exec("xy"));
    #|console.log(re.exec("yx"));
    #|var backtrack = /(?:(?<a>x+)y|(?<a>x))\k<a>/;
    #|console.log(backtrack.exec("xx")[0]);
    #|var quantified = /^(?:(?<a>x)|(?<a>y))*\k<a>$/;
    #|console.log(quantified.exec("xyy")[0]);
    #|console.log(quantified.exec("xyx"));
    #|var reverse = /^(?:(?<a>y)|(?<a>x))*\k<a>$/;
    #|console.log(reverse.exec("yxx")[0]);
    #|console.log(reverse.exec("yxy"));
  let output = run_output(src)
  json_inspect(output, content=[
    "xx", "yy", "null", "null", "xx", "xyy", "null", "yxx", "null",
  ])
}

///|
test "RegExp duplicate named replacements use the matched capture" {
  let src =
    #|console.log("y".replace(/(?<a>x)|(?<a>y)/, "$<a>"));
    #|console.log("xy".replace(/(?<a>x)|(?<a>y)/g, "$<a>"));
    #|console.log("xyy".replace(/^(?:(?<a>x)|(?<a>y))*\k<a>$/, "$<a>"));
  let output = run_output(src)
  json_inspect(output, content=["y", "xy", "y"])
}

///|
test "RegExp duplicate named groups backtrack into later alternatives" {
  let src =
    #|var matcher = /(?:(?<x>a)|(?<y>a)(?<x>b))(?:(?<z>c)|(?<z>d))/;
    #|var three = matcher.exec("abc");
    #|console.log(three[0]);
    #|console.log(three.groups.x);
    #|console.log(three.groups.y);
    #|console.log(three.groups.z);
    #|console.log(Object.keys(three.groups).join(","));
    #|var two = matcher.exec("ad");
    #|console.log(two[0]);
    #|console.log(two.groups.x);
    #|console.log(two.groups.y === undefined);
    #|console.log(two.groups.z);
    #|console.log(Object.keys(two.groups).join(","));
    #|var iterated = /(?:(?:(?<x>a)|(?<x>b)|c)\k<x>){2}/.exec("aac");
    #|console.log(iterated[0]);
    #|console.log(iterated.groups.x === undefined);
    #|console.log(Object.keys(iterated.groups).join(","));
  let output = run_output(src)
  json_inspect(output, content=[
    "abc", "b", "a", "c", "x,y,z", "ad", "a", "true", "d", "x,y,z", "aac", "true",
    "x",
  ])
}

///|
test "RegExp positive lookahead does not backtrack into assertion" {
  let src =
    #|console.log(/^(?=(a|aa))\1b/.exec("aab"));
    #|var m = /(?=(a|aa))\1b/.exec("aab");
    #|console.log(m.index);
    #|console.log(m[0]);
    #|console.log(m[1]);
    #|var spec = /(?=(a+))a*b\1/.exec("baaabac");
    #|console.log(spec.index);
    #|console.log(spec[0]);
    #|console.log(spec[1]);
  let output = run_output(src)
  json_inspect(output, content=["null", "1", "ab", "a", "3", "aba", "a"])
}

///|
test "RegExp compile uses internal slots across prototype mutation and subclasses" {
  let src =
    #|var r = /a/;
    #|Object.setPrototypeOf(r, null);
    #|RegExp.prototype.compile.call(r, "b");
    #|console.log(RegExp.prototype.test.call(r, "b"));
    #|console.log(RegExp.prototype.test.call(r, "a"));
    #|Object.setPrototypeOf(r, RegExp.prototype);
    #|console.log(r.source);
    #|var fake = {};
    #|Object.setPrototypeOf(fake, RegExp.prototype);
    #|try { RegExp.prototype.compile.call(fake, "x"); } catch (e) { console.log(e instanceof TypeError); }
    #|var C = class extends RegExp {};
    #|var s = new C("a");
    #|console.log(s.compile("c") === s);
    #|console.log(s.test("c"));
    #|console.log(s.test("a"));
    #|console.log(RegExp.prototype.compile.call(s, "d") === s);
    #|console.log(s.source);
    #|console.log(s.test("d"));
  let output = run_output(src)
  json_inspect(output, content=[
    "true", "false", "b", "true", "true", "true", "false", "true", "d", "true",
  ])
}

///|
test "regex character class" {
  let src =
    #|var re = /[a-z]+/;
    #|console.log(re.test("hello"));
    #|console.log(re.test("12345"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "regex dot and quantifiers" {
  let src =
    #|var re = /a.+b/;
    #|console.log(re.test("aXYZb"));
    #|console.log(re.test("ab"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "regex anchors" {
  let src =
    #|var re1 = /^hello/;
    #|console.log(re1.test("hello world"));
    #|console.log(re1.test("say hello"));
    #|var re2 = /world$/;
    #|console.log(re2.test("hello world"));
    #|console.log(re2.test("world hello"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "true", "false"])
}

///|
test "regex alternation" {
  let src =
    #|var re = /cat|dog/;
    #|console.log(re.test("I have a cat"));
    #|console.log(re.test("I have a dog"));
    #|console.log(re.test("I have a bird"));
  let output = run_output(src)
  json_inspect(output, content=["true", "true", "false"])
}

///|
test "regex digit and word shortcuts" {
  let src =
    #|var re1 = /\d+/;
    #|console.log(re1.test("abc123"));
    #|console.log(re1.test("abcdef"));
    #|var re2 = /\w+/;
    #|console.log(re2.test("hello"));
    #|console.log(re2.test("   "));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "true", "false"])
}

///|
test "string match with regex" {
  let src =
    #|var result = "hello 123 world 456".match(/\d+/g);
    #|console.log(result.length);
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  json_inspect(output, content=["2", "123", "456"])
}

///|
test "string match non-global" {
  let src =
    #|var result = "abc 123 def".match(/(\d+)/);
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  json_inspect(output, content=["123", "123"])
}

///|
test "RegExp Symbol.match fallback accepts empty pattern with non-callable exec" {
  let src =
    #|var r = new RegExp("");
    #|r.exec = undefined;
    #|var direct = r[Symbol.match]("abc");
    #|console.log(direct[0]);
    #|console.log(direct.index);
    #|var viaString = "abc".match(r);
    #|console.log(viaString[0]);
    #|console.log(viaString.index);
    #|var borrowed = String.prototype.match.call("abc", r);
    #|console.log(borrowed[0]);
    #|console.log(borrowed.index);
  let output = run_output(src)
  json_inspect(output, content=["", "0", "", "0", "", "0"])
}

///|
test "RegExp Symbol.match clamps sticky lastIndex before fallback exec" {
  let src =
    #|var r = /a/y;
    #|r.exec = undefined;
    #|r.lastIndex = -1;
    #|var match = r[Symbol.match]("a");
    #|console.log(match[0]);
    #|console.log(r.lastIndex);
  let output = run_output(src)
  json_inspect(output, content=["a", "1"])
}

///|
test "string match returns null" {
  let src =
    #|var result = "hello".match(/\d+/);
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["null"])
}

///|
test "string search with regex" {
  let src =
    #|console.log("hello 123 world".search(/\d+/));
    #|console.log("hello world".search(/\d+/));
  let output = run_output(src)
  json_inspect(output, content=["6", "-1"])
}

///|
test "string replace with regex" {
  let src =
    #|var result = "hello world".replace(/world/, "there");
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["hello there"])
}

///|
test "string replace with regex global" {
  let src =
    #|var result = "aaa bbb aaa".replace(/aaa/g, "ccc");
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["ccc bbb ccc"])
}

///|
test "string replace with capture group" {
  let src =
    #|var result = "John Smith".replace(/(\w+) (\w+)/, "$2 $1");
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["Smith John"])
}

///|
test "new RegExp constructor" {
  let src =
    #|var re = new RegExp("hello", "i");
    #|console.log(re.test("Hello"));
    #|console.log(re.source);
    #|console.log(re.flags);
  let output = run_output(src)
  json_inspect(output, content=["true", "hello", "i"])
}

///|
test "regex quantifier exact" {
  let src =
    #|var re = /a{3}/;
    #|console.log(re.test("aaa"));
    #|console.log(re.test("aa"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "regex optional quantifier" {
  let src =
    #|var re = /colou?r/;
    #|console.log(re.test("color"));
    #|console.log(re.test("colour"));
  let output = run_output(src)
  json_inspect(output, content=["true", "true"])
}

///|
test "regex with escaped special chars" {
  let src =
    #|var re = /\./;
    #|console.log(re.test("hello.world"));
    #|console.log(re.test("helloworld"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

// ---- Critical bug fix regression tests ----

///|
test "bugfix: defineProperty defaults to false" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 42 });
    #|var desc = Object.getOwnPropertyDescriptor(obj, "x");
    #|console.log(desc.writable);
    #|console.log(desc.enumerable);
    #|console.log(desc.configurable);
  let output = run_output(src)
  json_inspect(output, content=["false", "false", "false"])
}

///|
test "bugfix: defineProperty preserves existing descriptor" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 1, writable: true, enumerable: true, configurable: true });
    #|Object.defineProperty(obj, "x", { value: 2 });
    #|var desc = Object.getOwnPropertyDescriptor(obj, "x");
    #|console.log(desc.value);
    #|console.log(desc.writable);
    #|console.log(desc.enumerable);
  let output = run_output(src)
  json_inspect(output, content=["2", "true", "true"])
}

///|
test "bugfix: case-insensitive regex preserves captures" {
  let src =
    #|var result = "Hello World".match(/^(H)/i);
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  json_inspect(output, content=["H", "H"])
}

///|
test "bugfix: case-insensitive regex \\D not broken" {
  let src =
    #|var re = /\D+/i;
    #|console.log(re.test("abc"));
    #|console.log(re.test("123"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "bugfix: case-insensitive regex \\W not broken" {
  let src =
    #|var re = /\W/i;
    #|console.log(re.test(" "));
    #|console.log(re.test("a"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false"])
}

///|
test "bugfix: UserFuncExt strict mode" {
  let src =
    #|function f(a = 1) {
    #|  "use strict";
    #|  try { arguments.callee; console.log("no error"); }
    #|  catch(e) { console.log(e instanceof TypeError); }
    #|}
    #|f();
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "bugfix: UserFuncExt sloppy callee is ThrowTypeError accessor" {
  // §10.4.4.6: non-simple params → unmapped arguments; callee is a poison-pill accessor
  let src =
    #|function f(a = 1) {
    #|  try { arguments.callee; console.log("no-throw"); }
    #|  catch(e) { console.log(e instanceof TypeError); }
    #|}
    #|f();
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "bugfix: arrow function hoisting" {
  let src =
    #|var f = () => {
    #|  var x = 10;
    #|  function inner() { return x; }
    #|  return inner();
    #|};
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["10"])
}

///|
test "bugfix: destructure assign without let" {
  let src =
    #|var a = 1;
    #|var b = 2;
    #|[a, b] = [b, a];
    #|console.log(a);
    #|console.log(b);
  let output = run_output(src)
  json_inspect(output, content=["2", "1"])
}

///|
test "bugfix: array destructure assign from function" {
  let src =
    #|var a = 0;
    #|var b = 0;
    #|function swap() { return [3, 4]; }
    #|[a, b] = swap();
    #|console.log(a);
    #|console.log(b);
  let output = run_output(src)
  json_inspect(output, content=["3", "4"])
}

///|
test "bugfix: regex after if condition rparen" {
  let src =
    #|var x = "hello world";
    #|var result = "";
    #|if (/hello/.test(x)) {
    #|  result = "matched";
    #|}
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["matched"])
}

///|
test "bugfix: regex after while condition rparen" {
  let src =
    #|var s = "abc";
    #|var found = false;
    #|var i = 0;
    #|while (i < 1) {
    #|  if (/abc/.test(s)) found = true;
    #|  i++;
    #|}
    #|console.log(found);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "bugfix: division after function call rparen" {
  let src =
    #|function getNum() { return 10; }
    #|var result = getNum() / 2;
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["5"])
}

///|
test "bugfix: regex after for condition rparen" {
  let src =
    #|var count = 0;
    #|var items = ["abc", "def", "abx"];
    #|for (var i = 0; i < items.length; i++) {
    #|  if (/ab/.test(items[i])) count++;
    #|}
    #|console.log(count);
  let output = run_output(src)
  json_inspect(output, content=["2"])
}

///|
test "bugfix: strict mode restored after throwing strict function" {
  let src =
    #|function strictBoom() {
    #|  "use strict";
    #|  throw new Error("boom");
    #|}
    #|function sloppy() { return typeof arguments.callee; }
    #|try {
    #|  strictBoom();
    #|} catch (e) {}
    #|console.log(sloppy());
  let output = run_output(src)
  json_inspect(output, content=["function"])
}

///|
test "bugfix: constructor honors function strict mode" {
  // In strict mode, arguments.callee has %ThrowTypeError% getter per ES spec
  let src =
    #|function C() {
    #|  "use strict";
    #|  try {
    #|    arguments.callee;
    #|    console.log("no error");
    #|  } catch (e) {
    #|    console.log(e instanceof TypeError);
    #|  }
    #|}
    #|new C();
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "bugfix: var destructure declaration is hoisted" {
  let src =
    #|console.log(a);
    #|var [a] = [1];
    #|console.log(a);
  let output = run_output(src)
  json_inspect(output, content=["undefined", "1"])
}

///|
test "bugfix: for-of var binds in outer scope" {
  let src =
    #|for (var x of [1, 2]) {}
    #|console.log(x);
  let output = run_output(src)
  json_inspect(output, content=["2"])
}

///|
test "bugfix: for-of var closures share one binding" {
  let src =
    #|var fns = [];
    #|for (var x of [1, 2, 3]) {
    #|  fns.push(function() { return x; });
    #|}
    #|console.log(fns[0]());
    #|console.log(fns[2]());
  let output = run_output(src)
  json_inspect(output, content=["3", "3"])
}

///|
test "bugfix: regex literal after control-flow rparen" {
  let src =
    #|var out = 0;
    #|if (true) /ab/.test("zabz") ? out = 1 : out = 2;
    #|console.log(out);
  let output = run_output(src)
  json_inspect(output, content=["1"])
}

///|
test "bugfix: negative toFixed keeps sign and digits" {
  let src =
    #|console.log((-1.23).toFixed(2));
    #|console.log((-0.004).toFixed(2));
  let output = run_output(src)
  json_inspect(output, content=["-1.23", "-0.00"])
}

///|
test "bugfix: JSON.stringify propagates nested circular errors" {
  let src =
    #|var a = {};
    #|var b = {};
    #|a.child = b;
    #|b.parent = a;
    #|try {
    #|  JSON.stringify({ root: a });
    #|  console.log("no error");
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Converting circular structure to JSON",
  ])
}

///|
test "bugfix: JSON.parse rejects raw control chars in strings" {
  let src =
    #|try {
    #|  JSON.parse(`{"x":"a
    #|b"}`);
    #|  console.log("no error");
    #|} catch (e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected control character in JSON",
  ])
}

///|
test "test262 harness pattern - constructor with prototype method" {
  let src =
    #|function Test262Error(message) {
    #|  this.message = message || "";
    #|}
    #|Test262Error.prototype.toString = function() {
    #|  return "Test262Error: " + this.message;
    #|};
    #|var e = new Test262Error("test message");
    #|console.log(e.message);
    #|console.log(e.toString());
  let output = run_output(src)
  json_inspect(output, content=["test message", "Test262Error: test message"])
}

///|
test "test262 harness pattern - assert._isSameValue" {
  let src =
    #|function assert() {}
    #|assert._isSameValue = function(a, b) {
    #|  if (a === b) {
    #|    return a !== 0 || 1 / a === 1 / b;
    #|  }
    #|  return a !== a && b !== b;
    #|};
    #|console.log(assert._isSameValue("function", "function"));
    #|console.log(assert._isSameValue(0, -0));
    #|console.log(assert._isSameValue(NaN, NaN));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "true"])
}

///|
test "test262 harness pattern - typeof Array.isArray" {
  let src =
    #|var f = Array.isArray;
    #|console.log(typeof f);
  let output = run_output(src)
  json_inspect(output, content=["function"])
}

///|
test "test262 harness pattern - full assert.sameValue flow" {
  // This simulates the complete test262 harness and a simple test
  let src =
    #|// sta.js harness
    #|function Test262Error(message) {
    #|  this.message = message || "";
    #|}
    #|Test262Error.prototype.toString = function() {
    #|  return "Test262Error: " + this.message;
    #|};
    #|
    #|// assert.js harness (simplified)
    #|function assert(mustBeTrue, message) {
    #|  if (mustBeTrue === true) {
    #|    return;
    #|  }
    #|  throw new Test262Error(message);
    #|}
    #|assert._isSameValue = function(a, b) {
    #|  if (a === b) {
    #|    return a !== 0 || 1 / a === 1 / b;
    #|  }
    #|  return a !== a && b !== b;
    #|};
    #|assert.sameValue = function(actual, expected, message) {
    #|  if (assert._isSameValue(actual, expected)) {
    #|    return;
    #|  }
    #|  throw new Test262Error(message);
    #|};
    #|
    #|// The actual test (15.4.3.2-0-1.js)
    #|var f = Array.isArray;
    #|assert.sameValue(typeof f, "function", "Array.isArray must be a function");
    #|console.log("TEST PASSED");
  let output = run_output(src)
  json_inspect(output, content=["TEST PASSED"])
}

///|
test "comma-separated var declarations" {
  let src =
    #|var a, b, c;
    #|a = 1;
    #|b = 2;
    #|c = 3;
    #|console.log(a + b + c);
  let output = run_output(src)
  json_inspect(output, content=["6"])
}

///|
test "comma-separated var declarations with initializers" {
  let src =
    #|var x = 10, y = 20, z = 30;
    #|console.log(x + y + z);
  let output = run_output(src)
  json_inspect(output, content=["60"])
}

///|
test "comma-separated let declarations" {
  let src =
    #|let a = 1, b = 2;
    #|console.log(a * b);
  let output = run_output(src)
  json_inspect(output, content=["2"])
}

///|
test "comma-separated const declarations" {
  let src =
    #|const PI = 3.14, E = 2.71;
    #|console.log(PI + E);
  let output = run_output(src)
  json_inspect(output, content=["5.85"])
}

// Symbol.hasInstance tests

///|
test "instanceof with custom Symbol.hasInstance - returns true" {
  let src =
    #|const MyClass = {
    #|  [Symbol.hasInstance](instance) {
    #|    return instance.isMyClass === true;
    #|  }
    #|};
    #|const obj = { isMyClass: true };
    #|obj instanceof MyClass;
  let (_, result) = run_js(src)
  expect_result(result, "true")
}

///|
test "instanceof with custom Symbol.hasInstance - returns false" {
  let src =
    #|const MyClass = {
    #|  [Symbol.hasInstance](instance) {
    #|    return instance.isMyClass === true;
    #|  }
    #|};
    #|const obj = { isMyClass: false };
    #|obj instanceof MyClass;
  let (_, result) = run_js(src)
  expect_result(result, "false")
}

///|
test "instanceof Symbol.hasInstance with null check" {
  let src =
    #|const MyClass = {
    #|  [Symbol.hasInstance](instance) {
    #|    return instance !== null && instance !== undefined;
    #|  }
    #|};
    #|null instanceof MyClass;
  let (_, result) = run_js(src)
  expect_result(result, "false")
}

///|
test "instanceof Symbol.hasInstance converts result to boolean" {
  let src =
    #|const MyClass = {
    #|  [Symbol.hasInstance](instance) {
    #|    return "truthy string";
    #|  }
    #|};
    #|({}) instanceof MyClass;
  let (_, result) = run_js(src)
  expect_result(result, "true")
}

///|
test "instanceof Symbol.hasInstance returns falsy value" {
  let src =
    #|const MyClass = {
    #|  [Symbol.hasInstance](instance) {
    #|    return 0;
    #|  }
    #|};
    #|({}) instanceof MyClass;
  let (_, result) = run_js(src)
  expect_result(result, "false")
}

///|
test "instanceof Symbol.hasInstance on class static method" {
  let src =
    #|class MyArray {
    #|  static [Symbol.hasInstance](instance) {
    #|    return Array.isArray(instance);
    #|  }
    #|}
    #|[1, 2, 3] instanceof MyArray;
  let (_, result) = run_js(src)
  expect_result(result, "true")
}

///|
test "instanceof falls back to prototype chain when no Symbol.hasInstance" {
  let src =
    #|class Animal {}
    #|class Dog extends Animal {}
    #|const dog = new Dog();
    #|dog instanceof Animal;
  let (_, result) = run_js(src)
  expect_result(result, "true")
}

///|
test "instanceof Array works for array values" {
  let (_, result) = run_js("[1, 2, 3] instanceof Array")
  expect_result(result, "true")
}

///|
test "instanceof Object works for array values" {
  let (_, result) = run_js("[1, 2, 3] instanceof Object")
  expect_result(result, "true")
}

///|
test "instanceof Symbol.hasInstance receives correct argument" {
  let src =
    #|let receivedArg = null;
    #|const Checker = {
    #|  [Symbol.hasInstance](arg) {
    #|    receivedArg = arg;
    #|    return true;
    #|  }
    #|};
    #|const testObj = { x: 42 };
    #|testObj instanceof Checker;
    #|receivedArg.x;
  let (_, result) = run_js(src)
  expect_result(result, "42")
}

///|
test "instanceof throws TypeError for non-callable RHS without Symbol.hasInstance" {
  let src =
    #|try {
    #|  ({}) instanceof {};
    #|  "no error";
    #|} catch (e) {
    #|  (e instanceof TypeError) ? "caught" : String(e);
    #|}
  let (_, result) = run_js(src)
  expect_result(result, "caught")
}

///|
test "instanceof with Symbol.hasInstance inherited from prototype" {
  let src =
    #|const proto = {
    #|  [Symbol.hasInstance](instance) {
    #|    return instance.special === true;
    #|  }
    #|};
    #|const Constructor = Object.create(proto);
    #|({ special: true }) instanceof Constructor;
  let (_, result) = run_js(src)
  expect_result(result, "true")
}

///|
test "instanceof with bound function returns false (no own prototype)" {
  let src =
    #|function Foo() {}
    #|const boundFoo = Foo.bind(null);
    #|// Bound functions don't have own prototype, should return false per spec
    #|({}) instanceof boundFoo;
  let (_, result) = run_js(src)
  expect_result(result, "false")
}

// =============================================================================
// Phase 5: Object spread in object literals
// =============================================================================

///|
test "object spread basic" {
  let output = run_output(
    (
      #|const a = { x: 1, y: 2 };
      #|const b = { ...a, z: 3 };
      #|console.log(b.x);
      #|console.log(b.y);
      #|console.log(b.z);
    ),
  )
  json_inspect(output, content=["1", "2", "3"])
}

///|
test "object spread overrides earlier properties" {
  let output = run_output(
    (
      #|const a = { x: 1, y: 2 };
      #|const b = { x: 10, ...a };
      #|console.log(b.x);
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "object spread later properties override spread" {
  let output = run_output(
    (
      #|const a = { x: 1, y: 2 };
      #|const b = { ...a, x: 10 };
      #|console.log(b.x);
    ),
  )
  json_inspect(output, content=["10"])
}

///|
test "object spread null and undefined are skipped" {
  let output = run_output(
    (
      #|const a = { ...null, ...undefined, x: 1 };
      #|console.log(a.x);
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "object spread from array" {
  let output = run_output(
    (
      #|const a = { ...[10, 20, 30] };
      #|console.log(a["0"]);
      #|console.log(a["1"]);
      #|console.log(a["2"]);
    ),
  )
  json_inspect(output, content=["10", "20", "30"])
}

///|
test "object spread multiple sources" {
  let output = run_output(
    (
      #|const a = { x: 1 };
      #|const b = { y: 2 };
      #|const c = { ...a, ...b, z: 3 };
      #|console.log(c.x);
      #|console.log(c.y);
      #|console.log(c.z);
    ),
  )
  json_inspect(output, content=["1", "2", "3"])
}

///|
test "object spread string" {
  let output = run_output(
    (
      #|const a = { ..."hi" };
      #|console.log(a["0"]);
      #|console.log(a["1"]);
    ),
  )
  json_inspect(output, content=["h", "i"])
}

///|
test "object rest in destructuring" {
  let output = run_output(
    (
      #|const { x, ...rest } = { x: 1, y: 2, z: 3 };
      #|console.log(x);
      #|console.log(rest.y);
      #|console.log(rest.z);
    ),
  )
  json_inspect(output, content=["1", "2", "3"])
}

// =============================================================================
// Phase 5: new.target meta-property
// =============================================================================

///|
test "new.target in constructor" {
  let output = run_output(
    (
      #|function Foo() {
      #|  console.log(new.target === Foo);
      #|}
      #|new Foo();
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "new.target undefined in regular call" {
  let output = run_output(
    (
      #|function Foo() {
      #|  console.log(new.target === undefined);
      #|}
      #|Foo();
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "new.target in arrow function inherits from enclosing" {
  let output = run_output(
    (
      #|function Foo() {
      #|  const check = () => new.target;
      #|  console.log(check() === Foo);
      #|}
      #|new Foo();
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "new.target in class constructor" {
  let output = run_output(
    (
      #|class MyClass {
      #|  constructor() {
      #|    console.log(new.target === MyClass);
      #|  }
      #|}
      #|new MyClass();
    ),
  )
  json_inspect(output, content=["true"])
}

// ==================== Property Descriptor Tests (Phase 7A) ====================

///|
test "object literal getter" {
  let output = run_output(
    (
      #|const obj = { get x() { return 42; } };
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "object literal setter" {
  let output = run_output(
    (
      #|const obj = {
      #|  _val: 0,
      #|  get val() { return this._val; },
      #|  set val(v) { this._val = v * 2; }
      #|};
      #|obj.val = 5;
      #|console.log(obj.val);
    ),
  )
  json_inspect(output, content=["10"])
}

///|
test "defineProperty accessor descriptor" {
  let output = run_output(
    (
      #|const obj = {};
      #|let stored = 0;
      #|Object.defineProperty(obj, 'x', {
      #|  get: function() { return stored; },
      #|  set: function(v) { stored = v + 1; },
      #|  enumerable: true,
      #|  configurable: true
      #|});
      #|obj.x = 10;
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["11"])
}

///|
test "defineProperty accessor vs data validation" {
  let output = run_output(
    (
      #|try {
      #|  Object.defineProperty({}, 'x', {
      #|    get: function() { return 1; },
      #|    value: 42
      #|  });
      #|  console.log('no error');
      #|} catch(e) {
      #|  console.log('TypeError caught');
      #|}
    ),
  )
  json_inspect(output, content=["TypeError caught"])
}

///|
test "getOwnPropertyDescriptor accessor" {
  let output = run_output(
    (
      #|const obj = { get x() { return 1; } };
      #|const desc = Object.getOwnPropertyDescriptor(obj, 'x');
      #|console.log(typeof desc.get);
      #|console.log(desc.enumerable);
      #|console.log(desc.configurable);
      #|console.log(desc.value);
      #|console.log(desc.writable);
    ),
  )
  json_inspect(output, content=[
    "function", "true", "true", "undefined", "undefined",
  ])
}

///|
test "class getter and setter" {
  let output = run_output(
    (
      #|class Temp {
      #|  constructor(c) { this._c = c; }
      #|  get fahrenheit() { return this._c * 9/5 + 32; }
      #|  set fahrenheit(f) { this._c = (f - 32) * 5/9; }
      #|}
      #|const t = new Temp(100);
      #|console.log(t.fahrenheit);
      #|t.fahrenheit = 32;
      #|console.log(t._c);
    ),
  )
  json_inspect(output, content=["212", "0"])
}

///|
test "class accessors allow line terminator after get and set" {
  let output = run_output(
    (
      #|class C {
      #|  constructor() { this.seen = 0; }
      #|  get
      #|  x() { return 1; }
      #|  set
      #|  y(v) { this.seen = v; }
      #|}
      #|const c = new C();
      #|c.y = 2;
      #|console.log(c.x, c.seen);
    ),
  )
  json_inspect(output, content=["1 2"])
}

///|
test "class field initializer yield is rejected inside generator" {
  let result = run_throws(
    (
      #|function* g() {
      #|  class C { static x = yield 1; }
      #|}
    ),
  )
  inspect(
    result,
    content="SyntaxError: Unexpected yield in primary expression at line 2, col 24",
  )
}

///|
test "class constructor has arguments object through super call" {
  let output = run_output(
    (
      #|class Base {
      #|  constructor(a, b) {
      #|    console.log(arguments.length);
      #|    console.log(arguments[0] + arguments[1]);
      #|  }
      #|}
      #|class Derived extends Base {
      #|  constructor() {
      #|    super(3, 4);
      #|  }
      #|}
      #|new Derived();
    ),
  )
  json_inspect(output, content=["2", "7"])
}

///|
test "derived super double init throws ReferenceError" {
  let output = run_output(
    (
      #|try {
      #|  class B {}
      #|  class D extends B { constructor() { super(); super(); } }
      #|  new D();
      #|  console.log("no error");
      #|} catch (e) {
      #|  console.log(e.name);
      #|}
    ),
  )
  json_inspect(output, content=["ReferenceError"])
}

///|
test "derived super property before super throws ReferenceError" {
  let output = run_output(
    (
      #|try {
      #|  class B { get value() { return 1; } }
      #|  class D extends B { constructor() { return super.value; } }
      #|  new D();
      #|  console.log("no error");
      #|} catch (e) {
      #|  console.log(e.name);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=[
    "ReferenceError", "Must call super constructor in derived class before accessing 'this' or returning from derived constructor",
  ])
}

///|
test "derived super double init throws when super returns object" {
  let output = run_output(
    (
      #|try {
      #|  class B { constructor() { return { tag: "override" }; } }
      #|  class D extends B { constructor() { super(); super(); } }
      #|  new D();
      #|  console.log("no error");
      #|} catch (e) {
      #|  console.log(e.name);
      #|}
    ),
  )
  json_inspect(output, content=["ReferenceError"])
}

///|
test "derived super double init does not rerun field initializers" {
  let output = run_output(
    (
      #|let count = 0;
      #|class B {}
      #|class D extends B {
      #|  x = (count = count + 1);
      #|  constructor() {
      #|    super();
      #|    try { super(); } catch (e) { console.log(e.name); }
      #|  }
      #|}
      #|new D();
      #|console.log(count);
    ),
  )
  json_inspect(output, content=["ReferenceError", "1"])
}

///|
test "derived super double init guard preserves nested derived super chains" {
  let output = run_output(
    (
      #|class A { constructor() { this.a = 1; } }
      #|class B extends A { constructor() { super(); this.b = 2; } }
      #|class D extends B { constructor() { super(); this.d = 3; } }
      #|let d = new D();
      #|console.log(d.a + d.b + d.d);
    ),
  )
  json_inspect(output, content=["6"])
}

///|
test "derived super double init throws in intermediate constructor" {
  let output = run_output(
    (
      #|try {
      #|  class A {}
      #|  class B extends A { constructor() { super(); super(); } }
      #|  class D extends B { constructor() { super(); } }
      #|  new D();
      #|  console.log("no error");
      #|} catch (e) {
      #|  console.log(e.name);
      #|}
    ),
  )
  json_inspect(output, content=["ReferenceError"])
}

///|
test "defineProperty getter only (no setter)" {
  let output = run_output(
    (
      #|const obj = {};
      #|Object.defineProperty(obj, 'x', {
      #|  get: function() { return 42; }
      #|});
      #|console.log(obj.x);
      #|obj.x = 100;
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["42", "42"])
}

///|
test "accessor property enumerable in Object.keys" {
  let output = run_output(
    (
      #|const obj = {};
      #|Object.defineProperty(obj, 'a', { get: function() { return 1; }, enumerable: true });
      #|Object.defineProperty(obj, 'b', { get: function() { return 2; }, enumerable: false });
      #|obj.c = 3;
      #|console.log(Object.keys(obj).join(','));
    ),
  )
  json_inspect(output, content=["a,c"])
}

///|
test "Object.create with accessor descriptor" {
  let output = run_output(
    (
      #|let stored = 0;
      #|const obj = Object.create(null, {
      #|  x: {
      #|    get: function() { return stored; },
      #|    set: function(v) { stored = v; },
      #|    enumerable: true,
      #|    configurable: true
      #|  }
      #|});
      #|obj.x = 42;
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "Object.create applies enumerable Properties through descriptor pipeline" {
  let output = run_output(
    (
      #|const props = {};
      #|Object.defineProperty(props, 'hidden', {
      #|  value: { value: 'hidden', enumerable: true },
      #|  enumerable: false
      #|});
      #|const proto = {};
      #|Object.defineProperty(proto, 'value', {
      #|  get: function() { return 'inherited'; }
      #|});
      #|const desc = Object.create(proto);
      #|Object.defineProperty(desc, 'value', {
      #|  get: function() { return 'own'; }
      #|});
      #|desc.enumerable = true;
      #|props.visible = desc;
      #|const obj = Object.create({}, props);
      #|console.log(obj.hasOwnProperty('hidden'));
      #|console.log(obj.visible);
      #|console.log(Object.keys(obj).join(','));
    ),
  )
  json_inspect(output, content=["false", "own", "visible"])
}

///|
test "Object.create reads descriptor attributes from array objects" {
  let output = run_output(
    (
      #|const desc = [1, 2, 3];
      #|desc.get = function() { return 'from-array'; };
      #|desc.enumerable = true;
      #|const obj = Object.create({}, { prop: desc });
      #|console.log(obj.hasOwnProperty('prop'));
      #|console.log(obj.prop);
      #|console.log(Object.keys(obj).join(','));
    ),
  )
  json_inspect(output, content=["true", "from-array", "prop"])
}

///|
test "Object.create accepts array and primitive Properties inputs" {
  let output = run_output(
    (
      #|let getterThisIsArray = false;
      #|const props = [];
      #|Object.defineProperty(props, 'prop', {
      #|  get: function() {
      #|    getterThisIsArray = this instanceof Array;
      #|    return { value: 'array-props', enumerable: true };
      #|  },
      #|  enumerable: true
      #|});
      #|const obj = Object.create({}, props);
      #|console.log(getterThisIsArray);
      #|console.log(obj.prop);
      #|console.log(Object.getOwnPropertyNames(Object.create({}, true)).length);
      #|try {
      #|  Object.create({}, 'hello');
      #|  console.log('no error');
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true", "array-props", "0", "true"])
}

///|
test "defineProperties with accessor" {
  let output = run_output(
    (
      #|const obj = {};
      #|Object.defineProperties(obj, {
      #|  x: { get: function() { return 10; }, enumerable: true },
      #|  y: { value: 20, writable: true, enumerable: true }
      #|});
      #|console.log(obj.x);
      #|console.log(obj.y);
    ),
  )
  json_inspect(output, content=["10", "20"])
}

///|
test "getter this binding" {
  let output = run_output(
    (
      #|const obj = {
      #|  name: 'hello',
      #|  get upper() { return this.name.toUpperCase(); }
      #|};
      #|console.log(obj.upper);
    ),
  )
  json_inspect(output, content=["HELLO"])
}

///|
test "getOwnPropertyDescriptors with accessor" {
  let output = run_output(
    (
      #|const obj = { get x() { return 1; }, y: 2 };
      #|const descs = Object.getOwnPropertyDescriptors(obj);
      #|console.log(typeof descs.x.get);
      #|console.log(descs.x.value);
      #|console.log(descs.y.value);
      #|console.log(descs.y.writable);
    ),
  )
  json_inspect(output, content=["function", "undefined", "2", "true"])
}

///|
test "getOwnPropertyDescriptors uses own-key and descriptor dispatch" {
  let output = run_output(
    (
      #|let log = "";
      #|const target = { a: 1, b: 2 };
      #|Object.defineProperty(target, "c", { value: 3 });
      #|const proxy = new Proxy(target, {
      #|  ownKeys: function(t) {
      #|    log += "|ownKeys";
      #|    return ["a", "b", "c"];
      #|  },
      #|  getOwnPropertyDescriptor: function(t, k) {
      #|    log += "|getOwnPropertyDescriptor:" + k;
      #|    return Object.getOwnPropertyDescriptor(t, k);
      #|  }
      #|});
      #|const proxyDescs = Object.getOwnPropertyDescriptors(proxy);
      #|const stringDescs = Object.getOwnPropertyDescriptors("abc");
      #|console.log(log);
      #|console.log(proxyDescs.a.value + "/" + proxyDescs.c.enumerable);
      #|console.log(Object.keys(stringDescs).join(","));
      #|console.log(stringDescs[0].value + "/" + stringDescs.length.writable + "/" + stringDescs.length.enumerable + "/" + stringDescs.length.configurable);
    ),
  )
  json_inspect(output, content=[
    "|ownKeys|getOwnPropertyDescriptor:a|getOwnPropertyDescriptor:b|getOwnPropertyDescriptor:c",
    "1/false", "0,1,2,length", "a/false/false/false",
  ])
}

///|
test "descriptor builtins preserve user bracket keys and snapshot keys" {
  let output = run_output(
    (
      #|const descSource = {};
      #|descSource["[[x]]"] = { value: 7, enumerable: true };
      #|const target = {};
      #|Object.defineProperties(target, descSource);
      #|console.log(target["[[x]]"]);
      #|const descs = Object.getOwnPropertyDescriptors(target);
      #|console.log(descs["[[x]]"].value + "/" + descs["[[x]]"].enumerable);
      #|
      #|const arrayProps = [];
      #|Object.defineProperty(arrayProps, "0", {
      #|  enumerable: true,
      #|  get: function() {
      #|    arrayProps[1] = { value: "late", enumerable: true };
      #|    return { value: "first", enumerable: true };
      #|  }
      #|});
      #|const snapTarget = {};
      #|Object.defineProperties(snapTarget, arrayProps);
      #|console.log(snapTarget[0]);
      #|console.log(snapTarget.hasOwnProperty("1"));
      #|
      #|const mapProps = new Map();
      #|Object.defineProperty(mapProps, "x", {
      #|  value: { value: "map", enumerable: true },
      #|  enumerable: true
      #|});
      #|const mapTarget = {};
      #|Object.defineProperties(mapTarget, mapProps);
      #|console.log(mapTarget.x);
      #|
      #|const setProps = new Set();
      #|Object.defineProperty(setProps, "y", {
      #|  value: { value: "set", enumerable: true },
      #|  enumerable: true
      #|});
      #|const setTarget = {};
      #|Object.defineProperties(setTarget, setProps);
      #|console.log(setTarget.y);
    ),
  )
  json_inspect(output, content=["7", "7/true", "first", "false", "map", "set"])
}

///|
test "built-in function prototype and length descriptor metadata" {
  let output = run_output(
    (
      #|const functionProto = Object.getOwnPropertyDescriptor(Function, "prototype");
      #|const generatedLength = Object.getOwnPropertyDescriptor(Function("return 42;"), "length");
      #|const regexpProto = Object.getOwnPropertyDescriptor(RegExp, "prototype");
      #|console.log(functionProto.writable + "/" + functionProto.enumerable + "/" + functionProto.configurable);
      #|console.log(generatedLength.writable + "/" + generatedLength.enumerable + "/" + generatedLength.configurable);
      #|console.log(regexpProto.writable + "/" + regexpProto.enumerable + "/" + regexpProto.configurable);
    ),
  )
  json_inspect(output, content=[
    "false/false/false", "false/false/true", "false/false/false",
  ])
}

///|
test "inherited getter on prototype chain" {
  let output = run_output(
    (
      #|const proto = {};
      #|Object.defineProperty(proto, 'x', {
      #|  get: function() { return this._x * 2; }
      #|});
      #|const obj = Object.create(proto);
      #|obj._x = 5;
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["10"])
}

///|
test "defineProperty rejects non-callable getter" {
  let output = run_output(
    (
      #|try {
      #|  Object.defineProperty({}, 'x', { get: 42 });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "defineProperty rejects non-callable setter" {
  let output = run_output(
    (
      #|try {
      #|  Object.defineProperty({}, 'x', { set: "not a function" });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "non-configurable accessor cannot be redefined" {
  let output = run_output(
    (
      #|const obj = {};
      #|Object.defineProperty(obj, 'x', {
      #|  get: function() { return 1; },
      #|  configurable: false
      #|});
      #|try {
      #|  Object.defineProperty(obj, 'x', {
      #|    get: function() { return 2; }
      #|  });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "spread invokes getters and creates data properties" {
  let output = run_output(
    (
      #|const source = {};
      #|Object.defineProperty(source, 'x', {
      #|  get: function() { return 42; },
      #|  enumerable: true
      #|});
      #|const copy = { ...source };
      #|console.log(copy.x);
      #|const desc = Object.getOwnPropertyDescriptor(copy, 'x');
      #|console.log(desc.value);
      #|console.log(typeof desc.get);
    ),
  )
  json_inspect(output, content=["42", "42", "undefined"])
}

///|
test "computed assignment walks prototype chain for setters" {
  let output = run_output(
    (
      #|let stored = 0;
      #|const proto = {};
      #|Object.defineProperty(proto, 'x', {
      #|  set: function(v) { stored = v; },
      #|  get: function() { return stored; }
      #|});
      #|const obj = Object.create(proto);
      #|const key = 'x';
      #|obj[key] = 99;
      #|console.log(stored);
      #|console.log(obj[key]);
    ),
  )
  json_inspect(output, content=["99", "99"])
}

///|
test "own data property shadows inherited accessor" {
  let output = run_output(
    (
      #|let reads = 0;
      #|let stored = 0;
      #|const proto = {};
      #|Object.defineProperty(proto, 'x', {
      #|  get: function() { reads = reads + 1; return 7; },
      #|  set: function(v) { stored = v; }
      #|});
      #|const obj = { x: 1 };
      #|Object.setPrototypeOf(obj, proto);
      #|console.log(obj.x);
      #|obj.x = 99;
      #|console.log(obj.x);
      #|console.log(reads);
      #|console.log(stored);
    ),
  )
  json_inspect(output, content=["1", "99", "0", "0"])
}

///|
test "update expression invokes setter" {
  let output = run_output(
    (
      #|let stored = 5;
      #|const obj = {};
      #|Object.defineProperty(obj, 'x', {
      #|  get: function() { return stored; },
      #|  set: function(v) { stored = v; }
      #|});
      #|obj.x++;
      #|console.log(stored);
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["6", "6"])
}

///|
test "compound assignment invokes setter" {
  let output = run_output(
    (
      #|let stored = 10;
      #|const obj = {};
      #|Object.defineProperty(obj, 'x', {
      #|  get: function() { return stored; },
      #|  set: function(v) { stored = v; }
      #|});
      #|obj.x += 5;
      #|console.log(stored);
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["15", "15"])
}

///|
test "defineProperties validates accessor vs data mixing" {
  let output = run_output(
    (
      #|try {
      #|  Object.defineProperties({}, {
      #|    x: { get: function() {}, value: 1 }
      #|  });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "defineProperties validates getter is callable" {
  let output = run_output(
    (
      #|try {
      #|  Object.defineProperties({}, {
      #|    x: { get: 123 }
      #|  });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "Object.create rejects non-callable getter" {
  let output = run_output(
    (
      #|try {
      #|  Object.create({}, { x: { get: 42 } });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "Object.create rejects non-callable setter" {
  let output = run_output(
    (
      #|try {
      #|  Object.create({}, { x: { set: "bad" } });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "Object.create rejects accessor-data mixing" {
  let output = run_output(
    (
      #|try {
      #|  Object.create({}, { x: { get: function(){}, value: 1 } });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "getOwnPropertyDescriptors includes symbol-keyed properties" {
  let output = run_output(
    (
      #|const sym = Symbol('test');
      #|const obj = {};
      #|obj[sym] = 42;
      #|const descs = Object.getOwnPropertyDescriptors(obj);
      #|const symDesc = descs[sym];
      #|console.log(symDesc.value);
      #|console.log(symDesc.writable);
      #|console.log(symDesc.enumerable);
    ),
  )
  json_inspect(output, content=["42", "true", "true"])
}

///|
test "inherited non-writable data property blocks assignment" {
  let output = run_output(
    (
      #|const proto = {};
      #|Object.defineProperty(proto, 'x', { value: 1, writable: false });
      #|const obj = Object.create(proto);
      #|obj.x = 99;
      #|console.log(obj.x);
    ),
  )
  json_inspect(output, content=["1"])
}

// ================================================================
// Generator Tests
// ================================================================

///|
test "generator: function* returns object with next method" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|console.log(typeof it);
      #|console.log(typeof it.next);
    ),
  )
  json_inspect(output, content=["object", "function"])
}

///|
test "generator: basic yield and done" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield 1;
      #|  yield 2;
      #|  yield 3;
      #|}
      #|const it = g();
      #|const a = it.next();
      #|console.log(a.value, a.done);
      #|const b = it.next();
      #|console.log(b.value, b.done);
      #|const c = it.next();
      #|console.log(c.value, c.done);
      #|const d = it.next();
      #|console.log(d.value, d.done);
    ),
  )
  json_inspect(output, content=[
    "1 false", "2 false", "3 false", "undefined true",
  ])
}

///|
test "generator: return in generator body" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield 1;
      #|  return 42;
      #|}
      #|const it = g();
      #|let r = it.next();
      #|console.log(r.value, r.done);
      #|r = it.next();
      #|console.log(r.value, r.done);
      #|r = it.next();
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["1 false", "42 true", "undefined true"])
}

///|
test "generator: first next() arg is ignored" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield 1;
      #|}
      #|const it = g();
      #|const r = it.next(999);
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["1 false"])
}

///|
test "generator: completed generator returns done" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|it.next();
      #|it.next();
      #|const r = it.next();
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["undefined true"])
}

///|
test "generator: Symbol.iterator returns self" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|console.log(it[Symbol.iterator]() === it);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "generator: Symbol.toStringTag tags generator objects" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|console.log(Object.prototype.toString.call(it));
      #|console.log(Object.prototype.toString.call(GeneratorFunction.prototype));
    ),
  )
  json_inspect(output, content=[
    "[object Generator]", "[object GeneratorFunction]",
  ])
}

///|
test "generator: new with generator throws TypeError" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|try {
      #|  new g();
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "generator: two next() results are different objects" {
  let output = run_output(
    (
      #|function* g() { yield 1; yield 2; }
      #|const it = g();
      #|const a = it.next();
      #|const b = it.next();
      #|console.log(a !== b);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "generator: .throw(e) on SuspendedStart completes and throws" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|try {
      #|  it.throw(new Error("boom"));
      #|} catch(e) {
      #|  console.log(e.message);
      #|}
      #|const r = it.next();
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["boom", "undefined true"])
}

///|
test "generator: .return(v) on SuspendedStart returns done" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|const r = it.return(42);
      #|console.log(r.value, r.done);
      #|const r2 = it.next();
      #|console.log(r2.value, r2.done);
    ),
  )
  json_inspect(output, content=["42 true", "undefined true"])
}

///|
test "generator: .throw(e) on Completed throws" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|it.next();
      #|it.next();
      #|try {
      #|  it.throw(new Error("done-throw"));
      #|} catch(e) {
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=["done-throw"])
}

///|
test "generator: .return(v) on Completed returns done" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|it.next();
      #|it.next();
      #|const r = it.return(99);
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["99 true"])
}

///|
test "generator: generator expression" {
  let output = run_output(
    (
      #|const g = function*() { yield 10; yield 20; };
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
    ),
  )
  json_inspect(output, content=["10", "20"])
}

///|
test "generator: generator with parameters" {
  let output = run_output(
    (
      #|function* add(a, b) {
      #|  yield a;
      #|  yield b;
      #|  yield a + b;
      #|}
      #|const it = add(3, 7);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["3", "7", "10", "true"])
}

///|
test "generator: yield inside for loop (range)" {
  let output = run_output(
    (
      #|function* range(start, end) {
      #|  for (let i = start; i < end; i++) {
      #|    yield i;
      #|  }
      #|}
      #|const it = range(1, 4);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "2", "3", "true"])
}

///|
test "generator: for-of consumes generator" {
  let output = run_output(
    (
      #|function* g() { yield 1; yield 2; yield 3; }
      #|let results = [];
      #|for (const x of g()) {
      #|  results.push(x);
      #|}
      #|console.log(results.join(','));
    ),
  )
  json_inspect(output, content=["1,2,3"])
}

///|
test "generator: spread operator with generator" {
  let output = run_output(
    (
      #|function* g() { yield 1; yield 2; yield 3; }
      #|const arr = [...g()];
      #|console.log(arr.join(','));
    ),
  )
  json_inspect(output, content=["1,2,3"])
}

///|
test "generator: destructuring assignment from generator" {
  let output = run_output(
    (
      #|function* g() { yield 10; yield 20; yield 30; }
      #|const [a, b] = g();
      #|console.log(a, b);
    ),
  )
  json_inspect(output, content=["10 20"])
}

///|
test "generator: .return() on yielded generator" {
  let output = run_output(
    (
      #|function* g() { yield 1; yield 2; yield 3; }
      #|const it = g();
      #|console.log(it.next().value);
      #|const r = it.return(42);
      #|console.log(r.value, r.done);
      #|console.log(it.next().value, it.next().done);
    ),
  )
  json_inspect(output, content=["1", "42 true", "undefined true"])
}

///|
test "generator: yield as expression receives next value" {
  let output = run_output(
    (
      #|function* g() {
      #|  const x = yield 1;
      #|  yield x + 10;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next(5).value);
    ),
  )
  json_inspect(output, content=["1", "15"])
}

///|
test "sloppy yield identifier before slash remains division" {
  let output = run_output(
    (
      #|var yield = 8, x = 2, g = 4;
      #|console.log(yield / x / g);
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "generator: yield regexp literal after yield keyword" {
  let output = run_output(
    (
      #|function* g() { yield /x/g; }
      #|const it = g();
      #|const r = it.next();
      #|console.log(r.value instanceof RegExp, r.value.source, r.value.flags);
    ),
  )
  json_inspect(output, content=["true x g"])
}

///|
test "generator: nested yield in loop keeps replay indexes stable" {
  let output = run_output(
    (
      #|function* g() {
      #|  for (let i = 0; i < 1; i++) {
      #|    return yield (yield 1);
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next(2).value);
      #|const r = it.next(3);
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["1", "2", "3 true"])
}

///|
test "generator: abrupt resumes in loop target suspended yield" {
  let output = run_output(
    (
      #|function* g() { while (true) { yield 1; } }
      #|const thrown = g();
      #|console.log(thrown.next().value);
      #|try { thrown.throw(new Error("boom")); } catch (e) { console.log(e.message); }
      #|console.log(thrown.next().done);
      #|const returned = g();
      #|console.log(returned.next().value);
      #|let r = returned.return(9);
      #|console.log(r.value, r.done);
      #|console.log(returned.next().done);
    ),
  )
  json_inspect(output, content=["1", "boom", "true", "1", "9 true", "true"])
}

///|
test "generator: computed class name resume does not replay prefix effects" {
  let output = run_output(
    (
      #|function* g() {
      #|  let n = 0;
      #|  class C { [(++n, yield 1)]() {} }
      #|  console.log(n);
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next(2).done);
    ),
  )
  json_inspect(output, content=["1", "1", "true"])
}

///|
test "generator: yield in conditional" {
  let output = run_output(
    (
      #|function* g() {
      #|  if (true) {
      #|    yield 1;
      #|  } else {
      #|    yield 2;
      #|  }
      #|  yield 3;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "3", "true"])
}

///|
test "generator: multiple independent generators" {
  let output = run_output(
    (
      #|function* g() { yield 1; yield 2; }
      #|const a = g();
      #|const b = g();
      #|console.log(a.next().value);
      #|console.log(b.next().value);
      #|console.log(a.next().value);
      #|console.log(b.next().value);
    ),
  )
  json_inspect(output, content=["1", "1", "2", "2"])
}

///|
test "generator: generator with default params" {
  let output = run_output(
    (
      #|function* g(x = 10) {
      #|  yield x;
      #|  yield x + 1;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|const it2 = g(5);
      #|console.log(it2.next().value);
    ),
  )
  json_inspect(output, content=["10", "11", "5"])
}

///|
test "generator: generator instance supports property assignment" {
  let output = run_output(
    (
      #|function* g() { yield 1; }
      #|const it = g();
      #|it.x = 42;
      #|console.log(it.x);
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "generator: yield without argument yields undefined" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield;
      #|  yield;
      #|}
      #|const it = g();
      #|const a = it.next();
      #|console.log(a.value, a.done);
      #|const b = it.next();
      #|console.log(b.value, b.done);
    ),
  )
  json_inspect(output, content=["undefined false", "undefined false"])
}

// ================================================================
// Generator Phase 4: Exception handling in generators
// ================================================================

///|
test "generator: .throw() caught by try/catch in generator" {
  let output = run_output(
    (
      #|function* g() {
      #|  try {
      #|    yield 1;
      #|    yield 2;
      #|  } catch(e) {
      #|    yield "caught: " + e.message;
      #|  }
      #|  yield 3;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.throw(new Error("boom")).value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "caught: boom", "3", "true"])
}

///|
test "generator: uncaught .throw() completes generator and rethrows" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield 1;
      #|  yield 2;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|try {
      #|  it.throw(new Error("fail"));
      #|} catch(e) {
      #|  console.log(e.message);
      #|}
      #|const r = it.next();
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["1", "fail", "undefined true"])
}

///|
test "generator: .throw() caught continues and yields more" {
  let output = run_output(
    (
      #|function* g() {
      #|  let result;
      #|  try {
      #|    result = yield 1;
      #|  } catch(e) {
      #|    result = "error: " + e.message;
      #|  }
      #|  yield result;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.throw(new Error("oops")).value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "error: oops", "true"])
}

///|
test "generator: .return() on suspended generator completes it" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield 1;
      #|  yield 2;
      #|  yield 3;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|const r = it.return(42);
      #|console.log(r.value, r.done);
      #|const r2 = it.next();
      #|console.log(r2.value, r2.done);
    ),
  )
  json_inspect(output, content=["1", "42 true", "undefined true"])
}

///|
test "generator: .return() inside try executes finally" {
  let output = run_output(
    (
      #|function* g() {
      #|  try {
      #|    yield 1;
      #|    yield 2;
      #|  } finally {
      #|    console.log("finally ran");
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|const r = it.return(42);
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["1", "finally ran", "42 true"])
}

///|
test "generator: .return() when finally yields" {
  let output = run_output(
    (
      #|function* g() {
      #|  try {
      #|    yield 1;
      #|  } finally {
      #|    yield "from-finally";
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|const r = it.return(42);
      #|console.log(r.value, r.done);
      #|const r2 = it.next();
      #|console.log(r2.value, r2.done);
    ),
  )
  json_inspect(output, content=["1", "from-finally false", "42 true"])
}

///|
test "generator: .throw() in try/catch/finally runs finally" {
  let output = run_output(
    (
      #|function* g() {
      #|  try {
      #|    yield 1;
      #|  } catch(e) {
      #|    yield "caught: " + e.message;
      #|  } finally {
      #|    console.log("finally");
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.throw(new Error("err")).value);
      #|it.next();
    ),
  )
  json_inspect(output, content=["1", "caught: err", "finally"])
}

///|
test "generator: multiple .throw() with try/catch" {
  let output = run_output(
    (
      #|function* g() {
      #|  while (true) {
      #|    try {
      #|      yield "waiting";
      #|    } catch(e) {
      #|      console.log("got: " + e.message);
      #|    }
      #|  }
      #|}
      #|const it = g();
      #|it.next();
      #|it.throw(new Error("a"));
      #|it.throw(new Error("b"));
    ),
  )
  json_inspect(output, content=["got: a", "got: b"])
}

// ================================================================
// Generator Phase 5: Control-flow integration (loops)
// ================================================================

///|
test "generator: yield inside while loop" {
  let output = run_output(
    (
      #|function* g() {
      #|  let i = 0;
      #|  while (i < 3) {
      #|    yield i;
      #|    i++;
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["0", "1", "2", "true"])
}

///|
test "generator: yield inside for loop with return" {
  let output = run_output(
    (
      #|function* g() {
      #|  for (let i = 0; i < 10; i++) {
      #|    if (i === 3) return "done";
      #|    yield i;
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|const r = it.next();
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["0", "1", "2", "done true"])
}

///|
test "generator: yield in for loop preserves loop variable" {
  let output = run_output(
    (
      #|function* fib(n) {
      #|  let a = 0, b = 1;
      #|  for (let i = 0; i < n; i++) {
      #|    yield a;
      #|    const temp = a;
      #|    a = b;
      #|    b = temp + b;
      #|  }
      #|}
      #|const it = fib(6);
      #|const results = [];
      #|let r = it.next();
      #|while (!r.done) {
      #|  results.push(r.value);
      #|  r = it.next();
      #|}
      #|console.log(results.join(","));
    ),
  )
  json_inspect(output, content=["0,1,1,2,3,5"])
}

///|
test "generator: yield in nested loops" {
  let output = run_output(
    (
      #|function* g() {
      #|  for (let i = 0; i < 2; i++) {
      #|    for (let j = 0; j < 2; j++) {
      #|      yield i * 10 + j;
      #|    }
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["0", "1", "10", "11", "true"])
}

///|
test "generator: break inside generator loop" {
  let output = run_output(
    (
      #|function* g() {
      #|  for (let i = 0; i < 10; i++) {
      #|    yield i;
      #|    if (i >= 2) break;
      #|  }
      #|  yield "after loop";
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["0", "1", "2", "after loop", "true"])
}

///|
test "generator: yield inside for-of in generator" {
  let output = run_output(
    (
      #|function* flatten(arrays) {
      #|  for (const arr of arrays) {
      #|    yield arr;
      #|  }
      #|}
      #|const it = flatten([10, 20, 30]);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["10", "20", "30", "true"])
}

///|
test "generator: for-of consuming generator inside generator" {
  let output = run_output(
    (
      #|function* source() { yield 1; yield 2; yield 3; }
      #|function* doubled() {
      #|  for (const x of source()) {
      #|    yield x * 2;
      #|  }
      #|}
      #|const it = doubled();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["2", "4", "6", "true"])
}

///|
test "PR 213 review: comma replay sees yield in destructuring pattern" {
  let output = run_output(
    (
      #|function* g() {
      #|  let x;
      #|  ({ [yield "key"]: x } = { p: 7 }), yield x;
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next("p").value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["key", "7", "true"])
}

///|
test "PR 213 review: generator for-of destructuring body resumes same iterator" {
  let output = run_output(
    (
      #|function* g() {
      #|  for (const [x] of [[1], [2]]) {
      #|    yield x;
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "2", "true"])
}

///|
test "PR 213 review: generator for-of member assignment body resumes same iterator" {
  let output = run_output(
    (
      #|function* g() {
      #|  const o = {};
      #|  for (o.x of [1, 2]) {
      #|    yield o.x;
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "2", "true"])
}

///|
test "PR 213 review: generator for-of pattern yield resumes binding" {
  let output = run_output(
    (
      #|function* g() {
      #|  let x;
      #|  for ({ [yield "key"]: x } of [{ p: 9 }]) {
      #|    yield x;
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next("p").value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["key", "9", "true"])
}

///|
test "PR 213 review: generator for-of assignment yield resumes assignment" {
  let output = run_output(
    (
      #|function* g() {
      #|  const o = {};
      #|  for (o[yield "key"] of [11]) {
      #|    yield o.p;
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next("p").value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["key", "11", "true"])
}

///|
test "PR 214 review: nested generator for-of resumes inner iterator" {
  let output = run_output(
    (
      #|function* g() {
      #|  for (const x of [1, 2]) {
      #|    for (const y of [10, 20]) {
      #|      yield x + ":" + y;
      #|    }
      #|  }
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1:10", "1:20", "2:10", "2:20", "true"])
}

// ================================================================
// Generator Phase 6: yield* delegation
// ================================================================

///|
test "generator: yield* basic delegation" {
  let output = run_output(
    (
      #|function* inner() {
      #|  yield 1;
      #|  yield 2;
      #|}
      #|function* outer() {
      #|  yield 0;
      #|  yield* inner();
      #|  yield 3;
      #|}
      #|const it = outer();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["0", "1", "2", "3", "true"])
}

///|
test "generator: yield* with return value" {
  let output = run_output(
    (
      #|function* inner() {
      #|  yield 1;
      #|  return "done";
      #|}
      #|function* outer() {
      #|  const result = yield* inner();
      #|  yield result;
      #|}
      #|const it = outer();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "done", "true"])
}

///|
test "generator: yield* over array" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield* [10, 20, 30];
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["10", "20", "30", "true"])
}

///|
test "generator: yield* over string" {
  let output = run_output(
    (
      #|function* g() {
      #|  yield* "abc";
      #|}
      #|const it = g();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["a", "b", "c", "true"])
}

///|
test "generator: yield* nested delegation" {
  let output = run_output(
    (
      #|function* a() { yield 1; yield 2; }
      #|function* b() { yield* a(); yield 3; }
      #|function* c() { yield* b(); yield 4; }
      #|const it = c();
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "2", "3", "4", "true"])
}

///|
test "generator: yield* forwards .return() to delegate" {
  let output = run_output(
    (
      #|function* inner() {
      #|  try {
      #|    yield 1;
      #|    yield 2;
      #|  } finally {
      #|    console.log("inner finally");
      #|  }
      #|}
      #|function* outer() {
      #|  yield* inner();
      #|  yield 3;
      #|}
      #|const it = outer();
      #|console.log(it.next().value);
      #|const r = it.return(42);
      #|console.log(r.value, r.done);
    ),
  )
  json_inspect(output, content=["1", "inner finally", "42 true"])
}

///|
test "generator: yield* forwards .throw() to delegate" {
  let output = run_output(
    (
      #|function* inner() {
      #|  try {
      #|    yield 1;
      #|  } catch(e) {
      #|    yield "caught: " + e.message;
      #|  }
      #|}
      #|function* outer() {
      #|  yield* inner();
      #|  yield "after";
      #|}
      #|const it = outer();
      #|console.log(it.next().value);
      #|console.log(it.throw(new Error("err")).value);
      #|console.log(it.next().value);
      #|console.log(it.next().done);
    ),
  )
  json_inspect(output, content=["1", "caught: err", "after", "true"])
}

// ================================================================
// Generator Phase 7: Language integration
// ================================================================

///|
test "generator: for-of consuming generator (integration)" {
  let output = run_output(
    (
      #|function* range(n) {
      #|  for (let i = 0; i < n; i++) yield i;
      #|}
      #|const results = [];
      #|for (const x of range(5)) {
      #|  results.push(x);
      #|}
      #|console.log(results.join(","));
    ),
  )
  json_inspect(output, content=["0,1,2,3,4"])
}

///|
test "generator: spread with generator (integration)" {
  let output = run_output(
    (
      #|function* g() { yield 1; yield 2; yield 3; }
      #|const arr = [...g()];
      #|console.log(arr.length);
      #|console.log(arr.join(","));
    ),
  )
  json_inspect(output, content=["3", "1,2,3"])
}

///|
test "generator: destructuring with generator (integration)" {
  let output = run_output(
    (
      #|function* g() { yield "a"; yield "b"; yield "c"; }
      #|const [first, second] = g();
      #|console.log(first, second);
    ),
  )
  json_inspect(output, content=["a b"])
}

///|
test "generator: generator as method" {
  let output = run_output(
    (
      #|const obj = {
      #|  items: function*() {
      #|    yield 1;
      #|    yield 2;
      #|    yield 3;
      #|  }
      #|};
      #|const results = [];
      #|for (const x of obj.items()) {
      #|  results.push(x);
      #|}
      #|console.log(results.join(","));
    ),
  )
  json_inspect(output, content=["1,2,3"])
}

///|
test "generator: yield* over spread result" {
  let output = run_output(
    (
      #|function* a() { yield 1; yield 2; }
      #|function* b() { yield 3; yield 4; }
      #|function* combined() {
      #|  yield* a();
      #|  yield* b();
      #|}
      #|console.log([...combined()].join(","));
    ),
  )
  json_inspect(output, content=["1,2,3,4"])
}

///|
test "generator: generator with closures" {
  let output = run_output(
    (
      #|function* counter(start) {
      #|  let count = start;
      #|  while (true) {
      #|    const reset = yield count;
      #|    if (reset) {
      #|      count = start;
      #|    } else {
      #|      count++;
      #|    }
      #|  }
      #|}
      #|const c = counter(1);
      #|console.log(c.next().value);
      #|console.log(c.next().value);
      #|console.log(c.next().value);
      #|console.log(c.next(true).value);
      #|console.log(c.next().value);
    ),
  )
  json_inspect(output, content=["1", "2", "3", "1", "2"])
}

///|
test "generator: infinite fibonacci generator" {
  let output = run_output(
    (
      #|function* fibonacci() {
      #|  let a = 0, b = 1;
      #|  while (true) {
      #|    yield a;
      #|    const temp = a;
      #|    a = b;
      #|    b = temp + b;
      #|  }
      #|}
      #|const fib = fibonacci();
      #|const results = [];
      #|for (let i = 0; i < 8; i++) {
      #|  results.push(fib.next().value);
      #|}
      #|console.log(results.join(","));
    ),
  )
  json_inspect(output, content=["0,1,1,2,3,5,8,13"])
}

///|
test "generator: generator pipeline" {
  let output = run_output(
    (
      #|function* naturals() {
      #|  let i = 1;
      #|  while (true) yield i++;
      #|}
      #|function* take(n, iter) {
      #|  let count = 0;
      #|  for (const v of iter) {
      #|    if (count >= n) return;
      #|    yield v;
      #|    count++;
      #|  }
      #|}
      #|function* map(fn, iter) {
      #|  for (const v of iter) {
      #|    yield fn(v);
      #|  }
      #|}
      #|const squares = map(x => x * x, take(5, naturals()));
      #|console.log([...squares].join(","));
    ),
  )
  json_inspect(output, content=["1,4,9,16,25"])
}

// ================================================================
// Generator Phase 8: Hardening / stress tests
// ================================================================

///|
test "generator: deep iteration stress test" {
  let output = run_output(
    (
      #|function* range(n) {
      #|  for (let i = 0; i < n; i++) yield i;
      #|}
      #|let sum = 0;
      #|for (const x of range(100)) {
      #|  sum += x;
      #|}
      #|console.log(sum);
    ),
  )
  json_inspect(output, content=["4950"])
}

///|
test "generator: yield* chain stress" {
  let output = run_output(
    (
      #|function* single(v) { yield v; }
      #|function* chain(n) {
      #|  for (let i = 0; i < n; i++) {
      #|    yield* single(i);
      #|  }
      #|}
      #|let sum = 0;
      #|for (const x of chain(50)) sum += x;
      #|console.log(sum);
    ),
  )
  json_inspect(output, content=["1225"])
}

///|
test "generator: alternating yield and yield*" {
  let output = run_output(
    (
      #|function* inner() { yield "a"; yield "b"; }
      #|function* outer() {
      #|  yield 1;
      #|  yield* inner();
      #|  yield 2;
      #|  yield* inner();
      #|  yield 3;
      #|}
      #|console.log([...outer()].join(","));
    ),
  )
  json_inspect(output, content=["1,a,b,2,a,b,3"])
}

///|
test "generator: generator state isolation" {
  let output = run_output(
    (
      #|function* counter() {
      #|  let i = 0;
      #|  while (true) yield i++;
      #|}
      #|const a = counter();
      #|const b = counter();
      #|a.next(); a.next(); a.next();
      #|console.log(a.next().value);
      #|console.log(b.next().value);
    ),
  )
  json_inspect(output, content=["3", "0"])
}

///|
test "harness: print function" {
  let output = run_output(
    (
      #|print("hello");
      #|print("a", "b", "c");
      #|print(42);
      #|print(true, null, undefined);
    ),
  )
  json_inspect(output, content=["hello", "a b c", "42", "true null undefined"])
}

///|
test "harness: $262.global is globalThis" {
  let output = run_output(
    (
      #|console.log($262.global === globalThis);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "harness: $262.gc is a no-op" {
  let output = run_output(
    (
      #|var result = $262.gc();
      #|console.log(result === undefined);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "harness: host functions use current realm function prototype" {
  let output = run_output(
    (
      #|var localFunctionProto = Function.prototype;
      #|console.log(Object.getPrototypeOf(print) === localFunctionProto);
      #|console.log(Object.getPrototypeOf($262.gc) === localFunctionProto);
      #|console.log(Object.getPrototypeOf($262.evalScript) === localFunctionProto);
      #|console.log(Object.getPrototypeOf($262.createRealm) === localFunctionProto);
      #|console.log(Object.getPrototypeOf($262.agent.start) === localFunctionProto);
    ),
  )
  json_inspect(output, content=["true", "true", "true", "true", "true"])
}

///|
test "harness: $262.evalScript evaluates code in global scope" {
  let output = run_output(
    (
      #|$262.evalScript("var x = 42;");
      #|console.log(x);
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "harness: $262.evalScript returns result" {
  let output = run_output(
    (
      #|var result = $262.evalScript("1 + 2");
      #|console.log(result);
    ),
  )
  json_inspect(output, content=["3"])
}

///|
test "harness: $262.evalScript propagates errors" {
  let output = run_output(
    (
      #|try {
      #|  $262.evalScript("throw new TypeError('test error');");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=["true", "test error"])
}

///|
test "harness: $262.createRealm returns a new $262 object" {
  let output = run_output(
    (
      #|var newRealm = $262.createRealm();
      #|console.log(typeof newRealm);
      #|console.log(typeof newRealm.global);
      #|console.log(typeof newRealm.evalScript);
      #|console.log(typeof newRealm.gc);
    ),
  )
  json_inspect(output, content=["object", "object", "function", "function"])
}

///|
test "harness: $262.createRealm has isolated global" {
  let output = run_output(
    (
      #|var newRealm = $262.createRealm();
      #|console.log(newRealm.global !== $262.global);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "harness: $262.createRealm evalScript runs in new realm" {
  // evalScript on the returned $262 must execute in the new realm, not the caller's
  let output = run_output(
    (
      #|var x = "outer";
      #|var newRealm = $262.createRealm();
      #|newRealm.evalScript("var x = 'inner';");
      #|console.log(x);
    ),
  )
  json_inspect(output, content=["outer"])
}

///|
test "iterator methods stay in caller realm after createRealm" {
  let output = run_output(
    (
      #|var mapProto = Object.getPrototypeOf(new Map().entries());
      #|var setProto = Object.getPrototypeOf(new Set().values());
      #|var regexpProto = Object.getPrototypeOf(/a/g[Symbol.matchAll]("a"));
      #|$262.createRealm();
      #|console.log(Object.getPrototypeOf(new Map().entries()) === mapProto);
      #|console.log(Object.getPrototypeOf(new Map().keys()) === mapProto);
      #|console.log(Object.getPrototypeOf(new Set().values()) === setProto);
      #|console.log(Object.getPrototypeOf(new Set().entries()) === setProto);
      #|console.log(Object.getPrototypeOf(/a/g[Symbol.matchAll]("a")) === regexpProto);
    ),
  )
  json_inspect(output, content=["true", "true", "true", "true", "true"])
}

///|
test "borrowed iterator methods use method realm after createRealm" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var arrayProto = r.evalScript("Object.getPrototypeOf([].values())");
      #|var mapProto = r.evalScript("Object.getPrototypeOf(new Map().entries())");
      #|var setProto = r.evalScript("Object.getPrototypeOf(new Set().values())");
      #|var typedArrayProto = r.evalScript("Object.getPrototypeOf(new Uint8Array([1]).values())");
      #|var regexpProto = r.evalScript("Object.getPrototypeOf(/a/g[Symbol.matchAll]('a'))");
      #|var foreignArrayKeys = r.evalScript("Array.prototype.keys");
      #|var foreignArrayValues = r.evalScript("Array.prototype.values");
      #|var foreignArrayEntries = r.evalScript("Array.prototype.entries");
      #|var foreignMapKeys = r.evalScript("Map.prototype.keys");
      #|var foreignMapEntries = r.evalScript("Map.prototype.entries");
      #|var foreignSetValues = r.evalScript("Set.prototype.values");
      #|var foreignSetEntries = r.evalScript("Set.prototype.entries");
      #|var foreignTypedValues = r.evalScript("Uint8Array.prototype.values");
      #|var foreignMatchAll = r.evalScript("RegExp.prototype[Symbol.matchAll]");
      #|console.log(Object.getPrototypeOf(foreignArrayKeys.call([])) === arrayProto);
      #|console.log(Object.getPrototypeOf(foreignArrayValues.call([])) === arrayProto);
      #|console.log(Object.getPrototypeOf(foreignArrayEntries.call([])) === arrayProto);
      #|console.log(Object.getPrototypeOf(foreignMapKeys.call(new Map())) === mapProto);
      #|console.log(Object.getPrototypeOf(foreignMapEntries.call(new Map())) === mapProto);
      #|console.log(Object.getPrototypeOf(foreignSetValues.call(new Set())) === setProto);
      #|console.log(Object.getPrototypeOf(foreignSetEntries.call(new Set())) === setProto);
      #|console.log(Object.getPrototypeOf(foreignTypedValues.call(new Uint8Array([1]))) === typedArrayProto);
      #|console.log(Object.getPrototypeOf(foreignMatchAll.call(/a/g, "a")) === regexpProto);
    ),
  )
  json_inspect(output, content=[
    "true", "true", "true", "true", "true", "true", "true", "true", "true",
  ])
}

///|
test "iterator next functions use current realm function prototype" {
  let output = run_output(
    (
      #|var functionProto = Function.prototype;
      #|var mapIter = new Map([[1, 2]]).keys();
      #|var setIter = new Set([1]).values();
      #|var typedValuesIter = new Uint8Array([1]).values();
      #|var typedKeysIter = new Uint8Array([1]).keys();
      #|var typedEntriesIter = new Uint8Array([1]).entries();
      #|var regexpIter = /a/g[Symbol.matchAll]("a");
      #|console.log(Object.getPrototypeOf([].values().next) === functionProto);
      #|console.log(Object.getPrototypeOf([].keys().next) === functionProto);
      #|console.log(Object.getPrototypeOf([].entries().next) === functionProto);
      #|console.log(Object.getPrototypeOf("x"[Symbol.iterator]().next) === functionProto);
      #|console.log(Object.getPrototypeOf(mapIter.next) === functionProto);
      #|console.log(Object.getPrototypeOf(setIter.next) === functionProto);
      #|console.log(Object.getPrototypeOf(typedValuesIter.next) === functionProto);
      #|console.log(Object.getPrototypeOf(typedKeysIter.next) === functionProto);
      #|console.log(Object.getPrototypeOf(typedEntriesIter.next) === functionProto);
      #|console.log(Object.getPrototypeOf(typedValuesIter[Symbol.iterator]) === functionProto);
      #|console.log(Object.getPrototypeOf(regexpIter.next) === functionProto);
      #|console.log(Object.getPrototypeOf(Object.getPrototypeOf(mapIter).next) === functionProto);
      #|console.log(Object.getPrototypeOf(Object.getPrototypeOf(setIter).next) === functionProto);
      #|console.log(Object.getPrototypeOf(Object.getPrototypeOf(regexpIter).next) === functionProto);
    ),
  )
  json_inspect(output, content=[
    "true", "true", "true", "true", "true", "true", "true", "true", "true", "true",
    "true", "true", "true", "true",
  ])
}

///|
test "borrowed iterator next functions use method realm function prototype" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var localFunctionProto = Function.prototype;
      #|var foreignArrayValues = r.evalScript("Array.prototype.values");
      #|var foreignArrayKeys = r.evalScript("Array.prototype.keys");
      #|var foreignArrayEntries = r.evalScript("Array.prototype.entries");
      #|var foreignMapKeys = r.evalScript("Map.prototype.keys");
      #|var foreignSetValues = r.evalScript("Set.prototype.values");
      #|var foreignTypedValues = r.evalScript("Uint8Array.prototype.values");
      #|var foreignTypedKeys = r.evalScript("Uint8Array.prototype.keys");
      #|var foreignTypedEntries = r.evalScript("Uint8Array.prototype.entries");
      #|var foreignMatchAll = r.evalScript("RegExp.prototype[Symbol.matchAll]");
      #|console.log(Object.getPrototypeOf(foreignArrayValues.call([]).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignArrayKeys.call([]).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignArrayEntries.call([]).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignMapKeys.call(new Map()).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignSetValues.call(new Set()).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignTypedValues.call(new Uint8Array([1])).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignTypedKeys.call(new Uint8Array([1])).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignTypedEntries.call(new Uint8Array([1])).next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignTypedValues.call(new Uint8Array([1]))[Symbol.iterator]) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignMatchAll.call(/a/g, "a").next) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignMapKeys.call(new Map()).next) === localFunctionProto);
    ),
  )
  json_inspect(output, content=[
    "true", "true", "true", "true", "true", "true", "true", "true", "true", "true",
    "false",
  ])
}

///|
test "borrowed Promise.all resolve elements use builtin realm function prototype" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var foreignAll = r.evalScript("Promise.all");
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var localFunctionProto = Function.prototype;
      #|var originalThen = Promise.prototype.then;
      #|var captured = null;
      #|Promise.prototype.then = function(onFulfilled, onRejected) {
      #|  captured = onFulfilled;
      #|  return originalThen.call(this, onFulfilled, onRejected);
      #|};
      #|foreignAll.call(Promise, [1]);
      #|Promise.prototype.then = originalThen;
      #|console.log(Object.getPrototypeOf(captured) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(captured) === localFunctionProto);
    ),
  )
  json_inspect(output, content=["true", "false"])
}

///|
test "borrowed Promise.resolve capability executor uses builtin realm function prototype" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var foreignResolve = r.evalScript("Promise.resolve");
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var localFunctionProto = Function.prototype;
      #|var captured = null;
      #|function CustomPromise(executor) {
      #|  captured = executor;
      #|  executor(function() {}, function() {});
      #|}
      #|foreignResolve.call(CustomPromise, 1);
      #|console.log(captured !== null);
      #|console.log(Object.getPrototypeOf(captured) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(captured) === localFunctionProto);
    ),
  )
  json_inspect(output, content=["true", "true", "false"])
}

///|
test "array iterator methods keep method realm when installed in another realm" {
  let output = run_output(
    (
      #|var arrayProto = Object.getPrototypeOf([].values());
      #|var r = $262.createRealm();
      #|r.global.outerArrayKeys = [].keys;
      #|r.global.outerArrayValues = [].values;
      #|r.global.outerArrayEntries = [].entries;
      #|r.global.outerArrayProto = arrayProto;
      #|console.log(r.evalScript("Object.getPrototypeOf(outerArrayKeys.call([])) === outerArrayProto"));
      #|console.log(r.evalScript("Object.getPrototypeOf(outerArrayValues.call([])) === outerArrayProto"));
      #|console.log(r.evalScript("Object.getPrototypeOf(outerArrayEntries.call([])) === outerArrayProto"));
    ),
  )
  json_inspect(output, content=["true", "true", "true"])
}

///|
test "array iterator internal slots are not user properties" {
  let output = run_output(
    (
      #|var it = [1, 2].values();
      #|console.log(Object.getOwnPropertyNames(it).indexOf("[[ArrayIteratorNextIndex]]") === -1);
      #|console.log(Object.getOwnPropertyNames(it).indexOf("[[ArrayIteratorTarget]]") === -1);
      #|it["[[ArrayIteratorNextIndex]]"] = 1;
      #|it["[[ArrayIteratorTarget]]"] = undefined;
      #|console.log(it.next().value);
      #|var it2 = [3].values();
      #|var protoNext = Object.getPrototypeOf(it2).next;
      #|console.log(protoNext.call(it2).value);
      #|var source = [1, 2].values();
      #|source.next();
      #|var target = [9].values();
      #|Object.assign(target, source);
      #|console.log(target.next().value);
    ),
  )
  json_inspect(output, content=["true", "true", "1", "3", "9"])
}

///|
test "borrowed Object.assign wraps primitive targets with method realm prototypes" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var foreignAssign = r.evalScript("Object.assign");
      #|var foreignNumberProto = r.evalScript("Number.prototype");
      #|var foreignBooleanProto = r.evalScript("Boolean.prototype");
      #|var foreignStringProto = r.evalScript("String.prototype");
      #|var foreignSymbolProto = r.evalScript("Symbol.prototype");
      #|console.log(Object.getPrototypeOf(foreignAssign(1, {})) === foreignNumberProto);
      #|console.log(Object.getPrototypeOf(foreignAssign(true, {})) === foreignBooleanProto);
      #|console.log(Object.getPrototypeOf(foreignAssign("x", {})) === foreignStringProto);
      #|console.log(Object.getPrototypeOf(foreignAssign(Symbol("x"), {})) === foreignSymbolProto);
    ),
  )
  json_inspect(output, content=["true", "true", "true", "true"])
}

///|
test "local function creation keeps local prototypes after creating another realm" {
  let output = run_output(
    (
      #|var localObjectProto = Object.prototype;
      #|var localFunctionProto = Function.prototype;
      #|var r = $262.createRealm();
      #|var foreignObjectProto = r.evalScript("Object.prototype");
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var f = function localFunction() {};
      #|var arrow = () => {};
      #|console.log(Object.getPrototypeOf(f) === localFunctionProto);
      #|console.log(Object.getPrototypeOf(f) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(arrow) === localFunctionProto);
      #|console.log(Object.getPrototypeOf(f.prototype) === localObjectProto);
      #|console.log(Object.getPrototypeOf(f.prototype) === foreignObjectProto);
    ),
  )
  json_inspect(output, content=["true", "false", "true", "true", "false"])
}

///|
test "created realm setup does not inherit caller realm function prototype" {
  let output = run_output(
    (
      #|var localFunctionProto = Function.prototype;
      #|var r = $262.createRealm();
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var foreignIsNaN = r.evalScript("isNaN");
      #|var foreignObjectToString = r.evalScript("Object.prototype.toString");
      #|console.log(Object.getPrototypeOf(foreignIsNaN) === localFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignObjectToString) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(foreignObjectToString) === localFunctionProto);
    ),
  )
  json_inspect(output, content=["false", "true", "false"])
}

///|
test "$262 realm handle methods use created realm function prototype" {
  let output = run_output(
    (
      #|var localFunctionProto = Function.prototype;
      #|var r = $262.createRealm();
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|console.log(Object.getPrototypeOf(r.evalScript) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(r.evalScript) === localFunctionProto);
      #|console.log(Object.getPrototypeOf(r.createRealm) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(r.createRealm) === localFunctionProto);
    ),
  )
  json_inspect(output, content=["true", "false", "true", "false"])
}

///|
test "indirect eval keeps current realm function prototypes" {
  let output = run_output(
    (
      #|(0, eval)("var indirectEvalFn = function(){};");
      #|console.log(Object.getPrototypeOf(indirectEvalFn) === Function.prototype);
      #|console.log(Object.getPrototypeOf(indirectEvalFn.prototype) === Object.prototype);
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "borrowed Function.prototype.bind keeps target function prototype realm" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var localBind = Function.prototype.bind;
      #|var localFunctionProto = Function.prototype;
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var foreignFn = r.evalScript("(function target(){})");
      #|var bound = localBind.call(foreignFn, null);
      #|console.log(Object.getPrototypeOf(bound) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(bound) === localFunctionProto);
    ),
  )
  json_inspect(output, content=["true", "false"])
}

///|
test "binding Function.prototype.bind uses function prototype fallback" {
  let output = run_output(
    (
      #|var bound = Function.prototype.bind.call(Function.prototype.bind, null);
      #|console.log(Object.getPrototypeOf(bound) === Function.prototype);
      #|console.log(Object.getPrototypeOf(bound) === null);
    ),
  )
  json_inspect(output, content=["true", "false"])
}

///|
test "borrowed Object.fromEntries allocates result in callee realm" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var foreignFromEntries = r.evalScript("Object.fromEntries");
      #|var foreignObjectProto = r.evalScript("Object.prototype");
      #|var localObjectProto = Object.prototype;
      #|var result = foreignFromEntries([["x", 1]]);
      #|console.log(Object.getPrototypeOf(result) === foreignObjectProto);
      #|console.log(Object.getPrototypeOf(result) === localObjectProto);
    ),
  )
  json_inspect(output, content=["true", "false"])
}

///|
test "foreign function calls create returned functions in callee realm" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var outer = r.evalScript("(function(){ return function inner(){}; })");
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var foreignObjectProto = r.evalScript("Object.prototype");
      #|var localFunctionProto = Function.prototype;
      #|var localObjectProto = Object.prototype;
      #|var f = outer();
      #|console.log(Object.getPrototypeOf(f) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(f) === localFunctionProto);
      #|console.log(Object.getPrototypeOf(f.prototype) === foreignObjectProto);
      #|console.log(Object.getPrototypeOf(f.prototype) === localObjectProto);
    ),
  )
  json_inspect(output, content=["true", "false", "true", "false"])
}

///|
test "derived class constructors keep function realm separate from static inheritance" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var info = r.evalScript("(function(){ class A{}; class B extends A { constructor(){ super(); this.f = function(){}; } } return { A: A, B: B, functionProto: Function.prototype, objectProto: Object.prototype }; })()");
      #|var localFunctionProto = Function.prototype;
      #|var localObjectProto = Object.prototype;
      #|var b = new info.B();
      #|console.log(Object.getPrototypeOf(info.B) === info.A);
      #|console.log(Object.getPrototypeOf(b.f) === info.functionProto);
      #|console.log(Object.getPrototypeOf(b.f) === info.A);
      #|console.log(Object.getPrototypeOf(b.f) === localFunctionProto);
      #|console.log(Object.getPrototypeOf(b.f.prototype) === info.objectProto);
      #|console.log(Object.getPrototypeOf(b.f.prototype) === localObjectProto);
    ),
  )
  json_inspect(output, content=[
    "true", "true", "false", "false", "true", "false",
  ])
}

///|
test "Object.assign does not copy function realm markers" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var foreignFn = r.evalScript("(function foreignFn(){})");
      #|var foreignFunctionProto = r.evalScript("Function.prototype");
      #|var foreignObjectProto = r.evalScript("Object.prototype");
      #|var localFunctionProto = Function.prototype;
      #|var localObjectProto = Object.prototype;
      #|function localOuter() {
      #|  return function nested() {};
      #|}
      #|Object.assign(localOuter, foreignFn);
      #|var nested = localOuter();
      #|console.log(Object.getPrototypeOf(nested) === localFunctionProto);
      #|console.log(Object.getPrototypeOf(nested) === foreignFunctionProto);
      #|console.log(Object.getPrototypeOf(nested.prototype) === localObjectProto);
      #|console.log(Object.getPrototypeOf(nested.prototype) === foreignObjectProto);
    ),
  )
  json_inspect(output, content=["true", "false", "true", "false"])
}

///|
test "borrowed Object.getOwnPropertyDescriptor allocates descriptor in callee realm" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|var foreignGetOwnPropertyDescriptor = r.evalScript("Object.getOwnPropertyDescriptor");
      #|var foreignObjectProto = r.evalScript("Object.prototype");
      #|var localObjectProto = Object.prototype;
      #|var desc = foreignGetOwnPropertyDescriptor({ x: 1 }, "x");
      #|console.log(Object.getPrototypeOf(desc) === foreignObjectProto);
      #|console.log(Object.getPrototypeOf(desc) === localObjectProto);
    ),
  )
  json_inspect(output, content=["true", "false"])
}

///|
test "direct call_value keeps active realm for returned function prototypes" {
  let interp = new_interpreter()
  let prog = @parser.parse("function outer() { return function inner() {}; }")
  let _ = interp.run(prog.stmts)
  let outer = interp.global.get("outer")
  let result = interp.call_value(
    outer,
    Value::Undefined,
    [],
    @token.Loc::default(),
  )
  let function_proto = interp.global.get("[[FunctionPrototype]]")
  let object_proto = interp.global.get("[[ObjectPrototype]]")
  match result {
    Object(data) => {
      guard @runtime.strict_equal(data.prototype, function_proto) else {
        fail("direct call_value function [[Prototype]]")
      }
      match data.bag.properties.get("prototype") {
        Some(Object(proto_data)) =>
          if !@runtime.strict_equal(proto_data.prototype, object_proto) {
            fail("direct call_value function prototype object [[Prototype]]")
          }
        _ => fail("direct call_value function missing prototype object")
      }
    }
    _ => fail("direct call_value did not return function object")
  }
}

///|
test "direct construct_value keeps active realm for constructor-created functions" {
  let interp = new_interpreter()
  let prog = @parser.parse("function C() { this.f = function made() {}; }")
  let _ = interp.run(prog.stmts)
  let ctor = interp.global.get("C")
  let instance = interp.construct_value(ctor, [], @token.Loc::default())
  let made = interp.get_property(instance, "f", @token.Loc::default())
  let function_proto = interp.global.get("[[FunctionPrototype]]")
  let object_proto = interp.global.get("[[ObjectPrototype]]")
  match made {
    Object(data) => {
      guard @runtime.strict_equal(data.prototype, function_proto) else {
        fail("direct construct_value function [[Prototype]]")
      }
      match data.bag.properties.get("prototype") {
        Some(Object(proto_data)) =>
          if !@runtime.strict_equal(proto_data.prototype, object_proto) {
            fail(
              "direct construct_value function prototype object [[Prototype]]",
            )
          }
        _ => fail("direct construct_value function missing prototype object")
      }
    }
    _ => fail("direct construct_value did not create function object")
  }
}

///|
test "host factory helpers bind to target environment realm after setup" {
  let first = new_interpreter()
  let first_function_proto = first.global.get("[[FunctionPrototype]]")
  let first_host = @runtime.make_native_func(name="firstHost", fn(_args) {
    Value::Undefined
  })
  first.global.def_builtin("firstHost", first_host)
  let installed_first_host = first.global.get("firstHost")
  expect_function_object_prototype(
    "first host factory function [[Prototype]]", installed_first_host, first_function_proto,
  )
  let prog = @parser.parse("var r = $262.createRealm();")
  let _ = first.run(prog.stmts)
  let after_create_realm = @runtime.make_native_func(name="afterCreateRealm", fn(
    _args,
  ) {
    Value::Undefined
  })
  first.global.def_builtin("afterCreateRealm", after_create_realm)
  let installed_after_create_realm = first.global.get("afterCreateRealm")
  expect_function_object_prototype(
    "host factory realm after nested createRealm", installed_after_create_realm,
    first_function_proto,
  )
  let second = new_interpreter()
  let second_function_proto = second.global.get("[[FunctionPrototype]]")
  let first_after_second = @runtime.make_native_func(name="firstAfterSecond", fn(
    _args,
  ) {
    Value::Undefined
  })
  first.global.def_builtin("firstAfterSecond", first_after_second)
  let installed_first_after_second = first.global.get("firstAfterSecond")
  expect_function_object_prototype(
    "first host factory after second interpreter [[Prototype]]", installed_first_after_second,
    first_function_proto,
  )
  let second_host = @runtime.make_native_func(name="secondHost", fn(_args) {
    Value::Undefined
  })
  second.global.def_builtin("secondHost", second_host)
  let installed_second_host = second.global.get("secondHost")
  expect_function_object_prototype(
    "second host factory function [[Prototype]]", installed_second_host, second_function_proto,
  )
  match installed_second_host {
    Object(data) =>
      if @runtime.strict_equal(data.prototype, first_function_proto) {
        fail("second host factory should not keep first realm")
      }
    _ => fail("second host factory expected function object")
  }
}

///|
test "direct get_property uses interpreter realm for lazy array methods" {
  let interp = new_interpreter()
  let function_proto = interp.global.get("[[FunctionPrototype]]")
  let array_method = interp.get_property(
    @runtime.make_array([Value::Number(1.0)]),
    "toReversed",
    @token.Loc::default(),
  )
  expect_function_object_prototype(
    "direct get_property lazy array method [[Prototype]]", array_method, function_proto,
  )
}

///|
test "harness: globalThis.$262 is accessible" {
  let output = run_output(
    (
      #|console.log(typeof globalThis.$262);
      #|console.log(globalThis.$262 === $262);
      #|console.log(typeof globalThis.print);
    ),
  )
  json_inspect(output, content=["object", "true", "function"])
}

///|
test "harness: $262.detachArrayBuffer throws TypeError" {
  let output = run_output(
    (
      #|try {
      #|  $262.detachArrayBuffer({});
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=[
    "true", "$262.detachArrayBuffer requires an ArrayBuffer argument",
  ])
}

///|
test "harness: $262.agent.start throws TypeError" {
  let output = run_output(
    (
      #|try {
      #|  $262.agent.start("");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=["true", "$262.agent.start is not supported"])
}

///|
test "harness: $262 object exists and has expected properties" {
  let output = run_output(
    (
      #|console.log(typeof $262);
      #|console.log(typeof $262.global);
      #|console.log(typeof $262.gc);
      #|console.log(typeof $262.createRealm);
      #|console.log(typeof $262.evalScript);
      #|console.log(typeof $262.detachArrayBuffer);
      #|console.log(typeof $262.agent);
    ),
  )
  json_inspect(output, content=[
    "object", "object", "function", "function", "function", "function", "object",
  ])
}

///|
test "harness: Function constructor with body string" {
  let output = run_output(
    (
      #|var add = new Function("a", "b", "return a + b;");
      #|console.log(add(2, 3));
      #|console.log(typeof add);
    ),
  )
  json_inspect(output, content=["5", "function"])
}

///|
test "harness: Function constructor with no args" {
  let output = run_output(
    (
      #|var f = new Function();
      #|console.log(typeof f);
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["function", "undefined"])
}

///|
test "harness: Function constructor body only" {
  let output = run_output(
    (
      #|var f = new Function("return 42;");
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "harness: Function constructor runs in global scope" {
  let output = run_output(
    (
      #|var x = "global";
      #|function makeFunc() {
      #|  var x = "local";
      #|  return new Function("return x;");
      #|}
      #|console.log(makeFunc()());
    ),
  )
  json_inspect(output, content=["global"])
}

///|
test "harness: Function constructor called without new" {
  let output = run_output(
    (
      #|var f = Function("a", "return a * 2;");
      #|console.log(f(5));
    ),
  )
  json_inspect(output, content=["10"])
}

///|
test "harness: fnGlobalObject pattern" {
  // This is the pattern used by test262's fnGlobalObject.js harness
  let output = run_output(
    (
      #|var __globalObject = Function("return this;")();
      #|console.log(typeof __globalObject);
      #|console.log(__globalObject === globalThis);
    ),
  )
  json_inspect(output, content=["object", "true"])
}

///|
test "eval: basic expression evaluation" {
  let output = run_output(
    (
      #|console.log(eval("1 + 2"));
    ),
  )
  json_inspect(output, content=["3"])
}

///|
test "eval: no arguments returns undefined" {
  let output = run_output(
    (
      #|console.log(eval());
    ),
  )
  json_inspect(output, content=["undefined"])
}

///|
test "eval: non-string argument returns as-is" {
  let output = run_output(
    (
      #|console.log(eval(42));
      #|console.log(eval(true));
      #|console.log(eval(null));
    ),
  )
  json_inspect(output, content=["42", "true", "null"])
}

///|
test "eval: typeof eval is function" {
  let output = run_output(
    (
      #|console.log(typeof eval);
    ),
  )
  json_inspect(output, content=["function"])
}

///|
test "eval: direct eval accesses caller scope" {
  let output = run_output(
    (
      #|function f() {
      #|  var x = 42;
      #|  return eval("x");
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: direct eval var leaks to caller scope" {
  let output = run_output(
    (
      #|function f() {
      #|  eval("var x = 42;");
      #|  return x;
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: direct eval var leaks to global scope" {
  let output = run_output(
    (
      #|eval("var x = 99;");
      #|console.log(x);
    ),
  )
  json_inspect(output, content=["99"])
}

///|
test "eval: indirect eval via comma operator" {
  let output = run_output(
    (
      #|var x = "global";
      #|function f() {
      #|  var x = "local";
      #|  return (0, eval)("x");
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["global"])
}

///|
test "eval: indirect eval via variable" {
  let output = run_output(
    (
      #|var x = "global";
      #|var e = eval;
      #|function f() {
      #|  var x = "local";
      #|  return e("x");
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["global"])
}

///|
test "eval: strict mode isolates var declarations" {
  let output = run_output(
    (
      #|"use strict";
      #|eval("var x = 42;");
      #|try { console.log(x); } catch(e) { console.log("not defined"); }
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: function declaration in direct eval" {
  let output = run_output(
    (
      #|function f() {
      #|  eval("function g() { return 42; }");
      #|  return g();
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: syntax error throws SyntaxError" {
  let output = run_output(
    (
      #|try {
      #|  eval("var x = ;");
      #|} catch(e) {
      #|  console.log(e instanceof SyntaxError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "eval: runtime error propagates" {
  let output = run_output(
    (
      #|try {
      #|  eval("throw new TypeError('boom');");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=["true", "boom"])
}

///|
test "eval: globalThis.eval is same as eval" {
  let output = run_output(
    (
      #|console.log(globalThis.eval === eval);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "eval: eval modifies caller scope variables" {
  let output = run_output(
    (
      #|var x = 1;
      #|eval("x = 2");
      #|console.log(x);
    ),
  )
  json_inspect(output, content=["2"])
}

///|
test "eval: eval returns last expression value" {
  let output = run_output(
    (
      #|console.log(eval("1; 2; 3"));
    ),
  )
  json_inspect(output, content=["3"])
}

///|
test "eval: eval with empty string returns undefined" {
  let output = run_output(
    (
      #|console.log(eval(""));
    ),
  )
  json_inspect(output, content=["undefined"])
}

///|
test "eval: direct eval this refers to caller this" {
  let output = run_output(
    (
      #|var obj = {
      #|  x: 42,
      #|  getX: function() { return eval("this.x"); }
      #|};
      #|console.log(obj.getX());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: indirect eval var leaks to global" {
  let output = run_output(
    (
      #|(0, eval)("var indirectVar = 123;");
      #|console.log(indirectVar);
    ),
  )
  json_inspect(output, content=["123"])
}

///|
test "eval: strict eval code with use strict in eval" {
  let output = run_output(
    (
      #|eval("'use strict'; var x = 42;");
      #|try { console.log(x); } catch(e) { console.log("not defined"); }
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: eval in nested function scope" {
  let output = run_output(
    (
      #|function outer() {
      #|  var a = 1;
      #|  function inner() {
      #|    var b = 2;
      #|    return eval("a + b");
      #|  }
      #|  return inner();
      #|}
      #|console.log(outer());
    ),
  )
  json_inspect(output, content=["3"])
}

///|
test "eval: let in non-strict eval is isolated" {
  let output = run_output(
    (
      #|eval("let y = 2;");
      #|try { console.log(y); } catch(e) { console.log("not visible"); }
    ),
  )
  json_inspect(output, content=["not visible"])
}

///|
test "eval: const in non-strict eval is isolated" {
  let output = run_output(
    (
      #|eval("const c = 1;");
      #|try { console.log(c); } catch(e) { console.log("not visible"); }
    ),
  )
  json_inspect(output, content=["not visible"])
}

///|
test "eval: function declaration leaks from non-strict eval" {
  let output = run_output(
    (
      #|eval("function g() { return 99; }");
      #|console.log(g());
    ),
  )
  json_inspect(output, content=["99"])
}

///|
test "eval: strict function eval isolates var" {
  let output = run_output(
    (
      #|function f() {
      #|  "use strict";
      #|  eval("var x = 42;");
      #|  try { return x; } catch(e) { return "isolated"; }
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["isolated"])
}

///|
test "eval: indirect eval does not inherit caller strict mode" {
  // (0, eval)("var x = 1") from strict caller should NOT be strict —
  // indirect eval only respects its own "use strict" directive
  let output = run_output(
    (
      #|"use strict";
      #|(0, eval)("var x = 1;");
      #|console.log(x);
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "eval: eval in block hoists var to function scope" {
  // Direct eval inside a block should hoist var to the enclosing
  // function scope, not the block scope
  let output = run_output(
    (
      #|function f() {
      #|  { eval("var x = 1"); }
      #|  return x;
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "eval: parenthesized eval is direct eval" {
  // (eval)("x") is still a direct eval per ES spec
  let output = run_output(
    (
      #|var x = "global";
      #|function f() {
      #|  var x = "local";
      #|  return (eval)("x");
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["local"])
}

///|
test "eval: nested grouping ((eval)) is direct eval" {
  // ((eval))("x") should also be direct eval — grouping does not
  // change the Reference type regardless of nesting depth
  let output = run_output(
    (
      #|var x = "global";
      #|function f() {
      #|  var x = "local";
      #|  return ((eval))("x");
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["local"])
}

///|
test "eval: new eval() throws TypeError" {
  // eval is not a constructor — new eval() should throw TypeError
  let output = run_output(
    (
      #|try {
      #|  new eval("1 + 2");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=[
    "true", "eval is not a constructor at line 2, col 3",
  ])
}

///|
test "eval: direct eval sees block-scoped let" {
  // Direct eval inside a block should see block-scoped let bindings
  let output = run_output(
    (
      #|function f() {
      #|  let x = 42;
      #|  return eval("x");
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: direct eval sees block-scoped let in nested block" {
  // { let x = 1; eval("x") } must see the block's let binding
  let output = run_output(
    (
      #|var result;
      #|{
      #|  let x = "block_let";
      #|  result = eval("x");
      #|}
      #|console.log(result);
    ),
  )
  json_inspect(output, content=["block_let"])
}

///|
test "eval: strict eval let/const with TDZ" {
  // Strict eval should properly handle let/const with TDZ
  let output = run_output(
    (
      #|function f() {
      #|  "use strict";
      #|  return eval("let x = 10; x + 5;");
      #|}
      #|console.log(f());
    ),
  )
  json_inspect(output, content=["15"])
}

///|
test "eval: var in eval conflicts with block let throws SyntaxError" {
  // Per EvalDeclarationInstantiation step 5.d, eval("var x") must throw
  // SyntaxError when a let/const x exists in an intermediate scope between
  // the eval scope and the variable environment.
  let output = run_output(
    (
      #|function f() {
      #|  var x = "var_x";
      #|  {
      #|    let x = "let_x";
      #|    try {
      #|      eval("var x = 'eval_x'");
      #|      console.log("BUG");
      #|    } catch (e) {
      #|      console.log(e.constructor.name);
      #|    }
      #|    console.log(x);
      #|  }
      #|  console.log(x);
      #|}
      #|f();
    ),
  )
  json_inspect(output, content=["SyntaxError", "let_x", "var_x"])
}

///|
test "eval: nested block var conflict throws SyntaxError" {
  let output = run_output(
    (
      #|function f() {
      #|  {
      #|    let x = "let_x";
      #|    try {
      #|      eval("{ var x = 'eval_x'; }");
      #|      console.log("BUG");
      #|    } catch (e) {
      #|      console.log(e.constructor.name);
      #|    }
      #|    console.log(x);
      #|  }
      #|}
      #|f();
    ),
  )
  json_inspect(output, content=["SyntaxError", "let_x"])
}

///|
test "eval: block function does not trigger var conflict with outer let" {
  let output = run_output(
    (
      #|function f() {
      #|  {
      #|    let x = "let_x";
      #|    try {
      #|      eval("{ function x() {} }");
      #|      console.log("ok");
      #|    } catch (e) {
      #|      console.log(e.constructor.name);
      #|    }
      #|    console.log(x);
      #|  }
      #|}
      #|f();
    ),
  )
  json_inspect(output, content=["ok", "let_x"])
}

///|
test "eval: if-branch function does not trigger var conflict with outer let" {
  let output = run_output(
    (
      #|function f() {
      #|  {
      #|    let x = "let_x";
      #|    try {
      #|      eval("if (true) function x() {}");
      #|      console.log("ok");
      #|    } catch (e) {
      #|      console.log(e.constructor.name);
      #|    }
      #|    console.log(x);
      #|  }
      #|}
      #|f();
    ),
  )
  json_inspect(output, content=["ok", "let_x"])
}

///|
test "eval: global var conflicts with global let throws SyntaxError" {
  // Per EvalDeclarationInstantiation step 5.a, eval("var x") at global scope
  // must throw SyntaxError when a let/const x exists in the global env.
  let output = run_output(
    (
      #|let x = "let";
      #|try {
      #|  eval("var x;");
      #|  console.log("BUG");
      #|} catch (e) {
      #|  console.log(e.constructor.name);
      #|}
      #|console.log(x);
    ),
  )
  json_inspect(output, content=["SyntaxError", "let"])
}

///|
test "eval: var hoists to function scope past non-conflicting block" {
  // eval("var x = 42") in a block with no conflicting lex binding
  // should hoist x to the enclosing function scope.
  let output = run_output(
    (
      #|function test() {
      #|  { eval("var x = 42"); }
      #|  console.log(x);
      #|}
      #|test();
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "eval: function decl reassignment propagates to var_env" {
  // eval("function foo(){} foo = 42") should update var_env, not just exec_env
  let output = run_output(
    (
      #|function test() {
      #|  eval("function foo() { return 'original'; } foo = 42;");
      #|  return foo;
      #|}
      #|console.log(test());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "strict: block function does not overwrite outer var" {
  let output = run_output(
    (
      #|"use strict";
      #|var f = 1;
      #|{
      #|  function f() {}
      #|}
      #|console.log(f);
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "sloppy: duplicate block function declarations are allowed" {
  let output = run_output(
    (
      #|try {
      #|  { function f() {} function f() {} }
      #|  console.log("ok");
      #|} catch (e) {
      #|  console.log(e.constructor.name);
      #|}
    ),
  )
  json_inspect(output, content=["ok"])
}

///|
test "block: lexical and var redeclaration throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js("{ const f = 0; var f; }")
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'f' has already been declared",
  )
}

///|
test "script: let and function redeclaration throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js("let f = 0; function f() {}")
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'f' has already been declared",
  )
}

///|
test "block: function body lexical and nested var redeclaration throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f() {
        #|  let x = 0;
        #|  { var x = 1; }
        #|}
        #|f();
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'x' has already been declared",
  )
}

///|
test "block: var declarations hoist out of nested block in function scope" {
  let output = run_output(
    (
      #|function fn() {
      #|  {
      #|    var x = 1;
      #|    var y;
      #|  }
      #|  console.log(x);
      #|  console.log(y);
      #|}
      #|fn();
    ),
  )
  json_inspect(output, content=["1", "undefined"])
}

///|
test "syntax: function declaration as while body throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js("while (false) function f() {}")
  } catch {
    @errors.SyntaxError(message=msg) => err_msg = "SyntaxError: " + msg
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Function declaration in statement position is not allowed",
  )
}

///|
test "syntax: function declaration as for body throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js("for (; false; ) function f() {}")
  } catch {
    @errors.SyntaxError(message=msg) => err_msg = "SyntaxError: " + msg
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Function declaration in statement position is not allowed",
  )
}

///|
test "syntax: function declaration as do-while body throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js("do function f() {} while (false)")
  } catch {
    @errors.SyntaxError(message=msg) => err_msg = "SyntaxError: " + msg
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Function declaration in statement position is not allowed",
  )
}

// ============================================================
// P6: Strict-Mode Prerequisite Bundle tests
// ============================================================

///|
test "strict: delete unqualified identifier throws SyntaxError" {
  let src =
    #|"use strict";
    #|var x = 1;
    #|try {
    #|  delete x;
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Delete of an unqualified identifier in strict mode.",
  ])
}

///|
test "strict: delete unqualified identifier in strict function" {
  let src =
    #|function f() {
    #|  "use strict";
    #|  var x = 1;
    #|  delete x;
    #|}
    #|try {
    #|  f();
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Delete of an unqualified identifier in strict mode.",
  ])
}

///|
test "sloppy: delete unqualified identifier is allowed" {
  let src =
    #|var x = 1;
    #|var result = delete x;
    #|console.log(result);
  let output = run_output(src)
  json_inspect(output, content=["false"])
}

///|
test "delete: Member on undefined throws TypeError (non-strict)" {
  let src =
    #|var base = undefined;
    #|try {
    #|  delete base.prop;
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot convert undefined or null to object",
  ])
}

///|
test "delete: Member on null throws TypeError (non-strict)" {
  let src =
    #|var base = null;
    #|try {
    #|  delete base.prop;
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot convert undefined or null to object",
  ])
}

///|
test "delete: Member on undefined throws TypeError (strict)" {
  let src =
    #|"use strict";
    #|var base = undefined;
    #|try {
    #|  delete base.prop;
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot convert undefined or null to object",
  ])
}

///|
test "delete: Member on null throws TypeError (strict)" {
  let src =
    #|"use strict";
    #|var base = null;
    #|try {
    #|  delete base.prop;
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot convert undefined or null to object",
  ])
}

///|
test "delete: ComputedMember on undefined throws TypeError" {
  let src =
    #|var base = undefined;
    #|try {
    #|  delete base[0];
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot convert undefined or null to object",
  ])
}

///|
test "delete: ComputedMember on null throws TypeError" {
  let src =
    #|var base = null;
    #|try {
    #|  delete base["x"];
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError: Cannot convert undefined or null to object",
  ])
}

///|
test "delete: normal object property returns true (regression guard)" {
  let src =
    #|var o = { a: 1 };
    #|console.log(delete o.a);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "delete: primitive receiver still returns true (regression guard)" {
  let src =
    #|console.log(delete "foo".length);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "strict: assignment to eval throws SyntaxError" {
  let src =
    #|"use strict";
    #|eval = 42;
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "strict: assignment to arguments throws SyntaxError" {
  let src =
    #|"use strict";
    #|function f() {
    #|  arguments = [1, 2];
    #|}
    #|f();
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "strict: ++eval throws SyntaxError" {
  let src =
    #|"use strict";
    #|++eval;
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "strict: eval += 1 throws SyntaxError" {
  let src =
    #|"use strict";
    #|eval += 1;
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "sloppy: assignment to eval is allowed" {
  let src =
    #|eval = 42;
    #|console.log(typeof eval);
  let output = run_output(src)
  json_inspect(output, content=["number"])
}

///|
test "strict: var eval declaration throws SyntaxError" {
  let src =
    #|"use strict";
    #|var eval = 1;
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "strict: var arguments declaration throws SyntaxError" {
  let src =
    #|"use strict";
    #|var arguments = 1;
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "strict: destructuring assignment to eval throws SyntaxError" {
  let src =
    #|"use strict";
    #|({x: eval} = {x: 1});
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "strict: function named eval throws SyntaxError" {
  let src =
    #|"use strict";
    #|try {
    #|  function eval() {}
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected eval or arguments in strict mode",
  ])
}

///|
test "strict: duplicate parameters throw SyntaxError" {
  let src =
    #|"use strict";
    #|try {
    #|  function f(a, a) { return a; }
    #|  f(1, 2);
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Duplicate parameter name not allowed in this context",
  ])
}

///|
test "strict caller does not make sloppy callee strict" {
  let src =
    #|function f(a, a) { return a; }
    #|function g() {
    #|  "use strict";
    #|  return f(1, 2);
    #|}
    #|console.log(g());
  let output = run_output(src)
  json_inspect(output, content=["2"])
}

///|
test "strict: duplicate parameters fail at declaration time" {
  let src =
    #|"use strict";
    #|try {
    #|  function dup(a, a) {}
    #|  console.log("defined");
    #|} catch (e) {
    #|  console.log(e.constructor.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["SyntaxError"])
}

///|
test "strict: duplicate parameters abort script before later statements" {
  let src =
    #|"use strict";
    #|function dup(a, a) {}
    #|console.log("defined");
  let mut err_msg = ""
  try {
    let _ = run_output(src)
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Duplicate parameter name not allowed in this context",
  )
}

///|
test "class constructor duplicate params fail at declaration time" {
  let src =
    #|let done = "no";
    #|try {
    #|  class C { constructor(a, a) {} }
    #|  done = "yes";
    #|} catch (e) {
    #|  console.log(e.constructor.name);
    #|}
    #|console.log(done);
  let output = run_output(src)
  json_inspect(output, content=["SyntaxError", "no"])
}

///|
test "strict: duplicate parameters with use strict in function body" {
  let src =
    #|try {
    #|  function f(a, b, a) {
    #|    "use strict";
    #|    return a;
    #|  }
    #|  f(1, 2, 3);
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Duplicate parameter name not allowed in this context",
  ])
}

///|
test "sloppy: duplicate parameters are allowed" {
  let src =
    #|function f(a, a) { return a; }
    #|console.log(f(1, 2));
  let output = run_output(src)
  json_inspect(output, content=["2"])
}

///|
test "sloppy: simple arguments parameter shadows arguments object" {
  let src =
    #|function f(arguments) { return arguments; }
    #|function g(arguments, arguments) { return arguments; }
    #|console.log(f(2));
    #|console.log(g(1, 3));
  let output = run_output(src)
  json_inspect(output, content=["2", "3"])
}

///|
test "sloppy: extended arguments parameter suppresses arguments object" {
  let src =
    #|function f(arguments = 1) { return arguments; }
    #|function g(arguments, b = arguments) { return b; }
    #|function h(...arguments) { return arguments.length + ":" + arguments[0]; }
    #|function d({arguments}) { return arguments; }
    #|function k({arguments: x = arguments.length}) { return x; }
    #|function r(...[arguments]) { return arguments; }
    #|console.log(f());
    #|console.log(f(2));
    #|console.log(g(7));
    #|console.log(h(4, 5));
    #|console.log(d({arguments: 9}));
    #|console.log(k({}));
    #|console.log(r(10));
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "7", "2:4", "9", "1", "10"])
}

///|
test "sloppy: constructor arguments parameter shadows arguments object" {
  let src =
    #|function F(arguments) { this.value = arguments; }
    #|function G(arguments = 4) { this.value = arguments; }
    #|console.log(new F(3).value);
    #|console.log(new G().value);
  let output = run_output(src)
  json_inspect(output, content=["3", "4"])
}

///|
test "sloppy: generator arguments parameter shadows arguments object" {
  let src =
    #|function* f(arguments) { yield arguments; }
    #|function* g(arguments = 8) { yield arguments; }
    #|console.log(f(6).next().value);
    #|console.log(g().next().value);
  let output = run_output(src)
  json_inspect(output, content=["6", "8"])
}

///|
test "sloppy: async arguments parameter shadows arguments object" {
  let src =
    #|async function f(arguments) { return arguments; }
    #|async function g(arguments = 10) { return arguments; }
    #|f(9).then(function(v) { console.log(v); });
    #|g().then(function(v) { console.log(v); });
  let output = run_output_async(src)
  json_inspect(output, content=["9", "10"])
}

///|
test "sloppy: async generator arguments parameter shadows arguments object" {
  let src =
    #|async function* f(arguments) { yield arguments; }
    #|async function* g(arguments = 12) { yield arguments; }
    #|f(11).next().then(function(r) { console.log(r.value); });
    #|g().next().then(function(r) { console.log(r.value); });
  let output = run_output_async(src)
  json_inspect(output, content=["11", "12"])
}

///|
test "strict: parameter named eval throws SyntaxError" {
  let src =
    #|"use strict";
    #|try {
    #|  function f(eval) { return eval; }
    #|  f(1);
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected eval or arguments in strict mode",
  ])
}

///|
test "strict: parameter named arguments throws SyntaxError" {
  let src =
    #|"use strict";
    #|try {
    #|  function f(arguments) { return arguments; }
    #|  f(1);
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected eval or arguments in strict mode",
  ])
}

///|
test "strict: destructured arguments parameter throws SyntaxError" {
  let src =
    #|function f({arguments}) { "use strict"; return arguments; }
    #|f({arguments: 1});
  expect_throw(src, "SyntaxError: Unexpected eval or arguments in strict mode")
}

///|
test "strict: generator destructured arguments parameter throws SyntaxError" {
  let src =
    #|function* f({arguments}) { "use strict"; yield arguments; }
    #|f({arguments: 1}).next();
  expect_throw(src, "SyntaxError: Unexpected eval or arguments in strict mode")
}

///|
test "strict: async destructured arguments parameter throws SyntaxError" {
  let src =
    #|async function f({arguments}) { "use strict"; return arguments; }
    #|f({arguments: 1});
  expect_throw(src, "SyntaxError: Unexpected eval or arguments in strict mode")
}

///|
test "strict: async generator destructured arguments parameter throws SyntaxError" {
  let src =
    #|async function* f({arguments}) { "use strict"; yield arguments; }
    #|f({arguments: 1}).next();
  expect_throw(src, "SyntaxError: Unexpected eval or arguments in strict mode")
}

///|
test "strict: reserved word 'implements' as var name throws SyntaxError" {
  let src =
    #|"use strict";
    #|var implements = 1;
  expect_error_display(src, "SyntaxError: Unexpected strict mode reserved word")
}

///|
test "strict: reserved word 'interface' as var name throws SyntaxError" {
  let src =
    #|"use strict";
    #|var interface = 1;
  expect_error_display(src, "SyntaxError: Unexpected strict mode reserved word")
}

///|
test "strict: reserved word 'private' as var name throws SyntaxError" {
  let src =
    #|"use strict";
    #|var private = 1;
  expect_error_display(src, "SyntaxError: Unexpected strict mode reserved word")
}

///|
test "strict: reserved word 'protected' as function name throws SyntaxError" {
  let src =
    #|"use strict";
    #|try {
    #|  function protected() {}
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected strict mode reserved word",
  ])
}

///|
test "strict: reserved word 'public' as parameter name throws SyntaxError" {
  let src =
    #|"use strict";
    #|function f(public) { return public; }
    #|f(1);
  expect_error_display(src, "SyntaxError: Unexpected strict mode reserved word")
}

///|
test "strict: reserved word 'package' as var name throws SyntaxError" {
  let src =
    #|"use strict";
    #|var package = 1;
  expect_error_display(src, "SyntaxError: Unexpected strict mode reserved word")
}

///|
test "sloppy: reserved words are valid identifiers" {
  let src =
    #|var implements = 1;
    #|var interface = 2;
    #|var private = 3;
    #|console.log(implements + interface + private);
  let output = run_output(src)
  json_inspect(output, content=["6"])
}

///|
test "class body is implicitly strict: delete unqualified identifier" {
  let src =
    #|class C {
    #|  method() {
    #|    var x = 1;
    #|    return delete x;
    #|  }
    #|}
    #|try {
    #|  new C().method();
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Delete of an unqualified identifier in strict mode.",
  ])
}

///|
test "class body is implicitly strict: no arguments.callee" {
  let src =
    #|class C {
    #|  method() {
    #|    try { arguments.callee; return "no error"; }
    #|    catch(e) { return e instanceof TypeError; }
    #|  }
    #|}
    #|console.log(new C().method());
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "class constructor is implicitly strict" {
  let src =
    #|class C {
    #|  constructor() {
    #|    this.strict = (function() { return this === undefined; })();
    #|  }
    #|}
    #|var obj = new C();
    #|console.log(obj.strict);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
test "strict: function-level strict mode with eval assignment" {
  let src =
    #|function f() {
    #|  "use strict";
    #|  eval = 1;
    #|}
    #|f();
  expect_error_display(
    src, "SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "strict: yield as binding name throws SyntaxError" {
  let src =
    #|"use strict";
    #|var yield = 1;
  expect_error_display(src, "SyntaxError: Unexpected strict mode reserved word")
}

///|
test "sloppy: yield as identifier outside generator is allowed" {
  let src =
    #|var yield = 42;
    #|console.log(yield);
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
test "reserved words: yield accessor property name is allowed" {
  let src =
    #|var test = "";
    #|var obj = {
    #|  set yield(value) { test = "yield"; },
    #|  get yield() { return "yield"; }
    #|};
    #|console.log(obj.yield);
    #|obj.yield = 0;
    #|console.log(test);
  let output = run_output(src)
  json_inspect(output, content=["yield", "yield"])
}

///|
test "future reserved: static is sloppy identifier and strict reserved" {
  let sloppy =
    #|var static = 1;
    #|var st\u0061tic = 2;
    #|{ let static = 3; console.log(static); }
    #|console.log(static);
  let sloppy_output = run_output(sloppy)
  json_inspect(sloppy_output, content=["3", "2"])
  let strict =
    #|"use strict";
    #|var static = 1;
  let mut err_msg = ""
  try {
    let _ = run_js(strict)
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "SyntaxError: Unexpected strict mode reserved word",
  )
  let strict_reference =
    #|"use strict";
    #|static;
  err_msg = ""
  try {
    let _ = run_js(strict_reference)
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "SyntaxError: Unexpected strict mode reserved word",
  )
  let strict_assignment =
    #|"use strict";
    #|static = 1;
  err_msg = ""
  try {
    let _ = run_js(strict_assignment)
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "SyntaxError: Unexpected strict mode reserved word",
  )
  let strict_typeof =
    #|"use strict";
    #|typeof static;
  err_msg = ""
  try {
    let _ = run_js(strict_typeof)
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "SyntaxError: Unexpected strict mode reserved word",
  )
  let strict_unreachable_reference =
    #|"use strict";
    #|if (false) { static; }
  err_msg = ""
  try {
    let _ = run_js(strict_unreachable_reference)
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "SyntaxError: Unexpected strict mode reserved word",
  )
  let strict_unreachable_binding =
    #|"use strict";
    #|if (false) { var static; }
  err_msg = ""
  try {
    let _ = run_js(strict_unreachable_binding)
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "SyntaxError: Unexpected strict mode reserved word",
  )
}

///|
test "class constructor strict: does not leak strict mode" {
  let src =
    #|class Base {
    #|  constructor() {
    #|    this.x = 1;
    #|  }
    #|}
    #|class Derived extends Base {}
    #|var d = new Derived();
    #|// After class construction, strict mode should not leak
    #|function sloppy() { return typeof this; }
    #|console.log(d.x);
    #|console.log(sloppy());
  let output = run_output(src)
  json_inspect(output, content=["1", "object"])
}

///|
test "strict: generator declaration named eval throws SyntaxError" {
  let src =
    #|"use strict";
    #|try {
    #|  function* eval() { yield 1; }
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected eval or arguments in strict mode",
  ])
}

///|
test "strict: generator declaration named arguments throws SyntaxError" {
  let src =
    #|"use strict";
    #|try {
    #|  function* arguments() { yield 1; }
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected eval or arguments in strict mode",
  ])
}

///|
test "strict: class constructor with eval param throws SyntaxError" {
  let src =
    #|try {
    #|  class Foo { constructor(eval) {} }
    #|  new Foo();
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected eval or arguments in strict mode",
  ])
}

///|
test "strict: class constructor with arguments param throws SyntaxError" {
  let src =
    #|try {
    #|  class Bar { constructor(arguments) {} }
    #|  new Bar();
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Unexpected eval or arguments in strict mode",
  ])
}

///|
test "strict: class constructor with duplicate params throws SyntaxError" {
  let src =
    #|try {
    #|  class Baz { constructor(a, a) {} }
    #|  new Baz();
    #|  console.log("no error");
    #|} catch(e) {
    #|  console.log(e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Duplicate parameter name not allowed in this context",
  ])
}

// ===== TypedArray / ArrayBuffer / DataView test262-style tests =====

///|
test "test262: ArrayBuffer constructor basic" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|console.log(buf.byteLength);
      #|console.log(buf instanceof ArrayBuffer);
      #|console.log(typeof buf);
    ),
  )
  json_inspect(output, content=["8", "true", "object"])
}

///|
test "ArrayBuffer backing store is isolated across interpreters" {
  let interp_a = new_interpreter()
  let interp_b = new_interpreter()
  let prog_a = @parser.parse(
    (
      #|var view = new Uint8Array(1);
      #|view[0] = 77;
      #|console.log(view[0]);
      #|$262.detachArrayBuffer(view.buffer);
      #|console.log(view[0]);
    ),
  )
  let _ = interp_a.run(prog_a.stmts)
  let prog_b = @parser.parse(
    (
      #|var view = new Uint8Array(1);
      #|console.log(view[0]);
      #|console.log(view.buffer.byteLength);
    ),
  )
  let _ = interp_b.run(prog_b.stmts)

  assert_eq(interp_a.realm_state.arraybuffer_id_counter.val, 1)
  assert_eq(interp_b.realm_state.arraybuffer_id_counter.val, 1)
  json_inspect(interp_a.host.output, content=["77", "undefined"])
  json_inspect(interp_b.host.output, content=["0", "1"])
}

///|
test "ArrayBuffer backing store follows cross-realm typed arrays" {
  let output = run_output(
    (
      #|var r = $262.createRealm();
      #|r.evalScript("var view = new Uint8Array(1); view[0] = 64;");
      #|console.log(r.global.view[0]);
      #|console.log(Uint8Array.prototype.join.call(r.global.view));
      #|$262.detachArrayBuffer(r.global.view.buffer);
      #|console.log(r.global.view[0]);
      #|try {
      #|  Uint8Array.prototype.join.call(r.global.view);
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["64", "64", "undefined", "true"])
}

///|
test "test262: ArrayBuffer constructor requires new" {
  let output = run_output(
    (
      #|try {
      #|  ArrayBuffer(8);
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: ArrayBuffer allocation limit throws RangeError" {
  let output = run_output(
    (
      #|try {
      #|  new ArrayBuffer(7 * 1125899906842624);
      #|} catch(e) {
      #|  console.log(e instanceof RangeError);
      #|}
      #|try {
      #|  new ArrayBuffer(9007199254740992 - 1);
      #|} catch(e) {
      #|  console.log(e instanceof RangeError);
      #|}
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "test262: ArrayBuffer constructor uses NewTarget prototype" {
  let output = run_output(
    (
      #|var fromObject = Reflect.construct(ArrayBuffer, [8], Object);
      #|console.log(Object.getPrototypeOf(fromObject) === Object.prototype);
      #|var newTarget = function() {}.bind(null);
      #|Object.defineProperty(newTarget, "prototype", {
      #|  get: function() { return Array.prototype; }
      #|});
      #|var fromAccessor = Reflect.construct(ArrayBuffer, [16], newTarget);
      #|console.log(Object.getPrototypeOf(fromAccessor) === Array.prototype);
      #|function DummyError() {}
      #|var throwingTarget = function() {}.bind(null);
      #|Object.defineProperty(throwingTarget, "prototype", {
      #|  get: function() { throw new DummyError(); }
      #|});
      #|try {
      #|  Reflect.construct(ArrayBuffer, [1], throwingTarget);
      #|} catch (e) {
      #|  console.log(e instanceof DummyError);
      #|}
    ),
  )
  json_inspect(output, content=["true", "true", "true"])
}

///|
test "test262: ArrayBuffer.prototype.slice" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var view = new Uint8Array(buf);
      #|for (var i = 0; i < 8; i++) view[i] = i * 10;
      #|var sliced = buf.slice(2, 5);
      #|var view2 = new Uint8Array(sliced);
      #|console.log(sliced.byteLength);
      #|console.log(view2[0]);
      #|console.log(view2[1]);
      #|console.log(view2[2]);
    ),
  )
  json_inspect(output, content=["3", "20", "30", "40"])
}

///|
test "PR 214 review: ArrayBuffer slice validates species buffer" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(2);
      #|var view = new Uint8Array(buf);
      #|view[0] = 11;
      #|view[1] = 22;
      #|var ctor = {};
      #|ctor[Symbol.species] = function() { return new ArrayBuffer(0); };
      #|buf.constructor = ctor;
      #|try { buf.slice(0, 2); console.log("too-small ok"); }
      #|catch (e) { console.log(e instanceof TypeError); }
      #|ctor[Symbol.species] = function() { return buf; };
      #|try { buf.slice(0, 1); console.log("same-buffer ok"); }
      #|catch (e) { console.log(e instanceof TypeError); }
      #|ctor[Symbol.species] = function() {
      #|  $262.detachArrayBuffer(buf);
      #|  return new ArrayBuffer(2);
      #|};
      #|try { buf.slice(0, 1); console.log("detached-source ok"); }
      #|catch (e) { console.log(e instanceof TypeError); }
    ),
  )
  json_inspect(output, content=["true", "true", "true"])
}

///|
test "test262: ArrayBuffer.isView" {
  let output = run_output(
    (
      #|console.log(ArrayBuffer.isView(new Uint8Array(4)));
      #|console.log(ArrayBuffer.isView(new DataView(new ArrayBuffer(4))));
      #|console.log(ArrayBuffer.isView(new ArrayBuffer(4)));
      #|console.log(ArrayBuffer.isView({}));
      #|console.log(ArrayBuffer.isView(42));
    ),
  )
  json_inspect(output, content=["true", "true", "false", "false", "false"])
}

///|
test "test262: TypedArray constructors from length" {
  let output = run_output(
    (
      #|var a = new Int8Array(3);
      #|console.log(a.length);
      #|console.log(a.byteLength);
      #|console.log(a.BYTES_PER_ELEMENT);
      #|console.log(a[0]);
      #|var b = new Float64Array(2);
      #|console.log(b.length);
      #|console.log(b.byteLength);
      #|console.log(b.BYTES_PER_ELEMENT);
    ),
  )
  json_inspect(output, content=["3", "3", "1", "0", "2", "16", "8"])
}

///|
test "test262: BigInt typed array constructors are empty-instance stubs" {
  let output = run_output(
    (
      #|var ctors = [BigInt64Array, BigUint64Array];
      #|for (var i = 0; i < ctors.length; i++) {
      #|  var C = ctors[i];
      #|  var view = new C();
      #|  var zero = new C(0);
      #|  console.log(typeof C);
      #|  console.log(typeof C.of);
      #|  console.log(typeof C.from);
      #|  console.log(view.length, view.byteLength, view.BYTES_PER_ELEMENT);
      #|  console.log(zero.length);
      #|  view[0] = 1;
      #|  console.log(view[0] === undefined);
      #|  console.log(Object.seal(view) === view);
      #|  try { new C(1); console.log("no length throw"); }
      #|  catch (e) { console.log(e instanceof TypeError); }
      #|  try { C.of(1); console.log("no of throw"); }
      #|  catch (e) { console.log(e instanceof TypeError); }
      #|}
    ),
  )
  json_inspect(output, content=[
    "function", "undefined", "undefined", "0 0 8", "0", "true", "true", "true", "true",
    "function", "undefined", "undefined", "0 0 8", "0", "true", "true", "true", "true",
  ])
}

///|
test "test262: TypedArray.of inherited custom constructor semantics" {
  let output = run_output(
    (
      #|var TypedArray = Object.getPrototypeOf(Int8Array);
      #|console.log(Int8Array.of === TypedArray.of);
      #|console.log(Int8Array.hasOwnProperty("of"));
      #|var of = Int8Array.of;
      #|try { of(1); console.log("no throw"); }
      #|catch (e) { console.log(e instanceof TypeError); }
      #|var calls = 0;
      #|function custom(len) {
      #|  calls++;
      #|  return new Uint8Array(len + 1);
      #|}
      #|var result = Int8Array.of.call(custom, 7, 8);
      #|console.log(calls);
      #|console.log(result.length);
      #|console.log(result[0]);
      #|console.log(result[1]);
      #|console.log(result instanceof Uint8Array);
      #|function notTypedArray(len) { return {}; }
      #|try { TypedArray.of.call(notTypedArray, 1); console.log("no throw"); }
      #|catch (e) { console.log(e instanceof TypeError); }
      #|function tooShort(len) { return new Int8Array(0); }
      #|try { TypedArray.of.call(tooShort, 1); console.log("no throw"); }
      #|catch (e) { console.log(e instanceof TypeError); }
    ),
  )
  json_inspect(output, content=[
    "true", "false", "true", "1", "3", "7", "8", "true", "true", "true",
  ])
}

///|
test "test262: TypedArray constructor requires new" {
  let output = run_output(
    (
      #|try {
      #|  Int8Array(3);
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray constructor from array" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30]);
      #|console.log(a.length);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
    ),
  )
  json_inspect(output, content=["3", "10", "20", "30"])
}

///|
test "TypedArray constructor rejects primitive iterator results" {
  let output = run_output(
    (
      #|function badIterator() {
      #|  return { next: function() { return 1; } };
      #|}
      #|var arr = [1];
      #|arr[Symbol.iterator] = badIterator;
      #|try { new Int8Array(arr); console.log("array no throw"); }
      #|catch (e) { console.log(e instanceof TypeError); }
      #|var obj = {};
      #|obj[Symbol.iterator] = badIterator;
      #|try { new Int8Array(obj); console.log("object no throw"); }
      #|catch (e) { console.log(e instanceof TypeError); }
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "test262: TypedArray constructor from another TypedArray" {
  let output = run_output(
    (
      #|var a = new Int16Array([1000, 2000, 3000]);
      #|var b = new Uint8Array(a);
      #|console.log(b.length);
      #|console.log(b[0]);
      #|console.log(b[1]);
      #|console.log(b[2]);
    ),
  )
  // 1000 & 0xFF = 232, 2000 & 0xFF = 208, 3000 & 0xFF = 184
  json_inspect(output, content=["3", "232", "208", "184"])
}

///|
test "test262: TypedArray constructor from ArrayBuffer" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var u8 = new Uint8Array(buf);
      #|u8[0] = 1; u8[1] = 0; u8[2] = 2; u8[3] = 0;
      #|u8[4] = 3; u8[5] = 0; u8[6] = 4; u8[7] = 0;
      #|var u16 = new Uint16Array(buf);
      #|console.log(u16.length);
      #|console.log(u16[0]);
      #|console.log(u16[1]);
      #|console.log(u16[2]);
      #|console.log(u16[3]);
    ),
  )
  json_inspect(output, content=["4", "1", "2", "3", "4"])
}

///|
test "test262: TypedArray constructor from ArrayBuffer with byteOffset" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(12);
      #|var full = new Uint8Array(buf);
      #|for (var i = 0; i < 12; i++) full[i] = i;
      #|var view = new Uint32Array(buf, 4);
      #|console.log(view.length);
      #|console.log(view.byteOffset);
      #|console.log(view.byteLength);
    ),
  )
  json_inspect(output, content=["2", "4", "8"])
}

///|
test "test262: TypedArray constructor from ArrayBuffer with offset and length" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(12);
      #|var view = new Int32Array(buf, 4, 1);
      #|console.log(view.length);
      #|console.log(view.byteOffset);
      #|console.log(view.byteLength);
    ),
  )
  json_inspect(output, content=["1", "4", "4"])
}

///|
test "test262: TypedArray constructor rejects detached ArrayBuffer" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|$262.detachArrayBuffer(buf);
      #|try {
      #|  var a = new Uint8Array(buf);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray constructor rejects negative byteOffset" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|try {
      #|  var a = new Uint8Array(buf, -1);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof RangeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray constructor rejects unaligned byteOffset" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|try {
      #|  var a = new Int32Array(buf, 3);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof RangeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.set from array" {
  let output = run_output(
    (
      #|var a = new Uint8Array(5);
      #|a.set([10, 20, 30], 1);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
      #|console.log(a[4]);
    ),
  )
  json_inspect(output, content=["0", "10", "20", "30", "0"])
}

///|
test "test262: TypedArray.prototype.set from TypedArray" {
  let output = run_output(
    (
      #|var src = new Uint8Array([10, 20, 30]);
      #|var dst = new Uint8Array(5);
      #|dst.set(src, 1);
      #|console.log(dst[0]);
      #|console.log(dst[1]);
      #|console.log(dst[2]);
      #|console.log(dst[3]);
      #|console.log(dst[4]);
    ),
  )
  json_inspect(output, content=["0", "10", "20", "30", "0"])
}

///|
test "test262: TypedArray.prototype.set overlapping buffers" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var a = new Uint8Array(buf, 0, 4);
      #|var b = new Uint8Array(buf, 2, 4);
      #|a[0] = 1; a[1] = 2; a[2] = 3; a[3] = 4;
      #|b.set(a);
      #|console.log(b[0]);
      #|console.log(b[1]);
      #|console.log(b[2]);
      #|console.log(b[3]);
    ),
  )
  // After set: b should get the original a values [1,2,3,4]
  json_inspect(output, content=["1", "2", "3", "4"])
}

///|
test "test262: TypedArray.prototype.subarray" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30, 40, 50]);
      #|var sub = a.subarray(1, 4);
      #|console.log(sub.length);
      #|console.log(sub[0]);
      #|console.log(sub[1]);
      #|console.log(sub[2]);
      #|sub[0] = 99;
      #|console.log(a[1]);
    ),
  )
  // subarray shares the buffer, so modifying sub affects a
  json_inspect(output, content=["3", "20", "30", "40", "99"])
}

///|
test "test262: TypedArray.prototype.slice" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30, 40, 50]);
      #|var s = a.slice(1, 4);
      #|console.log(s.length);
      #|console.log(s[0]);
      #|console.log(s[1]);
      #|console.log(s[2]);
      #|s[0] = 99;
      #|console.log(a[1]);
    ),
  )
  // slice creates a new buffer, so modifying s does not affect a
  json_inspect(output, content=["3", "20", "30", "40", "20"])
}

///|
test "test262: TypedArray.prototype.fill" {
  let output = run_output(
    (
      #|var a = new Uint8Array(5);
      #|a.fill(42);
      #|console.log(a[0]);
      #|console.log(a[4]);
      #|a.fill(99, 1, 3);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
    ),
  )
  json_inspect(output, content=["42", "42", "42", "99", "99", "42"])
}

///|
test "test262: TypedArray.prototype.copyWithin" {
  let output = run_output(
    (
      #|var a = new Uint8Array([1, 2, 3, 4, 5]);
      #|a.copyWithin(0, 3);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
      #|console.log(a[4]);
    ),
  )
  json_inspect(output, content=["4", "5", "3", "4", "5"])
}

///|
test "test262: TypedArray.prototype.indexOf" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30, 20, 40]);
      #|console.log(a.indexOf(20));
      #|console.log(a.indexOf(20, 2));
      #|console.log(a.indexOf(99));
    ),
  )
  json_inspect(output, content=["1", "3", "-1"])
}

///|
test "test262: TypedArray.prototype.lastIndexOf" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30, 20, 40]);
      #|console.log(a.lastIndexOf(20));
      #|console.log(a.lastIndexOf(20, 2));
      #|console.log(a.lastIndexOf(99));
    ),
  )
  json_inspect(output, content=["3", "1", "-1"])
}

///|
test "test262: TypedArray indexOf skips detached integer indices" {
  let output = run_output(
    (
      #|var a = new Int8Array(1);
      #|console.log(a.indexOf(undefined, {
      #|  valueOf: function() { $262.detachArrayBuffer(a.buffer); return 0; }
      #|}));
      #|var b = new Int8Array(1);
      #|console.log(b.lastIndexOf(undefined, {
      #|  valueOf: function() { $262.detachArrayBuffer(b.buffer); return 0; }
      #|}));
      #|var c = new Int8Array(1);
      #|console.log(c.includes(undefined, {
      #|  valueOf: function() { $262.detachArrayBuffer(c.buffer); return 0; }
      #|}));
    ),
  )
  json_inspect(output, content=["-1", "-1", "true"])
}

///|
test "test262: TypedArray.prototype.includes" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30]);
      #|console.log(a.includes(20));
      #|console.log(a.includes(99));
    ),
  )
  json_inspect(output, content=["true", "false"])
}

///|
test "test262: TypedArray.prototype.reverse" {
  let output = run_output(
    (
      #|var a = new Uint8Array([1, 2, 3, 4, 5]);
      #|a.reverse();
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
      #|console.log(a[4]);
    ),
  )
  json_inspect(output, content=["5", "4", "3", "2", "1"])
}

///|
test "test262: TypedArray.prototype.sort default numeric" {
  let output = run_output(
    (
      #|var a = new Uint8Array([30, 10, 50, 20, 40]);
      #|a.sort();
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
      #|console.log(a[4]);
    ),
  )
  json_inspect(output, content=["10", "20", "30", "40", "50"])
}

///|
test "test262: TypedArray.prototype.sort with comparator" {
  let output = run_output(
    (
      #|var a = new Uint8Array([30, 10, 50, 20, 40]);
      #|a.sort(function(x, y) { return y - x; });
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
      #|console.log(a[4]);
    ),
  )
  json_inspect(output, content=["50", "40", "30", "20", "10"])
}

///|
test "test262: TypedArray.prototype.sort stability" {
  let output = run_output(
    (
      #|function compare(a, b) { return (a / 4 | 0) - (b / 4 | 0); }
      #|var pre = new Float64Array([0, 1, 2, 3, 4, 5, 6, 7]);
      #|pre.sort(compare);
      #|console.log(pre.join(","));
      #|var rev = new Float64Array([7, 6, 5, 4, 3, 2, 1, 0]);
      #|rev.sort(compare);
      #|console.log(rev.join(","));
    ),
  )
  json_inspect(output, content=["0,1,2,3,4,5,6,7", "3,2,1,0,7,6,5,4"])
}

///|
test "TypedArray.prototype.toSorted stability" {
  let output = run_output(
    (
      #|function compare(a, b) { return (a / 10 | 0) - (b / 10 | 0); }
      #|var values = [];
      #|for (var i = 99; i >= 0; i--) values.push(i);
      #|var sorted = new Float64Array(values).toSorted(compare);
      #|console.log(sorted.slice(0, 20).join(","));
      #|console.log(sorted.slice(90).join(","));
    ),
  )
  json_inspect(output, content=[
    "9,8,7,6,5,4,3,2,1,0,19,18,17,16,15,14,13,12,11,10", "99,98,97,96,95,94,93,92,91,90",
  ])
}

///|
test "test262: TypedArray.prototype.sort NaN sorts last" {
  let output = run_output(
    (
      #|var a = new Float64Array([3, NaN, 1, NaN, 2]);
      #|a.sort();
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(isNaN(a[3]));
      #|console.log(isNaN(a[4]));
    ),
  )
  json_inspect(output, content=["1", "2", "3", "true", "true"])
}

///|
test "test262: TypedArray.prototype.join" {
  let output = run_output(
    (
      #|var a = new Uint8Array([1, 2, 3]);
      #|console.log(a.join());
      #|console.log(a.join("-"));
    ),
  )
  json_inspect(output, content=["1,2,3", "1-2-3"])
}

///|
test "test262: TypedArray.prototype.toString" {
  let output = run_output(
    (
      #|var a = new Uint8Array([1, 2, 3]);
      #|console.log(a.toString());
    ),
  )
  json_inspect(output, content=["1,2,3"])
}

///|
test "TypedArray.prototype.toLocaleString rejects non-callable element hook" {
  let output = run_output(
    (
      #|Number.prototype.toLocaleString = 1;
      #|try {
      #|  new Int8Array([1]).toLocaleString();
      #|  console.log("no throw");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.at" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30]);
      #|console.log(a.at(0));
      #|console.log(a.at(-1));
      #|console.log(a.at(3));
    ),
  )
  json_inspect(output, content=["10", "30", "undefined"])
}

///|
test "test262: TypedArray.from basic" {
  let output = run_output(
    (
      #|var a = Uint8Array.from([10, 20, 30]);
      #|console.log(a.length);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
    ),
  )
  json_inspect(output, content=["3", "10", "20", "30"])
}

///|
test "test262: TypedArray.from with mapFn" {
  let output = run_output(
    (
      #|var a = Uint8Array.from([1, 2, 3], function(x) { return x * 10; });
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
    ),
  )
  json_inspect(output, content=["10", "20", "30"])
}

///|
test "test262: TypedArray.from with mapFn receives index" {
  let output = run_output(
    (
      #|var a = Uint8Array.from([10, 20, 30], function(v, i) { return v + i; });
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
    ),
  )
  json_inspect(output, content=["10", "21", "32"])
}

///|
test "test262: TypedArray.of" {
  let output = run_output(
    (
      #|var a = Uint8Array.of(10, 20, 30);
      #|console.log(a.length);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
    ),
  )
  json_inspect(output, content=["3", "10", "20", "30"])
}

///|
test "test262: TypedArray buffer property" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var a = new Uint8Array(buf);
      #|console.log(a.buffer === buf);
      #|console.log(a.buffer instanceof ArrayBuffer);
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "test262: TypedArray Uint8ClampedArray clamping" {
  let output = run_output(
    (
      #|var a = new Uint8ClampedArray(3);
      #|a[0] = -5;
      #|a[1] = 300;
      #|a[2] = 128;
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
    ),
  )
  json_inspect(output, content=["0", "255", "128"])
}

///|
test "test262: TypedArray Uint8ClampedArray banker's rounding" {
  let output = run_output(
    (
      #|var a = new Uint8ClampedArray(6);
      #|a[0] = 0.5;   // half -> round to even (0)
      #|a[1] = 1.5;   // half -> round to even (2)
      #|a[2] = 2.5;   // half -> round to even (2)
      #|a[3] = 3.5;   // half -> round to even (4)
      #|a[4] = 4.5;   // half -> round to even (4)
      #|a[5] = 5.5;   // half -> round to even (6)
      #|var result = [];
      #|for (var i = 0; i < 6; i++) result.push(a[i]);
      #|console.log(result.join(","));
    ),
  )
  json_inspect(output, content=["0,2,2,4,4,6"])
}

///|
test "test262: TypedArray Int8Array signed wrap" {
  let output = run_output(
    (
      #|var a = new Int8Array(2);
      #|a[0] = 128;
      #|a[1] = 255;
      #|console.log(a[0]);
      #|console.log(a[1]);
    ),
  )
  json_inspect(output, content=["-128", "-1"])
}

///|
test "test262: TypedArray Int16Array signed" {
  let output = run_output(
    (
      #|var a = new Int16Array(1);
      #|a[0] = 65535;
      #|console.log(a[0]);
    ),
  )
  json_inspect(output, content=["-1"])
}

///|
test "test262: TypedArray Int32Array range" {
  let output = run_output(
    (
      #|var a = new Int32Array(1);
      #|a[0] = 2147483647;
      #|console.log(a[0]);
    ),
  )
  json_inspect(output, content=["2147483647"])
}

///|
test "test262: TypedArray Float32Array precision" {
  let output = run_output(
    (
      #|var a = new Float32Array(1);
      #|a[0] = 1.5;
      #|console.log(a[0]);
    ),
  )
  json_inspect(output, content=["1.5"])
}

///|
test "test262: TypedArray Float32Array mantissa carry" {
  // Test values where mantissa rounding carries into exponent
  let output = run_output(
    (
      #|var a = new Float32Array(4);
      #|a[0] = 16777215;    // 2^24 - 1 = max exact int in float32
      #|a[1] = 16777216;    // 2^24 = still exact
      #|a[2] = 16777217;    // 2^24 + 1 = rounds to 2^24
      #|a[3] = 16777218;    // 2^24 + 2 = representable
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
    ),
  )
  json_inspect(output, content=["16777215", "16777216", "16777218", "16777218"])
}

///|
test "test262: TypedArray Float64Array" {
  let output = run_output(
    (
      #|var a = new Float64Array(1);
      #|a[0] = 1.7976931348623157e+308;
      #|console.log(a[0]);
    ),
  )
  json_inspect(output, content=["1.7976931348623157e+308"])
}

///|
test "test262: TypedArray shared buffer view" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(4);
      #|var u8 = new Uint8Array(buf);
      #|var u16 = new Uint16Array(buf);
      #|u8[0] = 1;
      #|u8[1] = 0;
      #|console.log(u16[0]);
      #|u16[1] = 256;
      #|console.log(u8[2]);
      #|console.log(u8[3]);
    ),
  )
  json_inspect(output, content=["1", "0", "1"])
}

///|
test "test262: TypedArray Symbol.toStringTag" {
  let output = run_output(
    (
      #|var a = new Uint8Array(0);
      #|console.log(Object.prototype.toString.call(a));
    ),
  )
  json_inspect(output, content=["[object Uint8Array]"])
}

///|
test "test262: TypedArray Symbol.iterator" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30]);
      #|var result = [];
      #|for (var v of a) {
      #|  result.push(v);
      #|}
      #|console.log(result.join(","));
    ),
  )
  json_inspect(output, content=["10,20,30"])
}

///|
test "test262: TypedArray entries iterator" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20]);
      #|var it = a.entries();
      #|var n1 = it.next();
      #|console.log(n1.done);
      #|console.log(n1.value[0]);
      #|console.log(n1.value[1]);
      #|var n2 = it.next();
      #|console.log(n2.value[0]);
      #|console.log(n2.value[1]);
      #|var n3 = it.next();
      #|console.log(n3.done);
    ),
  )
  json_inspect(output, content=["false", "0", "10", "1", "20", "true"])
}

///|
test "test262: TypedArray keys iterator" {
  let output = run_output(
    (
      #|var a = new Uint8Array(3);
      #|var keys = [];
      #|for (var k of a.keys()) {
      #|  keys.push(k);
      #|}
      #|console.log(keys.join(","));
    ),
  )
  json_inspect(output, content=["0,1,2"])
}

///|
test "test262: TypedArray values iterator" {
  let output = run_output(
    (
      #|var a = new Uint8Array([5, 10, 15]);
      #|var vals = [];
      #|for (var v of a.values()) {
      #|  vals.push(v);
      #|}
      #|console.log(vals.join(","));
    ),
  )
  json_inspect(output, content=["5,10,15"])
}

///|
test "test262: TypedArray out-of-bounds index returns undefined" {
  let output = run_output(
    (
      #|var a = new Uint8Array(3);
      #|console.log(a[3]);
      #|console.log(a[-1]);
      #|console.log(a[100]);
    ),
  )
  json_inspect(output, content=["undefined", "undefined", "undefined"])
}

///|
test "test262: TypedArray canonical numeric index string" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30]);
      #|console.log(a["0"]);
      #|console.log(a["1"]);
      #|console.log(a["-0"]);
      #|console.log(a["1.5"]);
    ),
  )
  json_inspect(output, content=["10", "20", "undefined", "undefined"])
}

///|
test "test262: TypedArray BYTES_PER_ELEMENT" {
  let output = run_output(
    (
      #|console.log(Int8Array.BYTES_PER_ELEMENT);
      #|console.log(Uint8Array.BYTES_PER_ELEMENT);
      #|console.log(Int16Array.BYTES_PER_ELEMENT);
      #|console.log(Uint16Array.BYTES_PER_ELEMENT);
      #|console.log(Int32Array.BYTES_PER_ELEMENT);
      #|console.log(Uint32Array.BYTES_PER_ELEMENT);
      #|console.log(Float32Array.BYTES_PER_ELEMENT);
      #|console.log(Float64Array.BYTES_PER_ELEMENT);
    ),
  )
  json_inspect(output, content=["1", "1", "2", "2", "4", "4", "4", "8"])
}

///|
test "test262: TypedArray.prototype.set range error" {
  let output = run_output(
    (
      #|var a = new Uint8Array(3);
      #|try {
      #|  a.set([1, 2, 3, 4]);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof RangeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.set array-like object" {
  let output = run_output(
    (
      #|var a = new Uint8Array(4);
      #|a.set({0: 10, 1: 20, 2: 30, length: 3});
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
    ),
  )
  json_inspect(output, content=["10", "20", "30", "0"])
}

///|
test "test262: TypedArray.prototype.set array-like coercion order" {
  let output = run_output(
    (
      #|var fromString = new Uint8Array([1, 2, 3, 4, 5]);
      #|fromString.set("678", 1);
      #|console.log(fromString.join());
      #|
      #|var sample = new Uint8Array(5);
      #|var calls = [];
      #|var src = { length: 3 };
      #|Object.defineProperty(src, "0", { get: function() {
      #|  calls.push("0:" + sample.join());
      #|  return 42;
      #|} });
      #|Object.defineProperty(src, "1", { get: function() {
      #|  calls.push("1:" + sample.join());
      #|  return 43;
      #|} });
      #|Object.defineProperty(src, "2", { get: function() {
      #|  calls.push("2:" + sample.join());
      #|  return 44;
      #|} });
      #|sample.set(src, 1);
      #|console.log(sample.join());
      #|console.log(calls.join("|"));
      #|
      #|var uncached = new Uint8Array(5);
      #|var dynamic = { length: 5, 1: 7, 2: 7, 3: 7, 4: 7 };
      #|Object.defineProperty(dynamic, "0", { get: function() {
      #|  dynamic[1] = 43; dynamic[2] = 44; dynamic[3] = 45; dynamic[4] = 46;
      #|  return 42;
      #|} });
      #|uncached.set(dynamic);
      #|console.log(uncached.join());
      #|
      #|var abruptLength = {};
      #|Object.defineProperty(abruptLength, "length", { get: function() {
      #|  throw new Error("length");
      #|} });
      #|try {
      #|  new Uint8Array(1).set(abruptLength);
      #|  console.log("no length error");
      #|} catch (e) {
      #|  console.log(e instanceof Error && e.message === "length");
      #|}
      #|
      #|try {
      #|  new Uint8Array(1).set(undefined);
      #|  console.log("no toobject error");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|}
      #|
      #|var detached = new Uint8Array(2);
      #|var calledOffset = 0;
      #|try {
      #|  detached.set([1], { valueOf: function() {
      #|    $262.detachArrayBuffer(detached.buffer);
      #|    calledOffset += 1;
      #|    return 0;
      #|  } });
      #|  console.log("no detach error");
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|}
      #|console.log(calledOffset);
      #|
      #|var mid = new Uint8Array([1, 2, 3]);
      #|var get2Called = false;
      #|var midSrc = { length: 3, 0: 42 };
      #|Object.defineProperty(midSrc, "1", { get: function() {
      #|  $262.detachArrayBuffer(mid.buffer);
      #|} });
      #|Object.defineProperty(midSrc, "2", { get: function() {
      #|  get2Called = true;
      #|  return 2;
      #|} });
      #|try {
      #|  mid.set(midSrc);
      #|  console.log("mid ok");
      #|} catch (e) {
      #|  console.log("mid threw");
      #|}
      #|console.log(get2Called);
      #|console.log(mid.length);
    ),
  )
  json_inspect(output, content=[
    "1,6,7,8,5", "0,42,43,44,0", "0:0,0,0,0,0|1:0,42,0,0,0|2:0,42,43,0,0", "42,43,44,45,46",
    "true", "true", "true", "1", "mid ok", "true", "0",
  ])
}

///|
test "test262: TypedArray.prototype.subarray negative indices" {
  let output = run_output(
    (
      #|var a = new Uint8Array([1, 2, 3, 4, 5]);
      #|var sub = a.subarray(-3, -1);
      #|console.log(sub.length);
      #|console.log(sub[0]);
      #|console.log(sub[1]);
    ),
  )
  json_inspect(output, content=["2", "3", "4"])
}

///|
test "test262: TypedArray.prototype.slice negative indices" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30, 40, 50]);
      #|var s = a.slice(-3);
      #|console.log(s.length);
      #|console.log(s[0]);
      #|console.log(s[1]);
      #|console.log(s[2]);
    ),
  )
  json_inspect(output, content=["3", "30", "40", "50"])
}

///|
test "test262: TypedArray.prototype.fill negative indices" {
  let output = run_output(
    (
      #|var a = new Uint8Array([1, 2, 3, 4, 5]);
      #|a.fill(0, -3, -1);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
      #|console.log(a[4]);
    ),
  )
  json_inspect(output, content=["1", "2", "0", "0", "5"])
}

///|
test "test262: TypedArray for-in enumeration" {
  let output = run_output(
    (
      #|var a = new Uint8Array([10, 20, 30]);
      #|var keys = [];
      #|for (var k in a) {
      #|  keys.push(k);
      #|}
      #|console.log(keys.join(","));
    ),
  )
  json_inspect(output, content=["0,1,2"])
}

///|
test "test262: DataView constructor basic" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var dv = new DataView(buf);
      #|console.log(dv.byteLength);
      #|console.log(dv.byteOffset);
      #|console.log(dv.buffer === buf);
    ),
  )
  json_inspect(output, content=["8", "0", "true"])
}

///|
test "test262: DataView constructor with offset and length" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(16);
      #|var dv = new DataView(buf, 4, 8);
      #|console.log(dv.byteLength);
      #|console.log(dv.byteOffset);
    ),
  )
  json_inspect(output, content=["8", "4"])
}

///|
test "test262: DataView constructor requires new" {
  let output = run_output(
    (
      #|try {
      #|  DataView(new ArrayBuffer(8));
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: DataView constructor rejects non-ArrayBuffer" {
  let output = run_output(
    (
      #|try {
      #|  new DataView({});
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: DataView constructor rejects negative byteOffset" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|try {
      #|  new DataView(buf, -1);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof RangeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: DataView getInt8/setInt8" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(4);
      #|var dv = new DataView(buf);
      #|dv.setInt8(0, -128);
      #|dv.setInt8(1, 127);
      #|dv.setInt8(2, 0);
      #|console.log(dv.getInt8(0));
      #|console.log(dv.getInt8(1));
      #|console.log(dv.getInt8(2));
    ),
  )
  json_inspect(output, content=["-128", "127", "0"])
}

///|
test "test262: DataView getUint8/setUint8" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(4);
      #|var dv = new DataView(buf);
      #|dv.setUint8(0, 255);
      #|dv.setUint8(1, 0);
      #|console.log(dv.getUint8(0));
      #|console.log(dv.getUint8(1));
    ),
  )
  json_inspect(output, content=["255", "0"])
}

///|
test "test262: DataView getInt16/setInt16 endianness" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(4);
      #|var dv = new DataView(buf);
      #|dv.setInt16(0, 256, false);
      #|console.log(dv.getUint8(0));
      #|console.log(dv.getUint8(1));
      #|dv.setInt16(2, 256, true);
      #|console.log(dv.getUint8(2));
      #|console.log(dv.getUint8(3));
    ),
  )
  // Big-endian: 256 = 0x0100 => byte[0]=1, byte[1]=0
  // Little-endian: 256 = 0x0100 => byte[2]=0, byte[3]=1
  json_inspect(output, content=["1", "0", "0", "1"])
}

///|
test "test262: DataView getInt32/setInt32" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var dv = new DataView(buf);
      #|dv.setInt32(0, 305419896, false);
      #|console.log(dv.getInt32(0, false));
      #|console.log(dv.getInt32(0, true));
    ),
  )
  // 305419896 = 0x12345678
  // Big-endian read back: same = 305419896
  // Little-endian read of big-endian stored: 0x78563412 = 2018915346
  json_inspect(output, content=["305419896", "2018915346"])
}

///|
test "test262: DataView getFloat64/setFloat64" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var dv = new DataView(buf);
      #|dv.setFloat64(0, 3.14);
      #|console.log(dv.getFloat64(0));
    ),
  )
  json_inspect(output, content=["3.14"])
}

///|
test "test262: DataView setFloat missing value stores NaN" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(16);
      #|var dv = new DataView(buf);
      #|console.log(dv.setFloat32(0) === undefined);
      #|console.log(isNaN(dv.getFloat32(0)));
      #|console.log(dv.setFloat64(8) === undefined);
      #|console.log(isNaN(dv.getFloat64(8)));
    ),
  )
  json_inspect(output, content=["true", "true", "true", "true"])
}

///|
test "test262: DataView BigInt methods are exposed but not constructors" {
  let output = run_output(
    (
      #|var dv = new DataView(new ArrayBuffer(16));
      #|var methods = [
      #|  ["getBigInt64", 1],
      #|  ["getBigUint64", 1],
      #|  ["setBigInt64", 2],
      #|  ["setBigUint64", 2]
      #|];
      #|for (var i = 0; i < methods.length; i++) {
      #|  var name = methods[i][0];
      #|  var expectedLength = methods[i][1];
      #|  var method = DataView.prototype[name];
      #|  console.log(typeof method, method.length === expectedLength);
      #|  try {
      #|    method.call(dv, 0, 0);
      #|    console.log("no call error");
      #|  } catch(e) {
      #|    console.log(e instanceof TypeError);
      #|  }
      #|  try {
      #|    new method(0, 0);
      #|    console.log("no construct error");
      #|  } catch(e) {
      #|    console.log(e instanceof TypeError);
      #|  }
      #|}
    ),
  )
  json_inspect(output, content=[
    "function true", "true", "true", "function true", "true", "true", "function true",
    "true", "true", "function true", "true", "true",
  ])
}

///|
test "test262: DataView out-of-bounds access" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(4);
      #|var dv = new DataView(buf);
      #|try {
      #|  dv.getInt32(2);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof RangeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: DataView receiver brand check" {
  let output = run_output(
    (
      #|var dv = new DataView(new ArrayBuffer(4));
      #|var getInt8 = dv.getInt8;
      #|try {
      #|  getInt8.call({}, 0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: DataView Symbol.toStringTag" {
  let output = run_output(
    (
      #|var dv = new DataView(new ArrayBuffer(4));
      #|console.log(Object.prototype.toString.call(dv));
    ),
  )
  json_inspect(output, content=["[object DataView]"])
}

///|
test "test262: detachArrayBuffer makes TypedArray return undefined" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var a = new Uint8Array(buf);
      #|a[0] = 42;
      #|console.log(a[0]);
      #|$262.detachArrayBuffer(buf);
      #|console.log(a[0]);
    ),
  )
  json_inspect(output, content=["42", "undefined"])
}

///|
test "test262: TypedArray.prototype.sort comparator error propagation" {
  let output = run_output(
    (
      #|var a = new Uint8Array([3, 1, 2]);
      #|try {
      #|  a.sort(function() { throw new Error("oops"); });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e.message);
      #|}
    ),
  )
  json_inspect(output, content=["oops"])
}

///|
test "test262: TypedArray.from with thisArg" {
  let output = run_output(
    (
      #|var obj = { multiplier: 10 };
      #|var a = Uint8Array.from([1, 2, 3], function(x) {
      #|  return x * this.multiplier;
      #|}, obj);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
    ),
  )
  json_inspect(output, content=["10", "20", "30"])
}

///|
test "test262: TypedArray all constructor types exist" {
  let output = run_output(
    (
      #|console.log(typeof Int8Array);
      #|console.log(typeof Uint8Array);
      #|console.log(typeof Uint8ClampedArray);
      #|console.log(typeof Int16Array);
      #|console.log(typeof Uint16Array);
      #|console.log(typeof Int32Array);
      #|console.log(typeof Uint32Array);
      #|console.log(typeof Float32Array);
      #|console.log(typeof Float64Array);
    ),
  )
  json_inspect(output, content=[
    "function", "function", "function", "function", "function", "function", "function",
    "function", "function",
  ])
}

///|
test "test262: TypedArray.prototype.copyWithin overlapping" {
  let output = run_output(
    (
      #|var a = new Uint8Array([1, 2, 3, 4, 5]);
      #|a.copyWithin(1, 0, 3);
      #|console.log(a[0]);
      #|console.log(a[1]);
      #|console.log(a[2]);
      #|console.log(a[3]);
      #|console.log(a[4]);
    ),
  )
  json_inspect(output, content=["1", "1", "2", "3", "5"])
}

///|
test "test262: TypedArray.prototype.includes NaN" {
  let output = run_output(
    (
      #|var a = new Float64Array([1, NaN, 3]);
      #|console.log(a.includes(NaN));
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: ArrayBuffer.prototype.slice detached throws" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|$262.detachArrayBuffer(buf);
      #|try {
      #|  buf.slice(0, 4);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: ArrayBuffer.prototype.byteLength detached returns 0" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|$262.detachArrayBuffer(buf);
      #|console.log(buf.byteLength);
    ),
  )
  json_inspect(output, content=["0"])
}

///|
test "test262: TypedArray detached buffer accessors return 0" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(16);
      #|var sample = new Int16Array(buf, 4, 3);
      #|$262.detachArrayBuffer(buf);
      #|console.log(sample.buffer === buf);
      #|console.log(sample.byteOffset);
      #|console.log(sample.byteLength);
      #|console.log(sample.length);
    ),
  )
  json_inspect(output, content=["true", "0", "0", "0"])
}

///|
test "test262: DataView on detached buffer throws" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var dv = new DataView(buf);
      #|$262.detachArrayBuffer(buf);
      #|try {
      #|  dv.getInt8(0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: DataView detached buffer accessors" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|var dv = new DataView(buf, 2, 4);
      #|$262.detachArrayBuffer(buf);
      #|console.log(dv.buffer === buf);
      #|try {
      #|  dv.byteOffset;
      #|  console.log("no offset error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
      #|try {
      #|  dv.byteLength;
      #|  console.log("no length error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true", "true", "true"])
}

///|
test "test262: DataView constructor rejects detached ArrayBuffer" {
  let output = run_output(
    (
      #|var buf = new ArrayBuffer(8);
      #|$262.detachArrayBuffer(buf);
      #|try {
      #|  new DataView(buf);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: DataView constructor orders offset/prototype/detach checks" {
  let output = run_output(
    (
      #|var detached = new ArrayBuffer(8);
      #|var offsetCalls = 0;
      #|var offset = { valueOf: function() { offsetCalls += 1; return 0; } };
      #|$262.detachArrayBuffer(detached);
      #|try {
      #|  new DataView(detached, offset);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
      #|console.log(offsetCalls);
      #|
      #|function newTarget() {}
      #|var proto = {};
      #|newTarget.prototype = proto;
      #|var sample = Reflect.construct(DataView, [new ArrayBuffer(8), 0], newTarget);
      #|console.log(Object.getPrototypeOf(sample) === proto);
      #|console.log(sample.constructor === Object);
      #|
      #|var buffer = new ArrayBuffer(8);
      #|var called = false;
      #|var detachingOffset = { valueOf: function() { called = true; return 0; } };
      #|var detachingNewTarget = function() {}.bind(null);
      #|Object.defineProperty(detachingNewTarget, "prototype", {
      #|  get: function() {
      #|    $262.detachArrayBuffer(buffer);
      #|    return DataView.prototype;
      #|  }
      #|});
      #|try {
      #|  Reflect.construct(DataView, [buffer, detachingOffset], detachingNewTarget);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
      #|console.log(called);
    ),
  )
  json_inspect(output, content=["true", "1", "true", "true", "true", "true"])
}

///|
/// §22.2.3.9 %TypedArray%.prototype.filter step 10 invokes
/// TypedArraySpeciesCreate(O, « captured »). Per §7.3.20 SpeciesConstructor
/// step 4, if `Get(O, "constructor")` is a non-Object non-undefined value,
/// throw TypeError. Pinned for filter; same invariant on map/slice/subarray.
test "test262: TypedArray.prototype.filter throws when constructor is non-Object" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|sample.constructor = 42;
      #|try {
      #|  sample.filter(function() { return true; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.map throws when constructor is non-Object" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|sample.constructor = "string";
      #|try {
      #|  sample.map(function(x) { return x; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.slice throws when constructor is non-Object" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|sample.constructor = null === sample.constructor ? Int8Array : 42;
      #|try {
      #|  sample.slice(0, 2);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.subarray throws when constructor is non-Object" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|sample.constructor = false;
      #|try {
      #|  sample.subarray(0, 2);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
/// §22.2.4.7 TypedArraySpeciesCreate step 3 + §7.3.20 step 6: if
/// `C[@@species]` is null/undefined, fall back to the default constructor.
/// Verifies the spec-required fast path: setting `sample.constructor` to
/// undefined should NOT throw — it just uses the default Int8Array ctor.
test "test262: TypedArray.prototype.filter uses default ctor when constructor is undefined" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3, 4]);
      #|sample.constructor = undefined;
      #|var result = sample.filter(function(x) { return x % 2 === 0; });
      #|console.log(result instanceof Int8Array, result.length);
    ),
  )
  json_inspect(output, content=["true 2"])
}

///|
/// §22.2.4.7 step 5: if `S[@@species]` is callable, use it to construct
/// the result. Pinned positive test: custom species ctor returns the
/// correct type (here Uint8Array instead of the default Int8Array).
test "test262: TypedArray.prototype.map honors custom @@species" {
  let output = run_output(
    (
      #|var Ctor = function Ctor() {};
      #|Ctor[Symbol.species] = Uint8Array;
      #|var sample = new Int8Array([1, 2, 3]);
      #|sample.constructor = Ctor;
      #|var result = sample.map(function(x) { return x * 2; });
      #|console.log(result instanceof Uint8Array, result.length, result[0]);
    ),
  )
  json_inspect(output, content=["true 3 2"])
}

///|
/// Codex P2 (PR B review): `sample.constructor = []` must NOT throw — Array
/// is an Object per spec Type(C), and our runtime has Array as a distinct
/// Value variant from Object (six object-typed variants total). Initial
/// implementation matched `Object(_)` only and spuriously rejected this.
/// The fix uses `is_object_value` for the Type(C) check.
test "test262: TypedArray.prototype.filter accepts Array-variant as constructor" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|sample.constructor = [];
      #|var result = sample.filter(function(x) { return x > 1; });
      #|console.log(result instanceof Int8Array, result.length);
    ),
  )
  // `[]` is an Object with no own constructor.[@@species]; falls back to
  // default Int8Array ctor.
  json_inspect(output, content=["true 2"])
}

///|
/// Codex (post-PR-#121 review, second pass): §22.2.3.20 map has NO post-
/// species source-detach validation. If a species ctor detaches the source
/// mid-construction, `Get(O, Pk)` returns Undefined per IntegerIndexedElement
/// Get, the callback observes it, and the result holds coerced values. The
/// initial Codex-bot P1 pattern-matched off slice (which DOES validate, but
/// only when count > 0); that fix was spec-incorrect and reverted.
test "test262: TypedArray.prototype.map does NOT throw when species detaches source" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3, 4]);
      #|function CustomCtor(n) {
      #|  $262.detachArrayBuffer(sample.buffer);
      #|  return new Int8Array(n);
      #|}
      #|CustomCtor[Symbol.species] = CustomCtor;
      #|sample.constructor = CustomCtor;
      #|var result = sample.map(function(x) { return x; });
      #|// Result is an Int8Array of length 4, filled with zeros because
      #|// Get on a detached source returns undefined → ToNumber → NaN →
      #|// Int8 coerced 0.
      #|console.log(result instanceof Int8Array, result.length, result[0], result[3]);
    ),
  )
  json_inspect(output, content=["true 4 0 0"])
}

///|
/// Codex P1 (PR B review): if a custom species constructor detaches
/// `sample.buffer` as a side effect, slice must re-validate the SOURCE
/// before copying. Without the re-validate, `typedarray_get_index` silently
/// returns `Undefined`, producing a zero-filled result instead of the
/// spec-required TypeError. Mirrors test262's
/// `detached-buffer-custom-ctor-{same,other}-targettype.js` fixtures.
test "test262: TypedArray.prototype.slice throws when species detaches source" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3, 4]);
      #|function CustomCtor(n) {
      #|  $262.detachArrayBuffer(sample.buffer);
      #|  return new Int8Array(n);
      #|}
      #|CustomCtor[Symbol.species] = CustomCtor;
      #|sample.constructor = CustomCtor;
      #|try {
      #|  sample.slice(0, 2);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
/// §7.3.20 step 7: if `C[@@species]` is non-callable (e.g. a string), throw
/// TypeError. Pinned for map; structurally identical for filter/slice/subarray.
test "test262: TypedArray.prototype.map throws when @@species is non-callable" {
  let output = run_output(
    (
      #|var Ctor = function Ctor() {};
      #|Ctor[Symbol.species] = "not a constructor";
      #|var sample = new Int8Array([1, 2, 3]);
      #|sample.constructor = Ctor;
      #|try {
      #|  sample.map(function(x) { return x; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
/// Codex bot P1 (PR #121 review): §22.2.4.7 step 2 says defaultConstructor is
/// the *intrinsic* TA constructor for the exemplar's [[TypedArrayName]], not
/// the mutable global binding. If user code reassigns `Int8Array = Uint8Array`,
/// `sample.map(...)` on an Int8Array (with default species path) must still
/// build an Int8Array — the writable global must not poison species default.
test "test262: TypedArray species default uses intrinsic, not reassigned global" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|var OriginalInt8 = sample.constructor;
      #|Int8Array = Uint8Array;
      #|var result = sample.map(function(x) { return x; });
      #|console.log(result instanceof OriginalInt8, result.constructor === OriginalInt8);
    ),
  )
  // Default species path runs because `sample.constructor` is the intrinsic
  // (not reassigned) and its @@species is the same intrinsic. The result
  // must come from the *intrinsic* Int8Array slot, untouched by the global
  // reassignment.
  json_inspect(output, content=["true true"])
}

///|
/// Codex finding 1 (post-PR-#121, second pass): §22.2.3.20 step 4 says
/// IsCallable(callbackfn) check runs BEFORE TypedArraySpeciesCreate. A
/// numeric (non-callable) callback must throw without invoking @@species —
/// otherwise observable species side effects leak. Pinned: `@@species` getter
/// counts invocations; a TypeError before species means count stays 0.
test "test262: TypedArray.prototype.map non-callable throws before species" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|var speciesCalls = 0;
      #|var Ctor = function Ctor() {};
      #|Object.defineProperty(Ctor, Symbol.species, {
      #|  get: function() { speciesCalls++; return Int8Array; }
      #|});
      #|sample.constructor = Ctor;
      #|try {
      #|  sample.map(1);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError, speciesCalls);
      #|}
    ),
  )
  json_inspect(output, content=["true 0"])
}

///|
/// Same as the map test above, but for filter (§22.2.3.9 step 4).
test "test262: TypedArray.prototype.filter non-callable throws before species" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3]);
      #|var speciesCalls = 0;
      #|var Ctor = function Ctor() {};
      #|Object.defineProperty(Ctor, Symbol.species, {
      #|  get: function() { speciesCalls++; return Int8Array; }
      #|});
      #|sample.constructor = Ctor;
      #|try {
      #|  sample.filter("not a function");
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError, speciesCalls);
      #|}
    ),
  )
  json_inspect(output, content=["true 0"])
}

///|
/// %TypedArray%.prototype reduce/find family methods must reject
/// non-callable callbacks even when the loop body is unreachable, and
/// toSorted must reject/cancel invalid or throwing comparators before it
/// silently returns a copied array.
test "test262: TypedArray callback and comparator callable checks" {
  let output = run_output(
    (
      #|function check(label, thunk) {
      #|  try {
      #|    thunk();
      #|    console.log(label + ":no");
      #|  } catch (e) {
      #|    console.log(label + ":" + (e instanceof TypeError));
      #|  }
      #|}
      #|var empty = new Int8Array(0);
      #|var single = new Int8Array([1]);
      #|check("reduce", function() { single.reduce(undefined); });
      #|check("reduceRight", function() { single.reduceRight(null); });
      #|check("find", function() { empty.find({}); });
      #|check("findIndex", function() { empty.findIndex([]); });
      #|check("findLast", function() { empty.findLast(1); });
      #|check("findLastIndex", function() { empty.findLastIndex(""); });
      #|check("toSorted", function() { new Int8Array([1]).toSorted(null); });
      #|console.log("stringRegExp:" + String(/a/g));
      #|var calls = 0;
      #|try {
      #|  new Int8Array([3, 1, 2]).toSorted(function() {
      #|    calls++;
      #|    throw new TypeError("stop");
      #|  });
      #|  console.log("toSortedError:no");
      #|} catch (e) {
      #|  console.log("toSortedError:" + (e instanceof TypeError) + ":" + calls);
      #|}
    ),
  )
  json_inspect(output, content=[
    "reduce:true", "reduceRight:true", "find:true", "findIndex:true", "findLast:true",
    "findLastIndex:true", "toSorted:true", "stringRegExp:/a/g", "toSortedError:true:1",
  ])
}

///|
/// Codex finding 2 (post-PR-#121, second pass): §22.2.3.27 slice step 14
/// guards source re-validation on `count > 0`. A zero-count slice with a
/// species ctor that detaches the source must NOT throw — it returns an
/// empty TA of the species type. Without the guard, my initial fix threw
/// too eagerly.
test "test262: TypedArray.prototype.slice with zero count tolerates source detach" {
  let output = run_output(
    (
      #|var sample = new Int8Array([1, 2, 3, 4]);
      #|function CustomCtor(n) {
      #|  $262.detachArrayBuffer(sample.buffer);
      #|  return new Int8Array(n);
      #|}
      #|CustomCtor[Symbol.species] = CustomCtor;
      #|sample.constructor = CustomCtor;
      #|var result = sample.slice(0, 0);
      #|console.log(result instanceof Int8Array, result.length);
    ),
  )
  // count = 0, so the spec's step 14 detach check is skipped entirely. The
  // species ctor's detach side effect is allowed; the result is an empty TA.
  json_inspect(output, content=["true 0"])
}

///|
/// Length-zero variant of the map / species-detaches test: spec has no
/// detach check, and the loop doesn't run, so the result is an empty TA
/// of the species type. Forcing function — an implementation that
/// (incorrectly) re-validates source post-species would fail this even
/// though the loop body is unreachable.
test "test262: TypedArray.prototype.map with zero length tolerates source detach" {
  let output = run_output(
    (
      #|var sample = new Int8Array(0);
      #|function CustomCtor(n) {
      #|  $262.detachArrayBuffer(sample.buffer);
      #|  return new Int8Array(n);
      #|}
      #|CustomCtor[Symbol.species] = CustomCtor;
      #|sample.constructor = CustomCtor;
      #|var result = sample.map(function(x) { return x; });
      #|console.log(result instanceof Int8Array, result.length);
    ),
  )
  json_inspect(output, content=["true 0"])
}

///|
/// §22.2.3.5.1 ValidateTypedArray: most %TypedArray%.prototype methods must
/// throw TypeError at entry if the underlying buffer is detached. Pinned
/// per-method tests below mirror test262's
/// `built-ins/TypedArray/prototype/<method>/detached-buffer.js` fixtures,
/// which previously failed because methods skipped the validate step.
test "test262: TypedArray.prototype.reverse detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.reverse();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.copyWithin detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.copyWithin(0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.fill detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.fill(0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.slice detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.slice();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.subarray detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.subarray();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray fill/copyWithin/subarray detachment order" {
  let output = run_output(
    (
      #|function check(label, thunk) {
      #|  try {
      #|    thunk();
      #|    console.log(label + ": no error");
      #|  } catch (e) {
      #|    console.log(label + ": " + (e instanceof TypeError));
      #|  }
      #|}
      #|
      #|var fillValue = new Int8Array(4);
      #|check("fill value", function() {
      #|  fillValue.fill({ valueOf: function() {
      #|    $262.detachArrayBuffer(fillValue.buffer);
      #|    return 1;
      #|  } }, 0, 1);
      #|});
      #|
      #|var fillStart = new Int8Array(4);
      #|check("fill start", function() {
      #|  fillStart.fill(1, { valueOf: function() {
      #|    $262.detachArrayBuffer(fillStart.buffer);
      #|    return 0;
      #|  } }, 1);
      #|});
      #|
      #|var fillEnd = new Int8Array(4);
      #|check("fill end", function() {
      #|  fillEnd.fill(1, 0, { valueOf: function() {
      #|    $262.detachArrayBuffer(fillEnd.buffer);
      #|    return 1;
      #|  } });
      #|});
      #|
      #|var copyStart = new Int8Array([1, 2, 3, 4]);
      #|check("copyWithin start", function() {
      #|  copyStart.copyWithin(0, { valueOf: function() {
      #|    $262.detachArrayBuffer(copyStart.buffer);
      #|    return 1;
      #|  } }, 3);
      #|});
      #|
      #|var copyEnd = new Int8Array([1, 2, 3, 4]);
      #|check("copyWithin end", function() {
      #|  copyEnd.copyWithin(0, 1, { valueOf: function() {
      #|    $262.detachArrayBuffer(copyEnd.buffer);
      #|    return 3;
      #|  } });
      #|});
      #|
      #|var sub = new Int8Array(2);
      #|var begin = false;
      #|var end = false;
      #|$262.detachArrayBuffer(sub.buffer);
      #|check("subarray", function() {
      #|  sub.subarray({ valueOf: function() {
      #|    begin = true;
      #|    return 0;
      #|  } }, { valueOf: function() {
      #|    end = true;
      #|    return 1;
      #|  } });
      #|});
      #|console.log("subarray coercions: " + begin + "," + end);
    ),
  )
  json_inspect(output, content=[
    "fill value: true", "fill start: true", "fill end: true", "copyWithin start: true",
    "copyWithin end: true", "subarray: true", "subarray coercions: true,true",
  ])
}

///|
test "test262: TypedArray.prototype.set detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.set([0, 0]);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.map detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.map(function() {});
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.filter detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.filter(function() {});
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.forEach detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.forEach(function() {});
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.every detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.every(function() {});
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.some detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.some(function() {});
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.find detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.find(function() { return true; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.findIndex detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.findIndex(function() { return true; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.findLast detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.findLast(function() { return true; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.findLastIndex detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.findLastIndex(function() { return true; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.reduce detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.reduce(function(a, b) { return a; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.reduceRight detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.reduceRight(function(a, b) { return a; });
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.indexOf detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.indexOf(0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.lastIndexOf detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.lastIndexOf(0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.includes detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.includes(0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.join detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.join();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.toString detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.toString();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.at detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.at(0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.keys detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.keys();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.values detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.values();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.entries detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.entries();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.sort detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.sort();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.toReversed detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.toReversed();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.toSorted detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.toSorted();
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "test262: TypedArray.prototype.with detached throws" {
  let output = run_output(
    (
      #|var sample = new Int8Array(2);
      #|$262.detachArrayBuffer(sample.buffer);
      #|try {
      #|  sample.with(0, 0);
      #|  console.log("no error");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "class fields on Map subclass" {
  let output = run_output(
    (
      #|class D extends Map {
      #|  x = 1;
      #|  constructor() { super(); }
      #|}
      #|const d = new D();
      #|console.log(d.x);
      #|console.log(d instanceof Map);
    ),
  )
  json_inspect(output, content=["1", "true"])
}

///|
test "class fields on Set subclass" {
  let output = run_output(
    (
      #|class S extends Set {
      #|  label = 'my-set';
      #|}
      #|const s = new S();
      #|console.log(s.label);
      #|console.log(s instanceof Set);
    ),
  )
  json_inspect(output, content=["my-set", "true"])
}

///|
test "PR 214 review: explicit super object return keeps original prototype" {
  let output = run_output(
    (
      #|class B { constructor() { return {}; } }
      #|class D extends B { constructor() { super(); } }
      #|var d = new D();
      #|console.log(d instanceof D);
      #|console.log(Object.getPrototypeOf(d) === D.prototype);
      #|console.log(Object.getPrototypeOf(d) === Object.prototype);
      #|function F() { return {}; }
      #|class G extends F { constructor() { super(); } }
      #|var g = new G();
      #|console.log(g instanceof G);
      #|console.log(Object.getPrototypeOf(g) === G.prototype);
      #|console.log(Object.getPrototypeOf(g) === Object.prototype);
    ),
  )
  json_inspect(output, content=[
    "false", "false", "true", "false", "false", "true",
  ])
}

///|
test "PR 214 review: class heritage accepts array and proxy prototypes" {
  let output = run_output(
    (
      #|function ArrayParent() {}
      #|var arrayProto = [];
      #|ArrayParent.prototype = arrayProto;
      #|class ArrayChild extends ArrayParent {}
      #|console.log(Object.getPrototypeOf(ArrayChild.prototype) === arrayProto);
      #|var proxyProto = new Proxy({}, {});
      #|function ProxyParent() {}
      #|ProxyParent.prototype = proxyProto;
      #|class ProxyChild extends ProxyParent {}
      #|console.log(Object.getPrototypeOf(ProxyChild.prototype) === proxyProto);
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "PR 214 review: Symbol heritage remains valid while Proxy has no prototype" {
  let output = run_output(
    (
      #|function F() {}
      #|class C extends Symbol {}
      #|console.log(typeof C);
      #|try { new C(); console.log("new symbol subclass ok"); }
      #|catch (e) { console.log(e instanceof TypeError); }
      #|var reflected = Reflect.construct(F, [], Symbol);
      #|console.log(Object.getPrototypeOf(reflected) === Symbol.prototype);
      #|console.log(Object.prototype.hasOwnProperty.call(Proxy, "prototype"));
      #|console.log(Object.getOwnPropertyDescriptor(Proxy, "prototype") === undefined);
      #|var names = Object.getOwnPropertyNames(Proxy);
      #|var found = false;
      #|for (var i = 0; i < names.length; i++) { if (names[i] === "prototype") found = true; }
      #|console.log(found);
      #|try { class P extends Proxy {} console.log("proxy heritage ok"); }
      #|catch (e) { console.log(e instanceof TypeError); }
    ),
  )
  json_inspect(output, content=[
    "function", "true", "true", "false", "true", "false", "true",
  ])
}

///|
test "Map and Set well-known symbol computed access" {
  let output = run_output(
    (
      #|const m = new Map();
      #|const s = new Set();
      #|console.log(m[Symbol.iterator] === Map.prototype.entries);
      #|console.log(m[Symbol.toStringTag]);
      #|console.log(s[Symbol.iterator] === Set.prototype.values);
      #|console.log(s[Symbol.toStringTag]);
    ),
  )
  json_inspect(output, content=["true", "Map", "true", "Set"])
}

///|
test "regex flag ordering is normalized to alphabetical" {
  let output = run_output(
    (
      #|console.log(new RegExp("x", "smig").flags);
      #|console.log(new RegExp("x", "yg").flags);
      #|console.log(new RegExp("x", "igsm").flags);
      #|console.log(/abc/gi.flags);
    ),
  )
  json_inspect(output, content=["gims", "gy", "gims", "gi"])
}

///|
test "GeneratorFunction constructor throws SyntaxError on bad source" {
  let output = run_output(
    (
      #|var GF = Object.getPrototypeOf(function*(){}).constructor;
      #|try { GF("???"); } catch(e) { console.log(e instanceof SyntaxError); }
      #|try { GF("a", "???"); } catch(e) { console.log(e instanceof SyntaxError); }
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "GeneratorPrototype is a shared singleton across generator functions (§27.3.1)" {
  let output = run_output(
    (
      #|function* g1() {}
      #|function* g2() {}
      #|console.log(Object.getPrototypeOf(g1.prototype) === Object.getPrototypeOf(g2.prototype));
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "GeneratorPrototype own key order is constructor,next,return,throw (§27.3.1)" {
  let output = run_output(
    (
      #|function* g() {}
      #|var proto = Object.getPrototypeOf(g.prototype);
      #|console.log(Object.getOwnPropertyNames(proto).join(','));
    ),
  )
  json_inspect(output, content=["constructor,next,return,throw"])
}

///|
test "GeneratorPrototype.constructor points to GeneratorFunction.prototype (§27.3.1.1)" {
  let output = run_output(
    (
      #|function* g1() {}
      #|function* g2() {}
      #|var GeneratorProto = Object.getPrototypeOf(g1.prototype);
      #|var GeneratorFuncProto = Object.getPrototypeOf(g1);
      #|console.log(GeneratorProto.constructor === GeneratorFuncProto);
      #|console.log(Object.getPrototypeOf(g1) === Object.getPrototypeOf(g2));
      #|console.log(GeneratorFuncProto[Symbol.toStringTag]);
    ),
  )
  json_inspect(output, content=["true", "true", "GeneratorFunction"])
}

///|
test "GeneratorFunction.prototype.prototype descriptor is configurable:true (§27.3.3.2)" {
  let output = run_output(
    (
      #|function* g() {}
      #|var GeneratorFuncProto = Object.getPrototypeOf(g);
      #|var d = Object.getOwnPropertyDescriptor(GeneratorFuncProto, 'prototype');
      #|console.log(d.writable);
      #|console.log(d.enumerable);
      #|console.log(d.configurable);
      #|var ctorDesc = Object.getOwnPropertyDescriptor(g.constructor, 'prototype');
      #|console.log(ctorDesc.configurable);
    ),
  )
  // gen_func_proto.prototype: writable=false, enumerable=false, configurable=true (§27.3.3.2)
  // gen_func_ctor.prototype: configurable=false (§27.3.2.2)
  json_inspect(output, content=["false", "false", "true", "false"])
}

///|
test "GeneratorFunction.prototype own key order is constructor,prototype (§27.3.3)" {
  let output = run_output(
    (
      #|function* g() {}
      #|var GeneratorFuncProto = Object.getPrototypeOf(g);
      #|console.log(Object.getOwnPropertyNames(GeneratorFuncProto).join(','));
    ),
  )
  json_inspect(output, content=["constructor,prototype"])
}

///|
test "GeneratorPrototype inherits Symbol.iterator from %IteratorPrototype% (§27.3.1)" {
  let output = run_output(
    (
      #|function* g() {}
      #|var GenProto = Object.getPrototypeOf(g.prototype);
      #|// Symbol.iterator is NOT an own property — inherited from %IteratorPrototype%
      #|console.log(Object.getOwnPropertyDescriptor(GenProto, Symbol.iterator) === undefined);
      #|// But accessible via prototype chain (returns this per §27.1.2)
      #|var gen = g();
      #|console.log(gen[Symbol.iterator]() === gen);
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
// Chain: gen → g.prototype → %GeneratorPrototype% → %IteratorPrototype% → %ObjectPrototype%
test "generator instances are instanceof Object (§27.3.1 prototype chain)" {
  let output = run_output(
    (
      #|function* g() {}
      #|var gen = g();
      #|console.log(gen instanceof Object);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "Function.prototype.toString distinguishes async functions" {
  let src =
    #|console.log((function foo(){}).toString());
    #|console.log((async function bar(){}).toString());
  let output = run_output(src)
  json_inspect(output, content=["function foo(){}", "async function bar(){}"])
}

///|
test "Function.prototype.toString preserves parsed source text" {
  let output = run_output(
    (
      #|console.log((function f() {}).toString());
      #|console.log((() => 42).toString());
      #|console.log((() => /x/g).toString());
      #|console.log((() => `x`).toString());
      #|let escapedIdent = 1;
      #|console.log((() => \u0065scapedIdent).toString());
      #|console.log((x => { return x; }).toString());
      #|console.log((async () => {}).toString());
      #|console.log((function* g() {}).toString());
      #|function* hg() {}
      #|console.log(hg.toString());
      #|async function ha() {}
      #|console.log(ha.toString());
      #|async function* hag() {}
      #|console.log(hag.toString());
      #|console.log((class Foo {}).toString());
      #|console.log(Function("return 1").toString());
      #|console.log(Function().toString());
      #|let GF = Object.getPrototypeOf(function*(){}).constructor;
      #|console.log(GF().toString());
      #|let AF = Object.getPrototypeOf(async function(){}).constructor;
      #|console.log(AF().toString());
      #|let C = class { get x(){} set y(v){} async m(){} *g(){} };
      #|console.log(Object.getOwnPropertyDescriptor(C.prototype, "x").get.toString());
      #|console.log(Object.getOwnPropertyDescriptor(C.prototype, "y").set.toString());
      #|console.log(C.prototype.m.toString());
      #|console.log(C.prototype.g.toString());
      #|let p = new Proxy(function f(){}, {});
      #|console.log(Function.prototype.toString.call(p));
      #|console.log(String(p));
      #|console.log(parseInt.toString());
      #|console.log((function(){}).bind(null).toString());
    ),
  )
  json_inspect(output, content=[
    "function f() {}", "() => 42", "() => /x/g", "() => `x`", "() => \\u0065scapedIdent",
    "x => { return x; }", "async () => {}", "function* g() {}", "function* hg() {}",
    "async function ha() {}", "async function* hag() {}", "class Foo {}", "function anonymous(\n) {\nreturn 1\n}",
    "function anonymous(\n) {\n\n}", "function* anonymous(\n) {\n\n}", "async function anonymous(\n) {\n\n}",
    "get x(){}", "set y(v){}", "async m(){}", "*g(){}", "function proxy() { [native code] }",
    "function proxy() { [native code] }", "function parseInt() { [native code] }",
    "function bound() { [native code] }",
  ])
}

///|
test "Function.prototype.toString: template tail end_offset includes closing backtick" {
  // Arrow whose body ends with a TemplateTail token (raw:"" because lexer
  // doesn't fill raw for templates). Verifies advance→last_end→consume_source_text
  // uses end_offset rather than loc.offset+raw.length(), which would give 0+0=start.
  let output = run_output(
    (
      #|let y = 1;
      #|console.log((() => `x${y}`).toString());
    ),
  )
  json_inspect(output, content=["() => `x${y}`"])
}

///|
test "Function.prototype.toString: numeric separator preserved in source" {
  // Arrow whose body ends with a NumericLiteral whose raw has underscores stripped.
  // end_offset is set to lexer's offset (past the full token), not loc.offset+raw.length().
  let output = run_output(
    (
      #|console.log((() => 1_000).toString());
    ),
  )
  json_inspect(output, content=["() => 1_000"])
}

///|
test "Function.prototype.toString: astral-plane identifier in body (2 UTF-16 units)" {
  // 𝒜 (U+1D49C) is 1 code point but 2 UTF-16 code units.
  // With end_offset=offset (code-point-based), only 1 unit was included and
  // consume_source_text returned a half-surrogate. With end_offset=loc.offset+
  // decoded.length() (UTF-16 units), both code units are included correctly.
  // No prior astral chars in source — this isolates the per-identifier regression.
  let output = run_output(
    (
      #|console.log((() => 𝒜).toString());
    ),
  )
  json_inspect(output, content=["() => 𝒜"])
}

///|
test "Function.prototype.toString: loc.offset correct when prior astral identifier shifts UTF-16 positions" {
  // The first 𝒜 (binding) causes astral_count=1 after its token is scanned.
  // Without the loc.offset fix, the second 𝒜 (body) gets loc.offset off by 1,
  // and unsafe_substring returns a half-surrogate instead of the full char.
  let output = run_output(
    (
      #|var 𝒜 = 1;
      #|console.log((() => 𝒜).toString());
    ),
  )
  json_inspect(output, content=["() => 𝒜"])
}

///|
test "Function.prototype.toString: loc.offset correct when prior astral char in string" {
  // "𝒜" advances astral_count by 1; the arrow function body token must have
  // the correct UTF-16 loc.offset so toString returns unshifted source text.
  let output = run_output(
    (
      #|"𝒜";
      #|console.log((() => 1).toString());
    ),
  )
  json_inspect(output, content=["() => 1"])
}

///|
test "Function.prototype.toString: loc.offset correct when prior astral char in comment" {
  // 𝒜 inside a block comment advances astral_count; the following arrow function
  // body must still start at the correct UTF-16 offset.
  let output = run_output(
    (
      #|/* 𝒜 */
      #|console.log((() => 1).toString());
    ),
  )
  json_inspect(output, content=["() => 1"])
}

///|
// Positive control: confirms %GeneratorPrototype%.next is writable and the singleton
// is shared — the patch IS live for sync generators, making the async isolation test below
// a genuine discriminator (not a vacuous pass).
test "monkey-patch on %GeneratorPrototype%.next intercepts sync generator iteration" {
  let output = run_output(
    (
      #|Object.getPrototypeOf(function*(){}.prototype).next = () => ({ value: 99, done: true });
      #|function* g() { yield 1; }
      #|console.log(g().next().value);
    ),
  )
  json_inspect(output, content=["99"])
}

///|
test "async function resolution is not affected by monkey-patching %GeneratorPrototype%.next" {
  let output = run_output_async(
    (
      #|Object.getPrototypeOf(function*(){}.prototype).next = () => ({ value: 99, done: true });
      #|async function f() { return 1; }
      #|f().then(v => console.log(v));
    ),
  )
  // Must resolve to 1, not 99 — internal async generator bypasses public prototype
  json_inspect(output, content=["1"])
}

///|
test "async functions and generators expose well-known symbol protocol hooks" {
  let output = run_output(
    (
      #|let AF = (async function(){}).constructor;
      #|console.log(Object.prototype.toString.call(AF.prototype));
      #|async function* ag() { yield 1; }
      #|let it = ag();
      #|console.log(typeof it[Symbol.asyncIterator]);
      #|console.log(it[Symbol.asyncIterator]() === it);
    ),
  )
  json_inspect(output, content=["[object AsyncFunction]", "function", "true"])
}

///|
test "AsyncGeneratorPrototype has correct Symbol.toStringTag" {
  let output = run_output(
    (
      #|async function* ag() {}
      #|let iter = ag();
      #|let proto = Object.getPrototypeOf(iter);
      #|let AsyncGenProto = Object.getPrototypeOf(proto);
      #|console.log(AsyncGenProto[Symbol.toStringTag]);
    ),
  )
  json_inspect(output, content=["AsyncGenerator"])
}

///|
test "AsyncGeneratorPrototype.constructor points to AsyncGeneratorFunction.prototype" {
  let output = run_output(
    (
      #|async function* g1() {}
      #|async function* g2() {}
      #|let AsyncGenerator = Object.getPrototypeOf(g1);
      #|let AsyncGeneratorProto = AsyncGenerator.prototype;
      #|console.log(AsyncGeneratorProto.constructor === AsyncGenerator);
      #|console.log(Object.getPrototypeOf(g1) === Object.getPrototypeOf(g2));
      #|console.log(AsyncGenerator[Symbol.toStringTag]);
    ),
  )
  json_inspect(output, content=["true", "true", "AsyncGeneratorFunction"])
}

///|
test "AsyncGeneratorFunction.prototype.prototype descriptor is configurable:true (§27.4.3.2)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|let AsyncGenerator = Object.getPrototypeOf(g);
      #|let d = Object.getOwnPropertyDescriptor(AsyncGenerator, 'prototype');
      #|console.log(d.writable);
      #|console.log(d.enumerable);
      #|console.log(d.configurable);
      #|let ctorDesc = Object.getOwnPropertyDescriptor(g.constructor, 'prototype');
      #|console.log(ctorDesc.configurable);
    ),
  )
  // agf_proto.prototype: writable=false, enumerable=false, configurable=true (§27.4.3.2)
  // async_gen_func_ctor.prototype: configurable=false (§27.4.2.2)
  json_inspect(output, content=["false", "false", "true", "false"])
}

///|
test "AsyncGeneratorPrototype own key order is constructor,next,return,throw (§27.6)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|let proto = Object.getPrototypeOf(g.prototype);
      #|console.log(Object.getOwnPropertyNames(proto).join(','));
    ),
  )
  json_inspect(output, content=["constructor,next,return,throw"])
}

///|
test "AsyncGeneratorFunction.prototype own key order is constructor,prototype (§27.4.3)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|let AsyncGenerator = Object.getPrototypeOf(g);
      #|console.log(Object.getOwnPropertyNames(AsyncGenerator).join(','));
    ),
  )
  json_inspect(output, content=["constructor,prototype"])
}

///|
test "AsyncGeneratorFunction [[Prototype]] is Function (§27.4.1)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|console.log(Object.getPrototypeOf(g.constructor) === Function);
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "Symbol.asyncIterator lives on %AsyncIteratorPrototype%, not %AsyncGeneratorPrototype% (§27.1.2)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|const agp = Object.getPrototypeOf(g.prototype);
      #|const aip = Object.getPrototypeOf(agp);
      #|console.log(Object.prototype.hasOwnProperty.call(agp, Symbol.asyncIterator));
      #|console.log(Object.prototype.hasOwnProperty.call(aip, Symbol.asyncIterator));
      #|console.log(typeof agp[Symbol.asyncIterator]);
    ),
  )
  json_inspect(output, content=["false", "true", "function"])
}

///|
test "AsyncGeneratorFunction constructor throws TypeError for Symbol body (§7.1.17)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|try {
      #|  g.constructor(Symbol());
      #|  console.log('no throw');
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "AsyncGeneratorFunction constructor coerces params before body (§20.2.1.1)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|let bodyCalled = false;
      #|const body = { toString() { bodyCalled = true; return ''; } };
      #|try {
      #|  g.constructor(Symbol(), body);
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|  console.log(bodyCalled);
      #|}
    ),
  )
  json_inspect(output, content=["true", "false"])
}

///|
test "AsyncGeneratorFunction constructor calls object toString for body (§7.1.17)" {
  let output = run_output(
    (
      #|async function* g() {}
      #|let called = false;
      #|const body = { toString() { called = true; return ''; } };
      #|const f = g.constructor(body);
      #|console.log(typeof f);
      #|console.log(called);
    ),
  )
  json_inspect(output, content=["function", "true"])
}

///|
test "async generator function name and length" {
  let output = run_output(
    (
      #|async function* simple(a, b) {}
      #|async function* def(a, b = 1, c) {}
      #|async function* rest(a, ...r) {}
      #|async function* destruct(a, ...[b]) {}
      #|async function* collision($rest, ...[x]) {}
      #|let expr = async function* named(a, b = 1) {};
      #|console.log(simple.name + ":" + simple.length);
      #|console.log(def.name + ":" + def.length);
      #|console.log(rest.name + ":" + rest.length);
      #|console.log(destruct.name + ":" + destruct.length);
      #|console.log(collision.name + ":" + collision.length);
      #|console.log(expr.name + ":" + expr.length);
      #|console.log(simple.bind(null).length);
      #|console.log(simple.bind(null, 1).length);
      #|let desc = Object.getOwnPropertyDescriptor(simple, "name");
      #|console.log(desc.writable + ":" + desc.enumerable + ":" + desc.configurable);
    ),
  )
  json_inspect(output, content=[
    "simple:2", "def:1", "rest:1", "destruct:1", "collision:1", "named:1", "2", "1",
    "false:false:true",
  ])
}

// ES262 §10.2.4 ExpectedArgumentCount: function `length` reports the
// count of parameters before the first one with a default initializer
// (or rest). Non-async siblings already handle this; PR #103
// (trailing-comma in non-arrow params) exposed that async function /
// method / arrow factories were still using the raw param count.

///|
test "async function length: default param stops count" {
  let src =
    #|console.log((async function (a, b = 39) {}).length);
    #|console.log((async function (a, b = 39,) {}).length);
    #|console.log((async function (a, b, c = 1) {}).length);
    #|console.log((async function (a, b, c) {}).length);
    #|console.log((async function () {}).length);
  let output = run_output(src)
  json_inspect(output, content=["1", "1", "2", "3", "0"])
}

///|
test "async function length: covers async-statement, arrow, methods" {
  let src =
    #|async function af(a, b = 1,) {}
    #|console.log(af.length);
    #|let arrow = async (a, b = 1,) => {};
    #|console.log(arrow.length);
    #|let obj = { async m(a, b = 1,) {} };
    #|console.log(obj.m.length);
    #|class C {
    #|  async m(a, b = 1,) {}
    #|  static async sm(a, b = 1,) {}
    #|}
    #|console.log(new C().m.length);
    #|console.log(C.sm.length);
  let output = run_output(src)
  json_inspect(output, content=["1", "1", "1", "1", "1"])
}

// ES262 §10.2.4 ExpectedArgumentCount: the count also stops at a
// FunctionRestParameter. Named rest is passed separately and not in the
// params array, so the original loop only checked `default_val`. But
// destructuring rest (`...[b]`) is represented in this codebase as both
// `rest_param = Some("$rest")` AND a synthetic Param pushed into `params`
// (parser/stmt.mbt:314, :353), so without an explicit rest-name check the
// loop overcounts.

///|
test "function length: destructuring rest halts count across factories" {
  let src =
    #|function f(a, ...[b]) {}
    #|console.log(f.length);
    #|function* g(a, ...[b]) {}
    #|console.log(g.length);
    #|const arrow = (a, ...[b]) => {};
    #|console.log(arrow.length);
    #|async function af(a, ...[b]) {}
    #|console.log(af.length);
  let output = run_output(src)
  json_inspect(output, content=["1", "1", "1", "1"])
}

///|
test "destructuring param name collision does not masquerade as rest" {
  let src =
    #|function f({a}, ...$0) {
    #|  console.log(a);
    #|  console.log($0.length);
    #|  console.log($0[0].b);
    #|}
    #|f({a: "first"}, {b: "second"}, {b: "third"});
  let output = run_output(src)
  json_inspect(output, content=["first", "2", "second"])
}

///|
test "function length: ordinary $rest before destructuring rest counts normally" {
  let src =
    #|function f($rest, ...[b]) {}
    #|console.log(f.length);
    #|function* g($rest, ...[b]) {}
    #|console.log(g.length);
    #|const arrow = ($rest, ...[b]) => {};
    #|console.log(arrow.length);
    #|async function af($rest, ...[b]) {}
    #|console.log(af.length);
    #|async function* ag($rest, ...[b]) {}
    #|console.log(ag.length);
    #|class C { constructor($rest, ...[b]) {} }
    #|console.log(C.length);
  let output = run_output(src)
  json_inspect(output, content=["1", "1", "1", "1", "1", "1"])
}

///|
test "dynamic function constructors accept destructuring rest" {
  let src =
    #|let f = new Function("a", "...[b]", "return a + ':' + b;");
    #|console.log(f("first", "second", "third"));
    #|let GF = (function*(){}).constructor;
    #|let g = new GF("a", "...[b]", "yield a + ':' + b;");
    #|console.log(g("first", "second", "third").next().value);
    #|let AF = (async function(){}).constructor;
    #|let af = new AF("a", "...[b]", "return a + ':' + b;");
    #|af("first", "second", "third").then(function(v) { console.log(v); });
  let output = run_output_async(src)
  json_inspect(output, content=["first:second", "first:second", "first:second"])
}

///|
test "class constructor accepts destructuring rest" {
  let src =
    #|class C {
    #|  constructor(a, ...[b]) { this.value = a + ':' + b; }
    #|}
    #|console.log(new C("first", "second", "third").value);
  let output = run_output(src)
  json_inspect(output, content=["first:second"])
}

///|
test "class constructor length: stops at first default" {
  let src =
    #|class A { constructor(a, b = 1) {} }
    #|console.log(A.length);
    #|class B { constructor(a, b, c = 1) {} }
    #|console.log(B.length);
    #|class C { constructor(a, b, c) {} }
    #|console.log(C.length);
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "3"])
}

// Function() constructor mirrors the same ExpectedArgumentCount logic
// when the source it parses uses default parameters.

///|
test "Function constructor length: stops at first default" {
  let src =
    #|console.log(new Function("a", "b=1", "").length);
    #|console.log(new Function("a", "b", "c=2", "").length);
    #|console.log(new Function("a", "b", "c", "").length);
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "3"])
}

// Engine-thrown error shape (agent-todo #13 + rebinding regression).
// Invariant: an engine-raised native error must always report a defined
// `.name` matching its error type, even when user code rebinds the native
// constructor. Spec-ideal: `name` lives on the prototype, not as an own
// property. When the prototype chain cannot be trusted (rebinding,
// missing binding), fall back to an own `name` property.

///|
test "engine TypeError: name on prototype, not own" {
  let src =
    #|try { null.x } catch(e) {
    #|  console.log(e.name);
    #|  console.log(Object.prototype.hasOwnProperty.call(e, "name"));
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError", "false"])
}

///|
test "engine TypeError survives constructor rebinding" {
  let src =
    #|TypeError = function() {};
    #|try { null.x } catch(e) {
    #|  console.log(e.name);
    #|  console.log(Object.prototype.hasOwnProperty.call(e, "name"));
    #|}
  let output = run_output(src)
  // After rebinding, native prototype is unreachable — fall back to own `name`.
  json_inspect(output, content=["TypeError", "true"])
}

///|
test "engine ReferenceError survives constructor rebinding" {
  let src =
    #|ReferenceError = function() {};
    #|try { undeclared_identifier } catch(e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["ReferenceError"])
}

///|
test "Promise.try rejection name survives constructor rebinding" {
  // Regression from PR #53: engine errors surfaced through Promise.try
  // must keep their name even when user rebinds TypeError.
  let src =
    #|TypeError = function() {};
    #|Promise.try(() => null.x).catch(e => {
    #|  console.log(e.name);
    #|});
  let output = run_output_async(src)
  json_inspect(output, content=["TypeError"])
}

///|
test "Promise.any AggregateError name reflects rebound constructor" {
  // Documents a separate code path (not fixed by PR #53): Promise.any
  // constructs its rejection via `interp.construct_value(aggregate_ctor, ...)`
  // where `aggregate_ctor` is resolved through `env.get("AggregateError")`.
  // Rebinding therefore leaks through — distinct from the `make_*_error_value`
  // path that PR #53 hardened. Proper fix needs intrinsic references
  // (agent-todo #15). Test pins current behavior.
  let src =
    #|AggregateError = function() {};
    #|Promise.any([Promise.reject(1), Promise.reject(2)]).catch(e => {
    #|  console.log(typeof e.name);
    #|});
  let output = run_output_async(src)
  json_inspect(output, content=["undefined"])
}

///|
test "engine error adversarial: proto rebound to name-matching object" {
  // Documents a known limitation of the heuristic fallback. An adversary
  // can set Foo.prototype.name = "TypeError" to bypass the own-name fallback;
  // the spec-correct fix is intrinsic references (agent-todo #15). Until then,
  // the test pins current behavior so an unrelated refactor can't silently
  // change it.
  let src =
    #|function Fake() {}
    #|Fake.prototype.name = "TypeError";
    #|TypeError = Fake;
    #|try { null.x } catch(e) {
    #|  console.log(e.name);
    #|  console.log(Object.prototype.hasOwnProperty.call(e, "name"));
    #|}
  let output = run_output(src)
  // Fallback skipped because Fake.prototype has own name "TypeError".
  // e.name is resolved via the (user-owned) prototype chain.
  json_inspect(output, content=["TypeError", "false"])
}

///|
/// Annex B §B.3.3.3: bare `function f` nested in a block inside eval must
/// skip the Annex B var-binding extension when a top-level `let f` would
/// conflict — no SyntaxError, no var binding created.
test "annex-b eval: skip extension when top-level let conflicts" {
  let src =
    #|(function() {
    #|  var threw = false;
    #|  try {
    #|    eval("let f = 123; { function f(){} } globalThis.__typ = typeof f;");
    #|  } catch (e) {
    #|    threw = true;
    #|    globalThis.__typ = "THROWN:" + e.name;
    #|  }
    #|  console.log(threw ? "threw" : "ok");
    #|  console.log(globalThis.__typ);
    #|})();
  let output = run_output_annex_b(src)
  json_inspect(output, content=["ok", "number"])
}

///|
/// Annex B §B.3.3.3 (no-skip-param): function parameter `f` exists, eval
/// contains `{function f(){}}`. Skip check passes (param not a lex binding
/// for eval). Before-block: `f` keeps param value. After-block: `f`
/// reassigned to the closure.
test "annex-b eval: reinit param binding on block-entry" {
  let src =
    #|(function(f) {
    #|  eval("globalThis.__init = f; { function f(){} } globalThis.__after = typeof f;");
    #|})(123);
    #|console.log(globalThis.__init);
    #|console.log(globalThis.__after);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["123", "function"])
}

///|
/// Annex B §B.3.3.3: basic block-level function decl in eval with no
/// enclosing lex conflict. Var binding created at hoist time (undefined),
/// reassigned on block entry.
test "annex-b eval: basic block function hoists as var, reinits on block entry" {
  let src =
    #|(function() {
    #|  eval(`
    #|    try { globalThis.__init = f; } catch(e) { globalThis.__init = "threw:"+e.name; }
    #|    { function f(){} }
    #|    globalThis.__after = typeof f;
    #|  `);
    #|})();
    #|console.log(globalThis.__init);
    #|console.log(globalThis.__after);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["undefined", "function"])
}

///|
/// §19.2.1.3 step 5.d: walk from fresh eval lex env (not caller env) up to
/// var env. For indirect eval nested inside a block with `let`, the walk
/// starts from the eval's new env (empty) rooted at global — no
/// false-positive SyntaxError.
test "annex-b eval: indirect eval does not false-positive on caller block let" {
  let src =
    #|var outerErr = null;
    #|try {
    #|  {
    #|    let x = 1;
    #|    {
    #|      (0, eval)("var x = 2;");
    #|    }
    #|  }
    #|} catch (e) {
    #|  outerErr = e.name;
    #|}
    #|console.log(outerErr);
    #|console.log(typeof x);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["null", "number"])
}

///|
/// §B.3.2.1 step ii: skip the Annex B extension when F is a formal
/// parameter of the enclosing function. Without this check, a block-level
/// `function f(){}` would overwrite the param `f` — matching eval's
/// §B.3.2.3 behavior (which the shared walker implements), but violating
/// function-body semantics. test262 fixture
/// annexB/language/function-code/block-decl-func-skip-param.js.
test "annex-b: function-body skip when candidate equals param name" {
  let src =
    #|var init, after;
    #|(function(f) {
    #|  init = f;
    #|  { function f() {} }
    #|  after = f;
    #|})(123);
    #|console.log(init);
    #|console.log(after);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["123", "123"])
}

///|
/// §B.3.2.1 + FunctionDeclarationInstantiation step 22.f: "arguments" is
/// appended to parameterNames when the arguments object is materialized,
/// so a block-level `function arguments(){}` must not overwrite the
/// enclosing function's arguments object. test262 fixture
/// annexB/language/function-code/block-decl-func-skip-arguments.js.
test "annex-b: function-body skip when candidate equals arguments" {
  let src =
    #|(function() {
    #|  var before = arguments.toString();
    #|  { function arguments() {} }
    #|  var after = arguments.toString();
    #|  console.log(before);
    #|  console.log(after);
    #|})();
  let output = run_output_annex_b(src)
  json_inspect(output, content=["[object Arguments]", "[object Arguments]"])
}

///|
/// §B.3.2.1: Annex B block-level function hoisting into a function body's
/// var scope must skip when the candidate name conflicts with a
/// lexically-declared name in an enclosing block of the same function.
/// Without the syntactic walk, `hoist_block_func_declarations` blindly
/// creates a var slot for `g` at function scope — visible after the block
/// ends. Per §B.3.2.1 the extension must be skipped and `g` stays
/// undeclared at function scope.
test "annex-b: function-body skip when enclosing block let conflicts" {
  let src =
    #|function foo() {
    #|  {
    #|    let g = "lex";
    #|    { function g(){} }
    #|  }
    #|  return typeof g;
    #|}
    #|console.log(foo());
  let output = run_output_annex_b(src)
  json_inspect(output, content=["undefined"])
}

///|
/// §B.3.4: `if (cond) FunctionDeclaration` is treated as if the body were a
/// Block containing the FunctionDeclaration. Inside eval, the Annex B hoist
/// must therefore promote `f` to the enclosing var env — so `f` remains
/// visible in the caller after eval returns. Prior bug: IfStmt forwarded
/// `in_block~` (false at the eval top level) through to the inner FuncDecl,
/// so the Annex B walk skipped it and no var was created in the enclosing
/// scope.
test "annex-b eval: if-clause FunctionDeclaration hoists via B.3.4" {
  let src =
    #|(function() {
    #|  eval("if (true) function f(){}");
    #|  globalThis.__typ = typeof f;
    #|})();
    #|console.log(globalThis.__typ);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["function"])
}

///|
/// §B.3.3.3 step ii + §8.2.10: a FunctionDeclaration inside `if (...)` is
/// in a block-like context (per §B.3.4 it parses as `{ FunctionDeclaration }`).
/// At the eval top level, the FuncDecl in the if-branch must NOT count as a
/// var-declared name for the lex/var conflict check — otherwise `let f =
/// 123; if (true) function f() {}` raises a spurious "Identifier 'f' has
/// already been declared". Cohort:
/// `annexB/language/eval-code/direct/func-if-{decl,stmt}-*-eval-func-skip-early-err.js`
/// (54 non-strict failures pre-fix).
test "annex-b eval: if-branch FunctionDeclaration ignored by lex/var conflict check" {
  let src =
    #|var init, after;
    #|(function() {
    #|  eval(
    #|    "let f = 123;" +
    #|    "init = f;" +
    #|    "if (true) function f() {} else function _f() {};" +
    #|    "after = f;"
    #|  );
    #|}());
    #|console.log(init, after);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["123 123"])
}

///|
/// Same shape, `const f` (no initializer-overwrite issue) — the early-error
/// check must skip the if-branch FuncDecl whether the outer lexical is
/// `let`, `const`, or `class`.
test "annex-b eval: const conflicts with if-branch FunctionDeclaration are skipped" {
  let src =
    #|var observed;
    #|(function() {
    #|  eval(
    #|    "const f = 'outer';" +
    #|    "if (true) function f() {};" +
    #|    "observed = f;"
    #|  );
    #|}());
    #|console.log(observed);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["outer"])
}

///|
/// §8.2.10 + §B.3.4: a `try { function f(){} }` block sits at the eval top
/// level under control-flow. Its `function f` must be hidden from the
/// surrounding StatementList's VarDeclaredNames so a sibling `let f` does
/// not spuriously collide. Defensive coverage: confirms the
/// `collect_block_var_decl_names_from_stmt` fix flowed through TryCatchStmt
/// too, not only IfStmt.
test "annex-b eval: try-block FunctionDeclaration ignored by lex/var conflict check" {
  let src =
    #|var observed;
    #|(function() {
    #|  eval(
    #|    "let f = 1;" +
    #|    "try { function f() {} } catch (e) {};" +
    #|    "observed = f;"
    #|  );
    #|}());
    #|console.log(observed);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["1"])
}

///|
/// Confirmation that the top-level FunctionDeclaration path still works:
/// `let f` collides with a SIBLING top-level `function f` (NOT under any
/// nested control flow), which is a real var/lex conflict.
test "annex-b eval: top-level let f + top-level function f still throws" {
  let display = run_error_display(
    (
      #|eval("let f = 1; function f() {}");
    ),
  )
  inspect(
    display,
    content="SyntaxError: Identifier 'f' has already been declared",
  )
}

///|
/// Codex-found gap (P2): `collect_eval_var_names_from_stmt` walks the eval
/// source up through any enclosing caller-scope `let`/`const`/`class`
/// bindings to check the var/lex conflict. The walker's IfStmt arm already
/// used `in_block=true`, but Try/Switch/While/For arms still mirrored
/// caller's `in_block`. The cohort-canonical fixture only covers `if`, so
/// these companion tests pin try/switch and ensure the walker fix doesn't
/// regress when the FuncDecl lives in an alternate control-flow body.
test "annex-b eval: caller let f + nested-eval try-block function f is skipped" {
  let src =
    #|var observed;
    #|(function() {
    #|  let f;
    #|  eval(
    #|    "try { function f() {} } catch (e) {};" +
    #|    "observed = typeof f;"
    #|  );
    #|}());
    #|console.log(observed);
  let output = run_output_annex_b(src)
  // Outer `let f` is in caller TDZ at observation time, but the eval body
  // has no top-level binding for `f` (Annex B extension was skipped), so
  // `typeof f` reads the outer slot via the var-environment chain → "undefined".
  json_inspect(output, content=["undefined"])
}

///|
/// Companion to the try-block test — switch-case is also a §B.3.4 block-like
/// context. `case 0: function f(){}` must not leak `f` into VarDeclaredNames.
test "annex-b eval: caller let f + nested-eval switch-case function f is skipped" {
  let src =
    #|var observed;
    #|(function() {
    #|  let f;
    #|  eval(
    #|    "switch (0) { case 0: function f() {} };" +
    #|    "observed = typeof f;"
    #|  );
    #|}());
    #|console.log(observed);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["undefined"])
}

///|
/// Codex-found gap (P1): `FuncDeclExt` (FuncDecl with default/rest/destructured
/// params) shared the same unconditional `env.assign` bug as plain `FuncDecl`.
/// The cohort-canonical fixture uses zero-arg FuncDecls; this test pins the
/// param-bearing flavor so a regression would be caught locally.
test "annex-b eval: if-branch FuncDeclExt (default-param) ignored by conflict check" {
  let src =
    #|var observed;
    #|(function() {
    #|  eval(
    #|    "let f = 7;" +
    #|    "if (true) function f(a = 0) {} else function _f() {};" +
    #|    "observed = f;"
    #|  );
    #|}());
    #|console.log(observed);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["7"])
}

///|
/// Self-review follow-up (PR #119): pin the LabeledStmt semantics in
/// `collect_eval_var_names_from_stmt`. Per ES262 §B.3.2 + §B.3.4, a labeled
/// FunctionDeclaration at eval script top participates in
/// `TopLevelVarDeclaredNames`, so it DOES collide with a sibling `let` —
/// this is the one §B.3.4 case where the FuncDecl is NOT block-scoped. The
/// walker mirrors the caller's `in_block` flag (rather than forcing
/// `=true`) precisely to keep this collision detectable.
///
/// Companion to the if-branch / try-block / switch-case tests above, which
/// assert the OPPOSITE direction (FuncDecl hidden, no collision).
test "annex-b eval: labeled function at eval top still conflicts with sibling let" {
  let display = run_error_display(
    (
      #|eval("label: function f() {}; let f = 1");
    ),
  )
  inspect(
    display,
    content="SyntaxError: Identifier 'f' has already been declared",
  )
}

///|
/// Self-review follow-up (PR #119): the `Some(_) => ()` no-op branch in
/// `bind_function_decl_value` was originally exercised by `let f` and
/// `const f` conflicts only. Class declarations bind as `LetBinding` in
/// this engine (see exec_stmt.mbt `ClassDecl` arm), so this test
/// completes the §B.3.3.3 conflict-skip coverage across all three lex
/// binding kinds documented in the helper's docstring (let / const / class).
test "annex-b eval: class conflicts with if-branch FunctionDeclaration are skipped" {
  let src =
    #|var observed;
    #|(function() {
    #|  eval(
    #|    "class f {};" +
    #|    "if (true) function f() {};" +
    #|    "observed = typeof f;"
    #|  );
    #|}());
    #|console.log(observed);
  let output = run_output_annex_b(src)
  // The Annex B var-promotion is suppressed → outer `class f` stays bound,
  // and `typeof class` is "function".
  json_inspect(output, content=["function"])
}

///|
/// §B.3.3.3 + LabeledStmt: in sloppy mode, `{ label: function f(){} }`
/// should reinit the outer `function f` var binding on block entry.
/// `hoist_block_func_declarations` recurses through LabeledStmt but has no
/// FuncDecl arm at the labeled level, so the outer `f` never gets
/// `annex_b_hoisted` tagged. Prior to this fix, the exec-time reinit
/// checked only `annex_b_hoisted`, regressing the case that previously
/// worked via `kind == VarBinding`. The reinit gate must allow VarBindings
/// regardless of the tag, because VarBindings are mutable anyway.
test "annex-b: labeled block function reinits outer var (no eval)" {
  let src =
    #|function f() { return 1; }
    #|{ label: function f() { return 2; } }
    #|console.log(f());
  let output = run_output_annex_b(src)
  json_inspect(output, content=["2"])
}

///|
/// §B.3.3.3 step ii: a block-level `function f(){}` in sloppy eval must
/// reinit the enclosing function's parameter `f`, regardless of which
/// runtime entry point created the function call — ordinary call, `new`
/// construct, and generator setup all bind parameters the same way for
/// Annex B purposes. Prior bug: only `call.mbt` migrated to
/// `def_parameter`; constructor/generator sites still used
/// `def(..., LetBinding)`, leaving `is_parameter=false` so
/// `tag_annex_b_hoisted` skipped them — block-entry reinit never ran.
test "annex-b eval: reinit param in constructor call" {
  // Must use a sloppy-mode function constructor, not `class`, since class
  // bodies are strict by default and Annex B is disabled in strict mode.
  let src =
    #|function C(f) {
    #|  eval("globalThis.__init = f; { function f(){} } globalThis.__after = typeof f;");
    #|}
    #|new C(123);
    #|console.log(globalThis.__init);
    #|console.log(globalThis.__after);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["123", "function"])
}

///|
/// §B.3.3.3 skip check must see names from comma-separated declarations.
/// `let f = 1, g = 2;` is parsed as `StmtList([VarDecl, VarDecl])`, so the
/// lex-name collector needs to descend into StmtList — otherwise the eval
/// top-level `let f` stays invisible to `annex_b_candidate_conflicts` and
/// a block-level `function f(){}` gets incorrectly hoisted into the outer
/// var env, overwriting the caller's binding. Prior bug: `add_stmt_lex_names`
/// had no StmtList arm, so `eval("let f=1,g=2; { function f(){} }")` leaked
/// `f` back to the caller.
test "annex-b eval: skip extension when comma-let declares conflicting name" {
  let src =
    #|var f = "outer";
    #|eval("let f=1,g=2; { function f(){} }");
    #|console.log(f);
    #|console.log(typeof f);
  let output = run_output_annex_b(src)
  json_inspect(output, content=["outer", "string"])
}

///|
/// §B.3.4: a pre-existing `const` binding in the enclosing var env must
/// suppress the Annex B extension — replacing `function f(){}` with `var f`
/// would be an early error against the const, so the hoist must skip. Prior
/// bug: `tag_annex_b_hoisted` marked any existing binding, letting the later
/// block-entry reinit overwrite the const via a direct `binding.value = ...`
/// write that bypasses `Environment::assign` const enforcement.
test "annex-b eval: skip extension when enclosing const conflicts" {
  let src =
    #|(function() {
    #|  const f = 1;
    #|  eval("{ function f(){} }");
    #|  console.log(f);
    #|  console.log(typeof f);
    #|})();
  let output = run_output_annex_b(src)
  json_inspect(output, content=["1", "number"])
}

///|
/// §10.2.11 param-env / body-env split: a body-level `let arguments`
/// shadows the `arguments` object installed at the function's param scope.
/// Pre-split: `arguments` is a `VarBinding` on the single func_env, and the
/// body's `let arguments` hoist either throws (binding-exists) or collides
/// at runtime. Post-split: `arguments` lives on param_env, `let arguments`
/// lives on body_env → no collision, body sees "local".
test "§10.2.11: body let arguments shadows param-scope arguments object" {
  let src =
    #|function f(a = 1) {
    #|  let arguments = "local";
    #|  return arguments;
    #|}
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["local"])
}

///|
/// §10.2.11 canonical test262 shape
/// (language/eval-code/direct/arrow-fn-body-cntns-arguments-*).
/// Direct eval in a param default declares `var arguments = 'param'` in
/// the param scope; a later arrow default `q = () => arguments` closes
/// over the same param scope. The body then has `let arguments = "local"`,
/// which is a distinct binding in body_env. q() must see "param", body
/// must see "local".
test "§10.2.11: arrow default eval-var-arguments + body let arguments" {
  let src =
    #|var log = [];
    #|const f = (p = eval("var arguments = 'param'"), q = () => arguments) => {
    #|  let arguments = "local";
    #|  log.push(arguments);
    #|  log.push(q());
    #|};
    #|f();
    #|console.log(log[0]);
    #|console.log(log[1]);
  let output = run_output(src)
  json_inspect(output, content=["local", "param"])
}

///|
/// §10.2.11 step 26 gate: plain-rest Ext has HasParameterExpressions=false,
/// so the param-env / body-env split must NOT fire — otherwise a body-level
/// `var rest` hoists to a distinct binding instead of reusing the param,
/// changing observable behavior. Codex-flagged during PR review.
test "§10.2.11: plain-rest Ext stays single-env (body var reuses param)" {
  let src =
    #|function f(...rest) {
    #|  var rest;
    #|  return rest;
    #|}
    #|console.log(JSON.stringify(f(1, 2, 3)));
  let output = run_output(src)
  json_inspect(output, content=["[1,2,3]"])
}

///|
/// §10.2.11 `ContainsExpression` precision: a destructuring pattern
/// WITHOUT any nested Initializer or computed key has no expression,
/// so no param/body env split. Otherwise `function f({a}) { var a;
/// return a }` wrongly hoists `var a` to body_env and shadows the
/// destructured parameter, returning undefined instead of 1. Codex P1
/// finding, post-merge review.
test "§10.2.11: plain-destructure Ext stays single-env (body var reuses param)" {
  let obj_src =
    #|function f({a}) {
    #|  var a;
    #|  return a;
    #|}
    #|console.log(f({a: 1}));
  let arr_src =
    #|function g([a]) {
    #|  var a;
    #|  return a;
    #|}
    #|console.log(g([2]));
  let out1 = run_output(obj_src)
  let out2 = run_output(arr_src)
  json_inspect(out1, content=["1"])
  json_inspect(out2, content=["2"])
}

///|
/// §10.2.11: a named function expression's self-binding must not
/// shadow a same-named parameter. `function f(f = 1) { return f }`
/// returns 1 (the param), not the callee. In the split path the
/// self-binding would go on body_env while the param sits on
/// param_env, so the check "don't re-bind if name already exists"
/// needs to consult BOTH envs. Codex P1 finding, post-merge review.
test "§10.2.11: function-name self-binding yields to param of same name" {
  let src =
    #|var g = function f(f = 1) { return f; };
    #|console.log(g());
    #|console.log(g(7));
  let output = run_output(src)
  json_inspect(output, content=["1", "7"])
}

///|
/// §15.2.5 + §10.2.11: a named function expression's self-name must be
/// reachable from default-expression closures. Defaults evaluate in
/// param_env, so arrows created inside defaults capture param_env; if
/// the self-name only appears on body_env (child of param_env), the
/// capture has no path to it. Per §15.2.5 the spec installs the name
/// on a dedicated funcEnv BETWEEN the outer closure and the call's
/// param_env, which our implementation mirrors. Codex P2 finding.
test "§10.2.11: named function expression self-name visible to default closures" {
  let src =
    #|var g = function f(a = () => f) { return a(); };
    #|console.log(g() === g);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// §15.2.5 scope of the self-name binding: ONLY named FunctionExpression
/// gets it. MethodDefinition (object method, class method, generator
/// method, getter, setter) does NOT — methods have no `[[FunctionName]]`
/// env entry. The parser still puts the shorthand key on the FuncData's
/// `name` for `.name` display, but call-time must not create the
/// funcEnv wrapper. Codex P1 regression follow-up to the §15.2.5 fix.
test "§15.2.5: object shorthand method has no self-name binding" {
  let src =
    #|try {
    #|  console.log(({ m(a = () => m) { let m = 1; return a(); } }).m());
    #|} catch (e) {
    #|  console.log(e.name + ': ' + e.message);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["ReferenceError: m is not defined"])
}

///|
test "§15.2.5: simple methods have no self-name binding" {
  let src =
    #|console.log(({ m() { return typeof m; } }).m());
    #|console.log((new class { m() { return typeof m; } }).m());
  let output = run_output(src)
  json_inspect(output, content=["undefined", "undefined"])
}

///|
/// Class methods mirror object-method semantics: no self-name binding.
test "§15.2.5: class method has no self-name binding" {
  let src =
    #|try {
    #|  console.log((new class { m(a = () => m) { let m = 1; return a(); } }).m());
    #|} catch (e) {
    #|  console.log(e.name + ': ' + e.message);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["ReferenceError: m is not defined"])
}

///|
/// Counterpart: `key: function name() {}` IS a FunctionExpression (not
/// method shorthand), so the self-name binding DOES apply. Regression
/// guard: stripping has_name_binding on all prop values would break
/// this case.
test "§15.2.5: `key: function name() {}` keeps named-FE self binding" {
  let src =
    #|var o = { f: function foo() { return foo; } };
    #|console.log(o.f() === o.f);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// §10.2.11: implicit super() must apply the same param-env / body-env
/// split as a direct call to the parent constructor. Calling a parent
/// ctor through `class D extends B {}` (no own constructor) used to
/// skip the split and let `var x` hoist into the param env, where a
/// default's arrow captured it. Both direct `new B()` and implicit
/// `new D()` must throw ReferenceError for the same reason. Codex P1.
test "§10.2.11: implicit super() splits body env under HasParameterExpressions" {
  let src =
    #|class B { constructor(a = 1, q = () => x) { var x = 'b'; this.v = q(); } }
    #|class D extends B {}
    #|try {
    #|  new D();
    #|  console.log('no throw');
    #|} catch (e) {
    #|  console.log(e.name + ': ' + e.message);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["ReferenceError: x is not defined"])
}

///|
/// §10.2.11: class constructor default expressions must see `arguments`.
/// Regression: previously the `arguments` binding was installed AFTER
/// the parameter/default loop, so `constructor(a = arguments.length)`
/// threw `ReferenceError: arguments is not defined`.
test "§10.2.11: class constructor default expressions see arguments" {
  let src =
    #|class C { constructor(a = arguments.length) { this.a = a } }
    #|console.log(new C(undefined, 2, 3).a);
  let output = run_output(src)
  json_inspect(output, content=["3"])
}

///|
/// §10.2.11: same ordering requirement applies to the implicit-super
/// path where a derived class calls `super()` and the parent's
/// constructor defaults evaluate in super_env. `arguments` must be in
/// scope before the super ctor's param defaults fire.
test "§10.2.11: implicit super() ctor default expressions see arguments" {
  let src =
    #|class B { constructor(a = arguments.length) { this.a = a } }
    #|class D extends B {}
    #|console.log(new D(undefined, 2, 3).a);
  let output = run_output(src)
  json_inspect(output, content=["3"])
}

///|
/// §10.2.11: param-scope eval-var visible to an arrow default closure,
/// and body's `let` of the same name creates a distinct binding. Like
/// the canonical test but without the `arguments` special name, to
/// isolate the env-split logic from the arguments-object machinery.
test "§10.2.11: param-scope eval-var captured by arrow default closure" {
  let src =
    #|var log = [];
    #|function f(p = eval("var z = 'from-eval'"), q = () => z) {
    #|  let z = "body";
    #|  log.push(z);
    #|  log.push(q());
    #|}
    #|f();
    #|console.log(log[0]);
    #|console.log(log[1]);
  let output = run_output(src)
  json_inspect(output, content=["body", "from-eval"])
}

///|
/// §19.2.1.3 step 5.d probe (#A.6). Canonical test262 shape from
/// language/eval-code/direct/func-decl-fn-body-cntns-arguments-var-bind-
/// declare-arguments.js: a non-arrow function whose parameter default
/// runs `eval("var arguments")` while the body also declares
/// `var arguments`. Spec mandates SyntaxError at call time. Purpose of
/// this probe: determine whether this early-error is decidable under
/// our current 2-env model (param_env + body_env) without lifting to
/// the full 3-env (param / varEnv / lexEnv) split.
test "§19.2.1.3 probe: eval(var arguments) in default + body var arguments throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f(p = eval("var arguments")) {
        #|  var arguments;
        #|}
        #|f();
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'arguments' has already been declared",
  )
}

///|
/// §19.2.1.3 step 5.d probe (#A.6) — func-decl shape. Maps to test262
/// template default/func-decl/fn-body-cntns-arguments-func-decl.template.
/// Spec anchor and expected behavior identical to the var-bind probe;
/// only the body-level declaration kind differs (body has a function
/// declaration named `arguments` rather than a var). If this probe fails
/// with the same "no error raised" signature as the var-bind probe,
/// all three shapes share a single root cause (body decls invisible
/// to the step 5.d walk at default-evaluation time).
test "§19.2.1.3 probe: eval(var arguments) in default + body function arguments() throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f(p = eval("var arguments")) {
        #|  function arguments() {}
        #|}
        #|f();
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'arguments' has already been declared",
  )
}

///|
/// §19.2.1.3 step 5.d probe (#A.6) — lex-bind shape. Maps to test262
/// template default/func-decl/fn-body-cntns-arguments-lex-bind.template.
/// Body declares `let arguments` (lexical binding) instead of var.
/// In the spec 3-env model this lands on lexEnv (not varEnv), and the
/// walk from eval's lexEnv up to varEnv exclusive must observe it.
/// In our 2-env collapse, body let/const hoist to body_env alongside
/// vars, so if the fix surfaces body decls before defaults evaluate,
/// all three shapes flip green together.
test "§19.2.1.3 probe: eval(var arguments) in default + body let arguments throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f(p = eval("var arguments")) {
        #|  let arguments;
        #|}
        #|f();
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'arguments' has already been declared",
  )
}

///|
/// §19.2.1.3 probe (#A.6) — empty-body shape (no-pre-existing-arguments-
/// bindings cohort, 22 non-arrow test262 fails). Proves the rule fires on
/// eval's intent alone, not on body-decl visibility.
test "§19.2.1.3 probe: eval(var arguments) in default + empty body throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f(p = eval("var arguments")) {}
        #|f();
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'arguments' has already been declared",
  )
}

///|
/// §19.2.1.3 probe (#A.6) — preceding-parameter shape. `arguments` is an
/// explicit PARAMETER declared before the eval-containing default. Covers
/// preceding-parameter-is-named-arguments cohort (~10 non-arrow fails).
test "§19.2.1.3 probe: preceding arguments param + eval(var arguments) in later default throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f(arguments, p = eval("var arguments")) {}
        #|f();
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'arguments' has already been declared",
  )
}

///|
/// §19.2.1.3 probe (#A.6) — following-parameter shape. `arguments` is an
/// explicit PARAMETER declared after the eval-containing default. Covers
/// following-parameter-is-named-arguments cohort (~8 non-arrow fails).
test "§19.2.1.3 probe: eval(var arguments) in default + following arguments param throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f(p = eval("var arguments"), arguments) {}
        #|f();
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'arguments' has already been declared",
  )
}

///|
/// §19.2.1.3 probe (#A.6) — following-parameter conflicts are rejected
/// during EvalDeclarationInstantiation, before the eval body can run.
test "§19.2.1.3 probe: eval(var arguments) with following param rejects before side effects" {
  let src =
    #|var log = [];
    #|function f(p = eval("log.push('ran'); var arguments"), arguments) {}
    #|try { f(); } catch (e) { console.log(e.name + ": " + e.message); }
    #|console.log(log.length);
  let output = run_output(src)
  json_inspect(output, content=[
    "SyntaxError: Identifier 'arguments' has already been declared", "0",
  ])
}

///|
/// §19.2.1.3 probe (#A.6) — direct eval in a non-arrow default cannot
/// var-declare a formal parameter name, not just the special `arguments` name.
test "§19.2.1.3 probe: eval(var param) in default throws SyntaxError" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      (
        #|function f(a, p = eval("var a = 2")) { return a; }
        #|f(1);
      ),
    )
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected"
  }
  expect_error_message(
    err_msg, "SyntaxError: Identifier 'a' has already been declared",
  )
}

///|
/// §19.2.1.3 negative regression (#A.6) — arrow variant must NOT throw.
/// Arrows have no `arguments` binding; eval's var lands in an empty scope.
/// Protects the 86 currently-passing arrow test262 tests.
test "§19.2.1.3 regression: arrow with eval(var arguments) in default runs normally" {
  let src =
    #|const f = (p = eval("var arguments")) => {
    #|  let arguments = "ok";
    #|  return arguments;
    #|};
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["ok"])
}

///|
/// §19.2.1.3 negative regression (#A.6) — body eval of `var arguments`
/// (not param-default) must NOT throw. Confirms the signal is strictly
/// scoped to parameter-default evaluation.
test "§19.2.1.3 regression: body eval(var arguments) in non-arrow runs normally" {
  let src =
    #|function f() {
    #|  eval("var arguments = 42");
    #|  return typeof arguments;
    #|}
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["number"])
}

///|
/// §19.2.1.3 negative regression (#A.6) — eval declaring a non-`arguments`
/// var must NOT throw, even in non-arrow param default. Confirms the gate
/// is `arguments`-specific, not a generic eval-in-default ban. (Only
/// asserts non-throw; observable value of the body's `x` differs from
/// spec under our 2-env collapse — see agent-todo item 7.)
test "§19.2.1.3 regression: eval(var x) in default of non-arrow does not throw" {
  let src =
    #|function f(p = eval("var x = 1")) {}
    #|f();
    #|console.log("ok");
  let output = run_output(src)
  json_inspect(output, content=["ok"])
}

///|
/// §19.2.1.3 negative regression (#A.6) — indirect eval (comma-expr form)
/// must NOT throw. Indirect eval uses global var scope, not caller's.
/// Our gate is `direct`-only; this protects that invariant.
test "§19.2.1.3 regression: indirect eval(var arguments) in default runs normally" {
  let src =
    #|function f(p = (0, eval)("var arguments")) {
    #|  return typeof p;
    #|}
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["undefined"])
}

///|
/// §20.1.2.24 step 1 — RequireObjectCoercible: null throws TypeError
test "Object.setPrototypeOf(null) throws TypeError" {
  let src =
    #|try {
    #|  Object.setPrototypeOf(null);
    #|} catch(e) {
    #|  console.log(e instanceof TypeError);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// §20.1.2.24 step 1 — RequireObjectCoercible: undefined throws TypeError
test "Object.setPrototypeOf(undefined) throws TypeError" {
  let src =
    #|try {
    #|  Object.setPrototypeOf(undefined);
    #|} catch(e) {
    #|  console.log(e instanceof TypeError);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// §20.1.2.24 step 3 — primitive (non-null/undefined) is returned unchanged
test "Object.setPrototypeOf(42, null) returns 42" {
  let src =
    #|console.log(Object.setPrototypeOf(42, null));
  let output = run_output(src)
  json_inspect(output, content=["42"])
}

///|
/// §20.1.2.24 normal case — object with null proto does not throw
test "Object.setPrototypeOf({}, null) does not throw" {
  let src =
    #|try {
    #|  Object.setPrototypeOf({}, null);
    #|  console.log("ok");
    #|} catch(e) {
    #|  console.log("threw: " + e);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["ok"])
}

///|
/// §19.2.1.3 negative regression (#A.6) — a nested non-arrow IIFE in a
/// default whose body contains `eval("var arguments")` must NOT throw
/// (the IIFE's eval runs in the IIFE's own var scope, not f's). Proves
/// the signal resets on every function entry. Without reset-on-entry,
/// the IIFE body would inherit f's default-eval-in-progress state and
/// false-fire — the bug the self-review caught.
test "§19.2.1.3 regression: nested IIFE with eval(var arguments) in f's default runs normally" {
  let src =
    #|function f(p = (function() { eval("var arguments"); return 1; })()) {
    #|  return p;
    #|}
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["1"])
}

///|
/// §19.2.1.3 negative regression (#A.6) — baseline check that nested
/// arrow invocations in defaults don't accidentally trigger the gate
/// for unrelated reasons. No eval involved.
test "§19.2.1.3 regression: nested arrow invocation in default runs normally" {
  let src =
    #|function f(p = (() => 1)()) { return p; }
    #|console.log(f());
  let output = run_output(src)
  json_inspect(output, content=["1"])
}

///|
/// §15.4.5 MethodDefinitionEvaluation: object-literal shorthand methods
/// have no [[Construct]] internal method and must throw TypeError on `new`.
test "§15.4.5: new obj.method() throws TypeError" {
  let output = run_output(
    (
      #|var obj = { m: function() {} };
      #|try {
      #|  new obj.m();
      #|  console.log("no throw");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  // Regular function expression used as property value is still a constructor
  json_inspect(output, content=["no throw"])
}

///|
test "§15.4.5: new ({method() {}}).method() throws TypeError" {
  let output = run_output(
    (
      #|var obj = { m() {} };
      #|try {
      #|  new obj.m();
      #|  console.log("no throw");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "§15.4.5: method shorthand normal call still works" {
  // Regression guard: calling a method shorthand normally must succeed
  let output = run_output(
    (
      #|var obj = {
      #|  m() { return 42; }
      #|};
      #|console.log(obj.m());
    ),
  )
  json_inspect(output, content=["42"])
}

///|
test "§15.4.5: new (function() {}) still works as constructor" {
  // Regression guard: normal function expressions are still constructors
  let output = run_output(
    (
      #|function Ctor() { this.x = 1; }
      #|var o = new Ctor();
      #|console.log(o.x);
    ),
  )
  json_inspect(output, content=["1"])
}

///|
test "§15.4.5: arrow functions still throw on new (regression guard)" {
  // Arrow functions must remain non-constructable
  let output = run_output(
    (
      #|try {
      #|  new (() => {})();
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
/// §10.5.13 ProxyExoticObject [[Construct]]: when the proxy target is a
/// method shorthand (non-constructor), `new Proxy(target, {})()` must throw
/// TypeError. The IsConstructor check on the target runs before any trap
/// dispatch — a proxy cannot resurrect constructability that the target
/// lacks. Codex P1 regression guard for PR #71.
test "§10.5.13: new Proxy(methodShorthand, {})() throws TypeError" {
  let output = run_output(
    (
      #|var obj = { m() {} };
      #|try {
      #|  new (new Proxy(obj.m, {}))();
      #|  console.log("no throw");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
/// §10.5.13 regression: arrows behind a Proxy are still non-constructable.
test "§10.5.13: new Proxy(arrow, {})() throws TypeError" {
  let output = run_output(
    (
      #|try {
      #|  new (new Proxy(() => {}, {}))();
      #|  console.log("no throw");
      #|} catch(e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
/// §10.5.13 regression: a normal function wrapped in a Proxy stays
/// constructable. This asserts the IsConstructor check is correctly
/// narrow — it only rejects non-constructors, not "any callable".
test "§10.5.13: new Proxy(function, {})() still works" {
  let output = run_output(
    (
      #|function Ctor() { this.x = 7; }
      #|var o = new (new Proxy(Ctor, {}))();
      #|console.log(o.x);
    ),
  )
  json_inspect(output, content=["7"])
}

// ====== OrdinaryHasInstance: non-object prototype throws TypeError ======

///|
test "instanceof throws TypeError when prototype is a string" {
  let mut err_msg = ""
  try {
    let _ = run_js("function F() {} F.prototype = \"\"; [] instanceof F")
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "TypeError: Function has non-object prototype in instanceof check",
  )
}

///|
test "instanceof throws TypeError when prototype is a number" {
  let mut err_msg = ""
  try {
    let _ = run_js("function F() {} F.prototype = 42; [] instanceof F")
  } catch {
    @runtime.JsException(val) => err_msg = error_display(val)
    _ => err_msg = "unexpected error"
  }
  expect_error_message(
    err_msg, "TypeError: Function has non-object prototype in instanceof check",
  )
}

///|
test "instanceof does not throw when prototype is a normal object" {
  let (_, result) = run_js("function F() {} [] instanceof F")
  expect_result(result, "false")
}

///|
/// OrdinaryHasInstance step 3 (O not Object → return false) precedes step 5
/// (prototype not Object → TypeError). A primitive LHS must return false even
/// when C.prototype is a non-object value. See test262
/// language/expressions/instanceof/primitive-prototype-with-primitive.js.
test "instanceof returns false for primitive LHS with non-object prototype (number LHS)" {
  let (_, result) = run_js("function F() {} F.prototype = true; 0 instanceof F")
  expect_result(result, "false")
}

///|
test "instanceof returns false for primitive LHS with non-object prototype (string LHS)" {
  let (_, result) = run_js(
    "function F() {} F.prototype = 42; \"s\" instanceof F",
  )
  expect_result(result, "false")
}

///|
/// Non-plain-Object variants (Array, Map, Set, Promise, Proxy) are also
/// objects in this engine's Value model. OrdinaryHasInstance step 5 must
/// accept them as valid `prototype` values, not throw TypeError.
test "instanceof with Array as prototype walks chain" {
  let (_, result) = run_js(
    "function F() {} F.prototype = []; ({}) instanceof F",
  )
  expect_result(result, "false")
}

///|
test "instanceof with Map as prototype walks chain" {
  let (_, result) = run_js(
    "function F() {} F.prototype = new Map(); ({}) instanceof F",
  )
  expect_result(result, "false")
}

///|
/// Fallback path when @@hasInstance is overridden to undefined: same gate must
/// also accept non-plain-Object prototypes.
test "instanceof fallback path with Array prototype" {
  let (_, result) = run_js(
    "function F() {} F[Symbol.hasInstance] = undefined; F.prototype = []; ({}) instanceof F",
  )
  expect_result(result, "false")
}

///|
/// Function.prototype.apply with a non-plain-Object array-like (Proxy/Map/
/// Promise) must not throw TypeError; per §7.3.18, only primitives throw.
test "apply with Proxy argArray does not throw" {
  let (_, result) = run_js(
    "var called = false; function f(){ called = true; } f.apply(null, new Proxy({length: 0}, {})); called",
  )
  expect_result(result, "true")
}

///|
test "apply with Map argArray does not throw" {
  let (_, result) = run_js(
    "var n = -1; function f(){ n = arguments.length; } f.apply(null, new Map()); n",
  )
  expect_result(result, "0")
}

///|
/// CreateListFromArrayLike (§7.3.18) must route length + indexed reads
/// through Get, so a Proxy that fakes array-like shape via its `get` trap
/// still delivers arguments. The preceding e9a5b33 fix accepted non-plain
/// object variants past the type gate but then silently returned [] for
/// Map/Set/Promise/Proxy, dropping trapped args. Codex P2 regression guard.
test "apply with Proxy length+index traps delivers argument" {
  let (_, result) = run_js(
    (
      #|var h = { get: function(t, k) { if (k === "length") return 1; if (k === "0") return 42; } };
      #|var p = new Proxy({}, h);
      #|var got = -1;
      #|function f() { got = arguments[0]; }
      #|f.apply(null, p);
      #|got
    ),
  )
  expect_result(result, "42")
}

///|
/// Same shape via Reflect.apply — independent code path that delegates to
/// the same create_list_from_array_like helper.
test "Reflect.apply with Proxy length+index traps delivers argument" {
  let (_, result) = run_js(
    (
      #|var h = { get: function(t, k) { if (k === "length") return 2; if (k === "0") return "a"; if (k === "1") return "b"; } };
      #|var p = new Proxy({}, h);
      #|var out = "";
      #|function f(x, y) { out = x + y; }
      #|Reflect.apply(f, null, p);
      #|out
    ),
  )
  expect_result(result, "ab")
}

///|
/// ArrayLike Objects with inherited length should work too — previous
/// implementation read data.bag.properties directly, missing prototype chain.
test "apply with Object inheriting length from prototype" {
  let (_, result) = run_js(
    (
      #|var proto = { length: 1, 0: 99 };
      #|var obj = Object.create(proto);
      #|var got = -1;
      #|function f() { got = arguments[0]; }
      #|f.apply(null, obj);
      #|got
    ),
  )
  expect_result(result, "99")
}

///|
/// ES §15.4.5 MethodDefinitionEvaluation does not perform MakeConstructor.
/// Class methods and object-literal method shorthand therefore reject `new`
/// and expose no own `.prototype` property.
test "method definitions are not constructors and have no prototype property" {
  let src =
    #|var obj = { m() {} };
    #|class C { m() {} static s() {} }
    #|var c = new C();
    #|
    #|try { new obj.m(); console.log("object-ok"); } catch (e) { console.log(e.name); }
    #|try { new c.m(); console.log("class-ok"); } catch (e) { console.log(e.name); }
    #|try { new C.s(); console.log("static-ok"); } catch (e) { console.log(e.name); }
    #|
    #|console.log(Object.prototype.hasOwnProperty.call(obj.m, "prototype"));
    #|console.log(Object.prototype.hasOwnProperty.call(c.m, "prototype"));
    #|console.log(typeof obj.m.prototype);
    #|console.log(typeof c.m.prototype);
    #|console.log(typeof C.s.prototype);
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError", "TypeError", "TypeError", "false", "false", "undefined", "undefined",
    "undefined",
  ])
}

///|
/// Generator MethodDefinitions keep their own `.prototype` property, but
/// generator functions still do not have [[Construct]].
test "generator method definitions are not constructors" {
  let src =
    #|class C { *m() {} static *s() {} }
    #|var c = new C();
    #|try { new c.m(); console.log("method-ok"); } catch (e) { console.log(e.name); }
    #|try { new C.s(); console.log("static-ok"); } catch (e) { console.log(e.name); }
    #|console.log(Object.prototype.hasOwnProperty.call(c.m, "prototype"));
    #|console.log(Object.prototype.hasOwnProperty.call(C.s, "prototype"));
    #|console.log(typeof c.m.prototype);
    #|console.log(typeof C.s.prototype);
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError", "TypeError", "true", "true", "object", "object",
  ])
}

///|
/// Async generator MethodDefinitions follow the same constructor rule as
/// generator methods while preserving their own `.prototype` property.
test "async generator method definitions are not constructors" {
  let src =
    #|class C { async *m() {} static async *s() {} }
    #|var c = new C();
    #|try { new c.m(); console.log("method-ok"); } catch (e) { console.log(e.name); }
    #|try { new C.s(); console.log("static-ok"); } catch (e) { console.log(e.name); }
    #|console.log(Object.prototype.hasOwnProperty.call(c.m, "prototype"));
    #|console.log(Object.prototype.hasOwnProperty.call(C.s, "prototype"));
    #|console.log(typeof c.m.prototype);
    #|console.log(typeof C.s.prototype);
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError", "TypeError", "true", "true", "object", "object",
  ])
}

///|
/// Getter and setter method functions are also MethodDefinitions: their
/// descriptor functions are non-constructors and have no `.prototype`.
test "class accessor method definitions are not constructors" {
  let src =
    #|class C {
    #|  get m() { return 1; }
    #|  set n(v) {}
    #|}
    #|var gd = Object.getOwnPropertyDescriptor(C.prototype, "m").get;
    #|var sd = Object.getOwnPropertyDescriptor(C.prototype, "n").set;
    #|try { new gd(); console.log("getter-ok"); } catch (e) { console.log(e.name); }
    #|try { new sd(); console.log("setter-ok"); } catch (e) { console.log(e.name); }
    #|console.log(typeof gd.prototype);
    #|console.log(typeof sd.prototype);
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError", "TypeError", "undefined", "undefined",
  ])
}

// ---------------------------------------------------------------------------
// Stage B.2 regression guards — [[GetOwnProperty]] + [[DefineOwnProperty]]
// ---------------------------------------------------------------------------

///|
/// §10.1.9.2 step 3.e: Reflect.set with a separate target but the receiver's
/// length is writable — landing uses { value: V } valueDesc, ArraySetLength
/// applies, length becomes 10.
test "B.2: Reflect.set writable length via {} target succeeds" {
  let src =
    #|var arr = [];
    #|var ok = Reflect.set({}, "length", 10, arr);
    #|console.log(ok);
    #|console.log(arr.length);
  let output = run_output(src)
  json_inspect(output, content=["true", "10"])
}

///|
/// §10.4.2.4 ArraySetLength with writable:false length → Reflect.set returns
/// false and length is unchanged. Today the B.1 landing bypasses the
/// descriptor, wrongly succeeds. B.2 fix: route through [[DefineOwnProperty]].
test "B.2: Reflect.set on non-writable length rejects (B.1 approx #1)" {
  let src =
    #|var arr = [1, 2, 3];
    #|Object.defineProperty(arr, "length", { writable: false });
    #|var ok = Reflect.set({}, "length", 10, arr);
    #|console.log(ok);
    #|console.log(arr.length);
  let output = run_output(src)
  json_inspect(output, content=["false", "3"])
}

///|
/// §10.5.6: Reflect.defineProperty on a Proxy must invoke the
/// defineProperty trap. Today the B.1 landing unwraps the target and
/// bypasses the trap.
test "B.2: Reflect.defineProperty on Proxy invokes trap (B.1 approx #2)" {
  let src =
    #|var target = {};
    #|var calls = [];
    #|var handler = {
    #|  defineProperty: function(t, k, d) {
    #|    calls.push(k);
    #|    return Reflect.defineProperty(t, k, d);
    #|  }
    #|};
    #|var p = new Proxy(target, handler);
    #|Reflect.defineProperty(p, "x", { value: 1, writable: true, enumerable: true, configurable: true });
    #|console.log(calls.length);
    #|console.log(calls[0]);
    #|console.log(target.x);
  let output = run_output(src)
  json_inspect(output, content=["1", "x", "1"])
}

///|
/// Object.defineProperty on a Proxy also invokes the trap (spec-parallel
/// to Reflect, different throw-vs-return behavior).
test "B.2: Object.defineProperty on Proxy invokes trap" {
  let src =
    #|var target = {};
    #|var trapCalled = false;
    #|var handler = {
    #|  defineProperty: function(t, k, d) {
    #|    trapCalled = true;
    #|    return Reflect.defineProperty(t, k, d);
    #|  }
    #|};
    #|var p = new Proxy(target, handler);
    #|Object.defineProperty(p, "x", { value: 7 });
    #|console.log(trapCalled);
    #|console.log(target.x);
  let output = run_output(src)
  json_inspect(output, content=["true", "7"])
}

///|
/// §10.5.5: Proxy.getOwnPropertyDescriptor invokes the getOwnPropertyDescriptor
/// trap.
test "B.2: Reflect.getOwnPropertyDescriptor on Proxy invokes trap" {
  let src =
    #|var target = { y: 42 };
    #|var calls = [];
    #|var handler = {
    #|  getOwnPropertyDescriptor: function(t, k) {
    #|    calls.push(k);
    #|    return { value: 999, writable: false, enumerable: true, configurable: true };
    #|  }
    #|};
    #|var p = new Proxy(target, handler);
    #|var d = Reflect.getOwnPropertyDescriptor(p, "y");
    #|console.log(calls.length);
    #|console.log(calls[0]);
    #|console.log(d.value);
    #|console.log(d.writable);
  let output = run_output(src)
  json_inspect(output, content=["1", "y", "999", "false"])
}

///|
/// §10.5.5 step 14: trap returns undefined for a non-configurable own
/// property on the target → TypeError.
test "B.2: Proxy GOPD trap hides non-configurable own prop throws TypeError" {
  let src =
    #|var target = {};
    #|Object.defineProperty(target, "x", { value: 1, configurable: false, writable: false });
    #|var handler = { getOwnPropertyDescriptor: function(t, k) { return undefined; } };
    #|var p = new Proxy(target, handler);
    #|try {
    #|  Reflect.getOwnPropertyDescriptor(p, "x");
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError"])
}

///|
/// §10.5.5 step 8: trap returns a non-object non-undefined → TypeError.
test "B.2: Proxy GOPD trap returning non-object throws TypeError" {
  let src =
    #|var target = { x: 1 };
    #|var handler = { getOwnPropertyDescriptor: function(t, k) { return 42; } };
    #|var p = new Proxy(target, handler);
    #|try {
    #|  Reflect.getOwnPropertyDescriptor(p, "x");
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError"])
}

///|
/// §10.5.5 non-extensible target: trap reports a property not on the
/// target when target is non-extensible → TypeError.
test "B.2: Proxy GOPD trap reports phantom prop on non-extensible target" {
  let src =
    #|var target = {};
    #|Object.preventExtensions(target);
    #|var handler = {
    #|  getOwnPropertyDescriptor: function(t, k) {
    #|    return { value: 1, writable: true, enumerable: true, configurable: true };
    #|  }
    #|};
    #|var p = new Proxy(target, handler);
    #|try {
    #|  Reflect.getOwnPropertyDescriptor(p, "x");
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError"])
}

///|
/// §10.5.6 step 17: defineProperty trap returns true for a non-configurable
/// descriptor on a key that doesn't exist on a non-extensible target →
/// TypeError (after the trap succeeds, invariant check fails).
test "B.2: Proxy defineProperty trap succeeds against non-extensible target" {
  let src =
    #|var target = {};
    #|Object.preventExtensions(target);
    #|var handler = { defineProperty: function(t, k, d) { return true; } };
    #|var p = new Proxy(target, handler);
    #|try {
    #|  Reflect.defineProperty(p, "x", { value: 1, configurable: false });
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError"])
}

///|
/// §10.5.6 step 16: defineProperty trap reports non-configurable on a key
/// that target has as configurable → TypeError.
test "B.2: Proxy defineProperty trap non-config lies about target" {
  let src =
    #|var target = { x: 1 };
    #|var handler = { defineProperty: function(t, k, d) { return true; } };
    #|var p = new Proxy(target, handler);
    #|try {
    #|  Reflect.defineProperty(p, "x", { configurable: false });
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError"])
}

///|
/// Descriptor visibility on arrays: Object.getOwnPropertyDescriptor(arr, "0")
/// and (arr, "length") return correctly-shaped descriptors.
test "B.2: Object.getOwnPropertyDescriptor on array elements and length" {
  let src =
    #|var arr = [10, 20, 30];
    #|var d0 = Object.getOwnPropertyDescriptor(arr, "0");
    #|console.log(d0.value + "/" + d0.writable + "/" + d0.enumerable + "/" + d0.configurable);
    #|var dl = Object.getOwnPropertyDescriptor(arr, "length");
    #|console.log(dl.value + "/" + dl.writable + "/" + dl.enumerable + "/" + dl.configurable);
  let output = run_output(src)
  json_inspect(output, content=["10/true/true/true", "3/true/false/false"])
}

///|
/// Stage C: RegExp match arrays store named properties in ArrayData.bag, so
/// ordinary own-property inspection observes them.
test "Stage C: RegExp match array named properties are own descriptors" {
  let src =
    #|var match = /(a)(b)/.exec("zabz");
    #|var indexDesc = Object.getOwnPropertyDescriptor(match, "index");
    #|var inputDesc = Object.getOwnPropertyDescriptor(match, "input");
    #|var groupsDesc = Object.getOwnPropertyDescriptor(match, "groups");
    #|console.log(indexDesc.value + "/" + indexDesc.writable + "/" + indexDesc.enumerable + "/" + indexDesc.configurable);
    #|console.log(inputDesc.value + "/" + inputDesc.writable + "/" + inputDesc.enumerable + "/" + inputDesc.configurable);
    #|console.log(groupsDesc.value === undefined);
    #|var names = Object.getOwnPropertyNames(match);
    #|console.log(names.indexOf("index") >= 0);
    #|console.log(Object.keys(match).indexOf("input") >= 0);
    #|console.log(match.propertyIsEnumerable("groups"));
    #|var seenGroups = false;
    #|for (var k in match) { if (k === "groups") seenGroups = true; }
    #|console.log(seenGroups);
    #|console.log(delete match.groups);
    #|console.log(match.hasOwnProperty("groups"));
    #|var descs = Object.getOwnPropertyDescriptors(match);
    #|console.log(descs.index.value);
  let output = run_output(src)
  json_inspect(output, content=[
    "1/true/true/true", "zabz/true/true/true", "true", "true", "true", "true", "true",
    "true", "false", "1",
  ])
}

///|
/// Stage C: array indexed element descriptors are stored on ArrayData.bag.
test "Stage C: Array index descriptors persist attributes" {
  let src =
    #|var arr = [10, 20, 30];
    #|Object.defineProperty(arr, "0", { value: 11, writable: false, enumerable: false, configurable: false });
    #|var d0 = Object.getOwnPropertyDescriptor(arr, "0");
    #|console.log(d0.value + "/" + d0.writable + "/" + d0.enumerable + "/" + d0.configurable);
    #|console.log(Object.keys(arr).indexOf("0") < 0);
    #|arr[0] = 99;
    #|console.log(arr[0]);
    #|try {
    #|  Object.defineProperty(arr, "length", { value: 0 });
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|console.log(arr.length);
  let output = run_output(src)
  json_inspect(output, content=[
    "11/false/false/false", "true", "11", "TypeError", "1",
  ])
}

///|
/// Stage C: sparse length overrides are internal state, not observable
/// string-keyed properties.
test "Stage C: Array sparse length override is hidden" {
  let src =
    #|var arr = new Array(10000001);
    #|console.log(arr.length);
    #|console.log(arr["length"]);
    #|console.log(arr["[[ArrayLengthOverride]]"]);
    #|console.log(arr.hasOwnProperty("[[ArrayLengthOverride]]"));
    #|console.log(Object.getOwnPropertyDescriptor(arr, "[[ArrayLengthOverride]]"));
    #|console.log(Object.getOwnPropertyNames(arr).indexOf("[[ArrayLengthOverride]]"));
  let output = run_output(src)
  json_inspect(output, content=[
    "10000001", "10000001", "undefined", "false", "undefined", "-1",
  ])
}

///|
/// Stage C: setter-only indexed accessors read as undefined instead of
/// falling through to the dense element backing store.
test "Stage C: Array setter-only index accessor reads undefined" {
  let src =
    #|var arr = [10];
    #|var seen = 0;
    #|Object.defineProperty(arr, "0", { set: function(v) { seen = v; }, enumerable: true, configurable: true });
    #|console.log(arr[0]);
    #|console.log(arr["0"]);
    #|arr[0] = 42;
    #|console.log(seen);
    #|console.log(Object.getOwnPropertyDescriptor(arr, "0").get);
  let output = run_output(src)
  json_inspect(output, content=["undefined", "undefined", "42", "undefined"])
}

///|
/// §10.4.2.4: Object.defineProperty(arr, "length", { value: N, writable: false })
/// truncates AND locks length in a single step.
test "B.2: Array length partial-truncate and lock writable in one step" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|Object.defineProperty(arr, "length", { value: 2, writable: false });
    #|console.log(arr.length);
    #|try {
    #|  arr.length = 3;
    #|  console.log("sloppy-silent");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|console.log(arr.length);
  let output = run_output(src)
  json_inspect(output, content=["2", "sloppy-silent", "2"])
}

///|
/// §10.4.2.4: failed truncation still applies a requested length writable:false.
test "B.2: Failed Array length truncation locks writable" {
  let src =
    #|var arr = [0, 1, 2];
    #|Object.defineProperty(arr, "1", { configurable: false });
    #|try {
    #|  Object.defineProperties(arr, { length: { value: 0, writable: false } });
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var d = Object.getOwnPropertyDescriptor(arr, "length");
    #|console.log(arr.length);
    #|console.log(d.writable);
    #|console.log(arr.hasOwnProperty("1"));
  let output = run_output(src)
  json_inspect(output, content=["TypeError", "2", "false", "true"])
}

///|
/// §10.4.2.4: length value that coerces to NaN → RangeError.
test "B.2: Array length set to NaN throws RangeError" {
  let src =
    #|var arr = [1, 2, 3];
    #|try {
    #|  Object.defineProperty(arr, "length", { value: "not a number" });
    #|  console.log("ok");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["RangeError"])
}

///|
/// §10.4.2.4: extending beyond the small-gap threshold via defineProperty
/// must not materialise the new slots — the engine relies on the logical-
/// length override for sparse arrays. If the bound is ever removed, this
/// test will OOM or time out instead of returning instantly.
test "B.2: Array length set huge via defineProperty stays sparse" {
  let src =
    #|var arr = [1, 2, 3];
    #|Object.defineProperty(arr, "length", { value: 1000000 });
    #|console.log(arr.length);
    #|console.log(arr[0]);
    #|console.log(arr[999999]);
  let output = run_output(src)
  json_inspect(output, content=["1000000", "1", "undefined"])
}

///|
/// IteratorClose: iterator.return() called when for-of body throws (ForOfStmt)
test "IteratorClose: body throw calls iterator return (ForOfStmt)" {
  let src =
    #|var returnCalled = false;
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { returnCalled = true; return {}; }
    #|};
    #|try {
    #|  for (var x of iter) { throw new Error("body"); }
    #|} catch(e) {}
    #|console.log(returnCalled);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose: iterator.return() called when for-of body throws (ForOfStmtPat)
test "IteratorClose: body throw calls iterator return (ForOfStmtPat)" {
  let src =
    #|var returnCalled = false;
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: {a: 1} }; },
    #|  return() { returnCalled = true; return {}; }
    #|};
    #|try {
    #|  for (let {a} of iter) { throw new Error("body"); }
    #|} catch(e) {}
    #|console.log(returnCalled);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose: iterator.return() called when pattern assignment fails (ForOfStmtPat)
test "IteratorClose: pattern assign error calls iterator return" {
  let src =
    #|var returnCalled = false;
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: null }; },
    #|  return() { returnCalled = true; return {}; }
    #|};
    #|try {
    #|  for (let {a} of iter) {}
    #|} catch(e) {}
    #|console.log(returnCalled);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose: iterator.return() called when ForOfExpr lhs assignment throws
test "IteratorClose: lhs put error calls iterator return (ForOfExpr)" {
  let src =
    #|"use strict";
    #|var returnCalled = false;
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { returnCalled = true; return {}; }
    #|};
    #|var obj = Object.freeze({x: 0});
    #|try {
    #|  for (obj.x of iter) {}
    #|} catch(e) {}
    #|console.log(returnCalled);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose: iterator.return() called when ForOfExpr body throws
test "IteratorClose: body throw calls iterator return (ForOfExpr)" {
  let src =
    #|var returnCalled = false;
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { returnCalled = true; return {}; }
    #|};
    #|var target = {};
    #|try {
    #|  for (target.x of iter) { throw new Error("body"); }
    #|} catch(e) {}
    #|console.log(returnCalled);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose: iterator.return() called on ForOfStmt ReturnSignal
test "IteratorClose: return inside for-of calls iterator return" {
  let src =
    #|var returnCalled = false;
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { returnCalled = true; return {}; }
    #|};
    #|function f() {
    #|  for (var x of iter) { return x; }
    #|}
    #|f();
    #|console.log(returnCalled);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose: iterator.return() called on ForOfStmt break
test "IteratorClose: break inside for-of calls iterator return" {
  let src =
    #|var returnCalled = false;
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { returnCalled = true; return {}; }
    #|};
    #|for (var x of iter) { break; }
    #|console.log(returnCalled);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose §7.4.10 step 5: return() throw on non-throw completion replaces the signal
test "IteratorClose: return() throw on return-completion propagates (not suppressed)" {
  let src =
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { throw new Error("close threw"); }
    #|};
    #|function f() { for (var x of iter) { return x; } }
    #|try { f(); console.log("no error"); } catch(e) { console.log(e.message); }
  let output = run_output(src)
  json_inspect(output, content=["close threw"])
}

///|
/// IteratorClose §7.4.10 step 7: return() returning non-Object on non-throw completion is TypeError
test "IteratorClose: return() non-object on break-completion throws TypeError" {
  let src =
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { return 42; }
    #|};
    #|try { for (var x of iter) { break; } console.log("no error"); } catch(e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose §7.4.10 step 7: Array/Map/Set/Promise/Proxy are valid object results from return()
test "IteratorClose: return() returning Array is accepted (not TypeError)" {
  let src =
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { return []; }
    #|};
    #|try { for (var x of iter) { break; } console.log("ok"); } catch(e) { console.log("error: " + e.message); }
  let output = run_output(src)
  json_inspect(output, content=["ok"])
}

///|
/// IteratorClose §7.3.9 GetMethod: non-callable non-undefined return property is TypeError
test "IteratorClose: non-callable return property throws TypeError on break-completion" {
  let src =
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return: 42
    #|};
    #|try { for (var x of iter) { break; } console.log("no error"); } catch(e) { console.log(e instanceof TypeError); }
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// IteratorClose §7.4.10 step 4: throw completion suppresses return() throw
test "IteratorClose: throw-completion suppresses return() error (original throw wins)" {
  let src =
    #|var iter = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return { done: false, value: 1 }; },
    #|  return() { throw new Error("close threw"); }
    #|};
    #|try { for (var x of iter) { throw new Error("body threw"); } } catch(e) { console.log(e.message); }
  let output = run_output(src)
  json_inspect(output, content=["body threw"])
}

///|
/// Proxy [[Construct]] newTarget: Reflect.construct passes newTarget to trap
test "Proxy construct: Reflect.construct newTarget forwarded to trap" {
  let src =
    #|var capturedNewTarget;
    #|var handler = {
    #|  construct(target, args, newTarget) {
    #|    capturedNewTarget = newTarget;
    #|    return {};
    #|  }
    #|};
    #|function Foo() {}
    #|function Bar() {}
    #|var P = new Proxy(Foo, handler);
    #|Reflect.construct(P, [], Bar);
    #|console.log(capturedNewTarget === Bar);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// Proxy [[Construct]] no trap: newTarget propagated to target via no-trap path
test "Proxy construct no trap: new.target = explicit newTarget" {
  let src =
    #|var capturedNewTarget;
    #|function Foo() { capturedNewTarget = new.target; }
    #|var P = new Proxy(Foo, {});
    #|function Bar() {}
    #|Reflect.construct(P, [], Bar);
    #|console.log(capturedNewTarget === Bar);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// Reflect.construct: new.target in body equals the newTarget argument
test "Reflect.construct: new.target in body is newTarget" {
  let src =
    #|function Foo() { return new.target; }
    #|function Bar() {}
    #|var result = Reflect.construct(Foo, [], Bar);
    #|console.log(result === Bar);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// direct new: new.target === constructor (unchanged regression)
test "construct: new.target === ctor for direct new" {
  let src =
    #|function Foo() { return new.target; }
    #|console.log(new Foo() === Foo);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// super() propagates new.target to super constructor body
test "class: new.target propagates through super() call" {
  let src =
    #|class Base {
    #|  constructor() { this.nt = new.target; }
    #|}
    #|class Derived extends Base {}
    #|var d = new Derived();
    #|console.log(d.nt === Derived);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// Reflect.construct with implicit derived ctor: new.target is newTarget arg, not D
test "class: Reflect.construct implicit ctor new.target is newTarget not derived" {
  let src =
    #|class Base {
    #|  constructor() { this.nt = new.target; }
    #|}
    #|class D extends Base {}
    #|function OtherCtor() {}
    #|var obj = Reflect.construct(D, [], OtherCtor);
    #|console.log(obj.nt === OtherCtor);
  let output = run_output(src)
  json_inspect(output, content=["true"])
}

///|
/// Reflect.construct(boundFn, [], boundFn): newTarget rewritten to target, instance
/// prototype comes from target.prototype, not the absent bound-fn .prototype (Null)
test "BoundFunc construct: newTarget===boundFn drops proto_override, uses target proto" {
  let src =
    #|function Target() {}
    #|Target.prototype.tag = "target";
    #|var bound = Target.bind(null);
    #|var obj = Reflect.construct(bound, [], bound);
    #|console.log(obj.tag);
  let output = run_output(src)
  json_inspect(output, content=["target"])
}

///|
/// §7.1.21 / §10.4.5: TypedArray string keys "-0", "NaN", "Infinity", "-Infinity"
/// are canonical numeric index strings but invalid integer indices. Writes must
/// succeed as no-ops (no expando created); reads must return undefined.
test "typedarray canonical-invalid string keys: -0 write is no-op" {
  let src =
    #|var a = new Uint8Array(1);
    #|a["-0"] = 99;
    #|console.log(a["-0"]);
    #|console.log(Object.keys(a).length);
  let output = run_output(src)
  json_inspect(output, content=["undefined", "0"])
}

///|
test "typedarray canonical-invalid string keys: NaN write is no-op" {
  let src =
    #|var a = new Uint8Array(1);
    #|a["NaN"] = 99;
    #|console.log(a["NaN"]);
    #|console.log(Object.keys(a).length);
  let output = run_output(src)
  json_inspect(output, content=["undefined", "0"])
}

///|
test "typedarray canonical-invalid string keys: Infinity write is no-op" {
  let src =
    #|var a = new Uint8Array(1);
    #|a["Infinity"] = 99;
    #|console.log(a["Infinity"]);
    #|console.log(Object.keys(a).length);
  let output = run_output(src)
  json_inspect(output, content=["undefined", "0"])
}

///|
/// "1.5" is canonical (ToString round-trip) but a fractional, not integer index.
test "typedarray canonical-invalid string keys: 1.5 write is no-op" {
  let src =
    #|var a = new Uint8Array(2);
    #|a["1.5"] = 99;
    #|console.log(a["1.5"]);
    #|console.log(Object.keys(a).length);
  let output = run_output(src)
  json_inspect(output, content=["undefined", "0"])
}

///|
/// Non-canonical string keys ("foo", "1e1", "+Infinity") are ordinary expando
/// properties — the spec fall-through is preserved.
test "typedarray non-canonical string keys: foo stores as expando" {
  let src =
    #|var a = new Uint8Array(1);
    #|a["foo"] = 99;
    #|console.log(a["foo"]);
  let output = run_output(src)
  json_inspect(output, content=["99"])
}

///|
test "typedarray non-canonical string keys: 1e1 stores as expando" {
  let src =
    #|var a = new Uint8Array(1);
    #|a["1e1"] = 99;
    #|console.log(a["1e1"]);
  let output = run_output(src)
  json_inspect(output, content=["99"])
}

///|
/// Strict mode: setting a Symbol into a TypedArray element slot triggers
/// ToNumber which must raise TypeError — this is the wide-catch regression
/// from the 2026-04-24 refactor. Applies to canonical valid indices.
test "typedarray strict symbol coercion raises TypeError" {
  let src =
    #|"use strict";
    #|var a = new Uint8Array(1);
    #|try {
    #|  a["0"] = Symbol();
    #|  console.log("no throw");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError"])
}

///|
/// §7.4.10 IteratorClose via §7.3.10 GetMethod: accessor `return` getter
/// must be invoked. Pre-fix the close walked `bag.properties` directly and
/// missed accessor descriptors (their data slot stores Undefined as sentinel).
test "for-of break invokes accessor return getter on iterator" {
  let src =
    #|var invoked = 0;
    #|const it = {
    #|  next() { return { value: 1, done: false }; },
    #|  [Symbol.iterator]() { return this; }
    #|};
    #|Object.defineProperty(it, "return", {
    #|  get() {
    #|    invoked++;
    #|    return function() { return { value: undefined, done: true }; };
    #|  }
    #|});
    #|for (const x of it) break;
    #|console.log(invoked);
  let output = run_output(src)
  json_inspect(output, content=["1"])
}

///|
/// §10.4.5.5 step 1.b.i: SameValue(O, Receiver) → write to buffer.
test "TypedArray Reflect.set same-receiver in-range writes to buffer" {
  let src =
    #|const ta = new Uint8Array(3);
    #|const r = Reflect.set(ta, "1", 42, ta);
    #|console.log(r);
    #|console.log(ta[1]);
  let output = run_output(src)
  json_inspect(output, content=["true", "42"])
}

///|
/// §10.4.5.5 step 2 (when 1.b.i and 1.b.ii both fall through):
/// O !== Receiver AND valid integer index → OrdinarySet on Receiver,
/// landing as an ordinary data property on Receiver. The TypedArray's
/// backing buffer is NOT written to.
test "TypedArray Reflect.set different-receiver in-range lands on receiver" {
  let src =
    #|const ta = new Uint8Array(3);
    #|const obj = {};
    #|Reflect.set(ta, "0", 99, obj);
    #|console.log(ta[0]);
    #|console.log(obj[0]);
  let output = run_output(src)
  json_inspect(output, content=["0", "99"])
}

///|
/// §10.4.5.5 step 1.b.ii: O !== Receiver AND not a valid integer
/// index (out-of-range) → return true (no-op, do NOT land on Receiver).
test "TypedArray Reflect.set different-receiver out-of-range is no-op" {
  let src =
    #|const ta = new Uint8Array(3);
    #|const obj = {};
    #|const r = Reflect.set(ta, "100", 99, obj);
    #|console.log(r);
    #|console.log(typeof obj["100"]);
  let output = run_output(src)
  json_inspect(output, content=["true", "undefined"])
}

///|
/// §10.4.5.5 [[Set]] receiver-sensitive numeric semantics also apply when a
/// TypedArray is encountered on the prototype chain.
test "TypedArray Set receiver and prototype numeric semantics" {
  let src =
    #|let valueOfCalls = 0;
    #|const value = { valueOf() { valueOfCalls++; return 7; } };
    #|
    #|const sameReceiver = new Uint8Array([1]);
    #|sameReceiver["-1"] = value;
    #|console.log(valueOfCalls);
    #|console.log(sameReceiver.hasOwnProperty("-1"));
    #|
    #|valueOfCalls = 0;
    #|const proto = new Uint8Array([2]);
    #|const receiver = Object.create(proto);
    #|receiver["0"] = value;
    #|console.log(proto[0]);
    #|console.log(receiver[0] === value);
    #|console.log(valueOfCalls);
    #|receiver["1.5"] = value;
    #|console.log(receiver.hasOwnProperty("1.5"));
    #|console.log(valueOfCalls);
    #|const arr = Object.setPrototypeOf([], proto);
    #|arr[1] = value;
    #|console.log(arr.hasOwnProperty("1"));
    #|console.log(arr.length);
    #|const arrString = Object.setPrototypeOf([], proto);
    #|arrString["1"] = value;
    #|console.log(arrString.hasOwnProperty("1"));
    #|console.log(arrString.length);
    #|console.log(valueOfCalls);
    #|
    #|const typedReceiver = new Uint8Array([3]);
    #|console.log(Reflect.set(proto, "0", new Number(9), typedReceiver));
    #|console.log(typedReceiver[0]);
    #|
    #|valueOfCalls = 0;
    #|const obj = Object.create(typedReceiver);
    #|console.log(Reflect.set(obj, "100", value, typedReceiver));
    #|console.log(valueOfCalls);
  let output = run_output(src)
  json_inspect(output, content=[
    "1", "false", "2", "true", "0", "false", "0", "false", "0", "false", "0", "0",
    "true", "9", "true", "1",
  ])
}

///|
/// Map/Set instances use a collection-specific prototype walk before writing
/// expandos. If that walk sees a TypedArray with an own integer-index
/// descriptor, it must stop there and land on the collection receiver instead
/// of continuing to a higher setter.
test "Map and Set prototype Set walk stops at TypedArray integer index" {
  let src =
    #|const log = [];
    #|const blocker = {};
    #|Object.defineProperty(blocker, "0", {
    #|  set(v) { log.push("setter:" + v); }
    #|});
    #|
    #|const mapProtoStop = new Uint8Array([7]);
    #|Object.setPrototypeOf(mapProtoStop, blocker);
    #|class M extends Map {}
    #|Object.setPrototypeOf(M.prototype, mapProtoStop);
    #|const m = new M();
    #|m[0] = 42;
    #|console.log(log.length);
    #|console.log(m[0]);
    #|console.log(mapProtoStop[0]);
    #|console.log(Object.getOwnPropertyDescriptor(m, "0").value);
    #|
    #|const setProtoStop = new Uint8Array([8]);
    #|Object.setPrototypeOf(setProtoStop, blocker);
    #|class S extends Set {}
    #|Object.setPrototypeOf(S.prototype, setProtoStop);
    #|const s = new S();
    #|s[0] = 43;
    #|console.log(log.length);
    #|console.log(s[0]);
    #|console.log(setProtoStop[0]);
    #|console.log(Object.getOwnPropertyDescriptor(s, "0").value);
  let output = run_output(src)
  json_inspect(output, content=["0", "42", "7", "42", "0", "43", "8", "43"])
}

///|
/// §10.4.5.2 [[HasProperty]]: canonical numeric index strings are handled by
/// IntegerIndexedExoticObject before falling through to OrdinaryHasProperty.
test "TypedArray Reflect.has numeric keys bypass prototype chain" {
  let src =
    #|const ta = new Uint8Array([7]);
    #|const proto = { foo: 42, 1: "proto-index" };
    #|Object.setPrototypeOf(proto, Object.getPrototypeOf(ta));
    #|Object.setPrototypeOf(ta, proto);
    #|console.log(Reflect.has(ta, "0"));
    #|console.log(Reflect.has(ta, "1"));
    #|console.log(Reflect.has(ta, "foo"));
  let output = run_output(src)
  json_inspect(output, content=["true", "false", "true"])
}

///|
/// §10.4.5.1 [[GetOwnProperty]] synthesizes descriptors for valid integer
/// indices, and detached buffers make those descriptors disappear.
test "TypedArray getOwnPropertyDescriptor integer indices" {
  let src =
    #|const ta = new Uint8Array([42, 43]);
    #|const d0 = Object.getOwnPropertyDescriptor(ta, "0");
    #|console.log(d0.value);
    #|console.log(d0.writable);
    #|console.log(d0.enumerable);
    #|console.log(d0.configurable);
    #|console.log(Reflect.defineProperty(ta, "1", { value: 99 }));
    #|console.log(ta[1]);
    #|console.log(Reflect.defineProperty(ta, "1", { value: 100, writable: false }));
    #|console.log(ta[1]);
    #|$262.detachArrayBuffer(ta.buffer);
    #|console.log(Object.getOwnPropertyDescriptor(ta, "0"));
    #|let count = 0;
    #|for (var key in ta) { count++; }
    #|console.log(count);
  let output = run_output(src)
  json_inspect(output, content=[
    "42", "true", "true", "true", "true", "99", "false", "99", "undefined", "0",
  ])
}

///|
/// §10.4.5.6 [[OwnPropertyKeys]] reports integer indices first, followed by
/// ordinary string keys in insertion order and then symbol keys.
test "TypedArray Reflect.ownKeys integer indices" {
  let src =
    #|const sym = Symbol("s");
    #|const ta = new Uint8Array([1, 2, 3]);
    #|ta.test262 = 1;
    #|ta.ecma262 = 2;
    #|ta[sym] = 3;
    #|const keys = Reflect.ownKeys(ta);
    #|const parts = [];
    #|for (var i = 0; i < keys.length; i++) {
    #|  parts.push(typeof keys[i] === "symbol" ? keys[i] === sym : keys[i]);
    #|}
    #|console.log(parts.join("|"));
    #|console.log(Reflect.ownKeys(ta.subarray(1)).join(","));
    #|console.log(Reflect.ownKeys(new Uint8Array()).length);
  let output = run_output(src)
  json_inspect(output, content=["0|1|2|test262|ecma262|true", "0,1", "0"])
}

///|
/// §10.4.5.10 [[Delete]]: valid TypedArray integer indices are non-deletable,
/// while out-of-range, detached, and canonical-invalid numeric keys return true.
test "TypedArray delete integer-indexed elements" {
  let src =
    #|const ta = new Uint8Array([7]);
    #|console.log(delete ta["0"]);
    #|console.log(delete ta["1"]);
    #|console.log(delete ta["-0"]);
    #|console.log(delete ta[-0]);
    #|$262.detachArrayBuffer(ta.buffer);
    #|console.log(delete ta["0"]);
  let output = run_output(src)
  json_inspect(output, content=["false", "true", "true", "false", "true"])
}

///|
test "strict TypedArray delete valid index throws" {
  let src =
    #|"use strict";
    #|const ta = new Uint8Array([7]);
    #|try {
    #|  delete ta["0"];
    #|  console.log("no throw");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|console.log(delete ta["1"]);
  let output = run_output(src)
  json_inspect(output, content=["TypeError", "true"])
}

///|
/// Review regression: Reflect and Proxy paths must route through the same
/// TypedArray integer-index [[Delete]]/[[GetOwnProperty]]/[[OwnPropertyKeys]]
/// dispatch as direct syntax, including detached-buffer filtering.
test "TypedArray Reflect and Proxy integer-index internals" {
  let src =
    #|const ta = new Uint8Array([1, 2]);
    #|console.log(Reflect.deleteProperty(ta, "0"));
    #|const passthrough = new Proxy(ta, {});
    #|console.log(Reflect.deleteProperty(passthrough, "0"));
    #|console.log(delete passthrough[0]);
    #|console.log(Object.getOwnPropertyDescriptor(passthrough, "0").value);
    #|console.log(Object.getOwnPropertyDescriptor(ta, 0).value);
    #|console.log(Reflect.getOwnPropertyDescriptor(ta, 1).value);
    #|Object.preventExtensions(ta);
    #|try {
    #|  delete new Proxy(ta, { deleteProperty() { return true; } })[0];
    #|  console.log("no throw");
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|const detached = new Uint8Array([3, 4]);
    #|$262.detachArrayBuffer(detached.buffer);
    #|console.log(Reflect.ownKeys(detached).length);
    #|console.log(Reflect.deleteProperty(detached, "0"));
    #|const proto = new Uint8Array([5]);
    #|const mid = Object.create(proto);
    #|const arrValid = Object.setPrototypeOf([], mid);
    #|arrValid[0] = 9;
    #|console.log(arrValid[0]);
    #|console.log(proto[0]);
    #|console.log(arrValid.length);
    #|const arrInvalid = Object.setPrototypeOf([], mid);
    #|arrInvalid[1] = 7;
    #|console.log(arrInvalid.hasOwnProperty("1"));
    #|console.log(arrInvalid.length);
  let output = run_output(src)
  json_inspect(output, content=[
    "false", "false", "false", "1", "1", "2", "TypeError", "0", "true", "9", "5",
    "1", "false", "0",
  ])
}

///|
/// Reflect.deleteProperty must dispatch to Map/Set/Promise [[Delete]], not just
/// accept them as object-like and report success while leaving expando props.
test "Reflect.deleteProperty removes Map Set Promise expandos" {
  let src =
    #|function check(o) {
    #|  o.x = 1;
    #|  console.log(Reflect.deleteProperty(o, "x"));
    #|  console.log(Object.prototype.hasOwnProperty.call(o, "x"));
    #|  const sym = Symbol("expando");
    #|  o[sym] = 2;
    #|  console.log(Reflect.deleteProperty(o, sym));
    #|  console.log(Object.prototype.hasOwnProperty.call(o, sym));
    #|  Object.defineProperty(o, "locked", { value: 3, configurable: false });
    #|  console.log(Reflect.deleteProperty(o, "locked"));
    #|  console.log(o.locked);
    #|}
    #|check(new Map());
    #|check(new Set());
    #|check(Promise.resolve(1));
  let output = run_output(src)
  json_inspect(output, content=[
    "true", "false", "true", "false", "false", "3", "true", "false", "true", "false",
    "false", "3", "true", "false", "true", "false", "false", "3",
  ])
}

///|
/// §7.4.10 IteratorClose via §7.3.10 GetMethod: non-callable `return`
/// inherited from the prototype chain must throw TypeError. Pre-fix the
/// close walked `bag.properties` directly without descriptor awareness;
/// inherited non-callable values were sometimes silently skipped depending
/// on prototype shape. The new dispatcher path resolves uniformly.
test "for-of break with non-callable inherited return throws TypeError" {
  let src =
    #|var threw = "";
    #|const proto = { return: 42 };
    #|const it = Object.create(proto);
    #|it.next = function() { return { value: 1, done: false }; };
    #|it[Symbol.iterator] = function() { return this; };
    #|try {
    #|  for (const x of it) break;
    #|} catch (e) {
    #|  threw = e.name;
    #|}
    #|console.log(threw);
  let output = run_output(src)
  json_inspect(output, content=["TypeError"])
}

///|
test "ToPrimitive: @@toPrimitive returning undefined falls through to OrdinaryToPrimitive" {
  let src =
    #|var t = { [Symbol.toPrimitive]: undefined, valueOf: function() { return 42; } };
    #|console.log(t + 1);
  let output = run_output(src)
  json_inspect(output, content=["43"])
}

///|
test "ToPrimitive: @@toPrimitive returning null falls through to OrdinaryToPrimitive" {
  let src =
    #|var t = { [Symbol.toPrimitive]: null, valueOf: function() { return 7; } };
    #|console.log(t * 2);
  let output = run_output(src)
  json_inspect(output, content=["14"])
}

///|
test "ToPrimitive: @@toPrimitive accessor invoked exactly once on default-hint fallback" {
  let src =
    #|var calls = 0;
    #|var t = {};
    #|Object.defineProperty(t, Symbol.toPrimitive, {
    #|  get: function() { calls += 1; return undefined; }
    #|});
    #|var r = t + 1;
    #|console.log(calls);
  let output = run_output(src)
  json_inspect(output, content=["1"])
}

///|
test "ToPrimitive: user error from valueOf accessor propagates with original identity" {
  let src =
    #|function MyError(msg) { this.message = msg; this.name = "MyError"; }
    #|var t = {};
    #|Object.defineProperty(t, "valueOf", {
    #|  get: function() { throw new MyError("from-valueOf"); }
    #|});
    #|var caught = "no-throw";
    #|try { t + 1; } catch (e) { caught = e.name + ":" + e.message; }
    #|console.log(caught);
  let output = run_output(src)
  json_inspect(output, content=["MyError:from-valueOf"])
}

///|
test "strict legacy octal: \\1 in string literal" {
  let src =
    #|"use strict"; "\1";
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "strict legacy octal: 0777 numeric literal" {
  let src =
    #|"use strict"; 0777;
  expect_throw(
    src, "SyntaxError: Octal literals are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "strict legacy octal: 08 numeric literal" {
  let src =
    #|"use strict"; 08;
  expect_throw(
    src, "SyntaxError: Decimals with leading zeros are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "non-strict legacy octal: \\1 is allowed" {
  let src =
    #|"\1"
  let result = run(src)
  expect_result(result, "\u{0001}")
}

///|
test "non-strict legacy octal: 0777 evaluates to 511" {
  let src =
    #|0777
  let result = run(src)
  expect_result(result, "511")
}

///|
test "strict NonOctalDecimal + fraction: 08.1 rejected" {
  let src =
    #|"use strict"; 08.1;
  expect_throw(
    src, "SyntaxError: Decimals with leading zeros are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "strict NonOctalDecimal + exponent: 08e2 rejected" {
  let src =
    #|"use strict"; 08e2;
  expect_throw(
    src, "SyntaxError: Decimals with leading zeros are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "non-strict NonOctalDecimal + fraction: 08.1 evaluates to 8.1" {
  let src =
    #|08.1
  let result = run(src)
  expect_result(result, "8.1")
}

///|
test "non-strict NonOctalDecimal + exponent: 08e2 evaluates to 800" {
  let src =
    #|08e2
  let result = run(src)
  expect_result(result, "800")
}

///|
test "single-zero fractional 0.5 valid in strict" {
  let src =
    #|"use strict"; 0.5
  let result = run(src)
  expect_result(result, "0.5")
}

///|
test "single-zero exponent 0.1e2 valid in strict" {
  let src =
    #|"use strict"; 0.1e2
  let result = run(src)
  expect_result(result, "10")
}

///|
test "LegacyOctal + fraction 01.2 is SyntaxError in non-strict" {
  let src =
    #|01.2
  expect_throw(
    src, "SyntaxError: Invalid number literal at line 1, col 1: leading-zero octal-style integer cannot be followed by a fractional part",
  )
}

///|
test "LegacyOctal + exponent 01e2 is SyntaxError in non-strict" {
  let src =
    #|01e2
  expect_throw(
    src, "SyntaxError: Invalid number literal at line 1, col 1: leading-zero octal-style integer cannot be followed by an exponent",
  )
}

///|
test "LegacyOctal + fraction 07.5 is SyntaxError in non-strict" {
  let src =
    #|07.5
  expect_throw(
    src, "SyntaxError: Invalid number literal at line 1, col 1: leading-zero octal-style integer cannot be followed by a fractional part",
  )
}

///|
test "LegacyOctal member access 01.toString() valid in non-strict" {
  let src =
    #|01.toString()
  let result = run(src)
  expect_result(result, "1")
}

///|
test "LegacyOctal member access 07.toString() returns string of value" {
  let src =
    #|07.toString()
  let result = run(src)
  expect_result(result, "7")
}

///|
test "LegacyOctal member access 01.constructor is Number" {
  let src =
    #|01.constructor === Number
  let result = run(src)
  expect_result(result, "true")
}

///|
test "bare \\0 NUL is allowed in strict" {
  let src =
    #|"use strict"; "\0".charCodeAt(0)
  let result = run(src)
  expect_result(result, "0")
}

///|
test "strict legacy octal: \\8 (NonOctalDecimalEscape) rejected" {
  let src =
    #|"use strict"; "\8";
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "strict legacy octal: \\9 (NonOctalDecimalEscape) rejected" {
  let src =
    #|"use strict"; "\9";
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "strict legacy octal: \\01 (\\0 followed by digit) rejected" {
  let src =
    #|"use strict"; "\01";
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 15",
  )
}

///|
test "non-strict: \\8 evaluates to literal '8'" {
  let src =
    #|"\8"
  let result = run(src)
  expect_result(result, "8")
}

///|
test "non-strict: \\9 evaluates to literal '9'" {
  let src =
    #|"\9"
  let result = run(src)
  expect_result(result, "9")
}

///|
test "strict legacy octal: \\1 nested in dead branch still errors" {
  let src =
    #|"use strict"; if (false) { "\1"; }
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 28",
  )
}

///|
test "strict legacy octal: never-called function still errors" {
  let src =
    #|"use strict";
    #|function f() { "\1"; }
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 2, col 16",
  )
}

///|
test "strict legacy octal: yield expression argument" {
  let src =
    #|"use strict";
    #|function* g() { yield "\1"; }
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 2, col 23",
  )
}

///|
test "strict legacy octal: yield* delegate argument" {
  let src =
    #|"use strict";
    #|function* g() { yield* ["\1"]; }
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 2, col 25",
  )
}

///|
test "strict legacy octal: super(args) call argument" {
  let src =
    #|class B {}
    #|class C extends B { constructor() { super("\1"); } }
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 2, col 43",
  )
}

///|
test "strict legacy octal: class superclass expression" {
  let src =
    #|"use strict";
    #|class C extends ("\1", Object) {}
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 2, col 18",
  )
}

///|
test "class superclass expression is strict even without 'use strict' (ClassDecl)" {
  // ES262 §15.7.1: all parts of a class — including the extends expression —
  // are strict-mode code regardless of the surrounding script's strictness.
  let src =
    #|class C extends ("\1", Object) {}
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 18",
  )
}

///|
test "class expression superclass is strict even without 'use strict' (ClassExpr)" {
  let src =
    #|var C = (class extends ("\1", Object) {});
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 25",
  )
}

///|
test "class method with legacy octal escape key" {
  let src =
    #|class C { "\1"() {} }
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 11",
  )
}

///|
test "class method with legacy octal numeric key" {
  let src =
    #|class C { 0777() {} }
  expect_throw(
    src, "SyntaxError: Octal literals are not allowed in strict mode at line 1, col 11",
  )
}

///|
test "class field with legacy octal numeric key" {
  let src =
    #|class C { 08 = 1; }
  expect_throw(
    src, "SyntaxError: Decimals with leading zeros are not allowed in strict mode at line 1, col 11",
  )
}

///|
test "destructuring pattern key with legacy octal escape" {
  let src =
    #|"use strict"; let { "\1": x } = {};
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 1, col 21",
  )
}

///|
test "destructuring pattern key with non-octal-decimal" {
  let src =
    #|"use strict"; let { 08: x } = {};
  expect_throw(
    src, "SyntaxError: Decimals with leading zeros are not allowed in strict mode at line 1, col 21",
  )
}

///|
test "new Function with strict directive and legacy octal" {
  let src =
    #|new Function('"use strict"; "\\1"');
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 3, col 15",
  )
}

///|
test "new GeneratorFunction with strict directive and legacy octal" {
  let src =
    #|let GF = (function*(){}).constructor;
    #|new GF('"use strict"; "\\1"');
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 3, col 15",
  )
}

///|
test "new AsyncFunction with strict directive and legacy octal" {
  let src =
    #|let AF = (async function(){}).constructor;
    #|new AF('"use strict"; "\\1"');
  expect_throw(
    src, "SyntaxError: Octal escape sequences are not allowed in strict mode at line 3, col 15",
  )
}

///|
test "new Function rejects duplicate params under strict directive" {
  let src =
    #|new Function('a', 'a', '"use strict";');
  expect_throw(
    src, "SyntaxError: Duplicate parameter name not allowed in this context",
  )
}

///|
test "new Function rejects 'eval' param under strict directive" {
  let src =
    #|new Function('eval', '"use strict"; return eval;');
  expect_throw(src, "SyntaxError: Unexpected eval or arguments in strict mode")
}

///|
test "new Function rejects 'arguments' param under strict directive" {
  let src =
    #|new Function('arguments', '"use strict"; return arguments;');
  expect_throw(src, "SyntaxError: Unexpected eval or arguments in strict mode")
}

///|
test "new Function rejects 'use strict' with non-simple params (default)" {
  let src =
    #|new Function('a = 1', '"use strict";');
  expect_throw(
    src, "SyntaxError: Illegal 'use strict' directive in function with non-simple parameter list",
  )
}

///|
test "new Function rejects 'use strict' with non-simple params (rest)" {
  let src =
    #|new Function('...a', '"use strict";');
  expect_throw(
    src, "SyntaxError: Illegal 'use strict' directive in function with non-simple parameter list",
  )
}

///|
test "new GeneratorFunction rejects duplicate params under strict" {
  let src =
    #|let GF = (function*(){}).constructor;
    #|new GF('a', 'a', '"use strict";');
  expect_throw(
    src, "SyntaxError: Duplicate parameter name not allowed in this context",
  )
}

///|
test "new AsyncFunction rejects 'eval' param under strict" {
  let src =
    #|let AF = (async function(){}).constructor;
    #|new AF('eval', '"use strict";');
  expect_throw(src, "SyntaxError: Unexpected eval or arguments in strict mode")
}

///|
test "new Function allows duplicate params in sloppy mode" {
  let src =
    #|var f = new Function('a', 'a', 'return a;');
  let output = run_output(src + "\nconsole.log(f(1, 2));")
  json_inspect(output, content=["2"])
}

// ----- ES262 §19.2.1.1 PerformEval early-error checks -----
//
// These cover the "Expected SyntaxError but got ReferenceError" cluster:
// the eval source contains a forbidden construct (super(), super.x,
// new.target, arguments) for the surrounding context. Per spec, the
// SyntaxError must fire BEFORE any side effects of the eval body.
// Behavior cross-checked against V8 (Node v24.14.1, 2026-05-10).

///|
test "direct eval in non-derived function: super() rejected" {
  let src =
    #|var executed = false;
    #|function f() { eval("executed = true; super();"); }
    #|try { f(); } catch (e) { /* expected */ }
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

///|
test "direct eval in plain function: super.x rejected" {
  let src =
    #|var executed = false;
    #|function f() { eval("executed = true; super.x;"); }
    #|try { f(); } catch (e) {}
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

///|
test "direct eval in derived constructor: super() allowed" {
  let src =
    #|class B { constructor() { this.tag = 'B'; } }
    #|class D extends B {
    #|  constructor() { eval("super();"); }
    #|}
    #|new D().tag
  let result = run(src)
  expect_result(result, "B")
}

///|
test "direct eval in method: super.x allowed" {
  let src =
    #|class B { foo() { return 'B.foo'; } }
    #|class D extends B {
    #|  bar() { return eval("super.foo()"); }
    #|}
    #|new D().bar()
  let result = run(src)
  expect_result(result, "B.foo")
}

///|
test "direct eval in class field initializer: arguments rejected" {
  let src =
    #|var executed = false;
    #|class C { x = eval("executed = true; arguments;"); }
    #|try { new C(); } catch (e) {}
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

///|
test "direct eval in class field initializer: super.x allowed" {
  let src =
    #|class B { foo() { return 'B.foo'; } }
    #|class D extends B { x = eval("super.foo()"); }
    #|new D().x
  let result = run(src)
  expect_result(result, "B.foo")
}

///|
test "direct eval in class field initializer: super() rejected" {
  let src =
    #|var executed = false;
    #|class B { constructor() {} }
    #|class D extends B { x = eval("executed = true; super();"); }
    #|try { new D(); } catch (e) {}
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

///|
test "direct eval in class field initializer: new.target allowed (returns undefined)" {
  let src =
    #|class C { x = eval("new.target === undefined"); }
    #|new C().x
  let result = run(src)
  expect_result(result, "true")
}

///|
test "direct eval at top-level: new.target rejected" {
  let src =
    #|var executed = false;
    #|try { eval("executed = true; new.target;"); } catch (e) {}
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

///|
test "indirect eval: super() rejected" {
  let src =
    #|var executed = false;
    #|class B { constructor() {} }
    #|class D extends B {
    #|  constructor() { super(); var ie = (0, eval); try { ie("executed = true; super();"); } catch (e) {} }
    #|}
    #|new D();
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

///|
test "indirect eval: arguments OK (no class-field context)" {
  // (0,eval)('arguments') should not throw SyntaxError — it should fail at
  // runtime as a ReferenceError because indirect eval has no surrounding
  // function context. This proves we're not over-throwing.
  let src =
    #|var caught;
    #|try { (0, eval)("arguments"); } catch (e) { caught = e.constructor.name; }
    #|caught
  let result = run(src)
  expect_result(result, "ReferenceError")
}

///|
test "direct eval: arguments inside regular function is fine" {
  // Regular function context binds `arguments` itself; eval('arguments') just
  // reads it. Should not be rejected by our class-field-init guard.
  let src =
    #|function f() { return eval("arguments[0]"); }
    #|f(42)
  let result = run(src)
  expect_result(result, "42")
}

///|
test "eval source containing super() inside a nested function does NOT trigger" {
  // Contains stops at non-arrow function boundaries. The nested function
  // body's super() is THAT function's concern, not eval's outer context.
  let src =
    #|var executed = false;
    #|function f() {
    #|  eval("executed = true; function inner() { super(); }");
    #|}
    #|f();
    #|executed
  let result = run(src)
  expect_result(result, "true")
}

///|
test "eval source: super.x inside a nested arrow IS visible (transparent)" {
  // Arrows are transparent for super, so super.x inside an arrow inside the
  // eval body still demands inMethod for the eval's outer context.
  let src =
    #|var executed = false;
    #|function f() {
    #|  try { eval("executed = true; (() => super.x)();"); } catch (e) {}
    #|}
    #|f();
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

// Regression coverage for Codex P2 (PR #100): arrow PARAMETER defaults
// also live in surrounding scope, so super/new.target/arguments inside
// `((x = forbidden) => 0)` must trigger the same Contains check.

///|
test "eval source: super.x in arrow param default rejected (Codex catch)" {
  // `function f() { eval('((x = super.x) => 0)') }` — V8 SyntaxError
  let src =
    #|var executed = false;
    #|function f() {
    #|  try { eval("executed = true; ((x = super.x) => 0)"); } catch (e) {}
    #|}
    #|f();
    #|executed
  let result = run(src)
  expect_result(result, "false")
}

///|
test "eval source: arguments in arrow param default rejected in field init" {
  // `class C { y = eval('((x = arguments) => 0)') }` — V8 SyntaxError
  let src =
    #|var executed = false;
    #|class C { y = (function () {
    #|  try { eval("executed = true; ((x = arguments) => 0)"); } catch (e) {}
    #|  return 1;
    #|})(); }
  // Class field init runs `eval` via the IIFE wrapper so we can observe
  // executed without bubbling. (We can't put `var executed` inside the
  // field init.) Top-level executed should remain false because the
  // SyntaxError fires before the eval body runs.
  let result = run(src + "\nexecuted")
  expect_result(result, "false")
}

///|
test "eval source: arguments in destructuring arrow default rejected in field init" {
  // `class C { y = eval('(({x = arguments}) => 0)') }` — V8 SyntaxError
  let src =
    #|var executed = false;
    #|class C { y = (function () {
    #|  try { eval("executed = true; (({x = arguments}) => 0)"); } catch (e) {}
    #|  return 1;
    #|})(); }
  let result = run(src + "\nexecuted")
  expect_result(result, "false")
}

///|
test "eval source: arguments in array destructuring arrow default rejected" {
  let src =
    #|var executed = false;
    #|class C { y = (function () {
    #|  try { eval("executed = true; (([a = arguments]) => 0)"); } catch (e) {}
    #|  return 1;
    #|})(); }
  let result = run(src + "\nexecuted")
  expect_result(result, "false")
}

///|
test "eval source: arrow param default with no forbidden refs is fine" {
  // Negative regression — make sure we didn't break ordinary defaults.
  let src =
    #|function f() { return eval("((x = 42) => x)()") }
    #|f()
  let result = run(src)
  expect_result(result, "42")
}

///|
test "Date.prototype.toJSON propagates ToPrimitive abrupt completion" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var obj = {
    #|  get valueOf() {
    #|    throw new MyError();
    #|  }
    #|};
    #|try {
    #|  Date.prototype.toJSON.call(obj);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError"])
}

///|
test "String.raw propagates raw getter abrupt completion" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var template = {
    #|  get raw() {
    #|    throw new MyError();
    #|  }
    #|};
    #|try {
    #|  String.raw(template);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError"])
}

///|
test "Object.assign propagates target setter abrupt completion" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var target = {};
    #|Object.defineProperty(target, "attr", {
    #|  set: function(_) {
    #|    throw new MyError();
    #|  }
    #|});
    #|try {
    #|  Object.assign(target, { attr: 1 });
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError"])
}

///|
test "Array.from constructs custom iterable result before reading iterator result" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|function C() {
    #|  throw new MyError();
    #|}
    #|var items = {};
    #|items[Symbol.iterator] = function() {};
    #|try {
    #|  Array.from.call(C, items);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError"])
}

///|
test "iterator value accessors throw before advancing" {
  let src =
    #|function MyError(name) { this.name = name; }
    #|function check(name, action) {
    #|  var count = 0;
    #|  var iter = {};
    #|  var poisoned = Object.defineProperty({}, "value", {
    #|    get: function() { throw new MyError(name); }
    #|  });
    #|  iter[Symbol.iterator] = function() {
    #|    return {
    #|      next: function() {
    #|        count += 1;
    #|        if (count > 1) { throw new MyError(name + " advanced"); }
    #|        return poisoned;
    #|      }
    #|    };
    #|  };
    #|  try {
    #|    action(iter);
    #|  } catch (e) {
    #|    console.log(e.name + ":" + count);
    #|  }
    #|}
    #|check("spread", function(iter) { (function() {})(...iter); });
    #|check("arrayFrom", function(iter) { Array.from(iter); });
    #|check("destructure", function(iter) { var [...x] = iter; });
    #|check("forOf", function(iter) { for (var x of iter) {} });
  let output = run_output(src)
  json_inspect(output, content=[
    "spread:1", "arrayFrom:1", "destructure:1", "forOf:1",
  ])
}

///|
test "destructuring elisions skip IteratorValue" {
  let src =
    #|function makeIter(label) {
    #|  var count = 0;
    #|  var iter = {};
    #|  iter[Symbol.iterator] = function() {
    #|    return {
    #|      next: function() {
    #|        count = count + 1;
    #|        if (count === 1) {
    #|          return Object.defineProperty({ done: false }, "value", {
    #|            get: function() { throw new Error(label + " elision"); }
    #|          });
    #|        }
    #|        return { done: false, value: count };
    #|      },
    #|      return: function() { return {}; }
    #|    };
    #|  };
    #|  return iter;
    #|}
    #|var [, x] = makeIter("binding");
    #|console.log("binding:" + x);
    #|var y;
    #|[, y] = makeIter("assignment");
    #|console.log("assignment:" + y);
  let output = run_output(src)
  json_inspect(output, content=["binding:2", "assignment:2"])
}

///|
test "destructuring closes iterator when element binding throws" {
  let src =
    #|var log = [];
    #|function makeIter(label, value) {
    #|  var iter = {};
    #|  iter[Symbol.iterator] = function() {
    #|    return {
    #|      next: function() { return { done: false, value: value }; },
    #|      return: function() { log.push(label + ":return"); return {}; }
    #|    };
    #|  };
    #|  return iter;
    #|}
    #|function fail(label) { throw new Error(label); }
    #|try {
    #|  var [x = fail("binding")] = makeIter("binding", undefined);
    #|} catch (e) {
    #|  log.push("binding:" + e.message);
    #|}
    #|try {
    #|  var target;
    #|  [target = fail("assignment")] = makeIter("assignment", undefined);
    #|} catch (e) {
    #|  log.push("assignment:" + e.message);
    #|}
    #|console.log(log.join("|"));
  let output = run_output(src)
  json_inspect(output, content=[
    "binding:return|binding:binding|assignment:return|assignment:assignment",
  ])
}

///|
test "Array.from closes only mapper abrupts during iterator consumption" {
  let src =
    #|var log = [];
    #|function makeIter(label, mode) {
    #|  var iter = {};
    #|  iter[Symbol.iterator] = function() {
    #|    return {
    #|      next: function() {
    #|        if (mode === "step") { throw new Error(label); }
    #|        if (mode === "done") {
    #|          return Object.defineProperty({}, "done", {
    #|            get: function() { throw new Error(label); }
    #|          });
    #|        }
    #|        if (mode === "value") {
    #|          return Object.defineProperty({ done: false }, "value", {
    #|            get: function() { throw new Error(label); }
    #|          });
    #|        }
    #|        return { done: false, value: 1 };
    #|      },
    #|      return: function() { log.push(label + ":return"); return {}; }
    #|    };
    #|  };
    #|  return iter;
    #|}
    #|try {
    #|  Array.from(makeIter("step", "step"));
    #|} catch (e) {
    #|  log.push("step:" + e.message);
    #|}
    #|try {
    #|  Array.from(makeIter("done", "done"));
    #|} catch (e) {
    #|  log.push("done:" + e.message);
    #|}
    #|try {
    #|  Array.from(makeIter("value", "value"));
    #|} catch (e) {
    #|  log.push("value:" + e.message);
    #|}
    #|try {
    #|  Array.from(makeIter("map", "ok"), function() { throw new Error("mapped"); });
    #|} catch (e) {
    #|  log.push("map:" + e.message);
    #|}
    #|console.log(log.join("|"));
  let output = run_output(src)
  json_inspect(output, content=[
    "step:step|done:done|value:value|map:return|map:mapped",
  ])
}

///|
test "Map and Set propagate IteratorValue abrupts without closing" {
  let src =
    #|var log = [];
    #|function makeIter(label) {
    #|  var iter = {};
    #|  iter[Symbol.iterator] = function() {
    #|    return {
    #|      next: function() {
    #|        return Object.defineProperty({ done: false }, "value", {
    #|          get: function() { throw new Error(label); }
    #|        });
    #|      },
    #|      return: function() { log.push(label + ":return"); return {}; }
    #|    };
    #|  };
    #|  return iter;
    #|}
    #|try {
    #|  new Map(makeIter("map"));
    #|} catch (e) {
    #|  log.push("map:" + e.message);
    #|}
    #|try {
    #|  new Set(makeIter("set"));
    #|} catch (e) {
    #|  log.push("set:" + e.message);
    #|}
    #|console.log(log.join("|"));
  let output = run_output(src)
  json_inspect(output, content=["map:map|set:set"])
}

///|
test "Map and Set bracket access uses prototype accessors" {
  let src =
    #|var m = new Map([[1, 2]]);
    #|var s = new Set([1, 2]);
    #|console.log(m["size"]);
    #|console.log(s["size"]);
    #|var seen;
    #|Object.defineProperty(Map.prototype, "answer", {
    #|  configurable: true,
    #|  get: function() { seen = this; return 42; }
    #|});
    #|console.log(m["answer"]);
    #|console.log(seen === m);
  let output = run_output(src)
  json_inspect(output, content=["1", "2", "42", "true"])
}

///|
test "Map.prototype.forEach validates callback and visits readded keys" {
  let src =
    #|try {
    #|  new Map().forEach({});
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var map = new Map();
    #|map.set("foo", 0);
    #|map.set("bar", 1);
    #|var count = 0;
    #|var results = [];
    #|map.forEach(function(value, key) {
    #|  if (count === 0) {
    #|    map.delete("foo");
    #|    map.set("foo", "baz");
    #|  }
    #|  results.push(key + ":" + value);
    #|  count++;
    #|});
    #|console.log(count);
    #|console.log(results.join("|"));
    #|console.log(map.size);
    #|var single = new Map([["solo", 0]]);
    #|var singleCount = 0;
    #|var singleResults = [];
    #|single.forEach(function(value, key) {
    #|  singleResults.push(key + ":" + value);
    #|  if (singleCount === 0) {
    #|    single.clear();
    #|    single.set("solo", 1);
    #|  }
    #|  singleCount++;
    #|});
    #|console.log(singleCount);
    #|console.log(singleResults.join("|"));
    #|var compacted = new Map([["a", 1], ["b", 2], ["c", 3]]);
    #|var compactedResults = [];
    #|compacted.forEach(function(value, key) {
    #|  compactedResults.push(key + ":" + value);
    #|  if (key === "b") {
    #|    compacted.delete("a");
    #|    compacted.delete("b");
    #|  }
    #|});
    #|console.log(compactedResults.join("|"));
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError", "3", "foo:0|bar:1|foo:baz", "2", "2", "solo:0|solo:1", "a:1|b:2|c:3",
  ])
}

///|
test "Map.groupBy uses iterator protocol" {
  let src =
    #|var bad = {};
    #|bad[Symbol.iterator] = undefined;
    #|try {
    #|  Map.groupBy(bad, function() { throw new Error("unreachable"); });
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|
    #|var throwing = {};
    #|throwing[Symbol.iterator] = function() { return throwing; };
    #|throwing.next = function() { throw new Error("next"); };
    #|try {
    #|  Map.groupBy(throwing, function() { return "key"; });
    #|} catch (e) {
    #|  console.log(e.message);
    #|}
    #|
    #|var valueThrowing = {};
    #|var closed = false;
    #|valueThrowing[Symbol.iterator] = function() { return valueThrowing; };
    #|valueThrowing.next = function() {
    #|  var result = { done: false };
    #|  Object.defineProperty(result, "value", {
    #|    get: function() { throw new Error("value"); }
    #|  });
    #|  return result;
    #|};
    #|valueThrowing.return = function() { closed = true; return {}; };
    #|try {
    #|  Map.groupBy(valueThrowing, function() { return "key"; });
    #|} catch (e) {
    #|  console.log(e.message);
    #|}
    #|console.log(String(closed));
    #|
    #|var proxied = {};
    #|proxied[Symbol.iterator] = new Proxy(function() {
    #|  return [1, 2][Symbol.iterator]();
    #|}, {});
    #|var proxiedMap = Map.groupBy(proxied, function(value) { return value % 2; });
    #|console.log(Array.from(proxiedMap.keys()).join("|"));
    #|console.log(proxiedMap.get(1)[0] + "|" + proxiedMap.get(0)[0]);
    #|
    #|var map = Map.groupBy("\uD83E\uDD70\uD83D\uDCA9\uD83D\uDE4F\uD83D\uDE08", function(char) {
    #|  return char < "\uD83D\uDE4F" ? "before" : "after";
    #|});
    #|console.log(Array.from(map.keys()).join("|"));
    #|console.log(map.get("before").length);
    #|console.log(map.get("before")[0].length + "|" + map.get("before")[1].length);
    #|console.log(map.get("after").length);
    #|console.log(map.get("after")[0].length + "|" + map.get("after")[1].length);
  let output = run_output(src)
  json_inspect(output, content=[
    "TypeError", "next", "value", "false", "1|0", "1|2", "after|before", "2", "2|2",
    "2", "2|2",
  ])
}

///|
test "Map and Set constructors honor accessor adders" {
  let src =
    #|var mapGetterCalls = 0;
    #|var mapAdderCalls = 0;
    #|var mapReceiver;
    #|Object.defineProperty(Map.prototype, "set", {
    #|  configurable: true,
    #|  get: function() {
    #|    mapGetterCalls = mapGetterCalls + 1;
    #|    return function(k, v) {
    #|      mapAdderCalls = mapAdderCalls + 1;
    #|      mapReceiver = this;
    #|    };
    #|  }
    #|});
    #|var m = new Map([[1, 2], [3, 4]]);
    #|console.log(mapGetterCalls);
    #|console.log(mapAdderCalls);
    #|console.log(mapReceiver === m);
    #|console.log(m.size);
    #|
    #|var setGetterCalls = 0;
    #|var setAdderCalls = 0;
    #|var setReceiver;
    #|Object.defineProperty(Set.prototype, "add", {
    #|  configurable: true,
    #|  get: function() {
    #|    setGetterCalls = setGetterCalls + 1;
    #|    return function(v) {
    #|      setAdderCalls = setAdderCalls + 1;
    #|      setReceiver = this;
    #|    };
    #|  }
    #|});
    #|var s = new Set([1, 2]);
    #|console.log(setGetterCalls);
    #|console.log(setAdderCalls);
    #|console.log(setReceiver === s);
    #|console.log(s.size);
    #|
    #|var err = new Error("set getter");
    #|var iterated = false;
    #|Object.defineProperty(Map.prototype, "set", {
    #|  configurable: true,
    #|  get: function() { throw err; }
    #|});
    #|var iterable = {};
    #|iterable[Symbol.iterator] = function() {
    #|  iterated = true;
    #|  return [][Symbol.iterator]();
    #|};
    #|try {
    #|  new Map(iterable);
    #|} catch (e) {
    #|  console.log(e === err);
    #|  console.log(iterated);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "1", "2", "true", "0", "1", "2", "true", "0", "true", "false",
  ])
}

///|
test "Map and Set close iterators when constructor adders throw" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var mapCloseCount = 0;
    #|var mapIterable = {};
    #|mapIterable[Symbol.iterator] = function() {
    #|  return {
    #|    next: function() { return { value: [], done: false }; },
    #|    return: function() { mapCloseCount += 1; return {}; }
    #|  };
    #|};
    #|Map.prototype.set = function() { throw new MyError(); };
    #|try {
    #|  new Map(mapIterable);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(mapCloseCount);
    #|}
    #|var setCloseCount = 0;
    #|var setIterable = {};
    #|setIterable[Symbol.iterator] = function() {
    #|  return {
    #|    next: function() { return { value: null, done: false }; },
    #|    return: function() { setCloseCount += 1; return {}; }
    #|  };
    #|};
    #|Set.prototype.add = function() { throw new MyError(); };
    #|try {
    #|  new Set(setIterable);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(setCloseCount);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError", "1", "MyError", "1"])
}

///|
test "Weak collections close iterators when constructor adders throw" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var weakMapCloseCount = 0;
    #|var weakMapIterable = {};
    #|weakMapIterable[Symbol.iterator] = function() {
    #|  return {
    #|    next: function() {
    #|      return { value: [], done: false };
    #|    },
    #|    return: function() {
    #|      weakMapCloseCount += 1;
    #|    }
    #|  };
    #|};
    #|WeakMap.prototype.set = function() {
    #|  throw new MyError();
    #|};
    #|try {
    #|  new WeakMap(weakMapIterable);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(weakMapCloseCount);
    #|}
    #|var weakSetCloseCount = 0;
    #|var weakSetIterable = {};
    #|weakSetIterable[Symbol.iterator] = function() {
    #|  return {
    #|    next: function() {
    #|      return { value: null, done: false };
    #|    },
    #|    return: function() {
    #|      weakSetCloseCount += 1;
    #|    }
    #|  };
    #|};
    #|WeakSet.prototype.add = function() {
    #|  throw new MyError();
    #|};
    #|try {
    #|  new WeakSet(weakSetIterable);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(weakSetCloseCount);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError", "1", "MyError", "1"])
}

///|
test "TypedArray.from propagates source abrupt completions" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var TypedArray = Object.getPrototypeOf(Int8Array);
    #|var lengthGetter = {};
    #|Object.defineProperty(lengthGetter, "length", {
    #|  get: function() { throw new MyError(); }
    #|});
    #|try {
    #|  TypedArray.from(lengthGetter);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var lengthValueOf = { length: {
    #|  valueOf: function() { throw new MyError(); }
    #|} };
    #|try {
    #|  TypedArray.from(lengthValueOf);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var iteratorGetter = {};
    #|Object.defineProperty(iteratorGetter, Symbol.iterator, {
    #|  get: function() { throw new MyError(); }
    #|});
    #|try {
    #|  TypedArray.from(iteratorGetter);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var iteratorCall = {};
    #|iteratorCall[Symbol.iterator] = function() { throw new MyError(); };
    #|try {
    #|  TypedArray.from(iteratorCall);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var iteratorNext = {};
    #|iteratorNext[Symbol.iterator] = function() {
    #|  return { next: function() { throw new MyError(); } };
    #|};
    #|try {
    #|  TypedArray.from(iteratorNext);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var iteratorValue = {};
    #|iteratorValue[Symbol.iterator] = function() {
    #|  return { next: function() {
    #|    var result = {};
    #|    Object.defineProperty(result, "value", {
    #|      get: function() { throw new MyError(); }
    #|    });
    #|    return result;
    #|  } };
    #|};
    #|try {
    #|  TypedArray.from(iteratorValue);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "MyError", "MyError", "MyError", "MyError", "MyError", "MyError",
  ])
}

///|
test "TypedArray.from validates receiver before reading source" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var TypedArray = Object.getPrototypeOf(Int8Array);
    #|var touched = false;
    #|var source = {};
    #|Object.defineProperty(source, Symbol.iterator, {
    #|  get: function() {
    #|    touched = true;
    #|    throw new MyError();
    #|  }
    #|});
    #|try {
    #|  TypedArray.from.call({}, source);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(touched);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError", "false"])
}

///|
test "TypedArray.from rejects non-callable mapFn without coercion" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var TypedArray = Object.getPrototypeOf(Int8Array);
    #|var touched = false;
    #|var mapFn = {
    #|  toString: function() {
    #|    touched = true;
    #|    throw new MyError();
    #|  }
    #|};
    #|try {
    #|  TypedArray.from.call(Int8Array, [1], mapFn);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(touched);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["TypeError", "false"])
}

///|
test "TypedArray.from is inherited and validates custom constructor result" {
  let src =
    #|var TypedArray = Object.getPrototypeOf(Int8Array);
    #|console.log(Int8Array.from === TypedArray.from);
    #|console.log(Int8Array.hasOwnProperty("from"));
    #|var called = 0;
    #|function C(len) {
    #|  called++;
    #|  return new Int8Array(len);
    #|}
    #|var r = Int8Array.from.call(C, [7, 8]);
    #|console.log(r.length);
    #|console.log(r[0]);
    #|console.log(r[1]);
    #|console.log(called);
    #|try {
    #|  Int8Array.from.call(function() {}, []);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  Int8Array.from.call(function() { return new Int8Array(1); }, [1, 2]);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  Int8Array.from.call(function() { return new Int8Array(1); }, { length: 2 });
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=[
    "true", "false", "2", "7", "8", "1", "TypeError", "TypeError", "TypeError",
  ])
}

///|
test "Weak collection constructors check adders before iterables" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var weakMapTouched = false;
    #|var weakMapIterable = {};
    #|Object.defineProperty(weakMapIterable, Symbol.iterator, {
    #|  get: function() {
    #|    weakMapTouched = true;
    #|    throw new MyError();
    #|  }
    #|});
    #|var originalWeakMapSet = WeakMap.prototype.set;
    #|WeakMap.prototype.set = 1;
    #|try {
    #|  new WeakMap(weakMapIterable);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(weakMapTouched);
    #|}
    #|WeakMap.prototype.set = originalWeakMapSet;
    #|var weakSetTouched = false;
    #|var weakSetIterable = {};
    #|Object.defineProperty(weakSetIterable, Symbol.iterator, {
    #|  get: function() {
    #|    weakSetTouched = true;
    #|    throw new MyError();
    #|  }
    #|});
    #|var originalWeakSetAdd = WeakSet.prototype.add;
    #|WeakSet.prototype.add = 1;
    #|try {
    #|  new WeakSet(weakSetIterable);
    #|} catch (e) {
    #|  console.log(e.name);
    #|  console.log(weakSetTouched);
    #|}
    #|WeakSet.prototype.add = originalWeakSetAdd;
  let output = run_output(src)
  json_inspect(output, content=["TypeError", "false", "TypeError", "false"])
}

///|
test "TypedArray constructor consumes iterable sources before reduce callbacks" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|var iterable = {};
    #|iterable[Symbol.iterator] = function() {
    #|  return [1, 2][Symbol.iterator]();
    #|};
    #|var sample = new Float64Array(iterable);
    #|try {
    #|  sample.reduce(function() { throw new MyError(); });
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  sample.reduce(function() { throw new MyError(); }, 0);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  sample.reduceRight(function() { throw new MyError(); });
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  sample.reduceRight(function() { throw new MyError(); }, 0);
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
  let output = run_output(src)
  json_inspect(output, content=["MyError", "MyError", "MyError", "MyError"])
}

///|
test "TypedArray.prototype.join coerces separator and treats detached elements as empty" {
  let src =
    #|function MyError() { this.name = "MyError"; }
    #|MyError.prototype = Object.create(Error.prototype);
    #|console.log([1, 2, 3].join({ toString: function() { return "array"; } }));
    #|var sample = new Uint8Array([1, 2, 3]);
    #|console.log(sample.join({ toString: function() { return "foo"; } }));
    #|console.log(sample.join({
    #|  toString: undefined,
    #|  valueOf: function() { return "bar"; }
    #|}));
    #|try {
    #|  new Uint8Array(0).join(Symbol("s"));
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|try {
    #|  new Uint8Array(0).join({ toString: function() { throw new MyError(); } });
    #|} catch (e) {
    #|  console.log(e.name);
    #|}
    #|var detached = new Uint8Array([1, 2, 3]);
    #|console.log(detached.join({
    #|  toString: function() {
    #|    $262.detachArrayBuffer(detached.buffer);
    #|    return ",";
    #|  }
    #|}));
  let output = run_output(src)
  json_inspect(output, content=[
    "1array2array3", "1foo2foo3", "1bar2bar3", "TypeError", "MyError", ",,",
  ])
}

///|
test "tagged template strings object inherits Array methods" {
  let src =
    #|function tag(strings) {
    #|  console.log(strings.map(function(s) { return s; }).join("|"));
    #|  console.log(String.raw({ raw: strings.raw }));
    #|}
    #|tag`a${1}b`;
    #|console.log(String.raw`x${1}y`);
  let output = run_output(src)
  json_inspect(output, content=["a|b", "ab", "x1y"])
}

///|
test "tagged template objects are cached and frozen" {
  let src =
    #|var first;
    #|var firstRaw;
    #|function tag(strings) {
    #|  if (!first) {
    #|    first = strings;
    #|    firstRaw = strings.raw;
    #|  } else {
    #|    console.log(strings === first);
    #|    console.log(strings.raw === firstRaw);
    #|  }
    #|  strings[0] = "x";
    #|  strings.raw[0] = "y";
    #|  strings.raw = [];
    #|  console.log(strings[0] + "," + strings.raw[0] + "," + (strings.raw === firstRaw));
    #|  console.log(Object.isExtensible(strings) + "," + Object.isExtensible(strings.raw));
    #|}
    #|function run(value) { tag`a${value}b`; }
    #|run(1);
    #|run(2);
  let output = run_output(src)
  json_inspect(output, content=[
    "a,a,true", "false,false", "true", "true", "a,a,true", "false,false",
  ])
}

// ====== Stage 8: [[OwnPropertyKeys]] runtime-op migration equivalence ======
// These lock the CURRENT enumeration behavior preserved by routing
// Object.getOwnProperty{Names,Symbols,Descriptors} / defineProperties through
// the @runtime own-property-keys ops (own_property_keys.mbt).

///|
test "stage8 ownkeys: integer keys sort ascending before string keys" {
  let src =
    #|var o = {};
    #|o[2] = "a"; o["x"] = "b"; o[0] = "c"; o[1] = "d"; o["y"] = "e";
    #|console.log(Object.getOwnPropertyNames(o).join(","));
  let output = run_output(src)
  json_inspect(output, content=["0,1,2,x,y"])
}

///|
test "stage8 ownkeys: getOwnPropertySymbols returns only symbol keys" {
  let src =
    #|var s1 = Symbol("s1"); var s2 = Symbol("s2");
    #|var o = { a: 1 }; o[s1] = 2; o["b"] = 3; o[s2] = 4;
    #|var syms = Object.getOwnPropertySymbols(o);
    #|console.log(syms.length);
    #|console.log(syms.map(function(s) { return s.toString(); }).join(","));
  let output = run_output(src)
  json_inspect(output, content=["2", "Symbol(s1),Symbol(s2)"])
}

///|
test "stage8 ownkeys: sparse array names vs descriptors hole handling" {
  let src =
    #|var a = [1, , 3];
    #|console.log(Object.getOwnPropertyNames(a).join(","));
    #|console.log(Object.keys(Object.getOwnPropertyDescriptors(a)).join(","));
  let output = run_output(src)
  // Sparse array `[1, , 3]` has a hole at index 1. After the #336 enumerator
  // unification both paths route through the canonical OrdinaryOwnPropertyKeys
  // op, which omits the hole index per ES §10.4.2.1 / §10.1.11. Both emit
  // "0,2,length".
  json_inspect(output, content=["0,2,length", "0,2,length"])
}

///|
test "ownkeys #336: Reflect.ownKeys on sparse array with named + symbol keys" {
  // Reflect.ownKeys routes through the canonical OrdinaryOwnPropertyKeys op.
  // Order per ES §10.1.11: integer indices ascending (hole at 1 omitted),
  // then "length", then insertion-order string keys, then symbol keys.
  let src =
    #|var a = [1, , 3];
    #|a.foo = "x";
    #|var s = Symbol("s");
    #|a[s] = 1;
    #|console.log(Reflect.ownKeys(a).map(function (k) { return k.toString(); }).join(","));
  let output = run_output(src)
  json_inspect(output, content=["0,2,length,foo,Symbol(s)"])
}

///|
test "ownkeys #336: getOwnPropertyDescriptors on typedarray enumerates integer indices" {
  // TypedArrays carry own integer-indexed properties (backed by the buffer,
  // not bag.properties). `length` is a prototype accessor, not an own key.
  // The canonical op routes the descriptor snapshot through the typedarray
  // [[OwnPropertyKeys]] variant so the indices surface.
  let src =
    #|var ta = new Uint8Array([10, 20, 30]);
    #|console.log(Object.keys(Object.getOwnPropertyDescriptors(ta)).join(","));
    #|console.log(Object.getOwnPropertyNames(ta).join(","));
  let output = run_output(src)
  json_inspect(output, content=["0,1,2", "0,1,2"])
}

///|
test "Object.prototype.__lookupGetter__: data property on instance stops prototype chain" {
  // A data property on the instance shadows a getter on the prototype.
  // __lookupGetter__ must return undefined (spec §B.2.2.1 step 4b.ii) instead
  // of continuing to find the proto getter.
  let output = run_output(
    (
      #|var root = Object.defineProperty({}, 'x', { get: function() { return 1; } });
      #|var child = Object.create(root, { x: { value: 42 } });
      #|console.log(child.__lookupGetter__('x'));
      #|console.log(root.__lookupGetter__('x') !== undefined);
    ),
  )
  json_inspect(output, content=["undefined", "true"])
}

///|
test "Object.prototype.__lookupSetter__: data property on instance stops prototype chain" {
  let output = run_output(
    (
      #|var root = Object.defineProperty({}, 'x', { set: function(v) {} });
      #|var child = Object.create(root, { x: { value: 42 } });
      #|console.log(child.__lookupSetter__('x'));
      #|console.log(root.__lookupSetter__('x') !== undefined);
    ),
  )
  json_inspect(output, content=["undefined", "true"])
}

///|
test "String.prototype.replaceAll: global RegExp with Symbol.replace=undefined uses string path" {
  // When Symbol.replace is null/undefined, replaceAll converts searchValue to
  // string via ToString and searches for the literal string representation.
  // The IsRegExp check must still pass (customRE has 'g') without throwing.
  let output = run_output(
    (
      #|var re = /AB/g;
      #|Object.defineProperty(re, Symbol.replace, { value: undefined });
      #|var result = '--- /AB/g ---'.replaceAll(re, 'X');
      #|console.log(result);
    ),
  )
  json_inspect(output, content=["--- X ---"])
}

///|
test "String.prototype.replaceAll: non-global RegExp throws TypeError" {
  let output = run_output(
    (
      #|try {
      #|  'abc'.replaceAll(/a/, 'x');
      #|} catch (e) {
      #|  console.log(e instanceof TypeError);
      #|}
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "regex char class: \\uXXXX and \\xHH escapes decode correctly" {
  // Regression: \uXXXX inside [...] was decoded as literal 'u' causing
  // ranges like \u2000-\u200A to corrupt into ('-','u') = (0x2D-0x75)
  // which false-matched ASCII letters like 'f'.
  let output = run_output(
    (
      #|console.log(/[\u2000-\u200A]/.test('f'));     // false -- U+0066 not in range
      #|console.log(/[\u0041-\u005A]/.test('Z'));     // true -- Z = U+005A
      #|console.log(/[\u0041-\u005A]/.test('f'));     // false -- f = U+0066 > U+005A
      #|console.log(/[\u0066]/.test('f'));             // true -- U+0066 = f
      #|console.log(/[\x41-\x5A]/.test('Z'));         // true -- \xHH range A-Z
      #|console.log(/[\x41-\x5A]/.test('f'));         // false -- f > Z via \xHH
    ),
  )
  json_inspect(output, content=[
    "false", "true", "false", "true", "true", "false",
  ])
}

///|
test "regex char class: Annex B identity escape for malformed \\x and \\u" {
  // In non-Unicode mode, \x without 2 valid hex digits is an identity escape
  // for 'x'; \u with fewer than 4 hex digits is an identity escape for 'u'.
  let output = run_output(
    (
      #|console.log(/[\x]/.test('x'));   // true — identity escape
      #|console.log(/[\u]/.test('u'));   // true — identity escape
      #|console.log(/[\u1]/.test('u'));  // true — 'u' identity + '1' separate
      #|console.log(/[\u1]/.test('1'));  // true — '1' is in the class
      #|console.log(/[\x4]/.test('x'));  // true — 'x' identity + '4' separate
      #|console.log(/[\x4]/.test('4'));  // true — '4' is in the class
    ),
  )
  json_inspect(output, content=["true", "true", "true", "true", "true", "true"])
}

///|
test "regex char class: \\0 null escape with following decimal digits" {
  // \0 not followed by digit: NUL
  // \00, \07: consumed as 2-digit octal (non-unicode)
  // \000:     consumed as 3-digit octal (non-unicode)
  // \08:      NUL + '8' as separate class char (8 is not octal)
  // \00 in unicode mode: SyntaxError (decimal escape not allowed)
  let output = run_output(
    (
      #|console.log(/[\0]/.test('\x00'));       // true -- plain \0 = NUL
      #|console.log(/[\00]/.test('\x00'));      // true -- octal \00 = NUL
      #|console.log(/[\00]/.test('0'));         // false -- '0' consumed by \00
      #|console.log(/[\07]/.test('\x07'));      // true -- octal \07 = BEL
      #|console.log(/[\000]/.test('\x00'));     // true -- 3-digit octal \000 = NUL
      #|console.log(/[\000]/.test('0'));        // false -- '0' consumed
      #|console.log(/[\08]/.test('\x00'));      // true -- \0=NUL; 8 not octal
      #|console.log(/[\08]/.test('8'));         // true -- '8' is separate class char
      #|try { /[\00]/u; console.log('no error') } catch(e) { console.log(e instanceof SyntaxError) }
    ),
  )
  json_inspect(output, content=[
    "true", "true", "false", "true", "true", "false", "true", "true", "true",
  ])
}

///|
test "regex char class: unicode mode strict errors for malformed \\x and \\u" {
  // In Unicode mode (/u flag), malformed \x and \u must throw SyntaxError.
  let output = run_output(
    (
      #|var threw = 0;
      #|try { /[\x]/u }   catch(e) { if (e instanceof SyntaxError) threw++ }
      #|try { /[\u]/u }   catch(e) { if (e instanceof SyntaxError) threw++ }
      #|try { /[\u1]/u }  catch(e) { if (e instanceof SyntaxError) threw++ }
      #|try { /[\x4]/u }  catch(e) { if (e instanceof SyntaxError) threw++ }
      #|console.log(threw);   // 4 -- all four must throw
      #|try { /[\xA0]/u; console.log(true) } catch(e) { console.log(false) }
      #|try { /[A]/u; console.log(true) } catch(e) { console.log(false) }
    ),
  )
  json_inspect(output, content=["4", "true", "true"])
}

///|
test "regex char class: non-unicode surrogate \\u escapes are not folded" {
  // In non-unicode mode, \uD83D and \uDE00 inside [...] are separate code-unit atoms;
  // parse_class_single_escape must not fold adjacent surrogate \uXXXX escapes.
  let output = run_output(
    (
      #|// Escape form: \uD83D and \uDE00 as two separate class members
      #|console.log(/[\uD83D\uDE00]/.test('\uD83D')); // true -- high surrogate
      #|console.log(/[\uD83D\uDE00]/.test('\uDE00')); // true -- low surrogate
      #|// Unicode mode: class folds to scalar U+1F600; surrogates not in class
      #|console.log(/[\uD83D\uDE00]/u.test('\uD83D')); // false
      #|console.log(/[\uD83D\uDE00]/u.test('\uDE00')); // false
      #|// \u{41} in non-unicode mode: { is not a hex digit, so identity escape
      #|console.log(/[\u{41}]/.test('u'));  // true -- identity escape
      #|console.log(/[\u{41}]/.test('A'));  // false
    ),
  )
  json_inspect(output, content=[
    "true", "true", "false", "false", "true", "false",
  ])
}

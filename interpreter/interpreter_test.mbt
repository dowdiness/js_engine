///|
fn run_js(source : String) -> (Array[String], @interpreter.Value) raise Error {
  let interp = @interpreter.Interpreter::new()
  let prog = @parser.parse(source)
  let result = interp.run(prog.stmts)
  (interp.output, result)
}

///|
fn run_output(source : String) -> Array[String] raise Error {
  let (output, _) = run_js(source)
  output
}

///|
test "arithmetic" {
  let (_, result) = run_js("1 + 2 * 3")
  inspect(result, content="7")
}

///|
test "variables" {
  let (_, result) = run_js("let x = 10; let y = 20; x + y")
  inspect(result, content="30")
}

///|
test "string concatenation" {
  let (_, result) = run_js("\"hello\" + \" \" + \"world\"")
  inspect(result, content="hello world")
}

///|
test "console.log" {
  let output = run_output("console.log(\"hello\"); console.log(1 + 2)")
  inspect(output, content="[\"hello\", \"3\"]")
}

///|
test "if/else true" {
  let (_, result) = run_js("let x = 10; if (x > 5) { 1 } else { 2 }")
  inspect(result, content="1")
}

///|
test "if/else false" {
  let (_, result) = run_js("let x = 3; if (x > 5) { 1 } else { 2 }")
  inspect(result, content="2")
}

///|
test "while loop" {
  let output = run_output(
    "let i = 0; while (i < 3) { console.log(i); i = i + 1 }",
  )
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "for loop" {
  let output = run_output(
    "for (let i = 0; i < 3; i = i + 1) { console.log(i) }",
  )
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "function declaration and call" {
  let (_, result) = run_js("function add(a, b) { return a + b; } add(3, 4)")
  inspect(result, content="7")
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
  inspect(output, content="[\"1\", \"2\", \"3\"]")
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
  inspect(output, content="[\"55\"]")
}

///|
test "ternary expression" {
  let (_, result) = run_js("let x = 5; x > 3 ? \"big\" : \"small\"")
  inspect(result, content="big")
}

///|
test "typeof" {
  let output = run_output(
    "console.log(typeof 42); console.log(typeof \"hi\"); console.log(typeof true); console.log(typeof null); console.log(typeof undefined)",
  )
  inspect(
    output,
    content="[\"number\", \"string\", \"boolean\", \"object\", \"undefined\"]",
  )
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
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "continue in for" {
  let src =
    #|for (let i = 0; i < 5; i = i + 1) {
    #|  if (i === 2 || i === 4) { continue; }
    #|  console.log(i);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"0\", \"1\", \"3\"]")
}

///|
test "const assignment error" {
  let mut err_msg = ""
  try {
    let _ = run_js("const x = 5; x = 10")

  } catch {
    @interpreter.JsException(val) => err_msg = val.to_string()
    _ => err_msg = "unexpected error"
  }
  inspect(err_msg, content="TypeError: Assignment to constant variable 'x'")
}

///|
test "strict equality" {
  let output = run_output(
    "console.log(1 === 1); console.log(1 === 2); console.log(null === undefined)",
  )
  inspect(output, content="[\"true\", \"false\", \"false\"]")
}

///|
test "loose equality null/undefined" {
  let output = run_output(
    "console.log(null == undefined); console.log(undefined == null)",
  )
  inspect(output, content="[\"true\", \"true\"]")
}

///|
test "logical operators short-circuit" {
  let output = run_output(
    "console.log(false && 42); console.log(true || 42); console.log(0 || \"default\")",
  )
  inspect(output, content="[\"false\", \"true\", \"default\"]")
}

///|
test "unary not" {
  let (_, result) = run_js("!false")
  inspect(result, content="true")
}

///|
test "unary minus" {
  let (_, result) = run_js("-5 + 3")
  inspect(result, content="-2")
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
  inspect(output, content="[\"outer\"]")
}

///|
test "string and number concatenation" {
  let (_, result) = run_js("\"value: \" + 42")
  inspect(result, content="value: 42")
}

///|
test "modulo operator" {
  let (_, result) = run_js("10 % 3")
  inspect(result, content="1")
}

///|
test "comparison operators" {
  let output = run_output(
    "console.log(1 < 2); console.log(2 > 1); console.log(1 <= 1); console.log(1 >= 2)",
  )
  inspect(output, content="[\"true\", \"true\", \"true\", \"false\"]")
}

///|
test "string comparison" {
  let output = run_output(
    "console.log(\"a\" < \"b\"); console.log(\"z\" > \"a\"); console.log(\"abc\" <= \"abd\"); console.log(\"x\" >= \"y\")",
  )
  inspect(output, content="[\"true\", \"true\", \"true\", \"false\"]")
}

///|
test "typeof function" {
  let output = run_output(
    "console.log(typeof function() {}); function foo() {} console.log(typeof foo)",
  )
  inspect(output, content="[\"function\", \"function\"]")
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
  inspect(
    output,
    content="[\"1\", \"2\", \"Fizz\", \"4\", \"Buzz\", \"Fizz\", \"7\", \"8\", \"Fizz\", \"Buzz\", \"11\", \"Fizz\", \"13\", \"14\", \"FizzBuzz\"]",
  )
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
  inspect(output, content="[\"oops\"]")
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
  inspect(output, content="[\"42\"]")
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
  inspect(output, content="[\"before\", \"caught: error\"]")
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
  inspect(output, content="[\"caught\", \"finally\"]")
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
  inspect(output, content="[\"try\", \"finally\"]")
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
  inspect(output, content="[\"finally: inside\"]")
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
  inspect(output, content="[\"bang\"]")
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
  inspect(output, content="[\"inner: inner\", \"outer: outer\"]")
}

///|
test "uncaught throw is error" {
  let mut err_msg = ""
  try {
    let _ = run_js("throw \"uncaught\"")

  } catch {
    @interpreter.JsException(val) => err_msg = val.to_string()
    _ => err_msg = "unexpected"
  }
  inspect(err_msg, content="uncaught")
}

///|
test "object literal" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|console.log(o.x + o.y);
  let output = run_output(src)
  inspect(output, content="[\"3\"]")
}

///|
test "object property assignment" {
  let src =
    #|let o = { x: 1 };
    #|o.x = 42;
    #|console.log(o.x);
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
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
  inspect(output, content="[\"10\", \"20\", \"30\", \"3\"]")
}

///|
test "array assignment" {
  let src =
    #|let a = [1, 2, 3];
    #|a[1] = 99;
    #|console.log(a[1]);
  let output = run_output(src)
  inspect(output, content="[\"99\"]")
}

///|
test "computed member access" {
  let src =
    #|let o = { a: 1, b: 2 };
    #|let key = "b";
    #|console.log(o[key]);
  let output = run_output(src)
  inspect(output, content="[\"2\"]")
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
  inspect(output, content="[\"two\"]")
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
  inspect(output, content="[\"other\"]")
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
  inspect(output, content="[\"one\", \"two\"]")
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
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "do-while executes at least once" {
  let src =
    #|let i = 10;
    #|do {
    #|  console.log(i);
    #|} while (i < 3);
  let output = run_output(src)
  inspect(output, content="[\"10\"]")
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
  inspect(output, content="[\"abc\"]")
}

///|
test "prefix increment" {
  let src =
    #|let x = 5;
    #|console.log(++x);
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"6\", \"6\"]")
}

///|
test "postfix increment" {
  let src =
    #|let x = 5;
    #|console.log(x++);
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"5\", \"6\"]")
}

///|
test "prefix decrement" {
  let src =
    #|let x = 5;
    #|console.log(--x);
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"4\", \"4\"]")
}

///|
test "compound assignment +=" {
  let src =
    #|let x = 10;
    #|x += 5;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"15\"]")
}

///|
test "compound assignment -=" {
  let src =
    #|let x = 10;
    #|x -= 3;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"7\"]")
}

///|
test "compound assignment *=" {
  let src =
    #|let x = 4;
    #|x *= 3;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"12\"]")
}

///|
test "bitwise AND" {
  let (_, result) = run_js("12 & 10")
  inspect(result, content="8")
}

///|
test "bitwise OR" {
  let (_, result) = run_js("12 | 10")
  inspect(result, content="14")
}

///|
test "bitwise XOR" {
  let (_, result) = run_js("12 ^ 10")
  inspect(result, content="6")
}

///|
test "bitwise NOT" {
  let (_, result) = run_js("~0")
  inspect(result, content="-1")
}

///|
test "left shift" {
  let (_, result) = run_js("1 << 4")
  inspect(result, content="16")
}

///|
test "right shift" {
  let (_, result) = run_js("-16 >> 2")
  inspect(result, content="-4")
}

///|
test "unsigned right shift" {
  let (_, result) = run_js("-1 >>> 0")
  inspect(result, content="4294967295")
}

///|
test "void operator" {
  let (_, result) = run_js("void 0")
  inspect(result, content="undefined")
}

///|
test "void expression" {
  let output = run_output("console.log(void 0 === undefined)")
  inspect(output, content="[\"true\"]")
}

///|
test "delete property" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|delete o.x;
    #|console.log(o.x);
  let output = run_output(src)
  inspect(output, content="[\"undefined\"]")
}

///|
test "in operator" {
  let src =
    #|let o = { x: 1, y: 2 };
    #|console.log("x" in o);
    #|console.log("z" in o);
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "comma expression" {
  let (_, result) = run_js("1, 2, 3")
  inspect(result, content="3")
}

///|
test "typeof undeclared variable" {
  let (_, result) = run_js("typeof nonExistent")
  inspect(result, content="undefined")
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
  inspect(output, content="[\"Alice\"]")
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
  inspect(output, content="[\"1\", \"2\"]")
}

///|
test "method call this binding" {
  let src =
    #|let obj = { x: 42, getX: function() { return this.x; } };
    #|console.log(obj.getX());
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
}

///|
test "string length" {
  let (_, result) = run_js("\"hello\".length")
  inspect(result, content="5")
}

///|
test "for loop with ++" {
  let src =
    #|for (let i = 0; i < 3; i++) {
    #|  console.log(i);
    #|}
  let output = run_output(src)
  inspect(output, content="[\"0\", \"1\", \"2\"]")
}

///|
test "type coercion arithmetic" {
  let output = run_output(
    "console.log(true + 1); console.log(null + 1); console.log(false + false)",
  )
  inspect(output, content="[\"2\", \"1\", \"0\"]")
}

///|
test "neg coercion" {
  let (_, result) = run_js("-true")
  inspect(result, content="-1")
}

// ===== Task 1G: Built-in Globals =====

///|
test "NaN global" {
  let out = run_output("console.log(NaN)")
  inspect(out[0], content="NaN")
}

///|
test "Infinity global" {
  let out = run_output("console.log(Infinity)")
  inspect(out[0], content="Infinity")
}

///|
test "undefined global" {
  let (_, result) = run_js("undefined")
  inspect(result, content="undefined")
}

///|
test "isNaN true" {
  let (_, result) = run_js("isNaN(NaN)")
  inspect(result, content="true")
}

///|
test "isNaN false" {
  let (_, result) = run_js("isNaN(42)")
  inspect(result, content="false")
}

///|
test "isNaN string coercion" {
  let (_, result) = run_js("isNaN(\"hello\")")
  inspect(result, content="true")
}

///|
test "isNaN numeric string" {
  let (_, result) = run_js("isNaN(\"123\")")
  inspect(result, content="false")
}

///|
test "isFinite true" {
  let (_, result) = run_js("isFinite(42)")
  inspect(result, content="true")
}

///|
test "isFinite infinity" {
  let (_, result) = run_js("isFinite(Infinity)")
  inspect(result, content="false")
}

///|
test "isFinite NaN" {
  let (_, result) = run_js("isFinite(NaN)")
  inspect(result, content="false")
}

///|
test "parseInt basic" {
  let (_, result) = run_js("parseInt(\"42\")")
  inspect(result, content="42")
}

///|
test "parseInt with leading text stops" {
  let (_, result) = run_js("parseInt(\"123abc\")")
  inspect(result, content="123")
}

///|
test "parseInt hex" {
  let (_, result) = run_js("parseInt(\"0xFF\")")
  inspect(result, content="255")
}

///|
test "parseInt radix" {
  let (_, result) = run_js("parseInt(\"111\", 2)")
  inspect(result, content="7")
}

///|
test "parseInt negative" {
  let (_, result) = run_js("parseInt(\"-42\")")
  inspect(result, content="-42")
}

///|
test "parseInt NaN for non-numeric" {
  let out = run_output("console.log(parseInt(\"hello\"))")
  inspect(out[0], content="NaN")
}

///|
test "parseInt empty string" {
  let out = run_output("console.log(parseInt(\"\"))")
  inspect(out[0], content="NaN")
}

///|
test "parseFloat basic" {
  let (_, result) = run_js("parseFloat(\"3.14\")")
  inspect(result, content="3.14")
}

///|
test "parseFloat integer" {
  let (_, result) = run_js("parseFloat(\"42\")")
  inspect(result, content="42")
}

///|
test "parseFloat with trailing text" {
  let (_, result) = run_js("parseFloat(\"3.14abc\")")
  inspect(result, content="3.14")
}

///|
test "parseFloat NaN" {
  let out = run_output("console.log(parseFloat(\"hello\"))")
  inspect(out[0], content="NaN")
}

///|
test "String conversion number" {
  let (_, result) = run_js("String(42)")
  inspect(result, content="42")
}

///|
test "String conversion bool" {
  let (_, result) = run_js("String(true)")
  inspect(result, content="true")
}

///|
test "String conversion null" {
  let (_, result) = run_js("String(null)")
  inspect(result, content="null")
}

///|
test "String conversion undefined" {
  let (_, result) = run_js("String(undefined)")
  inspect(result, content="undefined")
}

///|
test "Number conversion string" {
  let (_, result) = run_js("Number(\"42\")")
  inspect(result, content="42")
}

///|
test "Number conversion true" {
  let (_, result) = run_js("Number(true)")
  inspect(result, content="1")
}

///|
test "Number conversion false" {
  let (_, result) = run_js("Number(false)")
  inspect(result, content="0")
}

///|
test "Number conversion null" {
  let (_, result) = run_js("Number(null)")
  inspect(result, content="0")
}

///|
test "Number conversion non-numeric string" {
  let out = run_output("console.log(Number(\"hello\"))")
  inspect(out[0], content="NaN")
}

///|
test "Boolean truthy" {
  let (_, result) = run_js("Boolean(1)")
  inspect(result, content="true")
}

///|
test "Boolean falsy zero" {
  let (_, result) = run_js("Boolean(0)")
  inspect(result, content="false")
}

///|
test "Boolean empty string" {
  let (_, result) = run_js("Boolean(\"\")")
  inspect(result, content="false")
}

///|
test "Boolean non-empty string" {
  let (_, result) = run_js("Boolean(\"hello\")")
  inspect(result, content="true")
}

///|
test "Boolean null" {
  let (_, result) = run_js("Boolean(null)")
  inspect(result, content="false")
}

///|
test "new Error" {
  let src =
    #|var e = new Error("something went wrong");
    #|console.log(e.message);
  let out = run_output(src)
  inspect(out[0], content="something went wrong")
}

///|
test "new TypeError" {
  let src =
    #|var e = new TypeError("bad type");
    #|console.log(e.name);
  let out = run_output(src)
  inspect(out[0], content="TypeError")
}

///|
test "new RangeError" {
  let src =
    #|var e = new RangeError("out of range");
    #|console.log(e.message);
  let out = run_output(src)
  inspect(out[0], content="out of range")
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
  inspect(out[0], content="oops")
}

///|
test "Error name property" {
  let src =
    #|var e = new Error("test");
    #|console.log(e.name);
  let out = run_output(src)
  inspect(out[0], content="Error")
}

///|
test "Error no args" {
  let src =
    #|var e = new Error();
    #|console.log(e.message);
  let out = run_output(src)
  inspect(out[0], content="")
}

///|
test "parseInt with whitespace" {
  let (_, result) = run_js("parseInt(\"  42  \")")
  inspect(result, content="42")
}

///|
test "parseInt hex with radix 16" {
  let (_, result) = run_js("parseInt(\"ff\", 16)")
  inspect(result, content="255")
}

///|
test "parseFloat negative" {
  let (_, result) = run_js("parseFloat(\"-3.14\")")
  inspect(result, content="-3.14")
}

///|
test "typeof NaN" {
  let (_, result) = run_js("typeof NaN")
  inspect(result, content="number")
}

///|
test "typeof Infinity" {
  let (_, result) = run_js("typeof Infinity")
  inspect(result, content="number")
}

///|
test "NaN not equal to itself" {
  let (_, result) = run_js("NaN === NaN")
  inspect(result, content="false")
}

///|
test "Infinity arithmetic" {
  let out = run_output("console.log(Infinity + 1)")
  inspect(out[0], content="Infinity")
}

///|
test "negative Infinity" {
  let out = run_output("console.log(-Infinity)")
  inspect(out[0], content="-Infinity")
}

// ===== Phase 1 Known Issue Fixes =====

// Issue 1: to_int32 spec compliance

///|
test "to_int32 wrapping large positive" {
  let (_, result) = run_js("2147483648 | 0")
  inspect(result, content="-2147483648")
}

///|
test "to_int32 wrapping large negative" {
  let (_, result) = run_js("-2147483649 | 0")
  inspect(result, content="2147483647")
}

///|
test "to_int32 wrapping 4294967296" {
  let (_, result) = run_js("4294967296 | 0")
  inspect(result, content="0")
}

// Issue 5: parseFloat improvements

///|
test "parseFloat leading dot" {
  let (_, result) = run_js("parseFloat(\".5\")")
  inspect(result, content="0.5")
}

///|
test "parseFloat exponent" {
  let (_, result) = run_js("parseFloat(\"1e2\")")
  inspect(result, content="100")
}

///|
test "parseFloat Infinity" {
  let (_, result) = run_js("parseFloat(\"Infinity\")")
  inspect(result, content="Infinity")
}

///|
test "parseFloat negative Infinity" {
  let (_, result) = run_js("parseFloat(\"-Infinity\")")
  inspect(result, content="-Infinity")
}

// Issue 2: Error prototype chain (instanceof)

///|
test "new Error instanceof Error" {
  let (_, result) = run_js("new Error() instanceof Error")
  inspect(result, content="true")
}

///|
test "new TypeError instanceof TypeError" {
  let (_, result) = run_js("new TypeError(\"bad\") instanceof TypeError")
  inspect(result, content="true")
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
  inspect(output, content="[\"ab\"]")
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
  inspect(output, content="[\"1\", \"11\"]")
}

///|
test "compound assign member single evaluation" {
  let src =
    #|var obj = { x: 10 };
    #|obj.x += 5;
    #|console.log(obj.x);
  let output = run_output(src)
  inspect(output, content="[\"15\"]")
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
  inspect(output, content="[\"00,\"]")
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
  inspect(output, content="[\"00,10,20,\"]")
}

// ====== Phase 2: Template Literals ======

///|
test "template literal no interpolation" {
  let (_, result) = run_js("`hello world`")
  inspect(result, content="hello world")
}

///|
test "template literal with interpolation" {
  let (_, result) = run_js("let x = 42; `the answer is ${x}`")
  inspect(result, content="the answer is 42")
}

///|
test "template literal multiple interpolations" {
  let (_, result) = run_js("let a = 1; let b = 2; `${a} + ${b} = ${a + b}`")
  inspect(result, content="1 + 2 = 3")
}

///|
test "template literal with expressions" {
  let (_, result) = run_js("`result: ${2 * 3 + 1}`")
  inspect(result, content="result: 7")
}

///|
test "template literal nested braces" {
  let src =
    #|var obj = {a: 1};
    #|`value: ${obj.a}`
  let (_, result) = run_js(src)
  inspect(result, content="value: 1")
}

///|
test "template literal escape sequences" {
  let (_, result) = run_js("`line1\\nline2`")
  inspect(result, content="line1\nline2")
}

///|
test "template literal empty" {
  let (_, result) = run_js("``")
  inspect(result, content="")
}

///|
test "template literal used in console.log" {
  let src =
    #|var name = "World";
    #|console.log(`Hello, ${name}!`);
  let output = run_output(src)
  inspect(output, content="[\"Hello, World!\"]")
}

// ====== Phase 2: Arrow Functions ======

///|
test "arrow function expression body" {
  let src =
    #|var add = (a, b) => a + b;
    #|add(3, 4);
  let (_, result) = run_js(src)
  inspect(result, content="7")
}

///|
test "arrow function block body" {
  let src =
    #|var square = (x) => { return x * x; };
    #|square(5);
  let (_, result) = run_js(src)
  inspect(result, content="25")
}

///|
test "arrow function single param no parens" {
  let src =
    #|var double = x => x * 2;
    #|double(7);
  let (_, result) = run_js(src)
  inspect(result, content="14")
}

///|
test "arrow function zero params" {
  let src =
    #|var greet = () => "hello";
    #|greet();
  let (_, result) = run_js(src)
  inspect(result, content="hello")
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
  inspect(output, content="[\"6,2,4\"]")
}

///|
test "arrow function closure" {
  let src =
    #|var make_adder = (n) => (x) => n + x;
    #|var add5 = make_adder(5);
    #|add5(3);
  let (_, result) = run_js(src)
  inspect(result, content="8")
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
  inspect(output, content="[\"10\", \"20\"]")
}

///|
test "prototype chain own property shadows" {
  let src =
    #|var parent = {x: 10};
    #|var child = Object.create(parent);
    #|child.x = 99;
    #|console.log(child.x);
  let output = run_output(src)
  inspect(output, content="[\"99\"]")
}

///|
test "hasOwnProperty" {
  let src =
    #|var obj = {a: 1};
    #|console.log(obj.hasOwnProperty("a"));
    #|console.log(obj.hasOwnProperty("b"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

// ====== Phase 2: Function.call / apply / bind ======

///|
test "function call method" {
  let src =
    #|function greet() { return "Hello, " + this.name; }
    #|var obj = { name: "Alice" };
    #|greet.call(obj);
  let (_, result) = run_js(src)
  inspect(result, content="Hello, Alice")
}

///|
test "function apply method" {
  let src =
    #|function sum(a, b) { return a + b; }
    #|sum.apply(null, [10, 20]);
  let (_, result) = run_js(src)
  inspect(result, content="30")
}

///|
test "function bind method" {
  let src =
    #|function greet() { return "Hi " + this.name; }
    #|var obj = { name: "Bob" };
    #|var bound = greet.bind(obj);
    #|bound();
  let (_, result) = run_js(src)
  inspect(result, content="Hi Bob")
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
  inspect(output, content="[\"4\", \"4\", \"3\"]")
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
  inspect(output, content="[\"1\", \"0,2,3\"]")
}

///|
test "array join" {
  let src =
    #|var arr = [1, 2, 3];
    #|console.log(arr.join("-"));
    #|console.log(arr.join(""));
  let output = run_output(src)
  inspect(output, content="[\"1-2-3\", \"123\"]")
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
  inspect(output, content="[\"1\", \"-1\", \"true\", \"false\"]")
}

///|
test "array slice" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|console.log(arr.slice(1, 3).join(","));
    #|console.log(arr.slice(-2).join(","));
  let output = run_output(src)
  inspect(output, content="[\"2,3\", \"4,5\"]")
}

///|
test "array concat" {
  let (_, result) = run_js("[1, 2].concat([3, 4]).join(\",\")")
  inspect(result, content="1,2,3,4")
}

///|
test "array reverse" {
  let (_, result) = run_js("[1, 2, 3].reverse().join(\",\")")
  inspect(result, content="3,2,1")
}

///|
test "array splice" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|var removed = arr.splice(1, 2);
    #|console.log(removed.join(","));
    #|console.log(arr.join(","));
  let output = run_output(src)
  inspect(output, content="[\"2,3\", \"1,4,5\"]")
}

///|
test "array sort" {
  let (_, result) = run_js(
    "[\"banana\", \"apple\", \"cherry\"].sort().join(\",\")",
  )
  inspect(result, content="apple,banana,cherry")
}

///|
test "array isArray" {
  let src =
    #|console.log(Array.isArray([1, 2]));
    #|console.log(Array.isArray("hello"));
    #|console.log(Array.isArray(42));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\", \"false\"]")
}

///|
test "array fill" {
  let (_, result) = run_js("[1, 2, 3, 4].fill(0, 1, 3).join(\",\")")
  inspect(result, content="1,0,0,4")
}

// ====== Phase 2: String Methods ======

///|
test "string charAt charCodeAt" {
  let src =
    #|var s = "hello";
    #|console.log(s.charAt(1));
    #|console.log(s.charCodeAt(0));
  let output = run_output(src)
  inspect(output, content="[\"e\", \"104\"]")
}

///|
test "string indexOf lastIndexOf" {
  let src =
    #|var s = "hello world hello";
    #|console.log(s.indexOf("hello"));
    #|console.log(s.lastIndexOf("hello"));
    #|console.log(s.indexOf("xyz"));
  let output = run_output(src)
  inspect(output, content="[\"0\", \"12\", \"-1\"]")
}

///|
test "string indexOf lastIndexOf empty needle clamping" {
  let src =
    #|console.log("abc".indexOf("", 10));
    #|console.log("abc".lastIndexOf("", -1));
    #|console.log("abc".lastIndexOf("", 99));
  let output = run_output(src)
  inspect(output, content="[\"3\", \"0\", \"3\"]")
}

///|
test "string includes" {
  let src =
    #|console.log("foobar".includes("bar"));
    #|console.log("foobar".includes("baz"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "string slice" {
  let src =
    #|console.log("hello world".slice(6));
    #|console.log("hello world".slice(0, 5));
    #|console.log("hello world".slice(-5));
  let output = run_output(src)
  inspect(output, content="[\"world\", \"hello\", \"world\"]")
}

///|
test "string toUpperCase toLowerCase" {
  let src =
    #|console.log("Hello".toUpperCase());
    #|console.log("Hello".toLowerCase());
  let output = run_output(src)
  inspect(output, content="[\"HELLO\", \"hello\"]")
}

///|
test "string trim" {
  let (_, result) = run_js("\"  hello  \".trim()")
  inspect(result, content="hello")
}

///|
test "string split" {
  let src =
    #|var parts = "a,b,c".split(",");
    #|console.log(parts.length);
    #|console.log(parts.join("|"));
  let output = run_output(src)
  inspect(output, content="[\"3\", \"a|b|c\"]")
}

///|
test "string replace" {
  let (_, result) = run_js("\"hello world\".replace(\"world\", \"there\")")
  inspect(result, content="hello there")
}

///|
test "string startsWith endsWith" {
  let src =
    #|console.log("hello".startsWith("hel"));
    #|console.log("hello".endsWith("llo"));
    #|console.log("hello".startsWith("llo"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"true\", \"false\"]")
}

///|
test "string repeat" {
  let (_, result) = run_js("\"ab\".repeat(3)")
  inspect(result, content="ababab")
}

///|
test "string padStart padEnd" {
  let src =
    #|console.log("5".padStart(3, "0"));
    #|console.log("hi".padEnd(5, "!"));
  let output = run_output(src)
  inspect(output, content="[\"005\", \"hi!!!\"]")
}

///|
test "string substring" {
  let (_, result) = run_js("\"hello\".substring(1, 4)")
  inspect(result, content="ell")
}

// ====== Phase 2: Object Methods ======

///|
test "object keys values entries" {
  let src =
    #|var obj = {a: 1, b: 2};
    #|console.log(Object.keys(obj).join(","));
    #|console.log(Object.values(obj).join(","));
  let output = run_output(src)
  inspect(output, content="[\"a,b\", \"1,2\"]")
}

///|
test "object assign" {
  let src =
    #|var target = {a: 1};
    #|Object.assign(target, {b: 2, c: 3});
    #|console.log(Object.keys(target).join(","));
  let output = run_output(src)
  inspect(output, content="[\"a,b,c\"]")
}

///|
test "object create" {
  let src =
    #|var proto = {greet: function() { return "hello"; }};
    #|var obj = Object.create(proto);
    #|console.log(obj.greet());
  let output = run_output(src)
  inspect(output, content="[\"hello\"]")
}

///|
test "object getPrototypeOf" {
  let src =
    #|var proto = {x: 1};
    #|var obj = Object.create(proto);
    #|var p = Object.getPrototypeOf(obj);
    #|console.log(p.x);
  let output = run_output(src)
  inspect(output, content="[\"1\"]")
}

///|
test "object getOwnPropertyNames" {
  let src =
    #|var obj = {a: 1, b: 2};
    #|console.log(Object.getOwnPropertyNames(obj).join(","));
  let output = run_output(src)
  inspect(output, content="[\"a,b\"]")
}

// ====== Phase 2: Math Object ======

///|
test "math constants" {
  let src =
    #|console.log(Math.PI > 3.14);
    #|console.log(Math.E > 2.71);
  let output = run_output(src)
  inspect(output, content="[\"true\", \"true\"]")
}

///|
test "math abs floor ceil round" {
  let src =
    #|console.log(Math.abs(-5));
    #|console.log(Math.floor(3.7));
    #|console.log(Math.ceil(3.2));
    #|console.log(Math.round(3.5));
  let output = run_output(src)
  inspect(output, content="[\"5\", \"3\", \"4\", \"4\"]")
}

///|
test "math round preserves negative zero" {
  let src =
    #|console.log(1 / Math.round(-0.1));
    #|console.log(1 / Math.round(-0.5));
    #|console.log(1 / Math.round(0.1));
  let output = run_output(src)
  inspect(output, content="[\"-Infinity\", \"-Infinity\", \"Infinity\"]")
}

///|
test "math sqrt pow" {
  let src =
    #|console.log(Math.sqrt(16));
    #|console.log(Math.pow(2, 10));
  let output = run_output(src)
  inspect(output, content="[\"4\", \"1024\"]")
}

///|
test "math min max" {
  let src =
    #|console.log(Math.min(3, 1, 2));
    #|console.log(Math.max(3, 1, 2));
  let output = run_output(src)
  inspect(output, content="[\"1\", \"3\"]")
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
  inspect(output, content="[\"3\", \"-3\", \"-1\", \"0\", \"1\"]")
}

///|
test "math log" {
  let src =
    #|console.log(Math.log(1));
    #|console.log(Math.log2(8));
    #|console.log(Math.log10(1000));
  let output = run_output(src)
  inspect(output, content="[\"0\", \"3\", \"3\"]")
}

// ====== Regression: .call/.apply/.bind dispatch only for callables ======

///|
test "object with own call method" {
  let src =
    #|var obj = { call: function() { return 1; } };
    #|console.log(obj.call());
  let output = run_output(src)
  inspect(output, content="[\"1\"]")
}

///|
test "object with own apply method" {
  let src =
    #|var obj = { apply: function(a) { return a + 1; } };
    #|console.log(obj.apply(10));
  let output = run_output(src)
  inspect(output, content="[\"11\"]")
}

///|
test "object with own bind method" {
  let src =
    #|var obj = { bind: function() { return "custom"; } };
    #|console.log(obj.bind());
  let output = run_output(src)
  inspect(output, content="[\"custom\"]")
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
  inspect(output, content="[\"boom\"]")
}

///|
test "bound function propagates runtime error" {
  let mut err_msg = ""
  try {
    let _ = run_js(
      "function bad() { return null.x; } var b = bad.bind(null); b();",
    )

  } catch {
    @interpreter.JsException(val) => err_msg = val.to_string()
    _ => err_msg = "other error"
  }
  inspect(err_msg.contains("Cannot read property"), content="true")
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
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "startsWith negative position" {
  let src =
    #|console.log("abc".startsWith("a", -1));
    #|console.log("abc".startsWith("abc", -100));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"true\"]")
}

///|
test "startsWith empty string with large position" {
  let src =
    #|console.log("abc".startsWith("", 100));
    #|console.log("abc".startsWith("", -1));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"true\"]")
}

///|
test "startsWith position edge cases" {
  let src =
    #|console.log("abc".startsWith("a", -999));
    #|console.log("abc".startsWith("a", 999));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "indexOf lastIndexOf more edge cases" {
  let src =
    #|console.log("abc".indexOf("", -5));
    #|console.log("abc".lastIndexOf("", 2));
  let output = run_output(src)
  inspect(output, content="[\"0\", \"2\"]")
}

///|
test "hasOwnProperty missing argument" {
  let src =
    #|var obj = { "undefined": 1 };
    #|console.log(obj.hasOwnProperty());
    #|var obj2 = { a: 1 };
    #|console.log(obj2.hasOwnProperty());
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "callable with own call property" {
  let src =
    #|function f() { return "original"; }
    #|f.call = function(t) { return "overridden"; };
    #|console.log(f.call(null));
  let output = run_output(src)
  inspect(output, content="[\"overridden\"]")
}

///|
test "array includes NaN" {
  let src =
    #|var arr = [1, NaN, 3];
    #|console.log(arr.includes(NaN));
    #|console.log(arr.includes(2));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "endsWith large end position" {
  let src =
    #|console.log("abc".endsWith("c", 100));
    #|console.log("abc".endsWith("c", 3));
    #|console.log("abc".endsWith("a", 1));
    #|console.log("abc".endsWith("c", 0));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"true\", \"true\", \"false\"]")
}

///|
test "computed hasOwnProperty" {
  let src =
    #|var obj = { a: 1 };
    #|console.log(obj["hasOwnProperty"]("a"));
    #|console.log(obj["hasOwnProperty"]("b"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
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
  inspect(output, content="[\"hi!\", \"hi?\", \"hi.\"]")
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
  inspect(output, content="[\"true\", \"true\", \"true\"]")
}

///|
test "f.call is a function" {
  let src =
    #|function f() {}
    #|console.log(typeof f.call);
    #|console.log(typeof f.apply);
    #|console.log(typeof f.bind);
  let output = run_output(src)
  inspect(output, content="[\"function\", \"function\", \"function\"]")
}

///|
test "stored call method" {
  let src =
    #|function add(x) { return this.val + x; }
    #|var c = add.call;
    #|var obj = { val: 10 };
    #|console.log(c(obj, 5));
  let output = run_output(src)
  inspect(output, content="[\"15\"]")
}

///|
test "stored bind method" {
  let src =
    #|function greet() { return this.msg; }
    #|var b = greet.bind;
    #|var bound = b({ msg: "hello" });
    #|console.log(bound());
  let output = run_output(src)
  inspect(output, content="[\"hello\"]")
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
  inspect(output, content="[\"true\", \"false\", \"true\"]")
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
  inspect(output, content="[\"3\"]")
}

///|
test "arguments object index access" {
  let src =
    #|function f() {
    #|  return arguments[0] + arguments[1];
    #|}
    #|console.log(f(10, 20));
  let output = run_output(src)
  inspect(output, content="[\"30\"]")
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
  inspect(output, content="[\"120\"]")
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
  inspect(output, content="[\"3\"]")
}

// ====== Phase 3A: Hoisting ======

///|
test "var hoisting" {
  let src =
    #|console.log(x);
    #|var x = 5;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"undefined\", \"5\"]")
}

///|
test "function hoisting" {
  let src =
    #|console.log(f());
    #|function f() { return 42; }
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
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
  inspect(output, content="[\"undefined\", \"10\"]")
}

///|
test "var hoisting does not overwrite" {
  let src =
    #|var x = 1;
    #|var x = 2;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"2\"]")
}

// ====== Phase 3A: String.fromCharCode ======

///|
test "String.fromCharCode basic" {
  let (_, result) = run_js("String.fromCharCode(72, 101, 108, 108, 111)")
  inspect(result, content="Hello")
}

///|
test "String.fromCharCode single" {
  let (_, result) = run_js("String.fromCharCode(65)")
  inspect(result, content="A")
}

// ====== Phase 3A: Number builtins ======

///|
test "Number.isNaN" {
  let src =
    #|console.log(Number.isNaN(NaN));
    #|console.log(Number.isNaN(42));
    #|console.log(Number.isNaN("hello"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\", \"false\"]")
}

///|
test "Number.isFinite" {
  let src =
    #|console.log(Number.isFinite(42));
    #|console.log(Number.isFinite(Infinity));
    #|console.log(Number.isFinite("42"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\", \"false\"]")
}

///|
test "Number.isInteger" {
  let src =
    #|console.log(Number.isInteger(42));
    #|console.log(Number.isInteger(42.5));
    #|console.log(Number.isInteger("42"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\", \"false\"]")
}

///|
test "Number.MAX_SAFE_INTEGER" {
  let (_, result) = run_js("Number.MAX_SAFE_INTEGER")
  inspect(result, content="9007199254740991")
}

///|
test "Number.EPSILON" {
  let output = run_output("console.log(Number.EPSILON < 1)")
  inspect(output, content="[\"true\"]")
}

///|
test "number toFixed" {
  let src =
    #|var n = 3.14159;
    #|console.log(n.toFixed(2));
    #|console.log(n.toFixed(0));
  let output = run_output(src)
  inspect(output, content="[\"3.14\", \"3\"]")
}

///|
test "number toString radix" {
  let src =
    #|var n = 255;
    #|console.log(n.toString(16));
    #|console.log(n.toString(2));
  let output = run_output(src)
  inspect(output, content="[\"ff\", \"11111111\"]")
}

///|
test "Number.parseInt parseFloat" {
  let src =
    #|console.log(Number.parseInt("42"));
    #|console.log(Number.parseFloat("3.14"));
  let output = run_output(src)
  inspect(output, content="[\"42\", \"3.14\"]")
}

// ====== Phase 3A: Error hierarchy polish ======

///|
test "Error has stack property" {
  let src =
    #|var e = new Error("test");
    #|console.log(typeof e.stack);
  let output = run_output(src)
  inspect(output, content="[\"string\"]")
}

///|
test "Error.prototype.toString" {
  let src =
    #|var e = new Error("test");
    #|console.log(e.name);
    #|console.log(e.message);
  let output = run_output(src)
  inspect(output, content="[\"Error\", \"test\"]")
}

// ====== Phase 3A: JSON ======

///|
test "JSON.parse basic" {
  let src =
    #|var obj = JSON.parse('{"a":1,"b":"hello"}');
    #|console.log(obj.a);
    #|console.log(obj.b);
  let output = run_output(src)
  inspect(output, content="[\"1\", \"hello\"]")
}

///|
test "JSON.parse array" {
  let src =
    #|var arr = JSON.parse('[1, 2, 3]');
    #|console.log(arr.length);
    #|console.log(arr[0]);
  let output = run_output(src)
  inspect(output, content="[\"3\", \"1\"]")
}

///|
test "JSON.parse nested" {
  let src =
    #|var obj = JSON.parse('{"a":{"b":42}}');
    #|console.log(obj.a.b);
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
}

///|
test "JSON.parse booleans null" {
  let src =
    #|var obj = JSON.parse('{"t":true,"f":false,"n":null}');
    #|console.log(obj.t);
    #|console.log(obj.f);
    #|console.log(obj.n);
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\", \"null\"]")
}

///|
test "JSON.stringify basic" {
  let src =
    #|var obj = {a: 1, b: "hello"};
    #|console.log(JSON.stringify(obj));
  let output = run_output(src)
  inspect(output[0], content="{\"a\":1,\"b\":\"hello\"}")
}

///|
test "JSON.stringify array" {
  let src =
    #|console.log(JSON.stringify([1, 2, 3]));
  let output = run_output(src)
  inspect(output, content="[\"[1,2,3]\"]")
}

///|
test "JSON.stringify null undefined" {
  let src =
    #|console.log(JSON.stringify(null));
    #|console.log(JSON.stringify(42));
    #|console.log(JSON.stringify("hello"));
    #|console.log(JSON.stringify(true));
  let output = run_output(src)
  inspect(output, content="[\"null\", \"42\", \"\\\"hello\\\"\", \"true\"]")
}

///|
test "JSON.stringify skips functions" {
  let src =
    #|var obj = {a: 1, b: function() {}};
    #|console.log(JSON.stringify(obj));
  let output = run_output(src)
  inspect(output[0], content="{\"a\":1}")
}

// ====== Phase 3B: Array Higher-Order Functions ======

///|
test "array map" {
  let src =
    #|var arr = [1, 2, 3];
    #|var result = arr.map(function(x) { return x * 2; });
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"2,4,6\"]")
}

///|
test "array map with arrow" {
  let src =
    #|var arr = [1, 2, 3];
    #|var result = arr.map(x => x * x);
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"1,4,9\"]")
}

///|
test "array filter" {
  let src =
    #|var arr = [1, 2, 3, 4, 5];
    #|var result = arr.filter(x => x % 2 === 0);
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"2,4\"]")
}

///|
test "array reduce" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|var sum = arr.reduce(function(acc, x) { return acc + x; }, 0);
    #|console.log(sum);
  let output = run_output(src)
  inspect(output, content="[\"10\"]")
}

///|
test "array reduce no initial" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|var sum = arr.reduce(function(acc, x) { return acc + x; });
    #|console.log(sum);
  let output = run_output(src)
  inspect(output, content="[\"10\"]")
}

///|
test "array forEach" {
  let src =
    #|var result = [];
    #|[1, 2, 3].forEach(function(x) { result.push(x * 10); });
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"10,20,30\"]")
}

///|
test "array find" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|console.log(arr.find(x => x > 2));
    #|console.log(arr.find(x => x > 10));
  let output = run_output(src)
  inspect(output, content="[\"3\", \"undefined\"]")
}

///|
test "array findIndex" {
  let src =
    #|var arr = [1, 2, 3, 4];
    #|console.log(arr.findIndex(x => x > 2));
    #|console.log(arr.findIndex(x => x > 10));
  let output = run_output(src)
  inspect(output, content="[\"2\", \"-1\"]")
}

///|
test "array every" {
  let src =
    #|console.log([2, 4, 6].every(x => x % 2 === 0));
    #|console.log([2, 3, 6].every(x => x % 2 === 0));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "array some" {
  let src =
    #|console.log([1, 3, 5].some(x => x % 2 === 0));
    #|console.log([1, 2, 5].some(x => x % 2 === 0));
  let output = run_output(src)
  inspect(output, content="[\"false\", \"true\"]")
}

///|
test "array flat" {
  let src =
    #|var arr = [1, [2, 3], [4, [5]]];
    #|console.log(arr.flat().join(","));
  let output = run_output(src)
  inspect(output, content="[\"1,2,3,4,5\"]")
}

///|
test "array flatMap" {
  let src =
    #|var arr = [1, 2, 3];
    #|var result = arr.flatMap(x => [x, x * 2]);
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"1,2,2,4,3,6\"]")
}

///|
test "array sort with compareFn" {
  let src =
    #|var arr = [3, 1, 4, 1, 5];
    #|arr.sort(function(a, b) { return a - b; });
    #|console.log(arr.join(","));
  let output = run_output(src)
  inspect(output, content="[\"1,1,3,4,5\"]")
}

///|
test "array reduceRight" {
  let src =
    #|var arr = ["a", "b", "c"];
    #|var result = arr.reduceRight(function(acc, x) { return acc + x; });
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"cba\"]")
}

///|
test "array map with index" {
  let src =
    #|var arr = ["a", "b", "c"];
    #|var result = arr.map(function(val, idx) { return idx + ":" + val; });
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"0:a,1:b,2:c\"]")
}

///|
test "JSON.parse then stringify roundtrip" {
  let src =
    #|var str = '{"x":1,"y":[2,3]}';
    #|var obj = JSON.parse(str);
    #|console.log(JSON.stringify(obj));
  let output = run_output(src)
  inspect(output[0], content="{\"x\":1,\"y\":[2,3]}")
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
  inspect(output, content="[\"60\"]")
}

///|
test "for-of with let" {
  let src =
    #|var arr = ["a", "b", "c"];
    #|var result = "";
    #|for (let x of arr) { result += x; }
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"abc\"]")
}

///|
test "for-of string" {
  let src =
    #|var result = [];
    #|for (var ch of "hello") { result.push(ch); }
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"h,e,l,l,o\"]")
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
  inspect(output, content="[\"6\"]")
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
  inspect(output, content="[\"9\"]")
}

///|
test "spread in array literal" {
  let src =
    #|var a = [1, 2, 3];
    #|var b = [0, ...a, 4];
    #|console.log(b.join(","));
  let output = run_output(src)
  inspect(output, content="[\"0,1,2,3,4\"]")
}

///|
test "spread in function call" {
  let src =
    #|function add(a, b, c) { return a + b + c; }
    #|var args = [1, 2, 3];
    #|console.log(add(...args));
  let output = run_output(src)
  inspect(output, content="[\"6\"]")
}

///|
test "spread with concat" {
  let src =
    #|var a = [1, 2];
    #|var b = [3, 4];
    #|var c = [...a, ...b];
    #|console.log(c.join(","));
  let output = run_output(src)
  inspect(output, content="[\"1,2,3,4\"]")
}

///|
test "spread string in array" {
  let src =
    #|var arr = [..."abc"];
    #|console.log(arr.join(","));
  let output = run_output(src)
  inspect(output, content="[\"a,b,c\"]")
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
  inspect(output, content="[\"Hello, world!\", \"Hello, Alice!\"]")
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
  inspect(output, content="[\"9\", \"8\"]")
}

///|
test "default parameter undefined triggers default" {
  let src =
    #|function f(x = 10) { return x; }
    #|console.log(f(undefined));
    #|console.log(f(null));
    #|console.log(f(0));
  let output = run_output(src)
  inspect(output, content="[\"10\", \"null\", \"0\"]")
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
  inspect(output, content="[\"10\"]")
}

///|
test "rest parameter with leading params" {
  let src =
    #|function first_and_rest(first, ...rest) {
    #|  return first + ":" + rest.join(",");
    #|}
    #|console.log(first_and_rest("a", "b", "c", "d"));
  let output = run_output(src)
  inspect(output, content="[\"a:b,c,d\"]")
}

///|
test "rest parameter empty" {
  let src =
    #|function f(a, ...rest) {
    #|  return rest.length;
    #|}
    #|console.log(f(1));
  let output = run_output(src)
  inspect(output, content="[\"0\"]")
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
  inspect(output, content="[\"1,2,\", \"10,2,\", \"10,20,30;40\"]")
}

///|
test "arrow function with default param" {
  let src =
    #|var greet = (name = "world") => "Hello, " + name;
    #|console.log(greet());
    #|console.log(greet("Bob"));
  let output = run_output(src)
  inspect(output, content="[\"Hello, world\", \"Hello, Bob\"]")
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
  inspect(output, content="[\"6\"]")
}

///|
test "function expression with default" {
  let src =
    #|var f = function(x = 5) { return x * 2; };
    #|console.log(f());
    #|console.log(f(3));
  let output = run_output(src)
  inspect(output, content="[\"10\", \"6\"]")
}

///|
test "function expression with rest" {
  let src =
    #|var f = function(first, ...rest) { return rest; };
    #|var result = f(1, 2, 3);
    #|console.log(result.join(","));
  let output = run_output(src)
  inspect(output, content="[\"2,3\"]")
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
  inspect(output, content="[\"10,20\"]")
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
  inspect(output, content="[\"6\"]")
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
  inspect(output, content="[\"10,20,30\"]")
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
  inspect(output, content="[\"1\", \"99\"]")
}

///|
test "default param with function call" {
  let src =
    #|function getDefault() { return 42; }
    #|function f(x = getDefault()) { return x; }
    #|console.log(f());
    #|console.log(f(10));
  let output = run_output(src)
  inspect(output, content="[\"42\", \"10\"]")
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
  inspect(output, content="[\"6\", \"15\", \"33\", \"60\"]")
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
  inspect(output, content="[\"5\"]")
}

///|
test "spread in middle of array" {
  let src =
    #|var mid = [3, 4];
    #|var arr = [1, 2, ...mid, 5, 6];
    #|console.log(arr.length);
    #|console.log(arr.join(","));
  let output = run_output(src)
  inspect(output, content="[\"6\", \"1,2,3,4,5,6\"]")
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
  inspect(output, content="[\"2,3,4\"]")
}

///|
test "spread function call with extra args" {
  let src =
    #|function f(a, b, c, d) { return a + b + c + d; }
    #|var arr = [1, 2];
    #|console.log(f(...arr, 3, 4));
  let output = run_output(src)
  inspect(output, content="[\"10\"]")
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
  inspect(output, content="[\"1,2,3\"]")
}

///|
test "array destructuring with rest" {
  let src =
    #|let [first, ...rest] = [1, 2, 3, 4, 5];
    #|console.log(first);
    #|console.log(rest.join(","));
  let output = run_output(src)
  inspect(output, content="[\"1\", \"2,3,4,5\"]")
}

///|
test "array destructuring with holes" {
  let src =
    #|var [a, , b] = [1, 2, 3];
    #|console.log(a + "," + b);
  let output = run_output(src)
  inspect(output, content="[\"1,3\"]")
}

///|
test "array destructuring fewer elements" {
  let src =
    #|var [a, b, c] = [1, 2];
    #|console.log(a);
    #|console.log(b);
    #|console.log(c);
  let output = run_output(src)
  inspect(output, content="[\"1\", \"2\", \"undefined\"]")
}

///|
test "object destructuring basic" {
  let src =
    #|var {x, y} = {x: 10, y: 20};
    #|console.log(x + "," + y);
  let output = run_output(src)
  inspect(output, content="[\"10,20\"]")
}

///|
test "object destructuring with alias" {
  let src =
    #|var {name: n, age: a} = {name: "Alice", age: 30};
    #|console.log(n + " is " + a);
  let output = run_output(src)
  inspect(output, content="[\"Alice is 30\"]")
}

///|
test "object destructuring with default" {
  let src =
    #|var {x, y = 5} = {x: 10};
    #|console.log(x + "," + y);
  let output = run_output(src)
  inspect(output, content="[\"10,5\"]")
}

///|
test "object destructuring with rest" {
  let src =
    #|var {a, ...rest} = {a: 1, b: 2, c: 3};
    #|console.log(a);
    #|console.log(rest.b);
    #|console.log(rest.c);
  let output = run_output(src)
  inspect(output, content="[\"1\", \"2\", \"3\"]")
}

///|
test "nested array destructuring" {
  let src =
    #|var [a, [b, c]] = [1, [2, 3]];
    #|console.log(a + "," + b + "," + c);
  let output = run_output(src)
  inspect(output, content="[\"1,2,3\"]")
}

///|
test "nested object destructuring" {
  let src =
    #|var {a, b: {c, d}} = {a: 1, b: {c: 2, d: 3}};
    #|console.log(a + "," + c + "," + d);
  let output = run_output(src)
  inspect(output, content="[\"1,2,3\"]")
}

///|
test "destructuring in let" {
  let src =
    #|let [x, y] = [100, 200];
    #|console.log(x + y);
  let output = run_output(src)
  inspect(output, content="[\"300\"]")
}

///|
test "destructuring in const" {
  let src =
    #|const {PI, E} = {PI: 3.14, E: 2.72};
    #|console.log(PI);
    #|console.log(E);
  let output = run_output(src)
  inspect(output, content="[\"3.14\", \"2.72\"]")
}

///|
test "array destructuring with rest empty" {
  let src =
    #|var [a, b, ...rest] = [1, 2];
    #|console.log(a);
    #|console.log(b);
    #|console.log(rest.length);
  let output = run_output(src)
  inspect(output, content="[\"1\", \"2\", \"0\"]")
}

///|
test "object destructuring alias with default" {
  let src =
    #|var {name: n = "unknown", age: a = 0} = {name: "Bob"};
    #|console.log(n);
    #|console.log(a);
  let output = run_output(src)
  inspect(output, content="[\"Bob\", \"0\"]")
}

///|
test "destructuring from function return" {
  let src =
    #|function getPoint() { return {x: 10, y: 20}; }
    #|var {x, y} = getPoint();
    #|console.log(x + "," + y);
  let output = run_output(src)
  inspect(output, content="[\"10,20\"]")
}

///|
test "array destructuring from function return" {
  let src =
    #|function getCoords() { return [3, 4]; }
    #|var [x, y] = getCoords();
    #|console.log(x + "," + y);
  let output = run_output(src)
  inspect(output, content="[\"3,4\"]")
}

///|
test "swap with array destructuring" {
  let src =
    #|var a = 1;
    #|var b = 2;
    #|var [c, d] = [b, a];
    #|console.log(c + "," + d);
  let output = run_output(src)
  inspect(output, content="[\"2,1\"]")
}

///|
test "destructuring with computed property from array" {
  let src =
    #|var arr = [10, 20, 30, 40, 50];
    #|var [, second, , fourth] = arr;
    #|console.log(second + "," + fourth);
  let output = run_output(src)
  inspect(output, content="[\"20,40\"]")
}

///|
test "object destructuring missing key" {
  let src =
    #|var {a, b, c} = {a: 1};
    #|console.log(a);
    #|console.log(b);
    #|console.log(c);
  let output = run_output(src)
  inspect(output, content="[\"1\", \"undefined\", \"undefined\"]")
}

///|
test "mixed nested destructuring" {
  let src =
    #|var {data: [first, second], count} = {data: [10, 20], count: 2};
    #|console.log(first + "," + second + "," + count);
  let output = run_output(src)
  inspect(output, content="[\"10,20,2\"]")
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
  inspect(output, content="[\"42\"]")
}

///|
test "Object.defineProperty non-writable" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 42, writable: false });
    #|obj.x = 100;
    #|console.log(obj.x);
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
}

///|
test "Object.defineProperty non-enumerable" {
  let src =
    #|var obj = {a: 1, b: 2};
    #|Object.defineProperty(obj, "c", { value: 3, enumerable: false });
    #|console.log(Object.keys(obj).join(","));
    #|console.log(obj.c);
  let output = run_output(src)
  inspect(output, content="[\"a,b\", \"3\"]")
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
  inspect(output, content="[\"false\", \"1\"]")
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
  inspect(output, content="[\"5\", \"false\", \"true\", \"false\"]")
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
  inspect(output, content="[\"1\", \"undefined\", \"true\"]")
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
  inspect(output, content="[\"100\", \"undefined\", \"false\", \"true\"]")
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
  inspect(output, content="[\"1\", \"undefined\", \"false\"]")
}

///|
test "Object.isFrozen on non-frozen object" {
  let src =
    #|var obj = {x: 1};
    #|console.log(Object.isFrozen(obj));
  let output = run_output(src)
  inspect(output, content="[\"false\"]")
}

///|
test "Object.isSealed on non-sealed object" {
  let src =
    #|var obj = {x: 1};
    #|console.log(Object.isSealed(obj));
  let output = run_output(src)
  inspect(output, content="[\"false\"]")
}

///|
test "Object.isExtensible on regular object" {
  let src =
    #|var obj = {};
    #|console.log(Object.isExtensible(obj));
  let output = run_output(src)
  inspect(output, content="[\"true\"]")
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
  inspect(output, content="[\"1\", \"2\"]")
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
  inspect(output, content="[\"false\", \"1\"]")
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
  inspect(output, content="[\"a,b\"]")
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
  inspect(output, content="[\"10\", \"99\"]")
}

///|
test "getOwnPropertyDescriptor missing prop" {
  let src =
    #|var obj = {x: 1};
    #|var desc = Object.getOwnPropertyDescriptor(obj, "y");
    #|console.log(desc);
  let output = run_output(src)
  inspect(output, content="[\"undefined\"]")
}

///|
test "freeze with Object.keys" {
  let src =
    #|var obj = {a: 1, b: 2, c: 3};
    #|Object.freeze(obj);
    #|console.log(Object.keys(obj).join(","));
  let output = run_output(src)
  inspect(output, content="[\"a,b,c\"]")
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
  inspect(output, content="[\"undefined\"]")
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
  inspect(
    output,
    content="[\"TypeError: Cannot assign to read only property 'x'\"]",
  )
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
  inspect(
    output,
    content="[\"TypeError: Cannot assign to read only property 'x'\", \"TypeError: Cannot add property y, object is not extensible\"]",
  )
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
  inspect(output, content="[\"TypeError: Cannot delete property 'x'\"]")
}

///|
test "use strict: no arguments.callee" {
  let src =
    #|"use strict";
    #|function f() {
    #|  return typeof arguments.callee;
    #|}
    #|console.log(f());
  let output = run_output(src)
  inspect(output, content="[\"undefined\"]")
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
  inspect(output, content="[\"undefined\"]")
}

///|
test "non-strict mode: this is not undefined" {
  let src =
    #|function getThis() { return typeof this; }
    #|console.log(getThis());
  let output = run_output(src)
  inspect(output, content="[\"undefined\"]")
}

///|
test "strict mode: sloppy function has arguments.callee" {
  let src =
    #|function f() {
    #|  return typeof arguments.callee;
    #|}
    #|console.log(f());
  let output = run_output(src)
  inspect(output, content="[\"function\"]")
}

///|
test "use strict in global scope" {
  let src =
    #|"use strict";
    #|var x = 10;
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"10\"]")
}

///|
test "strict mode: non-writable silent in sloppy" {
  let src =
    #|var obj = {};
    #|Object.defineProperty(obj, "x", { value: 42, writable: false });
    #|obj.x = 100;
    #|console.log(obj.x);
  let output = run_output(src)
  inspect(output, content="[\"42\"]")
}

// ---- Phase 3G: RegExp tests ----

///|
test "regex literal test method" {
  let src =
    #|var re = /hello/;
    #|console.log(re.test("hello world"));
    #|console.log(re.test("goodbye"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "regex literal with flags" {
  let src =
    #|var re = /hello/i;
    #|console.log(re.test("Hello World"));
    #|console.log(re.flags);
    #|console.log(re.ignoreCase);
  let output = run_output(src)
  inspect(output, content="[\"true\", \"i\", \"true\"]")
}

///|
test "regex exec method" {
  let src =
    #|var re = /(\d+)/;
    #|var result = re.exec("abc 123 def");
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  inspect(output, content="[\"123\", \"123\"]")
}

///|
test "regex exec returns null on no match" {
  let src =
    #|var re = /xyz/;
    #|var result = re.exec("hello world");
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"null\"]")
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
  inspect(output, content="[\"abc\", \"gi\", \"true\", \"true\"]")
}

///|
test "regex character class" {
  let src =
    #|var re = /[a-z]+/;
    #|console.log(re.test("hello"));
    #|console.log(re.test("12345"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "regex dot and quantifiers" {
  let src =
    #|var re = /a.+b/;
    #|console.log(re.test("aXYZb"));
    #|console.log(re.test("ab"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
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
  inspect(output, content="[\"true\", \"false\", \"true\", \"false\"]")
}

///|
test "regex alternation" {
  let src =
    #|var re = /cat|dog/;
    #|console.log(re.test("I have a cat"));
    #|console.log(re.test("I have a dog"));
    #|console.log(re.test("I have a bird"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"true\", \"false\"]")
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
  inspect(output, content="[\"true\", \"false\", \"true\", \"false\"]")
}

///|
test "string match with regex" {
  let src =
    #|var result = "hello 123 world 456".match(/\d+/g);
    #|console.log(result.length);
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  inspect(output, content="[\"2\", \"123\", \"456\"]")
}

///|
test "string match non-global" {
  let src =
    #|var result = "abc 123 def".match(/(\d+)/);
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  inspect(output, content="[\"123\", \"123\"]")
}

///|
test "string match returns null" {
  let src =
    #|var result = "hello".match(/\d+/);
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"null\"]")
}

///|
test "string search with regex" {
  let src =
    #|console.log("hello 123 world".search(/\d+/));
    #|console.log("hello world".search(/\d+/));
  let output = run_output(src)
  inspect(output, content="[\"6\", \"-1\"]")
}

///|
test "string replace with regex" {
  let src =
    #|var result = "hello world".replace(/world/, "there");
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"hello there\"]")
}

///|
test "string replace with regex global" {
  let src =
    #|var result = "aaa bbb aaa".replace(/aaa/g, "ccc");
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"ccc bbb ccc\"]")
}

///|
test "string replace with capture group" {
  let src =
    #|var result = "John Smith".replace(/(\w+) (\w+)/, "$2 $1");
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"Smith John\"]")
}

///|
test "new RegExp constructor" {
  let src =
    #|var re = new RegExp("hello", "i");
    #|console.log(re.test("Hello"));
    #|console.log(re.source);
    #|console.log(re.flags);
  let output = run_output(src)
  inspect(output, content="[\"true\", \"hello\", \"i\"]")
}

///|
test "regex quantifier exact" {
  let src =
    #|var re = /a{3}/;
    #|console.log(re.test("aaa"));
    #|console.log(re.test("aa"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "regex optional quantifier" {
  let src =
    #|var re = /colou?r/;
    #|console.log(re.test("color"));
    #|console.log(re.test("colour"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"true\"]")
}

///|
test "regex with escaped special chars" {
  let src =
    #|var re = /\./;
    #|console.log(re.test("hello.world"));
    #|console.log(re.test("helloworld"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
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
  inspect(output, content="[\"false\", \"false\", \"false\"]")
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
  inspect(output, content="[\"2\", \"true\", \"true\"]")
}

///|
test "bugfix: case-insensitive regex preserves captures" {
  let src =
    #|var result = "Hello World".match(/^(H)/i);
    #|console.log(result[0]);
    #|console.log(result[1]);
  let output = run_output(src)
  inspect(output, content="[\"H\", \"H\"]")
}

///|
test "bugfix: case-insensitive regex \\D not broken" {
  let src =
    #|var re = /\D+/i;
    #|console.log(re.test("abc"));
    #|console.log(re.test("123"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "bugfix: case-insensitive regex \\W not broken" {
  let src =
    #|var re = /\W/i;
    #|console.log(re.test(" "));
    #|console.log(re.test("a"));
  let output = run_output(src)
  inspect(output, content="[\"true\", \"false\"]")
}

///|
test "bugfix: UserFuncExt strict mode" {
  let src =
    #|function f(a = 1) {
    #|  "use strict";
    #|  console.log(arguments.callee);
    #|}
    #|f();
  let output = run_output(src)
  inspect(output, content="[\"undefined\"]")
}

///|
test "bugfix: UserFuncExt sloppy has callee" {
  let src =
    #|function f(a = 1) {
    #|  console.log(typeof arguments.callee);
    #|}
    #|f();
  let output = run_output(src)
  inspect(output, content="[\"function\"]")
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
  inspect(output, content="[\"10\"]")
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
  inspect(output, content="[\"2\", \"1\"]")
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
  inspect(output, content="[\"3\", \"4\"]")
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
  inspect(output, content="[\"matched\"]")
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
  inspect(output, content="[\"true\"]")
}

///|
test "bugfix: division after function call rparen" {
  let src =
    #|function getNum() { return 10; }
    #|var result = getNum() / 2;
    #|console.log(result);
  let output = run_output(src)
  inspect(output, content="[\"5\"]")
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
  inspect(output, content="[\"2\"]")
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
  inspect(output, content="[\"function\"]")
}

///|
test "bugfix: constructor honors function strict mode" {
  let src =
    #|function C() {
    #|  "use strict";
    #|  console.log(typeof arguments.callee);
    #|}
    #|new C();
  let output = run_output(src)
  inspect(output, content="[\"undefined\"]")
}

///|
test "bugfix: var destructure declaration is hoisted" {
  let src =
    #|console.log(a);
    #|var [a] = [1];
    #|console.log(a);
  let output = run_output(src)
  inspect(output, content="[\"undefined\", \"1\"]")
}

///|
test "bugfix: for-of var binds in outer scope" {
  let src =
    #|for (var x of [1, 2]) {}
    #|console.log(x);
  let output = run_output(src)
  inspect(output, content="[\"2\"]")
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
  inspect(output, content="[\"3\", \"3\"]")
}

///|
test "bugfix: regex literal after control-flow rparen" {
  let src =
    #|var out = 0;
    #|if (true) /ab/.test("zabz") ? out = 1 : out = 2;
    #|console.log(out);
  let output = run_output(src)
  inspect(output, content="[\"1\"]")
}

///|
test "bugfix: negative toFixed keeps sign and digits" {
  let src =
    #|console.log((-1.23).toFixed(2));
    #|console.log((-0.004).toFixed(2));
  let output = run_output(src)
  inspect(output, content="[\"-1.23\", \"-0.00\"]")
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
  inspect(
    output,
    content="[\"TypeError: Converting circular structure to JSON\"]",
  )
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
  inspect(
    output,
    content="[\"SyntaxError: Unexpected control character in JSON\"]",
  )
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
  inspect(output, content="[\"test message\", \"Test262Error: test message\"]")
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
  inspect(output, content="[\"true\", \"false\", \"true\"]")
}

///|
test "test262 harness pattern - typeof Array.isArray" {
  let src =
    #|var f = Array.isArray;
    #|console.log(typeof f);
  let output = run_output(src)
  inspect(output, content="[\"function\"]")
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
  inspect(output, content="[\"TEST PASSED\"]")
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
  inspect(output, content="[\"6\"]")
}

///|
test "comma-separated var declarations with initializers" {
  let src =
    #|var x = 10, y = 20, z = 30;
    #|console.log(x + y + z);
  let output = run_output(src)
  inspect(output, content="[\"60\"]")
}

///|
test "comma-separated let declarations" {
  let src =
    #|let a = 1, b = 2;
    #|console.log(a * b);
  let output = run_output(src)
  inspect(output, content="[\"2\"]")
}

///|
test "comma-separated const declarations" {
  let src =
    #|const PI = 3.14, E = 2.71;
    #|console.log(PI + E);
  let output = run_output(src)
  inspect(output, content="[\"5.85\"]")
}

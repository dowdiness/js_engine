///|
const BYTECODE_CLOSURE_FACTORY_PROGRAM : String =
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
const BYTECODE_PIPELINE_EXEC_PROGRAM : String =
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
fn bytecode_interpreter_outcome(src : String) -> String {
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
fn bytecode_outcome(src : String) -> String {
  try {
    let prog = @parser.parse(src)
    let interp = @interpreter.new_interpreter()
    let bytecode = compile_script_to_bytecode(prog.stmts)
    "value:" + bytecode.run(interp).to_string()
  } catch {
    @runtime.JsException(value) => "throw:" + value.to_string()
    err => "error:" + err.to_string()
  }
}

///|
fn bytecode_compare(src : String) -> String {
  let expected = bytecode_interpreter_outcome(src)
  let actual = bytecode_outcome(src)
  if actual == expected {
    actual
  } else {
    "expected \{expected}; got \{actual}"
  }
}

///|
fn bytecode_interpreter_output_outcome(src : String) -> String {
  let interp = @interpreter.new_interpreter()
  try {
    let prog = @parser.parse(src)
    "value:" +
    interp.run(prog.stmts).to_string() +
    "; output:" +
    interp.host.output.join("|")
  } catch {
    @runtime.JsException(value) =>
      "throw:" + value.to_string() + "; output:" + interp.host.output.join("|")
    err =>
      "error:" + err.to_string() + "; output:" + interp.host.output.join("|")
  }
}

///|
fn bytecode_output_outcome(src : String) -> String {
  let interp = @interpreter.new_interpreter()
  try {
    let prog = @parser.parse(src)
    let bytecode = compile_script_to_bytecode(prog.stmts)
    "value:" +
    bytecode.run(interp).to_string() +
    "; output:" +
    interp.host.output.join("|")
  } catch {
    @runtime.JsException(value) =>
      "throw:" + value.to_string() + "; output:" + interp.host.output.join("|")
    err =>
      "error:" + err.to_string() + "; output:" + interp.host.output.join("|")
  }
}

///|
fn bytecode_compare_with_output(src : String) -> String {
  let expected = bytecode_interpreter_output_outcome(src)
  let actual = bytecode_output_outcome(src)
  if actual == expected {
    actual
  } else {
    "expected \{expected}; got \{actual}"
  }
}

///|
test "bytecode constants locals and binary ops" {
  let src =
    #|var x = 1;
    #|x = x + 2;
    #|x;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode comma expression returns right value" {
  let src =
    #|(0, "right");
  inspect(bytecode_compare(src), content="value:right")
}

///|
test "bytecode comma expression runs left side effects before right" {
  let src =
    #|var x = 0;
    #|(x = 1, x = x + 1);
    #|x;
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode comma in assignment expression statement returns right value" {
  let src =
    #|var x = 0;
    #|x = (1, 2);
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode nested grouped comma expressions preserve evaluation order" {
  let src =
    #|var order = "";
    #|var result = ((order = order + "a", order = order + "b"), (order = order + "c", order = order + "d"));
    #|order + ":" + result;
  inspect(bytecode_compare(src), content="value:abcd:abcd")
}

///|
test "bytecode template literal interpolates values" {
  let src =
    #|var x = 2;
    #|var y = true;
    #|`a${x + 1}b${y}c`;
  inspect(bytecode_compare(src), content="value:a3btruec")
}

///|
test "bytecode template literal converts substitutions before later expressions" {
  let src =
    #|var log = "";
    #|var f = function() {};
    #|f.toString = function() { log = log + "s"; return "F"; };
    #|var result = `${f}${(log = log + "e", "E")}`;
    #|result + ":" + log;
  inspect(bytecode_compare(src), content="value:FE:se")
}

///|
test "bytecode template literal captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = "cap";
    #|  return function() { return `:${x}:`; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value::cap:")
}

///|
test "bytecode regex literal uses runtime regexp semantics" {
  let src =
    #|var r = /a+/;
    #|r.test("caaat") + "," + r.test("bbb");
  inspect(bytecode_compare(src), content="value:true,false")
}

///|
test "bytecode regex literal honors flags" {
  let src =
    #|var r = /a/i;
    #|r.test("A");
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode regex literal creates a fresh object each evaluation" {
  let src =
    #|function make() { return /x/g; }
    #|make() === make();
  inspect(bytecode_compare(src), content="value:false")
}

///|
test "bytecode logical and skips rhs and returns original falsy operand" {
  let src =
    #|var rhs = 0;
    #|var result = 0 && (rhs = 1);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:0,0")
}

///|
test "bytecode logical and evaluates rhs and returns rhs when lhs is truthy" {
  let src =
    #|var rhs = 0;
    #|var result = 2 && (rhs = 5);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:5,5")
}

///|
test "bytecode logical or skips rhs and returns original truthy operand" {
  let src =
    #|var rhs = 0;
    #|var result = "left" || (rhs = 1);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:left,0")
}

///|
test "bytecode logical or evaluates rhs and returns rhs when lhs is falsy" {
  let src =
    #|var rhs = 0;
    #|var result = false || (rhs = 7);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:7,7")
}

///|
test "bytecode nullish coalescing only skips non-nullish lhs values" {
  let src =
    #|var side = 0;
    #|var a = 0 ?? (side = side + 1);
    #|var b = false ?? (side = side + 10);
    #|var c = "" ?? (side = side + 100);
    #|var d = null ?? (side = side + 1000);
    #|var e = undefined ?? (side = side + 10000);
    #|a + "," + b + "," + c + "," + d + "," + e + "," + side;
  inspect(bytecode_compare(src), content="value:0,false,,1000,11000,11000")
}

///|
test "bytecode ternary uses truthiness and returns selected branch" {
  let src =
    #|var a = 0 ? "bad" : "zero";
    #|var b = "x" ? "string" : "bad";
    #|a + "," + b;
  inspect(bytecode_compare(src), content="value:zero,string")
}

///|
test "bytecode ternary skips unselected branch side effects" {
  let src =
    #|var hits = 0;
    #|var a = true ? (hits = hits + 1) : (hits = hits + 100);
    #|var b = false ? (hits = hits + 1000) : (hits = hits + 10);
    #|a + "," + b + "," + hits;
  inspect(bytecode_compare(src), content="value:1,11,11")
}

///|
test "bytecode ternary expression statement updates completion" {
  let src =
    #|false ? "then" : "else";
  inspect(bytecode_compare(src), content="value:else")
}

///|
test "bytecode unary numeric logical and bitwise operators" {
  let src =
    #|var x = "2";
    #|(-x) + "," + (+true) + "," + (!0) + "," + (~1);
  inspect(bytecode_compare(src), content="value:-2,1,true,-2")
}

///|
test "bytecode void evaluates operand effects and yields undefined" {
  let src =
    #|var x = 0;
    #|var r = void (x = 42);
    #|(r === undefined) + "," + x;
  inspect(bytecode_compare(src), content="value:true,42")
}

///|
test "bytecode unary captured vars use environment fallback" {
  let src =
    #|function outer() {
    #|  var x = 2;
    #|  return function() { return -x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:-2")
}

///|
test "bytecode rejects delete operator until delete semantics are shared" {
  let src =
    #|var xs = [1];
    #|delete xs[0];
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: delete operator",
  )
}

///|
test "bytecode typeof handles missing and resolved identifiers" {
  let src =
    #|var x = 1;
    #|var f = function() {};
    #|typeof missing + "," + typeof x + "," + typeof f;
  inspect(bytecode_compare(src), content="value:undefined,number,function")
}

///|
test "bytecode typeof reads function local slots" {
  let src =
    #|function f(a) {
    #|  var b = "x";
    #|  return typeof a + "," + typeof b;
    #|}
    #|f(1);
  inspect(bytecode_compare(src), content="value:number,string")
}

///|
test "bytecode typeof evaluates non-identifier operands" {
  let src =
    #|var x = 1;
    #|typeof (x + 1);
  inspect(bytecode_compare(src), content="value:number")
}

///|
test "bytecode typeof keeps lexical TDZ errors" {
  let src =
    #|typeof x;
    #|let x = 1;
  inspect(
    bytecode_compare(src),
    content="throw:ReferenceError: Cannot access 'x' before initialization",
  )
}

///|
test "bytecode typeof captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return typeof x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:number")
}

///|
test "bytecode jumps and branch completion" {
  let src =
    #|var x = 0;
    #|if (1 < 2) {
    #|  x = 3;
    #|} else {
    #|  x = 4;
    #|}
    #|x;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode do while runs body before checking condition" {
  let src =
    #|var x = 0;
    #|do {
    #|  x = x + 1;
    #|} while (false);
    #|x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode do while preserves condition order and repeats" {
  let src =
    #|var x = 0;
    #|var log = "";
    #|do {
    #|  log = log + "b";
    #|  x = x + 1;
    #|} while ((log = log + "c", x < 3));
    #|log + ":" + x;
  inspect(bytecode_compare(src), content="value:bcbcbc:3")
}

///|
test "bytecode do while statement completion comes from body" {
  let src =
    #|do {
    #|  "body";
    #|} while (false);
  inspect(bytecode_compare(src), content="value:body")
}

///|
test "bytecode do while captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 0;
    #|  return function() {
    #|    do {
    #|      x = x + 1;
    #|    } while (false);
    #|    return x;
    #|  };
    #|}
    #|var f = outer();
    #|f() + "," + f();
  inspect(bytecode_compare(src), content="value:1,2")
}

///|
test "bytecode calls and return" {
  let src =
    #|function add(a, b) {
    #|  return a + b;
    #|}
    #|add(2, 3);
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode hoists nested function declarations" {
  let src =
    #|(function() {
    #|  return f();
    #|  function f() { return 7; }
    #|})();
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode function declaration identity is stable after hoist" {
  let src =
    #|(function() {
    #|  var a = f;
    #|  function f() { return 1; }
    #|  var b = f;
    #|  return a === b;
    #|})();
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode hoists captured var bindings to undefined" {
  let src =
    #|(function() {
    #|  var f = function() { return x; };
    #|  return f();
    #|  var x = 1;
    #|})();
  inspect(bytecode_compare(src), content="value:undefined")
}

///|
test "bytecode mirrors top-level var initialization to global object" {
  let src =
    #|var x = 1;
    #|globalThis.x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode statement completion matches interpreter for declarations and skipped branches" {
  inspect(bytecode_compare("1; var x = 2;"), content="value:undefined")
  inspect(bytecode_compare("1; if (false) { 2; }"), content="value:undefined")
  inspect(
    bytecode_compare("1; while (false) { 2; }"),
    content="value:undefined",
  )
}

///|
test "bytecode sets function names for anonymous assignment targets" {
  let src =
    #|var f = function() {};
    #|f.name;
  inspect(bytecode_compare(src), content="value:f")
}

///|
test "bytecode reuses runtime name assignment semantics" {
  let src =
    #|x = 1;
    #|globalThis.x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode identifier compound assignment reuses binary semantics" {
  let src =
    #|var x = "4";
    #|x += 2;
    #|x;
  inspect(bytecode_compare(src), content="value:42")
}

///|
test "bytecode identifier compound assignment updates local slots" {
  let src =
    #|function f(a) {
    #|  var x = a;
    #|  x *= 3;
    #|  return x;
    #|}
    #|f(4);
  inspect(bytecode_compare(src), content="value:12")
}

///|
test "bytecode logical compound assignment short-circuits identifiers" {
  let src =
    #|var log = "";
    #|function rhs(v) { log = log + v; return v; }
    #|var a = 0;
    #|var b = 1;
    #|a &&= rhs("a");
    #|b &&= rhs("b");
    #|a + "," + b + "," + log;
  inspect(bytecode_compare(src), content="value:0,b,b")
}

///|
test "bytecode nullish and or compound assignment short-circuits identifiers" {
  let src =
    #|var log = "";
    #|function rhs(v) { log = log + v; return v; }
    #|var a = 1;
    #|var b = 0;
    #|var c = null;
    #|var d = "x";
    #|var e = undefined;
    #|a ||= rhs("a");
    #|b ||= rhs("b");
    #|c ??= rhs("c");
    #|d ??= rhs("d");
    #|e ??= rhs("e");
    #|a + "," + b + "," + c + "," + d + "," + e + "," + log;
  inspect(bytecode_compare(src), content="value:1,b,c,x,e,bce")
}

///|
test "bytecode identifier compound assignment captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { x += 2; return x; };
    #|}
    #|var f = outer();
    #|f() + "," + f();
  inspect(bytecode_compare(src), content="value:3,5")
}

///|
test "bytecode identifier compound assignment uses assignment reference reads" {
  let src =
    #|globalThis.x = 1;
    #|x += 2;
  inspect(
    bytecode_compare(src),
    content="throw:ReferenceError: x is not defined",
  )
}

///|
test "bytecode member compound assignment reuses property semantics" {
  let src =
    #|var o = { x: "4" };
    #|o.x += 2;
    #|o.x;
  inspect(bytecode_compare(src), content="value:42")
}

///|
test "bytecode computed compound assignment canonicalizes key once" {
  let src =
    #|var log = "";
    #|var o = { x: 1 };
    #|var key = { toString: function() { log = log + "k"; return "x"; } };
    #|function rhs() { log = log + "r"; return 2; }
    #|o[key] += rhs();
    #|o.x + ":" + log;
  inspect(bytecode_compare(src), content="value:3:kr")
}

///|
test "bytecode member compound assignment null receiver throws like interpreter" {
  let src =
    #|var target = null;
    #|target.x += 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot read properties of null (reading 'x')",
  )
}

///|
test "bytecode computed compound assignment captures outer key binding" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { o[key] += 2; return o.x; };
    #|}
    #|outer()({ x: 1 });
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode rejects non-identifier logical compound assignment targets" {
  let src =
    #|var o = { x: 0 };
    #|o.x ||= 1;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: compound assignment target",
  )
}

///|
test "bytecode resolves computed callees before arguments" {
  let src =
    #|var fns = [
    #|  function() { return "old"; },
    #|  function() { return "new"; }
    #|];
    #|function arg() {
    #|  fns.shift();
    #|  return 0;
    #|}
    #|fns[0](arg());
  inspect(bytecode_compare(src), content="value:old")
}

///|
test "bytecode member assignment writes through runtime property semantics" {
  let src =
    #|var xs = [];
    #|xs.label = 3;
    #|xs.label = xs.label + 4;
    #|xs.label;
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode computed assignment preserves object key value order" {
  let src =
    #|var log = "";
    #|var xs = [];
    #|function obj() { log = log + "o"; return xs; }
    #|function key() { log = log + "k"; return 0; }
    #|function val() { log = log + "v"; return 9; }
    #|obj()[key()] = val();
    #|log + ":" + xs[0];
  inspect(bytecode_compare(src), content="value:okv:9")
}

///|
test "bytecode member assignment null receiver throws like interpreter" {
  let src =
    #|var target = null;
    #|target.x = 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot set properties of null (setting 'x')",
  )
}

///|
test "bytecode computed assignment captures outer key binding" {
  let src =
    #|function outer() {
    #|  var key = 0;
    #|  return function(xs) {
    #|    xs[key] = 5;
    #|    return xs[0];
    #|  };
    #|}
    #|outer()([]);
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode object literal evaluates static data properties" {
  let src =
    #|var o = { a: 1, b: 2 };
    #|o.a + o.b;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode object literal preserves value evaluation order" {
  let src =
    #|var log = "";
    #|function side(x) { log = log + x; return x; }
    #|var o = { a: side("a"), b: side("b") };
    #|log + ":" + o.a + o.b;
  inspect(bytecode_compare(src), content="value:ab:ab")
}

///|
test "bytecode object literal uses the runtime object prototype" {
  let src =
    #|"toString" in {};
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode object literal sets anonymous function property names" {
  let src =
    #|var o = { f: function() {} };
    #|o.f.name;
  inspect(bytecode_compare(src), content="value:f")
}

///|
test "bytecode object literal captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 7;
    #|  return function() { return { value: x }.value; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode rejects unsupported object literal forms explicitly" {
  inspect(
    bytecode_outcome("var k = 'x'; ({ [k]: 1 });"),
    content="error:InternalError: bytecode prototype unsupported: object literal computed property",
  )
  inspect(
    bytecode_outcome("({ ...{ x: 1 } });"),
    content="error:InternalError: bytecode prototype unsupported: object literal spread property",
  )
  inspect(
    bytecode_outcome("({ get x() { return 1; } });"),
    content="error:InternalError: bytecode prototype unsupported: object literal accessor property",
  )
  inspect(
    bytecode_outcome("({ m() { return 1; } });"),
    content="error:InternalError: bytecode prototype unsupported: object literal method property",
  )
  inspect(
    bytecode_outcome("({ __proto__: null });"),
    content="error:InternalError: bytecode prototype unsupported: object literal __proto__ property",
  )
}

///|
test "bytecode new expression constructs bytecode functions" {
  let src =
    #|function C(x) {
    #|  this.x = x;
    #|}
    #|var o = new C(4);
    #|o.x + "," + (o.constructor === C);
  inspect(bytecode_compare(src), content="value:4,true")
}

///|
test "bytecode new expression ignores primitive constructor return" {
  let src =
    #|function C() {
    #|  this.x = 1;
    #|  return 9;
    #|}
    #|new C().x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode new expression preserves object constructor return" {
  let src =
    #|function C() {
    #|  return [1, 2, 3];
    #|}
    #|var o = new C();
    #|o.length + "," + o[1];
  inspect(bytecode_compare(src), content="value:3,2")
}

///|
test "bytecode new expression reuses builtin constructor semantics" {
  let src =
    #|var xs = new Array(2);
    #|xs.length;
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode new expression captures outer constructor binding" {
  let src =
    #|function outer() {
    #|  var C = function() { this.x = 5; };
    #|  return function() { return new C().x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode rejects spread arguments in new expressions" {
  let src =
    #|function C() {}
    #|new C(...[]);
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: spread argument",
  )
}

///|
test "bytecode top-level this resolves global object" {
  let src =
    #|this === globalThis;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode this uses call receiver and sloppy global fallback" {
  let src =
    #|var obj = [];
    #|obj.x = 4;
    #|obj.get = function() { return this.x; };
    #|function plain() { return this === globalThis; }
    #|obj.get() + "," + plain();
  inspect(bytecode_compare(src), content="value:4,true")
}

///|
test "bytecode strict function call keeps undefined this" {
  let src =
    #|function strictThis() {
    #|  "use strict";
    #|  return this === undefined;
    #|}
    #|strictThis();
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode rejects named function expressions until self-name binding is implemented" {
  let src =
    #|var f = function g() { return g; };
    #|f();
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: named function expression",
  )
}

///|
test "bytecode rejects arguments object until function call setup supports it" {
  let src =
    #|function f() {
    #|  return arguments[0];
    #|}
    #|f(42);
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: arguments object",
  )
}

///|
test "bytecode console log writes through shared host output helper" {
  let src =
    #|console.log(1, "two");
    #|console.log(true);
  inspect(
    bytecode_compare_with_output(src),
    content="value:undefined; output:1 two|true",
  )
}

///|
test "bytecode console member expression returns callable log function" {
  let src =
    #|var log = console.log;
    #|log("saved");
    #|"done";
  inspect(bytecode_compare_with_output(src), content="value:done; output:saved")
}

///|
test "bytecode console member errors like interpreter for unsupported methods" {
  let src =
    #|console.warn(1);
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: console.warn is not supported",
  )
}

///|
test "bytecode leaves captured vars in environment fallback" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  return function() { return b; };
    #|}
    #|outer(1)();
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode closure captures parent binding" {
  let src =
    #|function makeCounter(start) {
    #|  var count = start;
    #|  return function() {
    #|    count = count + 1;
    #|    return count;
    #|  };
    #|}
    #|var counter = makeCounter(2);
    #|counter();
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode hoists function body lexical bindings before execution" {
  let src =
    #|var x = 2;
    #|function f() {
    #|  return x;
    #|  let x = 1;
    #|}
    #|f();
  inspect(
    bytecode_compare(src),
    content="throw:ReferenceError: Cannot access 'x' before initialization",
  )
}

///|
test "bytecode rejects direct eval until caller-env semantics are implemented" {
  let src =
    #|var x = 1;
    #|eval("x = 2");
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: direct eval call",
  )
}

///|
test "bytecode block var declarations bind in the outer scope" {
  let src =
    #|var x = 1;
    #|{
    #|  var x = 2;
    #|}
    #|x;
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode block var declarations use function-local slots" {
  let src =
    #|function f() {
    #|  {
    #|    var x = 3;
    #|  }
    #|  return x;
    #|}
    #|f();
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode block var declaration completion matches interpreter" {
  inspect(bytecode_compare("{ var x = 1; }"), content="value:undefined")
  inspect(bytecode_compare("{ var x = 1; 'done'; }"), content="value:done")
  inspect(bytecode_compare("{ 'before'; var x = 1; }"), content="value:before")
}

///|
test "bytecode block var declarations can be captured" {
  let src =
    #|function outer() {
    #|  {
    #|    var x = 4;
    #|  }
    #|  return function() { return x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:4")
}

///|
test "bytecode rejects block lexical declarations until block envs are implemented" {
  let src =
    #|var x = 1;
    #|{
    #|  let x = 2;
    #|}
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: block lexical declaration",
  )
}

///|
test "bytecode rejects for lexical initializers until loop scoping is implemented" {
  let src =
    #|for (let i = 0; i < 1; i = i + 1) {
    #|}
    #|i;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: for lexical initializer",
  )
}

///|
test "bytecode control-flow var declarations preserve prior completion" {
  let src =
    #|if (true) {
    #|  1;
    #|  var x = 2;
    #|}
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode control-flow var declarations are hoisted when skipped" {
  let src =
    #|var before = typeof x;
    #|if (false) {
    #|  var x = 2;
    #|}
    #|before + "," + x;
  inspect(bytecode_compare(src), content="value:undefined,undefined")
}

///|
test "bytecode loop var declarations use function-local slots" {
  let src =
    #|function f() {
    #|  var i = 0;
    #|  while (i < 3) {
    #|    var x = i;
    #|    i = i + 1;
    #|  }
    #|  return x;
    #|}
    #|f();
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode control-flow var declarations can be captured" {
  let src =
    #|function outer(flag) {
    #|  if (flag) {
    #|    var x = 4;
    #|  }
    #|  return function() { return x; };
    #|}
    #|outer(true)() + "," + outer(false)();
  inspect(bytecode_compare(src), content="value:4,undefined")
}

///|
test "bytecode rejects control-flow function declarations until block semantics are implemented" {
  let src =
    #|if (true) {
    #|  function f() { return 1; }
    #|}
    #|f();
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: control-flow function declaration",
  )
}

///|
test "bytecode in operator finds own array index property" {
  let src =
    #|var xs = [10];
    #|0 in xs;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode in operator walks array prototype chain" {
  let src =
    #|"push" in [];
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode in operator rejects primitive rhs like interpreter" {
  let src =
    #|"x" in 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot use 'in' operator to search for 'x' in number",
  )
}

///|
test "bytecode instanceof uses runtime prototype chain semantics" {
  let src =
    #|function C() {}
    #|var o = new C();
    #|o instanceof C;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode instanceof returns false for primitive lhs" {
  let src =
    #|1 instanceof function() {};
  inspect(bytecode_compare(src), content="value:false")
}

///|
test "bytecode instanceof reuses runtime rhs error semantics" {
  let src =
    #|({}) instanceof {};
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Right-hand side of 'instanceof' is not callable",
  )
}

///|
test "bytecode instanceof honors Symbol.hasInstance" {
  let src =
    #|var C = {};
    #|C[Symbol.hasInstance] = function(value) { return value === 7; };
    #|(7 instanceof C) + "," + (8 instanceof C);
  inspect(bytecode_compare(src), content="value:true,false")
}

///|
test "bytecode closure factory workload" {
  inspect(
    bytecode_compare(BYTECODE_CLOSURE_FACTORY_PROGRAM),
    content="value:500500",
  )
}

///|
test "bytecode pipeline evaluate workload" {
  inspect(
    bytecode_compare(BYTECODE_PIPELINE_EXEC_PROGRAM),
    content="value:500500",
  )
}

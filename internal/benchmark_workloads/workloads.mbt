///|
// Canonical execution workload sources shared by benchmark and route tests.
// Keeping these values in a neutral package prevents compiler-test imports
// from depending on the executable benchmarks package.

///|
pub const FIBONACCI_SRC : String =
  #|function fib(n) {
  #|  if (n <= 1) return n;
  #|  return fib(n - 1) + fib(n - 2);
  #|}
  #|fib(30);

///|
pub const FIBONACCI_SMALL_SRC : String =
  #|function fib(n) {
  #|  if (n <= 1) return n;
  #|  return fib(n - 1) + fib(n - 2);
  #|}
  #|fib(10);

///|
/// Deep property chain access in a 10 000-iteration JS loop.
///
/// Category: Regression
/// Exercises: get_property() with 5-level object literal nesting.
///            Each JS loop body performs 5 property reads:
///              obj.a → obj.a.b → obj.a.b.c → obj.a.b.c.d → obj.a.b.c.d.e
///            Total: 50 000 get_property() calls per run().
///
/// This workload is deliberately chosen over prototype-chain access to
/// isolate the own-property lookup hot path and keep the scenario stable.
/// Prototype-chain depth and property descriptors are excluded by design.
///
/// Expected result: "420000" (10000 * 42).
pub const PROPERTY_CHAIN_SRC : String =
  #|var obj = { a: { b: { c: { d: { e: 42 } } } } };
  #|var sum = 0;
  #|for (var i = 0; i < 10000; i++) {
  #|  sum = sum + obj.a.b.c.d.e;
  #|}
  #|sum;

///|
/// Object literal construction: 1 000 objects with 5 properties each.
///
/// Expected result: "1000".
pub const OBJECT_CONSTRUCTION_SRC : String =
  #|var objects = [];
  #|for (var i = 0; i < 1000; i++) {
  #|  objects.push({
  #|    id: i,
  #|    value: i * 2,
  #|    label: "item" + i,
  #|    active: true,
  #|    score: i * i
  #|  });
  #|}
  #|objects.length;

///|
/// String method dispatch in a 100-iteration loop.
///
/// Category: Component
/// Exercises: String.prototype.toUpperCase, string concatenation,
///            string length property access.
///
/// Expected result: "600" (100 × "HELLO " = 100 × 6 chars).
pub const STRING_OPS_SRC : String =
  #|var result = "";
  #|for (var i = 0; i < 100; i++) {
  #|  result = result + "hello".toUpperCase() + " ";
  #|}
  #|result.length;

///|
/// 200 Promise reactions increment a shared counter before a timer observes it.
///
/// Expected console output: "200".
pub const MICROTASK_DRAIN_200_SRC : String =
  #|var counter = 0;
  #|var p = Promise.resolve();
  #|for (var i = 0; i < 200; i++) {
  #|  p.then(function() { counter++; });
  #|}
  #|setTimeout(function() { console.log(counter); }, 0);

///|
pub const MICROTASK_DRAIN_200_OUTPUT : String = "200"

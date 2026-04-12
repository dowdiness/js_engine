// =============================================================================
// Benchmark workloads — JavaScript source strings
//
// Each constant is a self-contained JavaScript program. Comments above each
// constant explain:
//   - what the workload exercises
//   - expected return value (for execution workloads)
//   - approximate token count (for lexer / parser workloads)
//
// Design rules:
//   - Execution workloads place the hot loop *inside* the JS source so that
//     a single run() call produces meaningful work (not just startup cost).
//   - Lexer/parser workloads are never executed; they are passed directly to
//     tokenize() or parse() to isolate the pipeline stage under test.
//   - Every execution workload documents its expected result so that callers
//     can verify correctness before the timed loop.
// =============================================================================

// ---------------------------------------------------------------------------
// Lexer workloads (tokenize() only — never executed)
// ---------------------------------------------------------------------------

///|
/// Exact token count for LEXER_SMALL_SRC (including EOF token).
/// Used by benchmarks.mbt to verify tokenizer correctness before timing.
pub const LEXER_SMALL_TOKEN_COUNT : Int = 110

///|
/// Exact token count for LEXER_LARGE_SRC (including EOF token).
/// Used by benchmarks.mbt to verify tokenizer correctness before timing.
pub const LEXER_LARGE_TOKEN_COUNT : Int = 1167

///|
/// Small lexer workload — 110 tokens (verified; see LEXER_SMALL_TOKEN_COUNT).
///
/// Covers: keywords, identifiers, numeric literals, string literals,
/// operators, delimiters, and single-line comments. Designed as a
/// regression guard: stable, low-noise, and fast per call.
pub const LEXER_SMALL_SRC : String =
  #|// Small realistic JS snippet for lexer benchmarking
  #|var counter = 0;
  #|var limit = 100;
  #|var message = "hello world";
  #|var PI = 3.14159;
  #|function increment(n) {
  #|  return n + 1;
  #|}
  #|function clamp(n, lo, hi) {
  #|  if (n < lo) return lo;
  #|  if (n > hi) return hi;
  #|  return n;
  #|}
  #|for (var i = 0; i < limit; i++) {
  #|  counter = increment(counter);
  #|}
  #|if (counter === limit) {
  #|  var result = clamp(counter, 0, 200);
  #|}
  #|result;

///|
/// Large lexer workload — 1 167 tokens (verified; see LEXER_LARGE_TOKEN_COUNT).
///
/// A realistic utility-library style JS source: constants, pure functions,
/// array helpers, algorithms, and usage code. Exercises the full range of
/// token types (template literals excluded) at a realistic source size.
pub const LEXER_LARGE_SRC : String =
  #|"use strict";
  #|var MAX_ITEMS = 1000;
  #|var MIN_VAL = 0;
  #|var DEFAULT_NAME = "unnamed";
  #|var VERSION = "1.0.0";
  #|var SCALE = 2.718281828;
  #|function identity(x) { return x; }
  #|function negate(x) { return -x; }
  #|function add(a, b) { return a + b; }
  #|function sub(a, b) { return a - b; }
  #|function mul(a, b) { return a * b; }
  #|function clamp(n, lo, hi) { return n < lo ? lo : n > hi ? hi : n; }
  #|function sign(n) { return n > 0 ? 1 : n < 0 ? -1 : 0; }
  #|function abs(n) { return n < 0 ? -n : n; }
  #|function makePoint(x, y) {
  #|  return { x: x, y: y, dist: x * x + y * y };
  #|}
  #|function makeRange(start, end, step) {
  #|  var arr = [];
  #|  for (var i = start; i < end; i = i + step) { arr.push(i); }
  #|  return arr;
  #|}
  #|function forEach(arr, fn) {
  #|  for (var i = 0; i < arr.length; i++) { fn(arr[i], i); }
  #|}
  #|function map(arr, fn) {
  #|  var result = [];
  #|  for (var i = 0; i < arr.length; i++) { result.push(fn(arr[i])); }
  #|  return result;
  #|}
  #|function filter(arr, pred) {
  #|  var result = [];
  #|  for (var i = 0; i < arr.length; i++) {
  #|    if (pred(arr[i])) { result.push(arr[i]); }
  #|  }
  #|  return result;
  #|}
  #|function reduce(arr, fn, init) {
  #|  var acc = init;
  #|  for (var i = 0; i < arr.length; i++) { acc = fn(acc, arr[i]); }
  #|  return acc;
  #|}
  #|function find(arr, pred) {
  #|  for (var i = 0; i < arr.length; i++) {
  #|    if (pred(arr[i])) { return arr[i]; }
  #|  }
  #|  return null;
  #|}
  #|function every(arr, pred) {
  #|  for (var i = 0; i < arr.length; i++) {
  #|    if (!pred(arr[i])) { return false; }
  #|  }
  #|  return true;
  #|}
  #|function some(arr, pred) {
  #|  for (var i = 0; i < arr.length; i++) {
  #|    if (pred(arr[i])) { return true; }
  #|  }
  #|  return false;
  #|}
  #|function gcd(a, b) {
  #|  while (b !== 0) { var t = b; b = a % b; a = t; }
  #|  return a;
  #|}
  #|function lcm(a, b) { return abs(a * b) / gcd(a, b); }
  #|function isPrime(n) {
  #|  if (n < 2) return false;
  #|  for (var i = 2; i * i <= n; i++) {
  #|    if (n % i === 0) return false;
  #|  }
  #|  return true;
  #|}
  #|function fibIter(n) {
  #|  if (n <= 1) return n;
  #|  var a = 0;
  #|  var b = 1;
  #|  for (var i = 2; i <= n; i++) {
  #|    var c = a + b; a = b; b = c;
  #|  }
  #|  return b;
  #|}
  #|function factorial(n) {
  #|  var result = 1;
  #|  for (var i = 2; i <= n; i++) { result = result * i; }
  #|  return result;
  #|}
  #|function isEven(n) { return n % 2 === 0; }
  #|function isOdd(n) { return n % 2 !== 0; }
  #|function square(n) { return n * n; }
  #|function cube(n) { return n * n * n; }
  #|function compose(f, g) { return function(x) { return f(g(x)); }; }
  #|function memoize(fn) {
  #|  var cache = {};
  #|  return function(n) {
  #|    if (cache[n] !== undefined) { return cache[n]; }
  #|    var result = fn(n);
  #|    cache[n] = result;
  #|    return result;
  #|  };
  #|}
  #|var nums = makeRange(1, 21, 1);
  #|var doubled = map(nums, function(x) { return x * 2; });
  #|var evens = filter(doubled, function(x) { return x % 4 === 0; });
  #|var total = reduce(evens, add, 0);
  #|var primes = filter(makeRange(2, 30, 1), isPrime);
  #|var squares = map(nums, square);
  #|var cubes = map(nums, cube);
  #|var squaredOdds = filter(squares, isOdd);
  #|var hasLarge = some(nums, function(x) { return x > 15; });
  #|var allPos = every(nums, function(x) { return x > 0; });
  #|var points = map(makeRange(0, 5, 1), function(i) {
  #|  return makePoint(i, i * SCALE);
  #|});
  #|var memoFib = memoize(fibIter);
  #|var facts = map(makeRange(1, 8, 1), factorial);
  #|var sumFacts = reduce(facts, add, 0);
  #|var squareOfOdd = compose(square, function(n) { return n * 2 + 1; });
  #|var result = total + reduce(primes, add, 0) + sumFacts;
  #|result;

// ---------------------------------------------------------------------------
// Execution workloads — passed to run() which tokenizes, parses, and executes
// ---------------------------------------------------------------------------

///|
/// Recursive Fibonacci(30).
///
/// Category: Regression
/// Exercises: function call overhead, scope chain creation, arithmetic,
///            conditional branching inside the interpreter loop.
/// Hot path: call_value() → exec_stmt() → eval_expr() recursively.
///
/// This benchmark amplifies function call cost: fib(30) makes
/// approximately 2.7 million recursive invocations.
///
/// Expected result: "832040"
pub const FIBONACCI_SRC : String =
  #|function fib(n) {
  #|  if (n <= 1) return n;
  #|  return fib(n - 1) + fib(n - 2);
  #|}
  #|fib(30);

///|
/// Sanity-check variant: Fibonacci(10) for quick verification.
/// Expected result: "55"
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
/// Expected result: "420000"   (10000 * 42)
pub const PROPERTY_CHAIN_SRC : String =
  #|var obj = { a: { b: { c: { d: { e: 42 } } } } };
  #|var sum = 0;
  #|for (var i = 0; i < 10000; i++) {
  #|  sum = sum + obj.a.b.c.d.e;
  #|}
  #|sum;

///|
/// Array.prototype.map + Array.prototype.filter on 1 000 elements.
///
/// Category: Component
/// Exercises: native callable dispatch (UserFuncExt vs NativeCallable),
///            array iteration in builtins_array.mbt, closure capture,
///            new Array allocation on each map/filter call.
///
/// Pipeline: arr.map(fn) → NativeCallable dispatch → call each element's fn
///           → filter(fn) → same path, with boolean result check.
///
/// Expected result: "334"
///   arr = [0..999], map(x => x*2) = [0,2,4,...,1998],
///   filter(x => x%6===0): keeps x where 2k%6=0 i.e. k%3=0 → 334 values.
pub const ARRAY_MAP_FILTER_SRC : String =
  #|var arr = [];
  #|for (var i = 0; i < 1000; i++) { arr.push(i); }
  #|var result = arr
  #|  .map(function(x) { return x * 2; })
  #|  .filter(function(x) { return x % 6 === 0; });
  #|result.length;

///|
/// Closure factory: create 1 000 closures, then call each once.
///
/// Category: Component
/// Exercises: closure Environment allocation (one per makeCounter call),
///            captured-variable lookup (count via parent-chain traversal),
///            function call overhead for both the factory and the returned fn.
///
/// Expected result: "500500"
///   Each counter(i) returns i+1, so sum = Σ(i+1) for i=0..999 = 500500.
pub const CLOSURE_FACTORY_SRC : String =
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
/// Object literal construction: 1 000 objects with 5 properties each.
///
/// Category: Component
/// Exercises: ObjectData allocation, property insertion (Map write),
///            string concatenation ("item" + i), array push.
///            Does NOT exercise prototype-chain or property descriptors.
///
/// Expected result: "1000"
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
/// Expected result: "600"   (100 × "HELLO " = 100 × 6 chars)
pub const STRING_OPS_SRC : String =
  #|var result = "";
  #|for (var i = 0; i < 100; i++) {
  #|  result = result + "hello".toUpperCase() + " ";
  #|}
  #|result.length;

// ---------------------------------------------------------------------------
// Pipeline workload (parser only — not executed)
// ---------------------------------------------------------------------------

///|
/// Expression-heavy source for parser throughput benchmarking.
///
/// Category: Workflow
/// Exercises: Pratt precedence climbing with ternary, binary arithmetic,
///            logical, comparison, and assignment operators interleaved.
///            Also covers: function declarations with complex bodies,
///            block statements, return expressions.
///
/// This source is passed to parse() (which includes tokenize()) to measure
/// combined lexer + parser throughput. It is never passed to run().
pub const PARSER_HEAVY_SRC : String =
  #|function f0(x, y) { return (x > y) ? x * y + x : y - x / 2; }
  #|function f1(x, y) { return x * x - y * y + 2 * x * y; }
  #|function f2(x, y) { var t = x + y; return t * t - x * x - y * y; }
  #|function f3(x, y) { return (x > 0 && y > 0) ? x + y : x - y; }
  #|function f4(x, y) { return x > y ? (x > 0 ? x : -x) : (y > 0 ? y : -y); }
  #|function f5(x, y) { return ((x + 1) * (y + 1) - 1) % (x + y + 1); }
  #|function f6(x, y) { return x * x * x - 3 * x * y * y; }
  #|function f7(x, y) { return (x || y) && !(x && y) ? 1 : 0; }
  #|function f8(x, y) { var a = x + 1; var b = y - 1; return a * b + a - b; }
  #|function f9(x, y) { return x >= y ? x % (y || 1) : y % (x || 1); }
  #|function g0(a, b, c) { return a > b ? (b > c ? a + b + c : a - c) : b + c; }
  #|function g1(a, b, c) { return (a + b) * c - a * (b + c); }
  #|function g2(a, b, c) { return a * a + b * b + c * c - a * b - b * c - a * c; }
  #|function g3(a, b, c) { return (a !== b && b !== c && a !== c) ? 1 : 0; }
  #|function g4(a, b, c) { var p = a + b + c; return p * p - a * a - b * b - c * c; }
  #|function g5(a, b, c) { return a % 2 === 0 ? b + c : b - c; }
  #|function g6(a, b, c) { return (a > 0 ? a : -a) + (b > 0 ? b : -b) + (c > 0 ? c : -c); }
  #|function g7(a, b, c) { return a > b && b > c ? a * a : b * b + c * c; }
  #|function g8(a, b, c) { var q = a > b ? a : b; return q > c ? q : c; }
  #|function g9(a, b, c) { return ((a + b) % (c || 1) + (b + c) % (a || 1)) % 100; }
  #|var r0 = f0(3, 7) + f1(2, 5) - f2(4, 1) * f3(6, 3);
  #|var r1 = f4(8, 2) - f5(5, 4) + f6(1, 3) / (f7(1, 0) + 1);
  #|var r2 = f8(9, 6) * f9(7, 5) - g0(2, 4, 6) + g1(1, 3, 5);
  #|var r3 = g2(3, 5, 7) - g3(1, 2, 3) + g4(4, 6, 8) - g5(2, 3, 5);
  #|var r4 = g6(1, 2, 3) + g7(5, 3, 1) - g8(7, 4, 2) * g9(3, 5, 7);
  #|var r5 = f0(r0, r1) + f1(r1, r2) - f2(r2, r3) + f3(r3, r4);
  #|var r6 = g0(r0, r2, r4) - g1(r1, r3, r5) + g2(r0, r3, r5);
  #|var r7 = f4(r6, r5) + g3(r4, r5, r6) - f5(r3, r2) * g4(r1, r2, r3);
  #|var r8 = g5(r7, r6, r5) + g6(r4, r3, r2) - g7(r1, r0, r7);
  #|var r9 = f6(r8, r7) - f7(r6, r5) + f8(r4, r3) * f9(r2, r1);
  #|r9;

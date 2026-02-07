///|
test "fib" {
  let array = [1, 2, 3, 4, 5].map(@js_engine.fib)
  inspect(array, content="[1, 2, 3, 5, 8]")
}

///|
test "sum" {
  let array = [1, 2, 3, 4, 5]
  inspect(@js_engine.sum(data=array), content="15")
  inspect(@js_engine.sum(data=array, start=1), content="14")
  inspect(@js_engine.sum(data=array, length=3), content="6")
  let length = None
  inspect(@js_engine.sum(data=array, length?), content="15")
}

///|
test "run facade" {
  let (output, _result) = @js_engine.run("console.log(1 + 2)")
  inspect(output, content="[\"3\"]")
}

///|
test "run fibonacci" {
  let src =
    #|function fib(n) {
    #|  if (n <= 1) { return n; }
    #|  return fib(n - 1) + fib(n - 2);
    #|}
    #|console.log(fib(10));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"55\"]")
}

///|
test "Promise.resolve" {
  let src =
    #|const p = Promise.resolve(42);
    #|p.then(x => console.log(x));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"42\"]")
}

///|
test "Promise.resolve assimilates thenables" {
  let src =
    #|Promise.resolve({
    #|  then: function(resolve) { resolve(1); }
    #|}).then(x => console.log(x));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"1\"]")
}

///|
test "Promise constructor with resolve" {
  let src =
    #|const p = new Promise((resolve, reject) => {
    #|  resolve("hello");
    #|});
    #|p.then(x => console.log(x));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"hello\"]")
}

///|
test "Promise constructor with reject" {
  let src =
    #|const p = new Promise((resolve, reject) => {
    #|  reject("error");
    #|});
    #|p.catch(x => console.log("caught: " + x));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"caught: error\"]")
}

///|
test "Promise chaining" {
  let src =
    #|Promise.resolve(1)
    #|  .then(x => x + 1)
    #|  .then(x => x * 2)
    #|  .then(x => console.log(x));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"4\"]")
}

///|
test "Promise.all" {
  let src =
    #|Promise.all([
    #|  Promise.resolve(1),
    #|  Promise.resolve(2),
    #|  Promise.resolve(3)
    #|]).then(results => console.log(results.join(",")));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"1,2,3\"]")
}

///|
test "Promise.race" {
  let src =
    #|Promise.race([
    #|  Promise.resolve("first"),
    #|  Promise.resolve("second")
    #|]).then(result => console.log(result));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"first\"]")
}

///|
test "queueMicrotask" {
  let src =
    #|console.log("start");
    #|queueMicrotask(() => console.log("microtask"));
    #|console.log("end");
  let (output, _) = @js_engine.run(src)
  // Microtask runs after synchronous code
  inspect(output, content="[\"start\", \"end\", \"microtask\"]")
}

///|
test "queueMicrotask callback gets no args" {
  let src =
    #|queueMicrotask(function() {
    #|  console.log(arguments.length);
    #|});
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"0\"]")
}

///|
test "Promise microtask ordering" {
  let src =
    #|console.log("1");
    #|Promise.resolve().then(() => console.log("2"));
    #|console.log("3");
  let (output, _) = @js_engine.run(src)
  // Promise callbacks run after synchronous code as microtasks
  inspect(output, content="[\"1\", \"3\", \"2\"]")
}

///|
test "Promise.finally" {
  let src =
    #|Promise.resolve(42)
    #|  .finally(() => console.log("finally"))
    #|  .then(x => console.log(x));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"finally\", \"42\"]")
}

///|
test "Promise.allSettled" {
  let src =
    #|Promise.allSettled([
    #|  Promise.resolve("ok"),
    #|  Promise.reject("fail")
    #|]).then(results => {
    #|  console.log(results[0].status);
    #|  console.log(results[1].status);
    #|});
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"fulfilled\", \"rejected\"]")
}

///|
test "Promise.any resolves on first fulfillment" {
  let src =
    #|Promise.any([
    #|  Promise.reject("fail-1"),
    #|  Promise.resolve("ok"),
    #|  Promise.reject("fail-2")
    #|]).then(value => console.log(value), err => console.log(err.name));
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"ok\"]")
}

///|
test "Promise.any rejects when all reject" {
  let src =
    #|Promise.any([
    #|  Promise.reject("fail-1"),
    #|  Promise.reject("fail-2")
    #|]).then(
    #|  value => console.log("resolved:" + value),
    #|  err => console.log(err.name)
    #|);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"AggregateError\"]")
}

///|
test "setTimeout basic" {
  let src =
    #|console.log("before");
    #|setTimeout(() => console.log("timer"), 0);
    #|console.log("after");
  let (output, _) = @js_engine.run(src)
  // Timer fires after synchronous code
  inspect(output, content="[\"before\", \"after\", \"timer\"]")
}

///|
test "setTimeout ordering by delay" {
  let src =
    #|setTimeout(() => console.log("slow"), 100);
    #|setTimeout(() => console.log("fast"), 0);
    #|setTimeout(() => console.log("medium"), 50);
  let (output, _) = @js_engine.run(src)
  // Timers fire in order of increasing delay
  inspect(output, content="[\"fast\", \"medium\", \"slow\"]")
}

///|
test "setTimeout with extra arguments" {
  let src =
    #|setTimeout((a, b) => console.log(a + b), 0, "hello", " world");
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"hello world\"]")
}

///|
test "clearTimeout cancels timer" {
  let src =
    #|var id = setTimeout(() => console.log("cancelled"), 0);
    #|clearTimeout(id);
    #|setTimeout(() => console.log("ran"), 0);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"ran\"]")
}

///|
test "setTimeout returns numeric ID" {
  let src =
    #|var id1 = setTimeout(() => {}, 0);
    #|var id2 = setTimeout(() => {}, 0);
    #|console.log(typeof id1);
    #|console.log(id2 > id1);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"number\", \"true\"]")
}

///|
test "microtasks run before timers" {
  let src =
    #|setTimeout(() => console.log("timer"), 0);
    #|Promise.resolve().then(() => console.log("microtask"));
    #|console.log("sync");
  let (output, _) = @js_engine.run(src)
  // Order: sync code, then microtasks, then timers
  inspect(output, content="[\"sync\", \"microtask\", \"timer\"]")
}

///|
test "setTimeout with Promise inside" {
  let src =
    #|setTimeout(() => {
    #|  console.log("timer");
    #|  Promise.resolve().then(() => console.log("microtask in timer"));
    #|}, 0);
    #|console.log("sync");
  let (output, _) = @js_engine.run(src)
  // Microtasks from timer callback drain before next timer
  inspect(output, content="[\"sync\", \"timer\", \"microtask in timer\"]")
}

///|
test "setInterval basic" {
  let src =
    #|var count = 0;
    #|var id = setInterval(() => {
    #|  count++;
    #|  console.log("tick " + count);
    #|  if (count >= 3) { clearInterval(id); }
    #|}, 100);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"tick 1\", \"tick 2\", \"tick 3\"]")
}

///|
test "setTimeout equal delays preserve insertion order" {
  let src =
    #|setTimeout(() => console.log("first"), 0);
    #|setTimeout(() => console.log("second"), 0);
    #|setTimeout(() => console.log("third"), 0);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"first\", \"second\", \"third\"]")
}

///|
test "unicode escape in identifier" {
  let src =
    #|var \u0061 = 42;
    #|console.log(a);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"42\"]")
}

///|
test "unicode escape in string literal" {
  let src =
    #|console.log("\u0048\u0065\u006C\u006C\u006F");
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"Hello\"]")
}

///|
test "unicode escape extended in string" {
  let src =
    #|console.log("\u{48}\u{65}\u{6C}\u{6C}\u{6F}");
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"Hello\"]")
}

///|
test "unicode escape identifier mid-word" {
  let src =
    #|var ab\u0063 = 10;
    #|console.log(abc);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"10\"]")
}

///|
test "ES module: export named declaration" {
  let (output, exports) = @js_engine.run_module(
    #|export const x = 42;
    #|export let y = "hello";
    #|console.log(x, y);
    ,
  )
  inspect(output, content="[\"42 hello\"]")
  inspect(exports.get("x"), content="Some(42)")
  inspect(exports.get("y"), content="Some(hello)")
}

///|
test "ES module: export function declaration" {
  let (_output, exports) = @js_engine.run_module(
    #|export function add(a, b) { return a + b; }
    ,
  )
  inspect(exports.contains("add"), content="true")
}

///|
test "ES module: export default expression" {
  let (_output, exports) = @js_engine.run_module(
    #|export default 42;
    ,
  )
  inspect(exports.get("default"), content="Some(42)")
}

///|
test "ES module: export default function" {
  let (_output, exports) = @js_engine.run_module(
    #|export default function greet() { return "hi"; }
    ,
  )
  inspect(exports.contains("default"), content="true")
}

///|
test "ES module: export default class" {
  let (_output, exports) = @js_engine.run_module(
    #|export default class Foo { constructor() { this.x = 1; } }
    ,
  )
  inspect(exports.contains("default"), content="true")
}

///|
test "ES module: export named specifiers" {
  let (_output, exports) = @js_engine.run_module(
    #|const a = 1;
    #|const b = 2;
    #|export { a, b };
    ,
  )
  inspect(exports.get("a"), content="Some(1)")
  inspect(exports.get("b"), content="Some(2)")
}

///|
test "ES module: export named with alias" {
  let (_output, exports) = @js_engine.run_module(
    #|const x = 10;
    #|export { x as myX };
    ,
  )
  inspect(exports.get("myX"), content="Some(10)")
  inspect(exports.contains("x"), content="false")
}

///|
test "ES module: export class declaration" {
  let (_output, exports) = @js_engine.run_module(
    #|export class MyClass {
    #|  getValue() { return 99; }
    #|}
    ,
  )
  inspect(exports.contains("MyClass"), content="true")
}

///|
test "ES module: import named from module" {
  let modules : Array[(String, String)] = [
    (
      "./math",
      #|export const PI = 3.14;
      #|export function double(x) { return x * 2; }
      ,
    ),
    (
      "./main",
      #|import { PI, double } from './math';
      #|console.log(PI);
      #|console.log(double(5));
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"3.14\", \"10\"]")
}

///|
test "ES module: import default" {
  let modules : Array[(String, String)] = [
    (
      "./greet",
      #|export default function() { return "hello"; }
      ,
    ),
    (
      "./main",
      #|import greet from './greet';
      #|console.log(greet());
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"hello\"]")
}

///|
test "ES module: import with alias" {
  let modules : Array[(String, String)] = [
    (
      "./data",
      #|export const value = 100;
      ,
    ),
    (
      "./main",
      #|import { value as v } from './data';
      #|console.log(v);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"100\"]")
}

///|
test "ES module: import namespace" {
  let modules : Array[(String, String)] = [
    (
      "./utils",
      #|export const a = 1;
      #|export const b = 2;
      #|export const c = 3;
      ,
    ),
    (
      "./main",
      #|import * as utils from './utils';
      #|console.log(utils.a);
      #|console.log(utils.b);
      #|console.log(utils.c);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"1\", \"2\", \"3\"]")
}

///|
test "ES module: import default and named" {
  let modules : Array[(String, String)] = [
    (
      "./mod",
      #|export default 42;
      #|export const name = "test";
      ,
    ),
    (
      "./main",
      #|import val, { name } from './mod';
      #|console.log(val);
      #|console.log(name);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"42\", \"test\"]")
}

///|
test "ES module: re-export named" {
  let modules : Array[(String, String)] = [
    (
      "./base",
      #|export const x = 10;
      #|export const y = 20;
      ,
    ),
    (
      "./reexport",
      #|export { x, y } from './base';
      ,
    ),
    (
      "./main",
      #|import { x, y } from './reexport';
      #|console.log(x + y);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"30\"]")
}

///|
test "ES module: re-export all" {
  let modules : Array[(String, String)] = [
    (
      "./source",
      #|export const a = 1;
      #|export const b = 2;
      ,
    ),
    (
      "./barrel",
      #|export * from './source';
      ,
    ),
    (
      "./main",
      #|import { a, b } from './barrel';
      #|console.log(a + b);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"3\"]")
}

///|
test "ES module: re-export all as namespace" {
  let modules : Array[(String, String)] = [
    (
      "./inner",
      #|export const val = 99;
      ,
    ),
    (
      "./outer",
      #|export * as inner from './inner';
      ,
    ),
    (
      "./main",
      #|import { inner } from './outer';
      #|console.log(inner.val);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"99\"]")
}

///|
test "ES module: side-effect import" {
  let modules : Array[(String, String)] = [
    (
      "./side-effect",
      #|console.log("side effect executed");
      ,
    ),
    (
      "./main",
      #|import './side-effect';
      #|console.log("main");
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"side effect executed\", \"main\"]")
}

///|
test "ES module: export var declaration" {
  let (_output, exports) = @js_engine.run_module(
    #|export var count = 0;
    ,
  )
  inspect(exports.get("count"), content="Some(0)")
}

///|
test "ES module: mixed exports" {
  let (_output, exports) = @js_engine.run_module(
    #|export const X = 1;
    #|export function getX() { return X; }
    #|export default "default_value";
    ,
  )
  inspect(exports.get("X"), content="Some(1)")
  inspect(exports.contains("getX"), content="true")
  inspect(exports.get("default"), content="Some(default_value)")
}

///|
test "ES module: from and as as identifiers" {
  let src =
    #|var from = 10;
    #|var as = 20;
    #|console.log(from + as);
  let (output, _) = @js_engine.run(src)
  inspect(output, content="[\"30\"]")
}

///|
test "ES module: import default and namespace" {
  let modules : Array[(String, String)] = [
    (
      "./lib",
      #|export default function() { return "default"; }
      #|export const a = 1;
      #|export const b = 2;
      ,
    ),
    (
      "./main",
      #|import def, * as lib from './lib';
      #|console.log(def());
      #|console.log(lib.a);
      #|console.log(lib.b);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"default\", \"1\", \"2\"]")
}

///|
test "ES module: re-export with alias" {
  let modules : Array[(String, String)] = [
    (
      "./original",
      #|export const value = 42;
      ,
    ),
    (
      "./alias",
      #|export { value as renamedValue } from './original';
      ,
    ),
    (
      "./main",
      #|import { renamedValue } from './alias';
      #|console.log(renamedValue);
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"42\"]")
}

///|
test "ES module: export default class with methods" {
  let modules : Array[(String, String)] = [
    (
      "./counter",
      #|export default class Counter {
      #|  constructor(start) { this.count = start; }
      #|  increment() { this.count++; return this.count; }
      #|}
      ,
    ),
    (
      "./main",
      #|import Counter from './counter';
      #|const c = new Counter(0);
      #|console.log(c.increment());
      #|console.log(c.increment());
      ,
    ),
  ]
  let (output, _) = @js_engine.run_modules(modules)
  inspect(output, content="[\"1\", \"2\"]")
}

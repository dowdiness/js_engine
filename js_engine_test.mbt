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

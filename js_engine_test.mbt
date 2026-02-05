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

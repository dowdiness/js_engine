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

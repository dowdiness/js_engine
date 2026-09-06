///|
test "Array.fromAsync awaits array-like values and mapper results in order" {
  let source =
    #|var trace = [];
    #|var input = {length: 2,
    #|  get 0() { trace.push('get0'); return Promise.resolve(3); },
    #|  get 1() { trace.push('get1'); return 4; }
    #|};
    #|Array.fromAsync(input, function (value, index) {
    #|  trace.push('map' + index);
    #|  return Promise.resolve(value * 2);
    #|}).then(function (result) {
    #|  console.log(JSON.stringify(result));
    #|  console.log(trace.join(','));
    #|});
  json_inspect(run_output_async(source), content=[
    "[6,8]", "get0,map0,get1,map1",
  ])
}

///|
test "Array.fromAsync reads array-like input without using the array iterator" {
  let source =
    #|Object.getPrototypeOf([].values()).next = function () { throw 'iterator'; };
    #|Array.fromAsync({length: 3, 0: 0, 1: 1, 2: 2}).then(function (result) {
    #|  console.log(JSON.stringify(result));
    #|});
  json_inspect(run_output_async(source), content=["[0,1,2]"])
}

///|
test "Array.fromAsync consumes sync and async iterators" {
  let source =
    #|Array.fromAsync([Promise.resolve(1), 2]).then(function (result) {
    #|  console.log('sync:' + result.join(','));
    #|});
    #|var value = Promise.resolve(7);
    #|var input = { [Symbol.asyncIterator]: function () {
    #|  var done = false;
    #|  return { next: function () {
    #|    var result = {done: done, value: value}; done = true;
    #|    return Promise.resolve(result);
    #|  }};
    #|}};
    #|Array.fromAsync(input).then(function (result) {
    #|  console.log('async:' + (result[0] === value));
    #|});
  let output = run_output_async(source)
  assert_true(output.contains("sync:1,2"))
  assert_true(output.contains("async:true"))
}

///|
test "Array.fromAsync rejects invalid mapper through its returned Promise" {
  let source =
    #|var result = Array.fromAsync([], null);
    #|console.log(result instanceof Promise);
    #|result.catch(function (error) { console.log(error.name); });
  json_inspect(run_output_async(source), content=["true", "TypeError"])
}

///|
test "rejected sync iterator values close synchronously and preserve the error" {
  let source =
    #|var marker = {}, calls = 0, reads = 0;
    #|var input = { [Symbol.iterator]: function () { return this; },
    #|  next: function () { return { value: Promise.reject(marker), done: false }; },
    #|  return: function () {
    #|    calls++;
    #|    return { get value() { reads++; throw 'must not be read'; } };
    #|  }
    #|};
    #|Array.fromAsync(input).catch(function (error) {
    #|  console.log(error === marker, calls, reads);
    #|});
  json_inspect(run_output_async(source), content=["true 1 0"])
}

///|
test "Array.fromAsync waits for async iterator close and preserves mapper error" {
  let source =
    #|var marker = {}, trace = [];
    #|var input = { [Symbol.asyncIterator]: function () { return this; },
    #|  next: function () { return Promise.resolve({ value: 1, done: false }); },
    #|  return: function () { return Promise.resolve().then(function () {
    #|    trace.push('closed'); throw 'close error';
    #|  }); }
    #|};
    #|Array.fromAsync(input, function () { throw marker; }).catch(function (error) {
    #|  console.log(error === marker, trace.join(','));
    #|});
  json_inspect(run_output_async(source), content=["true closed"])
}

///|
test "Array.fromAsync does not close an async iterator whose next rejects" {
  let source =
    #|var marker = {}, closed = false;
    #|var input = { [Symbol.asyncIterator]: function () { return this; },
    #|  next: function () { return Promise.reject(marker); },
    #|  return: function () { closed = true; return {}; }
    #|};
    #|Array.fromAsync(input).catch(function (error) {
    #|  console.log(error === marker, closed);
    #|});
  json_inspect(run_output_async(source), content=["true false"])
}

///|
test "Array.fromAsync awaits rejected sync iterator steps" {
  let source =
    #|var input = { [Symbol.iterator]: function () { return this; },
    #|  next: function () { throw 'next'; }
    #|};
    #|Array.fromAsync(input).catch(function () { console.log('rejected'); });
    #|Promise.resolve().then(function () { console.log('tick'); });
  json_inspect(run_output_async(source), content=["tick", "rejected"])
}

///|
test "Array.fromAsync uses intrinsic Promise operations" {
  let source =
    #|var then = Promise.prototype.then;
    #|var value = Promise.resolve(8);
    #|Promise.resolve = function () { throw 'resolve'; };
    #|Promise.prototype.then = function () { throw 'then'; };
    #|then.call(Array.fromAsync({length: 1, 0: value}), function (result) {
    #|  console.log(result[0]);
    #|});
  json_inspect(run_output_async(source), content=["8"])
}

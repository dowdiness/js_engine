///|
test "Array.fromAsync awaits each value and mapping before reading the next" {
  let source =
    #|var trace = [];
    #|var input = {length: 2,
    #|  get 0() { trace.push('get0'); return Promise.resolve(3); },
    #|  get 1() { trace.push('get1'); return 4; }
    #|};
    #|Array.fromAsync(input, (value, index) => {
    #|  trace.push('map' + index);
    #|  return Promise.resolve(value * 2).then(mapped => {
    #|    trace.push('mapped' + index);
    #|    return mapped;
    #|  });
    #|}).then(result => {
    #|  console.log(JSON.stringify(result));
    #|  console.log(trace.join(','));
    #|});
  json_inspect(run_output_async(source), content=[
    "[6,8]", "get0,map0,mapped0,get1,map1,mapped1",
  ])
}

///|
test "Array.fromAsync reads array-like input without using the array iterator" {
  let source =
    #|Object.getPrototypeOf([].values()).next = () => { throw 'iterator'; };
    #|Array.fromAsync({length: 3, 0: 0, 1: 1, 2: 2}).then(result => {
    #|  console.log(JSON.stringify(result));
    #|});
  json_inspect(run_output_async(source), content=["[0,1,2]"])
}

///|
test "Array.fromAsync unwraps sync iterator values" {
  let source =
    #|Array.fromAsync([Promise.resolve(1), 2]).then(result => {
    #|  console.log(JSON.stringify(result));
    #|});
  json_inspect(run_output_async(source), content=["[1,2]"])
}

///|
test "Array.fromAsync preserves async iterator values without a mapper" {
  let source =
    #|var value = Promise.resolve(7), done = false;
    #|var input = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() {
    #|    var result = {done: done, value: value};
    #|    done = true;
    #|    return Promise.resolve(result);
    #|  }
    #|};
    #|Array.fromAsync(input).then(result => {
    #|  console.log(result.length, result[0] === value);
    #|});
  json_inspect(run_output_async(source), content=["1 true"])
}

///|
test "Array.fromAsync rejects invalid mapper through its returned Promise" {
  let source =
    #|var result = Array.fromAsync([], null);
    #|console.log(result instanceof Promise);
    #|result.catch(error => console.log(error.name));
  json_inspect(run_output_async(source), content=["true", "TypeError"])
}

///|
test "rejected sync values close the iterator without reading the return value" {
  let source =
    #|var marker = {}, trace = [];
    #|var input = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { return {value: Promise.reject(marker), done: false}; },
    #|  return() {
    #|    trace.push('return');
    #|    return {get value() { trace.push('value'); throw 'close error'; }};
    #|  }
    #|};
    #|Array.fromAsync(input).catch(error => {
    #|  console.log(error === marker, trace.join(','));
    #|});
  json_inspect(run_output_async(source), content=["true return"])
}

///|
test "Array.fromAsync waits for async close and preserves the mapper error" {
  let source =
    #|var marker = {};
    #|var input = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() { return Promise.resolve({value: 1, done: false}); },
    #|  return() {
    #|    return {then(resolve, reject) {
    #|      console.log('closed');
    #|      reject('close error');
    #|    }};
    #|  }
    #|};
    #|Array.fromAsync(input, () => { throw marker; })
    #|  .catch(error => console.log(error === marker));
  json_inspect(run_output_async(source), content=["closed", "true"])
}

///|
test "Array.fromAsync does not close an async iterator whose next rejects" {
  let source =
    #|var marker = {};
    #|var input = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() { return Promise.reject(marker); },
    #|  return() { console.log('closed'); return {}; }
    #|};
    #|Array.fromAsync(input).catch(error => console.log(error === marker));
  json_inspect(run_output_async(source), content=["true"])
}

///|
test "Array.fromAsync awaits rejected sync iterator steps" {
  let source =
    #|var input = {
    #|  [Symbol.iterator]() { return this; },
    #|  next() { throw 'next'; }
    #|};
    #|Array.fromAsync(input).catch(() => console.log('rejected'));
    #|Promise.resolve().then(() => console.log('tick'));
  json_inspect(run_output_async(source), content=["tick", "rejected"])
}

///|
test "Array.fromAsync uses intrinsic Promise operations" {
  let source =
    #|var then = Promise.prototype.then;
    #|var value = Promise.resolve(8);
    #|Promise.resolve = () => { throw 'resolve'; };
    #|Promise.prototype.then = () => { throw 'then'; };
    #|then.call(Array.fromAsync({length: 1, 0: value}), result => {
    #|  console.log(result[0]);
    #|});
  json_inspect(run_output_async(source), content=["8"])
}

///|
test "for-await-of custom async iterator" {
  let src =
    #|async function f() {
    #|  let results = [];
    #|  let asyncIter = {
    #|    [Symbol.asyncIterator]() {
    #|      let values = [10, 20, 30];
    #|      return {
    #|        next() {
    #|          let v = values.shift();
    #|          return Promise.resolve(v ? {value: v, done: false} : {value: undefined, done: true});
    #|        }
    #|      };
    #|    }
    #|  };
    #|  for await (const x of asyncIter) {
    #|    results.push(x);
    #|  }
    #|  console.log(JSON.stringify(results));
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["[10,20,30]"])
}

///|
test "for-await-of empty iterable" {
  let src =
    #|async function f() {
    #|  let results = [];
    #|  for await (const x of []) {
    #|    results.push("unreachable");
    #|  }
    #|  console.log(JSON.stringify(results));
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["[]"])
}

///|
test "for-await-of break closes iterator" {
  let src =
    #|async function f() {
    #|  let results = [];
    #|  let closed = false;
    #|  let asyncIter = {
    #|    [Symbol.asyncIterator]() {
    #|      let values = [1, 2, 3];
    #|      return {
    #|        next() {
    #|          let v = values.shift();
    #|          return Promise.resolve(v ? {value: v, done: false} : {value: undefined, done: true});
    #|        },
    #|        return() {
    #|          closed = true;
    #|          return Promise.resolve({value: undefined, done: true});
    #|        }
    #|      };
    #|    }
    #|  };
    #|  for await (const x of asyncIter) {
    #|    results.push(x);
    #|    if (x === 1) break;
    #|  }
    #|  console.log(JSON.stringify(results) + ":" + closed);
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["[1]:true"])
}

///|
test "for-await-of destructuring" {
  let src =
    #|async function f() {
    #|  let results = [];
    #|  for await (const [a, b] of [[1, 2], [3, 4]]) {
    #|    results.push(a + b);
    #|  }
    #|  console.log(JSON.stringify(results));
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["[3,7]"])
}

///|
test "for-await-of member expression LHS" {
  let src =
    #|async function f() {
    #|  let obj = {};
    #|  for await (obj.x of [10, 20]) {
    #|    // empty body — assignment happens in the for-await head
    #|  }
    #|  console.log(JSON.stringify([obj.x]));
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["[20]"])
}

///|
test "for-await-of nested await in body" {
  let src =
    #|async function f() {
    #|  let results = [];
    #|  let asyncIter = {
    #|    [Symbol.asyncIterator]() {
    #|      let values = [2, 3, 5];
    #|      return {
    #|        next() {
    #|          let v = values.shift();
    #|          return Promise.resolve(v ? {value: v, done: false} : {value: undefined, done: true});
    #|        }
    #|      };
    #|    }
    #|  };
    #|  for await (const x of asyncIter) {
    #|    let doubled = await Promise.resolve(x * 2);
    #|    results.push(doubled);
    #|  }
    #|  console.log(JSON.stringify(results));
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["[4,6,10]"])
}

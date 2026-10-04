///|
test "for-await-of accepts callable Proxy async iterator method" {
  let src =
    #|async function f() {
    #|  let calls = [];
    #|  let iterable = { tag: "receiver" };
    #|  let target = function() {
    #|    calls.push(this === iterable ? "receiver" : "wrong-receiver");
    #|    calls.push(arguments.length);
    #|    return {
    #|      next() {
    #|        return Promise.resolve({value: 7, done: false});
    #|      }
    #|    };
    #|  };
    #|  iterable[Symbol.asyncIterator] = new Proxy(target, {
    #|    apply: function(target, thisArg, args) {
    #|      calls.push("apply");
    #|      return Reflect.apply(target, thisArg, args);
    #|    }
    #|  });
    #|  let result = [];
    #|  for await (const x of iterable) {
    #|    result.push(x);
    #|    break;
    #|  }
    #|  console.log(JSON.stringify([result, calls]));
    #|}
    #|f().catch(function(error) { console.log("error:" + error.name); });
  let output = run_output_async(src)
  json_inspect(output, content=["[[7],[\"apply\",\"receiver\",0]]"])
}

///|
test "for-await-of callable Proxy async iterator supports pattern head" {
  let src =
    #|async function f() {
    #|  let calls = [];
    #|  let iterable = {};
    #|  let target = function() {
    #|    calls.push(this === iterable ? "receiver" : "wrong-receiver");
    #|    calls.push(arguments.length);
    #|    let done = false;
    #|    return {
    #|      next() {
    #|        if (done) return Promise.resolve({value: undefined, done: true});
    #|        done = true;
    #|        return Promise.resolve({value: [3, 4], done: false});
    #|      }
    #|    };
    #|  };
    #|  iterable[Symbol.asyncIterator] = new Proxy(target, {
    #|    apply: function(target, thisArg, args) {
    #|      calls.push("apply");
    #|      return Reflect.apply(target, thisArg, args);
    #|    }
    #|  });
    #|  let result = [];
    #|  for await (const [a, b] of iterable) {
    #|    result.push(a + b);
    #|  }
    #|  console.log(JSON.stringify([result, calls]));
    #|}
    #|f().catch(function(error) { console.log("error:" + error.name); });
  let output = run_output_async(src)
  json_inspect(output, content=["[[7],[\"apply\",\"receiver\",0]]"])
}

///|
test "for-await-of callable Proxy async iterator supports expression head" {
  let src =
    #|async function f() {
    #|  let calls = [];
    #|  let iterable = {};
    #|  let target = function() {
    #|    calls.push(this === iterable ? "receiver" : "wrong-receiver");
    #|    calls.push(arguments.length);
    #|    let done = false;
    #|    return {
    #|      next() {
    #|        if (done) return Promise.resolve({value: undefined, done: true});
    #|        done = true;
    #|        return Promise.resolve({value: 5, done: false});
    #|      }
    #|    };
    #|  };
    #|  iterable[Symbol.asyncIterator] = new Proxy(target, {
    #|    apply: function(target, thisArg, args) {
    #|      calls.push("apply");
    #|      return Reflect.apply(target, thisArg, args);
    #|    }
    #|  });
    #|  let result = 0;
    #|  let box = { value: 0 };
    #|  for await (box.value of iterable) {
    #|    result += box.value;
    #|  }
    #|  console.log(JSON.stringify([result, box.value, calls]));
    #|}
    #|f().catch(function(error) { console.log("error:" + error.name); });
  let output = run_output_async(src)
  json_inspect(output, content=["[5,5,[\"apply\",\"receiver\",0]]"])
}

///|
test "for-await-of fallback accepts callable Proxy sync iterator with Promise values" {
  let src =
    #|async function f() {
    #|  let calls = [];
    #|  let iterable = {};
    #|  let target = function() {
    #|    calls.push(this === iterable ? "receiver" : "wrong-receiver");
    #|    calls.push(arguments.length);
    #|    let index = 0;
    #|    return {
    #|      next() {
    #|        if (index === 2) return {value: undefined, done: true};
    #|        index += 1;
    #|        return {value: Promise.resolve(index * 10), done: false};
    #|      }
    #|    };
    #|  };
    #|  iterable[Symbol.asyncIterator] = null;
    #|  iterable[Symbol.iterator] = new Proxy(target, {
    #|    apply: function(target, thisArg, args) {
    #|      calls.push("apply");
    #|      return Reflect.apply(target, thisArg, args);
    #|    }
    #|  });
    #|  let result = [];
    #|  for await (const x of iterable) {
    #|    result.push(x);
    #|  }
    #|  console.log(JSON.stringify([result, calls]));
    #|}
    #|f().catch(function(error) { console.log("error:" + error.name); });
  let output = run_output_async(src)
  json_inspect(output, content=["[[10,20],[\"apply\",\"receiver\",0]]"])
}

///|
test "for-await-of non-callable async method does not read sync method" {
  let src =
    #|async function f() {
    #|  let syncGets = 0;
    #|  let iterable = {
    #|    [Symbol.asyncIterator]: 42,
    #|    get [Symbol.iterator]() {
    #|      syncGets += 1;
    #|      return function() { return {next() { return {done: true}; }}; };
    #|    }
    #|  };
    #|  try {
    #|    for await (const x of iterable) {}
    #|    console.log("no-error:" + syncGets);
    #|  } catch (error) {
    #|    console.log(error.name + ":" + syncGets);
    #|  }
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["TypeError:0"])
}

///|
test "for-await-of rejects non-callable sync method" {
  let src =
    #|async function f() {
    #|  let iterable = { [Symbol.asyncIterator]: null, [Symbol.iterator]: 42 };
    #|  try {
    #|    for await (const x of iterable) {}
    #|    console.log("no-error");
    #|  } catch (error) {
    #|    console.log(error.name);
    #|  }
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["TypeError"])
}

///|
test "for-await-of revoked callable async Proxy rejects without sync fallback" {
  let src =
    #|async function f() {
    #|  let syncGets = 0;
    #|  let revocable = Proxy.revocable(function() { return {next() { return {done: true}; }}; }, {});
    #|  let iterable = {
    #|    [Symbol.asyncIterator]: revocable.proxy,
    #|    get [Symbol.iterator]() {
    #|      syncGets += 1;
    #|      return function() { return {next() { return {done: true}; }}; };
    #|    }
    #|  };
    #|  revocable.revoke();
    #|  try {
    #|    for await (const x of iterable) {}
    #|    console.log("no-error:" + syncGets);
    #|  } catch (error) {
    #|    console.log(error.name + ":" + syncGets);
    #|  }
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["TypeError:0"])
}

///|
test "for-await-of preserves throwing async iterator getter reason" {
  let src =
    #|async function f() {
    #|  let iterable = new Proxy({}, {
    #|    get: function(target, key) {
    #|      if (key === Symbol.asyncIterator) throw new Error("async-get");
    #|      return target[key];
    #|    }
    #|  });
    #|  try {
    #|    for await (const x of iterable) {}
    #|    console.log("no-error");
    #|  } catch (error) {
    #|    console.log(error.name + ":" + error.message);
    #|  }
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["Error:async-get"])
}

///|
test "for-await-of rejects nonobject async iterator result" {
  let src =
    #|async function f() {
    #|  let iterable = {
    #|    [Symbol.asyncIterator]: function() { return 1; }
    #|  };
    #|  try {
    #|    for await (const x of iterable) {}
    #|    console.log("no-error");
    #|  } catch (error) {
    #|    console.log(error.name);
    #|  }
    #|}
    #|f();
  let output = run_output_async(src)
  json_inspect(output, content=["TypeError"])
}

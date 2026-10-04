///|
fn async_for_of_next_result_head(kind : String) -> String {
  match kind {
    "name" => "let value"
    "pattern" => "let [value]"
    "reference" => "target.value"
    _ => "invalid-head"
  }
}

///|
fn assert_async_for_of_rejection(kind : String) -> Unit raise Error {
  let src =
    #|async function run() {
    #|  let events = [];
    #|  let reason = { marker: "next-reason" };
    #|  let iterable = {};
    #|  let iterator = {
    #|    next: function() {
    #|      events.push(["next", this === iterator, arguments.length]);
    #|      return Promise.reject(reason);
    #|    },
    #|    return: function() {
    #|      events.push(["return", this === iterator, arguments.length]);
    #|      return Promise.resolve({ value: undefined, done: true });
    #|    }
    #|  };
    #|  iterable[Symbol.asyncIterator] = function() {
    #|    events.push(["acquire", this === iterable, arguments.length]);
    #|    return iterator;
    #|  };
    #|  let target = { value: 0 };
    #|  let body = false;
    #|  try {
    #|    for await (__HEAD__ of iterable) { body = true; }
    #|    console.log(JSON.stringify(["completed", body, events]));
    #|  } catch (error) {
    #|    console.log(JSON.stringify(["rejected", error === reason, body, events]));
    #|  }
    #|}
    #|run();
  let output = run_output_async(
    src.replace(old="__HEAD__", new=async_for_of_next_result_head(kind)),
  )
  json_inspect(output, content=[
    "[\"rejected\",true,false,[[\"acquire\",true,0],[\"next\",true,0]]]",
  ])
}

///|
test "async for-of next rejection preserves reason for name head" {
  assert_async_for_of_rejection("name")
}

///|
test "async for-of next rejection preserves reason for pattern head" {
  assert_async_for_of_rejection("pattern")
}

///|
test "async for-of next rejection preserves reason for reference head" {
  assert_async_for_of_rejection("reference")
}

///|
fn assert_async_for_of_done_result(kind : String) -> Unit raise Error {
  let src =
    #|async function run() {
    #|  let nextCalls = 0;
    #|  let doneGets = 0;
    #|  let valueGets = 0;
    #|  let returnCalls = 0;
    #|  let body = false;
    #|  let iterator = {
    #|    next: function() {
    #|      nextCalls += 1;
    #|      return Promise.resolve({
    #|        get done() { doneGets += 1; return true; },
    #|        get value() { valueGets += 1; throw { marker: "value-read" }; }
    #|      });
    #|    },
    #|    return: function() {
    #|      returnCalls += 1;
    #|      return Promise.resolve({ value: undefined, done: true });
    #|    }
    #|  };
    #|  let iterable = { [Symbol.asyncIterator]: function() { return iterator; } };
    #|  let target = { value: 0 };
    #|  try {
    #|    for await (__HEAD__ of iterable) { body = true; }
    #|    console.log(JSON.stringify(["completed", body, nextCalls, doneGets, valueGets, returnCalls]));
    #|  } catch (error) {
    #|    console.log(JSON.stringify(["error", error.marker, body, nextCalls, doneGets, valueGets, returnCalls]));
    #|  }
    #|}
    #|run();
  let output = run_output_async(
    src.replace(old="__HEAD__", new=async_for_of_next_result_head(kind)),
  )
  json_inspect(output, content=["[\"completed\",false,1,1,0,0]"])
}

///|
test "async for-of done result skips value for name head" {
  assert_async_for_of_done_result("name")
}

///|
test "async for-of done result skips value for pattern head" {
  assert_async_for_of_done_result("pattern")
}

///|
test "async for-of done result skips value for reference head" {
  assert_async_for_of_done_result("reference")
}

///|
fn assert_async_for_of_object_result(kind : String) -> Unit raise Error {
  let src =
    #|async function run() {
    #|  let shapes = ["object", "array", "map", "set", "proxy"];
    #|  let reads = [];
    #|  let doneReads = 0;
    #|  let doneValueReads = 0;
    #|  let body = [];
    #|  let events = [];
    #|  let nextIndex = 0;
    #|  function makeResult(shape, index) {
    #|    let result;
    #|    if (shape === "object") result = {};
    #|    else if (shape === "array") result = [];
    #|    else if (shape === "map") result = new Map();
    #|    else if (shape === "set") result = new Set();
    #|    else result = new Proxy({}, {});
    #|    let counts = [shape, 0, 0];
    #|    reads.push(counts);
    #|    Object.defineProperty(result, "done", {
    #|      configurable: true,
    #|      get: function() { counts[1] += 1; return false; }
    #|    });
    #|    Object.defineProperty(result, "value", {
    #|      configurable: true,
    #|      get: function() { counts[2] += 1; return [index + 1]; }
    #|    });
    #|    return result;
    #|  }
    #|  let iterator = {
    #|    next: function() {
    #|      events.push(["next", this === iterator, arguments.length]);
    #|      if (nextIndex < shapes.length) {
    #|        let index = nextIndex;
    #|        nextIndex += 1;
    #|        return Promise.resolve(makeResult(shapes[index], index));
    #|      }
    #|      let done = {};
    #|      Object.defineProperty(done, "done", {
    #|        get: function() { doneReads += 1; return true; }
    #|      });
    #|      Object.defineProperty(done, "value", {
    #|        get: function() { doneValueReads += 1; throw { marker: "done-value-read" }; }
    #|      });
    #|      return Promise.resolve(done);
    #|    }
    #|  };
    #|  let iterable = { [Symbol.asyncIterator]: function() { return iterator; } };
    #|  let target = { value: 0 };
    #|  try {
    #|    for await (__HEAD__ of iterable) { __BODY__ }
    #|    console.log(JSON.stringify([body, reads, doneReads, doneValueReads, events]));
    #|  } catch (error) {
    #|    console.log(JSON.stringify(["error", error.name, error.marker]));
    #|  }
    #|}
    #|run();
  let body = match kind {
    "name" => "body.push(value[0]);"
    "pattern" => "body.push(value);"
    "reference" => "body.push(target.value[0]);"
    _ => "body.push(undefined);"
  }
  let source = src.replace(
    old="__HEAD__",
    new=async_for_of_next_result_head(kind),
  )
  let output = run_output_async(source.replace(old="__BODY__", new=body))
  json_inspect(output, content=[
    "[[1,2,3,4,5],[[\"object\",1,1],[\"array\",1,1],[\"map\",1,1],[\"set\",1,1],[\"proxy\",1,1]],1,0,[[\"next\",true,0],[\"next\",true,0],[\"next\",true,0],[\"next\",true,0],[\"next\",true,0],[\"next\",true,0]]]",
  ])
}

///|
test "async for-of accepts object-valued results for name head" {
  assert_async_for_of_object_result("name")
}

///|
test "async for-of accepts object-valued results for pattern head" {
  assert_async_for_of_object_result("pattern")
}

///|
test "async for-of accepts object-valued results for reference head" {
  assert_async_for_of_object_result("reference")
}

///|
fn async_for_of_non_object_next_source() -> String {
  let src =
    #|async function run() {
    #|  let values = [undefined, null, 1, true, "text", Symbol("s"), 1n];
    #|  let results = [];
    #|  async function check(nextResult) {
    #|    let body = 0;
    #|    let close = 0;
    #|    let first = true;
    #|    let iterator = {
    #|      next: function() {
    #|        if (first) {
    #|          first = false;
    #|          return Promise.resolve(nextResult);
    #|        }
    #|        return Promise.resolve({ value: undefined, done: true });
    #|      },
    #|      return: function() {
    #|        close += 1;
    #|        return Promise.resolve({ value: undefined, done: true });
    #|      }
    #|    };
    #|    let iterable = { [Symbol.asyncIterator]: function() { return iterator; } };
    #|    let target = { value: "unchanged" };
    #|    try {
    #|      for await (__HEAD__ of iterable) { body += 1; }
    #|      results.push(["completed", body, close]);
    #|    } catch (error) {
    #|      results.push([error.name, body, close]);
    #|    }
    #|  }
    #|  for (let i = 0; i < values.length; i += 1) {
    #|    await check(values[i]);
    #|  }
    #|  console.log(JSON.stringify(results));
    #|}
    #|run();
  src
}

///|
fn assert_async_for_of_non_object_next_result(
  kind : String,
) -> Unit raise Error {
  let src = async_for_of_non_object_next_source()
  let output = run_output_async(
    src.replace(old="__HEAD__", new=async_for_of_next_result_head(kind)),
  )
  json_inspect(output, content=[
    "[[\"TypeError\",0,0],[\"TypeError\",0,0],[\"TypeError\",0,0],[\"TypeError\",0,0],[\"TypeError\",0,0],[\"TypeError\",0,0],[\"TypeError\",0,0]]",
  ])
}

///|
test "async for-of rejects every primitive next result for name head" {
  assert_async_for_of_non_object_next_result("name")
}

///|
test "async for-of rejects every primitive next result for pattern head" {
  assert_async_for_of_non_object_next_result("pattern")
}

///|
test "async for-of rejects every primitive next result for reference head" {
  assert_async_for_of_non_object_next_result("reference")
}

///|
fn async_from_sync_primitive_source(head : String) -> String {
  let source =
    #|async function run() {
    #|  var values = [undefined, null, false, 1, "text", Symbol("s"), 1n];
    #|  var results = [];
    #|  async function check(nextResult) {
    #|    var body = 0;
    #|    var nextCalls = 0;
    #|    var closeCalls = 0;
    #|    var setterCalls = 0;
    #|    var defaultCalls = 0;
    #|    var iterable = {};
    #|    var target = {};
    #|    Object.defineProperty(target, "value", {
    #|      get: function() { return 0; },
    #|      set: function(_) { setterCalls += 1; }
    #|    });
    #|    function defaultValue() {
    #|      defaultCalls += 1;
    #|      return 99;
    #|    }
    #|    iterable[Symbol.asyncIterator] = null;
    #|    iterable[Symbol.iterator] = function() {
    #|      return {
    #|        next: function() {
    #|          nextCalls += 1;
    #|          if (nextCalls === 1) return nextResult;
    #|          return { value: undefined, done: true };
    #|        },
    #|        return: function() {
    #|          closeCalls += 1;
    #|          return { value: undefined, done: true };
    #|        }
    #|      };
    #|    };
    #|    try {
    #|      for await (__HEAD__ of iterable) { body += 1; }
    #|      results.push(["completed", body, nextCalls, closeCalls, setterCalls, defaultCalls]);
    #|    } catch (error) {
    #|      results.push(["rejected", error.name, body, nextCalls, closeCalls, setterCalls, defaultCalls]);
    #|    }
    #|  }
    #|  for (var i = 0; i < values.length; i += 1) await check(values[i]);
    #|  console.log(JSON.stringify(results));
    #|}
    #|run();
  source.replace(old="__HEAD__", new=head)
}

///|
fn assert_async_from_sync_primitive_head(head : String) -> Unit raise Error {
  let output = run_output_async(async_from_sync_primitive_source(head))
  json_inspect(output, content=[
    "[[\"rejected\",\"TypeError\",0,1,0,0,0],[\"rejected\",\"TypeError\",0,1,0,0,0],[\"rejected\",\"TypeError\",0,1,0,0,0],[\"rejected\",\"TypeError\",0,1,0,0,0],[\"rejected\",\"TypeError\",0,1,0,0,0],[\"rejected\",\"TypeError\",0,1,0,0,0],[\"rejected\",\"TypeError\",0,1,0,0,0]]",
  ])
}

///|
test "Async-from-Sync next rejects primitive results for name head" {
  assert_async_from_sync_primitive_head("const value")
}

///|
test "Async-from-Sync next rejects primitive results for pattern head" {
  assert_async_from_sync_primitive_head("const [value = defaultValue()]")
}

///|
test "Async-from-Sync next rejects primitive results for reference head" {
  assert_async_from_sync_primitive_head("target.value")
}

///|
test "Async-from-Sync next validates Number before getters and accepts object results" {
  let source =
    #|async function run() {
    #|  var results = [];
    #|  var kinds = ["object", "array", "map", "set", "proxy"];
    #|  var candidates = [];
    #|  for (var i = 0; i < kinds.length; i += 1) {
    #|    var kind = kinds[i];
    #|    var candidate = { done: false, value: kind };
    #|    if (kind === "array") {
    #|      candidate = [];
    #|      candidate.done = false;
    #|      candidate.value = kind;
    #|    } else if (kind === "map") {
    #|      candidate = new Map();
    #|      candidate.done = false;
    #|      candidate.value = kind;
    #|    } else if (kind === "set") {
    #|      candidate = new Set();
    #|      candidate.done = false;
    #|      candidate.value = kind;
    #|    } else if (kind === "proxy") {
    #|      candidate = new Proxy(candidate, {});
    #|    }
    #|    candidates.push(candidate);
    #|  }
    #|  var candidateIndex = 0;
    #|  var body = [];
    #|  var iterable = {};
    #|  iterable[Symbol.asyncIterator] = null;
    #|  iterable[Symbol.iterator] = function() {
    #|    return {
    #|      next: function() {
    #|        if (candidateIndex === candidates.length) return { done: true };
    #|        var candidate = candidates[candidateIndex];
    #|        candidateIndex += 1;
    #|        return candidate;
    #|      }
    #|    };
    #|  };
    #|  try {
    #|    for await (const item of iterable) {
    #|      body.push(item === kinds[body.length]);
    #|    }
    #|    results.push(["fulfilled", body]);
    #|  } catch (error) {
    #|    results.push(["rejected", error.name, body]);
    #|  }
    #|  var priorDone = Object.getOwnPropertyDescriptor(Number.prototype, "done");
    #|  var priorValue = Object.getOwnPropertyDescriptor(Number.prototype, "value");
    #|  var doneGets = 0;
    #|  var valueGets = 0;
    #|  Object.defineProperty(Number.prototype, "done", {
    #|    configurable: true,
    #|    get: function() { doneGets += 1; return false; }
    #|  });
    #|  Object.defineProperty(Number.prototype, "value", {
    #|    configurable: true,
    #|    get: function() { valueGets += 1; return "wrong"; }
    #|  });
    #|  var primitiveBody = [];
    #|  var primitiveClose = 0;
    #|  var primitiveIterable = {};
    #|  primitiveIterable[Symbol.asyncIterator] = null;
    #|  primitiveIterable[Symbol.iterator] = function() {
    #|    return {
    #|      next: function() { return 7; },
    #|      return: function() {
    #|        primitiveClose += 1;
    #|        return { value: undefined, done: true };
    #|      }
    #|    };
    #|  };
    #|  try {
    #|    for await (const value of primitiveIterable) {
    #|      primitiveBody.push(value);
    #|      break;
    #|    }
    #|    results.push(["completed", primitiveBody, primitiveClose]);
    #|  } catch (error) {
    #|    results.push(["rejected", error.name, primitiveBody, primitiveClose]);
    #|  }
    #|  if (priorDone === undefined) delete Number.prototype.done;
    #|  else Object.defineProperty(Number.prototype, "done", priorDone);
    #|  if (priorValue === undefined) delete Number.prototype.value;
    #|  else Object.defineProperty(Number.prototype, "value", priorValue);
    #|  console.log(JSON.stringify([doneGets, valueGets, results]));
    #|}
    #|run();
  let output = run_output_async(source)
  json_inspect(output, content=[
    "[0,0,[[\"fulfilled\",[true,true,true,true,true]],[\"rejected\",\"TypeError\",[],0]]]",
  ])
}

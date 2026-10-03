///|
test "async delegation rejection enters catch and finally" {
  let source =
    #|var trace = [];
    #|var iterable = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() { return Promise.reject("boom"); },
    #|  return() { trace.push("close"); return Promise.resolve({done: true}); }
    #|};
    #|async function* sample() {
    #|  try {
    #|    yield* iterable;
    #|    trace.push("after");
    #|  } catch (error) {
    #|    trace.push("catch:" + error);
    #|  } finally {
    #|    trace.push("finally");
    #|  }
    #|}
    #|sample().next().then(
    #|  result => console.log(JSON.stringify([result.done, trace])),
    #|  error => console.log(JSON.stringify([String(error), trace]))
    #|);
  let output = run_output_async(source)
  json_inspect(output, content=["[true,[\"catch:boom\",\"finally\"]]"])
}

///|
test "async delegation next throw and return rejection preserve outer handlers" {
  let source =
    #|var trace = [], reason = {}, calls = 0;
    #|var iterable = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() {
    #|    trace.push("next");
    #|    return calls++ === 0
    #|      ? Promise.resolve({value: 1, done: false})
    #|      : Promise.reject(reason);
    #|  },
    #|  throw() { trace.push("throw"); return Promise.reject(reason); },
    #|  return() { trace.push("return"); return Promise.reject(reason); }
    #|};
    #|async function* sample() {
    #|  try { yield* iterable; }
    #|  catch (error) { trace.push("catch:" + (error === reason)); return "handled"; }
    #|  finally { trace.push("finally"); }
    #|}
    #|var generator = sample();
    #|generator.next().then(first => generator[operation]("input").then(
    #|  result => console.log(JSON.stringify([
    #|    first.value, first.done, result.value, result.done, trace
    #|  ])),
    #|  error => console.log("unexpected rejection")
    #|));
  for operation in ["next", "throw", "return"] {
    let output = run_output_async("var operation = '\{operation}';\n" + source)
    assert_eq(output, [
      "[1,false,\"handled\",true,[\"next\",\"\{operation}\",\"catch:true\",\"finally\"]]",
    ])
  }
}

///|
test "async delegation rejection waits for a yielding finally" {
  let source =
    #|var trace = [];
    #|var iterable = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() { return Promise.reject("boom"); }
    #|};
    #|async function* sample() {
    #|  try { yield* iterable; }
    #|  finally { trace.push("start"); yield "cleanup"; trace.push("end"); }
    #|}
    #|var generator = sample();
    #|generator.next().then(result => {
    #|  console.log(JSON.stringify([result.value, result.done]));
    #|  return generator.next();
    #|}).then(
    #|  result => console.log("unexpected fulfillment"),
    #|  error => console.log(JSON.stringify([error, trace]))
    #|);
  let output = run_output_async(source)
  json_inspect(output, content=[
    "[\"cleanup\",false]", "[\"boom\",[\"start\",\"end\"]]",
  ])
}

///|
test "async delegation rejection can yield from catch before completion" {
  let source =
    #|var trace = [];
    #|var iterable = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() { return Promise.reject("boom"); }
    #|};
    #|async function* sample() {
    #|  try { yield* iterable; }
    #|  catch (error) { trace.push("catch"); yield error; return "recovered"; }
    #|  finally { trace.push("finally"); }
    #|}
    #|var generator = sample();
    #|generator.next().then(first => generator.next().then(
    #|  last => console.log(JSON.stringify([
    #|    first.value, first.done, last.value, last.done, trace
    #|  ])),
    #|  error => console.log("unexpected rejection")
    #|));
  let output = run_output_async(source)
  json_inspect(output, content=[
    "[\"boom\",false,\"recovered\",true,[\"catch\",\"finally\"]]",
  ])
}

///|
test "uncaught async delegation rejection releases generator execution state" {
  let interp = @interpreter.new_interpreter()
  let source =
    #|var iterable = {
    #|  [Symbol.asyncIterator]() { return this; },
    #|  next() { return Promise.reject("boom"); }
    #|};
    #|async function* sample() { yield* iterable; }
    #|var generator = sample();
    #|generator.next().catch(error => console.log(error));
  let _ = interp.run(@parser.parse(source).stmts)
  interp.run_microtasks()
  json_inspect(interp.host.output, content=["boom"])
  let owner = interp.generator_objects.get(0).unwrap()
  assert_true(owner.state is @runtime.Completed)
  assert_true(owner.env is None)
  assert_true(owner.yield_resume_values.is_empty())
  let _ = interp.run(
    @parser.parse("generator.next().then(result => console.log(result.done));").stmts,
  )
  interp.run_microtasks()
  json_inspect(interp.host.output, content=["boom", "true"])
}

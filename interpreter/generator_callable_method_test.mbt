///|
test "generator yield star accepts callable Proxy next" {
  let output = run_output(
    (
      #|let events = [];
      #|let calls = 0;
      #|let iterator = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: new Proxy(function(value) {
      #|    calls++;
      #|    events.push((this === iterator) + ":" + arguments.length + ":" + (value === undefined ? "undefined" : String(value)));
      #|    return calls === 1 ? { value: 1, done: false } : { value: 2, done: true };
      #|  }, {}),
      #|};
      #|function* outer() { return yield* iterator; }
      #|let it = outer();
      #|try {
      #|  let first = it.next();
      #|  let second = it.next(42);
      #|  console.log(first.value, first.done);
      #|  console.log(second.value, second.done);
      #|} catch (e) {
      #|  console.log("caught:" + e.name + ":" + e.message);
      #|}
      #|console.log(events.join("|"));
    ),
  )
  json_inspect(output, content=[
    "1 false", "2 true", "true:1:undefined|true:1:42",
  ])
}

///|
test "generator yield star accepts callable Proxy throw" {
  let output = run_output(
    (
      #|let events = [];
      #|let calls = 0;
      #|let reason = { marker: "reason" };
      #|let iterator = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function(value) {
      #|    calls++;
      #|    events.push("next:" + (this === iterator) + ":" + arguments.length + ":" + (value === undefined ? "undefined" : String(value)));
      #|    return calls === 1 ? { value: "first", done: false } : { value: "next", done: true };
      #|  },
      #|  throw: new Proxy(function(value) {
      #|    events.push("throw:" + (this === iterator) + ":" + arguments.length + ":" + (value === reason));
      #|    return { value: "thrown", done: false };
      #|  }, {}),
      #|};
      #|function* outer() { yield* iterator; console.log("after"); }
      #|let it = outer();
      #|try {
      #|  let first = it.next();
      #|  let thrown = it.throw(reason);
      #|  console.log(first.value, first.done);
      #|  console.log(thrown.value, thrown.done);
      #|  let done = it.next();
      #|  console.log(done.done);
      #|} catch (e) {
      #|  console.log("caught:" + e.name + ":" + e.message);
      #|}
      #|console.log(events.join("|"));
    ),
  )
  json_inspect(output, content=[
    "first false", "thrown false", "after", "true", "next:true:1:undefined|throw:true:1:true|next:true:1:undefined",
  ])
}

///|
test "generator yield star accepts callable Proxy return" {
  let output = run_output(
    (
      #|let events = [];
      #|let iterator = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  return: new Proxy(function(value) {
      #|    events.push((this === iterator) + ":" + arguments.length + ":" + value);
      #|    return { value: 23, done: true };
      #|  }, {}),
      #|};
      #|function* outer() {
      #|  try { return yield* iterator; }
      #|  finally { console.log("finally"); }
      #|}
      #|let it = outer();
      #|try {
      #|  let first = it.next();
      #|  let returned = it.return(13);
      #|  console.log(first.value, first.done);
      #|  console.log(returned.value, returned.done);
      #|} catch (e) {
      #|  console.log("caught:" + e.name + ":" + e.message);
      #|}
      #|console.log(events.join("|"));
    ),
  )
  json_inspect(output, content=["finally", "1 false", "23 true", "true:1:13"])
}

///|
test "generator missing throw closes through callable Proxy return" {
  let output = run_output(
    (
      #|let events = [];
      #|let iterator = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  return: new Proxy(function() {
      #|    events.push((this === iterator) + ":" + arguments.length);
      #|    return { done: true };
      #|  }, {}),
      #|};
      #|function* outer() {
      #|  try { yield* iterator; }
      #|  catch (e) { console.log(e instanceof TypeError); }
      #|}
      #|let it = outer();
      #|let first = it.next();
      #|let resumed = it.throw("reason");
      #|console.log(first.value, first.done);
      #|console.log(resumed.done);
      #|console.log(events.join("|"));
    ),
  )
  json_inspect(output, content=["true", "1 false", "true", "true:0"])
}

///|
test "generator delegation preserves abrupt getter identity and single lookup" {
  let output = run_output(
    (
      #|let events = [];
      #|let throwReason = { marker: "throw getter" };
      #|let throwIterator = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  get throw() { events.push("throw-get"); throw throwReason; },
      #|  return: function() { events.push("throw-fallback"); return { done: true }; },
      #|};
      #|function* throwOuter() {
      #|  try { yield* throwIterator; }
      #|  catch (e) { console.log(e === throwReason, e.marker); }
      #|}
      #|let throwIt = throwOuter();
      #|throwIt.next();
      #|let throwResult = throwIt.throw("input");
      #|console.log(throwResult.done);
      #|let returnReason = { marker: "return getter" };
      #|let returnIterator = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  get return() { events.push("return-get"); throw returnReason; },
      #|};
      #|function* returnOuter() {
      #|  try { yield* returnIterator; }
      #|  catch (e) { console.log(e === returnReason, e.marker); }
      #|}
      #|let returnIt = returnOuter();
      #|returnIt.next();
      #|let returnResult = returnIt.return(13);
      #|console.log(returnResult.done);
      #|console.log(events.join("|"));
    ),
  )
  json_inspect(output, content=[
    "true throw getter", "true", "true return getter", "true", "throw-get|return-get",
  ])
}

///|
test "generator delegation distinguishes noncallable and nullish methods" {
  let output = run_output(
    (
      #|let events = [];
      #|let badThrow = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  throw: 7,
      #|  return: function() { events.push("bad-throw-return"); return { done: true }; },
      #|};
      #|function* badThrowOuter() {
      #|  try { yield* badThrow; }
      #|  catch (e) { events.push("bad-throw:" + e.name); }
      #|}
      #|let badThrowIt = badThrowOuter();
      #|badThrowIt.next();
      #|events.push("bad-throw-done:" + badThrowIt.throw("input").done);
      #|let badReturn = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  return: 7,
      #|};
      #|function* badReturnOuter() {
      #|  try { yield* badReturn; }
      #|  catch (e) { events.push("bad-return:" + e.name); }
      #|}
      #|let badReturnIt = badReturnOuter();
      #|badReturnIt.next();
      #|events.push("bad-return-done:" + badReturnIt.return(13).done);
      #|let absentThrow = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  throw: null,
      #|  return: function() { events.push("absent-throw-return:" + arguments.length); return { done: true }; },
      #|};
      #|function* absentThrowOuter() {
      #|  try { yield* absentThrow; }
      #|  catch (e) { events.push("absent-throw:" + e.name); }
      #|}
      #|let absentThrowIt = absentThrowOuter();
      #|absentThrowIt.next();
      #|events.push("absent-throw-done:" + absentThrowIt.throw("input").done);
      #|let absentReturn = {
      #|  [Symbol.iterator]() { return this; },
      #|  next: function() { return { value: 1, done: false }; },
      #|  return: undefined,
      #|};
      #|function* absentReturnOuter() {
      #|  try { return yield* absentReturn; }
      #|  finally { events.push("absent-return-finally"); }
      #|}
      #|let absentReturnIt = absentReturnOuter();
      #|absentReturnIt.next();
      #|let absentReturnResult = absentReturnIt.return(13);
      #|events.push("absent-return:" + absentReturnResult.value + ":" + absentReturnResult.done);
      #|console.log(events.join("|"));
    ),
  )
  json_inspect(output, content=[
    "bad-throw:TypeError|bad-throw-done:true|bad-return:TypeError|bad-return-done:true|absent-throw-return:0|absent-throw:TypeError|absent-throw-done:true|absent-return-finally|absent-return:13:true",
  ])
}

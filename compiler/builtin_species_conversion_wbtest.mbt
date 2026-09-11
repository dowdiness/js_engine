///|
test "builtin species getters inherit Function prototype in bytecode conversion" {
  let source =
    #|function probe(ctor) {
    #|  var getter = Object.getOwnPropertyDescriptor(ctor, Symbol.species).get;
    #|  try {
    #|    return JSON.stringify([
    #|      Object.getPrototypeOf(getter) === Function.prototype,
    #|      '' + getter,
    #|      getter.call(ctor) === ctor
    #|    ]);
    #|  } finally {}
    #|}
  for ctor in ["Array", "RegExp", "Map", "Set"] {
    let program = source + "probe(" + ctor + ");"
    let (actual, evidence) = candidate_run_with_evidence_for_wb(program)
    assert_eq(
      actual.to_string(),
      "[true,\"function get [Symbol.species]() { [native code] }\",true]",
      msg=ctor,
    )
    let function = prepare_candidate_program(@parser.parse(program).stmts).root.children[0]
    assert_candidate_function_started_for_wb(
      evidence,
      function,
      CandidateBytecodeExecutor,
    )
  }
}

///|
test "builtin descriptor functions receive their realm without invocation" {
  let source =
    #|function probe(fn) {
    #|  return JSON.stringify([Object.getPrototypeOf(fn) === Function.prototype, '' + fn]);
    #|}
  for
    (accessor, name) in [
      (
        "Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get",
        "get byteLength",
      ),
      ("Object.getOwnPropertyDescriptor(Map.prototype, 'size').get", "get size"),
      (
        "Object.getOwnPropertyDescriptor(Object.prototype, '__proto__').set", "set __proto__",
      ),
    ] {
    let (actual, _) = candidate_run_with_evidence_for_wb(
      source + "probe(" + accessor + ");",
    )
    assert_eq(
      actual.to_string(),
      "[true,\"function " + name + "() { [native code] }\"]",
      msg=accessor,
    )
  }
}

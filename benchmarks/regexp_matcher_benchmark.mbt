// RegExp matcher-retention microbenchmark for issue #726.
//
// Run the focused row with:
//   make bench-focus ARGS="--runs 5 --rows regexp/retained_matcher"
//
// The RegExp is constructed once per interpreter run, then the same immutable
// matcher is executed repeatedly. The correctness check intentionally runs
// before b.bench so timing only covers the workload under investigation.

///|
const REGEXP_RETAINED_MATCHER_SRC : String =
  #|var re = /(?:Array|ArrayBuffer|AsyncFunction|AsyncGenerator|BigInt|Boolean|DataView|Date|Error|EvalError|FinalizationRegistry|Float32Array|Float64Array|Function|Generator|Infinity|Int8Array|Int16Array|Int32Array|Iterator|Map|NaN|Number|Object|Promise|Proxy|RangeError|ReferenceError|RegExp|Set|String|Symbol|SyntaxError|TypeError|URIError|Uint8Array|Uint8ClampedArray|Uint16Array|Uint32Array|WeakMap|WeakRef|WeakSet|decodeURI|decodeURIComponent|encodeURI|encodeURIComponent|eval|isFinite|isNaN|parseFloat|parseInt|undefined)(?:[.]prototype)?/g;
  #|var input = "prefix Object.prototype and Function.prototype then RegExp.prototype";
  #|var total = 0;
  #|for (var i = 0; i < 32; i++) {
  #|  re.lastIndex = 0;
  #|  var match = re.exec(input);
  #|  total += match[0].length;
  #|}
  #|total

///|
test "regexp/retained_matcher" (b : @bench.T) {
  expect("regexp/retained_matcher", REGEXP_RETAINED_MATCHER_SRC, "512")
  b.bench(fn() {
    try {
      let (_, value) = @lib.run(REGEXP_RETAINED_MATCHER_SRC)
      b.keep(value)
    } catch {
      _ => abort("regexp/retained_matcher: run raised")
    }
  })
}

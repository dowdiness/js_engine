// RegExp matcher-retention microbenchmark for issue #726.
//
// Run the focused row with:
//   make bench-focus ARGS="--runs 5 --rows regexp/retained_matcher"
//
// The RegExp is constructed once per interpreter run, then the same immutable
// matcher is executed repeatedly. The correctness check intentionally runs
// before b.bench so timing only covers the workload under investigation.

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

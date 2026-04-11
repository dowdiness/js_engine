///|
/// Benchmark category — controls which benchmarks run in a given context.
///
/// Regression: low-noise, stable scenarios. Run by default and in CI.
/// Component:  isolated subsystem benchmarks. Run with --all.
/// Workflow:   end-to-end scenarios with higher variance. Run with --all.
pub enum Category {
  Regression
  Component
  Workflow
}

///|
pub fn Category::label(self : Category) -> String {
  match self {
    Regression => "regression"
    Component => "component"
    Workflow => "workflow"
  }
}

///|
/// Immutable result snapshot produced by a single benchmark run.
pub struct BenchResult {
  /// Stable identifier, e.g. "lexer/small" or "exec/fibonacci_30".
  name : String
  category : Category
  /// Discarded warmup iterations (JIT / cache warm-up).
  warmup : Int
  /// Measured outer iterations used for statistics.
  iterations : Int
  /// Inner repetitions per outer iteration.
  /// For sub-millisecond operations use group_size > 1 to reduce
  /// timer-resolution noise. Reported timing is always per-call.
  group_size : Int
  /// Per-call timing statistics in milliseconds.
  mean_ms : Double
  min_ms : Double
  max_ms : Double
  stddev_ms : Double
  /// Coefficient of variation: stddev / mean × 100.
  /// CV > 15 % signals noisy measurements; interpret with caution.
  cv_pct : Double
  /// True when CV > 15 %.
  noisy : Bool
}

///|
/// Parameters that control how a benchmark is measured.
pub struct BenchConfig {
  warmup : Int
  iterations : Int
  group_size : Int
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

///|
fn compute_stats(
  times : Array[Double],
) -> (Double, Double, Double, Double, Double) {
  let n = times.length()
  let mut total = 0.0
  let mut lo = times[0]
  let mut hi = times[0]
  for t in times {
    total = total + t
    if t < lo {
      lo = t
    }
    if t > hi {
      hi = t
    }
  }
  let mean = total / n.to_double()
  let mut var_sum = 0.0
  for t in times {
    let d = t - mean
    var_sum = var_sum + d * d
  }
  let variance = if n > 1 { var_sum / (n - 1).to_double() } else { 0.0 }
  let stddev = variance.sqrt()
  let cv = if mean > 0.0 { stddev / mean * 100.0 } else { 0.0 }
  (mean, lo, hi, stddev, cv)
}

// ---------------------------------------------------------------------------
// Core runner
// ---------------------------------------------------------------------------

///|
/// Run a benchmark scenario and return timing statistics.
///
/// Measurement strategy:
///   1. Run `config.warmup` groups to prime JIT and CPU caches. Discard.
///   2. For each of `config.iterations` outer iterations:
///        a. Record t0 = now_ms()
///        b. Call f() exactly config.group_size times
///        c. Record t1 = now_ms()
///        d. Store per-call time: (t1 - t0) / group_size
///   3. Compute mean, min, max, stddev, CV over stored per-call times.
///
/// Errors from f() propagate immediately and abort the benchmark.
/// Benchmark correctness (expected output) must be verified by the caller
/// before invoking run_bench, outside the timed region.
pub fn run_bench(
  name : String,
  category : Category,
  config : BenchConfig,
  f : () -> Unit raise,
) -> BenchResult raise {
  // Warmup — discarded
  for _ in 0..<config.warmup {
    for _ in 0..<config.group_size {
      f()
    }
  }
  // Measurement
  let times : Array[Double] = Array::make(config.iterations, 0.0)
  for i in 0..<config.iterations {
    let t0 = now_ms()
    for _ in 0..<config.group_size {
      f()
    }
    let t1 = now_ms()
    times[i] = (t1 - t0) / config.group_size.to_double()
  }
  let (mean, lo, hi, stddev, cv) = compute_stats(times)
  {
    name,
    category,
    warmup: config.warmup,
    iterations: config.iterations,
    group_size: config.group_size,
    mean_ms: mean,
    min_ms: lo,
    max_ms: hi,
    stddev_ms: stddev,
    cv_pct: cv,
    noisy: cv > 15.0,
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

///|
/// Right-align an integer to width 5.
fn pad5(n : Int) -> String {
  if n >= 10000 {
    "\{n}"
  } else if n >= 1000 {
    " \{n}"
  } else if n >= 100 {
    "  \{n}"
  } else if n >= 10 {
    "   \{n}"
  } else {
    "    \{n}"
  }
}

///|
/// Format a millisecond value as a fixed-width 9-character string.
/// Units scale with magnitude: ms for ≥ 0.01 ms, µs below that.
fn fmt_ms(ms : Double) -> String {
  if ms >= 1000.0 {
    // e.g. " 1.23s  "
    let s = ms / 1000.0
    let i = s.to_int()
    let f = ((s - i.to_double()) * 100.0).to_int()
    let fs = if f < 10 { "0\{f}" } else { "\{f}" }
    "\{i}.\{fs}s    "
  } else if ms >= 100.0 {
    // e.g. "125.34ms"
    let i = ms.to_int()
    let f = ((ms - i.to_double()) * 100.0).to_int()
    let fs = if f < 10 { "0\{f}" } else { "\{f}" }
    "\{i}.\{fs}ms "
  } else if ms >= 10.0 {
    // e.g. " 12.34ms"
    let i = ms.to_int()
    let f = ((ms - i.to_double()) * 100.0).to_int()
    let fs = if f < 10 { "0\{f}" } else { "\{f}" }
    " \{i}.\{fs}ms"
  } else if ms >= 1.0 {
    // e.g. "  1.23ms"
    let i = ms.to_int()
    let f = ((ms - i.to_double()) * 100.0).to_int()
    let fs = if f < 10 { "0\{f}" } else { "\{f}" }
    "  \{i}.\{fs}ms"
  } else if ms >= 0.01 {
    // e.g. " 234.5µs"
    let scaled = ms * 1000.0
    let i = scaled.to_int()
    let f = ((scaled - i.to_double()) * 10.0).to_int()
    " \{i}.\{f}µs "
  } else {
    // e.g. "   1.2µs"
    let scaled = ms * 1000.0
    let i = scaled.to_int()
    let f = ((scaled - i.to_double()) * 10.0).to_int()
    "   \{i}.\{f}µs"
  }
}

///|
/// Format coefficient of variation as "XX.X%".
fn fmt_cv(cv : Double) -> String {
  let i = cv.to_int()
  let f = ((cv - i.to_double()) * 10.0).to_int()
  "\{i}.\{f}%"
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

///|
/// Print one result in aligned human-readable form.
///
/// Example:
///   [regression] lexer/small
///     100 itr × 100 reps  mean:   0.04ms  min:   0.03ms  max:   0.07ms  CV: 5.2%
pub fn print_result(r : BenchResult) -> Unit {
  let noise = if r.noisy { "  ⚠ NOISY" } else { "" }
  println("  [\{r.category.label()}] \{r.name}\{noise}")
  println(
    "    \{pad5(r.iterations)} itr ×\{pad5(r.group_size)} reps  mean: \{fmt_ms(r.mean_ms)}  min: \{fmt_ms(r.min_ms)}  max: \{fmt_ms(r.max_ms)}  CV: \{fmt_cv(r.cv_pct)}",
  )
}

///|
/// Print the CSV header line (call once before any print_result_csv calls).
pub fn print_csv_header() -> Unit {
  println(
    "name,category,warmup,iterations,group_size,mean_ms,min_ms,max_ms,stddev_ms,cv_pct,noisy",
  )
}

///|
/// Print one result as a CSV row for baseline tracking.
///
/// Columns: name, category, warmup, iterations, group_size,
///          mean_ms, min_ms, max_ms, stddev_ms, cv_pct, noisy
pub fn print_result_csv(r : BenchResult) -> Unit {
  let noisy = if r.noisy { "true" } else { "false" }
  println(
    "\{r.name},\{r.category.label()},\{r.warmup},\{r.iterations},\{r.group_size},\{r.mean_ms},\{r.min_ms},\{r.max_ms},\{r.stddev_ms},\{r.cv_pct},\{noisy}",
  )
}

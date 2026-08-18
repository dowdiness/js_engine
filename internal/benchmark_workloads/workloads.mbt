///|
// Canonical execution workload sources shared by benchmark and route tests.
// Keeping these values in a neutral package prevents compiler-test imports
// from depending on the executable benchmarks package.

///|
pub const FIBONACCI_SRC : String =
  #|function fib(n) {
  #|  if (n <= 1) return n;
  #|  return fib(n - 1) + fib(n - 2);
  #|}
  #|fib(30);

///|
pub const FIBONACCI_SMALL_SRC : String =
  #|function fib(n) {
  #|  if (n <= 1) return n;
  #|  return fib(n - 1) + fib(n - 2);
  #|}
  #|fib(10);

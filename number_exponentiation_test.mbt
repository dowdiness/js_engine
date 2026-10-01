///|
test "Math.pow and exponentiation preserve JavaScript number semantics" {
  let engine = @js_engine.Engine()
  let source =
    #|function exponentiate(base, exponent) { return base ** exponent; }
    #|var cases = [
    #|  [1, NaN, NaN], [-1, NaN, NaN],
    #|  [1, Infinity, NaN], [-1, Infinity, NaN],
    #|  [1, -Infinity, NaN], [-1, -Infinity, NaN],
    #|  [NaN, 0, 1], [NaN, -0, 1], [NaN, 2, NaN],
    #|  [-0, 3, -0], [-0, -3, -Infinity],
    #|  [2, 3, 8], [-2, 3, -8], [-2, 0.5, NaN],
    #|  [2, Infinity, Infinity], [0.5, Infinity, 0]
    #|];
    #|for (var i = 0; i < cases.length; i++) {
    #|  var c = cases[i];
    #|  if (!Object.is(Math.pow(c[0], c[1]), c[2]))
    #|    throw new Error('Math.pow case ' + i);
    #|  if (!Object.is(exponentiate(c[0], c[1]), c[2]))
    #|    throw new Error('exponentiation case ' + i);
    #|}
  engine.eval(source)
}

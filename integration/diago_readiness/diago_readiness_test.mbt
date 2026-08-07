///|
const LATEX_POLYFILLS_PRELUDE = "var XML_ENTITIES, HTML_ENTITIES, __set__, __DOMHandler, entities;"

///|
const LATEX_POLYFILLS_EPILOGUE = "entities = { XML_ENTITIES: XML_ENTITIES, HTML_ENTITIES: HTML_ENTITIES };"

///|
const LATEX_BUNDLE_PRELUDE = "var MathJax = { version: '3.2.2', _: {}, config: {} }; globalThis.MathJax = MathJax;"

///|
const LATEX_READINESS_HARNESS =
  #|function __diagoReadinessRender(source) {
  #|  const svg = adaptor.innerHTML(html.convert(source, { em: 16, ex: 8 }));
  #|  function pixels(name) {
  #|    const marker = name + '="';
  #|    const start = svg.indexOf(marker);
  #|    if (start < 0) return null;
  #|    const valueStart = start + marker.length;
  #|    const valueEnd = svg.indexOf('ex"', valueStart);
  #|    if (valueEnd < 0) return null;
  #|    return Math.ceil(Number(svg.slice(valueStart, valueEnd)) * 8);
  #|  }
  #|  return {
  #|    has_math: svg.includes('data-mml-node="math"'),
  #|    width: pixels("width"),
  #|    height: pixels("height"),
  #|  };
  #|}
  #|function __diagoReadinessComplex(source) {
  #|  const result = __diagoReadinessRender(source);
  #|  return {
  #|    has_math: result.has_math,
  #|    positive_finite_dimensions:
  #|      Number.isFinite(result.width) && result.width > 0 &&
  #|      Number.isFinite(result.height) && result.height > 0,
  #|  };
  #|}

///|
fn run_diago_source(
  engine : @js_engine.Engine,
  source : String,
) -> Unit raise @js_engine.EngineError {
  engine.eval(source)
  ignore(engine.run_microtask_checkpoint())
  engine.run_timer_checkpoint()
}

///|
fn load_mathjax() -> @js_engine.Engine raise @js_engine.EngineError {
  let engine = @js_engine.Engine()
  run_diago_source(engine, LATEX_POLYFILLS_PRELUDE)
  run_diago_source(engine, latex_polyfills_source)
  run_diago_source(engine, LATEX_POLYFILLS_EPILOGUE)
  run_diago_source(engine, LATEX_BUNDLE_PRELUDE)
  run_diago_source(engine, latex_mathjax_source)
  run_diago_source(engine, latex_setup_source)
  run_diago_source(engine, LATEX_READINESS_HARNESS)
  engine
}

///|
fn render_mathjax(
  engine : @js_engine.Engine,
  source : String,
) -> Json raise @js_engine.EngineError {
  let result = engine.call_json("__diagoReadinessRender", [Json::string(source)])
  ignore(engine.run_microtask_checkpoint())
  engine.run_timer_checkpoint()
  result
}

///|
fn render_complex_mathjax(
  engine : @js_engine.Engine,
  source : String,
) -> Json raise @js_engine.EngineError {
  let result = engine.call_json("__diagoReadinessComplex", [
    Json::string(source),
  ])
  ignore(engine.run_microtask_checkpoint())
  engine.run_timer_checkpoint()
  result
}

///|
test "diago readiness: MathJax renders and measures x^2" {
  let engine = load_mathjax()
  json_inspect(render_mathjax(engine, "x^2"), content={
    "has_math": true,
    "width": 19,
    "height": 17,
  })
}

///|
fn expect_complex_mathjax(source : String) -> Unit raise Error {
  let engine = load_mathjax()
  json_inspect(render_complex_mathjax(engine, source), content={
    "has_math": true,
    "positive_finite_dimensions": true,
  })
}

///|
test "diago readiness: MathJax renders former CD formula" {
  expect_complex_mathjax(
    (
      #|\begin{CD} B @>{\text{very long label}}>> C S^{{\mathcal{W}}_\Lambda}\otimes T @>j>> T\\ @VVV V \end{CD}
    ),
  )
}

///|
test "diago readiness: MathJax renders a minimal amscd arrow" {
  expect_complex_mathjax(
    (
      #|\begin{CD} @>>> \end{CD}
    ),
  )
}

///|
test "diago readiness: MathJax renders former bra-ket formula" {
  expect_complex_mathjax(
    (
      #|\bra{a}\ket{b}
    ),
  )
}

///|
test "diago readiness: MathJax renders former cancel formula" {
  expect_complex_mathjax(
    (
      #|\cancel{Culture + 5}
    ),
  )
}

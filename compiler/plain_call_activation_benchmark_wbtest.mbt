// Run with:
//   moon bench -p dowdiness/js_engine/compiler \
//     -f plain_call_activation_benchmark_wbtest.mbt --target js --release
//
// The rows are cumulative: preparation; preparation plus BytecodeFrame
// construction; preparation, frame construction, and one direct executor step;
// then one managed child activation through the coordinator. Parsing, lowering,
// verification, and callable creation stay outside timing.

///|
priv struct PlainCallActivationBenchmarkFixture {
  interp : @runtime.Interpreter
  callee : @runtime.Value
  executable : @runtime.ExecutorCallableData
  arguments : Array[@runtime.Value]
  loc : @token.Loc
}

///|
priv enum PlainCallCoordinatorBenchmarkState {
  Ready
  Waiting
  Done(@runtime.Value)
}

///|
priv struct PlainCallCoordinatorBenchmarkFrame {
  callee : @runtime.Value
  arguments : Array[@runtime.Value]
  loc : @token.Loc
  mut state : PlainCallCoordinatorBenchmarkState
}

///|
fn PlainCallCoordinatorBenchmarkFrame::PlainCallCoordinatorBenchmarkFrame(
  callee~ : @runtime.Value,
  arguments~ : Array[@runtime.Value],
  loc~ : @token.Loc,
) -> PlainCallCoordinatorBenchmarkFrame {
  { callee, arguments, loc, state: Ready }
}

///|
impl @runtime.ExecutorActivationFrame for PlainCallCoordinatorBenchmarkFrame with fn step(
  self,
  _interp,
) {
  match self.state {
    Ready => {
      self.state = Waiting
      @runtime.executor_activation_call(
        self.callee,
        @runtime.Undefined,
        self.arguments,
        self.loc,
      )
    }
    Waiting =>
      raise @errors.InternalError(
        message="plain-call benchmark root resumed before child completion",
      )
    Done(value) => @runtime.executor_activation_normal(value)
  }
}

///|
impl @runtime.ExecutorActivationFrame for PlainCallCoordinatorBenchmarkFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.state is Waiting else {
    raise @errors.InternalError(
      message="plain-call benchmark root received an unexpected completion",
    )
  }
  match completion {
    @runtime.ExecutorActivationCompletionNormal(value) =>
      self.state = Done(value)
    @runtime.ExecutorActivationCompletionAbrupt(error) => raise error
    @runtime.ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="plain-call benchmark received a binding reference",
      )
  }
}

///|
fn PlainCallActivationBenchmarkFixture::PlainCallActivationBenchmarkFixture() -> PlainCallActivationBenchmarkFixture {
  let program = compile_script_to_bytecode(
    @parser.parse("function identity(value) { return value; }").stmts,
  ) catch {
    _ => abort("plain-call activation benchmark failed to compile its fixture")
  }
  let function = program.verified_main.child(0)
  guard !function.function.needs_own_env else {
    abort("plain-call activation benchmark requires closure reuse")
  }
  let interp = @interpreter.new_interpreter()
  let callee = make_bytecode_func(function, interp.global, {
    strict: false,
    current_generator: None,
  }) catch {
    _ => abort("plain-call activation benchmark failed to create its callable")
  }
  let executable = match callee {
    @runtime.Object(
      { callable: Some(@runtime.ExecutorCallable(executable)), .. }
    ) => executable
    _ => abort("plain-call activation benchmark requires an executor callable")
  }
  {
    interp,
    callee,
    executable,
    arguments: [@runtime.Number(7.0)],
    loc: @token.Loc::default(),
  }
}

///|
fn PlainCallActivationBenchmarkFixture::prepare_activation(
  self : PlainCallActivationBenchmarkFixture,
) -> @runtime.PreparedExecutorActivation {
  self.interp.prepare_executor_callable_call(
    self.executable,
    self.callee,
    @runtime.Undefined,
    self.arguments,
  ) catch {
    _ => abort("plain-call activation preparation raised")
  }
}

///|
fn PlainCallActivationBenchmarkFixture::start_frame(
  self : PlainCallActivationBenchmarkFixture,
) -> &@runtime.ExecutorActivationFrame {
  self.executable.start_frame(self.interp, self.prepare_activation()) catch {
    _ => abort("plain-call frame construction raised")
  }
}

///|
fn PlainCallActivationBenchmarkFixture::execute_frame_once(
  self : PlainCallActivationBenchmarkFixture,
) -> @runtime.Value {
  let frame = self.start_frame()
  let step = frame.step(self.interp) catch {
    _ => abort("plain-call direct frame execution raised")
  }
  match step {
    @runtime.ExecutorActivationNormal(value)
    | @runtime.ExecutorActivationReturn(value) => value
    _ => abort("plain-call direct frame execution suspended")
  }
}

///|
fn PlainCallActivationBenchmarkFixture::managed_round_trip(
  self : PlainCallActivationBenchmarkFixture,
) -> @runtime.Value {
  let root = PlainCallCoordinatorBenchmarkFrame(
    callee=self.callee,
    arguments=self.arguments,
    loc=self.loc,
  )
  let step = self.interp.run_executor_activation_coordinator(root) catch {
    _ => abort("plain-call managed activation round trip raised")
  }
  match step {
    @runtime.ExecutorActivationNormal(value) => value
    _ => abort("plain-call managed activation returned a pending step")
  }
}

///|
test "isolate/bytecode/plain_call_activation_prepare" (b : @bench.T) {
  let fixture = PlainCallActivationBenchmarkFixture()
  b.bench(() => b.keep(fixture.prepare_activation()))
}

///|
test "isolate/bytecode/plain_call_activation_prepare_and_frame" (b : @bench.T) {
  let fixture = PlainCallActivationBenchmarkFixture()
  b.bench(() => b.keep(fixture.start_frame()))
}

///|
test "isolate/bytecode/plain_call_activation_prepare_frame_and_execute" (
  b : @bench.T,
) {
  let fixture = PlainCallActivationBenchmarkFixture()
  guard fixture.execute_frame_once().to_string() == "7" else {
    abort("plain-call direct frame execution produced the wrong result")
  }
  b.bench(() => b.keep(fixture.execute_frame_once()))
}

///|
test "isolate/bytecode/plain_call_managed_round_trip" (b : @bench.T) {
  let fixture = PlainCallActivationBenchmarkFixture()
  guard fixture.managed_round_trip().to_string() == "7" else {
    abort("plain-call activation benchmark produced the wrong result")
  }
  b.bench(() => b.keep(fixture.managed_round_trip()))
}

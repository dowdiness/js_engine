///|
using @runtime {type EnvironmentSlot}

///|
priv struct BytecodeForInState {
  keys : Array[String]
  mut index : Int
}

///|
priv enum BytecodeActivationResultDestination {
  PushValue
  PushReceiverAndValue(Value)
  NoStackChange
  AppendArraySpread
  AppendArgumentSpread
}

///|
priv struct BytecodeFrame {
  func_def : BytecodeFunction
  verified_func_def : VerifiedBytecodeFunction?
  candidate_child_materializer : CandidateChildMaterializer?
  preparation : BytecodePreparation
  stack : Array[Value]
  arg_lists : Array[Array[Value]]
  for_in_iters : Array[BytecodeForInState]
  locals : Array[Value]
  env_slots : Array[EnvironmentSlot]
  env : Environment
  ctx : ExecContext
  mut ip : Int
  mut completion : Value
  mut optional_chain_short_circuited : Bool
  mut pending_activation_result : BytecodeActivationResultDestination?
  candidate_route_activation : CandidateRouteActivation?
  mut candidate_route_completed : Bool
}

///|
priv enum BytecodeFrameStep {
  BytecodeFrameNormal(Value)
  BytecodeFrameReturn(Value)
  BytecodeFrameSuspended(@runtime.ExecutorActivationStep)
}

///|
fn BytecodeFrame::BytecodeFrame(
  verified_func_def : VerifiedBytecodeFunction,
  env : Environment,
  ctx : ExecContext,
  direct_args? : ArrayView[Value]? = None,
) -> BytecodeFrame raise Error {
  let func_def = verified_func_def.function
  let locals = Array::make(func_def.local_names.length(), Value::Undefined)
  match direct_args {
    Some(args) =>
      // Fast path: iterate params forward so last occurrence wins (duplicate params).
      for j, param in func_def.params {
        match func_def.local_indices.get(param) {
          Some(slot) => locals[slot] = args.get(j).unwrap_or(Value::Undefined)
          None => ()
        }
      }
    None =>
      for i, name in func_def.local_names {
        if string_array_contains(func_def.params, name) && env.has(name) {
          locals[i] = env.get(name)
        }
      }
  }
  let env_slots : Array[EnvironmentSlot] = []
  {
    func_def,
    verified_func_def: Some(verified_func_def),
    candidate_child_materializer: None,
    preparation: verified_func_def.preparation,
    stack: [],
    arg_lists: [],
    for_in_iters: [],
    locals,
    env_slots,
    env,
    ctx,
    ip: 0,
    completion: Value::Undefined,
    optional_chain_short_circuited: false,
    pending_activation_result: None,
    candidate_route_activation: None,
    candidate_route_completed: false,
  }
}

///|
fn BytecodeFrame::candidate(
  execution : CandidateBytecodeExecution,
  env : Environment,
  ctx : ExecContext,
  route_activation : CandidateRouteActivation,
  direct_args? : ArrayView[Value]? = None,
) -> BytecodeFrame raise Error {
  let func_def = execution.bytecode.function
  let locals = Array::make(func_def.local_names.length(), Value::Undefined)
  match direct_args {
    Some(args) =>
      for j, param in func_def.params {
        match func_def.local_indices.get(param) {
          Some(slot) => locals[slot] = args.get(j).unwrap_or(Value::Undefined)
          None => ()
        }
      }
    None =>
      for i, name in func_def.local_names {
        if string_array_contains(func_def.params, name) && env.has(name) {
          locals[i] = env.get(name)
        }
      }
  }
  {
    func_def,
    verified_func_def: None,
    candidate_child_materializer: Some(execution.child_materializer),
    preparation: func_def.preparation,
    stack: [],
    arg_lists: [],
    for_in_iters: [],
    locals,
    env_slots: [],
    env,
    ctx,
    ip: 0,
    completion: Value::Undefined,
    optional_chain_short_circuited: false,
    pending_activation_result: None,
    candidate_route_activation: Some(route_activation),
    candidate_route_completed: false,
  }
}

///|
fn start_candidate_bytecode_frame(
  interp : Interpreter,
  frame : BytecodeFrame,
) -> BytecodeFrame raise Error {
  try {
    match frame.func_def.activation_kind {
      ScriptRootActivation => {
        if frame.func_def.env_slot_names.length() > 0 {
          frame.bind_env_slots()
        }
        frame.hoist_function_decls(interp)
      }
      FunctionActivation => {
        if frame.func_def.needs_own_env {
          frame.hoist_env_var_bindings(interp)
          frame.hoist_lexical_bindings()
          if frame.func_def.env_slot_names.length() > 0 {
            frame.bind_env_slots()
          }
        }
        // Candidate children retain their own typed selection even when the
        // bytecode activation does not need an additional lexical environment.
        // Function declarations still need to be materialized into the frame's
        // local slots or enclosing environment before the first instruction.
        frame.hoist_function_decls(interp)
      }
    }
    frame
  } catch {
    error => {
      frame.complete_candidate_route(false)
      raise error
    }
  }
}

///|
priv struct BytecodeExecutorCode {
  func_def : VerifiedBytecodeFunction
}

///|
fn BytecodeExecutorCode::BytecodeExecutorCode(
  func_def~ : VerifiedBytecodeFunction,
) -> BytecodeExecutorCode {
  { func_def, }
}

///|
fn start_bytecode_frame(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  func_def : VerifiedBytecodeFunction,
  direct_args : ArrayView[Value]?,
) -> BytecodeFrame raise Error {
  let frame = BytecodeFrame(func_def, env, ctx, direct_args~)
  // needs_own_env=false implies all four hoist calls are provably no-ops.
  match frame.func_def.activation_kind {
    ScriptRootActivation => {
      // Runtime preparation owns root var/lexical setup. The VM still
      // materializes verified function declarations and binds captured slots.
      if frame.func_def.env_slot_names.length() > 0 {
        frame.bind_env_slots()
      }
      frame.hoist_function_decls(interp)
    }
    FunctionActivation =>
      if frame.func_def.needs_own_env {
        frame.hoist_env_var_bindings(interp)
        frame.hoist_lexical_bindings()
        if frame.func_def.env_slot_names.length() > 0 {
          frame.bind_env_slots()
        }
        frame.hoist_function_decls(interp)
      }
  }
  frame
}

///|
impl @runtime.ExecutorCode for BytecodeExecutorCode with fn start(
  self,
  interp,
  prepared,
) {
  let frame = start_bytecode_frame(
    interp,
    prepared.context(),
    prepared.environment(),
    self.func_def,
    Some(prepared.arguments()),
  )
  frame as &@runtime.ExecutorActivationFrame
}

///|
impl @runtime.ExecutorActivationFrame for BytecodeFrame with fn step(
  self,
  interp,
) {
  // Cross the neutral seam only at completion or an explicit suspension point.
  // #631 will add the first suspension result; continuing one opcode at a time
  // would make executor-neutral dispatch part of the bytecode inner loop.
  let step = self.step_bytecode(interp) catch {
    error => {
      self.complete_candidate_route(false)
      raise error
    }
  }
  match step {
    BytecodeFrameNormal(value) => {
      self.complete_candidate_route(true)
      @runtime.executor_activation_normal(value)
    }
    BytecodeFrameReturn(value) => {
      self.complete_candidate_route(true)
      @runtime.executor_activation_return(value)
    }
    BytecodeFrameSuspended(step) => step
  }
}

///|
impl @runtime.ExecutorActivationFrame for BytecodeFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  let destination = match self.pending_activation_result {
    Some(destination) => destination
    None =>
      raise @errors.InternalError(
        message="bytecode activation result has no pending consumer",
      )
  }
  self.pending_activation_result = None
  match completion {
    @runtime.ExecutorActivationCompletionNormal(value) =>
      match destination {
        PushValue => self.stack.push(value)
        PushReceiverAndValue(receiver) => {
          self.stack.push(receiver)
          self.stack.push(value)
        }
        NoStackChange => ()
        AppendArraySpread => {
          let spread_values = @runtime.executor_iterable_spread_batch_values(
            value,
          )
          @runtime.apply_array_literal_spread(self.peek(), spread_values)
        }
        AppendArgumentSpread => {
          let spread_values = @runtime.executor_iterable_spread_batch_values(
            value,
          )
          let args = self.current_arg_list()
          for spread_value in spread_values {
            args.push(spread_value)
          }
        }
      }
    @runtime.ExecutorActivationCompletionAbrupt(error) => {
      self.complete_candidate_route(false)
      raise error
    }
  }
}

///|
fn BytecodeFrame::complete_candidate_route(
  self : BytecodeFrame,
  normal : Bool,
) -> Unit raise Error {
  match self.candidate_route_activation {
    Some(activation) if !self.candidate_route_completed => {
      self.candidate_route_completed = true
      candidate_route_complete(
        activation,
        if normal {
          CandidateRouteNormal
        } else {
          CandidateRouteAbrupt
        },
      )
    }
    _ => ()
  }
}

///|
fn BytecodeFrame::bind_env_slots(self : BytecodeFrame) -> Unit raise Error {
  for name in self.func_def.env_slot_names {
    match self.env.resolve_slot(name) {
      Some(slot) => self.env_slots.push(slot)
      None =>
        raise @errors.InternalError(
          message="bytecode env slot binding missing for '\{name}'",
        )
    }
  }
}

///|
fn BytecodeFrame::read_env_slot(
  self : BytecodeFrame,
  slot : Int,
) -> Value raise Error {
  self.env_slots[slot].read()
}

///|
fn BytecodeFrame::initialize_env_slot(
  self : BytecodeFrame,
  slot : Int,
  value : Value,
) -> Unit {
  self.env_slots[slot].initialize(value)
}

///|
fn BytecodeFrame::assign_env_slot(
  self : BytecodeFrame,
  slot : Int,
  value : Value,
  strict : Bool,
) -> Unit raise Error {
  self.env_slots[slot].assign(value, strict~)
}

///|
fn BytecodeFrame::pop(self : BytecodeFrame) -> Value raise Error {
  match self.stack.pop() {
    Some(value) => value
    None => raise @errors.InternalError(message="bytecode stack underflow")
  }
}

///|
fn BytecodeFrame::peek(self : BytecodeFrame) -> Value raise Error {
  guard self.stack.length() > 0 else {
    raise @errors.InternalError(message="bytecode stack underflow")
  }
  self.stack[self.stack.length() - 1]
}

///|
fn pop_args(frame : BytecodeFrame, arg_count : Int) -> Array[Value] raise Error {
  let args = Array::make(arg_count, Value::Undefined)
  for i = arg_count - 1; i >= 0; i = i - 1 {
    args[i] = frame.pop()
  }
  args
}

///|
fn BytecodeFrame::current_arg_list(
  self : BytecodeFrame,
) -> Array[Value] raise Error {
  guard self.arg_lists.length() > 0 else {
    raise @errors.InternalError(message="bytecode argument list underflow")
  }
  self.arg_lists[self.arg_lists.length() - 1]
}

///|
fn BytecodeFrame::pop_dynamic_args(
  self : BytecodeFrame,
) -> Array[Value] raise Error {
  match self.arg_lists.pop() {
    Some(args) => args
    None =>
      raise @errors.InternalError(message="bytecode argument list underflow")
  }
}

///|
fn BytecodeFrame::hoist_env_var_bindings(
  self : BytecodeFrame,
  interp : Interpreter,
) -> Unit raise Error {
  // The env-hoist set (var-declared names that did not become local slots) is
  // precomputed at lowering on the IR (issue #325); iterate it instead of
  // re-walking source metadata and re-filtering on every call.
  for name in self.func_def.env_var_hoist_names {
    interp.define_compiled_binding(
      self.env,
      VarKind,
      name,
      Value::Undefined,
      false,
    )
  }
}

///|
fn BytecodeFrame::hoist_lexical_bindings(
  self : BytecodeFrame,
) -> Unit raise Error {
  for binding in self.preparation.lexical_bindings {
    // Runtime owns the mutable binding and TDZ operations.  The source
    // location remains attached to the immutable fact for diagnostics and
    // future source-aware runtime errors, but is not an executable AST edge.
    ignore(binding.loc)
    match binding.kind {
      BytecodeLet => self.env.def_let_tdz_if_absent(binding.name)
      BytecodeConst => self.env.def_const_tdz_if_absent(binding.name)
    }
  }
}

///|
fn BytecodeFrame::define_function_decl(
  self : BytecodeFrame,
  interp : Interpreter,
  name : String,
  child_index : Int,
) -> Unit raise Error {
  let func = match self.candidate_child_materializer {
    Some(_) => self.candidate_child_value(interp, child_index, self.env)
    None => {
      let child = self.verified_func_def.unwrap().child(child_index)
      make_bytecode_func(child, self.env, self.ctx)
    }
  }
  match local_index_from_names(self.func_def.local_names, name) {
    Some(slot) => self.locals[slot] = func
    None => interp.define_compiled_binding(self.env, VarKind, name, func, true)
  }
}

///|
fn BytecodeFrame::candidate_child_value(
  self : BytecodeFrame,
  interp : Interpreter,
  child_index : Int,
  closure : Environment,
) -> Value raise Error {
  let child_materializer = match self.candidate_child_materializer {
    Some(child_materializer) => child_materializer
    None =>
      raise @errors.InternalError(
        message="candidate child requested without a materializer",
      )
  }
  (child_materializer.materialize)(interp, child_index, closure)
}

///|
fn BytecodeFrame::hoist_function_decls(
  self : BytecodeFrame,
  interp : Interpreter,
) -> Unit raise Error {
  for declaration in self.preparation.function_declarations {
    // The declaration location is retained for source-aware diagnostics; the
    // VM consumes only the immutable name/index fact and the verified child.
    ignore(declaration.loc)
    self.define_function_decl(interp, declaration.name, declaration.child_index)
  }
}

///|
fn ensure_bytecode_signature_validated(
  verified_func_def : VerifiedBytecodeFunction,
) -> Unit raise Error {
  match verified_func_def.preparation.signature_validation {
    Some(_) => ()
    None =>
      raise @errors.InternalError(
        message="verified bytecode function has no canonical signature facts",
      )
  }
}

///|
fn make_bytecode_func(
  verified_func_def : VerifiedBytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
) -> Value raise Error {
  let func_def = verified_func_def.function
  ensure_bytecode_signature_validated(verified_func_def)
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  @runtime.make_prepared_executor_function(
    func_def.name,
    func_def.params,
    closure,
    strict,
    BytecodeExecutorCode(func_def=verified_func_def),
    verified_func_def.preparation.activation_capability,
    source_text=func_def.source_text,
    rest_param=func_def.rest_param,
    define_arguments_object=func_def.needs_arguments_object,
  )
}

///|
fn make_named_bytecode_func(
  func_def : VerifiedBytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
  name : String,
) -> Value raise Error {
  let self_name_env = Environment::new(parent=Some(closure))
  let func = make_bytecode_func(func_def, self_name_env, enclosing_ctx)
  self_name_env.def(name, func, FunctionNameBinding)
  func
}

///|
fn make_bytecode_method_func(
  verified_func_def : VerifiedBytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
  home_object : Value,
) -> Value raise Error {
  let func_def = verified_func_def.function
  ensure_bytecode_signature_validated(verified_func_def)
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  let method_env = Environment::new(parent=Some(closure))
  method_env.def_builtin("[[HomeObject]]", home_object)
  @runtime.make_prepared_executor_function(
    func_def.name,
    func_def.params,
    method_env,
    strict,
    BytecodeExecutorCode(func_def=verified_func_def),
    verified_func_def.preparation.activation_capability,
    source_text=func_def.source_text,
    rest_param=func_def.rest_param,
    constructable=false,
    call_self_name=func_def.call_self_name,
    define_arguments_object=func_def.needs_arguments_object,
  )
}

///|
fn make_bytecode_arrow_func(
  verified_func_def : VerifiedBytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
) -> Value raise Error {
  let func_def = verified_func_def.function
  ensure_bytecode_signature_validated(verified_func_def)
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  @runtime.make_prepared_executor_arrow_function(
    func_def.params,
    closure,
    strict,
    BytecodeExecutorCode(func_def=verified_func_def),
    verified_func_def.preparation.activation_capability,
    source_text=func_def.source_text,
    rest_param=func_def.rest_param,
  )
}

///|
fn run_bytecode_function(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  func_def : VerifiedBytecodeFunction,
  direct_args? : ArrayView[Value]? = None,
) -> BytecodeRunResult raise Error {
  let frame = start_bytecode_frame(interp, ctx, env, func_def, direct_args)
  match
    interp.run_executor_activation_coordinator(
      frame as &@runtime.ExecutorActivationFrame,
    ) {
    @runtime.ExecutorActivationNormal(value) => BytecodeNormal(value)
    @runtime.ExecutorActivationReturn(value) => BytecodeReturn(value)
    @runtime.ExecutorActivationContinue =>
      raise @errors.InternalError(
        message="executor activation coordinator returned continue",
      )
    @runtime.ExecutorActivationCall(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending call",
      )
    @runtime.ExecutorActivationConstruct(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending construct",
      )
    @runtime.ExecutorActivationPropertyGet(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending property get",
      )
    @runtime.ExecutorActivationPropertySet(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending property set",
      )
    @runtime.ExecutorActivationPropertyUpdate(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending property update",
      )
    @runtime.ExecutorActivationCoercingAddition(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending coercing addition",
      )
    @runtime.ExecutorActivationCoercingLessThanOrEqual(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending coercing less-than-or-equal",
      )
    @runtime.ExecutorActivationCoercingSubtraction(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending coercing subtraction",
      )
    @runtime.ExecutorActivationPropertyDelete(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending property delete",
      )
    @runtime.ExecutorActivationIterableSpread(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending iterable spread",
      )
    @runtime.ExecutorActivationCopyDataProperties(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending CopyDataProperties",
      )
    @runtime.ExecutorActivationBinding(_) =>
      raise @errors.InternalError(
        message="executor activation coordinator returned a pending binding resolution",
      )
  }
}

///|
fn BytecodeFrame::step_bytecode(
  frame : BytecodeFrame,
  interp : Interpreter,
) -> BytecodeFrameStep raise Error {
  let code = frame.func_def.code
  let code_len = code.length()
  guard frame.ip < code_len else {
    return BytecodeFrameNormal(frame.completion)
  }
  let stack = frame.stack
  let locals = frame.locals
  let env = frame.env
  let ctx = frame.ctx
  while frame.ip < code_len {
    let instr = code[frame.ip]
    frame.ip += 1
    match instr {
      ObserveStatement(source_id) | ObserveExpression(source_id) => {
        ignore(frame.func_def.resolve_source_point(source_id))
        interp.observe_execution_step()
      }
      LoadConst(value) => stack.push(value)
      LoadUndefined => stack.push(Value::Undefined)
      LoadThis => stack.push(@runtime.eval_this_value(env))
      LoadNewTarget => stack.push(@runtime.eval_new_target_value(env))
      LoadSuperProperty(prop, loc) =>
        stack.push(interp.eval_super_property(env, prop, loc))
      LoadSuperComputed(loc) => {
        let key = frame.pop()
        stack.push(interp.eval_super_computed_property(env, key, loc))
      }
      LoadConsoleMember(prop) => stack.push(interp.get_console_member(prop))
      LoadDirectEvalCallee =>
        match
          @runtime.begin_executor_binding_direct_eval(
            interp,
            ctx,
            env,
            @token.Loc::default(),
          ) {
          @runtime.ExecutorBindingCompleted(value) => stack.push(value)
          @runtime.ExecutorBindingSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_binding_request(request),
            )
          }
        }
      LoadName(name) =>
        match
          @runtime.begin_executor_binding_load(
            interp,
            ctx,
            env,
            name,
            @token.Loc::default(),
          ) {
          @runtime.ExecutorBindingCompleted(value) => stack.push(value)
          @runtime.ExecutorBindingSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_binding_request(request),
            )
          }
        }
      LoadAssignmentName(name) =>
        match
          @runtime.begin_executor_binding_assignment_load(
            interp,
            ctx,
            env,
            name,
            @token.Loc::default(),
          ) {
          @runtime.ExecutorBindingCompleted(value) => stack.push(value)
          @runtime.ExecutorBindingSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_binding_request(request),
            )
          }
        }
      StoreName(name) => {
        let value = frame.pop()
        match
          @runtime.begin_executor_binding_store(
            interp,
            ctx,
            env,
            name,
            value,
            @token.Loc::default(),
          ) {
          @runtime.ExecutorBindingCompleted(result) => stack.push(result)
          @runtime.ExecutorBindingSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_binding_request(request),
            )
          }
        }
      }
      LoadLocal(slot) => stack.push(locals[slot])
      StoreLocal(slot) => {
        let value = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        locals[slot] = value
        stack.push(value)
      }
      LoadEnvSlot(slot) => stack.push(frame.read_env_slot(slot))
      StoreEnvSlot(slot) => {
        let value = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        frame.assign_env_slot(slot, value, frame.ctx.strict)
        stack.push(value)
      }
      DefineBinding(kind, name, has_initializer) => {
        let value = frame.pop()
        interp.define_compiled_binding(env, kind, name, value, has_initializer)
      }
      DefineLocal(slot, has_initializer) => {
        let value = frame.pop()
        if has_initializer {
          locals[slot] = value
        }
      }
      DefineEnvSlot(slot, has_initializer) => {
        let value = frame.pop()
        if has_initializer {
          frame.initialize_env_slot(slot, value)
        }
      }
      SetCompletion =>
        match stack.pop() {
          Some(value) => frame.completion = value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
      SetCompletionValue(value) => frame.completion = value
      Pop =>
        match stack.pop() {
          Some(_) => ()
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
      Dup => stack.push(frame.peek())
      BinaryOp(Add, BinaryExpression, loc) => {
        let right = frame.pop()
        let left = frame.pop()
        match @runtime.begin_executor_coercing_addition(left, right, loc) {
          @runtime.ExecutorCoercingAdditionCompleted(value) => stack.push(value)
          @runtime.ExecutorCoercingAdditionSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_coercing_addition_request(request),
            )
          }
        }
      }
      BinaryOp(Sub, BinaryExpression, loc) => {
        let right = frame.pop()
        let left = frame.pop()
        match @runtime.begin_executor_coercing_subtraction(left, right, loc) {
          @runtime.ExecutorCoercingSubtractionCompleted(value) =>
            stack.push(value)
          @runtime.ExecutorCoercingSubtractionSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_coercing_subtraction_request(request),
            )
          }
        }
      }
      BinaryOp(LtEq, BinaryExpression, loc) => {
        let right = frame.pop()
        let left = frame.pop()
        match @runtime.begin_executor_coercing_less_than_or_equal(left, right, loc) {
          @runtime.ExecutorCoercingLessThanOrEqualCompleted(value) =>
            stack.push(value)
          @runtime.ExecutorCoercingLessThanOrEqualSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_coercing_less_than_or_equal_request(request),
            )
          }
        }
      }
      BinaryOp(op, _, loc) => {
        let right = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        let left = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        stack.push(
          @runtime.eval_binary_op(op, left, right, loc, interp=Some(interp)),
        )
      }
      UnaryValueOp(op, loc) => {
        let value = frame.pop()
        stack.push(@runtime.eval_unary_value_op(op, value, loc))
      }
      TypeofName(name) =>
        match
          @runtime.begin_executor_binding_typeof(
            interp,
            ctx,
            env,
            name,
            @token.Loc::default(),
          ) {
          @runtime.ExecutorBindingCompleted(value) => stack.push(value)
          @runtime.ExecutorBindingSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_binding_request(request),
            )
          }
        }
      DeleteName(name) =>
        stack.push(@runtime.eval_delete_identifier(interp, ctx, env, name))
      DeleteProperty(prop) => {
        let obj = frame.pop()
        match
          @runtime.begin_executor_property_delete_static(
            interp,
            obj,
            prop,
            ctx.strict,
            @token.Loc::default(),
          ) {
          @runtime.ExecutorPropertyDeleteCompleted(value) => stack.push(value)
          @runtime.ExecutorPropertyDeleteSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_property_delete_request(request),
            )
          }
        }
      }
      DeleteComputed => {
        let key = frame.pop()
        let obj = frame.pop()
        match
          @runtime.begin_executor_property_delete_computed(
            interp,
            obj,
            key,
            ctx.strict,
            @token.Loc::default(),
          ) {
          @runtime.ExecutorPropertyDeleteCompleted(value) => stack.push(value)
          @runtime.ExecutorPropertyDeleteSuspended(request) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_property_delete_request(request),
            )
          }
        }
      }
      AppendTemplate(tail) => {
        let value = frame.pop()
        let acc = frame.pop()
        match acc {
          String_(prefix) =>
            stack.push(
              Value::String_(
                prefix +
                @runtime.to_js_string(value, interp=Some(interp)) +
                tail,
              ),
            )
          _ =>
            raise @errors.InternalError(
              message="bytecode template accumulator was not a string",
            )
        }
      }
      MakeTemplateObject(strings) => {
        let site_key = frame.func_def.template_cache_key_prefix +
          ":" +
          (frame.ip - 1).to_string()
        stack.push(interp.get_cached_tagged_template_object(site_key, strings))
      }
      MakeRegExp(pattern, flags) =>
        stack.push(
          (interp.stdlib_hooks.make_regexp_object)(
            interp.realm_state,
            pattern,
            flags,
          ),
        )
      SetFunctionName(name) => {
        let value = frame.pop()
        @runtime.set_function_name(value, name)
        stack.push(value)
      }
      UpdateName(name, op, prefix, loc) =>
        stack.push(interp.update_compiled_name(ctx, env, name, op, prefix, loc))
      UpdateLocal(slot, op, prefix) => {
        let old_number = @runtime.to_number(locals[slot], interp=Some(interp))
        let next_value = match op {
          Increment => Value::Number(old_number + 1.0)
          Decrement => Value::Number(old_number - 1.0)
        }
        locals[slot] = next_value
        stack.push(if prefix { next_value } else { Value::Number(old_number) })
      }
      UpdateEnvSlot(slot, op, prefix) => {
        let old_number = @runtime.to_number(
          frame.read_env_slot(slot),
          interp=Some(interp),
        )
        let next_value = match op {
          Increment => Value::Number(old_number + 1.0)
          Decrement => Value::Number(old_number - 1.0)
        }
        frame.assign_env_slot(slot, next_value, frame.ctx.strict)
        stack.push(if prefix { next_value } else { Value::Number(old_number) })
      }
      UpdateProperty(prop, op, prefix, member_loc, loc) => {
        let obj = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          match op {
            Increment =>
              @runtime.executor_activation_property_increment(
                obj,
                prop,
                prefix,
                member_loc,
                loc,
                ctx.strict,
              )
            Decrement =>
              @runtime.executor_activation_property_decrement(
                obj,
                prop,
                prefix,
                member_loc,
                loc,
                ctx.strict,
              )
          },
        )
      }
      UpdateComputed(op, prefix, member_loc, loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        match key {
          String_(property_name) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              match op {
                Increment =>
                  @runtime.executor_activation_property_increment(
                    obj,
                    property_name,
                    prefix,
                    member_loc,
                    loc,
                    ctx.strict,
                  )
                Decrement =>
                  @runtime.executor_activation_property_decrement(
                    obj,
                    property_name,
                    prefix,
                    member_loc,
                    loc,
                    ctx.strict,
                  )
              },
            )
          }
          _ =>
            stack.push(
              interp.eval_update_computed_property(
                ctx, obj, key, op, prefix, member_loc, loc,
              ),
            )
        }
      }
      Jump(target) => frame.ip = target
      JumpIfFalse(target) => {
        let cond = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        if !@runtime.is_truthy(cond) {
          frame.ip = target
        }
      }
      JumpIfFalseKeep(target) => {
        let cond = frame.peek()
        if !@runtime.is_truthy(cond) {
          frame.ip = target
        }
      }
      JumpIfTrueKeep(target) => {
        let cond = frame.peek()
        if @runtime.is_truthy(cond) {
          frame.ip = target
        }
      }
      JumpIfNotNullishKeep(target) =>
        match frame.peek() {
          Null | Undefined => ()
          _ => frame.ip = target
        }
      BeginOptionalChain => frame.optional_chain_short_circuited = false
      MarkOptionalChainShortCircuit =>
        frame.optional_chain_short_circuited = true
      JumpIfNotOptionalChainShortCircuitKeep(target) =>
        if !frame.optional_chain_short_circuited {
          frame.ip = target
        }
      EndOptionalChain => frame.optional_chain_short_circuited = false
      StartForIn => {
        let obj = frame.pop()
        frame.for_in_iters.push({
          keys: @runtime.collect_for_in_keys(obj, interp),
          index: 0,
        })
      }
      ForInNext(target) => {
        guard frame.for_in_iters.length() > 0 else {
          raise @errors.InternalError(
            message="bytecode for-in iterator underflow",
          )
        }
        let state = frame.for_in_iters[frame.for_in_iters.length() - 1]
        if state.index >= state.keys.length() {
          let _ = frame.for_in_iters.pop()
          frame.ip = target
        } else {
          let key = state.keys[state.index]
          state.index += 1
          stack.push(Value::String_(key))
        }
      }
      EndForIn =>
        match frame.for_in_iters.pop() {
          Some(_) => ()
          None =>
            raise @errors.InternalError(
              message="bytecode for-in iterator underflow",
            )
        }
      MakeArray(count) => {
        let elements = pop_args(frame, count)
        stack.push(@runtime.make_array(elements))
      }
      MakeArrayWithHoles(count, hole_idxs) => {
        let elements = pop_args(frame, count)
        stack.push(@runtime.make_array_with_holes(elements, hole_idxs))
      }
      StartArray => stack.push(@runtime.make_array([]))
      ArrayPushValue => {
        let value = frame.pop()
        @runtime.apply_array_literal_element(frame.peek(), value)
      }
      ArrayPushSpread(loc) => {
        let value = frame.pop()
        match @runtime.begin_executor_iterable_spread(value, loc) {
          @runtime.ExecutorIterableSpreadCompleted(spread_values) =>
            @runtime.apply_array_literal_spread(frame.peek(), spread_values)
          @runtime.ExecutorIterableSpreadSuspended(request) => {
            frame.pending_activation_result = Some(AppendArraySpread)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_iterable_spread_request(request),
            )
          }
        }
      }
      ArrayPushHole => @runtime.apply_array_literal_hole(frame.peek())
      StartArgs => frame.arg_lists.push([])
      ArgPushValue => {
        let value = frame.pop()
        let args = frame.current_arg_list()
        args.push(value)
      }
      ArgPushSpread(loc) => {
        let value = frame.pop()
        match @runtime.begin_executor_iterable_spread(value, loc) {
          @runtime.ExecutorIterableSpreadCompleted(spread_values) => {
            let args = frame.current_arg_list()
            for spread_value in spread_values {
              args.push(spread_value)
            }
          }
          @runtime.ExecutorIterableSpreadSuspended(request) => {
            frame.pending_activation_result = Some(AppendArgumentSpread)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_iterable_spread_request(request),
            )
          }
        }
      }
      MakeObject(keys) => {
        let values = pop_args(frame, keys.length())
        let properties : Map[String, Value] = Map([])
        for i, key in keys {
          properties[key] = values[i]
        }
        let prototype = env.get("[[ObjectPrototype]]") catch {
          _ => Value::Null
        }
        stack.push(
          @runtime.make_object(
            properties,
            prototype,
            None,
            "Object",
            Map([]),
            true,
          ),
        )
      }
      StartObject => {
        let prototype = env.get("[[ObjectPrototype]]") catch {
          _ => Value::Null
        }
        stack.push(
          @runtime.make_object(
            Map([]),
            prototype,
            None,
            "Object",
            Map([]),
            true,
          ),
        )
      }
      ObjectSetStatic(key) => {
        let value = frame.pop()
        @runtime.apply_object_literal_static_data_property(
          frame.peek(),
          key,
          value,
        )
      }
      ObjectSetStaticGetter(key) => {
        let getter = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          Value::String_(key),
          getter,
          true,
        )
      }
      ObjectSetStaticSetter(key) => {
        let setter = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          Value::String_(key),
          setter,
          false,
        )
      }
      ObjectSetComputedGetter => {
        let getter = frame.pop()
        let key = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          key,
          getter,
          true,
        )
      }
      ObjectSetComputedSetter => {
        let setter = frame.pop()
        let key = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          key,
          setter,
          false,
        )
      }
      ToObjectLiteralPropertyKey => {
        let key = frame.pop()
        stack.push(interp.to_object_literal_property_key(key))
      }
      ObjectSetComputed => {
        let value = frame.pop()
        let key = frame.pop()
        @runtime.apply_object_literal_data_property(frame.peek(), key, value)
      }
      ObjectSpread(loc) => {
        let source = frame.pop()
        match
          @runtime.begin_executor_copy_data_properties(
            interp,
            frame.peek(),
            source,
            [],
            loc,
          ) {
          @runtime.ExecutorCopyDataPropertiesCompleted => ()
          @runtime.ExecutorCopyDataPropertiesSuspended(request) => {
            frame.pending_activation_result = Some(NoStackChange)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_copy_data_properties_request(request),
            )
          }
        }
      }
      ObjectSetProto => {
        let value = frame.pop()
        @runtime.apply_object_literal_proto_property(frame.peek(), value)
      }
      MakeFunction(index) =>
        match frame.candidate_child_materializer {
          Some(_) => stack.push(frame.candidate_child_value(interp, index, env))
          None => {
            let child = frame.verified_func_def.unwrap().child(index)
            stack.push(make_bytecode_func(child, env, ctx))
          }
        }
      MakeNamedFunction(index, name) =>
        match frame.candidate_child_materializer {
          Some(_) => stack.push(frame.candidate_child_value(interp, index, env))
          None => {
            let child = frame.verified_func_def.unwrap().child(index)
            stack.push(make_named_bytecode_func(child, env, ctx, name))
          }
        }
      MakeMethodFunction(index) => {
        let home_object = frame.peek()
        match frame.candidate_child_materializer {
          Some(_) => {
            let method_env = Environment::new(parent=Some(env))
            method_env.def_builtin("[[HomeObject]]", home_object)
            stack.push(frame.candidate_child_value(interp, index, method_env))
          }
          None => {
            let child = frame.verified_func_def.unwrap().child(index)
            stack.push(make_bytecode_method_func(child, env, ctx, home_object))
          }
        }
      }
      MakeComputedMethodFunction(index) => {
        guard stack.length() >= 2 else {
          raise @errors.InternalError(
            message="bytecode computed method missing home object",
          )
        }
        let home_object = stack[stack.length() - 2]
        match frame.candidate_child_materializer {
          Some(_) => {
            let method_env = Environment::new(parent=Some(env))
            method_env.def_builtin("[[HomeObject]]", home_object)
            stack.push(frame.candidate_child_value(interp, index, method_env))
          }
          None => {
            let child = frame.verified_func_def.unwrap().child(index)
            stack.push(make_bytecode_method_func(child, env, ctx, home_object))
          }
        }
      }
      MakeArrowFunction(index) =>
        match frame.candidate_child_materializer {
          Some(_) => stack.push(frame.candidate_child_value(interp, index, env))
          None => {
            let child = frame.verified_func_def.unwrap().child(index)
            stack.push(make_bytecode_arrow_func(child, env, ctx))
          }
        }
      DeclareFunction(name, _) => ignore(name)
      GetProperty(prop, loc) => {
        let obj = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_property_get(obj, prop, loc),
        )
      }
      GetComputed(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        match
          @runtime.executor_activation_computed_property_get_if_admitted(
            obj, key, loc,
          ) {
          Some(step) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(step)
          }
          None => stack.push(interp.get_computed_property(obj, key, loc))
        }
      }
      ReadPropertyForAssign(prop, loc) => {
        let receiver = frame.peek()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_property_get(receiver, prop, loc),
        )
      }
      ReadComputedForAssign(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        match
          @runtime.executor_activation_computed_property_get_if_admitted(
            obj, key, loc,
          ) {
          Some(step) => {
            stack.push(obj)
            stack.push(key)
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(step)
          }
          None => {
            if obj is Null {
              raise @errors.TypeError(message="Cannot read properties of null")
            }
            if obj is Undefined {
              raise @errors.TypeError(
                message="Cannot read properties of undefined",
              )
            }
            let prop_key = @runtime.to_property_key(key, interp=Some(interp))
            let current = interp.get_computed_property(obj, prop_key, loc)
            stack.push(obj)
            stack.push(prop_key)
            stack.push(current)
          }
        }
      }
      DropPropertyAssignReference => {
        let current = frame.pop()
        let _ = frame.pop()
        stack.push(current)
      }
      DropComputedAssignReference => {
        let current = frame.pop()
        let _ = frame.pop()
        let _ = frame.pop()
        stack.push(current)
      }
      SetProperty(prop, loc) => {
        let value = frame.pop()
        let obj = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_property_set(
            obj,
            prop,
            value,
            loc,
            ctx.strict,
          ),
        )
      }
      SetComputed(loc) => {
        let value = frame.pop()
        let key = frame.pop()
        let obj = frame.pop()
        match key {
          String_(property_name) => {
            frame.pending_activation_result = Some(PushValue)
            return BytecodeFrameSuspended(
              @runtime.executor_activation_property_set(
                obj,
                property_name,
                value,
                loc,
                ctx.strict,
              ),
            )
          }
          _ =>
            stack.push(
              interp.set_computed_property(
                obj,
                key,
                value,
                loc,
                strict=ctx.strict,
              ),
            )
        }
      }
      SetForInProperty(prop, loc) => {
        let obj = frame.pop()
        let value = frame.pop()
        stack.push(
          interp.set_property(obj, prop, value, loc, strict=ctx.strict),
        )
      }
      SetForInComputed(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        let value = frame.pop()
        stack.push(
          interp.set_computed_property(obj, key, value, loc, strict=ctx.strict),
        )
      }
      AssignDestructure(plan) => {
        let value = frame.pop()
        stack.push(interp.eval_destructure_assign_plan(ctx, plan, value, env))
      }
      PreparePropertyCall(prop, loc) => {
        let receiver = frame.pop()
        frame.pending_activation_result = Some(PushReceiverAndValue(receiver))
        return BytecodeFrameSuspended(
          @runtime.executor_activation_property_get(receiver, prop, loc),
        )
      }
      PreparePlainPropertyCall(prop, loc) => {
        let receiver = frame.pop()
        frame.pending_activation_result = Some(PushReceiverAndValue(receiver))
        return BytecodeFrameSuspended(
          @runtime.executor_activation_property_get(receiver, prop, loc),
        )
      }
      PrepareComputedCall(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        match
          @runtime.executor_activation_computed_property_get_if_admitted(
            obj, key, loc,
          ) {
          Some(step) => {
            frame.pending_activation_result = Some(PushReceiverAndValue(obj))
            return BytecodeFrameSuspended(step)
          }
          None => {
            let callee = interp.get_computed_property(obj, key, loc)
            stack.push(obj)
            stack.push(callee)
          }
        }
      }
      PrepareSuperPropertyCall(prop, loc) => {
        let (receiver, callee) = interp.eval_super_property_call_reference(
          env, prop, loc,
        )
        stack.push(receiver)
        stack.push(callee)
      }
      PrepareSuperComputedCall(loc) => {
        let key = frame.pop()
        let (receiver, callee) = interp.eval_super_computed_call_reference(
          env, key, loc,
        )
        stack.push(receiver)
        stack.push(callee)
      }
      CallDirectEval(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        stack.push(
          interp.call_direct_eval_or_shadowed(
            callee,
            args,
            env,
            loc,
            caller_strict=ctx.strict,
          ),
        )
      }
      Call(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let callee = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_call(callee, Value::Undefined, args, loc),
        )
      }
      CallWithReceiver(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let callee = frame.pop()
        let receiver = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_call(callee, receiver, args, loc),
        )
      }
      CallSpread(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_call(callee, Value::Undefined, args, loc),
        )
      }
      CallSpreadWithReceiver(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        let receiver = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_call(callee, receiver, args, loc),
        )
      }
      Construct(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let ctor = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_construct(ctor, args, loc),
        )
      }
      ConstructSpread(loc) => {
        let args = frame.pop_dynamic_args()
        let ctor = frame.pop()
        frame.pending_activation_result = Some(PushValue)
        return BytecodeFrameSuspended(
          @runtime.executor_activation_construct(ctor, args, loc),
        )
      }
      Return => return BytecodeFrameReturn(frame.pop())
      Throw => {
        let value = frame.pop()
        @runtime.raise_js_exception(value)
      }
    }
  }
  BytecodeFrameNormal(frame.completion)
}

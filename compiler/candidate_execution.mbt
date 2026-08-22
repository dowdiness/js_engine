///|
// Bytecode frames retain only this executor-neutral child capability. The
// candidate tree and checked child slots remain captured by the compiler
// closure, rather than entering the bytecode frame's VM state.
priv struct CandidateChildMaterializer {
  materialize : (Interpreter, Int, Environment) -> Value raise Error
}

///|
// The checked carrier and its child capability cross into a bytecode
// activation as one candidate-specific execution capability. The frame never
// receives the raw carrier independently.
priv struct CandidateBytecodeExecution {
  bytecode : CandidateVerifiedBytecodeFunction
  child_materializer : CandidateChildMaterializer
}

///|
fn CandidateBytecodeExecution::CandidateBytecodeExecution(
  bytecode : CandidateVerifiedBytecodeFunction,
  child_materializer : CandidateChildMaterializer,
) -> CandidateBytecodeExecution {
  { bytecode, child_materializer }
}

///|
fn candidate_request_form(
  consumer_form : BytecodeFunctionConsumerForm,
) -> @runtime.FunctionMaterializationForm {
  match consumer_form {
    DeclareFunctionConsumer(_) => @runtime.FunctionDeclaration
    FunctionConsumer => @runtime.FunctionExpression
    NamedFunctionConsumer(_) => @runtime.NamedFunctionExpression
    MethodFunctionConsumer => @runtime.MethodFunction
    ComputedMethodFunctionConsumer => @runtime.ComputedMethodFunction
    ArrowFunctionConsumer => @runtime.ArrowFunction
  }
}

// Resolve a request by its exact parser coordinate and consumer form. The
// coordinate locates a verified child; the child source identity and
// selection remain the compiler's authority.

///|
fn candidate_child_index_for_request(
  candidate : CandidateFunction,
  request : @runtime.FunctionMaterializationRequest,
) -> Int raise Error {
  let site = request.site
  let mut found : Int? = None
  for child_index, child in candidate.children {
    let child_site = match child.materialization_site {
      Some(child_site) => child_site
      None =>
        raise @errors.InternalError(
          message="candidate child has no syntax site",
        )
    }
    let child_form = match child.consumer_form {
      Some(form) => candidate_request_form(form)
      None =>
        raise @errors.InternalError(
          message="candidate child is missing its consumer form",
        )
    }
    if child_site == site && child_form == request.form {
      match found {
        Some(_) =>
          raise @errors.InternalError(
            message="candidate materialization site is ambiguous",
          )
        None => found = Some(child_index)
      }
    }
  }
  match found {
    Some(child_index) => child_index
    None =>
      raise @errors.InternalError(
        message="candidate materialization site is absent from verified plan",
      )
  }
}

///|
fn candidate_child_materializer(
  candidate : CandidateFunction,
  carrier : CandidateVerifiedBytecodeFunction,
  evidence : Ref[CandidateRouteEvidence],
) -> CandidateChildMaterializer {
  {
    materialize: fn(interp, child_index, closure) raise {
      guard child_index >= 0 && child_index < candidate.children.length() else {
        raise @errors.InternalError(
          message="candidate child index is outside the verified plan",
        )
      }
      let child = candidate.children[child_index]
      match (child.bytecode, carrier.child_slots[child_index]) {
        (Some(_), CandidateBytecodeChild(_)) | (None, CandidateTreeChild(_)) =>
          ()
        _ =>
          raise @errors.InternalError(
            message="candidate child slot disagrees with selected child",
          )
      }
      let request = candidate_function_request(child, closure)
      candidate_make_callable(interp, child, evidence, request)
    },
  }
}

///|
fn candidate_function_request(
  candidate : CandidateFunction,
  closure : @runtime.Environment,
) -> @runtime.FunctionMaterializationRequest {
  let consumer_form = match candidate.consumer_form {
    Some(form) => form
    None => candidate.consumer_form.unwrap()
  }
  let name = match candidate_request_form(consumer_form) {
    @runtime.ArrowFunction => None
    _ => candidate.name
  }
  let parameters = match candidate.signature {
    CandidateSimpleSignature(params) =>
      @runtime.SimpleFunctionParameters(params.copy())
    CandidateExtendedSignature(params, rest_param) =>
      @runtime.ExtendedFunctionParameters(params.copy(), rest_param)
  }
  @runtime.FunctionMaterializationRequest(
    form=candidate_request_form(consumer_form),
    site=candidate.materialization_site.unwrap(),
    name~,
    parameters~,
    body=candidate.body.copy(),
    closure~,
    strict=candidate.strict,
    source_text=candidate.source_text,
  )
}

///|
fn candidate_materializer_template(
  candidate : CandidateFunction,
  evidence : Ref[CandidateRouteEvidence],
) -> @runtime.FunctionMaterializer {
  @runtime.FunctionMaterializer(
    begin=fn() { candidate_materializer_instance(candidate, evidence) },
    materialize=fn(_interp, _request) raise {
      raise @errors.InternalError(
        message="candidate materializer used outside an activation",
      )
    },
  )
}

///|
fn candidate_materializer_instance(
  candidate : CandidateFunction,
  evidence : Ref[CandidateRouteEvidence],
) -> @runtime.FunctionMaterializer {
  let activation = candidate_route_prepare(
    evidence,
    candidate.source_identity,
    candidate.selection,
  )
  let hooks = @runtime.FunctionExecutionHooks(
    start=fn() raise {
      candidate_route_start(activation, CandidateTreeWalkerExecutor)
    },
    complete=fn(normal) raise {
      candidate_route_complete(
        activation,
        if normal {
          CandidateRouteNormal
        } else {
          CandidateRouteAbrupt
        },
      )
    },
  )
  @runtime.FunctionMaterializer(
    begin=fn() { candidate_materializer_instance(candidate, evidence) },
    materialize=fn(interp, request) raise {
      let child_index = candidate_child_index_for_request(candidate, request)
      let child = candidate.children[child_index]
      candidate_make_callable(interp, child, evidence, request)
    },
    hooks=Some(hooks),
  )
}

///|
priv struct CandidateBytecodeExecutorCode {
  execution : CandidateBytecodeExecution
  evidence : Ref[CandidateRouteEvidence]
  source_identity : BytecodeSourceIdentity
  decision : CandidateSelection
}

///|
fn CandidateBytecodeExecutorCode::CandidateBytecodeExecutorCode(
  execution : CandidateBytecodeExecution,
  evidence : Ref[CandidateRouteEvidence],
  source_identity : BytecodeSourceIdentity,
  decision : CandidateSelection,
) -> CandidateBytecodeExecutorCode {
  { execution, evidence, source_identity, decision }
}

///|
fn candidate_make_bytecode_callable(
  _interp : @runtime.Interpreter,
  candidate : CandidateFunction,
  bytecode : CandidateVerifiedBytecodeFunction,
  evidence : Ref[CandidateRouteEvidence],
  request : @runtime.FunctionMaterializationRequest,
) -> @runtime.Value {
  let func_def = bytecode.function
  let child_materializer = candidate_child_materializer(
    candidate, bytecode, evidence,
  )
  let code = CandidateBytecodeExecutorCode(
    CandidateBytecodeExecution(bytecode, child_materializer),
    evidence,
    candidate.source_identity,
    candidate.selection,
  )
  let capability = func_def.preparation.activation_capability
  match request.form {
    @runtime.ArrowFunction =>
      @runtime.make_prepared_executor_arrow_function(
        func_def.params,
        request.closure,
        request.strict,
        code,
        capability,
        source_text=func_def.source_text,
        rest_param=func_def.rest_param,
      )
    @runtime.MethodFunction | @runtime.ComputedMethodFunction =>
      @runtime.make_prepared_executor_function(
        func_def.name,
        func_def.params,
        request.closure,
        request.strict,
        code,
        capability,
        source_text=func_def.source_text,
        rest_param=func_def.rest_param,
        constructable=false,
        call_self_name=func_def.call_self_name,
        define_arguments_object=func_def.needs_arguments_object,
      )
    _ =>
      @runtime.make_prepared_executor_function(
        func_def.name,
        func_def.params,
        request.closure,
        request.strict,
        code,
        capability,
        source_text=func_def.source_text,
        rest_param=func_def.rest_param,
        call_self_name=func_def.call_self_name,
        define_arguments_object=func_def.needs_arguments_object,
      )
  }
}

///|
fn candidate_make_tree_callable(
  candidate : CandidateFunction,
  evidence : Ref[CandidateRouteEvidence],
  request : @runtime.FunctionMaterializationRequest,
) -> @runtime.Value {
  let children = candidate_materializer_template(candidate, evidence)
  @runtime.make_materialized_tree_function(request, Some(children))
}

///|
fn candidate_make_callable(
  interp : @runtime.Interpreter,
  candidate : CandidateFunction,
  evidence : Ref[CandidateRouteEvidence],
  request : @runtime.FunctionMaterializationRequest,
) -> @runtime.Value raise Error {
  match candidate.selection {
    UseTreeWalker(_) =>
      candidate_make_tree_callable(candidate, evidence, request)
    UseBytecode(_) => {
      let bytecode = match candidate.bytecode {
        Some(bytecode) => bytecode
        None =>
          raise @errors.InternalError(
            message="candidate bytecode selection has no checked carrier",
          )
      }
      candidate_make_bytecode_callable(
        interp, candidate, bytecode, evidence, request,
      )
    }
  }
}

///|
impl @runtime.ExecutorCode for CandidateBytecodeExecutorCode with fn start(
  self,
  interp,
  prepared,
) {
  let execution = self.execution
  let activation = candidate_route_prepare(
    self.evidence,
    self.source_identity,
    self.decision,
  )
  candidate_route_start(activation, CandidateBytecodeExecutor)
  let frame = {
    errdefer candidate_route_complete(activation, CandidateRouteAbrupt)
    BytecodeFrame::candidate(
      execution,
      prepared.environment(),
      prepared.context(),
      activation,
      direct_args=Some(prepared.arguments()),
    )
  }
  start_candidate_bytecode_frame(interp, frame)
  as &@runtime.ExecutorActivationFrame
}

///|
fn run_candidate_bytecode_function(
  interp : @runtime.Interpreter,
  ctx : @runtime.ExecContext,
  env : @runtime.Environment,
  candidate : CandidateFunction,
  bytecode : CandidateVerifiedBytecodeFunction,
  activation : CandidateRouteActivation,
) -> @runtime.Value raise Error {
  let _ = candidate
  candidate_route_start(activation, CandidateBytecodeExecutor)
  let execution = CandidateBytecodeExecution(
    bytecode,
    candidate_child_materializer(candidate, bytecode, activation.evidence),
  )
  let frame = {
    errdefer candidate_route_complete(activation, CandidateRouteAbrupt)
    BytecodeFrame::candidate(execution, env, ctx, activation)
  }
  let frame = start_candidate_bytecode_frame(interp, frame)
  let result = {
    errdefer frame.complete_candidate_route(false)
    interp.run_executor_activation_coordinator(
      frame as &@runtime.ExecutorActivationFrame,
    )
  }
  match result {
    @runtime.ExecutorActivationNormal(value)
    | @runtime.ExecutorActivationReturn(value) => value
    @runtime.ExecutorActivationContinue
    | @runtime.ExecutorActivationCall(_)
    | @runtime.ExecutorActivationConstruct(_)
    | @runtime.ExecutorActivationPropertyGet(_)
    | @runtime.ExecutorActivationComputedCallPreparation(_)
    | @runtime.ExecutorActivationPropertySet(_)
    | @runtime.ExecutorActivationPropertyUpdate(_)
    | @runtime.ExecutorActivationCoercingAddition(_)
    | @runtime.ExecutorActivationCoercingRelational(_)
    | @runtime.ExecutorActivationCoercingSubtraction(_)
    | @runtime.ExecutorActivationCoercingMultiplicative(_)
    | @runtime.ExecutorActivationPropertyDelete(_)
    | @runtime.ExecutorActivationIterableSpread(_)
    | @runtime.ExecutorActivationCopyDataProperties(_)
    | @runtime.ExecutorActivationBinding(_)
    | @runtime.ExecutorActivationBindingReference(_)
    | @runtime.ExecutorActivationBindingUpdate(_)
    | @runtime.ExecutorActivationReference(_) =>
      raise @errors.InternalError(
        message="candidate root coordinator returned a pending activation",
      )
  }
}

///|
fn run_candidate_program_with_recorder(
  interp : @runtime.Interpreter,
  stmts : Array[@ast.Stmt],
  evidence : Ref[CandidateRouteEvidence],
) -> @runtime.Value raise Error {
  let program = prepare_candidate_program(stmts)
  match program.root.selection {
    UseTreeWalker(_) => {
      let materializer = candidate_materializer_template(program.root, evidence)
      interp.run_with_function_materializer(stmts, materializer)
    }
    UseBytecode(_) => {
      let bytecode = match program.root.bytecode {
        Some(bytecode) => bytecode
        None =>
          raise @errors.InternalError(
            message="candidate root selected bytecode without carrier",
          )
      }
      let preparation = match program.script_preparation {
        Some(preparation) => preparation
        None =>
          raise @errors.InternalError(
            message="candidate bytecode root has no script preparation",
          )
      }
      let activation = candidate_route_prepare(
        evidence,
        program.root.source_identity,
        program.root.selection,
      )
      interp.run_prepared_compiled_script(preparation, fn(ctx, env) raise {
        run_candidate_bytecode_function(
          interp,
          ctx,
          env,
          program.root,
          bytecode,
          activation,
        )
      })
    }
  }
}

///|
#warnings("-unused_value")
fn run_candidate_program_with_evidence(
  interp : @runtime.Interpreter,
  stmts : Array[@ast.Stmt],
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=true),
  }
  let value = run_candidate_program_with_recorder(interp, stmts, evidence)
  (value, evidence)
}

///|
#warnings("-unused_value")
fn run_candidate_program_with_summary(
  interp : @runtime.Interpreter,
  stmts : Array[@ast.Stmt],
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(trace=false),
  }
  let value = run_candidate_program_with_recorder(interp, stmts, evidence)
  (value, evidence)
}

///|
pub fn run_candidate_program(
  interp : @runtime.Interpreter,
  stmts : Array[@ast.Stmt],
) -> @runtime.Value raise Error {
  let (value, _) = run_candidate_program_with_summary(interp, stmts)
  value
}

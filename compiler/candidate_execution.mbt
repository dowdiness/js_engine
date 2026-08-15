///|
// A compiler-owned cursor is created for each materialized JavaScript
// function value.  It consumes children in source order, while the child
// source identity and typed selection remain the authority for routing.
priv struct CandidateMaterializationCursor {
  candidate : CandidateFunction
  evidence : Ref[CandidateRouteEvidence]
  mut next_child : Int
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

///|
fn candidate_request_matches(
  candidate : CandidateFunction,
  request : @runtime.FunctionMaterializationRequest,
) -> Bool {
  let consumer_form = match candidate.consumer_form {
    Some(form) => form
    None => return false
  }
  if candidate_request_form(consumer_form) != request.form {
    return false
  }
  if candidate.name != request.name &&
    request.form != @runtime.ArrowFunction {
    return false
  }
  match (candidate.signature, request.parameters) {
    (CandidateSimpleSignature(params), @runtime.SimpleFunctionParameters(actual)) =>
      params == actual
    (
      CandidateExtendedSignature(params, rest),
      @runtime.ExtendedFunctionParameters(actual, actual_rest),
    ) => params == actual && rest == actual_rest
    _ => false
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
    name=name,
    parameters=parameters,
    body=candidate.body.copy(),
    closure=closure,
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
    begin=fn() {
      candidate_materializer_instance(candidate, evidence)
    },
    materialize=fn(_interp, _request) raise {
      raise @errors.InternalError(
        message="candidate materializer used outside an activation cursor",
      )
    },
  )
}

///|
fn candidate_materializer_instance(
  candidate : CandidateFunction,
  evidence : Ref[CandidateRouteEvidence],
) -> @runtime.FunctionMaterializer {
  let cursor : Ref[CandidateMaterializationCursor] = {
    val: {
      candidate,
      evidence,
      next_child: 0,
    },
  }
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
        if normal { CandidateRouteNormal } else { CandidateRouteAbrupt },
      )
    },
  )
  @runtime.FunctionMaterializer(
    begin=fn() {
      candidate_materializer_instance(candidate, evidence)
    },
    materialize=fn(interp, request) raise {
      let state = cursor.val
      guard state.next_child < state.candidate.children.length() else {
        raise @errors.InternalError(
          message="candidate function child cursor exceeded verified plan",
        )
      }
      let child = state.candidate.children[state.next_child]
      state.next_child += 1
      guard candidate_request_matches(child, request) else {
        raise @errors.InternalError(
          message="candidate child materialization metadata mismatch",
        )
      }
      candidate_make_callable(interp, child, state.evidence, request)
    },
    hooks=Some(hooks),
  )
}

///|
priv struct CandidateBytecodeExecutorCode {
  candidate : CandidateFunction
  bytecode : CandidateVerifiedBytecodeFunction
  activation : CandidateRouteActivation
}

///|
fn CandidateBytecodeExecutorCode::CandidateBytecodeExecutorCode(
  candidate : CandidateFunction,
  bytecode : CandidateVerifiedBytecodeFunction,
  activation : CandidateRouteActivation,
) -> CandidateBytecodeExecutorCode {
  { candidate, bytecode, activation }
}

///|
fn candidate_make_bytecode_callable(
  _interp : @runtime.Interpreter,
  candidate : CandidateFunction,
  bytecode : CandidateVerifiedBytecodeFunction,
  evidence : Ref[CandidateRouteEvidence],
  request : @runtime.FunctionMaterializationRequest,
) -> @runtime.Value raise Error {
  let func_def = bytecode.function
  let activation = candidate_route_prepare(
    evidence,
    candidate.source_identity,
    candidate.selection,
  )
  let code = CandidateBytecodeExecutorCode(candidate, bytecode, activation)
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
    UseTreeWalker(_) => candidate_make_tree_callable(candidate, evidence, request)
    UseBytecode(_) => {
      let bytecode = match candidate.bytecode {
        Some(bytecode) => bytecode
        None =>
          raise @errors.InternalError(
            message="candidate bytecode selection has no checked carrier",
          )
      }
      candidate_make_bytecode_callable(
        interp,
        candidate,
        bytecode,
        evidence,
        request,
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
  candidate_route_start(self.activation, CandidateBytecodeExecutor)
  let frame = BytecodeFrame::candidate(
    self.candidate,
    self.bytecode,
    prepared.environment(),
    prepared.context(),
    self.activation,
    direct_args=Some(prepared.arguments()),
  ) catch {
    error => {
      candidate_route_complete(self.activation, CandidateRouteAbrupt)
      raise error
    }
  }
  start_candidate_bytecode_frame(interp, frame) as &@runtime.ExecutorActivationFrame
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
  let frame = BytecodeFrame::candidate(
    candidate,
    bytecode,
    env,
    ctx,
    activation,
  ) catch {
    error => {
      candidate_route_complete(activation, CandidateRouteAbrupt)
      raise error
    }
  }
  let frame = start_candidate_bytecode_frame(interp, frame)
  let result = interp.run_executor_activation_coordinator(
    frame as &@runtime.ExecutorActivationFrame,
  ) catch {
    error => {
      frame.complete_candidate_route(false)
      raise error
    }
  }
  match result {
    @runtime.ExecutorActivationNormal(value)
    | @runtime.ExecutorActivationReturn(value) => value
    @runtime.ExecutorActivationContinue
    | @runtime.ExecutorActivationCall(_)
    | @runtime.ExecutorActivationConstruct(_)
    | @runtime.ExecutorActivationPropertyGet(_)
    | @runtime.ExecutorActivationPropertySet(_)
    | @runtime.ExecutorActivationPropertyUpdate(_) =>
      raise @errors.InternalError(
        message="candidate root coordinator returned a pending activation",
      )
  }
}

///|
fn run_candidate_program_with_evidence(
  interp : @runtime.Interpreter,
  stmts : Array[@ast.Stmt],
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  let program = prepare_candidate_program(stmts)
  let evidence : Ref[CandidateRouteEvidence] = {
    val: CandidateRouteEvidence(),
  }
  let value = match program.root.selection {
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
  (value, evidence)
}

///|
pub fn run_candidate_program(
  interp : @runtime.Interpreter,
  stmts : Array[@ast.Stmt],
) -> @runtime.Value raise Error {
  let (value, _) = run_candidate_program_with_evidence(interp, stmts)
  value
}

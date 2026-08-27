///|
/// Promise jobs and resolving functions use the executor activation seam while
/// keeping Promise state transitions in this runtime package.  The generic
/// microtask queue remains responsible for observation, selection, and
/// consumption; these private callables only own the selected job's lifetime.

///|
priv enum PromiseResolutionKind {
  PromiseResolutionResolve
  PromiseResolutionReject
}

///|
priv struct PromiseResolutionExecutorCode {
  owner : Interpreter
  promise_data : PromiseData
  already_resolved : Ref[Bool]
  kind : PromiseResolutionKind
}

///|
fn PromiseResolutionExecutorCode::PromiseResolutionExecutorCode(
  owner~ : Interpreter,
  promise_data~ : PromiseData,
  already_resolved~ : Ref[Bool],
  kind~ : PromiseResolutionKind,
) -> PromiseResolutionExecutorCode {
  { owner, promise_data, already_resolved, kind }
}

///|
priv enum PromiseResolutionPhase {
  PromiseResolutionNeedStart
  PromiseResolutionAwaitThenGet
  PromiseResolutionNeedThenableJob
  PromiseResolutionNeedFulfill(Value)
  PromiseResolutionNeedReject(Value)
  PromiseResolutionComplete
}

///|
priv struct PromiseResolutionExecutorFrame {
  owner : Interpreter
  promise_data : PromiseData
  already_resolved : Ref[Bool]
  kind : PromiseResolutionKind
  global : Environment
  resolution : Value
  mut then_value : Value
  mut phase : PromiseResolutionPhase
}

///|
fn PromiseResolutionExecutorFrame::PromiseResolutionExecutorFrame(
  owner~ : Interpreter,
  promise_data~ : PromiseData,
  already_resolved~ : Ref[Bool],
  kind~ : PromiseResolutionKind,
  global~ : Environment,
  resolution~ : Value,
) -> PromiseResolutionExecutorFrame {
  {
    owner,
    promise_data,
    already_resolved,
    kind,
    global,
    resolution,
    then_value: Undefined,
    phase: PromiseResolutionNeedStart,
  }
}

///|
// Only JavaScript guest errors become promise rejection reasons.  Internal
// errors and execution-control failures must cross the checkpoint boundary as
// runtime failures instead of being silently converted into guest values.
fn promise_guest_error_value(error : Error, global : Environment) -> Value? {
  match error {
    JsException(value) => Some(value)
    error =>
      match @errors.name_message_if_js_error(error) {
        Some(("InternalError", _)) => None
        Some(_) => Some(js_error_to_value_with_env(error, Some(global)))
        None => None
      }
  }
}

///|
fn PromiseResolutionExecutorFrame::step_start(
  self : PromiseResolutionExecutorFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.kind {
    PromiseResolutionReject => {
      if self.already_resolved.val {
        self.phase = PromiseResolutionComplete
      } else {
        self.already_resolved.val = true
        self.phase = PromiseResolutionNeedReject(self.resolution)
      }
      self.step_frame(interp)
    }
    PromiseResolutionResolve =>
      if self.already_resolved.val {
        self.phase = PromiseResolutionComplete
        self.step_frame(interp)
      } else {
        // First-call-wins is committed before any property lookup or call.
        self.already_resolved.val = true
        match self.resolution {
          Promise(pd) if physical_equal(pd, self.promise_data) => {
            let error = js_error_to_value_with_env(
              @errors.TypeError(message="Chaining cycle detected for promise"),
              Some(self.global),
            )
            self.phase = PromiseResolutionNeedReject(error)
            self.step_frame(interp)
          }
          _ if is_thenable_object_candidate(self.resolution) => {
            self.phase = PromiseResolutionAwaitThenGet
            executor_activation_managed_property_get(
              self.resolution,
              "then",
              @token.Loc::default(),
            )
          }
          _ => {
            self.phase = PromiseResolutionNeedFulfill(self.resolution)
            self.step_frame(interp)
          }
        }
      }
  }
}

///|
fn PromiseResolutionExecutorFrame::step_frame(
  self : PromiseResolutionExecutorFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    PromiseResolutionNeedStart => self.step_start(interp)
    PromiseResolutionNeedFulfill(value) => {
      fulfill_promise(self.owner, self.promise_data, value)
      self.phase = PromiseResolutionComplete
      ExecutorActivationReturn(Undefined)
    }
    PromiseResolutionNeedReject(reason) => {
      reject_promise(self.owner, self.promise_data, reason)
      self.phase = PromiseResolutionComplete
      ExecutorActivationReturn(Undefined)
    }
    PromiseResolutionNeedThenableJob => {
      enqueue_promise_thenable_job(
        self.owner,
        self.promise_data,
        self.resolution,
        self.then_value,
      )
      self.phase = PromiseResolutionComplete
      ExecutorActivationReturn(Undefined)
    }
    PromiseResolutionComplete => ExecutorActivationReturn(Undefined)
    PromiseResolutionAwaitThenGet =>
      raise @errors.InternalError(
        message="Promise resolution frame stepped while awaiting a child",
      )
  }
}

///|
impl ExecutorActivationFrame for PromiseResolutionExecutorFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for PromiseResolutionExecutorFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="Promise resolution frame received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        PromiseResolutionAwaitThenGet =>
          if is_callable(value) {
            self.then_value = value
            self.phase = PromiseResolutionNeedThenableJob
          } else {
            self.phase = PromiseResolutionNeedFulfill(self.resolution)
          }
        PromiseResolutionNeedStart
        | PromiseResolutionNeedThenableJob
        | PromiseResolutionNeedFulfill(_)
        | PromiseResolutionNeedReject(_)
        | PromiseResolutionComplete =>
          raise @errors.InternalError(
            message="Promise resolution frame received an unexpected completion",
          )
      }
    ExecutorActivationCompletionAbrupt(error) =>
      match self.phase {
        PromiseResolutionAwaitThenGet =>
          match promise_guest_error_value(error, self.global) {
            Some(reason) => self.phase = PromiseResolutionNeedReject(reason)
            None => raise error
          }
        PromiseResolutionNeedStart
        | PromiseResolutionNeedThenableJob
        | PromiseResolutionNeedFulfill(_)
        | PromiseResolutionNeedReject(_)
        | PromiseResolutionComplete =>
          raise @errors.InternalError(
            message="Promise resolution frame received an unexpected abrupt completion",
          )
      }
  }
}

///|
impl ExecutorCode for PromiseResolutionExecutorCode with fn start(
  self,
  _interp,
  prepared,
) {
  let args = prepared.arguments()
  let resolution = if args.length() > 0 { args[0] } else { Undefined }
  PromiseResolutionExecutorFrame(
    owner=self.owner,
    promise_data=self.promise_data,
    already_resolved=self.already_resolved,
    kind=self.kind,
    global=self.owner.global,
    resolution~,
  )
  as &ExecutorActivationFrame
}

///|
// Both capabilities capture one shared alreadyResolved cell.  Thenable
// assimilation creates a fresh pair for the managed then call, as required by
// the Promise Resolve Thenable Job algorithm.
fn make_promise_resolving_functions(
  interp : Interpreter,
  promise_data : PromiseData,
) -> (Value, Value) {
  let already_resolved : Ref[Bool] = { val: false }
  let resolve = make_executor_function(
    Some(""),
    ["resolution"],
    interp.global,
    true,
    PromiseResolutionExecutorCode(
      owner=interp,
      promise_data~,
      already_resolved~,
      kind=PromiseResolutionResolve,
    ),
    constructable=false,
    define_arguments_object=false,
  )
  let reject = make_executor_function(
    Some(""),
    ["reason"],
    interp.global,
    true,
    PromiseResolutionExecutorCode(
      owner=interp,
      promise_data~,
      already_resolved~,
      kind=PromiseResolutionReject,
    ),
    constructable=false,
    define_arguments_object=false,
  )
  (resolve, reject)
}

///|
fn promise_thenable_job_realm_protos(
  interp : Interpreter,
  then_method : Value,
) -> FunctionRealmProtos {
  let selected = get_function_realm_protos(then_method) catch { _ => None }
  match selected {
    Some(protos) => protos
    None => active_realm_protos(interp.realm_state)
  }
}

///|
priv struct PromiseThenableJobExecutorCode {
  promise_data : PromiseData
  thenable : Value
  then_method : Value
  realm_protos : FunctionRealmProtos
  consumed : Ref[Bool]
}

///|
fn PromiseThenableJobExecutorCode::PromiseThenableJobExecutorCode(
  promise_data~ : PromiseData,
  thenable~ : Value,
  then_method~ : Value,
  realm_protos~ : FunctionRealmProtos,
  consumed~ : Ref[Bool],
) -> PromiseThenableJobExecutorCode {
  { promise_data, thenable, then_method, realm_protos, consumed }
}

///|
priv enum PromiseThenableJobPhase {
  PromiseThenableJobNeedStart
  PromiseThenableJobAwaitThenCall
  PromiseThenableJobNeedReject(Value)
  PromiseThenableJobAwaitReject
  PromiseThenableJobComplete
}

///|
priv struct PromiseThenableJobExecutorFrame {
  promise_data : PromiseData
  thenable : Value
  then_method : Value
  realm_protos : FunctionRealmProtos
  global : Environment
  mut reject : Value
  mut phase : PromiseThenableJobPhase
}

///|
fn PromiseThenableJobExecutorFrame::PromiseThenableJobExecutorFrame(
  promise_data~ : PromiseData,
  thenable~ : Value,
  then_method~ : Value,
  realm_protos~ : FunctionRealmProtos,
  global~ : Environment,
) -> PromiseThenableJobExecutorFrame {
  {
    promise_data,
    thenable,
    then_method,
    realm_protos,
    global,
    reject: Undefined,
    phase: PromiseThenableJobNeedStart,
  }
}

///|
fn PromiseThenableJobExecutorFrame::step_frame(
  self : PromiseThenableJobExecutorFrame,
  interp : Interpreter,
) -> ExecutorActivationStep raise Error {
  match self.phase {
    PromiseThenableJobNeedStart => {
      // The resolving pair is created at job activation, not when the
      // original resolve function merely schedules this job.
      let (resolve, reject) = with_active_realm_protos(
        interp.realm_state,
        self.realm_protos,
        () => make_promise_resolving_functions(interp, self.promise_data),
      )
      self.reject = reject
      self.phase = PromiseThenableJobAwaitThenCall
      executor_activation_call(
        self.then_method,
        self.thenable,
        [resolve, reject],
        @token.Loc::default(),
      )
    }
    PromiseThenableJobNeedReject(reason) => {
      self.phase = PromiseThenableJobAwaitReject
      executor_activation_call(
        self.reject,
        Undefined,
        [reason],
        @token.Loc::default(),
      )
    }
    PromiseThenableJobComplete => ExecutorActivationReturn(Undefined)
    PromiseThenableJobAwaitThenCall | PromiseThenableJobAwaitReject =>
      raise @errors.InternalError(
        message="Promise thenable job stepped while awaiting a child",
      )
  }
}

///|
impl ExecutorActivationFrame for PromiseThenableJobExecutorFrame with fn step(
  self,
  interp,
) {
  self.step_frame(interp)
}

///|
impl ExecutorActivationFrame for PromiseThenableJobExecutorFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="Promise thenable job received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(_) =>
      match self.phase {
        PromiseThenableJobAwaitThenCall | PromiseThenableJobAwaitReject =>
          self.phase = PromiseThenableJobComplete
        PromiseThenableJobNeedStart
        | PromiseThenableJobNeedReject(_)
        | PromiseThenableJobComplete =>
          raise @errors.InternalError(
            message="Promise thenable job received an unexpected completion",
          )
      }
    ExecutorActivationCompletionAbrupt(error) =>
      match self.phase {
        PromiseThenableJobAwaitThenCall =>
          match promise_guest_error_value(error, self.global) {
            Some(reason) => self.phase = PromiseThenableJobNeedReject(reason)
            None => raise error
          }
        PromiseThenableJobAwaitReject => raise error
        PromiseThenableJobNeedStart
        | PromiseThenableJobNeedReject(_)
        | PromiseThenableJobComplete =>
          raise @errors.InternalError(
            message="Promise thenable job received an unexpected abrupt completion",
          )
      }
  }
}

///|
impl ExecutorCode for PromiseThenableJobExecutorCode with fn start(
  self,
  interp,
  _prepared,
) {
  guard !self.consumed.val else {
    raise @errors.InternalError(
      message="Promise thenable job executor callable was invoked twice",
    )
  }
  self.consumed.val = true
  PromiseThenableJobExecutorFrame(
    promise_data=self.promise_data,
    thenable=self.thenable,
    then_method=self.then_method,
    realm_protos=self.realm_protos,
    global=interp.global,
  )
  as &ExecutorActivationFrame
}

///|
fn make_promise_thenable_job(
  interp : Interpreter,
  promise_data : PromiseData,
  thenable : Value,
  then_method : Value,
) -> Value {
  let realm_protos = promise_thenable_job_realm_protos(interp, then_method)
  make_executor_function(
    Some("PromiseResolveThenableJob"),
    [],
    interp.global,
    true,
    PromiseThenableJobExecutorCode(
      promise_data~,
      thenable~,
      then_method~,
      realm_protos~,
      consumed={ val: false },
    ),
    constructable=false,
    define_arguments_object=false,
  )
}

///|
fn enqueue_promise_thenable_job(
  interp : Interpreter,
  promise_data : PromiseData,
  thenable : Value,
  then_method : Value,
) -> Unit {
  let job = make_promise_thenable_job(
    interp, promise_data, thenable, then_method,
  )
  interp.enqueue_microtask(job, [])
}

///|
priv struct PromiseReactionExecutorCode {
  reaction : PromiseReaction
  consumed : Ref[Bool]
}

///|
fn PromiseReactionExecutorCode::PromiseReactionExecutorCode(
  reaction~ : PromiseReaction,
  consumed~ : Ref[Bool],
) -> PromiseReactionExecutorCode {
  { reaction, consumed }
}

///|
priv enum PromiseReactionPhase {
  PromiseReactionNeedHandler
  PromiseReactionAwaitHandler
  PromiseReactionNeedResolve(Value)
  PromiseReactionAwaitResolve
  PromiseReactionNeedReject(Value)
  PromiseReactionAwaitReject
  PromiseReactionComplete
}

///|
priv struct PromiseReactionExecutorFrame {
  reaction : PromiseReaction
  argument : Value
  global : Environment
  mut phase : PromiseReactionPhase
}

///|
fn PromiseReactionExecutorFrame::PromiseReactionExecutorFrame(
  reaction~ : PromiseReaction,
  argument~ : Value,
  global~ : Environment,
) -> PromiseReactionExecutorFrame {
  { reaction, argument, global, phase: PromiseReactionNeedHandler }
}

///|
impl ExecutorActivationFrame for PromiseReactionExecutorFrame with fn step(
  self,
  _interp,
) {
  match self.phase {
    PromiseReactionNeedHandler =>
      match self.reaction.handler {
        Some(handler) => {
          self.phase = PromiseReactionAwaitHandler
          executor_activation_call(
            handler,
            Undefined,
            [self.argument],
            @token.Loc::default(),
          )
        }
        None =>
          match self.reaction.reaction_type {
            Fulfill => {
              self.phase = PromiseReactionAwaitResolve
              executor_activation_call(
                self.reaction.resolve,
                Undefined,
                [self.argument],
                @token.Loc::default(),
              )
            }
            Reject => {
              self.phase = PromiseReactionAwaitReject
              executor_activation_call(
                self.reaction.reject,
                Undefined,
                [self.argument],
                @token.Loc::default(),
              )
            }
          }
      }
    PromiseReactionNeedResolve(value) => {
      self.phase = PromiseReactionAwaitResolve
      executor_activation_call(
        self.reaction.resolve,
        Undefined,
        [value],
        @token.Loc::default(),
      )
    }
    PromiseReactionNeedReject(reason) => {
      self.phase = PromiseReactionAwaitReject
      executor_activation_call(
        self.reaction.reject,
        Undefined,
        [reason],
        @token.Loc::default(),
      )
    }
    PromiseReactionComplete => ExecutorActivationReturn(Undefined)
    PromiseReactionAwaitHandler
    | PromiseReactionAwaitResolve
    | PromiseReactionAwaitReject =>
      raise @errors.InternalError(
        message="Promise reaction frame stepped while awaiting a child",
      )
  }
}

///|
impl ExecutorActivationFrame for PromiseReactionExecutorFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="Promise reaction frame received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        PromiseReactionAwaitHandler =>
          self.phase = PromiseReactionNeedResolve(value)
        PromiseReactionAwaitResolve | PromiseReactionAwaitReject =>
          self.phase = PromiseReactionComplete
        PromiseReactionNeedHandler
        | PromiseReactionNeedResolve(_)
        | PromiseReactionNeedReject(_)
        | PromiseReactionComplete =>
          raise @errors.InternalError(
            message="Promise reaction frame received an unexpected completion",
          )
      }
    ExecutorActivationCompletionAbrupt(error) =>
      match self.phase {
        PromiseReactionAwaitHandler =>
          match promise_guest_error_value(error, self.global) {
            Some(reason) => self.phase = PromiseReactionNeedReject(reason)
            None => raise error
          }
        PromiseReactionAwaitResolve | PromiseReactionAwaitReject => raise error
        PromiseReactionNeedHandler
        | PromiseReactionNeedResolve(_)
        | PromiseReactionNeedReject(_)
        | PromiseReactionComplete =>
          raise @errors.InternalError(
            message="Promise reaction frame received an unexpected abrupt completion",
          )
      }
  }
}

///|
impl ExecutorCode for PromiseReactionExecutorCode with fn start(
  self,
  interp,
  prepared,
) {
  guard !self.consumed.val else {
    raise @errors.InternalError(
      message="Promise reaction executor callable was invoked twice",
    )
  }
  self.consumed.val = true
  let args = prepared.arguments()
  let argument = if args.length() > 0 { args[0] } else { Undefined }
  PromiseReactionExecutorFrame(
    reaction=self.reaction,
    argument~,
    global=interp.global,
  )
  as &ExecutorActivationFrame
}

///|
fn make_promise_reaction_job(
  interp : Interpreter,
  reaction : PromiseReaction,
) -> Value {
  make_executor_function(
    Some("PromiseReactionJob"),
    [],
    interp.global,
    true,
    PromiseReactionExecutorCode(reaction~, consumed={ val: false }),
    constructable=false,
    define_arguments_object=false,
  )
}

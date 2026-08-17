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
  promise_data : PromiseData
  already_resolved : Ref[Bool]
  kind : PromiseResolutionKind
}

///|
fn PromiseResolutionExecutorCode::PromiseResolutionExecutorCode(
  promise_data~ : PromiseData,
  already_resolved~ : Ref[Bool],
  kind~ : PromiseResolutionKind,
) -> PromiseResolutionExecutorCode {
  { promise_data, already_resolved, kind }
}

///|
priv enum PromiseResolutionPhase {
  PromiseResolutionNeedStart
  PromiseResolutionAwaitThenGet
  PromiseResolutionNeedThenCall
  PromiseResolutionAwaitThenCall
  PromiseResolutionNeedThenableReject(Value)
  PromiseResolutionAwaitThenableReject
  PromiseResolutionNeedFulfill(Value)
  PromiseResolutionNeedReject(Value)
  PromiseResolutionComplete
}

///|
priv struct PromiseResolutionExecutorFrame {
  promise_data : PromiseData
  already_resolved : Ref[Bool]
  kind : PromiseResolutionKind
  global : Environment
  resolution : Value
  mut then_value : Value
  mut then_reject : Value
  mut phase : PromiseResolutionPhase
}

///|
fn PromiseResolutionExecutorFrame::PromiseResolutionExecutorFrame(
  promise_data~ : PromiseData,
  already_resolved~ : Ref[Bool],
  kind~ : PromiseResolutionKind,
  global~ : Environment,
  resolution~ : Value,
) -> PromiseResolutionExecutorFrame {
  {
    promise_data,
    already_resolved,
    kind,
    global,
    resolution,
    then_value: Undefined,
    then_reject: Undefined,
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
      fulfill_promise(interp, self.promise_data, value)
      self.phase = PromiseResolutionComplete
      ExecutorActivationReturn(Undefined)
    }
    PromiseResolutionNeedReject(reason) => {
      reject_promise(interp, self.promise_data, reason)
      self.phase = PromiseResolutionComplete
      ExecutorActivationReturn(Undefined)
    }
    PromiseResolutionNeedThenCall => {
      let (resolve, reject) = make_promise_resolving_functions(
        interp,
        self.promise_data,
      )
      self.then_reject = reject
      self.phase = PromiseResolutionAwaitThenCall
      executor_activation_call(
        self.then_value,
        self.resolution,
        [resolve, reject],
        @token.Loc::default(),
      )
    }
    PromiseResolutionNeedThenableReject(reason) => {
      self.phase = PromiseResolutionAwaitThenableReject
      executor_activation_call(
        self.then_reject,
        Undefined,
        [reason],
        @token.Loc::default(),
      )
    }
    PromiseResolutionComplete => ExecutorActivationReturn(Undefined)
    PromiseResolutionAwaitThenGet
    | PromiseResolutionAwaitThenCall
    | PromiseResolutionAwaitThenableReject =>
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
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        PromiseResolutionAwaitThenGet =>
          if is_callable(value) {
            self.then_value = value
            self.phase = PromiseResolutionNeedThenCall
          } else {
            self.phase = PromiseResolutionNeedFulfill(self.resolution)
          }
        PromiseResolutionAwaitThenCall => self.phase = PromiseResolutionComplete
        PromiseResolutionAwaitThenableReject =>
          self.phase = PromiseResolutionComplete
        PromiseResolutionNeedStart
        | PromiseResolutionNeedThenCall
        | PromiseResolutionNeedThenableReject(_)
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
        PromiseResolutionAwaitThenCall =>
          match promise_guest_error_value(error, self.global) {
            Some(reason) =>
              self.phase = PromiseResolutionNeedThenableReject(reason)
            None => raise error
          }
        PromiseResolutionAwaitThenableReject => raise error
        PromiseResolutionNeedStart
        | PromiseResolutionNeedThenCall
        | PromiseResolutionNeedThenableReject(_)
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
  interp,
  prepared,
) {
  let args = prepared.arguments()
  let resolution = if args.length() > 0 { args[0] } else { Undefined }
  PromiseResolutionExecutorFrame(
    promise_data=self.promise_data,
    already_resolved=self.already_resolved,
    kind=self.kind,
    global=interp.global,
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

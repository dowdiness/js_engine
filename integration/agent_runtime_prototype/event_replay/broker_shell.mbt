///|
/// PROTOTYPE thin host shell over the P1 pure ToolBroker reducer.
priv struct BrokerShell {
  session_id_ : String
  mut state_ : @broker.BrokerState
}

///|
fn BrokerShell::BrokerShell(session_id : String) -> BrokerShell {
  {
    session_id_: session_id,
    state_: @broker.BrokerState(session_id, true, true, 4, 4096),
  }
}

///|
fn ensure_transition(
  transition : @broker.Transition,
  label : String,
) -> @broker.BrokerState {
  let state = transition.after()
  guard state.last_transition_error() is None else {
    abort(
      "PROTOTYPE ToolBroker transition failed at " +
      label +
      ": " +
      state.render().stringify(),
    )
  }
  state
}

///|
fn BrokerShell::submit_and_validate(
  self : BrokerShell,
  request : Json,
) -> String {
  let submitted = @broker.submit_worker_request(self.state_, request)
  self.state_ = ensure_transition(submitted, "submit")
  let validated = @broker.apply_host_action(
    self.state_,
    @broker.host_validate(),
  )
  self.state_ = ensure_transition(validated, "validate")
  match self.state_.current_call_id() {
    Some(call_id) => call_id
    None => abort("PROTOTYPE invariant: validated broker has no call ID")
  }
}

///|
fn BrokerShell::expected_idempotency_key(
  self : BrokerShell,
  call_id : String,
) -> String {
  self.session_id_ + ":" + call_id
}

///|
fn BrokerShell::approve(self : BrokerShell, call_id : String) -> Unit {
  let transition = @broker.apply_host_action(
    self.state_,
    @broker.operator_approve(call_id),
  )
  self.state_ = ensure_transition(transition, "approve")
}

///|
fn single_invocation(
  transition : @broker.Transition,
) -> @broker.AdapterInvocation {
  guard transition.effects().length() == 1 else {
    abort("PROTOTYPE invariant: dispatch did not emit exactly one effect")
  }
  match transition.effects()[0].adapter_invocation() {
    Some(invocation) => invocation
    None => abort("PROTOTYPE invariant: dispatch effect was not InvokeAdapter")
  }
}

///|
fn BrokerShell::dispatch(
  self : BrokerShell,
  call_id : String,
) -> @broker.AdapterInvocation {
  let transition = @broker.apply_host_action(
    self.state_,
    @broker.host_dispatch(call_id),
  )
  let invocation = single_invocation(transition)
  self.state_ = ensure_transition(transition, "dispatch")
  invocation
}

///|
fn result_value(result : Json) -> Json {
  match result {
    Json::Object(fields) =>
      match (fields.get("tag"), fields.get("value")) {
        (Some(Json::String("ok")), Some(value)) => value
        _ =>
          abort(
            "PROTOTYPE invariant: scenario uses only tagged success results",
          )
      }
    _ => abort("PROTOTYPE invariant: tool result is not an object")
  }
}

///|
fn delivered_result(transition : @broker.Transition) -> Json {
  guard transition.effects().length() == 1 else {
    abort("PROTOTYPE invariant: delivery did not emit exactly one effect")
  }
  match transition.effects()[0].delivered_result() {
    Some(result) => result
    None => abort("PROTOTYPE invariant: delivery effect lacks ToolResult")
  }
}

///|
fn BrokerShell::record_and_deliver(
  self : BrokerShell,
  call_id : String,
  result : Json,
  write_committed : Bool,
) -> Json {
  let recorded = @broker.apply_host_action(
    self.state_,
    @broker.adapter_succeeded_action(
      call_id,
      result_value(result),
      write_committed,
    ),
  )
  self.state_ = ensure_transition(recorded, "record adapter result")
  let delivered = @broker.apply_host_action(
    self.state_,
    @broker.host_deliver_result(),
  )
  let emitted = delivered_result(delivered)
  self.state_ = ensure_transition(delivered, "deliver tool result")
  guard emitted.equal(result) else {
    abort("PROTOTYPE invariant: P1 broker changed recorded ToolResult")
  }
  emitted
}

///|
fn BrokerShell::cancel(
  self : BrokerShell,
  call_id : String,
  reason : String,
) -> Unit {
  let transition = @broker.apply_host_action(
    self.state_,
    @broker.operator_cancel(call_id, reason),
  )
  self.state_ = ensure_transition(transition, "cancel")
}

///|
fn BrokerShell::phase(self : BrokerShell) -> String {
  self.state_.phase_name()
}

///|
fn BrokerShell::approval_status(self : BrokerShell) -> String {
  self.state_.current_approval_status()
}

///|
fn BrokerShell::render(self : BrokerShell) -> Json {
  self.state_.render()
}

// Deterministic state machine for the exact admitted Array.prototype.map
// callback slice. Runtime effects are acknowledged through MapEvent; this
// core owns no evaluator closure or host-language callback.

///|
priv suberror InvalidMapTransition {
  InvalidMapTransition(String)
}

///|
#warnings("-unused_constructor")
priv enum MapPhase {
  MapReady
  MapAwaitingHasProperty
  MapAwaitingGet
  MapAwaitingCallback
  MapAwaitingDefine
  MapCompleted
  MapFailed
}

///|
priv struct MapState {
  length : Int64
  index : Int64
  receiver : Value
  result : Value
  callback : Value
  this_arg : Value
  pending_result_consumer : DispatchContinuation
  phase : MapPhase
}

///|
#warnings("-unused_value")
fn MapState::MapState(
  length~ : Int64,
  index? : Int64 = 0L,
  receiver~ : Value,
  result~ : Value,
  callback~ : Value,
  this_arg~ : Value,
  pending_result_consumer~ : DispatchContinuation,
  phase? : MapPhase = MapReady,
) -> MapState {
  {
    length,
    index,
    receiver,
    result,
    callback,
    this_arg,
    pending_result_consumer,
    phase,
  }
}

///|
#warnings("-unused_constructor")
priv enum MapEvent {
  MapStart
  MapHasProperty(Bool)
  MapGotValue(Value)
  MapCallbackReturned(Value)
  MapPropertyDefined
  MapAbrupt(Error)
}

///|
#warnings("-unused_constructor-unused_field")
priv enum MapDecision {
  MapRequestHasProperty(Int64)
  MapRequestGet(Int64)
  MapRequestCallback(Value, Value, Int64, Value, Value)
  MapRequestDefine(Int64, Value)
  MapComplete(Value, DispatchContinuation)
  MapAbort(Error)
}

///|
fn[T] invalid_map_transition(message : String) -> T raise InvalidMapTransition {
  raise InvalidMapTransition(message)
}

///|
fn map_state_is_terminal(state : MapState) -> Bool {
  match state.phase {
    MapCompleted | MapFailed => true
    _ => false
  }
}

///|
fn map_next_decision(
  state : MapState,
) -> (MapState, MapDecision) raise InvalidMapTransition {
  guard state.phase is MapReady else {
    invalid_map_transition("map next decision requires Ready")
  }
  if state.index >= state.length {
    let completed = { ..state, phase: MapCompleted }
    (
      completed,
      MapDecision::MapComplete(state.result, state.pending_result_consumer),
    )
  } else {
    let awaiting = { ..state, phase: MapAwaitingHasProperty }
    (awaiting, MapDecision::MapRequestHasProperty(state.index))
  }
}

///|
#warnings("-unused_value")
fn reduce_array_map(
  state : MapState,
  event : MapEvent,
) -> (MapState, MapDecision) raise InvalidMapTransition {
  guard !map_state_is_terminal(state) else {
    invalid_map_transition("map received an event after terminal completion")
  }
  match (state.phase, event) {
    (MapReady, MapStart) => map_next_decision(state)
    (MapAwaitingHasProperty, MapHasProperty(true)) =>
      (
        { ..state, phase: MapAwaitingGet },
        MapDecision::MapRequestGet(state.index),
      )
    (MapAwaitingHasProperty, MapHasProperty(false)) => {
      let next = { ..state, index: state.index + 1L, phase: MapReady }
      map_next_decision(next)
    }
    (MapAwaitingGet, MapGotValue(value)) =>
      (
        { ..state, phase: MapAwaitingCallback },
        MapDecision::MapRequestCallback(
          state.callback,
          state.this_arg,
          state.index,
          state.receiver,
          value,
        ),
      )
    (MapAwaitingCallback, MapCallbackReturned(value)) =>
      (
        { ..state, phase: MapAwaitingDefine },
        MapDecision::MapRequestDefine(state.index, value),
      )
    (MapAwaitingDefine, MapPropertyDefined) => {
      let next = { ..state, index: state.index + 1L, phase: MapReady }
      map_next_decision(next)
    }
    (_, MapAbrupt(error)) =>
      ({ ..state, phase: MapFailed }, MapDecision::MapAbort(error))
    _ => invalid_map_transition("map event arrived outside its semantic order")
  }
}

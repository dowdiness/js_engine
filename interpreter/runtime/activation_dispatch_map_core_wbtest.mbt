///|
fn map_test_state(length : Int64) -> MapState {
  MapState(
    length~,
    receiver=Undefined,
    result=make_array([]),
    callback=Undefined,
    this_arg=Undefined,
    pending_result_consumer=DispatchCompleteReturn,
  )
}

///|
test "array map reducer advances absent elements without Get" {
  let (awaiting, decision) = reduce_array_map(map_test_state(1L), MapStart)
  match decision {
    MapRequestHasProperty(0L) => ()
    _ => fail("map start must request HasProperty")
  }
  let (completed, decision) = reduce_array_map(awaiting, MapHasProperty(false))
  match decision {
    MapComplete(_, DispatchCompleteReturn) => ()
    _ => fail("absent element must complete without Get")
  }
  guard completed.phase is MapCompleted else {
    fail("absent element completion must be terminal")
  }
}

///|
test "array map reducer acknowledges callback and property definition" {
  let state = map_test_state(1L)
  let (after_start, _) = reduce_array_map(state, MapStart)
  let (after_has, _) = reduce_array_map(after_start, MapHasProperty(true))
  let (after_get, decision) = reduce_array_map(
    after_has,
    MapGotValue(Number(2.0)),
  )
  match decision {
    MapRequestCallback(_, _, 0L, _, Number(2.0)) => ()
    _ => fail("present element must request callback with spec arguments")
  }
  let (after_callback, decision) = reduce_array_map(
    after_get,
    MapCallbackReturned(Number(3.0)),
  )
  match decision {
    MapRequestDefine(0L, Number(3.0)) => ()
    _ => fail("callback result must request property definition")
  }
  let (completed, decision) = reduce_array_map(
    after_callback,
    MapPropertyDefined,
  )
  match decision {
    MapComplete(_, DispatchCompleteReturn) => ()
    _ => fail("property acknowledgement must complete the one-element map")
  }
  guard completed.phase is MapCompleted else {
    fail("normal map completion must be terminal")
  }
}

///|
test "array map reducer rejects invalid order and double consumption" {
  let state = map_test_state(1L)
  let invalid : Result[(MapState, MapDecision), InvalidMapTransition] = Ok(
    reduce_array_map(state, MapGotValue(Undefined)),
  ) catch {
    error => Err(error)
  }
  guard invalid is Err(_) else {
    fail("Get result before HasProperty must reject")
  }
  let (awaiting, _) = reduce_array_map(state, MapStart)
  let (completed, _) = reduce_array_map(awaiting, MapHasProperty(false))
  let double : Result[(MapState, MapDecision), InvalidMapTransition] = Ok(
    reduce_array_map(completed, MapPropertyDefined),
  ) catch {
    error => Err(error)
  }
  guard double is Err(_) else { fail("terminal map state must reject reuse") }
}

///|
test "array map reducer preserves abrupt guest identity and terminal cleanup" {
  let state = map_test_state(1L)
  let (awaiting, _) = reduce_array_map(state, MapStart)
  let marker = make_array([String_("member marker")])
  let guest_throw : Error = JsException(marker)
  let (aborted, decision) = reduce_array_map(awaiting, MapAbrupt(guest_throw))
  match decision {
    MapAbort(JsException(actual)) =>
      match (marker, actual) {
        (Array(expected_data), Array(actual_data)) =>
          if !physical_equal(expected_data, actual_data) {
            fail("map abort changed the guest throw identity")
          }
        _ => fail("map abort lost the guest throw value")
      }
    _ => fail("abrupt map event must produce MapAbort")
  }
  guard aborted.phase is MapFailed else {
    fail("abrupt map event must leave a terminal failed state")
  }
  let reuse : Result[(MapState, MapDecision), InvalidMapTransition] = Ok(
    reduce_array_map(aborted, MapStart),
  ) catch {
    error => Err(error)
  }
  guard reuse is Err(_) else {
    fail("failed map state must reject terminal reuse")
  }
}

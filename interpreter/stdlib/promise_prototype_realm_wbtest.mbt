///| Whitebox tests for stdlib Promise prototype ownership by RealmState.

///|
fn new_promise_realm_state() -> @runtime.RealmState {
  @runtime.RealmState::from_symbols(@runtime.SymbolState::new())
}

///|
fn shifted_promise_realm_state() -> @runtime.RealmState {
  let symbols = @runtime.SymbolState::new()
  let _ = symbols.new_symbol(Some("offset"))
  @runtime.RealmState::from_symbols(symbols)
}

///|
fn assert_promise_object(
  label : String,
  value : Value,
) -> ObjectData raise Error {
  match value {
    Object(data) => data
    _ => fail(label + " expected object value")
  }
}

///|
test "promise prototype is realm-isolated" {
  let default_realm = new_promise_realm_state()
  let shifted_realm = shifted_promise_realm_state()
  let default_env = @runtime.Environment::new()
  let shifted_env = @runtime.Environment::new()
  setup_promise(default_env, default_realm)
  setup_promise(shifted_env, shifted_realm)

  // Each realm must have an installed Promise prototype.
  let default_proto = match default_realm.promise_prototype.val {
    Some(v) => v
    None => fail("default realm Promise.prototype missing")
  }
  let shifted_proto = match shifted_realm.promise_prototype.val {
    Some(v) => v
    None => fail("shifted realm Promise.prototype missing")
  }

  // The two prototypes must be physically distinct objects, not a shared
  // module-global value re-used across realms.
  let default_data = assert_promise_object(
    "default Promise.prototype", default_proto,
  )
  let shifted_data = assert_promise_object(
    "shifted Promise.prototype", shifted_proto,
  )
  if physical_equal(default_data, shifted_data) {
    fail("Promise.prototype must not be shared across realms")
  }

  // The realm-state field must agree with the JS-visible Promise.prototype
  // slot on the constructor object. Decoupling these would let a regression
  // silently route dispatch through one source while user code observes the
  // other (cache-for-X invariant; Codex finding on PR #138).
  let default_ctor_proto = ctor_prototype_from_env(default_env, "Promise")
  let default_ctor_proto_data = assert_promise_object(
    "default Promise constructor .prototype", default_ctor_proto,
  )
  if !physical_equal(default_data, default_ctor_proto_data) {
    fail(
      "realm_state.promise_prototype must equal Promise.prototype on the constructor",
    )
  }

  // get_promise_method must dispatch through the supplied realm: the same
  // PromiseData and key must yield each realm's own then() function.
  let promise_data = @runtime.new_promise_data()
  let default_then = get_promise_method(promise_data, "then", default_realm)
  let shifted_then = get_promise_method(promise_data, "then", shifted_realm)
  match default_then {
    Undefined => fail("expected Promise.prototype.then in default realm")
    _ => ()
  }
  match shifted_then {
    Undefined => fail("expected Promise.prototype.then in shifted realm")
    _ => ()
  }
  let default_then_obj = assert_promise_object("default then", default_then)
  let shifted_then_obj = assert_promise_object("shifted then", shifted_then)
  if physical_equal(default_then_obj, shifted_then_obj) {
    fail("Promise.prototype.then must not be shared across realms")
  }
}

///|
test "promise method lookup returns undefined for unknown keys" {
  let realm = new_promise_realm_state()
  setup_promise(@runtime.Environment::new(), realm)
  let promise_data = @runtime.new_promise_data()
  match get_promise_method(promise_data, "no_such_method", realm) {
    Undefined => ()
    _ => fail("expected Undefined for unknown method")
  }
}

///|
test "promise method lookup returns undefined when prototype is absent" {
  let realm = new_promise_realm_state()
  // No setup_promise call - realm.promise_prototype.val stays None.
  let promise_data = @runtime.new_promise_data()
  match get_promise_method(promise_data, "then", realm) {
    Undefined => ()
    _ => fail("expected Undefined without realm Promise.prototype")
  }
}

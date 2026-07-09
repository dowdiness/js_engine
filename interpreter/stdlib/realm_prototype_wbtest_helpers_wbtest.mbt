///| Shared whitebox helpers for realm-isolated stdlib prototype tests.
///
/// Centralizes helpers that were duplicated across `*_prototype_realm_wbtest.mbt`
/// files and hidden cross-file dependencies (e.g. `ctor_prototype_from_env`
/// living only in the weak-collection wbtest).

///|
fn new_realm_state() -> @runtime.RealmState {
  @runtime.RealmState::from_symbols(@runtime.SymbolState::new())
}

///|
fn shifted_realm_state() -> @runtime.RealmState {
  let symbols = @runtime.SymbolState::new()
  let _ = symbols.new_symbol(Some("offset"))
  @runtime.RealmState::from_symbols(symbols)
}

///|
fn assert_object_value(
  label : String,
  value : Value,
) -> ObjectData raise Error {
  match value {
    Object(data) => data
    _ => fail(label + " expected object value")
  }
}

///|
/// Look up the named constructor's `prototype` property from an environment.
///
/// Bridges the realm-state proto field to the JS-visible proto: a regression
/// that decouples `realm_state.*_prototype` from the constructor's `.prototype`
/// slot would otherwise be invisible to a realm-only test.
fn ctor_prototype_from_env(
  env : @runtime.Environment,
  ctor_name : String,
) -> Value raise Error {
  let ctor = match env.bindings.get(ctor_name) {
    Some(binding) => binding.value
    None => fail(ctor_name + " constructor missing from environment")
  }
  let ctor_data = match ctor {
    Object(data) => data
    _ => fail(ctor_name + " constructor is not an object")
  }
  match ctor_data.bag.properties.get("prototype") {
    Some(p) => p
    None => fail(ctor_name + ".prototype property missing from constructor")
  }
}

///|
fn assert_same_object(
  label : String,
  left : Value,
  right : Value,
) -> Unit raise Error {
  match (left, right) {
    (Object(left_data), Object(right_data)) =>
      if !physical_equal(left_data, right_data) {
        fail(label + " expected same object")
      }
    _ => fail(label + " expected object values")
  }
}

///|
fn assert_distinct_object(
  label : String,
  left : Value,
  right : Value,
) -> Unit raise Error {
  match (left, right) {
    (Object(left_data), Object(right_data)) =>
      if physical_equal(left_data, right_data) {
        fail(label + " expected distinct objects")
      }
    _ => fail(label + " expected object values")
  }
}

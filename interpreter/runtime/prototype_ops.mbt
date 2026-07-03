///|
/// Prototype internal operations (`[[GetPrototypeOf]]` / `[[SetPrototypeOf]]`)
/// relocated from `interpreter/stdlib/builtins_reflect.mbt` so that stdlib calls
/// a runtime operation instead of reaching into PropertyBag / ArrayData /
/// prototype / extensibility representation internals (architecture redesign
/// Stage 8, following #335 own-property-keys and #338 integrity ops).
///
/// These reproduce the existing Reflect.getPrototypeOf / Reflect.setPrototypeOf
/// behavior verbatim, including the existing latent asymmetries that are
/// preserved here and NOT "fixed": both operations only handle
/// Object / Array / Proxy targets and raise TypeError for Map / Set / Promise
/// targets even though those are objects whose `[[GetPrototypeOf]]` /
/// `[[SetPrototypeOf]]` should succeed. Object.getPrototypeOf /
/// Object.setPrototypeOf carry a richer (coercing, throw-on-non-extensible)
/// dispatch by design and intentionally do NOT route through these ops.
/// Aligning the Map/Set/Promise/Array arms is behavior-changing work tracked
/// for the enumerator-unification / internal-slot follow-ups (#336 / #337).

///|
/// Module-namespace exotic object `[[SetPrototypeOf]]` shortcut (§28.3 /
/// §10.4.6.2). Relocated from `interpreter/stdlib/module_namespace_helpers.mbt`;
/// the `stdlib_` name prefix is dropped because runtime is now the defining
/// package (necessary move fixup, not a redesign). Shared by
/// Reflect.setPrototypeOf and Object.setPrototypeOf.
pub fn module_namespace_set_prototype_result(
  data : ObjectData,
  proto : Value,
) -> Bool? {
  guard data.class_name == "Module" else { return None }
  // A module namespace exotic object accepts [[SetPrototypeOf]] only when the
  // new prototype is null (§10.4.6.2); any other proto fails.
  Some(proto is Null)
}

///|
/// [[SetPrototypeOf]] cycle detection and extensibility guard for ordinary objects
/// (§10.1.3). Returns true if the prototype was set, false if it would create a
/// cycle or the target is non-extensible. Does NOT handle immutable-prototype
/// exotic objects (Object.prototype) — callers check before reaching this.
pub fn ordinary_set_prototype(
  interp : Interpreter,
  data : ObjectData,
  proto : Value,
) -> Bool {
  if strict_equal(proto, data.prototype) {
    return true
  }
  if !data.extensible {
    return false
  }
  // §10.1.3 step 6: walk from proto up the chain checking if data is reachable
  let mut p = proto
  while true {
    if strict_equal(p, Object(data)) {
      return false
    }
    match p {
      Object(p_data) => p = p_data.prototype
      Array(p_data) => p = get_array_prototype(interp.realm_state, p_data)
      Null => break
      _ => break
    }
  }
  data.prototype = proto
  true
}

///|
pub fn object_get_prototype_of(
  interp : Interpreter,
  target : Value,
) -> Value raise Error {
  match target {
    Object(data) => data.prototype
    Array(data) => get_array_prototype(interp.realm_state, data)
    Value::Proxy(proxy_data) => proxy_get_prototype_of(interp, proxy_data)
    _ =>
      raise @errors.TypeError(
        message="Reflect.getPrototypeOf called on non-object",
      )
  }
}

///|
/// target.`[[SetPrototypeOf]]`(proto) backing for Reflect.setPrototypeOf
/// (§28.1.13). Argument-count validation stays at the stdlib boundary; this op
/// performs the proto-type validation and the `match target` dispatch verbatim,
/// including the non-object TypeError arm and the Reflect-specific "return false"
/// (rather than throw) on a non-extensible target.
pub fn object_set_prototype_of(
  interp : Interpreter,
  target : Value,
  proto : Value,
) -> Value raise Error {
  guard proto is (Object(_) | Proxy(_) | Null) else {
    raise @errors.TypeError(
      message="Object prototype may only be an Object or null",
    )
  }
  match target {
    Value::Proxy(proxy_data) =>
      Bool(proxy_set_prototype_of(interp, proxy_data, proto))
    Object(data) =>
      match module_namespace_set_prototype_result(data, proto) {
        Some(result) => Value::Bool(result)
        None => Value::Bool(ordinary_set_prototype(interp, data, proto))
      }
    Array(data) => {
      set_array_prototype_override(data, proto)
      Value::Bool(true)
    }
    _ =>
      raise @errors.TypeError(
        message="Reflect.setPrototypeOf called on non-object",
      )
  }
}

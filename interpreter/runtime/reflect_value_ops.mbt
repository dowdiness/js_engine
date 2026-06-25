///|
/// Reflect `[[Get]]` / `[[Set]]` value-path internal operations relocated from
/// `interpreter/stdlib/builtins_reflect.mbt` so that stdlib calls a runtime
/// operation instead of reaching into PropertyBag representation internals
/// (`bag.properties` / `bag.descriptors` / `bag.symbol_properties` /
/// `bag.symbol_descriptors`) for the receiver-aware get/set paths (architecture
/// redesign Stage 8, following #335 own-property-keys, #338 integrity, #339
/// keys/values/entries, #340 prototype ops, #341 Proxy revoke).
///
/// These reproduce the existing Reflect.get / Reflect.set behavior verbatim.
/// They are the VALUE path and are intentionally distinct from #340's
/// `prototype_ops.mbt` (the prototype path); do not unify them.
///
/// Preserved-as-is (NOT "fixed" here):
/// - `reflect_get_with_receiver` reimplements receiver-aware `[[Get]]` rather
///   than routing through `Interpreter::get_property`, because `get_property`
///   uses its `obj` argument as both lookup target and receiver and has no
///   receiver parameter — routing through it would silently drop Reflect.get's
///   custom (3rd-argument) receiver. Aligning this with the internal
///   receiver-preserving walk (`get_property_from_prototype`) is a separate
///   behavior-preserving refactor, not this move.
/// - `reflect_set_preflight_blocks` (removed in #342): the target-side
///   own-descriptor check (OrdinarySet §10.1.9.2 steps 1 / 3.a / 4) was
///   redundant — `set_property` already raises TypeError in strict mode for
///   getter-only and non-writable-data own descriptors, and Reflect.set
///   delegates with `strict=true` and catches TypeError → Bool(false).
///   The pre-flight was a no-op for non-Object targets (Array/Map/Set/Promise)
///   and equivalent to the existing TypeError path for Object targets.

///|
/// target receiver-aware `[[Get]]` backing for Reflect.get (§28.1.7). Argument
/// validation and the non-object TypeError check stay at the stdlib boundary;
/// this op performs the receiver-aware descriptor walk verbatim. The former
/// `try_get_with_receiver` closure's captures are threaded as parameters; its
/// body is unchanged.
pub fn reflect_get_with_receiver(
  interp : Interpreter,
  target : Value,
  key : Value,
  receiver : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let key_str = match key {
    Symbol(_) => ""
    _ => key.to_string()
  }
  // Find an own accessor getter and call it with `receiver`; otherwise fall
  // back to the own data slot. An own descriptor whose getter is None and a
  // missing descriptor both fall through to the stored property value.
  fn try_get_with_receiver(obj : Value) -> Value? raise {
    guard obj is Object(data) else { return None }
    match key {
      Value::Symbol(sym) =>
        match data.bag.symbol_descriptors.get(sym.id) {
          Some({ getter: Some(getter), .. }) =>
            Some(interp.call_value(getter, receiver, [], loc))
          _ => data.bag.symbol_properties.get(sym.id)
        }
      _ =>
        match data.bag.descriptors.get(key_str) {
          Some({ getter: Some(getter), .. }) =>
            Some(interp.call_value(getter, receiver, [], loc))
          _ => data.bag.properties.get(key_str)
        }
    }
  }

  // Check target first
  match try_get_with_receiver(target) {
    Some(v) => v
    None => {
      // Walk prototype chain
      let mut current = match target {
        Object(data) => data.prototype
        _ => Null
      }
      while current is Object(data) {
        match try_get_with_receiver(current) {
          Some(v) => return v
          None => current = data.prototype
        }
      }
      // Fall back to regular property access unconditionally.
      // Accessor getters with receiver were already handled in
      // try_get_with_receiver above; remaining cases are data reads
      // or absent properties, neither of which depends on receiver equality.
      match key {
        Symbol(_) => interp.get_computed_property(target, key, loc)
        _ => interp.get_property(target, key_str, loc)
      }
    }
  }
}
